import Foundation

#if canImport(ModelIO) && canImport(SceneKit)
import ModelIO
import SceneKit

/// Converts 3D model files (OBJ, STL, PLY, DAE, FBX, USDZ, etc.) to USDA format.
///
/// Uses ModelIO as the primary pipeline. For formats not directly supported by
/// ModelIO (e.g. FBX, DAE), falls back to SceneKit for loading and then bridges
/// geometry through MDLMesh.
public final class ModelConverter {

    public enum ConversionError: LocalizedError {
        case unsupportedFormat(String)
        case loadFailed(URL)
        case exportFailed(URL)
        case fileNotFound(URL)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported format: .\(ext). Use Reality Converter for this format."
            case .loadFailed(let url):
                return "Failed to load model: \(url.lastPathComponent)"
            case .exportFailed(let url):
                return "Failed to export to: \(url.lastPathComponent)"
            case .fileNotFound(let url):
                return "File not found: \(url.path)"
            }
        }
    }

    /// Formats that ModelIO can load directly.
    private static let modelIOFormats: Set<String> = ["obj", "stl", "ply", "usd", "usda", "usdc", "usdz", "abc"]

    /// Formats that require SceneKit as a bridge loader.
    private static let sceneKitFormats: Set<String> = ["dae", "fbx", "scn"]

    /// All formats this converter can attempt to handle.
    public static let supportedExtensions: Set<String> = modelIOFormats.union(sceneKitFormats)

    public init() {}

    /// Converts a source 3D model file to USDA format.
    ///
    /// - Parameters:
    ///   - sourceURL: Path to the source model file.
    ///   - destinationURL: Path where the .usda file should be written.
    /// - Throws: `ConversionError` if the conversion fails.
    public func convert(from sourceURL: URL, to destinationURL: URL) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ConversionError.fileNotFound(sourceURL)
        }

        let ext = sourceURL.pathExtension.lowercased()

        if Self.modelIOFormats.contains(ext) {
            try convertViaModelIO(from: sourceURL, to: destinationURL)
        } else if Self.sceneKitFormats.contains(ext) {
            try convertViaSceneKit(from: sourceURL, to: destinationURL)
        } else {
            throw ConversionError.unsupportedFormat(ext)
        }
    }

    /// Whether a given file extension can be converted.
    public static func canConvert(_ fileExtension: String) -> Bool {
        supportedExtensions.contains(fileExtension.lowercased())
    }

    // MARK: - ModelIO Pipeline

    private func convertViaModelIO(from sourceURL: URL, to destinationURL: URL) throws {
        let asset = MDLAsset(url: sourceURL)
        guard asset.count > 0 else {
            throw ConversionError.loadFailed(sourceURL)
        }

        do {
            try asset.export(to: destinationURL)
        } catch {
            throw ConversionError.exportFailed(destinationURL)
        }
    }

    // MARK: - SceneKit Bridge Pipeline

    private func convertViaSceneKit(from sourceURL: URL, to destinationURL: URL) throws {
        guard let scene = try? SCNScene(url: sourceURL) else {
            throw ConversionError.loadFailed(sourceURL)
        }

        let success = scene.write(to: destinationURL, options: nil, delegate: nil, progressHandler: nil)
        guard success else {
            throw ConversionError.exportFailed(destinationURL)
        }
    }
}

#endif
