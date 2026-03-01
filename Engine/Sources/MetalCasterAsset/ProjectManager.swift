import Foundation
import MetalCasterCore

/// Manages project directory structure, metafiles, and asset tracking.
///
/// Project layout:
/// ```
/// MyProject.mcproject/
/// ├── project.json           (ProjectConfig)
/// ├── Scenes/
/// │   ├── default.mcscene
/// │   └── default.mcscene.meta
/// ├── Assets/
/// │   ├── Meshes/
/// │   │   ├── model.usdz
/// │   │   └── model.usdz.meta
/// │   └── Textures/
/// └── Library/               (cached/compiled data, not versioned)
/// ```
public final class ProjectManager: @unchecked Sendable {

    // MARK: - Types

    public struct ProjectConfig: Codable {
        public var name: String
        public var version: Int = 1
        public var engineVersion: String = "0.1.0"
        public var defaultScene: String = "Scenes/default.mcscene"
        public var createdAt: Date
        public var modifiedAt: Date

        public init(name: String) {
            self.name = name
            let now = Date()
            self.createdAt = now
            self.modifiedAt = now
        }
    }

    public struct AssetMeta: Codable {
        public let guid: UUID
        public var assetType: AssetType
        public var importSettings: [String: String]

        public init(assetType: AssetType, importSettings: [String: String] = [:]) {
            self.guid = UUID()
            self.assetType = assetType
            self.importSettings = importSettings
        }

        public enum AssetType: String, Codable {
            case mesh
            case texture
            case scene
            case shader
            case audio
            case other
        }
    }

    // MARK: - Properties

    public private(set) var projectRoot: URL?
    public private(set) var config: ProjectConfig?

    /// GUID → relative asset path mapping (built from scanning .meta files)
    private var guidToPath: [UUID: String] = [:]
    private var pathToGuid: [String: UUID] = [:]

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init() {}

    // MARK: - Project Lifecycle

    public func createProject(at url: URL, name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        let subdirs = ["Scenes", "Assets/Meshes", "Assets/Textures", "Assets/Shaders", "Assets/Audio", "Library"]
        for sub in subdirs {
            try fm.createDirectory(at: url.appendingPathComponent(sub), withIntermediateDirectories: true)
        }

        var cfg = ProjectConfig(name: name)
        cfg.modifiedAt = Date()
        let data = try encoder.encode(cfg)
        try data.write(to: url.appendingPathComponent("project.json"))

        self.projectRoot = url
        self.config = cfg
    }

    public func openProject(at url: URL) throws {
        let configURL = url.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ProjectError.notAProject(url)
        }
        let data = try Data(contentsOf: configURL)
        config = try decoder.decode(ProjectConfig.self, from: data)
        projectRoot = url
        scanMetafiles()
    }

    public func saveConfig() throws {
        guard let root = projectRoot, var cfg = config else { return }
        cfg.modifiedAt = Date()
        self.config = cfg
        let data = try encoder.encode(cfg)
        try data.write(to: root.appendingPathComponent("project.json"))
    }

    // MARK: - Asset Metafiles

    public func ensureMeta(for assetRelativePath: String, type: AssetMeta.AssetType) -> UUID {
        if let existing = pathToGuid[assetRelativePath] {
            return existing
        }

        guard let root = projectRoot else { return UUID() }
        let assetURL = root.appendingPathComponent(assetRelativePath)
        let metaURL = URL(fileURLWithPath: assetURL.path + ".meta")

        if let existingMeta = readMeta(at: metaURL) {
            register(guid: existingMeta.guid, path: assetRelativePath)
            return existingMeta.guid
        }

        let meta = AssetMeta(assetType: type)
        writeMeta(meta, to: metaURL)
        register(guid: meta.guid, path: assetRelativePath)
        return meta.guid
    }

    public func resolveGUID(_ guid: UUID) -> URL? {
        guard let root = projectRoot, let path = guidToPath[guid] else { return nil }
        return root.appendingPathComponent(path)
    }

    public func guidForAsset(relativePath: String) -> UUID? {
        pathToGuid[relativePath]
    }

    public func relativePathForGUID(_ guid: UUID) -> String? {
        guidToPath[guid]
    }

    // MARK: - Scanning

    public func scanMetafiles() {
        guidToPath.removeAll()
        pathToGuid.removeAll()
        guard let root = projectRoot else { return }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles]) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "meta" else { continue }
            if let meta = readMeta(at: fileURL) {
                let assetPath = String(fileURL.path.dropLast(5))
                if let relativePath = relativePath(for: URL(fileURLWithPath: assetPath), from: root) {
                    register(guid: meta.guid, path: relativePath)
                }
            }
        }
    }

    // MARK: - Helpers

    public func scenesDirectory() -> URL? {
        projectRoot?.appendingPathComponent("Scenes")
    }

    public func assetsDirectory() -> URL? {
        projectRoot?.appendingPathComponent("Assets")
    }

    public static func detectAssetType(extension ext: String) -> AssetMeta.AssetType {
        let lower = ext.lowercased()
        if AssetManager.meshExtensions.contains(lower) { return .mesh }
        if AssetManager.textureExtensions.contains(lower) { return .texture }
        if AssetManager.sceneExtensions.contains(lower) { return .scene }
        if lower == "metal" || lower == "msl" { return .shader }
        if ["wav", "mp3", "aac", "ogg", "m4a"].contains(lower) { return .audio }
        return .other
    }

    // MARK: - Private

    private func register(guid: UUID, path: String) {
        guidToPath[guid] = path
        pathToGuid[path] = guid
    }

    private func readMeta(at url: URL) -> AssetMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AssetMeta.self, from: data)
    }

    private func writeMeta(_ meta: AssetMeta, to url: URL) {
        guard let data = try? encoder.encode(meta) else { return }
        try? data.write(to: url)
    }

    private func relativePath(for url: URL, from base: URL) -> String? {
        let filePath = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path + "/"
        guard filePath.hasPrefix(basePath) else { return nil }
        return String(filePath.dropFirst(basePath.count))
    }
}

public enum ProjectError: LocalizedError {
    case notAProject(URL)
    case missingAsset(UUID)

    public var errorDescription: String? {
        switch self {
        case .notAProject(let url):
            return "Not a MetalCaster project: \(url.lastPathComponent)"
        case .missingAsset(let guid):
            return "Asset not found: \(guid)"
        }
    }
}
