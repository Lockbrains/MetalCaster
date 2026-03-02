import Foundation
import MetalCasterCore

/// Legacy asset manager retained for backward compatibility.
/// New code should use `AssetDatabase` instead.
///
/// Extension sets are still used by other parts of the engine for type detection.
public final class AssetManager: @unchecked Sendable {

    public let projectRoot: URL?

    public static let meshExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "obj"]
    public static let textureExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "exr", "hdr"]
    public static let sceneExtensions: Set<String> = ["mcscene"]
    public static let shaderExtensions: Set<String> = ["metal"]
    public static let audioExtensions: Set<String> = ["wav", "mp3", "aac", "m4a", "ogg"]
    public static let materialExtensions: Set<String> = ["mcmat"]
    public static let prefabExtensions: Set<String> = ["mcprefab"]

    public init(projectRoot: URL? = nil) {
        self.projectRoot = projectRoot
    }

    public func resolveURL(for relativePath: String) -> URL? {
        guard let root = projectRoot else { return nil }
        return root.appendingPathComponent(relativePath)
    }

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
