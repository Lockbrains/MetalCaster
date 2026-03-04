import Foundation
import MetalCasterCore

/// Manages project directory structure, metafiles, and asset tracking.
///
/// Project layout:
/// ```
/// MyGame.mcproject/
/// ├── project.json           (ProjectConfig)
/// ├── Scenes/
/// ├── Meshes/
/// ├── Textures/
/// ├── Materials/
/// ├── Shaders/
/// ├── Audio/
/// ├── Prefabs/
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
        public var buildSettings: BuildSettings?
        public var editorSnapshot: EditorSnapshot?

        public init(name: String) {
            self.name = name
            let now = Date()
            self.createdAt = now
            self.modifiedAt = now
        }
    }

    public struct BuildSettings: Codable {
        public var targetPlatforms: [String]
        public var optimizationLevel: String
        public var bundleIdentifier: String

        public init(
            targetPlatforms: [String] = ["macOS"],
            optimizationLevel: String = "debug",
            bundleIdentifier: String = "com.metalcaster.project"
        ) {
            self.targetPlatforms = targetPlatforms
            self.optimizationLevel = optimizationLevel
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public struct EditorSnapshot: Codable {
        public var lastOpenScene: String?
        public var selectedEntityID: UInt64?
        public var cameraYaw: Float?
        public var cameraPitch: Float?
        public var cameraDistance: Float?

        public init() {}
    }

    public struct AssetMeta: Codable {
        public let guid: UUID
        public var assetType: AssetCategory
        public var importSettings: [String: String]

        public init(assetType: AssetCategory, importSettings: [String: String] = [:]) {
            self.guid = UUID()
            self.assetType = assetType
            self.importSettings = importSettings
        }
    }

    // MARK: - Properties

    public private(set) var projectRoot: URL?
    public private(set) var config: ProjectConfig?

    /// GUID -> relative asset path mapping (built from scanning .meta files)
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

        var subdirs = AssetCategory.allCases.map(\.directoryName)
        subdirs.append("Gameplay/.generated")
        subdirs.append("Library")
        subdirs.append("Library/TextureCache")
        subdirs.append("Library/MeshCache")
        subdirs.append("Library/ShaderCache")
        subdirs.append("Library/Thumbnails")

        for sub in subdirs {
            try fm.createDirectory(
                at: url.appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }

        var cfg = ProjectConfig(name: name)
        cfg.modifiedAt = Date()
        cfg.buildSettings = BuildSettings()
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

        ensureCategoryDirectories()
        scanMetafiles()
    }

    public func saveConfig() throws {
        guard let root = projectRoot, var cfg = config else { return }
        cfg.modifiedAt = Date()
        self.config = cfg
        let data = try encoder.encode(cfg)
        try data.write(to: root.appendingPathComponent("project.json"))
    }

    public func updateEditorSnapshot(_ snapshot: EditorSnapshot) {
        config?.editorSnapshot = snapshot
        try? saveConfig()
    }

    // MARK: - Directory Access

    public func directoryURL(for category: AssetCategory) -> URL? {
        projectRoot?.appendingPathComponent(category.directoryName)
    }

    /// Returns the `.generated` directory inside `Gameplay/`, creating it if needed.
    public func generatedScriptsDirectory() -> URL? {
        guard let gameplayDir = directoryURL(for: .gameplay) else { return nil }
        let genDir = gameplayDir.appendingPathComponent(".generated")
        try? FileManager.default.createDirectory(at: genDir, withIntermediateDirectories: true)
        return genDir
    }

    /// Returns the expected generated Swift file URL for a given `.prompt` file URL.
    public func generatedScriptURL(for promptURL: URL) -> URL? {
        guard let genDir = generatedScriptsDirectory() else { return nil }
        let baseName = promptURL.deletingPathExtension().lastPathComponent
        let sanitized = baseName.replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return genDir.appendingPathComponent("\(sanitized).swift")
    }

    /// Checks whether a generated Swift file exists for the given `.prompt` URL.
    public func hasGeneratedScript(for promptURL: URL) -> Bool {
        guard let url = generatedScriptURL(for: promptURL) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func libraryDirectory() -> URL? {
        projectRoot?.appendingPathComponent("Library")
    }

    public func scenesDirectory() -> URL? {
        directoryURL(for: .scenes)
    }

    /// Creates a subfolder within a category directory.
    @discardableResult
    public func createSubfolder(named name: String, in category: AssetCategory, parentSubpath: String? = nil) throws -> URL {
        guard let categoryDir = directoryURL(for: category) else {
            throw ProjectError.noProjectOpen
        }
        var target = categoryDir
        if let sub = parentSubpath, !sub.isEmpty {
            target = target.appendingPathComponent(sub)
        }
        target = target.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    // MARK: - Asset Metafiles

    public func ensureMeta(for assetRelativePath: String, type: AssetCategory) -> UUID {
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

    public func allRegisteredGUIDs() -> [UUID: String] {
        guidToPath
    }

    // MARK: - Asset Listing

    /// Lists files and subfolders within a category directory.
    public func listContents(
        in category: AssetCategory,
        subfolder: String? = nil
    ) -> (folders: [String], files: [URL]) {
        guard let categoryDir = directoryURL(for: category) else { return ([], []) }

        var targetDir = categoryDir
        if let sub = subfolder, !sub.isEmpty {
            targetDir = targetDir.appendingPathComponent(sub)
        }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: targetDir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }

        var folders: [String] = []
        var files: [URL] = []

        for url in contents {
            if url.pathExtension == "meta" { continue }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                folders.append(url.lastPathComponent)
            } else {
                let ext = url.pathExtension.lowercased()
                if category.acceptedExtensions.contains(ext) {
                    files.append(url)
                }
            }
        }

        folders.sort()
        files.sort { $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending }
        return (folders, files)
    }

    /// Returns the count of assets (files only, recursive) in a category.
    public func assetCount(in category: AssetCategory) -> Int {
        guard let categoryDir = directoryURL(for: category) else { return 0 }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: categoryDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "meta" { continue }
            if category.acceptedExtensions.contains(ext) {
                count += 1
            }
        }
        return count
    }

    // MARK: - Asset Import

    /// Copies a file into the project under the correct category.
    @discardableResult
    public func importFile(
        from sourceURL: URL,
        to category: AssetCategory,
        subfolder: String? = nil
    ) throws -> (url: URL, guid: UUID) {
        guard let categoryDir = directoryURL(for: category) else {
            throw ProjectError.noProjectOpen
        }

        var targetDir = categoryDir
        if let sub = subfolder, !sub.isEmpty {
            targetDir = targetDir.appendingPathComponent(sub)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        var destinationURL = targetDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Avoid overwriting by appending a number
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            var counter = 1
            repeat {
                let newName = "\(stem)_\(counter).\(ext)"
                destinationURL = targetDir.appendingPathComponent(newName)
                counter += 1
            } while fm.fileExists(atPath: destinationURL.path)
        }

        try fm.copyItem(at: sourceURL, to: destinationURL)

        guard let root = projectRoot else {
            throw ProjectError.noProjectOpen
        }
        let relativePath = self.relativePath(for: destinationURL, from: root) ?? destinationURL.lastPathComponent
        let guid = ensureMeta(for: relativePath, type: category)

        return (destinationURL, guid)
    }

    /// Deletes an asset file and its .meta sidecar.
    public func deleteAsset(relativePath: String) throws {
        guard let root = projectRoot else { throw ProjectError.noProjectOpen }
        let fileURL = root.appendingPathComponent(relativePath)
        let metaURL = URL(fileURLWithPath: fileURL.path + ".meta")
        let fm = FileManager.default

        if let guid = pathToGuid[relativePath] {
            guidToPath.removeValue(forKey: guid)
        }
        pathToGuid.removeValue(forKey: relativePath)

        try? fm.removeItem(at: metaURL)
        try fm.removeItem(at: fileURL)
    }

    /// Renames an asset file and updates its .meta mapping.
    public func renameAsset(relativePath: String, newName: String) throws -> String {
        guard let root = projectRoot else { throw ProjectError.noProjectOpen }
        let oldURL = root.appendingPathComponent(relativePath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        let fm = FileManager.default

        let oldMetaURL = URL(fileURLWithPath: oldURL.path + ".meta")
        let newMetaURL = URL(fileURLWithPath: newURL.path + ".meta")

        try fm.moveItem(at: oldURL, to: newURL)
        if fm.fileExists(atPath: oldMetaURL.path) {
            try fm.moveItem(at: oldMetaURL, to: newMetaURL)
        }

        let newRelativePath = self.relativePath(for: newURL, from: root) ?? newName
        if let guid = pathToGuid.removeValue(forKey: relativePath) {
            guidToPath[guid] = newRelativePath
            pathToGuid[newRelativePath] = guid
        }

        return newRelativePath
    }

    /// Moves an asset file from its current directory into a different folder within the same category.
    public func moveAsset(relativePath: String, toFolder folderRelativePath: String) throws -> String {
        guard let root = projectRoot else { throw ProjectError.noProjectOpen }
        let fm = FileManager.default
        let sourceURL = root.appendingPathComponent(relativePath)
        let destDir = root.appendingPathComponent(folderRelativePath)

        if !fm.fileExists(atPath: destDir.path) {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        try fm.moveItem(at: sourceURL, to: destURL)

        let oldMetaURL = URL(fileURLWithPath: sourceURL.path + ".meta")
        let newMetaURL = URL(fileURLWithPath: destURL.path + ".meta")
        if fm.fileExists(atPath: oldMetaURL.path) {
            try fm.moveItem(at: oldMetaURL, to: newMetaURL)
        }

        let newRelativePath = self.relativePath(for: destURL, from: root) ?? destURL.lastPathComponent
        if let guid = pathToGuid.removeValue(forKey: relativePath) {
            guidToPath[guid] = newRelativePath
            pathToGuid[newRelativePath] = guid
        }

        return newRelativePath
    }

    // MARK: - Scanning

    public func scanMetafiles() {
        guidToPath.removeAll()
        pathToGuid.removeAll()
        guard let root = projectRoot else { return }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "meta" else { continue }
            if let meta = readMeta(at: fileURL) {
                let assetPath = String(fileURL.path.dropLast(5)) // drop ".meta"
                if let relPath = relativePath(for: URL(fileURLWithPath: assetPath), from: root) {
                    register(guid: meta.guid, path: relPath)
                }
            }
        }
    }

    // MARK: - Search

    /// Searches across all categories (or a specific one) for assets matching a query.
    public func searchAssets(query: String, category: AssetCategory? = nil) -> [(relativePath: String, guid: UUID?)] {
        guard projectRoot != nil else { return [] }
        let lowerQuery = query.lowercased()
        let categories = category.map { [$0] } ?? AssetCategory.allCases

        var results: [(String, UUID?)] = []
        for cat in categories {
            let (folders, files) = listContents(in: cat)
            for file in files {
                if file.lastPathComponent.lowercased().contains(lowerQuery) {
                    let relPath = "\(cat.directoryName)/\(file.lastPathComponent)"
                    results.append((relPath, pathToGuid[relPath]))
                }
            }
            for folder in folders {
                searchRecursive(
                    category: cat,
                    subfolder: folder,
                    query: lowerQuery,
                    results: &results
                )
            }
        }
        return results
    }

    private func searchRecursive(
        category: AssetCategory,
        subfolder: String,
        query: String,
        results: inout [(String, UUID?)]
    ) {
        let (folders, files) = listContents(in: category, subfolder: subfolder)
        for file in files {
            if file.lastPathComponent.lowercased().contains(query) {
                let relPath = "\(category.directoryName)/\(subfolder)/\(file.lastPathComponent)"
                results.append((relPath, pathToGuid[relPath]))
            }
        }
        for folder in folders {
            searchRecursive(
                category: category,
                subfolder: "\(subfolder)/\(folder)",
                query: query,
                results: &results
            )
        }
    }

    // MARK: - Helpers (Public)

    public static func detectCategory(forExtension ext: String) -> AssetCategory? {
        AssetCategory.category(for: ext)
    }

    // MARK: - Private

    private func ensureCategoryDirectories() {
        guard let root = projectRoot else { return }
        let fm = FileManager.default
        for cat in AssetCategory.allCases {
            let dir = root.appendingPathComponent(cat.directoryName)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? fm.createDirectory(
            at: root.appendingPathComponent("Gameplay/.generated"),
            withIntermediateDirectories: true
        )
        let libraryDirs = ["Library", "Library/TextureCache", "Library/MeshCache", "Library/ShaderCache", "Library/Thumbnails"]
        for dir in libraryDirs {
            try? fm.createDirectory(
                at: root.appendingPathComponent(dir),
                withIntermediateDirectories: true
            )
        }
    }

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

    public func relativePath(for url: URL, from base: URL) -> String? {
        let filePath = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path + "/"
        guard filePath.hasPrefix(basePath) else { return nil }
        return String(filePath.dropFirst(basePath.count))
    }
}

public enum ProjectError: LocalizedError {
    case notAProject(URL)
    case missingAsset(UUID)
    case noProjectOpen

    public var errorDescription: String? {
        switch self {
        case .notAProject(let url):
            return "Not a MetalCaster project: \(url.lastPathComponent)"
        case .missingAsset(let guid):
            return "Asset not found: \(guid)"
        case .noProjectOpen:
            return "No project is currently open"
        }
    }
}
