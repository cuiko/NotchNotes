//
//  MarkdownStyler+Blockquote.swift
//  MarkdownEngine
//
//  GitHub-style blockquote callouts: `> ...` lines render with a left accent
//  bar and a faint background. The `>` marker is hidden and the text indented;
//  the bar/background are drawn by MarkdownTextLayoutFragment via the
//  `.blockquoteAccent` attribute.
//

import AppKit
import Foundation

extension MarkdownStyler {

    static func styleBlockquotes(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        guard let regex = try? NSRegularExpression(
            pattern: "^[ \\t]*(>[ \\t])",
            options: [.anchorsMatchLines]
        ) else { return attrs }

        let accent = ctx.configuration.theme.controlAccent

        for match in regex.matches(in: ctx.text, options: [], range: ctx.fullRange) {
            let markerRange = match.range(at: 1)
            if markerRange.location == NSNotFound { continue }
            if MarkdownDetection.isInsideCodeBlock(range: markerRange, codeTokens: ctx.codeTokens) { continue }

            let lineRange = ctx.nsText.lineRange(for: markerRange)
            let markerText = ctx.nsText.substring(with: markerRange)
            let markerWidth = HeadingHelpers.textWidth(markerText, font: ctx.baseFont)

            // Outer padding separates the callout from other content; a smaller
            // inner gap keeps consecutive quote lines from cramping while staying
            // ≤ 2× the box's internal padding so the drawn box stays continuous.
            let pad: CGFloat = 12
            let innerGap: CGFloat = 6
            let prevIsQuote = isQuoteLine(endingBefore: lineRange.location, in: ctx.nsText)
            let nextIsQuote = isQuoteLine(startingAt: NSMaxRange(lineRange), in: ctx.nsText)

            let para = NSMutableParagraphStyle()
            // The `> ` marker is invisible but keeps its width, so the caret lands
            // after it (typing stays a blockquote) and supplies the text indent.
            para.firstLineHeadIndent = 0
            para.headIndent = markerWidth
            para.minimumLineHeight = ctx.baseDefaultLineHeight
            para.maximumLineHeight = ctx.baseDefaultLineHeight
            para.paragraphSpacingBefore = prevIsQuote ? innerGap : pad
            para.paragraphSpacing = nextIsQuote ? 0 : pad
            attrs.append((lineRange, [.paragraphStyle: para]))

            attrs.append((markerRange, [.foregroundColor: NSColor.clear]))

            attrs.append((lineRange, [.blockquoteAccent: accent]))
        }
        return attrs
    }

    private static func isQuoteLine(endingBefore location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return false }
        let lineRange = text.lineRange(for: NSRange(location: location - 1, length: 0))
        return text.substring(with: lineRange)
            .range(of: "^[ \\t]*>[ \\t]", options: .regularExpression) != nil
    }

    private static func isQuoteLine(startingAt location: Int, in text: NSString) -> Bool {
        guard location < text.length else { return false }
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        return text.substring(with: lineRange)
            .range(of: "^[ \\t]*>[ \\t]", options: .regularExpression) != nil
    }
}
