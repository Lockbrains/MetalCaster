import Foundation
import MetalCasterCore
import MetalCasterRenderer

/// A single LOD level definition.
public struct LODLevel: Codable, Sendable {
    /// The mesh to use at this LOD level.
    public var meshType: MeshType

    /// Maximum distance from camera at which this LOD is active.
    /// The highest-detail LOD should have the smallest maxDistance.
    public var maxDistance: Float

    public init(meshType: MeshType, maxDistance: Float) {
        self.meshType = meshType
        self.maxDistance = maxDistance
    }
}

/// Enables automatic Level-of-Detail mesh switching based on camera distance.
///
/// LOD levels are sorted by distance — the system picks the first level whose
/// `maxDistance` exceeds the entity's distance from the camera. If no level
/// qualifies, the entity is culled (MeshComponent.meshType set to the last level).
public struct LODComponent: Component {
    /// Ordered LOD levels from highest detail (closest) to lowest (farthest).
    public var levels: [LODLevel]

    /// The currently active LOD index, updated by LODSystem each frame.
    public var activeLevelIndex: Int

    /// Whether distance-based culling is enabled (hide entity beyond max LOD distance).
    public var cullBeyondMaxDistance: Bool

    public init(levels: [LODLevel] = [], cullBeyondMaxDistance: Bool = false) {
        self.levels = levels.sorted { $0.maxDistance < $1.maxDistance }
        self.activeLevelIndex = 0
        self.cullBeyondMaxDistance = cullBeyondMaxDistance
    }
}
