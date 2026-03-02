import Foundation
import MetalCasterCore

/// Marks an entity as the scene skybox.
/// Only one skybox entity should exist per scene; the system uses the first one found.
public struct SkyboxComponent: Component {

    /// Path to the HDRI texture file (equirectangular format).
    /// When nil, the skybox renders a default gradient.
    public var hdriTexturePath: String?

    /// Exposure multiplier applied to the HDRI texture.
    public var exposure: Float

    /// Rotation offset in radians around the Y axis.
    public var rotation: Float

    public init(
        hdriTexturePath: String? = nil,
        exposure: Float = 1.0,
        rotation: Float = 0.0
    ) {
        self.hdriTexturePath = hdriTexturePath
        self.exposure = exposure
        self.rotation = rotation
    }
}
