import AppKit

enum Clipboard {
    /// Puts the annotated image on the clipboard as PNG, plus TIFF for apps that only paste that.
    static func copy(png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
