//
//  NativeTextView+CodeCopyButton.swift
//  MarkdownEngine
//
//  Hovering a fenced code block shows a small copy button at the block's
//  top-right corner. Clicking it puts the block's code (without the fences) on
//  the pasteboard and briefly swaps to a checkmark as confirmation.
//
//  Modelled on `NativeTextView+ImageDeleteButton`: the button is a real subview
//  carrying its own pointing-hand cursor, and the text view's cursor logic
//  (`NativeTextView+CheckboxCursor`) skips reasserting the I-beam while the
//  pointer is over it.
//

import AppKit

/// Copy button overlaid on a hovered code block. Transparent background — just
/// the icon — and carries its own pointing-hand cursor since the enclosing text
/// view otherwise re-asserts the I-beam. Brightens the icon while the pointer is
/// directly over it, since there's no box to signal the hit target.
final class CodeCopyButton: NSButton {
    static let idleTint = NSColor.white.withAlphaComponent(0.55)
    static let hoverTint = NSColor.white.withAlphaComponent(0.95)

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = Self.hoverTint
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = Self.idleTint
    }
}

extension NativeTextView {

    private static let copySymbol = "doc.on.doc"
    private static let copiedSymbol = "checkmark"

    /// Re-evaluated on every `mouseMoved`: show the copy button over the code
    /// block under the pointer, or hide it.
    func updateCodeCopyButton(for event: NSEvent) {
        guard let hit = codeBlockHit(at: event) else {
            hideCodeCopyButton()
            return
        }

        codeCopyText = hit.code
        let button = codeCopyButton ?? makeCodeCopyButton()
        if button.superview !== self { addSubview(button) }

        let size: CGFloat = 22
        let inset: CGFloat = 6
        button.frame = CGRect(
            x: hit.rect.maxX - size - inset,
            y: hit.rect.minY + inset,
            width: size,
            height: size
        )
        button.isHidden = false
    }

    func hideCodeCopyButton() {
        codeCopyButton?.isHidden = true
        codeCopyText = nil
        codeCopyResetWorkItem?.cancel()
        codeCopyResetWorkItem = nil
        codeCopyButton?.image = NSImage(systemSymbolName: Self.copySymbol, accessibilityDescription: "Copy code")
    }

    /// True while the pointer is over the visible copy button, so the text view
    /// can keep the pointing-hand cursor instead of reasserting the I-beam.
    func isPointOverCodeCopyButton(_ event: NSEvent) -> Bool {
        guard let button = codeCopyButton, !button.isHidden else { return false }
        return button.frame.contains(convert(event.locationInWindow, from: nil))
    }

    /// Finds a fenced code block whose on-screen box contains the pointer and
    /// returns that box plus the block's content (fences excluded). Reuses the
    /// coordinator's cached code-block tokens; the box is stretched to the full
    /// container width so the whole block — not just the glyph run — is
    /// hoverable and the button lands on the real top-right corner.
    private func codeBlockHit(at event: NSEvent) -> (rect: CGRect, code: String)? {
        guard let textContainer,
              let bridge = layoutBridge,
              let storage = textStorage, storage.length > 0,
              let coordinator = delegate as? NativeTextViewCoordinator else { return nil }

        let localPoint = convert(event.locationInWindow, from: nil)
        let nsText = storage.string as NSString

        for entry in coordinator.cachedCodeBlockTokens {
            let token = entry.token
            guard NSMaxRange(token.range) <= nsText.length,
                  NSMaxRange(token.contentRange) <= nsText.length else { continue }

            var rect = bridge.boundingRect(forCharacterRange: token.range, in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            rect.origin.x = textContainerOrigin.x
            rect.size.width = textContainer.size.width
            guard rect.width > 0, rect.height > 0, rect.contains(localPoint) else { continue }

            return (rect, nsText.substring(with: token.contentRange))
        }
        return nil
    }

    private func makeCodeCopyButton() -> NSButton {
        let button = CodeCopyButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""
        button.image = NSImage(systemSymbolName: Self.copySymbol, accessibilityDescription: "Copy code")
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = CodeCopyButton.idleTint
        button.target = self
        button.action = #selector(copyHoveredCodeBlock)
        codeCopyButton = button
        return button
    }

    @objc private func copyHoveredCodeBlock() {
        guard let code = codeCopyText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        // Brief checkmark confirmation, then restore the copy icon.
        codeCopyButton?.image = NSImage(systemSymbolName: Self.copiedSymbol, accessibilityDescription: "Copied")
        codeCopyResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.codeCopyButton?.image = NSImage(systemSymbolName: Self.copySymbol, accessibilityDescription: "Copy code")
            self.codeCopyResetWorkItem = nil
        }
        codeCopyResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
