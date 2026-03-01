import Foundation
import simd
import MetalCasterCore

/// Manages the entity hierarchy and provides scene-level queries.
///
/// The SceneGraph is a convenience layer on top of the ECS World.
/// It provides methods for building entity hierarchies and querying
/// the scene structure.
public final class SceneGraph {
    
    public let world: World
    
    public init(world: World) {
        self.world = world
    }
    
    /// Creates a new entity with a name and transform.
    @discardableResult
    public func createEntity(
        name: String,
        position: SIMD3<Float> = .zero,
        parent: Entity? = nil
    ) -> Entity {
        let entity = world.createEntity()
        world.addComponent(NameComponent(name: name), to: entity)
        world.addComponent(
            TransformComponent(position: position, parent: parent),
            to: entity
        )
        return entity
    }
    
    /// Returns all root entities (entities with no parent).
    public func rootEntities() -> [Entity] {
        world.query(TransformComponent.self)
            .filter { $0.1.parent == nil }
            .map { $0.0 }
    }
    
    /// Returns the children of a given entity.
    public func children(of parent: Entity) -> [Entity] {
        world.query(TransformComponent.self)
            .filter { $0.1.parent == parent }
            .map { $0.0 }
    }
    
    /// Returns the full hierarchy depth-first, starting from roots.
    public func flattenedHierarchy() -> [(Entity, Int)] {
        var result: [(Entity, Int)] = []
        for root in rootEntities() {
            flattenRecursive(entity: root, depth: 0, into: &result)
        }
        return result
    }
    
    private func flattenRecursive(entity: Entity, depth: Int, into result: inout [(Entity, Int)]) {
        result.append((entity, depth))
        for child in children(of: entity) {
            flattenRecursive(entity: child, depth: depth + 1, into: &result)
        }
    }
    
    /// Reparents an entity under a new parent (or nil for root).
    public func setParent(_ entity: Entity, to newParent: Entity?) {
        guard var tc = world.getComponent(TransformComponent.self, from: entity) else { return }
        tc.parent = newParent
        world.addComponent(tc, to: entity)
    }
    
    /// Destroys an entity and all its descendants.
    public func destroyEntityRecursive(_ entity: Entity) {
        for child in children(of: entity) {
            destroyEntityRecursive(child)
        }
        world.destroyEntity(entity)
    }
    
    /// Returns the name of an entity, or a fallback string.
    public func name(of entity: Entity) -> String {
        world.getComponent(NameComponent.self, from: entity)?.name ?? "Entity(\(entity.id))"
    }
}
