import Foundation
import simd
import MetalCasterCore

/// Manages the entity hierarchy and provides scene-level queries.
///
/// The SceneGraph is a convenience layer on top of the ECS World.
/// It provides methods for building entity hierarchies and querying
/// the scene structure via `ParentComponent` / `ChildrenComponent`.
public final class SceneGraph {
    
    public let world: World
    
    public init(world: World) {
        self.world = world
    }
    
    /// Creates a new entity with a name and transform, optionally parented.
    @discardableResult
    public func createEntity(
        name: String,
        position: SIMD3<Float> = .zero,
        parent: Entity? = nil
    ) -> Entity {
        let entity = world.createEntity()
        world.addComponent(NameComponent(name: name), to: entity)
        world.addComponent(
            TransformComponent(position: position),
            to: entity
        )
        if let parent {
            world.addComponent(ParentComponent(parent), to: entity)
            appendChild(entity, to: parent)
        }
        return entity
    }
    
    /// Returns all root entities (entities with a transform but no parent).
    public func rootEntities() -> [Entity] {
        world.query(TransformComponent.self)
            .filter { !world.hasComponent(ParentComponent.self, on: $0.0) }
            .map { $0.0 }
    }
    
    /// Returns the children of a given entity in O(1).
    public func children(of parent: Entity) -> [Entity] {
        world.getComponent(ChildrenComponent.self, from: parent)?.entities ?? []
    }
    
    /// Returns the parent of a given entity, if any.
    public func parent(of entity: Entity) -> Entity? {
        world.getComponent(ParentComponent.self, from: entity)?.entity
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
        if let oldParent = parent(of: entity) {
            removeChild(entity, from: oldParent)
        }

        if let newParent {
            world.addComponent(ParentComponent(newParent), to: entity)
            appendChild(entity, to: newParent)
        } else {
            world.removeComponent(ParentComponent.self, from: entity)
        }
    }
    
    /// Destroys an entity and all its descendants.
    public func destroyEntityRecursive(_ entity: Entity) {
        for child in children(of: entity) {
            destroyEntityRecursive(child)
        }
        if let p = parent(of: entity) {
            removeChild(entity, from: p)
        }
        world.destroyEntity(entity)
    }
    
    /// Returns the name of an entity, or a fallback string.
    public func name(of entity: Entity) -> String {
        world.getComponent(NameComponent.self, from: entity)?.name ?? "Entity(\(entity.id))"
    }

    // MARK: - Internal helpers

    private func appendChild(_ child: Entity, to parent: Entity) {
        var cc = world.getComponent(ChildrenComponent.self, from: parent) ?? ChildrenComponent()
        if !cc.entities.contains(child) {
            cc.entities.append(child)
        }
        world.addComponent(cc, to: parent)
    }

    private func removeChild(_ child: Entity, from parent: Entity) {
        guard var cc = world.getComponent(ChildrenComponent.self, from: parent) else { return }
        cc.entities.removeAll { $0 == child }
        if cc.entities.isEmpty {
            world.removeComponent(ChildrenComponent.self, from: parent)
        } else {
            world.addComponent(cc, to: parent)
        }
    }
}
