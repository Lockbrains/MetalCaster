import Metal
import MetalKit
import Foundation
import MetalCasterCore

/// Thread-safe GPU texture cache with reference counting and automatic eviction.
/// Avoids redundant texture loads by caching by file path.
public final class TextureCache: @unchecked Sendable {

    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    private let lock = NSLock()

    private var cache: [String: CacheEntry] = [:]

    /// Maximum number of textures before LRU eviction begins.
    public var maxTextures: Int = 512

    public init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }

    // MARK: - Synchronous Load

    /// Loads or retrieves a cached texture from a file URL.
    public func texture(for url: URL, sRGB: Bool = true, generateMipmaps: Bool = true) -> MTLTexture? {
        let key = url.absoluteString
        lock.lock()
        if let entry = cache[key] {
            cache[key]?.lastAccess = Date()
            cache[key]?.refCount += 1
            lock.unlock()
            return entry.texture
        }
        lock.unlock()

        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: sRGB,
            .generateMipmaps: generateMipmaps,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]

        guard let texture = try? textureLoader.newTexture(URL: url, options: options) else {
            MCLog.warning(.renderer, "TextureCache: failed to load \(url.lastPathComponent)")
            return nil
        }

        lock.lock()
        cache[key] = CacheEntry(texture: texture)
        evictIfNeeded()
        lock.unlock()

        MCLog.debug(.renderer, "TextureCache: loaded \(url.lastPathComponent)")
        return texture
    }

    /// Loads or retrieves a cached texture from raw data.
    public func texture(forKey key: String, data: Data, sRGB: Bool = true) -> MTLTexture? {
        lock.lock()
        if let entry = cache[key] {
            cache[key]?.lastAccess = Date()
            lock.unlock()
            return entry.texture
        }
        lock.unlock()

        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: sRGB,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]

        guard let texture = try? textureLoader.newTexture(data: data, options: options) else { return nil }

        lock.lock()
        cache[key] = CacheEntry(texture: texture)
        evictIfNeeded()
        lock.unlock()

        return texture
    }

    /// Creates or retrieves a 1x1 solid color texture.
    public func solidColor(r: Float, g: Float, b: Float, a: Float = 1) -> MTLTexture? {
        let key = "solid_\(r)_\(g)_\(b)_\(a)"
        lock.lock()
        if let entry = cache[key] {
            cache[key]?.lastAccess = Date()
            lock.unlock()
            return entry.texture
        }
        lock.unlock()

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        desc.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        var pixels: [UInt8] = [
            UInt8(min(max(r, 0), 1) * 255),
            UInt8(min(max(g, 0), 1) * 255),
            UInt8(min(max(b, 0), 1) * 255),
            UInt8(min(max(a, 0), 1) * 255)
        ]
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: 4
        )

        lock.lock()
        cache[key] = CacheEntry(texture: texture)
        lock.unlock()

        return texture
    }

    // MARK: - Management

    /// Releases a texture reference. The texture will be evicted when ref count hits 0 and cache is full.
    public func release(key: String) {
        lock.lock()
        if var entry = cache[key] {
            entry.refCount = max(0, entry.refCount - 1)
            cache[key] = entry
        }
        lock.unlock()
    }

    /// Removes all cached textures.
    public func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    // MARK: - Internal

    private func evictIfNeeded() {
        while cache.count > maxTextures {
            let evictable = cache.filter { $0.value.refCount <= 0 }
            guard let oldest = evictable.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            cache.removeValue(forKey: oldest.key)
            MCLog.debug(.renderer, "TextureCache: evicted \(oldest.key)")
        }
    }

    private struct CacheEntry {
        let texture: MTLTexture
        var refCount: Int = 1
        var lastAccess: Date = Date()
    }
}
