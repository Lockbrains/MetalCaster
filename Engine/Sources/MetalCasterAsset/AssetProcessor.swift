import Foundation
import MetalCasterCore
import MetalCasterRenderer
#if canImport(ModelIO)
import ModelIO
#endif

/// Processes imported assets: validates, optimizes, and generates Library cache entries.
public final class AssetProcessor: @unchecked Sendable {

    private let projectManager: ProjectManager

    public init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    // MARK: - Processing Dispatch

    /// Processes an asset after import. Returns true if processing succeeded.
    @discardableResult
    public func process(fileURL: URL, category: AssetCategory) -> Bool {
        switch category {
        case .meshes:
            return processMesh(at: fileURL)
        case .textures:
            return processTexture(at: fileURL)
        case .shaders:
            return processShader(at: fileURL)
        case .audio:
            return processAudio(at: fileURL)
        case .scenes, .materials, .prefabs:
            return validateJSON(at: fileURL, category: category)
        }
    }

    // MARK: - Mesh Processing

    private func processMesh(at url: URL) -> Bool {
        #if canImport(ModelIO)
        let asset = MDLAsset(url: url)
        guard asset.count > 0 else {
            print("[AssetProcessor] Invalid mesh file: \(url.lastPathComponent)")
            return false
        }
        return true
        #else
        return FileManager.default.fileExists(atPath: url.path)
        #endif
    }

    // MARK: - Texture Processing

    private func processTexture(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let validExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "exr", "hdr"]
        guard validExtensions.contains(ext) else {
            print("[AssetProcessor] Unsupported texture format: \(ext)")
            return false
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            print("[AssetProcessor] Empty or unreadable texture: \(url.lastPathComponent)")
            return false
        }

        return true
    }

    // MARK: - Shader Processing

    private func processShader(at url: URL) -> Bool {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("[AssetProcessor] Cannot read shader: \(url.lastPathComponent)")
            return false
        }

        let hasFunction = source.contains("vertex") || source.contains("fragment") || source.contains("kernel")
        if !hasFunction {
            print("[AssetProcessor] Shader has no vertex/fragment/kernel function: \(url.lastPathComponent)")
        }
        return true
    }

    // MARK: - Audio Processing

    private func processAudio(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let validExtensions: Set<String> = ["wav", "mp3", "aac", "m4a", "ogg"]
        guard validExtensions.contains(ext) else {
            print("[AssetProcessor] Unsupported audio format: \(ext)")
            return false
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > 0 else {
            print("[AssetProcessor] Empty audio file: \(url.lastPathComponent)")
            return false
        }

        return true
    }

    // MARK: - JSON Validation

    private func validateJSON(at url: URL, category: AssetCategory) -> Bool {
        let ext = url.pathExtension.lowercased()
        let jsonTypes: Set<String> = ["mcscene", "mcmat", "mcprefab"]
        guard jsonTypes.contains(ext) else { return true }

        guard let data = try? Data(contentsOf: url),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            print("[AssetProcessor] Invalid JSON in \(category.rawValue) file: \(url.lastPathComponent)")
            return false
        }
        return true
    }
}
