import Foundation
import simd
import MetalCasterCore

/// Computes world matrices for all entities with TransformComponent.
///
/// Traverses the entity hierarchy (via ParentComponent) and multiplies
/// parent world matrices with child local matrices to produce final
/// world-space transforms.
public final class TransformSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -100 }
    
    public init() {}
    
    public func update(context: UpdateContext) {
        let world = context.world
        let transforms = world.query(TransformComponent.self)
        
        var entityTransforms: [Entity: TransformComponent] = [:]
        var parentOf: [Entity: Entity] = [:]

        for (entity, tc) in transforms {
            entityTransforms[entity] = tc
        }

        for (entity, pc) in world.query(ParentComponent.self) {
            if entityTransforms[entity] != nil && entityTransforms[pc.entity] != nil {
                parentOf[entity] = pc.entity
            }
        }

        var computed: Set<Entity> = []
        for (entity, _) in transforms {
            computeWorldMatrix(entity: entity, entities: &entityTransforms, parentOf: parentOf, computed: &computed)
        }
        
        for (entity, tc) in entityTransforms {
            world.addComponent(tc, to: entity)
        }
    }
    
    private func computeWorldMatrix(
        entity: Entity,
        entities: inout [Entity: TransformComponent],
        parentOf: [Entity: Entity],
        computed: inout Set<Entity>
    ) {
        guard !computed.contains(entity) else { return }
        guard var tc = entities[entity] else { return }
        
        let localMatrix = tc.transform.matrix
        
        if let parent = parentOf[entity] {
            computeWorldMatrix(entity: parent, entities: &entities, parentOf: parentOf, computed: &computed)
            let parentWorldMatrix = entities[parent]?.worldMatrix ?? matrix_identity_float4x4
            tc.worldMatrix = parentWorldMatrix * localMatrix
        } else {
            tc.worldMatrix = localMatrix
        }
        
        entities[entity] = tc
        computed.insert(entity)
    }
}
