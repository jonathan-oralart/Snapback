import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global hotkey: capture the front window and start annotating.
    static let capture = Self("capture", default: .init(.c, modifiers: [.control, .option, .command]))

    // While annotating. Changeable in Settings; only active while the overlay is open.
    static let send = Self("send", default: .init(.return, modifiers: .command))
    static let discard = Self("discard", default: .init(.delete, modifiers: .command))
}
