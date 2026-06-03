//
//  MarkdownStyler+Code.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Fenced code blocks and inline code spans.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Fenced Code Blocks

    static func styleCodeBlocks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        // Outer spacing = unfilled margin to neighbors + filled inner padding.
        let edgeSpacing = ctx.configuration.codeBlock.paragraphSpacing + MarkdownTextLayoutFragment.codeBlockInnerPad
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .codeBlock {
            let codeContent = ctx.nsText.substring(with: token.contentRange)
            let isActive = ctx.activeTokenIndices.contains(idx)
            let language = MarkdownTokenizer.extractLanguage(from: token, in: ctx.text)

            attrs.append((token.range, [
                .font: ctx.codeFont,
                .backgroundColor: ctx.codeBackgroundColor
            ]))

            // Per-line paragraph styles: interior lines are tight (no spacing),
            // and the configured spacing is applied only at the block's first
            // and last line as an outer margin. The renderer keeps that margin
            // out of the fill, so it becomes a gap to neighboring content
            // rather than padding inside the box.
            var paragraphRanges: [NSRange] = []
            ctx.nsText.enumerateSubstrings(in: token.range, options: .byParagraphs) { _, _, enclosing, _ in
                paragraphRanges.append(enclosing)
            }
            for (line, paragraphRange) in paragraphRanges.enumerated() {
                guard let style = ctx.codeParagraphStyle.mutableCopy() as? NSMutableParagraphStyle else { continue }
                style.paragraphSpacingBefore = (line == 0) ? edgeSpacing : 0
                style.paragraphSpacing = (line == paragraphRanges.count - 1) ? edgeSpacing : 0
                attrs.append((paragraphRange, [.paragraphStyle: style]))
            }

            if !codeContent.isEmpty,
               let highlighted = ctx.services.syntaxHighlighter.highlight(code: codeContent, language: language) {
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { highlightAttrs, range, _ in
                    guard let foregroundColor = highlightAttrs[.foregroundColor] else { return }
                    let absoluteRange = NSRange(location: token.contentRange.location + range.location, length: range.length)
                    attrs.append((absoluteRange, [.foregroundColor: foregroundColor]))
                }
            }

            let hidden: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.clear, .font: ctx.hiddenMarkerFont]
            if isActive {
                let activeMarker: [NSAttributedString.Key: Any] = [.foregroundColor: ctx.configuration.theme.mutedText, .font: ctx.codeFont]
                token.markerRanges.forEach { attrs.append(($0, activeMarker)) }
            } else {
                // Collapsed: hide the fences, but surface the language as a small
                // label on the opening line (top-left of the box).
                for (markerIndex, marker) in token.markerRanges.enumerated() {
                    if markerIndex == 0, let language, !language.isEmpty, marker.length > 4 {
                        let langRange = NSRange(location: marker.location + 3, length: marker.length - 4)
                        let backticks = NSRange(location: marker.location, length: 3)
                        attrs.append((backticks, hidden))
                        attrs.append((langRange, [
                            .foregroundColor: ctx.configuration.theme.mutedText,
                            .font: ctx.codeFont
                        ]))
                        let trailingStart = NSMaxRange(langRange)
                        let trailing = NSRange(location: trailingStart, length: NSMaxRange(marker) - trailingStart)
                        if trailing.length > 0 { attrs.append((trailing, hidden)) }
                    } else {
                        attrs.append((marker, hidden))
                    }
                }
            }
        }
        return attrs
    }

    // MARK: Inline Code

    static func styleInlineCode(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .inlineCode {
            let isActive = ctx.activeTokenIndices.contains(idx)
            let accent = ctx.configuration.theme.controlAccent
            attrs.append((token.contentRange, [
                .font: ctx.baseFont,
                .foregroundColor: accent,
                .backgroundColor: accent.withAlphaComponent(0.16)
            ]))
            let inlineMarkerAttributes: [NSAttributedString.Key: Any] = isActive
                ? [
                    .foregroundColor: ctx.configuration.theme.mutedText,
                    .font: ctx.codeFont
                ]
                : [
                    .foregroundColor: ctx.configuration.theme.mutedText.withAlphaComponent(ctx.configuration.markers.inlineCodeMarkerAlpha),
                    .font: ctx.inlineMarkerFont
                ]
            token.markerRanges.forEach { attrs.append(($0, inlineMarkerAttributes)) }
        }
        return attrs
    }
}
