import Foundation
import simd
import MetalCasterCore

// MARK: - Water Type

public enum WaterType: String, CaseIterable, Codable, Sendable {
    case ocean  = "Ocean"
    case lake   = "Lake"
    case river  = "River"
    case pond   = "Pond"
}

// MARK: - Water Body Component

/// Defines a water body with surface simulation and rendering properties.
public struct WaterBodyComponent: Component {

    /// The category of water body.
    public var waterType: WaterType

    /// World-space Y coordinate of the water surface.
    public var surfaceHeight: Float

    /// XZ extent of the water surface (width, depth). Ignored for ocean type (infinite).
    public var extent: SIMD2<Float>

    /// Flow direction for rivers (normalized XZ vector). Nil for still water.
    public var flowDirection: SIMD2<Float>?

    /// Wave amplitude for surface animation.
    public var waveAmplitude: Float

    /// Wave frequency multiplier.
    public var waveFrequency: Float

    /// Water surface color (linear RGB).
    public var color: SIMD3<Float>

    /// Water transparency (0 = opaque, 1 = fully transparent).
    public var transparency: Float

    /// Index of refraction for under-surface distortion.
    public var refractionIndex: Float

    /// Whether to render planar reflections.
    public var reflectionsEnabled: Bool

    /// Foam threshold (wave crest intensity that triggers foam rendering).
    public var foamThreshold: Float

    public init(
        waterType: WaterType = .lake,
        surfaceHeight: Float = 0,
        extent: SIMD2<Float> = SIMD2<Float>(100, 100),
        waveAmplitude: Float = 0.3,
        waveFrequency: Float = 1.0,
        color: SIMD3<Float> = SIMD3<Float>(0.1, 0.3, 0.5),
        transparency: Float = 0.6
    ) {
        self.waterType = waterType
        self.surfaceHeight = surfaceHeight
        self.extent = extent
        self.flowDirection = nil
        self.waveAmplitude = waveAmplitude
        self.waveFrequency = waveFrequency
        self.color = color
        self.transparency = transparency
        self.refractionIndex = 1.33
        self.reflectionsEnabled = true
        self.foamThreshold = 0.8
    }
}
