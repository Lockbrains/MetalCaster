import Foundation
import simd
import MetalCasterScene
import MetalCasterCore

// MARK: - Composer Tool Mode

enum ComposerToolMode: String, CaseIterable, Identifiable {
    case terrain    = "Terrain"
    case vegetation = "Vegetation"
    case water      = "Water"
    case atmosphere = "Atmosphere"
    case objects    = "Objects"
    case brush      = "Brush"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .terrain:    return "mountain.2"
        case .vegetation: return "leaf"
        case .water:      return "drop"
        case .atmosphere: return "cloud.sun"
        case .objects:    return "cube"
        case .brush:      return "paintbrush.pointed"
        }
    }
}

// MARK: - Brush Mode

enum ComposerBrushMode: String, CaseIterable, Identifiable {
    case raise    = "Raise"
    case lower    = "Lower"
    case smooth   = "Smooth"
    case flatten  = "Flatten"
    case slope    = "Slope"
    case erode    = "Erode"
    case stamp    = "Stamp"
    case paint    = "Paint"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .raise:   return "arrow.up"
        case .lower:   return "arrow.down"
        case .smooth:  return "wand.and.rays"
        case .flatten: return "rectangle.compress.vertical"
        case .slope:   return "line.diagonal"
        case .erode:   return "water.waves"
        case .stamp:   return "seal"
        case .paint:   return "paintbrush"
        }
    }
}

// MARK: - Brush Settings

struct ComposerBrushSettings {
    var radius: Float = 50
    var strength: Float = 0.5
    var falloff: Float = 0.5
    var mode: ComposerBrushMode = .raise
}

// MARK: - Composer Layer

struct ComposerLayer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: LayerKind
    var isVisible: Bool
    var isLocked: Bool

    enum LayerKind: String, CaseIterable {
        case terrain    = "Terrain"
        case vegetation = "Vegetation"
        case water      = "Water"
        case atmosphere = "Atmosphere"
        case objects    = "Objects"
    }

    init(name: String, kind: LayerKind) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.isVisible = true
        self.isLocked = false
    }
}

// MARK: - Spatial Coordinate Mode (for AI interaction)

enum SpatialCoordinateMode: String, CaseIterable, Identifiable, Codable {
    case screenSpace  = "Screen"
    case worldSpace   = "World"
    case objectSpace  = "Object"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .screenSpace: return "display"
        case .worldSpace:  return "globe"
        case .objectSpace: return "cube"
        }
    }
}

// MARK: - Inline Prompt Context

enum InlinePromptContext: Equatable {
    case entity(UInt64, String)
    case terrainPoint(SIMD3<Float>)
    case sceneGlobal

    var displayLabel: String {
        switch self {
        case .entity(_, let name):
            return name
        case .terrainPoint(let pos):
            return String(format: "Terrain (%.0f, %.0f, %.0f)", pos.x, pos.y, pos.z)
        case .sceneGlobal:
            return "Scene Global"
        }
    }

    var isEntity: Bool {
        if case .entity = self { return true }
        return false
    }

    var isTerrainPoint: Bool {
        if case .terrainPoint = self { return true }
        return false
    }

    static func == (lhs: InlinePromptContext, rhs: InlinePromptContext) -> Bool {
        switch (lhs, rhs) {
        case (.sceneGlobal, .sceneGlobal):
            return true
        case (.entity(let a, _), .entity(let b, _)):
            return a == b
        case (.terrainPoint(let a), .terrainPoint(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Composition Plan

struct CompositionPlan: Codable, Identifiable {
    let id: UUID
    var title: String
    var description: String
    var stages: [PlanStage]
    var status: PlanStatus

    enum PlanStatus: String, Codable {
        case draft     = "Draft"
        case confirmed = "Confirmed"
        case executing = "Executing"
        case completed = "Completed"
        case failed    = "Failed"
    }

    struct PlanStage: Codable, Identifiable {
        let id: UUID
        var order: Int
        var name: String
        var description: String
        var requiredAssets: [AssetRequirement]
        var status: StageStatus

        enum StageStatus: String, Codable {
            case pending   = "Pending"
            case running   = "Running"
            case completed = "Completed"
            case failed    = "Failed"
        }

        init(order: Int, name: String, description: String, requiredAssets: [AssetRequirement] = []) {
            self.id = UUID()
            self.order = order
            self.name = name
            self.description = description
            self.requiredAssets = requiredAssets
            self.status = .pending
        }
    }

    struct AssetRequirement: Codable, Identifiable {
        let id: UUID
        var name: String
        var assetType: AssetType
        var source: AssetSource
        var referencePrompt: String?

        enum AssetType: String, Codable { case mesh, texture, material }
        enum AssetSource: String, Codable { case userProvided, aiGenerated, library }

        init(name: String, assetType: AssetType, source: AssetSource, referencePrompt: String? = nil) {
            self.id = UUID()
            self.name = name
            self.assetType = assetType
            self.source = source
            self.referencePrompt = referencePrompt
        }
    }

    init(title: String, description: String, stages: [PlanStage] = []) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.stages = stages
        self.status = .draft
    }
}

// MARK: - Scene Composer Document

struct SceneComposerDocument: Codable {
    var version: Int = 1
    var name: String
    var terrain: TerrainComponent?
    var vegetation: VegetationComponent?
    var waterBodies: [WaterBodyComponent]
    var layers: [ComposerLayerData]
    var cameraYaw: Float
    var cameraPitch: Float
    var cameraDistance: Float
    var spatialMode: SpatialCoordinateMode

    struct ComposerLayerData: Codable {
        var name: String
        var kind: String
        var isVisible: Bool
        var isLocked: Bool
    }

    init(name: String = "Untitled") {
        self.name = name
        self.terrain = nil
        self.vegetation = nil
        self.waterBodies = []
        self.layers = []
        self.cameraYaw = 0.5
        self.cameraPitch = 0.4
        self.cameraDistance = 200
        self.spatialMode = .screenSpace
    }
}
