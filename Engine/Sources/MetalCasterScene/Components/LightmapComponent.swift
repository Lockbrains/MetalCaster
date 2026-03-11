import Foundation
import simd
import MetalCasterCore

/// Marks a static mesh entity as lightmap-receiving.
/// At bake time the engine rasterizes indirect illumination into a 2D texture
/// using the mesh's lightmap UV set (UV1). At runtime the texture is sampled
/// and multiplied with the direct lighting result.
public struct LightmapComponent: Component {

    public enum BakeQuality: String, CaseIterable, Codable, Sendable {
        case draft   = "Draft"
        case medium  = "Medium"
        case production = "Production"
    }

    /// Path to the baked lightmap texture (relative to project).
    /// Nil until a bake has been performed.
    public var lightmapTexturePath: String?

    /// Lightmap UV channel index (typically 1).
    public var uvChannel: Int

    /// Resolution of the lightmap texture per-entity (width = height).
    public var resolution: Int

    /// Quality preset used during the next bake.
    public var bakeQuality: BakeQuality

    /// Intensity multiplier applied when sampling the lightmap.
    public var intensity: Float

    /// Whether this entity contributes to lightmap generation as a blocker/emitter.
    public var contributeGI: Bool

    public init(
        lightmapTexturePath: String? = nil,
        uvChannel: Int = 1,
        resolution: Int = 256,
        bakeQuality: BakeQuality = .medium,
        intensity: Float = 1.0,
        contributeGI: Bool = true
    ) {
        self.lightmapTexturePath = lightmapTexturePath
        self.uvChannel = uvChannel
        self.resolution = resolution
        self.bakeQuality = bakeQuality
        self.intensity = intensity
        self.contributeGI = contributeGI
    }
}
