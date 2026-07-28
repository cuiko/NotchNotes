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

/// Edit button overlaid on a hovered image — reveals the embed's `![[...]]`
/// source for editing. Same cursor handling as ``ImageDeleteButton``.
final class ImageEditButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

/// Zoom button overlaid on a hovered image — opens a full-screen preview.
/// Same cursor handling as ``ImageDeleteButton``.
final class ImageZoomButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

extension NativeTextView {

    /// Re-evaluated on every `mouseMoved`: show the edit + trash buttons over the
    /// rendered image under the pointer, or hide them.
    func updateImageDeleteButton(for event: NSEvent) {
        guard let hit = imageEmbedHit(at: event) else {
            hideImageDeleteButton()
            return
        }

        imageDeleteEmbedRange = hit.embedRange

        let size: CGFloat = 22
        let inset: CGFloat = 6
        let gap: CGFloat = 6

        // Delete button is intentionally not shown for now (kept in code); only
        // the edit + zoom buttons occupy the image's top-right corner.
        let editButton = imageEditButton ?? makeImageEditButton()
        if editButton.superview !== self { addSubview(editButton) }
        editButton.frame = CGRect(
            x: hit.imageRect.maxX - size - inset,
            y: hit.imageRect.minY + inset,
            width: size,
            height: size
        )
        editButton.isHidden = false

        let zoomButton = imageZoomButton ?? makeImageZoomButton()
        if zoomButton.superview !== self { addSubview(zoomButton) }
        zoomButton.frame = CGRect(
            x: hit.imageRect.maxX - size * 2 - inset - gap,
            y: hit.imageRect.minY + inset,
            width: size,
            height: size
        )
        zoomButton.isHidden = false
    }

    func hideImageDeleteButton() {
        imageDeleteButton?.isHidden = true
        imageEditButton?.isHidden = true
        imageZoomButton?.isHidden = true
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

    /// True while the pointer is over the visible edit button (same cursor role).
    func isPointOverImageEditButton(_ event: NSEvent) -> Bool {
        guard let button = imageEditButton, !button.isHidden else { return false }
        return button.frame.contains(convert(event.locationInWindow, from: nil))
    }

    /// True while the pointer is over the visible zoom button (same cursor role).
    func isPointOverImageZoomButton(_ event: NSEvent) -> Bool {
        guard let button = imageZoomButton, !button.isHidden else { return false }
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

    private func makeImageEditButton() -> NSButton {
        let button = ImageEditButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""
        button.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Edit image source")
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 5
        button.toolTip = "Edit this block"
        button.target = self
        button.action = #selector(editHoveredImageEmbed)
        imageEditButton = button
        return button
    }

    private func makeImageZoomButton() -> NSButton {
        let button = ImageZoomButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""
        button.image = Self.cornerBracketsImage(side: 13, lineWidth: 1.6, cornerLength: 3, inset: 1)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        button.layer?.cornerRadius = 5
        button.toolTip = "Zoom"
        button.target = self
        button.action = #selector(zoomHoveredImageEmbed)
        imageZoomButton = button
        return button
    }

    /// A "fullscreen" glyph drawn as four right-angle corner brackets. Template
    /// image so the button's `contentTintColor` colors it.
    private static func cornerBracketsImage(side: CGFloat, lineWidth: CGFloat, cornerLength: CGFloat, inset: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let lo = inset
            let hi = side - inset
            let len = cornerLength

            // Bottom-left
            path.move(to: NSPoint(x: lo, y: lo + len))
            path.line(to: NSPoint(x: lo, y: lo))
            path.line(to: NSPoint(x: lo + len, y: lo))
            // Bottom-right
            path.move(to: NSPoint(x: hi - len, y: lo))
            path.line(to: NSPoint(x: hi, y: lo))
            path.line(to: NSPoint(x: hi, y: lo + len))
            // Top-right
            path.move(to: NSPoint(x: hi, y: hi - len))
            path.line(to: NSPoint(x: hi, y: hi))
            path.line(to: NSPoint(x: hi - len, y: hi))
            // Top-left
            path.move(to: NSPoint(x: lo + len, y: hi))
            path.line(to: NSPoint(x: lo, y: hi))
            path.line(to: NSPoint(x: lo, y: hi - len))

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Opens the hovered embed's image in a full-screen preview.
    @objc private func zoomHoveredImageEmbed() {
        guard let storage = textStorage, let embedRange = imageDeleteEmbedRange else { return }
        let nsText = storage.string as NSString
        guard NSMaxRange(embedRange) <= nsText.length else { hideImageDeleteButton(); return }

        let embedText = nsText.substring(with: embedRange)
        guard let reference = ImageEmbedReference.parse(markdown: embedText),
              let image = EmbeddedImageCache.shared.image(for: reference, services: configuration.services) else {
            return
        }

        ImageLightbox.present(image, on: window?.screen)
    }

    /// Reveals the hovered embed's `![[...]]` source and selects it, so the user
    /// can edit the reference. Selecting the range activates the token, which the
    /// styler renders as visible source instead of the collapsed image.
    @objc private func editHoveredImageEmbed() {
        guard let storage = textStorage, let embedRange = imageDeleteEmbedRange else { return }
        let nsText = storage.string as NSString
        guard NSMaxRange(embedRange) <= nsText.length else { hideImageDeleteButton(); return }

        window?.makeFirstResponder(self)
        setSelectedRange(embedRange)
        hideImageDeleteButton()

        if let coord = delegate as? NativeTextViewCoordinator {
            let para = nsText.paragraphRange(for: embedRange)
            coord.restyleParagraphs([para], in: self)
        }
        scrollRangeToVisible(embedRange)
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
