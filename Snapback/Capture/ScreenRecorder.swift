import AppKit
import ScreenCaptureKit

/// A finished screen recording, before any frames are picked from it.
struct ScreenRecording {
    let url: URL
    /// The recorded display in global points, top-left origin.
    let frame: CGRect
    let screen: NSScreen
    /// The front window when recording started, in display points: where the crop starts.
    let windowRect: CGRect?
    let appName: String
    let windowTitle: String?
    /// Where and when the mouse was clicked, drawn onto the frames later.
    var clicks: [Click] = []
}

struct NotRecording: Error {}

/// Records the front window's display to a temporary movie, with the pointer and without Snapback's own windows,
/// so the stop pill never shows up in it. Clicks are logged rather than recorded, to be drawn onto the frames picked.
@Observable
final class ScreenRecorder {
    static let shared = ScreenRecorder()
    /// Longest recording; it stops by itself after this.
    static let limit: Duration = .seconds(60)

    /// True from the moment recording is asked for until it's stopped.
    private(set) var isRecording = false
    @ObservationIgnored private var active: Active?

    /// Whether capture has actually begun, so there's something to stop.
    var hasStarted: Bool { active != nil }

    private struct Active {
        let stream: SCStream
        let output: SCRecordingOutput
        let delegate: RecordingDelegate
        let recording: ScreenRecording
        let clickMonitor: Any?
    }

    /// Clicks so far, timed by system uptime until recording stops, in display points.
    @ObservationIgnored private var clicks: [Click] = []
    /// The click each held mouse button made, by button number, until it's let go.
    @ObservationIgnored private var pressed: [Int: Int] = [:]

    /// `beforeCapture` is called with the display's screen just before recording begins, and returns the window
    /// it showed there (the stop pill), which is waited for so Snapback can be left out of the recording.
    func start(beforeCapture: (NSScreen) -> CGWindowID) async throws {
        guard !isRecording else { return }
        isRecording = true
        do {
            try await begin(beforeCapture: beforeCapture)
        } catch {
            isRecording = false
            throw error
        }
    }

    /// Stops and waits for the movie file to be finished.
    func stop() async throws -> ScreenRecording {
        guard let active else { throw NotRecording() }
        self.active = nil
        isRecording = false
        if let monitor = active.clickMonitor { NSEvent.removeMonitor(monitor) }
        try await active.stream.stopCapture()
        try await active.delegate.finished()
        var recording = active.recording
        // The movie starts at 0 when the recording output starts.
        if let start = active.delegate.startUptime {
            recording.clicks = clicks.compactMap { click in
                var click = click
                click.time -= start
                click.release?.time -= start
                return click.time >= 0 ? click : nil
            }
        }
        clicks = []
        pressed = [:]
        return recording
    }

    private func begin(beforeCapture: (NSScreen) -> CGWindowID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let front = WindowCapture.frontWindow(in: content)
        // The front window's display, or the one under the pointer when there's no window.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        let center = front.map { CGPoint(x: $0.0.frame.midX, y: $0.0.frame.midY) } ?? CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
            throw NoFrontWindow()
        }

        let screen = screen(of: display)
        let ownWindow = beforeCapture(screen)
        // Snapback is only listed while it has a window on screen, and a new window takes a moment to be listed.
        var ownApp: [SCRunningApplication] = []
        for _ in 0..<40 {
            let latest = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            if latest.windows.contains(where: { $0.windowID == ownWindow }) {
                ownApp = latest.applications.filter { $0.processID == getpid() }
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.captureResolution = .best

        let url = FileManager.default.temporaryDirectory.appending(path: "Snapback-\(UUID().uuidString).mov")
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mov
        outputConfig.videoCodecType = .hevc
        let delegate = RecordingDelegate()
        let output = SCRecordingOutput(configuration: outputConfig, delegate: delegate)
        let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
        try stream.addRecordingOutput(output)

        let windowRect = front.map { window, _ in
            window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                .intersection(CGRect(origin: .zero, size: display.frame.size))
        }
        let recording = ScreenRecording(
            url: url,
            frame: display.frame,
            screen: screen,
            windowRect: windowRect.flatMap { $0.isEmpty ? nil : $0 },
            appName: front?.1.localizedName ?? "Screen",
            windowTitle: front.flatMap { $0.0.title?.isEmpty == false ? $0.0.title : nil }
        )
        clicks = []
        pressed = [:]
        // Clicks on Snapback's own windows, like the stop pill, aren't seen here.
        let displayFrame = display.frame
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        let clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.log(event, primaryHeight: primaryHeight, displayFrame: displayFrame)
        }
        try await stream.startCapture()
        active = Active(stream: stream, output: output, delegate: delegate, recording: recording, clickMonitor: clickMonitor)
    }

    /// Adds a press to the clicks, or the release to the press it ends.
    private func log(_ event: NSEvent, primaryHeight: CGFloat, displayFrame: CGRect) {
        // Screen coordinates, bottom-left origin, since a global event has no window.
        let location = event.locationInWindow
        let x = location.x - displayFrame.minX, y = primaryHeight - location.y - displayFrame.minY
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard CGRect(origin: .zero, size: displayFrame.size).contains(CGPoint(x: x, y: y)) else { return }
            let button: Click.Button = switch event.type {
            case .leftMouseDown: event.modifierFlags.contains(.control) ? .right : .left
            case .rightMouseDown: .right
            default: .other
            }
            pressed[event.buttonNumber] = clicks.count
            clicks.append(Click(time: event.timestamp, x: x, y: y, button: button))
        default:
            guard let index = pressed.removeValue(forKey: event.buttonNumber) else { return }
            clicks[index].release = Click.Release(time: event.timestamp, x: x, y: y)
        }
    }

    private func screen(of display: SCDisplay) -> NSScreen {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        } ?? WindowCapture.screen(containing: display.frame)
    }
}

/// Hears when the movie file is complete. ScreenCaptureKit calls it on its own queue.
nonisolated private final class RecordingDelegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    private var started: TimeInterval?

    /// The system uptime when the movie's first frame was taken, the same clock as event timestamps.
    var startUptime: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        started = now
        lock.unlock()
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(.success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(error))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(.failure(error))
    }

    /// Waits until the file is finished, or returns straight away if it already is.
    func finished() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    private func finish(_ outcome: Result<Void, Error>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(with: outcome)
    }
}
