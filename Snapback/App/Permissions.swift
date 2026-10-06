import AppKit
import ApplicationServices
import SwiftUI

/// What Snapback needs from macOS: capture to see the window, Accessibility to paste into Claude.
enum Permission: CaseIterable, Identifiable {
    case screenRecording
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }

    var purpose: String {
        switch self {
        case .screenRecording: "Captures the front window."
        case .accessibility: "Pastes the screenshot into Claude."
        }
    }

    var isGranted: Bool {
        switch self {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .accessibility: AXIsProcessTrusted()
        }
    }

    static var allGranted: Bool { allCases.allSatisfy(\.isGranted) }

    /// Asks macOS for the permission, landing in the right System Settings list.
    func request() {
        switch self {
        case .screenRecording:
            // The first request shows macOS's own dialog, which has its own "Open System Settings" button;
            // opening Settings as well would leave that dialog asking again afterwards. macOS only shows it
            // once, so later requests go straight to Settings.
            let key = "requestedScreenRecording"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                CGRequestScreenCaptureAccess()
                return
            }
            openSettings("Privacy_ScreenCapture")
        case .accessibility:
            // Adds Snapback to the list without macOS's prompt, then opens the list.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
            openSettings("Privacy_Accessibility")
        }
    }

    private func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

enum PermissionsWindow {
    private static var window: NSWindow?

    static func showIfNeeded() {
        guard !Permission.allGranted else { return }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PermissionsView()))
            window.title = "Snapback Permissions"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let window { AppWindows.show(window) }
    }

    static func close() {
        window?.close()
    }
}

private struct PermissionsView: View {
    @State private var granted: [Permission: Bool] = [:]
    @State private var requestedScreenRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Permission.allCases) { permission in
                HStack(spacing: 12) {
                    Image(systemName: granted[permission] == true ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(granted[permission] == true ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title).font(.headline)
                        Text(permission.purpose).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if granted[permission] != true {
                        Button("Open Settings") {
                            if permission == .screenRecording { requestedScreenRecording = true }
                            permission.request()
                        }
                    }
                }
            }

            if requestedScreenRecording && granted[.screenRecording] != true {
                HStack {
                    Text("Screen Recording applies after a relaunch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Relaunch", action: relaunch)
                }
            }

            HStack {
                Spacer()
                Button("Done") { PermissionsWindow.close() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(granted.values.contains(false))
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            // System Settings doesn't notify apps, so check once a second while the window is open.
            while !Task.isCancelled {
                granted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, $0.isGranted) })
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
