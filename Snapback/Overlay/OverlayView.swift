import KeyboardShortcuts
import SwiftUI

/// Full-screen overlay: the frozen window in place, markers on top, a note popup beside the marker
/// being edited, and a toolbar under the window.
struct OverlayView: View {
    @Bindable var session: AnnotationSession
    let onSend: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onDiscard: () -> Void
    /// Steps to an older (+1) or newer (−1) capture in history.
    let onNavigate: (Int) -> Void

    @State private var hoveredID: UUID?
    @State private var hoveredCorner: Marker.Corner?
    @State private var drag: DragMode?
    @State private var isBackdropShown: Bool
    @State private var popupSize = CGSize(width: NoteBubble.width, height: 44)
    @State private var toolbarSize = CGSize(width: 300, height: 52)
    /// The selected marker's popup is always shown; `.note` means its note is being typed into.
    /// Otherwise the canvas holds focus, so Delete removes the marker and Return edits its note.
    @FocusState private var focus: Focus?

    enum Focus: Hashable {
        case canvas
        case note
    }

    /// `animatesIn` fades the backdrop in when the overlay first opens, but not when stepping through history.
    init(session: AnnotationSession, animatesIn: Bool, onSend: @escaping () -> Void, onCopy: @escaping () -> Void, onSave: @escaping () -> Void,
         onDiscard: @escaping () -> Void, onNavigate: @escaping (Int) -> Void) {
        self.session = session
        self.onSend = onSend
        self.onCopy = onCopy
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onNavigate = onNavigate
        _isBackdropShown = State(initialValue: !animatesIn)
    }

