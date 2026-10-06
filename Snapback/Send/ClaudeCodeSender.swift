import AppKit
import ApplicationServices

/// Opens a new Claude Code session, then pastes the annotated screenshot into it.
enum ClaudeCodeSender {
    private static let claudeBundleID = "com.anthropic.claudefordesktop"
    /// Time for the new session's composer to appear and take focus once Claude is in front.
    private static let pasteDelay = Duration.seconds(1)

    static func send(_ png: Data) async {
        putImageOnPasteboard(png)

        // Bring Claude to the front with the new session, rather than leaving the previous app focused.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open(URL(string: "claude://code/new")!, configuration: configuration)

        guard await waitForClaudeInFront() else {
            notify("Claude didn't come to the front. The screenshot is on the clipboard — paste it with ⌘V.")
            return
        }
        try? await Task.sleep(for: pasteDelay)

        guard AXIsProcessTrusted() else {
            notify("Snapback needs Accessibility access to paste. The screenshot is on the clipboard — paste it with ⌘V.")
            return
        }
        pressCommandV()
    }

    private static func putImageOnPasteboard(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    private static func waitForClaudeInFront() async -> Bool {
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func notify(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't paste the screenshot"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
