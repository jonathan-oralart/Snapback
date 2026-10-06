import AppKit

/// The annotated screenshot: the window with markers, and the numbered notes in a card underneath.
/// Everything travels in the one image, so it works wherever an image can be pasted.
enum FeedbackImage {
    /// Like a macOS window screenshot: the window floats on transparent padding with a soft shadow.
    /// The notes sit in a white card underneath, so they stay readable on any background.
    static func png(for session: AnnotationSession) -> Data {
        let capture = session.capture
        let style = session.style
        // Legend badges keep the full size so their numbers stay readable next to the notes.
        let legendStyle = MarkerStyle(tint: style.tint)
        let scale = capture.pixelScale
        let windowWidth = CGFloat(capture.image.width)
        let windowHeight = CGFloat(capture.image.height)

        let margin = 48 * scale
        let cardGap = 20 * scale
        let padding = 16 * scale
        let badgeSize = legendStyle.pinRadius * 2 * scale
        let noteX = padding + badgeSize + 10 * scale
        let rowSpacing = 10 * scale

        let explanation = "\(style.tint.name) numbered pins and boxes are feedback markers, not part of the app."
        let header = NSAttributedString(string: explanation, attributes: [
            .font: NSFont.systemFont(ofSize: 13 * scale, weight: .medium),
            .foregroundColor: NSColor(white: 0.4, alpha: 1),
        ])
        let notes = session.markers.map { marker in
            let text = marker.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return NSAttributedString(string: text.isEmpty ? "(no note)" : text, attributes: [
                .font: NSFont.systemFont(ofSize: 15 * scale),
                .foregroundColor: NSColor(white: 0.1, alpha: 1),
            ])
        }

        let headerHeight = height(of: header, width: windowWidth - padding * 2)
        let noteHeights = notes.map { max(height(of: $0, width: windowWidth - noteX - padding), badgeSize) }
        let cardHeight = (padding + headerHeight + 14 * scale
            + noteHeights.reduce(0, +) + rowSpacing * CGFloat(max(notes.count - 1, 0)) + padding).rounded(.up)

        let pixelWidth = Int(windowWidth + margin * 2)
        let pixelHeight = Int((margin + windowHeight + cardGap + cardHeight + margin).rounded(.up))
        let total = CGFloat(pixelHeight)

        guard let cg = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }

        // Window and card with shadows, in Core Graphics' native bottom-left space.
        let windowRect = CGRect(x: margin, y: total - margin - windowHeight, width: windowWidth, height: windowHeight)
        let cardRect = CGRect(x: margin, y: windowRect.minY - cardGap - cardHeight, width: windowWidth, height: cardHeight)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 36 * scale, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        cg.draw(capture.image, in: windowRect)
        cg.setShadow(offset: CGSize(width: 0, height: -4 * scale), blur: 16 * scale, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        cg.addPath(CGPath(roundedRect: cardRect, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil))
        cg.setFillColor(NSColor.white.cgColor)
        cg.fillPath()
        cg.restoreGState()

        // Markers and notes top-left-origin, like the overlay.
        cg.translateBy(x: 0, y: total)
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: margin, y: margin)
        style.paint(session.markers, within: session.bounds, selectedID: nil, draft: nil, scale: scale, in: cg)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        var y = windowHeight + cardGap + padding
        header.draw(with: CGRect(x: padding, y: y, width: windowWidth - padding * 2, height: headerHeight), options: drawingOptions)
        y += headerHeight + 14 * scale

        for (index, note) in notes.enumerated() {
            let lineHeight = (note.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { NSLayoutManager().defaultLineHeight(for: $0) } ?? badgeSize
            legendStyle.paintBadge(index + 1, at: CGPoint(x: padding + badgeSize / 2, y: y + max(lineHeight, badgeSize) / 2), scale: scale, selected: false)
            let textY = y + max(0, (badgeSize - lineHeight) / 2)
            note.draw(with: CGRect(x: noteX, y: textY, width: windowWidth - noteX - padding, height: noteHeights[index]), options: drawingOptions)
            y += noteHeights[index] + rowSpacing
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let image = cg.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }

    private static let drawingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    private static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: drawingOptions).height.rounded(.up)
    }
}
