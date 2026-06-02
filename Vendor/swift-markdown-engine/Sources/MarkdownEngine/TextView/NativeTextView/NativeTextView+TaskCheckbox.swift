//
//  NativeTextView+TaskCheckbox.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Hit-test for `[ ]` / `[x]` checkbox glyphs and toggle the underlying text
//  + `.taskCheckbox` attribute, then nudge the coordinator to restyle the
//  enclosing paragraph.
//

import AppKit

private let taskCheckboxLineRegex = try! NSRegularExpression(
    pattern: #"^([ \t]*)([-•]|\d+\.)[ \t]+(\[[ xX]\])"#
)

extension NativeTextView {
    func toggleTaskCheckboxIfHit(event: NSEvent) -> Bool? {
        guard let textContainer = textContainer,
              let bridge = layoutBridge,
              let storage = textStorage else { return nil }
        let localPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = CGPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let index = bridge.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        let nsText = storage.string as NSString
        guard nsText.length > 0, index != NSNotFound, index <= nsText.length else { return nil }

        // Detect the checkbox from the clicked line's text so it toggles whether
        // the line is rendered (glyph) or active (raw `[ ]` while editing).
        let probe = min(index, nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: probe, length: 0))
        let lineText = nsText.substring(with: lineRange)
        let lineNSRange = NSRange(location: 0, length: (lineText as NSString).length)
        guard let match = taskCheckboxLineRegex.firstMatch(in: lineText, range: lineNSRange) else {
            return nil
        }

        // Only toggle when the click lands within the leading marker..checkbox
        // region (not in the item's text content).
        let markerRegionEnd = lineRange.location + match.range.location + match.range.length
        guard index >= lineRange.location, index <= markerRegionEnd else { return nil }

        let checkboxLocal = match.range(at: 3)
        let checkboxRange = NSRange(location: lineRange.location + checkboxLocal.location, length: checkboxLocal.length)
        if MarkdownDetection.isInsideCodeBlock(range: checkboxRange, in: storage.string) { return nil }

        let checkboxText = nsText.substring(with: checkboxRange)
        let isChecked = checkboxText.range(of: "x", options: .caseInsensitive) != nil
        let replacement = isChecked ? "[ ]" : "[x]"
        if shouldChangeText(in: checkboxRange, replacementString: replacement) {
            storage.replaceCharacters(in: checkboxRange, with: replacement)
            storage.addAttribute(.taskCheckbox, value: !isChecked, range: checkboxRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: checkboxRange)
            didChangeText()
            bridge.invalidateDisplay(forCharacterRange: checkboxRange)
            if let coord = delegate as? NativeTextViewCoordinator {
                let paragraph = (storage.string as NSString).paragraphRange(for: checkboxRange)
                coord.restyleParagraphs([paragraph], in: self)
            }
        }
        return true
    }
}
