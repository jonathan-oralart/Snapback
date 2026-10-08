#if DEBUG
import AppKit
import KeyboardShortcuts

/// Debug builds only: plays a scripted take for recording the README demo (`scripts/record-demo.sh`).
/// It first lays out Claude and the demo page side by side; then the take, a capture.json, has its markers added to a
/// capture of the page with real pointer and key events, as if typed by hand, and it's sent to a new Claude Code
/// session in the demo's folder and submitted.
enum DemoTake {
    static let notification = Notification.Name("com.oralart.snapback.dev.take")
    private static let claudeBundleID = "com.anthropic.claudefordesktop"

    /// Where the overlay shows the screenshot, set by `OverlayView`, so window points can be found on screen.
    struct Shown {
        var rect: CGRect
        var zoom: CGFloat
        var screen: CGRect
    }

    static var shown: Shown?
    /// The folder the next Claude Code session opens in, read by `ClaudeCodeSender`.
    private(set) static var folder: URL?

    private struct Take: Decodable {
        let markers: [Marker]
    }

    /// What the script asks for, from the notification's user info.
    private struct Request {
        /// Claude goes in the left half, the page in the right; global points, top-left origin.
        var layout: CGRect
        var browser: String
        /// The page's title, to find its window.
        var title: String
        /// Without a take, it only lays out the windows.
        var take: URL?
        var folder: URL
        var prompt: String
        /// A file each step's time is appended to, for cutting the recording.
        var times: URL
    }

    static func listen() {
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            guard let info = note.userInfo as? [String: String],
                  let layout = info["layout"]?.split(separator: ",").compactMap({ Double($0) }), layout.count == 4,
                  let browser = info["browser"], let title = info["title"], let take = info["take"],
                  let folder = info["folder"], let prompt = info["prompt"], let times = info["times"] else { return }
            let request = Request(layout: CGRect(x: layout[0], y: layout[1], width: layout[2], height: layout[3]),
                                  browser: browser, title: title, take: take.isEmpty ? nil : URL(filePath: take),
                                  folder: URL(filePath: folder), prompt: prompt, times: URL(filePath: times))
            Task { @MainActor in await play(request) }
        }
    }

    private static func play(_ request: Request) async {
        let times = request.times
        try? Data().write(to: times)
        log("received", to: times)
        guard arrange(request) else {
            log("failed couldn't find the Claude window, or a \(request.browser) window titled \"\(request.title)\"", to: times)
            return
        }
        log("arranged", to: times)
        guard let url = request.take else { return }
        guard let data = try? Data(contentsOf: url), let take = try? JSONDecoder().decode(Take.self, from: data) else {
            log("failed couldn't read the take", to: times)
            return
        }
        let folder = request.folder
        let prompt = request.prompt
        // Let the windows settle before the capture.
        try? await Task.sleep(for: .seconds(0.6))
        log("start", to: times)

        shown = nil
        CaptureCoordinator.shared.start()
        for _ in 0..<50 where shown == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard shown != nil else {
            log("failed the overlay didn't open", to: times)
            return
        }
        // Let the overlay finish fading in.
        try? await Task.sleep(for: .seconds(0.8))

        for (index, marker) in take.markers.enumerated() {
            switch marker.shape {
            case .pin(let point):
                await move(to: point)
                await click(at: point)
            case .box(let rect):
                await move(to: rect.origin)
                await drag(from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            try? await Task.sleep(for: .seconds(0.35))
            await type(marker.note)
            try? await Task.sleep(for: .seconds(0.5))
            // Esc leaves the note; a second Esc clears the selection so the next click adds a marker.
            press(53)
            if index < take.markers.count - 1 {
                try? await Task.sleep(for: .seconds(0.15))
                press(53)
            }
            try? await Task.sleep(for: .seconds(0.4))
        }

        self.folder = folder
        defer { self.folder = nil }
        if let send = KeyboardShortcuts.getShortcut(for: .send) {
            press(CGKeyCode(send.carbonKeyCode), flags: cgFlags(send.modifiers))
        }
        log("sent", to: times)

        // Wait for the paste: Claude in front, its composer up, the image attached.
        for _ in 0..<50 where !isClaudeInFront {
            try? await Task.sleep(for: .milliseconds(200))
        }
        try? await Task.sleep(for: .seconds(2.5))
        // Never type the prompt into whichever other app is in front.
        guard isClaudeInFront else {
            log("failed Claude didn't come to the front", to: times)
            return
        }
        await type(prompt)
        try? await Task.sleep(for: .seconds(0.4))
        press(36)
        log("submitted", to: times)
    }

    private static var isClaudeInFront: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID
    }

    // MARK: Windows

    /// Puts Claude in the left half of the layout and the page in the right, and brings the page to the front,
    /// since the capture is of the front window. Done with Accessibility, which Snapback has for pasting.
    private static func arrange(_ request: Request) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        guard let browser = apps.first(where: { $0.localizedName == request.browser }),
              let claude = apps.first(where: { $0.bundleIdentifier == claudeBundleID }),
              let page = windows(of: browser).first(where: { title(of: $0).contains(request.title) }),
              let claudeWindow = mainWindow(of: claude) else { return false }
        let layout = request.layout
        let half = layout.width / 2
        place(claudeWindow, in: CGRect(x: layout.minX, y: layout.minY, width: half, height: layout.height))
        place(page, in: CGRect(x: layout.minX + half, y: layout.minY, width: half, height: layout.height))
        AXUIElementPerformAction(page, kAXRaiseAction as CFString)
        browser.activate()
        return true
    }

    private static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    /// Claude has other, hidden windows; this is the one in use.
    private static func mainWindow(of app: NSRunningApplication) -> AXUIElement? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXMainWindowAttribute as CFString, &value)
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func title(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    private static func place(_ window: AXUIElement, in frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        if let position = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let size = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        }
    }

    // MARK: Input

    /// A point in window points, in global display coordinates (top-left origin) as the overlay shows it.
    private static func onScreen(_ point: CGPoint) -> CGPoint {
        guard let shown else { return point }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: shown.screen.minX + shown.rect.minX + point.x * shown.zoom,
                       y: primaryHeight - shown.screen.maxY + shown.rect.minY + point.y * shown.zoom)
    }

    /// Glides the pointer there, easing in and out, like a hand on a trackpad.
    private static func move(to point: CGPoint) async {
        let start = CGEvent(source: nil)?.location ?? .zero
        let end = onScreen(point)
        let steps = 30
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let location = CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
            post(.mouseMoved, at: location)
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private static func click(at point: CGPoint) async {
        post(.leftMouseDown, at: onScreen(point))
        try? await Task.sleep(for: .milliseconds(70))
        post(.leftMouseUp, at: onScreen(point))
    }

    private static func drag(from start: CGPoint, to end: CGPoint) async {
        post(.leftMouseDown, at: onScreen(start))
        let steps = 36
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = 1 - pow(1 - t, 3)
            post(.leftMouseDragged, at: onScreen(CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)))
            try? await Task.sleep(for: .milliseconds(16))
        }
        post(.leftMouseUp, at: onScreen(end))
    }

    private static func post(_ type: CGEventType, at location: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Types one character at a time, at a quick but human pace.
    private static func type(_ text: String) async {
        for character in text {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event?.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 40...90)))
        }
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func cgFlags(_ modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    private static func log(_ step: String, to times: URL) {
        guard let handle = try? FileHandle(forWritingTo: times) else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(step) \(Date().timeIntervalSince1970)\n".utf8))
        try? handle.close()
    }
}
#endif
