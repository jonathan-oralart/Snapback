import AppKit
import ApplicationServices

/// Opens a new Claude Code session, then pastes the annotated screenshot into it.
enum ClaudeCodeSender {
    private static let claudeBundleID = "com.anthropic.claudefordesktop"
    /// Time for the new session's composer to appear and take focus once Claude is in front.
    private static let pasteDelay = Duration.seconds(1)

    static func send(_ png: Data) async {
        Clipboard.copy(png: png)

        // Bring Claude to the front with the new session, rather than leaving the previous app focused.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let url = URL(string: "claude://code/new")!
        _ = try? await NSWorkspace.shared.open(url, configuration: configuration)

        guard await waitForClaudeInFront() else {
            notify("Claude didn't come to the front. The screenshot is on the clipboard — paste it with ⌘V.")
            return
        }
        try? await Task.sleep(for: pasteDelay)

        guard AXIsProcessTrusted() else {
            notify("Snapback needs Accessibility access to paste. The screenshot is on the clipboard — paste it with ⌘V.")
            return
        }
        guard pasteImage() else {
            notify("Couldn't choose Paste in Claude. The screenshot is on the clipboard.")
            return
        }
        SendSound.current.play()
    }

    private static func waitForClaudeInFront() async -> Bool {
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Invoke Claude's Paste menu item once instead of synthesizing keyboard events.
    private static func pasteImage() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first else { return false }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &menuBar) == .success,
              let menuBar, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { return false }

        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            return value as? [AXUIElement] ?? []
        }
        for entry in children(menuBar as! AXUIElement) {
            for menu in children(entry) {
                for item in children(menu) {
                    var key: CFTypeRef?
                    var modifiers: CFTypeRef?
                    AXUIElementCopyAttributeValue(item, kAXMenuItemCmdCharAttribute as CFString, &key)
                    AXUIElementCopyAttributeValue(item, kAXMenuItemCmdModifiersAttribute as CFString, &modifiers)
                    guard (key as? String)?.lowercased() == "v", (modifiers as? NSNumber)?.intValue == 0 else { continue }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    private static func notify(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't paste the screenshot"
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
