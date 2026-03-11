import Foundation
import simd
import MetalCasterCore

/// A Reflection Probe captures the surrounding environment into a cubemap
/// that is sampled for specular reflections on nearby surfaces.
public struct ReflectionProbeComponent: Component {

    public enum ProbeType: String, CaseIterable, Codable, Sendable {
        case baked    = "Baked"
        case realtime = "Realtime"
    }

    public enum ProbeShape: String, CaseIterable, Codable, Sendable {
        case sphere = "Sphere"
        case box    = "Box"
    }

    /// Whether the cubemap is baked or rendered each frame.
    public var probeType: ProbeType

    /// Influence volume shape.
    public var shape: ProbeShape

    /// Cubemap resolution (each face).
    public var resolution: Int

    /// Influence radius (sphere) or half-extents (box).
    public var radius: Float
    public var boxExtents: SIMD3<Float>

    /// HDR intensity multiplier.
    public var intensity: Float

    /// Path to the baked cubemap asset (nil until baked).
    public var bakedCubemapPath: String?

    /// Blend distance for smooth transitions between probes.
    public var blendDistance: Float

    /// Priority when multiple probes overlap (higher wins).
    public var priority: Int

    /// Whether the probe has valid baked data.
    public var isBaked: Bool

    /// Realtime update interval in frames (0 = every frame).
    public var realtimeUpdateInterval: Int

    /// Near/far clip for cubemap capture.
    public var nearClip: Float
    public var farClip: Float

    public init(
        probeType: ProbeType = .baked,
        shape: ProbeShape = .box,
        resolution: Int = 256,
        radius: Float = 10.0,
        boxExtents: SIMD3<Float> = SIMD3<Float>(5, 5, 5),
        intensity: Float = 1.0,
        bakedCubemapPath: String? = nil,
        blendDistance: Float = 1.0,
        priority: Int = 0,
        isBaked: Bool = false,
        realtimeUpdateInterval: Int = 0,
        nearClip: Float = 0.1,
        farClip: Float = 100.0
    ) {
        self.probeType = probeType
        self.shape = shape
        self.resolution = resolution
        self.radius = radius
        self.boxExtents = boxExtents
        self.intensity = intensity
        self.bakedCubemapPath = bakedCubemapPath
        self.blendDistance = blendDistance
        self.priority = priority
        self.isBaked = isBaked
        self.realtimeUpdateInterval = realtimeUpdateInterval
        self.nearClip = nearClip
        self.farClip = farClip
    }
}
