import AppKit
import ApplicationServices
import PermissionFlow
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
        case .screenRecording: "Captures the front window, and records the screen."
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

    /// The System Settings list PermissionFlow opens, with a panel to drag Snapback into it.
    var flowPane: PermissionFlowPane {
        switch self {
        case .screenRecording: .screenRecording
        case .accessibility: .accessibility
        }
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
    /// Opens the right System Settings list beside a small panel you drag Snapback from into the list.
    @StateObject private var flow = PermissionFlow.makeController()

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
                            let mouse = NSEvent.mouseLocation
                            flow.authorize(
                                pane: permission.flowPane,
                                suggestedAppURLs: [Bundle.main.bundleURL],
                                sourceFrameInScreen: CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
                            )
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
                Button("Done") {
                    flow.closePanel()
                    PermissionsWindow.close()
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(granted.values.contains(false))
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            // System Settings doesn't notify apps, so check once a second while the window is open.
            while !Task.isCancelled {
                let wasGranted = granted
                granted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, $0.isGranted) })
                // Put the drag panel away once the permission it was helping with comes through.
                if granted.contains(where: { $0.value && wasGranted[$0.key] == false }) {
                    flow.closePanel()
                }
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
