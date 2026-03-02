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
///
/// Draw calls are sorted by render queue: opaque objects first (front-to-back
/// for overdraw reduction), then transparent objects (back-to-front for
/// correct blending).
public final class MeshRenderSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { 0 }
    
    /// Draw calls for the current frame, consumed by the renderer.
    /// Sorted by render queue order.
    public nonisolated(unsafe) var drawCalls: [DrawCall] = []

    /// Camera position used for distance-based sorting. Set by the render loop.
    public nonisolated(unsafe) var cameraPosition: SIMD3<Float> = .zero
    
    public init() {}
    
    public func update(context: UpdateContext) {
        let meshEntities = context.world.query(
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

        let camPos = cameraPosition
        calls.sort { a, b in
            let queueA = a.material.renderState.renderQueue.rawValue
            let queueB = b.material.renderState.renderQueue.rawValue
            if queueA != queueB { return queueA < queueB }

            let posA = SIMD3<Float>(a.worldMatrix.columns.3.x, a.worldMatrix.columns.3.y, a.worldMatrix.columns.3.z)
            let posB = SIMD3<Float>(b.worldMatrix.columns.3.x, b.worldMatrix.columns.3.y, b.worldMatrix.columns.3.z)
            let distA = simd_distance_squared(camPos, posA)
            let distB = simd_distance_squared(camPos, posB)

            if a.material.renderState.renderQueue == .transparent {
                return distA > distB
            }
            return distA < distB
        }
        
        drawCalls = calls
    }
}
