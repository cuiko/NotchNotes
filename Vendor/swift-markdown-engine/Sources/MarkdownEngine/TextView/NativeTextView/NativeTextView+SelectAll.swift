//
//  NativeTextView+SelectAll.swift
//  MarkdownEngine
//
//  Makes ⌘A context-aware inside multi-line blocks: the first press selects
//  just the enclosing block (code block content, a blockquote, or a list); when
//  that block is already fully selected, a second press falls through to select
//  the whole document.
//

import AppKit

extension NativeTextView {
    override func selectAll(_ sender: Any?) {
        let current = selectedRange()
        if let blockRange = enclosingBlockRange(for: current),
           !NSEqualRanges(current, blockRange) {
            setSelectedRange(blockRange)
            scrollRangeToVisible(blockRange)
            return
        }
        super.selectAll(sender)
    }

    /// The range ⌘A should select for the block the selection sits in, or nil
    /// when it isn't inside a recognized block.
    private func enclosingBlockRange(for selection: NSRange) -> NSRange? {
        if let code = enclosingCodeBlockContentRange(for: selection) {
            return code
        }
        let caret = selection.location
        if let quote = contiguousLineBlock(around: caret, matching: Self.isBlockquoteLine) {
            return quote
        }
        // Lists select only the current item's line, not the whole list.
        if let listLine = currentLine(around: caret, matching: Self.isListLine) {
            return listLine
        }
        return nil
    }

    /// The caret's own line (trailing newline trimmed) when it matches
    /// `matching`, else nil.
    private func currentLine(around caret: Int, matching: (String) -> Bool) -> NSRange? {
        let nsText = string as NSString
        guard nsText.length > 0 else { return nil }
        let line = nsText.lineRange(for: NSRange(location: min(caret, nsText.length), length: 0))
        guard matching(nsText.substring(with: line)) else { return nil }

        var range = line
        if range.length > 0,
           nsText.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)) == "\n" {
            range.length -= 1
        }
        return range.length > 0 ? range : nil
    }

    /// The content range (fences excluded) of the fenced code block the current
    /// selection sits in, or nil when the selection isn't inside one.
    private func enclosingCodeBlockContentRange(for selection: NSRange) -> NSRange? {
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return nil }
        let length = (string as NSString).length
        let caret = selection.location

        for entry in coordinator.cachedCodeBlockTokens {
            let block = entry.token.range
            guard caret >= block.location && caret <= NSMaxRange(block) else { continue }

            var content = entry.token.contentRange
            guard content.location <= length else { return nil }
            if NSMaxRange(content) > length {
                content.length = max(0, length - content.location)
            }
            return content.length > 0 ? content : nil
        }
        return nil
    }

    /// Expands from the caret's line over contiguous lines that all satisfy
    /// `matching`, returning their combined range (trailing newline trimmed).
    /// Returns nil when the caret's own line doesn't match.
    private func contiguousLineBlock(around caret: Int, matching: (String) -> Bool) -> NSRange? {
        let nsText = string as NSString
        guard nsText.length > 0 else { return nil }

        let caretLine = nsText.lineRange(for: NSRange(location: min(caret, nsText.length), length: 0))
        guard matching(nsText.substring(with: caretLine)) else { return nil }

        var start = caretLine.location
        while start > 0 {
            let previous = nsText.lineRange(for: NSRange(location: start - 1, length: 0))
            guard matching(nsText.substring(with: previous)) else { break }
            start = previous.location
        }

        var end = NSMaxRange(caretLine)
        while end < nsText.length {
            let next = nsText.lineRange(for: NSRange(location: end, length: 0))
            guard matching(nsText.substring(with: next)) else { break }
            end = NSMaxRange(next)
        }

        var range = NSRange(location: start, length: end - start)
        if range.length > 0,
           nsText.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)) == "\n" {
            range.length -= 1
        }
        return range.length > 0 ? range : nil
    }

    private static func isBlockquoteLine(_ line: String) -> Bool {
        line.range(of: #"^[ \t]*>"#, options: .regularExpression) != nil
    }

    private static func isListLine(_ line: String) -> Bool {
        line.range(of: #"^[ \t]*([-*+•]|\d+\.)([ \t]|$)"#, options: .regularExpression) != nil
    }
}
