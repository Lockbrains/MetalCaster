import Foundation
import MetalCasterCore

/// Maintains consistency between `ParentComponent` and `ChildrenComponent`.
///
/// Runs before TransformSystem (priority -200) to ensure the hierarchy is
/// up-to-date before world matrices are propagated. On each frame it
/// rebuilds the `ChildrenComponent` cache from the authoritative
/// `ParentComponent` data, and cleans up stale references to dead entities.
public final class HierarchySystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -200 }

    public init() {}

    public func update(context: UpdateContext) {
        let world = context.world

        var parentOf: [Entity: Entity] = [:]
        var childrenOf: [Entity: [Entity]] = [:]

        for (child, pc) in world.query(ParentComponent.self) {
            guard world.isAlive(pc.entity) else {
                world.removeComponent(ParentComponent.self, from: child)
                continue
            }
            parentOf[child] = pc.entity
            childrenOf[pc.entity, default: []].append(child)
        }

        let allEntities = world.entities
        for entity in allEntities {
            if let expected = childrenOf[entity] {
                let existing = world.getComponent(ChildrenComponent.self, from: entity)
                if existing?.entities != expected {
                    world.addComponent(ChildrenComponent(expected), to: entity)
                }
            } else if world.hasComponent(ChildrenComponent.self, on: entity) {
                world.removeComponent(ChildrenComponent.self, from: entity)
            }
        }
    }
}
