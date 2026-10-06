import AppKit
import Observation

/// A sent capture on disk: the original window screenshot plus its markers, so it can be reopened and changed.
struct SavedCapture: Identifiable, Codable {
    let id: UUID
    var date: Date
    let appName: String
    let windowTitle: String?
    /// Where the window was on screen, top-left origin.
    let frame: CGRect
    var markers: [Marker]
    /// Missing from captures saved before marker styles existed.
    var style: MarkerStyle?

    var displayDate: String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Keeps the most recent sent captures in Application Support, one folder each:
/// `window.png` (unannotated), `capture.json` (markers and notes), `thumbnail.png` (the sent image, small).
@Observable
final class CaptureStore {
    static let shared = CaptureStore()
    static let limit = 20

    private(set) var captures: [SavedCapture] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    /// Decoded screenshots of the capture being shown and its neighbours, so stepping through
    /// history doesn't wait on PNG decoding.
    @ObservationIgnored private var decodedImages: [UUID: CGImage] = [:]

    private let root: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appending(path: "Snapback/Captures", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    /// Saves a capture as it's sent. Reopened captures update their existing entry.
    func save(_ session: AnnotationSession, png: Data) {
        let id = session.savedID ?? UUID()
        session.savedID = id
        let capture = session.capture
        let saved = SavedCapture(
            id: id,
            // Re-saving keeps the original date, so history order doesn't shift while browsing it.
            date: captures.first { $0.id == id }?.date ?? .now,
            appName: capture.appName,
            windowTitle: capture.windowTitle,
            frame: capture.frame,
            markers: session.markers,
            style: session.style
        )

        let directory = folder(of: id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let windowFile = directory.appending(path: "window.png")
        if !FileManager.default.fileExists(atPath: windowFile.path()) {
            try? Self.png(capture.image)?.write(to: windowFile)
        }
        let thumbnail = Self.thumbnail(fromPNG: png)
        if let thumbnail {
            try? Self.png(thumbnail)?.write(to: directory.appending(path: "thumbnail.png"))
        }
        try? JSONEncoder().encode(saved).write(to: directory.appending(path: "capture.json"))

        // Update the list in memory rather than re-reading every capture from disk.
        if let index = captures.firstIndex(where: { $0.id == id }) {
            captures[index] = saved
        } else {
            captures.insert(saved, at: 0)
        }
        thumbnails[id] = thumbnail.map { NSImage(cgImage: $0, size: .zero) }
        for old in captures.dropFirst(Self.limit) {
            delete(old.id)
        }
    }

    /// The saved capture ready to annotate again, placed where the window was if that's still on screen, otherwise centred.
    func restore(_ saved: SavedCapture) -> AnnotationSession? {
        guard let image = decodedImages[saved.id] ?? Self.decode(windowFile(of: saved.id)),
              let screen = NSScreen.main
        else { return nil }
        decodedImages[saved.id] = image

        let visible = screen.topLeftFrame
        var frame = saved.frame
        if !visible.contains(frame) {
            frame.origin = CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        }
        let capture = CapturedWindow(image: image, frame: frame, screen: screen, appName: saved.appName, windowTitle: saved.windowTitle)
        return AnnotationSession(capture: capture, markers: saved.markers, savedID: saved.id, style: saved.style ?? .lastUsed)
    }

    /// Decodes the screenshots either side of `id` (or the newest, for an unsaved capture) in the
    /// background, and forgets ones further away.
    func prefetchNeighbours(of id: UUID?) {
        let index = id.flatMap { id in captures.firstIndex { $0.id == id } } ?? -1
        let nearby = [index - 1, index, index + 1].filter(captures.indices.contains).map { captures[$0].id }
        decodedImages = decodedImages.filter { nearby.contains($0.key) }
        for neighbour in nearby where decodedImages[neighbour] == nil {
            let url = windowFile(of: neighbour)
            Task.detached(priority: .userInitiated) {
                let image = Self.decode(url)
                await MainActor.run { self.decodedImages[neighbour] = image }
            }
        }
    }

    /// Decodes the whole image now, so drawing it later doesn't stall.
    nonisolated private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private func windowFile(of id: UUID) -> URL {
        folder(of: id).appending(path: "window.png")
    }

    func folder(of id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(of: id))
        captures.removeAll { $0.id == id }
        thumbnails[id] = nil
        decodedImages[id] = nil
    }

    private func load() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        captures = folders
            .compactMap { folder in
                (try? Data(contentsOf: folder.appending(path: "capture.json")))
                    .flatMap { try? JSONDecoder().decode(SavedCapture.self, from: $0) }
            }
            .sorted { $0.date > $1.date }
        thumbnails = Dictionary(uniqueKeysWithValues: captures.compactMap { saved in
            NSImage(contentsOf: folder(of: saved.id).appending(path: "thumbnail.png")).map { (saved.id, $0) }
        })
    }

    private static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The sent image scaled to 480 pixels wide.
    private static func thumbnail(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
