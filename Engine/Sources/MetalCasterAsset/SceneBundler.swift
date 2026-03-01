import Foundation
import MetalCasterCore

// MARK: - BundleError

public enum BundleError: LocalizedError {
    case directoryCreationFailed(URL)
    case fileCopyFailed(source: URL, destination: URL, Error)
    case manifestWriteFailed(URL)
    case manifestReadFailed(URL)
    case manifestParseFailed(URL)
    case invalidBundleURL(URL)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let url):
            return "Failed to create directory: \(url.path)"
        case .fileCopyFailed(let src, let dst, let error):
            return "Failed to copy \(src.path) to \(dst.path): \(error.localizedDescription)"
        case .manifestWriteFailed(let url):
            return "Failed to write manifest to \(url.path)"
        case .manifestReadFailed(let url):
            return "Failed to read manifest from \(url.path)"
        case .manifestParseFailed(let url):
            return "Failed to parse manifest at \(url.path)"
        case .invalidBundleURL(let url):
            return "Invalid bundle URL: \(url.path)"
        }
    }
}

// MARK: - BundleMetadata

public struct BundleMetadata: Codable {
    public let engineVersion: String
    public let targetPlatform: String
    public let createdAt: Date
    public let bundleFormatVersion: Int

    public init(engineVersion: String, targetPlatform: String, createdAt: Date, bundleFormatVersion: Int = 1) {
        self.engineVersion = engineVersion
        self.targetPlatform = targetPlatform
        self.createdAt = createdAt
        self.bundleFormatVersion = bundleFormatVersion
    }
}

// MARK: - BundleConfig

public struct BundleConfig {
    public let sceneName: String
    public let sceneData: Data
    public let shaderLibraryURL: URL?
    public let textureURLs: [String: URL]
    public let meshURLs: [String: URL]
    public let metadata: BundleMetadata

    public init(
        sceneName: String,
        sceneData: Data,
        shaderLibraryURL: URL? = nil,
        textureURLs: [String: URL] = [:],
        meshURLs: [String: URL] = [:],
        metadata: BundleMetadata
    ) {
        self.sceneName = sceneName
        self.sceneData = sceneData
        self.shaderLibraryURL = shaderLibraryURL
        self.textureURLs = textureURLs
        self.meshURLs = meshURLs
        self.metadata = metadata
    }
}

// MARK: - BundleManifest

public struct BundleManifest: Codable {
    public let metadata: BundleMetadata
    public let sceneFile: String
    public let shaderLibrary: String?
    public let textures: [String: String]
    public let meshes: [String: String]

    public init(
        metadata: BundleMetadata,
        sceneFile: String,
        shaderLibrary: String? = nil,
        textures: [String: String] = [:],
        meshes: [String: String] = [:]
    ) {
        self.metadata = metadata
        self.sceneFile = sceneFile
        self.shaderLibrary = shaderLibrary
        self.textures = textures
        self.meshes = meshes
    }
}

// MARK: - BundleValidationIssue

public struct BundleValidationIssue {
    public enum Severity {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

// MARK: - SceneBundler

public final class SceneBundler {
    private let fileManager = FileManager.default

    public init() {}

    public func bundle(config: BundleConfig, to outputURL: URL) throws {
        let bundleDir = outputURL.pathExtension.lowercased() == "mcbundle"
            ? outputURL
            : outputURL.appendingPathComponent("\(config.sceneName).mcbundle", isDirectory: true)

        let shadersDir = bundleDir.appendingPathComponent("shaders", isDirectory: true)
        let texturesDir = bundleDir.appendingPathComponent("textures", isDirectory: true)
        let meshesDir = bundleDir.appendingPathComponent("meshes", isDirectory: true)

        try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: shadersDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: texturesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: meshesDir, withIntermediateDirectories: true)

        let sceneFile = "scene.mcscene"
        let sceneURL = bundleDir.appendingPathComponent(sceneFile)
        try config.sceneData.write(to: sceneURL)

        var shaderLibraryPath: String?
        if let shaderURL = config.shaderLibraryURL {
            let shaderFileName = shaderURL.lastPathComponent
            let destURL = shadersDir.appendingPathComponent(shaderFileName)
            try copyFile(from: shaderURL, to: destURL)
            shaderLibraryPath = "shaders/\(shaderFileName)"
        }