    private enum DragMode {
        case undecided
        case drawing
        case moving(UUID, original: Marker.Shape, before: [Marker])
        case resizing(UUID, Marker.Corner, original: CGRect, before: [Marker])
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The desktop blurs and dims behind the screenshot, so it's clear you're annotating a capture.
            ZStack {
                DesktopBlur()
                Color.black.opacity(0.3)
            }
            .opacity(isBackdropShown ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: 0.25)) { isBackdropShown = true } }
            .contentShape(Rectangle())
            .onTapGesture(perform: finish)

            canvas
                .offset(x: imageRect.minX, y: imageRect.minY)

            if let id = session.selectedID, let index = session.markers.firstIndex(where: { $0.id == id }) {
                let placement = placement(for: session.markers[index].shape, size: popupSize)
                NoteEditor(note: $session.markers[index].note, focus: $focus)
                    .noteBubble(edge: placement.edge, tailOffset: placement.tailOffset)
                    .id(id)
                    .onGeometryChange(for: CGSize.self, of: \.size) { popupSize = $0 }
                    .offset(placement.offset)
            }

            OverlayToolbar(hasMarkers: !session.markers.isEmpty, style: $session.style, history: historyPosition,
                           onNavigate: onNavigate, onCopy: onCopy, onSend: onSend)
                .onGeometryChange(for: CGSize.self, of: \.size) { toolbarSize = $0 }
                .offset(toolbarOffset)
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .ignoresSafeArea()
        #if DEBUG
        .onChange(of: imageRect, initial: true) {
            DemoTake.shown = .init(rect: imageRect, zoom: zoom, screen: session.capture.screen.frame)
        }
        #endif
        .background {
            // Invisible buttons for keys whose meaning depends on whether a note is being typed in.
            Group {
                Button("", action: escape).keyboardShortcut(.cancelAction)
                Button("", action: { undo(redo: false) }).keyboardShortcut("z")
                Button("", action: { undo(redo: true) }).keyboardShortcut("z", modifiers: [.command, .shift])
                Button("", action: discardKey).globalKeyboardShortcut(.discard)
                Button("", action: { if !session.markers.isEmpty { onSend() } }).globalKeyboardShortcut(.send)
                Button("", action: copyKey).keyboardShortcut("c")
                Button("", action: { if historyPosition.hasOlder { onNavigate(1) } }).keyboardShortcut("[")
                Button("", action: { if historyPosition.hasNewer { onNavigate(-1) } }).keyboardShortcut("]")
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .canvas)
        .onAppear {
            // Take the keyboard as soon as the view is in the window, so Delete, Return and arrows work straight away.
            DispatchQueue.main.async { if focus == nil { focus = .canvas } }
        }
        .onKeyPress { press in
            // Backspace arrives as U+007F, which doesn't match SwiftUI's `.delete` (U+0008).
            let isDelete = press.key == .delete || press.key == .deleteForward || press.characters == "\u{7F}"
            guard isDelete, focus != .note, let id = session.selectedID else { return .ignored }
            session.remove(id)
            focus = .canvas
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=-_")) { press in
            guard focus != .note else { return .ignored }
            session.style = session.style.resized(by: "+=".contains(press.characters) ? 1 : -1)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            // ← older, → newer, matching the toolbar's arrows. Arrows move the cursor while typing.
            guard focus != .note else { return .ignored }
            let step = press.key == .leftArrow ? 1 : -1
            guard step == 1 ? historyPosition.hasOlder : historyPosition.hasNewer else { return .handled }
            onNavigate(step)
            return .handled
        }
        .onKeyPress(.return) {
            guard focus != .note, session.selectedID != nil else { return .ignored }
            focus = .note
            return .handled
        }
    }

    private var canvas: some View {
        let markers = session.markers
        let selectedID = session.selectedID
        let hovered = drag == nil ? hoveredID : nil
        let draft = session.draft
        let style = session.style
        let bounds = session.bounds
        let size = session.capture.frame.size

        return ZStack {
            Image(decorative: session.capture.image, scale: session.capture.pixelScale)
                .resizable()
                .interpolation(.high)
            Canvas { context, _ in
                context.withCGContext { cg in
                    style.paint(markers, within: bounds, selectedID: selectedID, hoveredID: hovered, draft: draft, scale: 1, in: cg)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(markerGesture)
        .onContinuousHover { phase in
            if case .active(let location) = phase {
                hoveredCorner = session.resizeHandle(at: location)?.1
                hoveredID = session.marker(at: location)
            } else {
                hoveredCorner = nil
                hoveredID = nil
            }
        }
        .pointerStyle(pointerStyle)
        // Scaled after the gesture and hover, so they still report window points.
        .scaleEffect(zoom, anchor: .topLeading)
        .frame(width: size.width * zoom, height: size.height * zoom, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    // MARK: Selection and editing

    /// Selects a marker without typing into its note, or clears the selection.
    private func select(_ id: UUID?) {
        session.selectedID = id
        focus = .canvas
    }

    /// ⌘Z and ⇧⌘Z undo typing inside a note, otherwise marker changes. The overlay has no Edit
    /// menu, so the note's own undo is reached by sending the action to it directly.
    private func undo(redo: Bool) {
        if focus == .note {
            NSApp.sendAction(Selector(redo ? "redo:" : "undo:"), to: nil, from: nil)
        } else if redo {
            session.redo()
        } else {
            session.undo()
        }
    }

    /// Esc stops typing, then clears the selection, then closes.
    private func escape() {
        if focus == .note {
            focus = .canvas
        } else if session.selectedID != nil {
            select(nil)
        } else {
            finish()
        }
    }

    /// Closes, saving if there are markers, so closing never loses work.
    private func finish() {
        if session.markers.isEmpty {
            onDiscard()
        } else {
            onSave()
        }
    }

    /// ⌘C copies the selected text while typing a note; otherwise it copies the annotated image.
    private func copyKey() {
        if focus == .note {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        } else {
            onCopy()
        }
    }

    private func discardKey() {
        // ⌘⌫ deletes to the start of the line while typing; it only discards outside a note.
        if focus == .note, KeyboardShortcuts.getShortcut(for: .discard) == .init(.delete, modifiers: .command) {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
        } else {
            onDiscard()
        }
    }

    // MARK: Pointer

    /// Open hand over a marker that can be moved, closed while moving it, crosshair for adding.
    private var pointerStyle: PointerStyle {
        switch drag {
        case .moving: return .grabActive
        case .resizing(_, let corner, _, _): return Self.resizePointer(corner)
        default: break
        }
        if let hoveredCorner { return Self.resizePointer(hoveredCorner) }
        return hoveredID != nil ? .grabIdle : .rectSelection
    }

    private static func resizePointer(_ corner: Marker.Corner) -> PointerStyle {
        switch corner {
        case .topRight: .frameResize(position: .topTrailing)
        case .bottomLeft: .frameResize(position: .bottomLeading)
        case .bottomRight: .frameResize(position: .bottomTrailing)
        }
    }

    private var markerGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    if let (id, corner, rect) = session.resizeHandle(at: value.startLocation) {
                        drag = .resizing(id, corner, original: rect, before: session.markers)
                    } else if let id = session.marker(at: value.startLocation),
                       let marker = session.markers.first(where: { $0.id == id }) {
                        drag = .moving(id, original: marker.shape, before: session.markers)
                        select(id)
                    } else {
                        drag = .undecided
                    }
                }
                let distance = hypot(value.translation.width, value.translation.height)
                switch drag {
                case .moving(let id, let original, _):
                    if let index = session.markers.firstIndex(where: { $0.id == id }) {
                        session.markers[index].shape = original.offset(by: value.translation, within: session.bounds)
                    }
                case .resizing(let id, let corner, let original, _):
                    // The opposite corner stays put; the box never gets smaller than 8pt.
                    let anchor = corner.anchor(of: original)
                    let dragged = CGPoint(x: corner.point(of: original).x + value.translation.width,
                                          y: corner.point(of: original).y + value.translation.height).clamped(to: session.bounds)
                    let x = anchor.x < dragged.x ? anchor.x : min(dragged.x, anchor.x - 8)
                    let y = anchor.y < dragged.y ? anchor.y : min(dragged.y, anchor.y - 8)
                    let rect = CGRect(x: x, y: y,
                                      width: max(abs(dragged.x - anchor.x), 8), height: max(abs(dragged.y - anchor.y), 8))
                    if let index = session.markers.firstIndex(where: { $0.id == id }) {
                        session.markers[index].shape = .box(rect)
                    }
                case .undecided where distance > 4, .drawing:
                    drag = .drawing
                    session.draft = rect(from: value.startLocation, to: value.location)
                default:
                    break
                }
            }
            .onEnded { value in
                switch drag {
                case .moving(_, _, let before), .resizing(_, _, _, let before):
                    if hypot(value.translation.width, value.translation.height) >= 3 {
                        session.recordUndo(before)
                    }
                case .drawing:
                    let box = rect(from: value.startLocation, to: value.location)
                    session.draft = nil
                    create(box.width >= 8 && box.height >= 8 ? .box(box) : .pin(value.startLocation))
                case .undecided:
                    // With a marker selected, a click elsewhere just deselects it.
                    if session.selectedID != nil {
                        select(nil)
                    } else {
                        create(.pin(value.startLocation))
                    }
                case nil:
                    break
                }
                drag = nil
            }
    }

    /// A new marker opens its note ready for typing.
    private func create(_ shape: Marker.Shape) {
        session.add(shape)
        // The popup's field appears in this update; focus it once it's in the window.
        DispatchQueue.main.async { focus = .note }
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let clamped = end.clamped(to: session.bounds)
        return CGRect(
            x: min(start.x, clamped.x), y: min(start.y, clamped.y),
            width: abs(clamped.x - start.x), height: abs(clamped.y - start.y)
        )
    }

    /// Where this capture sits in Recent, for the toolbar's arrows.
    private var historyPosition: HistoryPosition {
        let captures = CaptureStore.shared.captures
        return HistoryPosition(index: session.savedID.flatMap { id in captures.firstIndex { $0.id == id } }, count: captures.count)
    }

    // MARK: Placement

    private static let margin: CGFloat = 32
    private static let toolbarGap: CGFloat = 16

    /// The screenshot is shown a little smaller than the real window, so it reads as a capture
    /// rather than the live app, and smaller still if it's needed to fit the toolbar underneath.
    private var zoom: CGFloat {
        let window = session.capture.frame.size
        let height = screenSize.height - Self.margin * 2 - Self.toolbarGap - toolbarSize.height
        let width = screenSize.width - Self.margin * 2
        return min(0.9, height / window.height, width / window.width)
    }

    /// Where the screenshot sits within the overlay, top-left origin: centred on the screen
    /// together with the toolbar below it.
    private var imageRect: CGRect {
        let window = session.capture.frame.size
        let size = CGSize(width: window.width * zoom, height: window.height * zoom)
        let groupHeight = size.height + Self.toolbarGap + toolbarSize.height
        return CGRect(x: (screenSize.width - size.width) / 2, y: (screenSize.height - groupHeight) / 2, width: size.width, height: size.height)
    }

    /// A point in window points, as shown in the overlay.
    private func onScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + point.x * zoom, y: imageRect.minY + point.y * zoom)
    }

    private var screenSize: CGSize { session.capture.screen.frame.size }

    /// Pins: to the right of the number, or the left if there's no room. Boxes: below, or above.
    /// The bubble's tail points back at the marker.
    private func placement(for shape: Marker.Shape, size: CGSize) -> (offset: CGSize, edge: Edge, tailOffset: CGFloat) {
        let screen = CGRect(origin: .zero, size: screenSize).insetBy(dx: 8, dy: 8)
        let clampX = { (x: CGFloat) in min(max(x, screen.minX), screen.maxX - size.width) }
        let clampY = { (y: CGFloat) in min(max(y, screen.minY), screen.maxY - size.height) }
        switch shape {
        case .pin(let point):
            let center = onScreen(point)
            let reach = session.style.pinRadius * zoom + 4
            let fitsRight = center.x + reach + size.width <= screen.maxX
            let x = fitsRight ? center.x + reach : center.x - reach - size.width
            let y = clampY(center.y - size.height / 2)
            return (CGSize(width: x, height: y), fitsRight ? .leading : .trailing, center.y - y)
        case .box(let rect):
            let origin = onScreen(rect.origin)
            let box = CGRect(x: origin.x, y: origin.y, width: rect.width * zoom, height: rect.height * zoom)
            let anchorX = box.minX + min(box.width / 2, 40)
            let fitsBelow = box.maxY + 4 + size.height <= screen.maxY
            let y = fitsBelow ? box.maxY + 4 : box.minY - 4 - size.height
            let x = clampX(anchorX - 28)
            return (CGSize(width: x, height: y), fitsBelow ? .top : .bottom, anchorX - x)
        }
    }

    /// Centred just below the screenshot.
    private var toolbarOffset: CGSize {
        CGSize(width: (screenSize.width - toolbarSize.width) / 2, height: imageRect.maxY + Self.toolbarGap)
    }
}

/// Blurs whatever is behind the overlay window.
private struct DesktopBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
