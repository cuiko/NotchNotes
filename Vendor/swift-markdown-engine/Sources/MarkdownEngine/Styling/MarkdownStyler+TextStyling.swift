//
//  MarkdownStyler+TextStyling.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Heading and emphasis (bold / italic / bold+italic) attribute generation.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Headings

    static func styleHeadings(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let headingTokens = ctx.tokens.filter { $0.kind == .heading }
        for token in headingTokens {
            let level = token.markerRanges.first?.length ?? 1
            let multiplier = ctx.configuration.headings.fontMultiplier(for: level)
            let fontSize = ctx.baseFont.pointSize * multiplier
            let headingBase = NSFont(name: ctx.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let headingFont = NSFontManager.shared.convert(headingBase, toHaveTrait: .boldFontMask)

            let paraRange = ctx.nsText.paragraphRange(for: token.range)
            let headingLineHeight = ceil(layoutBridgeDefaultLineHeight(for: headingFont, using: ctx.layoutBridge)) + 1
            let headingPara = NSMutableParagraphStyle()
            headingPara.minimumLineHeight = headingLineHeight
            headingPara.maximumLineHeight = headingLineHeight
            let beforeEm = ctx.configuration.headings.topSpacingEm(for: level)
            headingPara.paragraphSpacingBefore = headingFont.pointSize * beforeEm
            headingPara.paragraphSpacing = ctx.baseParagraphSpacing
            attrs.append((paraRange, [.paragraphStyle: headingPara]))

            for markerRange in token.markerRanges {
                attrs.append((markerRange, [
                    .font: headingFont,
                    .foregroundColor: ctx.configuration.theme.headingMarker
                ]))
            }
            attrs.append((token.contentRange, [.font: headingFont]))
        }
        return attrs
    }

    // MARK: Bold / Italic / Bold+Italic

    static func styleEmphasis(_ ctx: StylingContext) -> [StyledRange] {
        // Per-char trait map collapsed into contiguous font runs so nested emphasis combines instead of overwriting.
        let len = ctx.nsText.length
        guard len > 0 else { return [] }

        var traits = [UInt8](repeating: 0, count: len)
        let boldBit: UInt8 = 1
        let italicBit: UInt8 = 2

        for token in ctx.tokens {
            let mask: UInt8
            switch token.kind {
            case .bold: mask = boldBit
            case .italic: mask = italicBit
            case .boldItalic: mask = boldBit | italicBit
            default: continue
            }
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            let r = token.contentRange
            let upper = min(r.location + r.length, len)
            for i in max(r.location, 0)..<upper {
                traits[i] |= mask
            }
        }

        let regularBold = boldFont(in: ctx)

        var attrs: [StyledRange] = []
        var i = 0
        while i < len {
            let t = traits[i]
            if t == 0 { i += 1; continue }
            var j = i + 1
            while j < len && traits[j] == t { j += 1 }
            let range = NSRange(location: i, length: j - i)
            let wantsBold = (t & boldBit) != 0
            let wantsItalic = (t & italicBit) != 0
            var font = headingAwareFont(in: ctx, contentLocation: i, bold: wantsBold)
                ?? (wantsBold ? regularBold : ctx.baseFont)
            // The SF system font has no real italic face, and TextKit 2 ignores
            // the `.obliqueness` attribute, so shear the font itself to slant it.
            if wantsItalic {
                font = obliqueFont(font)
            }
            attrs.append((range, [.font: font]))
            i = j
        }
        return attrs
    }

    /// Produces a slanted (oblique) version of `base` by applying a shear to
    /// the font matrix, since SF has no italic face and TextKit 2 ignores the
    /// `.obliqueness` attribute.
    // Styling runs on the main thread, so a plain cache is safe and avoids
    // rebuilding a sheared font for every italic run on every restyle.
    private static var obliqueFontCache: [String: NSFont] = [:]

    private static func obliqueFont(_ base: NSFont) -> NSFont {
        let key = "\(base.fontName)|\(base.pointSize)"
        if let cached = obliqueFontCache[key] { return cached }
        // Unit-scale shear (keep the existing size from the descriptor); a
        // non-unit scale here would multiply the point size.
        let slant: CGFloat = 0.2
        let matrix = AffineTransform(m11: 1, m12: 0, m21: slant, m22: 1, tX: 0, tY: 0)
        let descriptor = base.fontDescriptor.addingAttributes([.matrix: matrix])
        let font = NSFont(descriptor: descriptor, size: base.pointSize) ?? base
        obliqueFontCache[key] = font
        return font
    }

    private static func boldFont(in ctx: StylingContext) -> NSFont {
        let desc = ctx.baseDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: desc, size: ctx.baseFont.pointSize)
            ?? NSFontManager.shared.convert(ctx.baseFont, toHaveTrait: .boldFontMask)
    }

    /// Returns a heading-sized font (optionally bold) when the location sits
    /// inside a heading, else `nil` so emphasis doesn't shrink mid-line. Italic
    /// is applied separately via obliqueness.
    private static func headingAwareFont(in ctx: StylingContext, contentLocation: Int, bold: Bool) -> NSFont? {
        guard let headingToken = ctx.tokens.first(where: {
            $0.kind == .heading && NSLocationInRange(contentLocation, $0.contentRange)
        }) else { return nil }
        let level = headingToken.markerRanges.first?.length ?? 1
        let multiplier = ctx.configuration.headings.fontMultiplier(for: level)
        let size = ctx.baseFont.pointSize * multiplier
        let headingBase = NSFont(name: ctx.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        guard bold else { return headingBase }
        let desc = headingBase.fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: desc, size: size)
            ?? NSFontManager.shared.convert(headingBase, toHaveTrait: .boldFontMask)
    }
}
