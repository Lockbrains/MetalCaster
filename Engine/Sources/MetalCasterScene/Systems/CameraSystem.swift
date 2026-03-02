import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// Computes view and projection matrices from the active camera entity.
///
/// Reads TransformComponent + CameraComponent to produce matrices
/// that are consumed by the rendering pipeline.
public final class CameraSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -90 }
    
    /// The computed view matrix from the active camera.
    public nonisolated(unsafe) var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    
    /// The computed projection matrix from the active camera.
    public nonisolated(unsafe) var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
    
    /// The active camera's world position.
    public nonisolated(unsafe) var cameraPosition: SIMD3<Float> = .zero
    
    /// The viewport aspect ratio (set externally by the renderer).
    public nonisolated(unsafe) var aspectRatio: Float = 16.0 / 9.0
    
    public init() {}
    
    public func update(world: World, deltaTime: Float) {
        let cameras = world.query(TransformComponent.self, CameraComponent.self)
        
        guard let (_, tc, cam) = cameras.first(where: { $0.2.isActive }) ?? cameras.first else {
            return
        }
        
        let worldMatrix = tc.worldMatrix
        let position = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)
        cameraPosition = position
        
        // Extract forward direction from world matrix (-Z)
        let forward = -SIMD3<Float>(worldMatrix.columns.2.x, worldMatrix.columns.2.y, worldMatrix.columns.2.z)
        let up = SIMD3<Float>(worldMatrix.columns.1.x, worldMatrix.columns.1.y, worldMatrix.columns.1.z)
        
        viewMatrix = matrix4x4LookAt(eye: position, target: position + forward, up: up)
        
        switch cam.projection {
        case .perspective:
            projectionMatrix = matrix4x4PerspectiveRightHand(
                fovyRadians: cam.fov,
                aspectRatio: aspectRatio,
                nearZ: cam.nearZ,
                farZ: cam.farZ
            )
        case .orthographic:
            let halfW = cam.orthoSize * aspectRatio
            let halfH = cam.orthoSize
            projectionMatrix = matrix4x4Orthographic(
                left: -halfW, right: halfW,
                bottom: -halfH, top: halfH,
                nearZ: cam.nearZ, farZ: cam.farZ
            )
        }
    }
}
