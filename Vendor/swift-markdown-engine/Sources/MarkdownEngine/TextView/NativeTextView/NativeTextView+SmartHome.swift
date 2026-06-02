//
//  NativeTextView+SmartHome.swift
//  MarkdownEngine
//
//  "Smart home": Cmd-Left / Home lands after a list/to-do/blockquote marker
//  (the content start) instead of column 0, which sits inside the hidden
//  marker. A second press from there falls back to the true line start.
//  Shift variants extend the selection to the same target.
//

import AppKit

private let blockquoteHomeRegex = try! NSRegularExpression(pattern: #"^[ \t]*>[ \t]"#)

extension NativeTextView {
    override func moveToLeftEndOfLine(_ sender: Any?) {
        if let target = smartLineStartTarget(forCaretAt: selectedRange().location) {
            setSelectedRange(NSRange(location: target, length: 0))
            scrollRangeToVisible(NSRange(location: target, length: 0))
            return
        }
        super.moveToLeftEndOfLine(sender)
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        if let target = smartLineStartTarget(forCaretAt: selectedRange().location) {
            setSelectedRange(NSRange(location: target, length: 0))
            scrollRangeToVisible(NSRange(location: target, length: 0))
            return
        }
        super.moveToBeginningOfLine(sender)
    }

    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) {
        if extendSelectionToSmartLineStart() { return }
        super.moveToLeftEndOfLineAndModifySelection(sender)
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        if extendSelectionToSmartLineStart() { return }
        super.moveToBeginningOfLineAndModifySelection(sender)
    }

    private func extendSelectionToSmartLineStart() -> Bool {
        let sel = selectedRange()
        guard let target = smartLineStartTarget(forCaretAt: sel.location), target < sel.location else {
            return false
        }
        let newRange = NSRange(location: target, length: NSMaxRange(sel) - target)
        setSelectedRange(newRange)
        scrollRangeToVisible(NSRange(location: target, length: 0))
        return true
    }

    /// The "smart" line start for `caret`: just after a list/to-do/blockquote
    /// marker, or the true line start if the caret is already there. Returns
    /// nil when the line has no such marker (use the default behavior).
    private func smartLineStartTarget(forCaretAt caret: Int) -> Int? {
        guard let storage = textStorage else { return nil }
        let nsText = storage.string as NSString
        guard nsText.length > 0 else { return nil }

        let lineRange = nsText.lineRange(for: NSRange(location: min(caret, nsText.length), length: 0))
        let line = nsText.substring(with: lineRange) as NSString
        let lineNSRange = NSRange(location: 0, length: line.length)

        var markerLength = NSNotFound
        if let match = MarkdownLists.listRegex.firstMatch(in: line as String, range: lineNSRange) {
            markerLength = match.range.location + match.range.length
        } else if let match = blockquoteHomeRegex.firstMatch(in: line as String, range: lineNSRange) {
            markerLength = match.range.location + match.range.length
        }
        guard markerLength != NSNotFound else { return nil }

        let contentStart = lineRange.location + markerLength
        return caret > contentStart ? contentStart : lineRange.location
    }
}
