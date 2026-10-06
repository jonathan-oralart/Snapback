import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture front window", name: .capture)
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
            }

            Section {
                KeyboardShortcuts.Recorder("Send to Claude", name: .send)
                FixedShortcut("Copy image", keys: "⌘C")
                KeyboardShortcuts.Recorder("Close without saving", name: .discard)
                FixedShortcut("Marker size", keys: "−  +")
                FixedShortcut("Delete selected marker", keys: "⌫")
                FixedShortcut("Edit selected note", keys: "↩")
                FixedShortcut("Undo / Redo", keys: "⌘Z  ⇧⌘Z")
                FixedShortcut("Older / Newer capture", keys: "← →  or  ⌘[ ⌘]")
                FixedShortcut("Leave note, deselect, close and save", keys: "esc")
            } header: {
                Text("While annotating")
            } footer: {
                Text("Clicking outside the screenshot also closes and saves.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
