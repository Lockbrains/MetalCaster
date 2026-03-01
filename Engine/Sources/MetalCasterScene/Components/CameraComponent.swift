import Foundation
import simd
import MetalCasterCore

/// Camera projection and viewport configuration.
public struct CameraComponent: Component {
    public enum Projection: String, Codable, Sendable {
        case perspective
        case orthographic
    }

    public var projection: Projection

    /// Vertical field of view in radians (perspective only).
    public var fov: Float

    /// Near clipping plane distance.
    public var nearZ: Float

    /// Far clipping plane distance.
    public var farZ: Float

    /// Orthographic size (half-height, orthographic only).
    public var orthoSize: Float

    /// Whether this is the active camera for rendering.
    public var isActive: Bool

    /// Background clear color (RGBA).
    public var clearColor: SIMD4<Float>

    public init(
        projection: Projection = .perspective,
        fov: Float = Float.pi / 3.0,
        nearZ: Float = 0.1,
        farZ: Float = 1000.0,
        orthoSize: Float = 10.0,
        isActive: Bool = true,
        clearColor: SIMD4<Float> = SIMD4<Float>(0.15, 0.15, 0.15, 1.0)
    ) {
        self.projection = projection
        self.fov = fov
        self.nearZ = nearZ
        self.farZ = farZ
        self.orthoSize = orthoSize
        self.isActive = isActive
        self.clearColor = clearColor
    }
}
