//
//  MarkdownStyler+ListFolding.swift
//  MarkdownEngine
//
//  Collapsible lists: detect list items that have nested children, tag the
//  parent's marker with a disclosure attribute (drawn as a chevron by
//  `MarkdownTextLayoutFragment`), and — when collapsed — hide the child
//  subtree by squashing its paragraphs to ~0 height and clearing their text.
//
//  Folding never edits the note text; it only adds attributes, so the stored
//  Markdown is untouched.
//

import AppKit
import Foundation

/// A list item that owns a nested subtree and can therefore be folded.
struct ListFoldInfo {
    /// Document offset of the parent line's first character — the stable-ish
    /// key used to remember which items are collapsed.
    let lineStart: Int
    /// Document offset of the parent's list marker (first character), where the
    /// disclosure chevron is anchored.
    let markerLocation: Int
    /// Document range covering every descendant line (what collapsing hides).
    let childrenRange: NSRange
}

enum MarkdownListFolding {
    /// Scan `range` for list items that have at least one more-indented child
    /// line, returning one entry per foldable parent.
    static func foldableParents(
        in nsText: NSString,
        range: NSRange,
        configuration: MarkdownEditorConfiguration
    ) -> [ListFoldInfo] {
        struct Line {
            let range: NSRange       // includes the trailing line terminator
            let indent: Int
            let isList: Bool
            let isBlank: Bool
            let markerLocation: Int?
        }

        let spacesPerLevel = max(1, configuration.indent.width)
        var lines: [Line] = []

        nsText.enumerateSubstrings(in: range, options: [.byLines]) { substring, substringRange, enclosingRange, _ in
            let line = substring ?? ""
            let full = NSRange(location: 0, length: (line as NSString).length)
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty

            let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: line, range: full)
            let ws = wsMatch != nil ? (line as NSString).substring(with: wsMatch!.range) : ""
            let indent = MarkdownLists.indentLevel(from: ws, spacesPerLevel: spacesPerLevel)

            if let match = MarkdownLists.listRegex.firstMatch(in: line, range: full) {
                // Anchor the chevron on the checkbox `[` for to-do items (the
                // box is drawn there) and on the bullet/number otherwise, so the
                // gap to the visible glyph reads the same across list types.
                let markerGroup = match.range(at: 1)
                let markerText = (line as NSString).substring(with: markerGroup) as NSString
                let bracket = markerText.range(of: "[").location
                let anchorOffset = bracket != NSNotFound ? markerGroup.location + bracket : markerGroup.location
                let markerLocation = substringRange.location + anchorOffset
                lines.append(Line(range: enclosingRange, indent: indent, isList: true, isBlank: false, markerLocation: markerLocation))
            } else {
                lines.append(Line(range: enclosingRange, indent: indent, isList: false, isBlank: isBlank, markerLocation: nil))
            }
        }

        var result: [ListFoldInfo] = []
        for i in 0..<lines.count {
            guard lines[i].isList, let markerLocation = lines[i].markerLocation else { continue }
            let parentIndent = lines[i].indent

            // Walk forward across deeper (or blank) lines to find the subtree end.
            var lastChild = i
            var j = i + 1
            while j < lines.count {
                if lines[j].isBlank { j += 1; continue }
                if lines[j].indent > parentIndent { lastChild = j; j += 1 } else { break }
            }
            guard lastChild > i, i + 1 < lines.count else { continue }

            let childStart = lines[i + 1].range.location
            let childEnd = NSMaxRange(lines[lastChild].range)
            guard childEnd > childStart else { continue }

            result.append(ListFoldInfo(
                lineStart: lines[i].range.location,
                markerLocation: markerLocation,
                childrenRange: NSRange(location: childStart, length: childEnd - childStart)
            ))
        }
        return result
    }
}

extension MarkdownStyler {
    /// Tag foldable parents with a disclosure chevron and hide collapsed
    /// subtrees. Runs last in the styling pass so its paragraph override wins
    /// over the list paragraph attributes for hidden children.
    static func styleListFolding(_ ctx: StylingContext) -> [StyledRange] {
        guard ctx.configuration.lists.helpersEnabled else { return [] }
        let parents = MarkdownListFolding.foldableParents(
            in: ctx.nsText,
            range: ctx.fullRange,
            configuration: ctx.configuration
        )
        guard !parents.isEmpty else { return [] }

        var attrs: [StyledRange] = []
        for parent in parents {
            let markerRange = NSRange(location: parent.markerLocation, length: 1)
            if MarkdownDetection.isInsideCodeBlock(range: markerRange, codeTokens: ctx.codeTokens) { continue }

            let isCollapsed = ctx.collapsedListAnchors.contains(parent.lineStart)
            attrs.append((markerRange, [.listDisclosure: isCollapsed]))

            guard isCollapsed, parent.childrenRange.length > 0 else { continue }
            let squashed = NSMutableParagraphStyle()
            // Don't clamp line height (a sub-1 maximum is treated as "no max"
            // and renders full height). Instead let the tiny hidden-marker font
            // drive a near-zero natural line height, so even a long subtree adds
            // almost no vertical space.
            squashed.lineSpacing = 0
            squashed.paragraphSpacing = 0
            squashed.paragraphSpacingBefore = 0
            attrs.append((parent.childrenRange, [
                .paragraphStyle: squashed,
                .foregroundColor: NSColor.clear,
                .font: ctx.inlineMarkerFont,
                .listCollapsedChild: true
            ]))
        }
        return attrs
    }
}
