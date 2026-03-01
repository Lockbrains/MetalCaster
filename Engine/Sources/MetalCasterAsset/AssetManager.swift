import Foundation
import MetalCasterCore

/// Manages loading, caching, and hot-reloading of game assets.
///
/// The AssetManager provides a centralized registry for all asset types
/// (meshes, textures, shaders, scenes). Assets are loaded lazily and
/// cached for reuse.
public final class AssetManager: @unchecked Sendable {
    
    /// The root directory for project assets.
    public let projectRoot: URL?
    
    /// In-memory asset cache keyed by asset path.
    private var cache: [String: Any] = [:]
    
    /// Known asset file extensions and their types.
    public static let meshExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "obj"]
    public static let textureExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "exr", "hdr"]
    public static let sceneExtensions: Set<String> = ["mcscene"]
    
    public init(projectRoot: URL? = nil) {
        self.projectRoot = projectRoot
    }
    
    /// Resolves a relative asset path to an absolute URL.
    public func resolveURL(for relativePath: String) -> URL? {
        guard let root = projectRoot else { return nil }
        return root.appendingPathComponent(relativePath)
    }
    
    /// Caches a value for the given key.
    public func cacheAsset(_ asset: Any, forKey key: String) {
        cache[key] = asset
    }
    
    /// Retrieves a cached asset.
    public func cachedAsset<T>(forKey key: String) -> T? {
        cache[key] as? T
    }
    
    /// Removes a cached asset.
    public func removeCachedAsset(forKey key: String) {
        cache.removeValue(forKey: key)
    }
    
    /// Clears all cached assets.
    public func clearCache() {
        cache.removeAll()
    }
    
    /// Lists all asset files in the project root, recursively.
    public func listAssets(ofType extensions: Set<String>? = nil) -> [URL] {
        guard let root = projectRoot else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if let exts = extensions {
                if exts.contains(fileURL.pathExtension.lowercased()) {
                    results.append(fileURL)
                }
            } else {
                results.append(fileURL)
            }
        }
        return results
    }
}
