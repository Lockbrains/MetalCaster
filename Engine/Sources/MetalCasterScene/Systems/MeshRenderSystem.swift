import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// A renderable mesh draw call, produced by MeshRenderSystem for consumption by the renderer.
public struct DrawCall: Sendable {
    public let entity: Entity
    public let meshType: MeshType
    public let material: MCMaterial
    public let worldMatrix: simd_float4x4
    public let normalMatrix: simd_float4x4
    
    public init(entity: Entity, meshType: MeshType, material: MCMaterial, worldMatrix: simd_float4x4, normalMatrix: simd_float4x4) {
        self.entity = entity
        self.meshType = meshType
        self.material = material
        self.worldMatrix = worldMatrix
        self.normalMatrix = normalMatrix
    }
}

/// Queries entities with Transform + Mesh + Material and produces draw calls.
public final class MeshRenderSystem: System {
    public var isEnabled: Bool = true
    public var priority: Int { 0 }
    
    /// Draw calls for the current frame, consumed by the renderer.
    public private(set) var drawCalls: [DrawCall] = []
    
    public init() {}
    
    public func update(world: World, deltaTime: Float) {
        let meshEntities = world.query(
            TransformComponent.self,
            MeshComponent.self,
            MaterialComponent.self
        )
        
        var calls: [DrawCall] = []
        calls.reserveCapacity(meshEntities.count)
        
        for (entity, tc, mc, matC) in meshEntities {
            let worldMatrix = tc.worldMatrix
            let normalMatrix = simd_transpose(simd_inverse(worldMatrix))
            
            calls.append(DrawCall(
                entity: entity,
                meshType: mc.meshType,
                material: matC.material,
                worldMatrix: worldMatrix,
                normalMatrix: normalMatrix
            ))
        }
        
        drawCalls = calls
    }
}
