import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// Computes view and projection matrices from the active camera entity.
///
/// Reads TransformComponent + CameraComponent to produce matrices
/// that are consumed by the rendering pipeline. When physical camera
/// mode is active, derives FOV from sensor size + focal length and
/// outputs exposure/DoF parameters for post-processing.
public final class CameraSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -90 }
    
    // MARK: - Core Outputs

    public nonisolated(unsafe) var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    public nonisolated(unsafe) var projectionMatrix: simd_float4x4 = matrix_identity_float4x4
    public nonisolated(unsafe) var cameraPosition: SIMD3<Float> = .zero
    public nonisolated(unsafe) var aspectRatio: Float = 16.0 / 9.0

    // MARK: - Physical Camera Outputs

    public nonisolated(unsafe) var exposureValue: Float = 0
    public nonisolated(unsafe) var exposureMultiplier: Float = 1.0
    public nonisolated(unsafe) var focusDistance: Float = 10.0
    public nonisolated(unsafe) var apertureValue: Float = 2.8
    public nonisolated(unsafe) var focalLengthMM: Float = 50.0
    public nonisolated(unsafe) var sensorHeightMM: Float = 24.0
    public nonisolated(unsafe) var shutterSpeedValue: Float = 1.0 / 125.0
    public nonisolated(unsafe) var shutterAngleValue: Float = 180.0
    public nonisolated(unsafe) var nearZ: Float = 0.1
    public nonisolated(unsafe) var farZ: Float = 1000.0

    // MARK: - Rendering Flags

    public nonisolated(unsafe) var allowPostProcessing: Bool = true
    public nonisolated(unsafe) var allowHDR: Bool = true
    public nonisolated(unsafe) var usePhysicalProperties: Bool = false

    // MARK: - Motion Blur (previous frame VP)

    public nonisolated(unsafe) var viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4
    public nonisolated(unsafe) var previousViewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4

    // MARK: - Clear Color

    public nonisolated(unsafe) var clearColor: SIMD4<Float> = SIMD4<Float>(0.15, 0.15, 0.15, 1.0)

    public init() {}
    
    public func update(world: World, deltaTime: Float) {
        let cameras = world.query(TransformComponent.self, CameraComponent.self)
        
        guard let (_, tc, cam) = cameras.first(where: { $0.2.isActive }) ?? cameras.first else {
            return
        }
        
        let worldMatrix = tc.worldMatrix
        let position = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)
        cameraPosition = position

        let forward = -SIMD3<Float>(worldMatrix.columns.2.x, worldMatrix.columns.2.y, worldMatrix.columns.2.z)
        let up = SIMD3<Float>(worldMatrix.columns.1.x, worldMatrix.columns.1.y, worldMatrix.columns.1.z)
        
        viewMatrix = matrix4x4LookAt(eye: position, target: position + forward, up: up)
        
        let effectiveFOV = cam.effectiveFOV
        nearZ = cam.nearZ
        farZ = cam.farZ

        switch cam.projection {
        case .perspective:
            projectionMatrix = matrix4x4PerspectiveRightHand(
                fovyRadians: effectiveFOV,
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

        // Track VP for motion blur
        previousViewProjectionMatrix = viewProjectionMatrix
        viewProjectionMatrix = projectionMatrix * viewMatrix

        // Physical camera outputs
        usePhysicalProperties = cam.usePhysicalProperties
        exposureValue = cam.ev100
        exposureMultiplier = cam.exposureMultiplier
        focusDistance = cam.focusDistance
        apertureValue = cam.aperture
        focalLengthMM = cam.focalLength
        sensorHeightMM = cam.sensorSizeMM.y
        shutterSpeedValue = cam.shutterSpeed
        shutterAngleValue = cam.shutterAngle
        clearColor = cam.clearColor

        // Rendering flags
        allowPostProcessing = cam.allowPostProcessing
        allowHDR = cam.allowHDR
    }
}
