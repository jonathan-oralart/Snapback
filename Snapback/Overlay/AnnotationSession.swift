import CoreGraphics
import Foundation
import Observation

/// The markers on one capture while it's being annotated, with selection and undo.
@Observable
final class AnnotationSession {
    let capture: CapturedWindow
    var markers: [Marker] = [] {
        didSet { hasChanges = true }
    }
    var selectedID: UUID?
    /// Box being dragged out, before it becomes a marker.
    var draft: CGRect?
    /// Set once the capture is saved, or when it was reopened from history.
    var savedID: UUID?
    /// Colour and size of every marker on this capture; also becomes the default for the next one.
    var style: MarkerStyle {
        didSet {
            MarkerStyle.lastUsed = style
            hasChanges = true
        }
    }
    /// Whether markers or style changed since this capture was opened, so unchanged ones aren't re-saved.
    private(set) var hasChanges = false

    /// Earlier and undone marker lists, for ⌘Z and ⇧⌘Z.
    private var undoStack: [[Marker]] = []
    private var redoStack: [[Marker]] = []

    init(capture: CapturedWindow, markers: [Marker] = [], savedID: UUID? = nil, style: MarkerStyle = .lastUsed) {
        self.capture = capture
        self.markers = markers
        self.savedID = savedID
        self.style = style
    }

    var bounds: CGRect { CGRect(origin: .zero, size: capture.frame.size) }

    /// The marker under a point: pins and box badges first, since they're drawn on top,
    /// then the box (anywhere inside it or on its edge) that was added last.
    func marker(at point: CGPoint) -> UUID? {
        let reach = style.pinRadius + 3
        for marker in markers.reversed() {
            let badge = style.badgeCenter(of: marker.shape, within: bounds)
            if hypot(point.x - badge.x, point.y - badge.y) <= reach { return marker.id }
        }
        for marker in markers.reversed() {
            if case .box(let rect) = marker.shape, rect.insetBy(dx: -6, dy: -6).contains(point) { return marker.id }
        }
        return nil
    }

    /// A resize handle of the selected box under a point.
    func resizeHandle(at point: CGPoint) -> (UUID, Marker.Corner, CGRect)? {
        guard let selectedID, let marker = markers.first(where: { $0.id == selectedID }), case .box(let rect) = marker.shape else { return nil }
        for corner in Marker.Corner.allCases {
            let handle = corner.point(of: rect)
            if hypot(point.x - handle.x, point.y - handle.y) <= 9 { return (selectedID, corner, rect) }
        }
        return nil
    }

    @discardableResult
    func add(_ shape: Marker.Shape) -> UUID {
        recordUndo(markers)
        let marker = Marker(shape: shape)
        markers.append(marker)
        selectedID = marker.id
        return marker.id
    }

    func remove(_ id: UUID) {
        recordUndo(markers)
        markers.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    /// Saves the markers as they were before a change.
    func recordUndo(_ snapshot: [Marker]) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(markers)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(markers)
        restore(next)
    }

    private func restore(_ snapshot: [Marker]) {
        markers = snapshot
        if let selectedID, !markers.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }
}
