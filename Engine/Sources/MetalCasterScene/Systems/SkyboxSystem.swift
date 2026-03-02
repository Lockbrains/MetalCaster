import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// Queries the scene for a SkyboxComponent and prepares skybox rendering data.
///
/// The renderer consumes `skyboxUniforms`, `hdriTexturePath`, and `isActive`
/// to draw the skybox before opaque geometry each frame.
public final class SkyboxSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { -85 }

    /// Whether a skybox entity exists and is active in the scene.
    public nonisolated(unsafe) var isActive: Bool = false

    /// Path to the HDRI texture for the active skybox (nil = use fallback gradient).
    public nonisolated(unsafe) var hdriTexturePath: String?

    /// Exposure multiplier for the HDRI.
    public nonisolated(unsafe) var exposure: Float = 1.0

    /// Y-axis rotation in radians.
    public nonisolated(unsafe) var rotation: Float = 0.0

    /// Pre-computed skybox uniforms for the current frame.
    public nonisolated(unsafe) var skyboxUniforms = SkyboxUniforms()

    public init() {}

    public func update(context: UpdateContext) {
        let skyboxes = context.world.query(SkyboxComponent.self)

        guard let (_, skybox) = skyboxes.first else {
            isActive = false
            return
        }

        isActive = true
        hdriTexturePath = skybox.hdriTexturePath
        exposure = skybox.exposure
        rotation = skybox.rotation
    }

    /// Computes the skybox view-projection matrix from camera data.
    /// Call this after CameraSystem has updated. The view matrix has its
    /// translation zeroed so the skybox appears infinitely far away.
    public func computeUniforms(viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4) {
        var viewNoTranslation = viewMatrix
        viewNoTranslation.columns.3 = SIMD4<Float>(0, 0, 0, 1)

        if rotation != 0 {
            let c = cos(rotation)
            let s = sin(rotation)
            let rotY = simd_float4x4(columns: (
                SIMD4<Float>(c, 0, s, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(-s, 0, c, 0),
                SIMD4<Float>(0, 0, 0, 1)
            ))
            viewNoTranslation = viewNoTranslation * rotY
        }

        skyboxUniforms = SkyboxUniforms(
            viewProjectionMatrix: projectionMatrix * viewNoTranslation
        )
    }
}
