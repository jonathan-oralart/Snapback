import AppKit

enum Clipboard {
    /// Kept while the image is on the clipboard; it makes the TIFF only if an app pastes that.
    private static var tiffProvider: TIFFProvider?

    /// Puts the annotated image on the clipboard as PNG, plus TIFF for apps that only paste that.
    static func copy(png: Data) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        let provider = TIFFProvider(png: png)
        item.setDataProvider(provider, forTypes: [.tiff])
        tiffProvider = provider

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}

private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    let png: Data

    init(png: Data) {
        self.png = png
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            item.setData(tiff, forType: type)
        }
    }
}
