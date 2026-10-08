import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct SnapbackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Checks GitHub Releases for new versions. Off in debug builds, so a development build isn't replaced by a release.
    private let updater = SPUStandardUpdaterController(startingUpdater: !isDebugBuild, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        KeyboardShortcuts.onKeyDown(for: .capture) {
            CaptureCoordinator.shared.start()
        }
        KeyboardShortcuts.onKeyDown(for: .record) {
            CaptureCoordinator.shared.toggleRecording()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(updater: updater.updater)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        Settings {
            SettingsView()
        }
        Window("Snapback History", id: "history") {
            HistoryView()
        }
        .defaultSize(width: 760, height: 540)
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct MenuContent: View {
    let updater: SPUUpdater
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    private let store = CaptureStore.shared

    var body: some View {
        Button("Capture Front Window") {
            CaptureCoordinator.shared.start()
        }
        .globalKeyboardShortcut(.capture)
        Button(ScreenRecorder.shared.isRecording ? "Stop Recording" : "Record Screen") {
            CaptureCoordinator.shared.toggleRecording()
        }
        .globalKeyboardShortcut(.record)
        Menu("Recent") {
            ForEach(store.captures) { saved in
                Button {
                    CaptureCoordinator.shared.reopen(saved)
                } label: {
                    if let thumbnail = store.thumbnails[saved.id] {
                        Image(nsImage: menuIcon(thumbnail))
                    }
                    Text("\(saved.appName) — \(saved.displayDate)")
                }
            }
            if !store.captures.isEmpty { Divider() }
            Button("Show All…") {
                AppWindows.show(id: "history") { openWindow(id: "history") }
            }
        }
        Divider()
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(isDebugBuild)
        Button("Settings…") {
            // SwiftUI identifies its Settings window as "com_apple_SwiftUI_Settings_window".
            AppWindows.show(id: "Settings") { openSettings() }
        }
        .keyboardShortcut(",")
        Button("Quit Snapback") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Menu items draw images at their own size, so shrink the thumbnail to fit a menu row.
private func menuIcon(_ image: NSImage) -> NSImage {
    let height: CGFloat = 32
    let width = image.size.height > 0 ? min(image.size.width / image.size.height * height, 64) : height
    let icon = image.copy() as! NSImage
    icon.size = NSSize(width: width, height: height)
    return icon
}

#if DEBUG
private let isDebugBuild = true
#else
private let isDebugBuild = false
#endif