        var texturePaths: [String: String] = [:]
        for (assetName, sourceURL) in config.textureURLs {
            let fileName = sourceURL.lastPathComponent
            let destURL = texturesDir.appendingPathComponent(fileName)
            try copyFile(from: sourceURL, to: destURL)
            texturePaths[assetName] = "textures/\(fileName)"
        }

        var meshPaths: [String: String] = [:]
        for (assetName, sourceURL) in config.meshURLs {
            let fileName = sourceURL.lastPathComponent
            let destURL = meshesDir.appendingPathComponent(fileName)
            try copyFile(from: sourceURL, to: destURL)
            meshPaths[assetName] = "meshes/\(fileName)"
        }

        let manifest = BundleManifest(
            metadata: config.metadata,
            sceneFile: sceneFile,
            shaderLibrary: shaderLibraryPath,
            textures: texturePaths,
            meshes: meshPaths
        )

        let manifestURL = bundleDir.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData: Data
        do {
            manifestData = try encoder.encode(manifest)
        } catch {
            throw BundleError.manifestWriteFailed(manifestURL)
        }
        do {
            try manifestData.write(to: manifestURL)
        } catch {
            throw BundleError.manifestWriteFailed(manifestURL)
        }
    }

    public func loadBundle(from url: URL) throws -> BundleManifest {
        let bundleDir = url.pathExtension.lowercased() == "mcbundle"
            ? url
            : url.appendingPathComponent("\(url.lastPathComponent).mcbundle", isDirectory: true)

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw BundleError.invalidBundleURL(bundleDir)
        }

        let manifestURL = bundleDir.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BundleError.manifestReadFailed(manifestURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw BundleError.manifestReadFailed(manifestURL)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BundleManifest.self, from: data)
        } catch {
            throw BundleError.manifestParseFailed(manifestURL)
        }
    }

    public func validateBundle(at url: URL) throws -> [BundleValidationIssue] {
        var issues: [BundleValidationIssue] = []

        let bundleDir = url.pathExtension.lowercased() == "mcbundle"
            ? url
            : url.appendingPathComponent("\(url.lastPathComponent).mcbundle", isDirectory: true)

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleDir.path, isDirectory: &isDir), isDir.boolValue else {
            return [BundleValidationIssue(severity: .error, message: "Bundle directory does not exist at \(bundleDir.path)")]
        }

        let manifestURL = bundleDir.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return [BundleValidationIssue(severity: .error, message: "manifest.json not found")]
        }

        let manifest: BundleManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(BundleManifest.self, from: data)
        } catch {
            return [BundleValidationIssue(severity: .error, message: "manifest.json is not valid: \(error.localizedDescription)")]
        }

        let sceneURL = bundleDir.appendingPathComponent(manifest.sceneFile)
        if !fileManager.fileExists(atPath: sceneURL.path) {
            issues.append(BundleValidationIssue(severity: .error, message: "Scene file '\(manifest.sceneFile)' not found"))
        }

        if let shaderPath = manifest.shaderLibrary {
            let shaderURL = bundleDir.appendingPathComponent(shaderPath)
            if !fileManager.fileExists(atPath: shaderURL.path) {
                issues.append(BundleValidationIssue(severity: .error, message: "Shader library '\(shaderPath)' not found"))
            }
        }

        for (name, relativePath) in manifest.textures {
            let textureURL = bundleDir.appendingPathComponent(relativePath)
            if !fileManager.fileExists(atPath: textureURL.path) {
                issues.append(BundleValidationIssue(severity: .error, message: "Texture '\(name)' at '\(relativePath)' not found"))
            }
        }

        for (name, relativePath) in manifest.meshes {
            let meshURL = bundleDir.appendingPathComponent(relativePath)
            if !fileManager.fileExists(atPath: meshURL.path) {
                issues.append(BundleValidationIssue(severity: .error, message: "Mesh '\(name)' at '\(relativePath)' not found"))
            }
        }

        return issues
    }

    private func copyFile(from source: URL, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw BundleError.fileCopyFailed(source: source, destination: destination, error)
        }
    }
}
