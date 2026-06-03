//
//  MarkdownTextLayoutFragment.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 12.04.26.
//
//  TextKit 2 replacement for CodeBlockLayoutManager.
//  Draws code-block backgrounds, LaTeX images, and task checkboxes
//  via NSTextLayoutFragment instead of NSLayoutManager glyph overrides.

import AppKit

// MARK: - Custom attribute keys for rendering overlays

extension NSAttributedString.Key {
    static let latexImage = NSAttributedString.Key("LatexRenderedImage")
    static let latexBounds = NSAttributedString.Key("LatexImageBounds")
    static let latexIsBlock = NSAttributedString.Key("LatexIsBlock")
    static let latexBlockOffsetY = NSAttributedString.Key("LatexBlockOffsetY")
    static let blockquoteAccent = NSAttributedString.Key("BlockquoteAccentColor")
    static let horizontalRule = NSAttributedString.Key("HorizontalRuleColor")
}

final class MarkdownTextLayoutFragment: NSTextLayoutFragment {

    /// Inner padding above/below the text inside a blockquote callout box.
    static let blockquoteInternalPad: CGFloat = 5

    /// Filled padding between a code block's content and the box edge. The code
    /// paragraph's outer spacing carries this plus the (unfilled) outer margin;
    /// only the margin is kept out of the fill.
    static let codeBlockInnerPad: CGFloat = 6

    // MARK: - FB15131180

    /// Maps to TextKit-2's private `extraLineFragmentAttributes` selector so we can pin the trailing extra-line metrics to body font; otherwise a trailing heading paragraph inflates `usageBoundsForTextContainer` by ~30pt when the caret enters it. Pattern from STTextView.
    @objc(extraLineFragmentAttributes)
    dynamic var stExtraLineFragmentAttributes: NSDictionary?

    // MARK: - Rendering surface

