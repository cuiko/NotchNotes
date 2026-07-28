//
//  TextStylingService.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Applies base text styling and refreshes only changed sections so editing
// stays smooth while Markdown formatting updates.
import AppKit
import Foundation

struct TextStylingService {
    static func makeBaseTypingAttributes(
        font: NSFont,
        paragraphStyle: NSParagraphStyle,
        theme: MarkdownEditorTheme = .default
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: theme.bodyText,
            .paragraphStyle: paragraphStyle
        ]
    }

    static func makeBaseFontAndStyle(
        fontName: String,
        fontSize: CGFloat,
        layoutBridge: LayoutBridge? = nil,
        configuration: MarkdownEditorConfiguration = .default
    ) -> (font: NSFont, style: NSMutableParagraphStyle) {
        let baseFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let defaultLineHeight = layoutBridgeDefaultLineHeight(for: baseFont, using: layoutBridge)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ceil(defaultLineHeight) + configuration.paragraph.lineHeightExtraSpacing
        paragraph.lineSpacing = 0
        let baseParagraphSpacing = ceil(defaultLineHeight * configuration.paragraph.spacingFactor)
        paragraph.paragraphSpacing = baseParagraphSpacing
        paragraph.paragraphSpacingBefore = 0
        paragraph.lineBreakMode = .byWordWrapping
        return (baseFont, paragraph)
    }

    static func restyle(
        textView: NSTextView,
        layoutBridge: LayoutBridge?,
        paragraphCandidates: [NSRange],
        baseFont: NSFont,
        paragraphStyle: NSMutableParagraphStyle,
        caretLocation: Int,
        activeTokenIndices: Set<Int>,
        wikiLinkIDProvider: (NSRange) -> String?,
        precomputedTokens: [MarkdownToken]? = nil,
        configuration: MarkdownEditorConfiguration = .default
    ) {
        let paragraphs = normalize(paragraphCandidates)

        textView.typingAttributes = makeBaseTypingAttributes(
            font: baseFont,
            paragraphStyle: paragraphStyle,
            theme: configuration.theme
        )

        guard !paragraphs.isEmpty else {
            textView.setNeedsDisplay(textView.visibleRect)
            return
        }

        let styledRanges = MarkdownStyler.styleAttributes(
            text: textView.string,
            fontName: baseFont.fontName,
            fontSize: baseFont.pointSize,
            layoutBridge: layoutBridge,
            caretLocation: caretLocation,
            activeTokenIndices: activeTokenIndices,
            wikiLinkIDProvider: wikiLinkIDProvider,
            precomputedTokens: precomputedTokens,
            scopedRanges: paragraphs,
            configuration: configuration
        )

        let spellingDisabledRanges = styledRanges.compactMap { (range, attrs) -> NSRange? in
            attrs[.spellingState] as? Int == 0 ? range : nil
        }

        // Remove existing spelling markers before reapplying disabled ranges.
        for disabledRange in spellingDisabledRanges {
            layoutBridge?.removeTemporaryAttribute(.spellingState, forCharacterRange: disabledRange)
        }

        textView.textStorage?.beginEditing()
        for disabledRange in spellingDisabledRanges {
            textView.textStorage?.addAttribute(.spellingState, value: 0, range: disabledRange)
        }
        for paragraph in paragraphs {
            textView.textStorage?.setAttributes([
                .font: baseFont,
                .foregroundColor: configuration.theme.bodyText,
                .paragraphStyle: paragraphStyle
            ], range: paragraph)
            textView.textStorage?.removeAttribute(.link, range: paragraph)
            for (range, attrs) in styledRanges where NSIntersectionRange(range, paragraph).length > 0 {
                let clippedRange = NSIntersectionRange(range, paragraph)
                for (key, value) in attrs {
                    textView.textStorage?.addAttribute(key, value: value, range: clippedRange)
                }
            }
        }
        textView.textStorage?.endEditing()

        // Block images (image embeds / block LaTeX) size their paragraph's line
        // to the image height. TextKit 2's lazy layout can leave a tall image
        // mispositioned — a big gap with the image pushed far down — until the
        // next interaction forces a relayout. Force layout for those paragraphs
        // now so the height is applied immediately, not on the next click.
        let blockImageRanges = styledRanges.compactMap { (range, attrs) -> NSRange? in
            (attrs[.latexImage] != nil && (attrs[.latexIsBlock] as? Bool == true)) ? range : nil
        }
        if !blockImageRanges.isEmpty,
           let tlm = textView.textLayoutManager,
           let contentStorage = tlm.textContentManager as? NSTextContentStorage {
            let nsText = textView.string as NSString
            for range in blockImageRanges {
                let paragraph = nsText.paragraphRange(for: range)
                guard let textRange = textRange(from: paragraph, in: contentStorage) else { continue }
                tlm.invalidateLayout(for: textRange)
                tlm.ensureLayout(for: textRange)
            }
        }

        // No general ensureLayout here:
        textView.setNeedsDisplay(textView.visibleRect)
        (textView as? NativeTextView)?.ensureVisibleLayout()
    }

    private static func normalize(_ candidates: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for candidate in candidates where candidate.location != NSNotFound && candidate.length > 0 {
            if result.contains(where: { $0.location == candidate.location && $0.length == candidate.length }) {
                continue
            }
            result.append(candidate)
        }
        return result
    }

    /// Convert an NSRange into an NSTextRange for use with NSTextLayoutManager.
    static func textRange(from range: NSRange, in contentStorage: NSTextContentStorage) -> NSTextRange? {
        let docStart = contentStorage.documentRange.location
        guard let start = contentStorage.location(docStart, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }
}
