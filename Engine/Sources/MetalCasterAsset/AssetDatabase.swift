import Foundation
import MetalCasterCore

/// Unified asset access layer that bridges ProjectManager's file operations
/// with in-memory caching and observation.
public final class AssetDatabase: @unchecked Sendable {

    public let projectManager: ProjectManager

    private var cache: [UUID: Any] = [:]
    private var refCounts: [UUID: Int] = [:]
    private struct Observer {
        let id: UUID
        let handler: ([AssetChange]) -> Void
    }

    private var observers: [AssetCategory: [Observer]] = [:]

    public init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    // MARK: - Project Lifecycle

    public var isProjectOpen: Bool {
        projectManager.projectRoot != nil
    }

    public var projectName: String {
        projectManager.config?.name ?? "Untitled"
    }

    // MARK: - Browse

    /// Returns asset entries for a given category and optional subfolder.
    public func entries(
        in category: AssetCategory,
        subfolder: String? = nil
    ) -> [AssetEntry] {
        let (folders, files) = projectManager.listContents(in: category, subfolder: subfolder)
        var entries: [AssetEntry] = []

        let subPrefix = subfolder.map { $0 + "/" } ?? ""

        for folder in folders {
            let relativePath = "\(category.directoryName)/\(subPrefix)\(folder)"
            entries.append(AssetEntry(
                guid: UUID(),
                name: folder,
                category: category,
                relativePath: relativePath,
                isDirectory: true
            ))
        }

        for fileURL in files {
            let relativePath: String
            if let root = projectManager.projectRoot,
               let rel = projectManager.relativePath(for: fileURL, from: root) {
                relativePath = rel
            } else {
                relativePath = "\(category.directoryName)/\(subPrefix)\(fileURL.lastPathComponent)"
            }

            let guid = projectManager.guidForAsset(relativePath: relativePath)
                ?? projectManager.ensureMeta(for: relativePath, type: category)

            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = UInt64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate ?? Date()

            entries.append(AssetEntry(
                guid: guid,
                name: fileURL.deletingPathExtension().lastPathComponent,
                category: category,
                relativePath: relativePath,
                fileExtension: fileURL.pathExtension.lowercased(),
                fileSize: fileSize,
                modifiedDate: modDate,
                isDirectory: false
            ))
        }

        return entries
    }

    /// Returns the count of assets in a category.
    public func assetCount(in category: AssetCategory) -> Int {
        projectManager.assetCount(in: category)
    }

    // MARK: - Import

    /// Imports a file into the project under the appropriate category.
    /// Automatically detects the category from the file extension.
    @discardableResult
    public func importAsset(
        from sourceURL: URL,
        toCategory: AssetCategory? = nil,
        subfolder: String? = nil
    ) throws -> AssetEntry {
        let ext = sourceURL.pathExtension.lowercased()
        let category = toCategory ?? AssetCategory.category(for: ext) ?? .meshes

        let (destURL, guid) = try projectManager.importFile(
            from: sourceURL,
            to: category,
            subfolder: subfolder
        )

        let resourceValues = try? destURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

        let entry = AssetEntry(
            guid: guid,
            name: destURL.deletingPathExtension().lastPathComponent,
            category: category,
            relativePath: projectManager.relativePathForGUID(guid) ?? destURL.lastPathComponent,
            fileExtension: ext,
            fileSize: UInt64(resourceValues?.fileSize ?? 0),
            modifiedDate: resourceValues?.contentModificationDate ?? Date(),
            isDirectory: false
        )

        notifyObservers(category: category, changes: [.added(entry)])
        return entry
    }

    // MARK: - Delete / Rename

    public func deleteAsset(entry: AssetEntry) throws {
        try projectManager.deleteAsset(relativePath: entry.relativePath)
        cache.removeValue(forKey: entry.guid)
        refCounts.removeValue(forKey: entry.guid)
        notifyObservers(category: entry.category, changes: [.removed(entry.guid)])
    }

