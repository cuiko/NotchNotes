//
//  ContextMenu.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 20.06.25.
//
//  Right-click menu with toggleable Markdown formatting actions.
//

import Cocoa
import SwiftUI

extension NativeTextViewWrapper.Coordinator {
    public func textView(_ textView: NSTextView,
                  menu: NSMenu,
                  for event: NSEvent,
                  at charIndex: Int) -> NSMenu? {
        let customMenu = menu.copy() as? NSMenu ?? NSMenu()
        insertImageAssetItemsIfNeeded(into: customMenu, textView: textView, charIndex: charIndex)

        if let fontIndex = customMenu.items.firstIndex(where: { $0.title == "Font" }) {
            customMenu.removeItem(at: fontIndex)
            let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
            let formatSubmenu = NSMenu(title: "Format")
            let boldItem = NSMenuItem(title: "Bold", action: #selector(didMarkdownBold(_:)), keyEquivalent: "")
            boldItem.target = self
            formatSubmenu.addItem(boldItem)
            let italicItem = NSMenuItem(title: "Italic", action: #selector(didMarkdownItalic(_:)), keyEquivalent: "")
            italicItem.target = self
            formatSubmenu.addItem(italicItem)
            formatItem.submenu = formatSubmenu
            customMenu.insertItem(formatItem, at: fontIndex)

            let headingItem = NSMenuItem(title: "Heading", action: nil, keyEquivalent: "")
            let headingSubmenu = NSMenu(title: "Heading")
            for level in 1...3 {
                let item = NSMenuItem(title: "H\(level)", action: #selector(didMarkdownHeading(_:)), keyEquivalent: "")
                item.target = self
                item.tag = level
                headingSubmenu.addItem(item)
            }
            headingItem.submenu = headingSubmenu
            customMenu.insertItem(headingItem, at: fontIndex + 1)

            let listItem = NSMenuItem(title: "Lists", action: nil, keyEquivalent: "")
            let listSubmenu = NSMenu(title: "Lists")
            let unorderedItem = NSMenuItem(title: "Bullet", action: #selector(didMarkdownUnorderedList(_:)), keyEquivalent: "")
            unorderedItem.target = self
            listSubmenu.addItem(unorderedItem)
            let orderedItem = NSMenuItem(title: "Numbered", action: #selector(didMarkdownOrderedList(_:)), keyEquivalent: "")
            orderedItem.target = self
            listSubmenu.addItem(orderedItem)
            listItem.submenu = listSubmenu
            customMenu.insertItem(listItem, at: fontIndex + 2)
            customMenu.insertItem(NSMenuItem.separator(), at: fontIndex + 3)
        }

        return customMenu
    }

    private func insertImageAssetItemsIfNeeded(into menu: NSMenu, textView: NSTextView, charIndex: Int) {
        guard let provider = configuration.services.images as? any EmbeddedImageFileProvider,
              let imageReference = imageReference(at: charIndex, in: textView) else {
            return
        }

        let request = imageReference.providerRequest
        let storedURL = provider.storedFileURL(for: request)
        let originalURL = provider.originalFileURL(for: request)

        let copyImageItem = NSMenuItem(title: "复制图片", action: #selector(didCopyEmbeddedImage(_:)), keyEquivalent: "")
        copyImageItem.target = self
        copyImageItem.representedObject = request
        copyImageItem.isEnabled = configuration.services.images.image(for: request) != nil

        let copyStoredFileItem = NSMenuItem(title: "复制图片文件", action: #selector(didCopyEmbeddedImageFile(_:)), keyEquivalent: "")
        copyStoredFileItem.target = self
        copyStoredFileItem.representedObject = storedURL
        copyStoredFileItem.isEnabled = storedURL != nil

        let copyOriginalFileItem = NSMenuItem(title: "复制原始文件", action: #selector(didCopyEmbeddedImageFile(_:)), keyEquivalent: "")
        copyOriginalFileItem.target = self
        copyOriginalFileItem.representedObject = originalURL
        copyOriginalFileItem.isEnabled = originalURL != nil

        let revealStoredItem = NSMenuItem(title: "在 Finder 中显示副本", action: #selector(didRevealEmbeddedImageFile(_:)), keyEquivalent: "")
        revealStoredItem.target = self
        revealStoredItem.representedObject = storedURL
        revealStoredItem.isEnabled = storedURL != nil

        let revealOriginalItem = NSMenuItem(title: "在 Finder 中显示原始文件", action: #selector(didRevealEmbeddedImageFile(_:)), keyEquivalent: "")
        revealOriginalItem.target = self
        revealOriginalItem.representedObject = originalURL
        revealOriginalItem.isEnabled = originalURL != nil

        let copyMarkdownItem = NSMenuItem(title: "复制 Markdown 引用", action: #selector(didCopyEmbeddedImageMarkdown(_:)), keyEquivalent: "")
        copyMarkdownItem.target = self
        copyMarkdownItem.representedObject = imageReference.markdown

        [
            copyImageItem,
            copyStoredFileItem,
            copyOriginalFileItem,
            revealStoredItem,
            revealOriginalItem,
            copyMarkdownItem,
            NSMenuItem.separator()
        ].reversed().forEach { item in
            menu.insertItem(item, at: 0)
        }
    }

    private func imageReference(at charIndex: Int, in textView: NSTextView) -> ImageEmbedReference? {
        let text = textView.string as NSString
        guard text.length > 0 else { return nil }

        let fallbackLocation = min(textView.selectedRange().location, text.length)
        let clickLocation = charIndex >= 0 ? min(charIndex, text.length) : fallbackLocation
        let parsed = parsedDocument(for: textView.string)

        let token = parsed.imageEmbedTokens.first { token in
            token.containsSelectionOrStandaloneParagraph(clickLocation, in: text)
                || token.containsSelectionOrStandaloneParagraph(fallbackLocation, in: text)
        }

        guard let token else { return nil }
        let content = text.substring(with: token.contentRange)
        return ImageEmbedReference(content: content)
    }

    @objc private func didCopyEmbeddedImage(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? EmbeddedImageRequest,
              let image = configuration.services.images.image(for: request) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @objc private func didCopyEmbeddedImageFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    @objc private func didRevealEmbeddedImageFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func didCopyEmbeddedImageMarkdown(_ sender: NSMenuItem) {
        guard let markdown = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    /// Returns the smallest bold or boldItalic token that fully contains the selection, or nil when the selection isn't enclosed by emphasis with a bold trait.
    func enclosingBoldToken(for selection: NSRange, in text: String) -> MarkdownToken? {
        let tokens = parsedDocument(for: text).tokens
        return tokens.first { token in
            (token.kind == .bold || token.kind == .boldItalic) && tokenEncloses(token, selection: selection)
        }
    }

    /// Returns the smallest italic or boldItalic token that fully contains the selection, or nil when the selection isn't enclosed by emphasis with an italic trait.
    func enclosingItalicToken(for selection: NSRange, in text: String) -> MarkdownToken? {
        let tokens = parsedDocument(for: text).tokens
        return tokens.first { token in
            (token.kind == .italic || token.kind == .boldItalic) && tokenEncloses(token, selection: selection)
        }
    }

    func isSelectionBold(in nsText: NSString, range: NSRange) -> Bool {
        return enclosingBoldToken(for: range, in: nsText as String) != nil
    }

    func isSelectionItalic(in nsText: NSString, range: NSRange) -> Bool {
        return enclosingItalicToken(for: range, in: nsText as String) != nil
    }

    private func tokenEncloses(_ token: MarkdownToken, selection: NSRange) -> Bool {
        return selection.location >= token.range.location
            && NSMaxRange(selection) <= NSMaxRange(token.range)
    }

    /// Replaces the marker characters of an emphasis token with `replacement` on each side, preserving the inner content.
    private func unwrapToken(_ token: MarkdownToken, leftReplacement: String, rightReplacement: String) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let content = nsText.substring(with: token.contentRange)
        let newText = leftReplacement + content + rightReplacement
        if tv.shouldChangeText(in: token.range, replacementString: newText) {
            tv.replaceCharacters(in: token.range, with: newText)
            tv.didChangeText()
            let newSelectionLocation = token.range.location + leftReplacement.count
            tv.setSelectedRange(NSRange(location: newSelectionLocation, length: content.count))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    func isSelectionHeading(level: Int, in nsText: NSString, range: NSRange) -> Bool {
        let lineRange = nsText.lineRange(for: range)
        let line = nsText.substring(with: lineRange)
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine.hasPrefix(String(repeating: "#", count: level) + " ")
    }

    func isSelectionList(in nsText: NSString, range: NSRange) -> Bool {
        let lineRange = nsText.lineRange(for: range)
        let line = nsText.substring(with: lineRange)
        return line.hasPrefix("\t• ") || line.hasPrefix("1. ")
    }

    /// Applies a line-level transform to every line the selection touches,
    /// replacing the whole line block in one edit so multi-line selections style
    /// each line instead of collapsing into the first one. `transform` returns
    /// nil to leave a line untouched (e.g. blanks); `itemIndex` counts only the
    /// transformed lines, for numbered lists.
    private func transformSelectedLines(_ transform: (_ line: String, _ itemIndex: Int) -> String?) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let lineRange = nsText.lineRange(for: range)
        let block = nsText.substring(with: lineRange)
        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hasTrailingNewline { lines.removeLast() }
        if lines.isEmpty { lines = [""] }

        var itemIndex = 0
        let transformed = lines.map { line -> String in
            if let out = transform(line, itemIndex) {
                itemIndex += 1
                return out
            }
            return line
        }
        let body = transformed.joined(separator: "\n")
        let replacement = body + (hasTrailingNewline ? "\n" : "")
        if tv.shouldChangeText(in: lineRange, replacementString: replacement) {
            tv.replaceCharacters(in: lineRange, with: replacement)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: lineRange.location, length: (body as NSString).length))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    private func applyHeading(level: Int) {
        let prefix = String(repeating: "#", count: level) + " "
        transformSelectedLines { line, _ in
            var content = line.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { return nil }
            while content.hasPrefix("#") { content.removeFirst() }
            content = content.trimmingCharacters(in: .whitespaces)
            return prefix + content
        }
    }

    @objc func didMarkdownHeading(_ sender: NSMenuItem) {
        applyHeading(level: sender.tag)
    }

    private func applyList(prefix: String) {
        transformSelectedLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            var content = line
            if content.hasPrefix(prefix) {
                content = String(content.dropFirst(prefix.count))
            }
            return prefix + content
        }
    }

    private func applyOrderedList() {
        transformSelectedLines { line, index in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let content = stripOrderedListPrefix(from: line)
            return "\(index + 1). " + content
        }
    }

    /// Drops a leading `N. ` ordered-list marker so re-applying renumbers
    /// instead of stacking prefixes.
    private func stripOrderedListPrefix(from line: String) -> String {
        var digits = 0
        for char in line {
            if char.isNumber { digits += 1 } else { break }
        }
        guard digits > 0 else { return line }
        let afterDigits = line.index(line.startIndex, offsetBy: digits)
        guard line[afterDigits...].hasPrefix(". ") else { return line }
        return String(line[line.index(afterDigits, offsetBy: 2)...])
    }

    @objc func didMarkdownUnorderedList(_ sender: Any?) {
        applyList(prefix: "\t• ")
    }

    @objc func didMarkdownOrderedList(_ sender: Any?) {
        applyOrderedList()
    }

    @objc func didMarkdownBold(_ sender: Any?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        if let token = enclosingBoldToken(for: range, in: tv.string) {
            // Toggle off: bold → plain, boldItalic → italic.
            let (left, right) = token.kind == .boldItalic ? ("*", "*") : ("", "")
            unwrapToken(token, leftReplacement: left, rightReplacement: right)
            return
        }

        if range.length == 0 {
            insertEmptyMarkers("**")
            return
        }

        wrapSelection(with: "**")
    }

    @objc func didMarkdownItalic(_ sender: Any?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()

        if let token = enclosingItalicToken(for: range, in: tv.string) {
            // Toggle off: italic → plain, boldItalic → bold.
            let (left, right) = token.kind == .boldItalic ? ("**", "**") : ("", "")
            unwrapToken(token, leftReplacement: left, rightReplacement: right)
            return
        }

        if range.length == 0 {
            insertEmptyMarkers("*")
            return
        }

        wrapSelection(with: "*")
    }

    private func insertEmptyMarkers(_ marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let insertion = marker + marker
        if tv.shouldChangeText(in: range, replacementString: insertion) {
            tv.replaceCharacters(in: range, with: insertion)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: range.location + marker.count, length: 0))
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    private func wrapSelection(with marker: String) {
        guard let tv = textView else { return }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        let original = nsText.substring(with: range)

        // Inline Markdown markers don't span line breaks, so a multi-line
        // selection wraps each line individually rather than only the whole
        // block's head/tail.
        if original.contains("\n") {
            let newText = original
                .components(separatedBy: "\n")
                .map { wrapLine($0, with: marker) }
                .joined(separator: "\n")
            if tv.shouldChangeText(in: range, replacementString: newText) {
                tv.replaceCharacters(in: range, with: newText)
                tv.didChangeText()
                let newRange = NSRange(location: range.location, length: (newText as NSString).length)
                tv.setSelectedRange(newRange)
                DispatchQueue.main.async { self.text = tv.string }
            }
            return
        }

        let leadingWS = original.prefix { $0.isWhitespace }.count
        let trailingWS = original.reversed().prefix { $0.isWhitespace }.count
        let coreStart = original.index(original.startIndex, offsetBy: leadingWS)
        let coreEnd = original.index(original.endIndex, offsetBy: -trailingWS)
        let core = coreStart <= coreEnd ? String(original[coreStart..<coreEnd]) : ""
        let leading = String(original[..<coreStart])
        let trailing = String(original[coreEnd...])
        let newText = leading + marker + core + marker + trailing
        if tv.shouldChangeText(in: range, replacementString: newText) {
            tv.replaceCharacters(in: range, with: newText)
            tv.didChangeText()
            let newRange = NSRange(location: range.location + leadingWS + marker.count, length: core.count)
            tv.setSelectedRange(newRange)
            DispatchQueue.main.async { self.text = tv.string }
        }
    }

    /// Wrap a single line's non-whitespace core with the marker, preserving any
    /// leading/trailing whitespace and leaving blank lines untouched.
    private func wrapLine(_ line: String, with marker: String) -> String {
        let leadingWS = line.prefix { $0.isWhitespace }.count
        let trailingWS = line.reversed().prefix { $0.isWhitespace }.count
        guard leadingWS + trailingWS < line.count else { return line }

        let coreStart = line.index(line.startIndex, offsetBy: leadingWS)
        let coreEnd = line.index(line.endIndex, offsetBy: -trailingWS)
        let leading = String(line[..<coreStart])
        let core = String(line[coreStart..<coreEnd])
        let trailing = String(line[coreEnd...])
        return leading + marker + core + marker + trailing
    }
}

// MARK: - Menu Item Validation
extension NativeTextViewWrapper.Coordinator: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let tv = textView else { return true }
        let nsText = tv.string as NSString
        let range = tv.selectedRange()
        switch menuItem.action {
        case #selector(didMarkdownBold(_:)):
            menuItem.state = enclosingBoldToken(for: range, in: tv.string) != nil ? .on : .off
            return true
        case #selector(didMarkdownItalic(_:)):
            menuItem.state = enclosingItalicToken(for: range, in: tv.string) != nil ? .on : .off
            return true
        case #selector(didMarkdownHeading(_:)):
            return !isSelectionHeading(level: menuItem.tag, in: nsText, range: range)
        case #selector(didMarkdownUnorderedList(_:)),
             #selector(didMarkdownOrderedList(_:)):
            return !isSelectionList(in: nsText, range: range)
        case #selector(didCopyEmbeddedImage(_:)):
            return menuItem.representedObject is EmbeddedImageRequest
        case #selector(didCopyEmbeddedImageFile(_:)),
             #selector(didRevealEmbeddedImageFile(_:)):
            return menuItem.representedObject is URL
        case #selector(didCopyEmbeddedImageMarkdown(_:)):
            return menuItem.representedObject is String
        default:
            return true
        }
    }
}
