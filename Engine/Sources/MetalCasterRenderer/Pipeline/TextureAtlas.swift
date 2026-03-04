import Metal
import simd

/// A texture atlas that packs multiple sub-images into a single GPU texture.
/// Used for sprite sheets, glyph atlases, and UI element batching.
public final class TextureAtlas {

    /// UV rectangle for a single sub-image within the atlas.
    public struct Region: Sendable {
        public var u: Float
        public var v: Float
        public var width: Float
        public var height: Float

        public var uvMin: SIMD2<Float> { SIMD2(u, v) }
        public var uvMax: SIMD2<Float> { SIMD2(u + width, v + height) }
    }

    private let device: MTLDevice
    public private(set) var texture: MTLTexture?
    public private(set) var atlasWidth: Int
    public private(set) var atlasHeight: Int

    private var regions: [String: Region] = [:]

    /// Current packing cursor.
    private var cursorX: Int = 0
    private var cursorY: Int = 0
    private var rowHeight: Int = 0

    public init(device: MTLDevice, width: Int = 2048, height: Int = 2048) {
        self.device = device
        self.atlasWidth = width
        self.atlasHeight = height

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        #if os(macOS)
        desc.storageMode = .managed
        #else
        desc.storageMode = .shared
        #endif
        self.texture = device.makeTexture(descriptor: desc)
        self.texture?.label = "TextureAtlas"
    }

    /// Packs a glyph bitmap into the atlas, returning its UV region.
    @discardableResult
    public func pack(name: String, pixels: [UInt8], width: Int, height: Int, padding: Int = 1) -> Region? {
        let pw = width + padding * 2
        let ph = height + padding * 2

        if cursorX + pw > atlasWidth {
            cursorX = 0
            cursorY += rowHeight + padding
            rowHeight = 0
        }

        guard cursorY + ph <= atlasHeight else { return nil }

        let region = MTLRegionMake2D(cursorX + padding, cursorY + padding, width, height)
        pixels.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            texture?.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width
            )
        }

        let uvRegion = Region(
            u: Float(cursorX + padding) / Float(atlasWidth),
            v: Float(cursorY + padding) / Float(atlasHeight),
            width: Float(width) / Float(atlasWidth),
            height: Float(height) / Float(atlasHeight)
        )

        regions[name] = uvRegion
        cursorX += pw
        rowHeight = max(rowHeight, ph)

        return uvRegion
    }

    /// Retrieves the UV region for a previously packed entry.
    public func region(for name: String) -> Region? {
        regions[name]
    }

    /// Resets the atlas for repacking.
    public func clear() {
        regions.removeAll()
        cursorX = 0
        cursorY = 0
        rowHeight = 0
    }
}