    public func renameAsset(entry: AssetEntry, newName: String) throws -> AssetEntry {
        let ext = entry.fileExtension.isEmpty ? "" : ".\(entry.fileExtension)"
        let newPath = try projectManager.renameAsset(
            relativePath: entry.relativePath,
            newName: newName + ext
        )

        let updated = AssetEntry(
            guid: entry.guid,
            name: newName,
            category: entry.category,
            relativePath: newPath,
            fileExtension: entry.fileExtension,
            fileSize: entry.fileSize,
            modifiedDate: Date(),
            isDirectory: false
        )

        notifyObservers(category: entry.category, changes: [.modified(updated)])
        return updated
    }

    // MARK: - Subfolder Management

    public func createSubfolder(named name: String, in category: AssetCategory, parentSubpath: String? = nil) throws {
        try projectManager.createSubfolder(named: name, in: category, parentSubpath: parentSubpath)
        let relPath = category.directoryName + "/" + (parentSubpath.map { $0 + "/" } ?? "") + name
        let folderEntry = AssetEntry(
            guid: UUID(),
            name: name,
            category: category,
            relativePath: relPath,
            isDirectory: true
        )
        notifyObservers(category: category, changes: [.added(folderEntry)])
    }

    /// Returns all non-directory asset entries recursively for a category.
    public func allEntries(in category: AssetCategory) -> [AssetEntry] {
        var result: [AssetEntry] = []
        collectEntries(in: category, subfolder: nil, into: &result)
        return result
    }

    private func collectEntries(in category: AssetCategory, subfolder: String?, into result: inout [AssetEntry]) {
        let items = entries(in: category, subfolder: subfolder)
        for entry in items {
            if entry.isDirectory {
                let sub = subfolder.map { $0 + "/" + entry.name } ?? entry.name
                collectEntries(in: category, subfolder: sub, into: &result)
            } else {
                result.append(entry)
            }
        }
    }

    // MARK: - Search

    public func search(query: String, category: AssetCategory? = nil) -> [AssetEntry] {
        let results = projectManager.searchAssets(query: query, category: category)
        return results.compactMap { (relPath, guid) -> AssetEntry? in
            let url = URL(fileURLWithPath: relPath)
            let ext = url.pathExtension.lowercased()
            guard let cat = AssetCategory.category(for: ext) else { return nil }
            return AssetEntry(
                guid: guid ?? UUID(),
                name: url.deletingPathExtension().lastPathComponent,
                category: cat,
                relativePath: relPath,
                fileExtension: ext,
                isDirectory: false
            )
        }
    }

    // MARK: - GUID Resolution

    public func resolveURL(for guid: UUID) -> URL? {
        projectManager.resolveGUID(guid)
    }

    // MARK: - Cache

    public func cacheAsset(_ asset: Any, forGUID guid: UUID) {
        cache[guid] = asset
    }

    public func cachedAsset<T>(forGUID guid: UUID) -> T? {
        cache[guid] as? T
    }

    public func retain(guid: UUID) {
        refCounts[guid, default: 0] += 1
    }

    public func release(guid: UUID) {
        guard let count = refCounts[guid] else { return }
        if count <= 1 {
            refCounts.removeValue(forKey: guid)
            cache.removeValue(forKey: guid)
        } else {
            refCounts[guid] = count - 1
        }
    }

    public func clearCache() {
        cache.removeAll()
        refCounts.removeAll()
    }

    // MARK: - Observation

    private let observerIDCounter = UnsafeMutablePointer<Int>.allocate(capacity: 1)

    public func observe(
        category: AssetCategory,
        handler: @escaping ([AssetChange]) -> Void
    ) -> UUID {
        let id = UUID()
        observers[category, default: []].append(Observer(id: id, handler: handler))
        return id
    }

    public func removeObserver(id: UUID) {
        for cat in AssetCategory.allCases {
            observers[cat]?.removeAll { $0.id == id }
        }
    }

    private func notifyObservers(category: AssetCategory, changes: [AssetChange]) {
        guard let handlers = observers[category] else { return }
        for observer in handlers {
            observer.handler(changes)
        }
    }

    // MARK: - Refresh

    /// Re-scans all metafiles and rebuilds the GUID mapping.
    public func refresh() {
        projectManager.scanMetafiles()
    }

    deinit {
        observerIDCounter.deallocate()
    }
}
