import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppWindows.watchForLastWindowClosing()
        PermissionsWindow.showIfNeeded()
    }
}