    /// Extend rendering bounds for code-block backgrounds (full container width)
    /// and block images drawn below text via paragraphSpacing.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds
        if hasCodeBlockBackground || hasBlockquote || hasHorizontalRule {
            let containerWidth = textLayoutManager?.textContainer?.size.width ?? bounds.width
            // Extend left to container edge
            bounds.origin.x = -layoutFragmentFrame.origin.x
            bounds.size.width = containerWidth
        }
        if hasBlockquote {
            // The callout box pads above the first text line. TextKit gives the
            // document's first paragraph no paragraphSpacingBefore, so that
            // padding lands above the fragment's natural surface and would be
            // clipped (the first quote then looks shorter than later ones).
            // Extend the surface up/down by the inner pad so every box draws
            // its full height regardless of position.
            bounds.origin.y -= Self.blockquoteInternalPad
            bounds.size.height += Self.blockquoteInternalPad * 2
        }
        // Extend bounds to cover block images that render below the text line
        // (visibleSource mode uses paragraphSpacing to create space for the image).
        for rect in blockImageRects(at: .zero) {
            bounds = bounds.union(rect)
        }
        return bounds
    }

    // MARK: - Drawing

    override func draw(at point: CGPoint, in context: CGContext) {
        // 1. Code-block backgrounds (behind text)
        drawCodeBlockBackground(at: point, in: context)

        // 1b. Blockquote callout background + left bar (behind text)
        drawBlockquote(at: point, in: context)

        // 1c. Horizontal rule (drawn line in place of the hidden dashes)
        drawHorizontalRule(at: point, in: context)

        // 2. LaTeX images (behind text — hidden markers are invisible anyway)
        drawLatexImages(at: point, in: context)

        // 3. Normal text
        super.draw(at: point, in: context)

        // 4. Task checkboxes (on top of hidden [ ]/[x] markers)
        drawTaskCheckboxes(at: point, in: context)
    }

    // MARK: - Helpers

    /// NSRange in the document for this fragment's content.
    private var fragmentNSRange: NSRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage else { return nil }
        let start = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.location)
        let end = tcs.offset(from: tcs.documentRange.location, to: rangeInElement.endLocation)
        guard start != NSNotFound, end != NSNotFound, end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private var textStorage: NSTextStorage? {
        (textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage
    }

    /// Returns the drawing position for a character at `docIndex` (document-level NSRange location).
    /// `point` is the draw origin passed to `draw(at:in:)`.
    private func drawPosition(forDocumentCharAt docIndex: Int, point: CGPoint) -> (x: CGFloat, baselineY: CGFloat, lineHeight: CGFloat)? {
        guard let fragRange = fragmentNSRange else { return nil }
        let localIndex = docIndex - fragRange.location
        guard localIndex >= 0 else { return nil }

        // NSTextLineFragment.typographicBounds.origin.y is already relative to the
        // parent layout fragment, so we use it directly — accumulating per-line
        // heights would double-count the inter-line offset on wrapped lines.
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let charPos = lineFragment.locationForCharacter(at: localIndex)
                let tb = lineFragment.typographicBounds
                return (
                    x: point.x + tb.origin.x + charPos.x,
                    baselineY: point.y + tb.origin.y + charPos.y,
                    lineHeight: tb.height
                )
            }
        }
        return nil
    }

    /// Typographic bounds of the line fragment containing `localIndex`
    /// (index relative to the fragment, not the document).
    private func lineBounds(forLocalIndex localIndex: Int, point: CGPoint) -> CGRect? {
        for lineFragment in textLineFragments {
            let lr = lineFragment.characterRange
            if localIndex >= lr.location && localIndex < lr.location + lr.length {
                let tb = lineFragment.typographicBounds
                return CGRect(x: point.x + lineFragment.glyphOrigin.x + tb.origin.x,
                              y: point.y + tb.origin.y,
                              width: tb.width,
                              height: tb.height)
            }
        }
        return nil
    }

    // MARK: - Code Block Background

    private var hasCodeBlockBackground: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        let bgColor = ts.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
        guard let bgColor else { return false }
        return isCodeBlockBackgroundColor(bgColor)
    }

    private func drawCodeBlockBackground(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        // Only fenced code-block fragments get the full-width fill (first char must carry the code background).
        guard let color = ts.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor,
              isCodeBlockBackgroundColor(color) else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width

        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1,
           let lastLF = textLineFragments.last,
           lastLF.characterRange.length == 0 {
            effectiveHeight -= lastLF.typographicBounds.height
        }

        // Keep the outer paragraph spacing (the block's top/bottom margin) out of
        // the fill so it reads as a gap to neighboring content. Interior code
        // lines carry no spacing, so their fragments still abut into one box.
        let prevIsCode = range.location > 0
            && (ts.attribute(.backgroundColor, at: range.location - 1, effectiveRange: nil) as? NSColor)
                .map { isCodeBlockBackgroundColor($0) } ?? false
        let nextIsCode = NSMaxRange(range) < ts.length
            && (ts.attribute(.backgroundColor, at: NSMaxRange(range), effectiveRange: nil) as? NSColor)
                .map { isCodeBlockBackgroundColor($0) } ?? false
        let paragraph = ts.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let topInset = prevIsCode ? 0 : max(0, (paragraph?.paragraphSpacingBefore ?? 0) - Self.codeBlockInnerPad)
        let bottomInset = nextIsCode ? 0 : max(0, (paragraph?.paragraphSpacing ?? 0) - Self.codeBlockInnerPad)

        let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let rawY = point.y + topInset
        let rawMaxY = point.y + effectiveHeight - bottomInset
        let snappedY = floor(rawY * scale) / scale
        let snappedMaxY = ceil(rawMaxY * scale) / scale
        // A collapsed fence line is shorter than the outer margin; skip it so
        // the margin reads as an empty gap instead of a sliver of fill.
        guard snappedMaxY > snappedY else { return }

        // Draw full-width background, clipping out any active selection rects
        // so the system's blue selection highlight remains visible inside code blocks.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let bgRect = CGRect(
            x: point.x - layoutFragmentFrame.origin.x,
            y: snappedY,
            width: containerWidth,
            height: snappedMaxY - snappedY
        )

        let selectionRects = selectionRectsInDrawCoordinates(drawPoint: point, snappedY: snappedY, snappedMaxY: snappedMaxY)
        color.setFill()
        if selectionRects.isEmpty {
            NSBezierPath(rect: bgRect).fill()
        } else {
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.appendRect(bgRect)
            for r in selectionRects {
                path.appendRect(r.intersection(bgRect))
            }
            path.fill()
        }
    }

    /// Returns active text-selection rectangles intersecting this fragment, in
    /// the same draw-relative coordinate system used by `drawCodeBlockBackground`.
    private func selectionRectsInDrawCoordinates(drawPoint: CGPoint, snappedY: CGFloat, snappedMaxY: CGFloat) -> [CGRect] {
        guard let tlm = textLayoutManager else { return [] }
        var rects: [CGRect] = []

        let dx = drawPoint.x - layoutFragmentFrame.origin.x
        let myRange = self.rangeInElement

        for selection in tlm.textSelections {
            for textRange in selection.textRanges {
                let interStart = textRange.location.compare(myRange.location) == .orderedAscending
                    ? myRange.location : textRange.location
                let interEnd = textRange.endLocation.compare(myRange.endLocation) == .orderedDescending
                    ? myRange.endLocation : textRange.endLocation
                guard interStart.compare(interEnd) == .orderedAscending,
                      let intersection = NSTextRange(location: interStart, end: interEnd) else { continue }

                tlm.enumerateTextSegments(in: intersection, type: .selection, options: []) { _, segFrame, _, _ in
                    // Expand vertically to match the bgRect's snapped span so the
                    // even-odd cut-out is geometrically congruent with the fill.
                    let drawRect = CGRect(
                        x: segFrame.origin.x + dx,
                        y: snappedY,
                        width: segFrame.width,
                        height: snappedMaxY - snappedY
                    )
                    rects.append(drawRect)
                    return true
                }
            }
        }
        return rects
    }

    private func isCodeBlockBackgroundColor(_ color: NSColor) -> Bool {
        let highlighter = (textLayoutManager?.textContainer?.textView as? NativeTextView)?
            .configuration.services.syntaxHighlighter
            ?? PlainTextSyntaxHighlighter()
        let currentBg = highlighter.backgroundColor()
        guard let colorRGB = color.usingColorSpace(.deviceRGB),
              let currentBgRGB = currentBg.usingColorSpace(.deviceRGB) else { return false }
        let tolerance: CGFloat = 0.03
        return abs(colorRGB.redComponent - currentBgRGB.redComponent) < tolerance &&
               abs(colorRGB.greenComponent - currentBgRGB.greenComponent) < tolerance &&
               abs(colorRGB.blueComponent - currentBgRGB.blueComponent) < tolerance
    }

    // MARK: - Blockquote callout

    private var hasBlockquote: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        return ts.attribute(.blockquoteAccent, at: range.location, effectiveRange: nil) is NSColor
    }

    private func drawBlockquote(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0,
              let accent = ts.attribute(.blockquoteAccent, at: range.location, effectiveRange: nil) as? NSColor
        else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let internalPad = Self.blockquoteInternalPad

        var lineFrags = textLineFragments
        if lineFrags.count > 1, let last = lineFrags.last, last.characterRange.length == 0 {
            lineFrags.removeLast()
        }
        guard let firstLF = lineFrags.first, let lastLF = lineFrags.last else { return }

        var effectiveHeight = layoutFragmentFrame.height
        if textLineFragments.count > 1, let last = textLineFragments.last, last.characterRange.length == 0 {
            effectiveHeight -= last.typographicBounds.height
        }

        // For adjacent quote lines, extend the box to the fragment edge so
        // consecutive boxes abut exactly (no margin between them).
        let prevIsQuote = range.location > 0
            && ts.attribute(.blockquoteAccent, at: range.location - 1, effectiveRange: nil) != nil
        let nextIsQuote = NSMaxRange(range) < ts.length
            && ts.attribute(.blockquoteAccent, at: NSMaxRange(range), effectiveRange: nil) != nil

        // Box the line box (origin → origin + height), in which TextKit already
        // centers the glyphs, then pad symmetrically. Cap the height to the
        // clean line height: the last line being typed has no trailing newline,
        // so TextKit folds the paragraph spacing into its bounds, which would
        // otherwise inflate the box downward and push the text up.
        let font = (ts.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let cleanLineHeight = ceil(font.ascender - font.descender + font.leading)
        let textTop = point.y + firstLF.typographicBounds.origin.y
        let textBottom = point.y + lastLF.typographicBounds.origin.y
            + min(lastLF.typographicBounds.height, cleanLineHeight)
        let topEdge = prevIsQuote ? point.y : (textTop - internalPad)
        let bottomEdge = nextIsQuote ? (point.y + effectiveHeight) : (textBottom + internalPad)

        let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        // Round both edges the same way so an abutting neighbor's shared edge
        // lands on the same pixel (no overlap seam, no gap).
        let snappedY = (topEdge * scale).rounded() / scale
        let snappedMaxY = (bottomEdge * scale).rounded() / scale
        let height = snappedMaxY - snappedY

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let leftX = point.x - layoutFragmentFrame.origin.x

        let bgRect = CGRect(x: leftX, y: snappedY, width: containerWidth, height: height)
        accent.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: bgRect).fill()

        let barRect = CGRect(x: leftX + 4, y: snappedY, width: 3, height: height)
        accent.setFill()
        NSBezierPath(rect: barRect).fill()
    }

    // MARK: - Horizontal rule

    private var hasHorizontalRule: Bool {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return false }
        return ts.attribute(.horizontalRule, at: range.location, effectiveRange: nil) is NSColor
    }

    private func drawHorizontalRule(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0,
              let color = ts.attribute(.horizontalRule, at: range.location, effectiveRange: nil) as? NSColor
        else { return }

        var lineFrags = textLineFragments
        if lineFrags.count > 1, let last = lineFrags.last, last.characterRange.length == 0 {
            lineFrags.removeLast()
        }
        guard let firstLF = lineFrags.first else { return }

        let containerWidth = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        let lineMidY = point.y + firstLF.typographicBounds.origin.y + firstLF.typographicBounds.height / 2

        let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let thickness: CGFloat = 1
        let y = (lineMidY * scale).rounded() / scale - thickness / 2

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        let leftX = point.x - layoutFragmentFrame.origin.x
        let ruleRect = CGRect(x: leftX, y: y, width: containerWidth, height: thickness)
        color.setFill()
        NSBezierPath(rect: ruleRect).fill()
    }

    // MARK: - LaTeX / Block Image Helpers

    /// Compute the draw rect for a block image at `attrRange` using `point` as
    /// the draw origin.  Shared by `drawLatexImages` and `blockImageRects` so
    /// bounds and rendering stay in sync.
    private func blockImageDrawRect(
        attrRange: NSRange,
        imageBounds: CGRect,
        blockOffsetY: CGFloat?,
        point: CGPoint
    ) -> CGRect? {
        guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return nil }
        let localIndex = attrRange.location - (fragmentNSRange?.location ?? 0)
        let lb = lineBounds(forLocalIndex: localIndex, point: point)
        let lineHeight = lb?.height ?? pos.lineHeight
        let lineMinY = lb?.origin.y ?? (pos.baselineY - lineHeight)

        let yPosition: CGFloat
        if let blockOffsetY {
            yPosition = lineMinY + blockOffsetY
        } else {
            yPosition = lineMinY + (lineHeight - imageBounds.height) / 2
        }
        return CGRect(x: pos.x, y: yPosition,
                       width: imageBounds.width, height: imageBounds.height)
    }

    /// Returns the rects of all block images in this fragment, relative to
    /// `point`.  Used by `renderingSurfaceBounds` (with `.zero`) to extend
    /// the surface so images drawn in paragraphSpacing aren't clipped.
    private func blockImageRects(at point: CGPoint) -> [CGRect] {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return [] }
        var rects: [CGRect] = []
        ts.enumerateAttribute(.latexImage, in: range, options: []) { value, attrRange, _ in
            guard value is NSImage else { return }
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            guard isBlock else { return }
            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.rectValue ?? .zero
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat
            if let rect = blockImageDrawRect(attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point) {
                rects.append(rect)
            }
        }
        return rects
    }

    // MARK: - LaTeX Images

    private func drawLatexImages(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        ts.enumerateAttribute(.latexImage, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, let image = value as? NSImage else { return }

            let boundsVal = ts.attribute(.latexBounds, at: attrRange.location, effectiveRange: nil) as? NSValue
            let imageBounds = boundsVal?.rectValue ?? CGRect(origin: .zero, size: image.size)
            let isBlock = ts.attribute(.latexIsBlock, at: attrRange.location, effectiveRange: nil) as? Bool ?? false
            let blockOffsetY = ts.attribute(.latexBlockOffsetY, at: attrRange.location, effectiveRange: nil) as? CGFloat

            guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            let drawRect: CGRect
            if isBlock {
                guard let rect = blockImageDrawRect(attrRange: attrRange, imageBounds: imageBounds, blockOffsetY: blockOffsetY, point: point) else { return }
                drawRect = rect
            } else {
                let descent = imageBounds.origin.y
                drawRect = CGRect(x: pos.x,
                                  y: pos.baselineY + descent - imageBounds.height,
                                  width: imageBounds.width, height: imageBounds.height)
            }
            image.draw(in: drawRect)
        }
    }

    // MARK: - Task List Checkboxes

    private func drawTaskCheckboxes(at point: CGPoint, in context: CGContext) {
        guard let ts = textStorage, let range = fragmentNSRange, range.length > 0 else { return }
        let selectionRanges: [NSRange] = {
            guard let tv = textLayoutManager?.textContainer?.textView else { return [] }
            let values = tv.selectedRanges as? [NSValue] ?? []
            return values.map { $0.rangeValue }.filter { $0.length > 0 }
        }()

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext

        ts.enumerateAttribute(.taskCheckbox, in: range, options: []) { [weak self] value, attrRange, _ in
            guard let self, value != nil else { return }
            if selectionRanges.contains(where: { NSIntersectionRange($0, attrRange).length > 0 }) { return }

            let isChecked = (value as? Bool) ?? false
            guard let pos = drawPosition(forDocumentCharAt: attrRange.location, point: point) else { return }

            let font = (ts.attribute(.font, at: attrRange.location, effectiveRange: nil) as? NSFont)
                ?? (textLayoutManager?.textContainer?.textView?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
            let ascent = max(0, font.ascender)
            let descent = max(0, -font.descender)
            let configuration = (textLayoutManager?.textContainer?.textView as? NativeTextView)?.configuration ?? .default
            let fontHeight = max(1, ceil(ascent + descent))
            let markerWidth = ("[ ]" as NSString).size(withAttributes: [.font: font]).width
            let size = max(
                1.0,
                min(
                    floor(fontHeight * configuration.checkbox.sizeFromFontHeightFactor),
                    floor(markerWidth * configuration.checkbox.sizeFromMarkerWidthFactor)
                )
            )
            let boxX = pos.x + max(0, (markerWidth - size) / 2)
            let centerY = pos.baselineY + (descent - ascent) / 2
            let boxY = centerY - size / 2

            let scale = textLayoutManager?.textContainer?.textView?.window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 2.0
            func alignToPixel(_ value: CGFloat) -> CGFloat {
                (value * scale).rounded(.toNearestOrAwayFromZero) / scale
            }
            let boxRect = CGRect(x: alignToPixel(boxX), y: alignToPixel(boxY), width: size, height: size)
            guard !boxRect.isEmpty, !boxRect.isNull else { return }

            let checkboxPath = NSBezierPath(
                roundedRect: boxRect,
                xRadius: max(3, size * 0.28),
                yRadius: max(3, size * 0.28)
            )

            if isChecked {
                configuration.theme.controlAccent.setFill()
                checkboxPath.fill()

                let checkPath = NSBezierPath()
                checkPath.lineWidth = max(1.9, size * 0.15)
                checkPath.lineCapStyle = .round
                checkPath.lineJoinStyle = .round
                checkPath.move(to: CGPoint(x: boxRect.minX + size * 0.26, y: boxRect.midY + size * 0.02))
                checkPath.line(to: CGPoint(x: boxRect.minX + size * 0.43, y: boxRect.maxY - size * 0.27))
                checkPath.line(to: CGPoint(x: boxRect.maxX - size * 0.22, y: boxRect.minY + size * 0.30))
                NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.08, alpha: 1.0).setStroke()
                checkPath.stroke()
            } else {
                NSColor(white: 1.0, alpha: 0.035).setFill()
                checkboxPath.fill()
                NSColor(white: 1.0, alpha: 0.30).setStroke()
                checkboxPath.lineWidth = 1
                checkboxPath.stroke()
            }
        }
    }
}

// MARK: - Layout Manager Delegate

final class MarkdownLayoutManagerDelegate: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        // Seed body font + paragraphStyle so the trailing fragment doesn't inherit heading metrics (FB15131180).
        if let textView = textLayoutManager.textContainer?.textView as? NativeTextView {
            let baseFont = textView.baseFont
            let para = NSMutableParagraphStyle()
            let lineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: textView.layoutBridge)
            para.minimumLineHeight = ceil(lineHeight) + textView.configuration.paragraph.lineHeightExtraSpacing
            para.paragraphSpacing = ceil(lineHeight * textView.configuration.paragraph.spacingFactor)
            para.paragraphSpacingBefore = 0
            fragment.stExtraLineFragmentAttributes = NSDictionary(dictionary: [
                NSAttributedString.Key.font: baseFont,
                NSAttributedString.Key.foregroundColor: textView.configuration.theme.bodyText,
                NSAttributedString.Key.paragraphStyle: para
            ])
        }
        return fragment
    }
}
