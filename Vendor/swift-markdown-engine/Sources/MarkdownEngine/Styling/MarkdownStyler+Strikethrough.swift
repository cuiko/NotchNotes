//
//  MarkdownStyler+Strikethrough.swift
//  MarkdownEngine
//
//  Applies the strikethrough attribute to ~~text~~ content ranges.
//  Markers are collapsed by shrinkInactiveMarkers when the caret is away.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Strikethrough ~~text~~

    static func styleStrikethrough(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for token in ctx.tokens where token.kind == .strikethrough {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            attrs.append((token.contentRange, [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: ctx.configuration.theme.strikethroughColor
            ]))
        }
        return attrs
    }
}
