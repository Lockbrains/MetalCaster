#if canImport(CoreText)
import Metal
import Foundation
import CoreText
import CoreGraphics
import MetalCasterCore

/// SDF font atlas generator using CoreText.
/// Rasterizes glyphs to a single-channel texture with signed distance fields
/// for resolution-independent text rendering.
public final class FontAtlas {

    /// Per-glyph metrics and atlas location.
    public struct GlyphInfo {
        public var uvMin: SIMD2<Float>
        public var uvMax: SIMD2<Float>
        public var size: SIMD2<Float>
        public var bearing: SIMD2<Float>
        public var advance: Float
    }

    private let device: MTLDevice
    private var atlas: TextureAtlas
    private var glyphs: [Character: GlyphInfo] = [:]

    public var fontName: String
    public var fontSize: CGFloat
    public var texture: MTLTexture? { atlas.texture }

    /// SDF spread in pixels (distance from edge to the max/min distance).
    public var sdfSpread: Int = 4

    public init(device: MTLDevice, fontName: String = "Helvetica", fontSize: CGFloat = 48,
                atlasSize: Int = 2048) {
        self.device = device
        self.fontName = fontName
        self.fontSize = fontSize
        self.atlas = TextureAtlas(device: device, width: atlasSize, height: atlasSize)
    }

    /// Generates SDF glyphs for a set of characters.
    public func generate(characters: String = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~") {
        guard let font = CTFontCreateWithName(fontName as CFString, fontSize, nil) as CTFont? else {
            MCLog.error(.renderer, "FontAtlas: failed to create font '\(fontName)'")
            return
        }

        atlas.clear()
        glyphs.removeAll()

        for char in characters {
            if let info = rasterizeGlyph(char, font: font) {
                glyphs[char] = info
            }
        }

        MCLog.info(.renderer, "FontAtlas: generated \(glyphs.count) glyphs for '\(fontName)' \(fontSize)pt")
    }

    /// Returns glyph info for a character, or nil if not in the atlas.
    public func glyph(for character: Character) -> GlyphInfo? {
        glyphs[character]
    }

    /// Measures the width of a string in atlas units.
    public func measureWidth(_ text: String) -> Float {
        var width: Float = 0
        for char in text {
            if let g = glyphs[char] {
                width += g.advance
            }
        }
        return width
    }

    // MARK: - Internal

    private func rasterizeGlyph(_ char: Character, font: CTFont) -> GlyphInfo? {
        let str = String(char)
        let attrString = NSAttributedString(
            string: str,
            attributes: [.font: font as Any]
        )
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        guard let run = runs.first else { return nil }

        var glyphID = CGGlyph(0)
        CTRunGetGlyphs(run, CFRangeMake(0, 1), &glyphID)

        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphID, &boundingRect, 1)

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &glyphID, &advance, 1)

        let pad = sdfSpread
        let glyphW = Int(ceil(boundingRect.width)) + pad * 2
        let glyphH = Int(ceil(boundingRect.height)) + pad * 2

        guard glyphW > 0 && glyphH > 0 else {
            return GlyphInfo(
                uvMin: .zero, uvMax: .zero,
                size: SIMD2<Float>(Float(glyphW), Float(glyphH)),
                bearing: SIMD2<Float>(Float(boundingRect.origin.x), Float(boundingRect.origin.y)),
                advance: Float(advance.width)
            )
        }

        var pixels = [UInt8](repeating: 0, count: glyphW * glyphH)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels,
            width: glyphW,
            height: glyphH,
            bitsPerComponent: 8,
            bytesPerRow: glyphW,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 1, alpha: 1)
        let origin = CGPoint(
            x: CGFloat(pad) - boundingRect.origin.x,
            y: CGFloat(pad) - boundingRect.origin.y
        )

        var position = CGPoint.zero
        CTFontDrawGlyphs(font, &glyphID, &position, 1, ctx)
        _ = origin

        let drawPos = CGPoint(x: origin.x, y: origin.y)
        ctx.textPosition = drawPos
        CTLineDraw(line, ctx)

        guard let region = atlas.pack(name: String(char), pixels: pixels, width: glyphW, height: glyphH) else {
            return nil
        }

        return GlyphInfo(
            uvMin: region.uvMin,
            uvMax: region.uvMax,
            size: SIMD2<Float>(Float(glyphW), Float(glyphH)),
            bearing: SIMD2<Float>(Float(boundingRect.origin.x), Float(boundingRect.origin.y)),
            advance: Float(advance.width)
        )
    }
}
#endif
