//
//  NativeTextView.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//
//  AppKit `NSTextView` subclass used by the markdown editor. Stored state
//  lives here; behavior is split across `NativeTextView+<Feature>.swift`
//  files in this folder (frame & overscroll, caret workarounds, click remap,
//  paste handling, drag-select boost, task checkbox, spelling policy).
//
//  Bottom-overscroll math lives in `BottomOverscrollPolicy.swift`.
//  Pasteboard image inspection lives in `PasteboardImageReader.swift`.
//

import AppKit
import UniformTypeIdentifiers

final class NativeTextView: NSTextView {
    // MARK: Frame & overscroll state
    var baseContentHeight: CGFloat = 0
    var activeBottomOverscroll: CGFloat = 0
    var isApplyingManagedFrameSize = false
    var suppressAutoRevealOnce: Bool = false

    // MARK: Configuration
    var configuration: MarkdownEditorConfiguration = .default {
        didSet {
            overscrollPercent = configuration.overscroll.percent
            maxOverscrollPoints = configuration.overscroll.maxPoints
            minOverscrollPoints = configuration.overscroll.minPoints
        }
    }
    var overscrollPercent: CGFloat = MarkdownEditorConfiguration.default.overscroll.percent
    var maxOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.maxPoints
    var minOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.minPoints

    // MARK: Editor wiring
    var onPasteImage: ((NSPasteboard) -> String?)?
    weak var layoutBridge: LayoutBridge?
    var baseFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    // MARK: Caret-workaround state
    var caretIndicatorObservation: NSKeyValueObservation?
    weak var observedCaretIndicator: NSView?
    var isApplyingCaretShift: Bool = false

    // MARK: Drag-select state
    var dragStartMouseScreenLoc: NSPoint?

    // MARK: Image-embed delete button
    var imageDeleteButton: NSButton?
    var imageDeleteEmbedRange: NSRange?

    /// When true the editor stops asserting its I-beam cursor, letting a modal
    /// overlay drawn on top (which is not a real subview, so it can't otherwise
    /// win the cursor) show the arrow instead.
    var cursorManagementSuppressed = false {
        didSet {
            guard oldValue != cursorManagementSuppressed else { return }
            window?.invalidateCursorRects(for: self)
            if cursorManagementSuppressed {
                hideImageDeleteButton()
                NSCursor.arrow.set()
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Forward appearance changes to the embedder-supplied syntax highlighter
        // via the notification name it registered. The engine doesn't know any
        // app-specific notification names; this hook is opt-in per highlighter.
        if let name = configuration.services.syntaxHighlighter.appearanceDidChangeNotification {
            NotificationCenter.default.post(name: name, object: self)
        }
    }

    // AppKit doesn't fire textDidChange for setMarkedText mutations, so Apple's inline-prediction inserts the completion with base typingAttributes and heading lines flicker to body font; restyle the paragraph here to reapply heading font.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        guard hasMarkedText(),
              let coord = delegate as? NativeTextViewCoordinator else { return }
        let marked = markedRange()
        guard marked.location != NSNotFound, marked.length > 0 else { return }
        let nsText = self.string as NSString
        let paragraph = nsText.paragraphRange(for: marked)
        let line = nsText.substring(with: nsText.lineRange(for: NSRange(location: paragraph.location, length: 0)))
        guard line.hasPrefix("#") else { return }
        coord.restyleParagraphs([paragraph], in: self)
    }

    deinit { caretIndicatorObservation?.invalidate() }
}

public extension NSTextView {
    /// Suppresses the markdown editor's I-beam cursor management while a modal
    /// overlay covers the editor, so the overlay can show the arrow cursor.
    func setMarkdownEditorCursorSuppressed(_ suppressed: Bool) {
        (self as? NativeTextView)?.cursorManagementSuppressed = suppressed
    }
}
