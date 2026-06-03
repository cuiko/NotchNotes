//
//  NativeTextView+ImageDeleteButton.swift
//  MarkdownEngine
//
//  Hovering a rendered image embed (`![[...]]`) shows a small trash button at
//  the image's top-right corner. Clicking it removes the embed text from the
//  document — the stored image asset is left untouched.
//

import AppKit

private let imageEmbedRegex = try! NSRegularExpression(pattern: #"!\[\[[^\]]*\]\]"#)

/// Trash button overlaid on a hovered image. Carries its own pointing-hand
/// cursor since the enclosing text view otherwise re-asserts the I-beam.
final class ImageDeleteButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

extension NativeTextView {

    /// Re-evaluated on every `mouseMoved`: show the trash button over the
    /// rendered image under the pointer, or hide it.
    func updateImageDeleteButton(for event: NSEvent) {
        guard let hit = imageEmbedHit(at: event) else {
            hideImageDeleteButton()
            return
        }

        imageDeleteEmbedRange = hit.embedRange
        let button = imageDeleteButton ?? makeImageDeleteButton()
        if button.superview !== self { addSubview(button) }

        let size: CGFloat = 22
        let inset: CGFloat = 6
        button.frame = CGRect(
            x: hit.imageRect.maxX - size - inset,
            y: hit.imageRect.minY + inset,
            width: size,
            height: size
        )
        button.isHidden = false
    }

    func hideImageDeleteButton() {
        imageDeleteButton?.isHidden = true
        imageDeleteEmbedRange = nil
    }

    /// Finds a rendered image whose on-screen rect contains the pointer and
    /// returns that rect plus the full `![[...]]` text range. Iterates the
    /// `.latexImage` runs and uses `.latexBounds` for the exact image rect so
    /// the whole image is hoverable (not just the glyph's mid-point) and the
    /// button lands on the real top-right corner. Works in both states: the
    /// collapsed embed centers the image in its line; while editing, the source
    /// line stays and the image is drawn below it by `.latexBlockOffsetY`.
    private func imageEmbedHit(at event: NSEvent) -> (imageRect: CGRect, embedRange: NSRange)? {
        guard let textContainer,
              let bridge = layoutBridge,
              let storage = textStorage, storage.length > 0 else { return nil }

        let localPoint = convert(event.locationInWindow, from: nil)
        let fullRange = NSRange(location: 0, length: storage.length)
        var result: (CGRect, NSRange)?

        storage.enumerateAttribute(.latexImage, in: fullRange, options: []) { value, range, stop in
            guard value != nil,
                  let boundsValue = storage.attribute(.latexBounds, at: range.location, effectiveRange: nil) as? NSValue
            else { return }

            let imageBounds = boundsValue.rectValue
            let lineRect = bridge.boundingRect(forCharacterRange: range, in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard lineRect.width > 0, lineRect.height > 0 else { return }

            let blockOffsetY = storage.attribute(.latexBlockOffsetY, at: range.location, effectiveRange: nil) as? CGFloat
            let imageY = blockOffsetY.map { lineRect.minY + $0 }
                ?? (lineRect.minY + (lineRect.height - imageBounds.height) / 2)
            let imageRect = CGRect(
                x: lineRect.minX,
                y: imageY,
                width: imageBounds.width,
                height: imageBounds.height
            )
            if imageRect.contains(localPoint),
               let embedRange = enclosingImageEmbedRange(at: range.location, in: storage.string as NSString) {
                result = (imageRect, embedRange)
                stop.pointee = true
            }
        }
        return result
    }

    /// True while the pointer is over the visible trash button, so the text
    /// view can keep the pointing-hand cursor instead of reasserting the I-beam.
    func isPointOverImageDeleteButton(_ event: NSEvent) -> Bool {
        guard let button = imageDeleteButton, !button.isHidden else { return false }
        return button.frame.contains(convert(event.locationInWindow, from: nil))
    }

    private func enclosingImageEmbedRange(at index: Int, in text: NSString) -> NSRange? {
        let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
        var found: NSRange?
        imageEmbedRegex.enumerateMatches(in: text as String, range: paragraph) { match, _, stop in
            guard let match else { return }
            if NSLocationInRange(index, match.range) || index == NSMaxRange(match.range) {
                found = match.range
                stop.pointee = true
            }
        }
        return found
    }

    private func makeImageDeleteButton() -> NSButton {
        let button = ImageDeleteButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""
        button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete image")
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 5
        button.target = self
        button.action = #selector(deleteHoveredImageEmbed)
        imageDeleteButton = button
        return button
    }

    @objc private func deleteHoveredImageEmbed() {
        guard let storage = textStorage, let embedRange = imageDeleteEmbedRange else { return }
        let nsText = storage.string as NSString
        guard NSMaxRange(embedRange) <= nsText.length else { hideImageDeleteButton(); return }

        // Drop the whole line when the embed is the only thing on it, so no
        // blank paragraph is left behind; otherwise remove just the embed text.
        let paragraph = nsText.paragraphRange(for: embedRange)
        let paragraphText = nsText.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
        let embedText = nsText.substring(with: embedRange)
        let deleteRange = (paragraphText == embedText) ? paragraph : embedRange

        guard shouldChangeText(in: deleteRange, replacementString: "") else { return }
        storage.replaceCharacters(in: deleteRange, with: "")
        didChangeText()
        hideImageDeleteButton()

        if let coord = delegate as? NativeTextViewCoordinator {
            let safeLocation = min(deleteRange.location, (storage.string as NSString).length)
            let para = (storage.string as NSString).paragraphRange(for: NSRange(location: safeLocation, length: 0))
            coord.restyleParagraphs([para], in: self)
        }
    }
}
