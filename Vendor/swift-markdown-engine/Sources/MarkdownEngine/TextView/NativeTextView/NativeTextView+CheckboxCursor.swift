//
//  NativeTextView+CheckboxCursor.swift
//  MarkdownEngine
//
//  Shows a pointing-hand cursor over clickable task checkboxes instead of
//  the default I-beam. NSTextView continuously re-asserts the I-beam, so the
//  cursor is re-decided on every mouseMoved/cursorUpdate via a hit-test and
//  `super` is skipped while over a checkbox (otherwise the I-beam returns).
//

import AppKit

private let checkboxCursorTrackingKey = "MarkdownCheckboxCursorTracking"

extension NativeTextView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in trackingAreas where area.userInfo?[checkboxCursorTrackingKey] != nil {
            removeTrackingArea(area)
        }

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: [checkboxCursorTrackingKey: true]
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        if isPointOverTaskCheckbox(event) {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isPointOverTaskCheckbox(event) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    private func isPointOverTaskCheckbox(_ event: NSEvent) -> Bool {
        guard let textContainer,
              let bridge = layoutBridge,
              let storage = textStorage else { return false }
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
        guard index != NSNotFound, index < storage.length else { return false }

        var effectiveRange = NSRange(location: 0, length: 0)
        return storage.attribute(.taskCheckbox, at: index, effectiveRange: &effectiveRange) as? Bool != nil
            && effectiveRange.length > 0
    }
}
