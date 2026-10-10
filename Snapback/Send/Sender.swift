import AppKit
import ApplicationServices

/// Opens a new chat in the app chosen in Settings, then pastes the annotated screenshot into it.
enum Sender {
    /// Time for the new chat's composer to appear and take focus once the app is in front.
    private static let pasteDelay = Duration.seconds(1)

    static func send(_ png: Data) async {
        let target = SendTarget.current
        Clipboard.copy(png: png)

        // Bring the app to the front with the new chat, rather than leaving the previous app focused.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open(target.newChatURL, configuration: configuration)

        guard await waitForFront(target) else {
            notify("\(target.title) didn't come to the front. The screenshot is on the clipboard — paste it with ⌘V.")
            return
        }
        try? await Task.sleep(for: pasteDelay)

        guard AXIsProcessTrusted() else {
            notify("Snapback needs Accessibility access to paste. The screenshot is on the clipboard — paste it with ⌘V.")
            return
        }
        guard pasteImage(into: target) else {
            notify("Couldn't choose Paste in \(target.title). The screenshot is on the clipboard.")
            return
        }
        SendSound.current.play()
    }

    private static func waitForFront(_ target: SendTarget) async -> Bool {
        for _ in 0..<50 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleID { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Invoke the app's Paste menu item once instead of synthesizing keyboard events.
    private static func pasteImage(into target: SendTarget) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else { return false }
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
