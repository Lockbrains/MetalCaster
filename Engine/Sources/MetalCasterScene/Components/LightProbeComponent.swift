import Foundation
import simd
import MetalCasterCore

/// A Light Probe captures indirect diffuse illumination at a point in space
/// using second-order Spherical Harmonics (L2, 9 coefficients per channel).
/// Dynamic objects interpolate between nearby probes to receive ambient lighting.
public struct LightProbeComponent: Component {

    public enum ProbeMode: String, CaseIterable, Codable, Sendable {
        case baked    = "Baked"
        case realtime = "Realtime"
    }

    /// Whether the probe uses baked or realtime SH data.
    public var mode: ProbeMode

    /// Influence radius — objects inside this sphere blend toward this probe.
    public var radius: Float

    /// Intensity multiplier for the probe's contribution.
    public var intensity: Float

    /// Second-order SH coefficients (9 per RGB channel = 27 floats total).
    /// Stored as three arrays of 9 coefficients for R, G, B.
    public var shCoefficientsR: [Float]
    public var shCoefficientsG: [Float]
    public var shCoefficientsB: [Float]

    /// Whether the probe has been baked at least once.
    public var isBaked: Bool

    /// Update interval in frames for realtime probes (0 = every frame).
    public var realtimeUpdateInterval: Int

    public init(
        mode: ProbeMode = .baked,
        radius: Float = 10.0,
        intensity: Float = 1.0,
        shCoefficientsR: [Float] = Array(repeating: 0, count: 9),
        shCoefficientsG: [Float] = Array(repeating: 0, count: 9),
        shCoefficientsB: [Float] = Array(repeating: 0, count: 9),
        isBaked: Bool = false,
        realtimeUpdateInterval: Int = 0
    ) {
        self.mode = mode
        self.radius = radius
        self.intensity = intensity
        self.shCoefficientsR = shCoefficientsR
        self.shCoefficientsG = shCoefficientsG
        self.shCoefficientsB = shCoefficientsB
        self.isBaked = isBaked
        self.realtimeUpdateInterval = realtimeUpdateInterval
    }
}
