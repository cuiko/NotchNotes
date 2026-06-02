//
//  MarkdownStyler+TaskCheckboxes.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  GitHub-style `- [ ] / - [x]` task checkbox styling and strike-through.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Task List Checkboxes

    static func styleTaskCheckboxes(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let taskMatches = MarkdownStyler.taskListRegex.matches(in: ctx.text, options: [], range: ctx.fullRange)
        for match in taskMatches {
            let markerRange = match.range(at: 2)
            let spacerRange = match.range(at: 3)
            let checkboxRange = match.range(at: 4)
            if checkboxRange.location == NSNotFound { continue }
            if MarkdownDetection.isInsideCodeBlock(range: checkboxRange, codeTokens: ctx.codeTokens) { continue }
            let checkboxText = ctx.nsText.substring(with: checkboxRange)
            let isChecked = checkboxText.range(of: "[x]", options: [.caseInsensitive]) != nil
            if markerRange.location != NSNotFound {
                let syntaxStart = markerRange.location
                let syntaxEnd = checkboxRange.location + checkboxRange.length
                let syntaxRange = NSRange(location: syntaxStart, length: max(0, syntaxEnd - syntaxStart))
                var isActiveSyntax = NSLocationInRange(ctx.caretLocation, syntaxRange)
                if !isActiveSyntax && ctx.caretLocation == syntaxEnd {
                    let lastIndex = syntaxEnd - 1
                    if lastIndex >= syntaxStart && lastIndex < ctx.nsText.length {
                        let lastChar = ctx.nsText.substring(with: NSRange(location: lastIndex, length: 1))
                        if lastChar != "\n" { isActiveSyntax = true }
                    }
                }
                if isChecked {
                    let lineRange = ctx.nsText.lineRange(for: checkboxRange)
                    var lineEnd = lineRange.location + lineRange.length
                    if lineEnd > lineRange.location {
                        let lastCharRange = NSRange(location: lineEnd - 1, length: 1)
                        if ctx.nsText.substring(with: lastCharRange) == "\n" {
                            lineEnd -= 1
                        }
                    }
                    var contentStart = checkboxRange.location + checkboxRange.length
                    while contentStart < lineEnd {
                        let charRange = NSRange(location: contentStart, length: 1)
                        let char = ctx.nsText.substring(with: charRange)
                        if char == " " || char == "\t" {
                            contentStart += 1
                            continue
                        }
                        break
                    }
                    if contentStart < lineEnd {
                        attrs.append((NSRange(location: contentStart, length: lineEnd - contentStart), [
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: ctx.configuration.theme.strikethroughColor
                        ]))
                    }
                }
                // Apply the checkbox-to-text spacing on the closing `]` (not the
                // trailing space, which TextKit collapses at line end). Also
                // normalize for the hidden text width — `[x]` is wider than `[ ]`
                // — so the content starts at the same offset in both states.
                if checkboxRange.length > 0 {
                    let closingBracketRange = NSRange(
                        location: checkboxRange.location + checkboxRange.length - 1,
                        length: 1
                    )
                    let extraSpacing = HeadingHelpers.checkboxExtraSpacing(
                        font: ctx.baseFont,
                        configuration: ctx.configuration.checkbox
                    )
                    let normalizedWidth = HeadingHelpers.textWidth("[ ]", font: ctx.baseFont)
                    let actualWidth = HeadingHelpers.textWidth(checkboxText, font: ctx.baseFont)
                    attrs.append((closingBracketRange, [.kern: extraSpacing + normalizedWidth - actualWidth]))
                }
                if isActiveSyntax { continue }
            }
            if markerRange.location != NSNotFound {
                attrs.append((markerRange, [.foregroundColor: NSColor.clear]))
            }
            if spacerRange.location != NSNotFound {
                attrs.append((spacerRange, [.foregroundColor: NSColor.clear]))
            }
            attrs.append((checkboxRange, [
                .taskCheckbox: isChecked,
                .foregroundColor: NSColor.clear
            ]))
        }
        return attrs
    }
}
