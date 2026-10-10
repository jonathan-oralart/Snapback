import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(SendSound.defaultsKey) private var sendSound = SendSound.button
    @AppStorage(SendTarget.defaultsKey) private var sendTarget = SendTarget.claude
    #if DEBUG
    @AppStorage(FeedbackImage.TextSize.defaultsKey) private var annotationTextSize = FeedbackImage.TextSize.standard
    #endif

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture front window", name: .capture, onChange: KeyboardShortcuts.Name.capture.takeShortcut)
                KeyboardShortcuts.Recorder("Record screen", name: .record, onChange: KeyboardShortcuts.Name.record.takeShortcut)
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Show what actually happened, e.g. if macOS refused.
                            opensAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker("Copy & Open", selection: $sendTarget) {
                    ForEach(SendTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                Picker("Sound when copied", selection: $sendSound) {
                    ForEach(SendSound.allCases) { sound in
                        Text(sound.title).tag(sound)
                    }
                }
                .onChange(of: sendSound) { _, sound in sound.play() }
            }

            #if DEBUG
            Section {
                Picker("Annotation text size", selection: $annotationTextSize) {
                    ForEach(FeedbackImage.TextSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
            } header: {
                Text("Exported image (dev build)")
            } footer: {
                Text("Controls the numbered notes below the screenshot when you copy an image.")
            }
            #endif

            Section {
                KeyboardShortcuts.Recorder("Copy and open \(sendTarget.title)", name: .send, onChange: KeyboardShortcuts.Name.send.takeShortcut)
                KeyboardShortcuts.Recorder("Copy image", name: .copy, onChange: KeyboardShortcuts.Name.copy.takeShortcut)
                KeyboardShortcuts.Recorder("Close without saving", name: .discard, onChange: KeyboardShortcuts.Name.discard.takeShortcut)
                FixedShortcut("Marker size", keys: "−  +")
                FixedShortcut("Delete selected marker", keys: "⌫")
                FixedShortcut("Edit selected note, or copy image", keys: "↩")
                FixedShortcut("Undo / Redo", keys: "⌘Z  ⇧⌘Z")
                FixedShortcut("Older / Newer capture", keys: ",  .")
                FixedShortcut("Leave note, deselect, close and save", keys: "esc")
            } header: {
                Text("While annotating")
            } footer: {
                Text("Clicking outside the screenshot also closes and saves.")
            }

            Section {
                FixedShortcut("Previous / Next frame", keys: "← →")
                FixedShortcut("Add or remove this frame", keys: "space")
                FixedShortcut("Previous / Next kept frame", keys: "↑ ↓")
            } header: {
                Text("While picking frames from a recording")
            } footer: {
                Text("Up to \(AnnotationSession.maxFrames) frames can be kept. Adding a marker keeps its frame. Recordings stop after a minute.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: min(720, (NSScreen.main?.visibleFrame.height ?? 760) - 40))
    }
}

/// A shortcut that can't be changed, listed so it can be discovered.
private struct FixedShortcut: View {
    let title: String
    let keys: String

    init(_ title: String, keys: String) {
        self.title = title
        self.keys = keys
    }

    var body: some View {
        LabeledContent(title) {
            Text(keys)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

/// One settings window, shared by the menu and reopening the app from Finder.
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            AppWindows.show(window)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Snapback Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        AppWindows.show(window)
    }
}
