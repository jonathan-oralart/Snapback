import AppKit
import ScreenCaptureKit

/// A frozen picture of one window and where it sat on screen.
struct CapturedWindow {
    let image: CGImage
    /// Window frame in global screen points, top-left origin (Core Graphics space).
    let frame: CGRect
    let screen: NSScreen
    let appName: String
    let windowTitle: String?

    /// Image pixels per window point.
    var pixelScale: CGFloat { CGFloat(image.width) / frame.width }
}

struct NoFrontWindow: Error {}

enum WindowCapture {
    /// Captures the front window of the frontmost app, without its shadow or the cursor.
    static func captureFrontWindow() async throws -> CapturedWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let (window, app) = frontWindow(in: content) else { throw NoFrontWindow() }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return CapturedWindow(
            image: image,
            frame: window.frame,
            screen: screen(containing: window.frame),
            appName: app.localizedName ?? window.owningApplication?.applicationName ?? "App",
            windowTitle: window.title?.isEmpty == false ? window.title : nil
        )
    }

    /// The frontmost app's front window, as ScreenCaptureKit sees it.
    static func frontWindow(in content: SCShareableContent) -> (SCWindow, NSRunningApplication)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let windowID = frontWindowID(of: app.processIdentifier),
              let window = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }
        return (window, app)
    }

    /// The app's frontmost normal window, from the window server's front-to-back list.
    private static func frontWindowID(of pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 40, rect.height > 40,
                  let id = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            return id
        }
        return nil
    }

    static func screen(containing frame: CGRect) -> NSScreen {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.topLeftFrame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

extension NSScreen {
    /// The screen's frame in top-left-origin global points, matching window frames from the window server.
    var topLeftFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
