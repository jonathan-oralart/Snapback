import AppKit
import SwiftUI

/// The full-screen window the overlay is drawn in.
final class OverlayPanel: NSPanel {
    init<Content: View>(screen: NSScreen, content: Content) {
        // Non-activating, like Spotlight: it takes typing straight away without a click to focus it.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        show(content)
        setFrame(screen.frame, display: true)
    }

    /// Replaces what the panel shows, e.g. when stepping to another capture in history.
    func show<Content: View>(_ content: Content) {
        let hosting = FirstMouseHostingView(rootView: content)
        hosting.safeAreaRegions = []
        contentView = hosting
        // A swapped-in view doesn't get the keyboard by itself; without this, keys just beep.
        makeFirstResponder(hosting)
    }

    /// Borderless panels can't take typing unless they say so.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The first click annotates instead of only focusing the overlay.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
