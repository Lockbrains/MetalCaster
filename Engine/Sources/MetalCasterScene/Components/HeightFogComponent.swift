import Foundation
import simd
import MetalCasterCore

/// Height-based atmospheric fog that increases density below a configurable altitude.
/// Designed as a full-scene effect — typically one per scene attached to a dedicated entity.
public struct HeightFogComponent: Component {

    public enum FogMode: String, CaseIterable, Codable, Sendable {
        case exponential  = "Exponential"
        case exponentialSquared = "Exponential²"
    }

    /// Fog falloff mode.
    public var mode: FogMode

    /// Fog color (RGB, linear space).
    public var color: SIMD3<Float>

    /// Base density at the fog plane.
    public var density: Float

    /// World-space Y coordinate of the fog base plane.
    public var baseHeight: Float

    /// Controls how quickly fog density decreases above baseHeight.
    /// Higher values = thinner fog above the plane.
    public var heightFalloff: Float

    /// Maximum fog opacity (0–1). Prevents fully opaque fog at extreme distances.
    public var maxOpacity: Float

    /// Distance from camera at which fog begins to appear.
    public var startDistance: Float

    /// Optional directional scattering toward a light source.
    public var inscatteringColor: SIMD3<Float>

    /// Intensity of the inscattering effect (Mie-like forward scattering).
    public var inscatteringIntensity: Float

    /// Exponent controlling the tightness of the inscattering cone.
    public var inscatteringExponent: Float

    /// Whether volumetric fog is enabled (more expensive, uses ray marching).
    public var volumetricEnabled: Bool

    /// Number of ray march steps for volumetric fog.
    public var volumetricSteps: Int

    public init(
        mode: FogMode = .exponential,
        color: SIMD3<Float> = SIMD3<Float>(0.6, 0.65, 0.75),
        density: Float = 0.02,
        baseHeight: Float = 0.0,
        heightFalloff: Float = 0.2,
        maxOpacity: Float = 1.0,
        startDistance: Float = 0.0,
        inscatteringColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.9, 0.7),
        inscatteringIntensity: Float = 0.0,
        inscatteringExponent: Float = 8.0,
        volumetricEnabled: Bool = false,
        volumetricSteps: Int = 64
    ) {
        self.mode = mode
        self.color = color
        self.density = density
        self.baseHeight = baseHeight
        self.heightFalloff = heightFalloff
        self.maxOpacity = maxOpacity
        self.startDistance = startDistance
        self.inscatteringColor = inscatteringColor
        self.inscatteringIntensity = inscatteringIntensity
        self.inscatteringExponent = inscatteringExponent
        self.volumetricEnabled = volumetricEnabled
        self.volumetricSteps = volumetricSteps
    }
}
