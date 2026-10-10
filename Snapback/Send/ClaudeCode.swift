import AppKit
import ApplicationServices

enum ClaudeCode {
    private static let claudeBundleID = "com.anthropic.claudefordesktop"

    /// Brings Claude's window to the front as it is, launching Claude if it isn't running, and puts the cursor in
    /// the chat's message box so ⌘V pastes there.
    static func activate() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        Task { await focusMessageBox() }
    }

    private static func focusMessageBox() async {
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first {
                let application = AXUIElementCreateApplication(app.processIdentifier)
                // Claude is an Electron app: its web content only appears to Accessibility once asked for.
                AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                if let box = messageBox(in: application) {
                    AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// The message box is the last text area in the window, after the conversation, so it's searched from the end.
    private static func messageBox(in application: AXUIElement) -> AXUIElement? {
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return value
        }
        guard let window = value(application, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var visited = 0
        func search(_ element: AXUIElement) -> AXUIElement? {
            visited += 1
            guard visited < 5000 else { return nil }
            if value(element, kAXRoleAttribute) as? String == kAXTextAreaRole { return element }
            for child in (value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed() {
                if let found = search(child) { return found }
            }
            return nil
        }
        return search(window as! AXUIElement)
    }
}
