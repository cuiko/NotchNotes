//
//  NativeTextView+ListFold.swift
//  MarkdownEngine
//
//  Hit-test the disclosure chevron drawn to the left of a foldable list item's
//  marker and toggle that item's collapsed state. Toggling only flips an
//  attribute-driven set — the note text is never modified.
//

import AppKit

extension NativeTextView {
    /// The foldable parent whose disclosure chevron sits under `event`, if any.
    /// Shared by the click toggle and the pointing-hand cursor so both agree on
    /// the hit region.
    func foldChevronHit(at event: NSEvent) -> ListFoldInfo? {
        guard configuration.lists.helpersEnabled,
              let textContainer = textContainer,
              let bridge = layoutBridge,
              let storage = textStorage else { return nil }

        let nsText = storage.string as NSString
        guard nsText.length > 0 else { return nil }

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
        guard index != NSNotFound else { return nil }
        let probe = min(max(index, 0), nsText.length - 1)
        let lineRange = nsText.lineRange(for: NSRange(location: probe, length: 0))

        // Cheap early-out: only scan the document for foldable parents when the
        // pointer is actually on a list line (this runs on every cursor update).
        let line = nsText.substring(with: lineRange)
        guard MarkdownLists.listRegex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ) != nil else { return nil }

        let parents = MarkdownListFolding.foldableParents(
            in: nsText,
            range: NSRange(location: 0, length: nsText.length),
            configuration: configuration
        )
        guard let parent = parents.first(where: { $0.lineStart == lineRange.location }) else { return nil }

        // The chevron sits just left of the marker; accept clicks in that gutter
        // band on the parent line's own row.
        let markerRect = bridge.boundingRect(
            forCharacterRange: NSRange(location: parent.markerLocation, length: 1),
            in: textContainer
        )
        guard markerRect.width >= 0 else { return nil }
        let zoneMinX = markerRect.minX - 24
        let zoneMaxX = markerRect.minX + 6
        guard containerPoint.x >= zoneMinX, containerPoint.x <= zoneMaxX,
              containerPoint.y >= markerRect.minY - 3, containerPoint.y <= markerRect.maxY + 3 else {
            return nil
        }
        return parent
    }

    /// Returns true when the click landed on a foldable item's chevron (and the
    /// fold was toggled), so `mouseDown` can consume the event.
    func toggleListFoldIfHit(event: NSEvent) -> Bool {
        guard let parent = foldChevronHit(at: event) else { return false }

        if collapsedListAnchors.contains(parent.lineStart) {
            collapsedListAnchors.remove(parent.lineStart)
        } else {
            collapsedListAnchors.insert(parent.lineStart)
            // Don't leave the caret stranded on a now-hidden child line.
            let sel = selectedRange()
            if NSLocationInRange(sel.location, parent.childrenRange) {
                let ns = (textStorage?.string ?? "") as NSString
                let parentLine = ns.lineRange(for: NSRange(location: parent.lineStart, length: 0))
                var end = NSMaxRange(parentLine)
                if end > parentLine.location,
                   ns.substring(with: NSRange(location: end - 1, length: 1)) == "\n" {
                    end -= 1
                }
                setSelectedRange(NSRange(location: end, length: 0))
            }
        }
        onCollapsedListAnchorsChanged?(collapsedListAnchors)

        if let coord = delegate as? NativeTextViewCoordinator {
            coord.reapplyStylingAfterFoldChange(self)
        }
        return true
    }
}
