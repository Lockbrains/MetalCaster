import Foundation
import MetalCasterCore
import MetalCasterScene

/// A lightweight organizational container for grouping entities in the Hierarchy panel.
/// Collections are purely a frontend concept — they do NOT create ECS entities or components,
/// and have zero impact on memory layout or archetypes.
public struct SceneCollection: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var memberEntityIDs: [UInt64]

    public init(name: String, memberEntityIDs: [UInt64] = []) {
        self.id = UUID()
        self.name = name
        self.memberEntityIDs = memberEntityIDs
    }

    /// Resolves live Entity handles from stored IDs, filtering out dead entities.
    public func liveMembers(in world: World) -> [Entity] {
        memberEntityIDs.compactMap { id in
            let entity = Entity(id: id)
            return world.isAlive(entity) ? entity : nil
        }
    }

    /// Snapshot member names for serialization (names survive entity ID remapping on load).
    public func memberNames(sceneGraph: SceneGraph) -> [String] {
        memberEntityIDs.map { id in
            sceneGraph.name(of: Entity(id: id))
        }
    }
}

/// Serialization wrapper that stores member names instead of raw entity IDs,
/// since IDs are not stable across save/load cycles.
public struct SceneCollectionData: Codable {
    public var id: UUID
    public var name: String
    public var memberNames: [String]
}

/// File-level container for all collections in a scene.
public struct SceneCollectionsFile: Codable {
    public var version: Int = 1
    public var collections: [SceneCollectionData] = []
}
