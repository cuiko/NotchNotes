//
//  NativeTextView+PasteHandling.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//

import AppKit

extension NativeTextView {
    private static let pastableTextExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "txt", "text"
    ]

    override func paste(_ sender: Any?) {
        guard isEditable else {
            super.paste(sender)
            return
        }

        let pasteboard = NSPasteboard.general

        if let imageEmbed = onPasteImage?(pasteboard), !imageEmbed.isEmpty {
            insertBlockEmbed(imageEmbed)
            return
        }

        if let pasted = pasteboard.string(forType: .string) {
            if selectedRange().length > 0, let url = bareURL(from: pasted) {
                insertMarkdownLink(url: url)
                return
            }
            let sanitized = sanitizePastedText(pasted)
            if !sanitized.isEmpty {
                insertText(sanitized, replacementRange: selectedRange())
                return
            }
        }

        if let fileText = textFromPastedFileURL(pasteboard: pasteboard) {
            let sanitized = sanitizePastedText(fileText)
            if !sanitized.isEmpty {
                insertText(sanitized, replacementRange: selectedRange())
                return
            }
        }

        pasteAsPlainText(sender)
    }

    /// Returns the clipboard text when it is a single bare URL, otherwise nil.
    /// Pasting one over a selection wraps it as `[selection](url)`. With no
    /// selection it falls through to a plain paste — a bare URL already renders
    /// and opens on its own, and `[url](url)` would only be harder to edit.
    private func bareURL(from pasted: String) -> String? {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") else {
            return nil
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let full = NSRange(location: 0, length: (trimmed as NSString).length)
        let matches = detector.matches(in: trimmed, range: full)
        guard matches.count == 1, let match = matches.first,
              NSEqualRanges(match.range, full), match.url != nil else {
            return nil
        }
        return trimmed
    }

    private func insertMarkdownLink(url: String) {
        let sel = selectedRange()
        let label = (string as NSString).substring(with: sel)
        insertText("[\(label)](\(url))", replacementRange: sel)
    }

    private func insertBlockEmbed(_ embed: String) {
        let sel = selectedRange()
        let nsText = string as NSString
        var prefix = ""
        var suffix = ""
        if sel.location > 0, nsText.character(at: sel.location - 1) != 0x0A {
            prefix = "\n"
        }
        let afterLocation = sel.location + sel.length
        if afterLocation < nsText.length, nsText.character(at: afterLocation) != 0x0A {
            suffix = "\n"
        }
        insertText(prefix + embed + suffix, replacementRange: sel)
    }

    /// Reads the textual content of a pasted markdown/text file URL — the
    /// fallback that makes iOS Universal Clipboard pastes useful.
    private func textFromPastedFileURL(pasteboard: NSPasteboard) -> String? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        for url in urls where url.isFileURL {
            guard Self.pastableTextExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
            if let s = try? String(contentsOf: url) { return s }
        }
        return nil
    }

    private func sanitizePastedText(_ s: String) -> String {
        var out = s
        if let regex = try? NSRegularExpression(pattern: "\\n{3,}") {
            let nsRange = NSRange(location: 0, length: (out as NSString).length)
            out = regex.stringByReplacingMatches(in: out, range: nsRange, withTemplate: "\n\n")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) {
            let pasteboard = NSPasteboard.general
            if PasteboardImageReader.canPasteImage(from: pasteboard) { return true }
            if textFromPastedFileURL(pasteboard: pasteboard) != nil { return true }
        }
        return super.validateUserInterfaceItem(item)
    }
}
