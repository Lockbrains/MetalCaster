import Foundation
import simd
import MetalCasterCore

/// Computes world matrices for all entities with TransformComponent.
///
/// Traverses the entity hierarchy and multiplies parent world matrices
/// with child local matrices to produce final world-space transforms.
public final class TransformSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -100 }
    
    public init() {}
    
    public func update(context: UpdateContext) {
        let world = context.world
        let transforms = world.query(TransformComponent.self)
        
        // Build parent lookup
        var entityTransforms: [Entity: TransformComponent] = [:]
        for (entity, tc) in transforms {
            entityTransforms[entity] = tc
        }
        
        // Find roots and compute world matrices
        var computed: Set<Entity> = []
        for (entity, _) in transforms {
            computeWorldMatrix(entity: entity, entities: &entityTransforms, computed: &computed)
        }
        
        // Write back
        for (entity, tc) in entityTransforms {
            world.addComponent(tc, to: entity)
        }
    }
    
    private func computeWorldMatrix(
        entity: Entity,
        entities: inout [Entity: TransformComponent],
        computed: inout Set<Entity>
    ) {
        guard !computed.contains(entity) else { return }
        guard var tc = entities[entity] else { return }
        
        let localMatrix = tc.transform.matrix
        
        if let parent = tc.parent, entities[parent] != nil {
            computeWorldMatrix(entity: parent, entities: &entities, computed: &computed)
            let parentWorldMatrix = entities[parent]?.worldMatrix ?? matrix_identity_float4x4
            tc.worldMatrix = parentWorldMatrix * localMatrix
        } else {
            tc.worldMatrix = localMatrix
        }
        
        entities[entity] = tc
        computed.insert(entity)
    }
}
