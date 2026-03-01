import Metal

/// Manages GPU texture and buffer resources, providing pooling and reuse.
///
/// Avoids redundant texture allocations by caching textures by size/format
/// and only reallocating when the viewport changes.
public final class ResourcePool {

    private let device: MTLDevice
    private var textureCache: [TextureKey: MTLTexture] = [:]

    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Texture Management

    /// Gets or creates an offscreen color texture of the given size.
    public func colorTexture(width: Int, height: Int, label: String = "color") -> MTLTexture? {
        let key = TextureKey(width: width, height: height, format: .bgra8Unorm, label: label)
        if let cached = textureCache[key], cached.width == width, cached.height == height {
            return cached
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.label = label
        textureCache[key] = texture
        return texture
    }

    /// Gets or creates a depth texture of the given size.
    public func depthTexture(width: Int, height: Int, label: String = "depth") -> MTLTexture? {
        let key = TextureKey(width: width, height: height, format: .depth32Float, label: label)
        if let cached = textureCache[key], cached.width == width, cached.height == height {
            return cached
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = .renderTarget
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.label = label
        textureCache[key] = texture
        return texture
    }

    /// Invalidates all cached textures, forcing reallocation on next use.
    public func invalidateAll() {
        textureCache.removeAll()
    }

    // MARK: - Internal

    private struct TextureKey: Hashable {
        let width: Int
        let height: Int
        let format: MTLPixelFormat
        let label: String
    }
}
