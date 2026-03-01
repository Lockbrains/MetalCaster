import Foundation
import simd
import MetalCasterCore

/// Light source component.
public struct LightComponent: Component {
    public enum LightType: String, Codable, Sendable {
        case directional
        case point
        case spot
    }

    public var type: LightType

    /// Light color (RGB, not premultiplied).
    public var color: SIMD3<Float>

    /// Light intensity multiplier.
    public var intensity: Float

    /// Range for point and spot lights (0 = infinite for directional).
    public var range: Float

    /// Inner cone angle in radians (spot lights only).
    public var innerConeAngle: Float

    /// Outer cone angle in radians (spot lights only).
    public var outerConeAngle: Float

    /// Whether this light casts shadows.
    public var castsShadows: Bool

    public init(
        type: LightType = .directional,
        color: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        intensity: Float = 1.0,
        range: Float = 10.0,
        innerConeAngle: Float = 0.5,
        outerConeAngle: Float = 0.7,
        castsShadows: Bool = false
    ) {
        self.type = type
        self.color = color
        self.intensity = intensity
        self.range = range
        self.innerConeAngle = innerConeAngle
        self.outerConeAngle = outerConeAngle
        self.castsShadows = castsShadows
    }
}
