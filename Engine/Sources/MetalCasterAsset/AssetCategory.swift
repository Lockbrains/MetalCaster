import Foundation

/// Fixed asset categories that define the top-level project directory structure.
/// Users cannot add or remove categories — only create subfolders within them.
public enum AssetCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case scenes    = "Scenes"
    case meshes    = "Meshes"
    case textures  = "Textures"
    case materials = "Materials"
    case shaders   = "Shaders"
    case audio     = "Audio"
    case prefabs   = "Prefabs"
    case gameplay  = "Gameplay"

    public var id: String { rawValue }

    public var directoryName: String { rawValue }

    public var icon: String {
        switch self {
        case .scenes:    return "film"
        case .meshes:    return "cube"
        case .textures:  return "photo"
        case .materials: return "paintpalette"
        case .shaders:   return "function"
        case .audio:     return "speaker.wave.2"
        case .prefabs:   return "square.on.square"
        case .gameplay:  return "swift"
        }
    }

    public var acceptedExtensions: Set<String> {
        switch self {
        case .scenes:    return ["usda", "mcscene", "mcmeta", "mcterrain"]
        case .meshes:    return ["usdz", "usd", "usda", "usdc", "obj", "stl", "ply", "abc", "dae", "fbx"]
        case .textures:  return ["png", "jpg", "jpeg", "tiff", "exr", "hdr"]
        case .materials: return ["mcmat"]
        case .shaders:   return ["metal"]
        case .audio:     return ["wav", "mp3", "aac", "m4a", "ogg"]
        case .prefabs:   return ["mcprefab"]
        case .gameplay:  return ["swift", "prompt"]
        }
    }

    /// File extensions recognized as 3D mesh files.
    public static let meshExtensions: Set<String> = ["usdz", "usd", "usda", "usdc", "obj", "stl", "ply", "abc", "dae", "fbx"]

    /// Detect the asset category from a file extension.
    public static func category(for fileExtension: String) -> AssetCategory? {
        let ext = fileExtension.lowercased()
        return allCases.first { $0.acceptedExtensions.contains(ext) }
    }
}

/// Represents a single asset entry visible in the Project Assets browser.
public struct AssetEntry: Identifiable, Sendable {
    public let guid: UUID
    public let name: String
    public let category: AssetCategory
    public let relativePath: String
    public let fileExtension: String
    public let fileSize: UInt64
    public let modifiedDate: Date
    public let isDirectory: Bool

    public var id: UUID { guid }

    public init(
        guid: UUID,
        name: String,
        category: AssetCategory,
        relativePath: String,
        fileExtension: String = "",
        fileSize: UInt64 = 0,
        modifiedDate: Date = Date(),
        isDirectory: Bool = false
    ) {
        self.guid = guid
        self.name = name
        self.category = category
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.modifiedDate = modifiedDate
        self.isDirectory = isDirectory
    }
}

/// Describes a change to the asset database for observation.
public enum AssetChange: Sendable {
    case added(AssetEntry)
    case removed(UUID)
    case modified(AssetEntry)
}
