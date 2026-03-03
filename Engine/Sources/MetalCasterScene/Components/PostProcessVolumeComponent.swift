import Foundation
import simd
import MetalCasterCore

// MARK: - Bloom

public struct BloomSettings: Codable, Sendable {
    public var enabled: Bool
    public var threshold: Float
    public var intensity: Float
    public var scatter: Float
    public var tint: SIMD3<Float>

    public init(
        enabled: Bool = false,
        threshold: Float = 0.9,
        intensity: Float = 1.0,
        scatter: Float = 0.7,
        tint: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.enabled = enabled
        self.threshold = threshold
        self.intensity = intensity
        self.scatter = scatter
        self.tint = tint
    }
}

// MARK: - Chromatic Aberration

public struct ChromaticAberrationSettings: Codable, Sendable {
    public var enabled: Bool
    public var intensity: Float

    public init(enabled: Bool = false, intensity: Float = 0.1) {
        self.enabled = enabled
        self.intensity = intensity
    }
}

// MARK: - Color Adjustments

public struct ColorAdjustmentsSettings: Codable, Sendable {
    public var enabled: Bool
    public var postExposure: Float
    public var contrast: Float
    public var colorFilter: SIMD3<Float>
    public var hueShift: Float
    public var saturation: Float

    public init(
        enabled: Bool = false,
        postExposure: Float = 0.0,
        contrast: Float = 0.0,
        colorFilter: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        hueShift: Float = 0.0,
        saturation: Float = 0.0
    ) {
        self.enabled = enabled
        self.postExposure = postExposure
        self.contrast = contrast
        self.colorFilter = colorFilter
        self.hueShift = hueShift
        self.saturation = saturation
    }
}

// MARK: - Channel Mixer

public struct ChannelMixerSettings: Codable, Sendable {
    public var enabled: Bool
    public var redOutRed: Float
    public var redOutGreen: Float
    public var redOutBlue: Float
    public var greenOutRed: Float
    public var greenOutGreen: Float
    public var greenOutBlue: Float
    public var blueOutRed: Float
    public var blueOutGreen: Float
    public var blueOutBlue: Float

    public init(
        enabled: Bool = false,
        redOutRed: Float = 100, redOutGreen: Float = 0, redOutBlue: Float = 0,
        greenOutRed: Float = 0, greenOutGreen: Float = 100, greenOutBlue: Float = 0,
        blueOutRed: Float = 0, blueOutGreen: Float = 0, blueOutBlue: Float = 100
    ) {
        self.enabled = enabled
        self.redOutRed = redOutRed; self.redOutGreen = redOutGreen; self.redOutBlue = redOutBlue
        self.greenOutRed = greenOutRed; self.greenOutGreen = greenOutGreen; self.greenOutBlue = greenOutBlue
        self.blueOutRed = blueOutRed; self.blueOutGreen = blueOutGreen; self.blueOutBlue = blueOutBlue
    }
}

// MARK: - Depth of Field

public enum DoFMode: String, CaseIterable, Codable, Sendable {
    case gaussian = "Gaussian"
    case bokeh = "Bokeh"
}

public struct DepthOfFieldSettings: Codable, Sendable {
    public var enabled: Bool
    public var mode: DoFMode
    public var focusDistance: Float
    public var aperture: Float
    public var focalLength: Float

    public init(
        enabled: Bool = false,
        mode: DoFMode = .gaussian,
        focusDistance: Float = 10.0,
        aperture: Float = 5.6,
        focalLength: Float = 50.0
    ) {
        self.enabled = enabled
        self.mode = mode
        self.focusDistance = focusDistance
        self.aperture = aperture
        self.focalLength = focalLength
    }
}

// MARK: - Film Grain

public enum FilmGrainType: String, CaseIterable, Codable, Sendable {
    case thin = "Thin"
    case medium = "Medium"
    case large = "Large"
}

public struct FilmGrainSettings: Codable, Sendable {
    public var enabled: Bool
    public var type: FilmGrainType
    public var intensity: Float
    public var response: Float

    public init(
        enabled: Bool = false,
        type: FilmGrainType = .medium,
        intensity: Float = 0.5,
        response: Float = 0.8
    ) {
        self.enabled = enabled
        self.type = type
        self.intensity = intensity
        self.response = response
    }
}

// MARK: - Lens Distortion

public struct LensDistortionSettings: Codable, Sendable {
    public var enabled: Bool
    public var intensity: Float
    public var xMultiplier: Float
    public var yMultiplier: Float
    public var center: SIMD2<Float>
    public var scale: Float

    public init(
        enabled: Bool = false,
        intensity: Float = 0.0,
        xMultiplier: Float = 1.0,
        yMultiplier: Float = 1.0,
        center: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        scale: Float = 1.0
    ) {
        self.enabled = enabled
        self.intensity = intensity
        self.xMultiplier = xMultiplier
        self.yMultiplier = yMultiplier
        self.center = center
        self.scale = scale
    }
}

// MARK: - Lift Gamma Gain

public struct LiftGammaGainSettings: Codable, Sendable {
    public var enabled: Bool
    public var lift: SIMD4<Float>
    public var gamma: SIMD4<Float>
    public var gain: SIMD4<Float>

    public init(
        enabled: Bool = false,
        lift: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0),
        gamma: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0),
        gain: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0)
    ) {
        self.enabled = enabled
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
    }
}

// MARK: - Motion Blur

public struct MotionBlurSettings: Codable, Sendable {
    public var enabled: Bool
    public var intensity: Float
    public var quality: Int

    public init(enabled: Bool = false, intensity: Float = 0.5, quality: Int = 16) {
        self.enabled = enabled
        self.intensity = intensity
        self.quality = quality
    }
}

// MARK: - Panini Projection

public struct PaniniProjectionSettings: Codable, Sendable {
    public var enabled: Bool
    public var distance: Float
    public var cropToFit: Float

    public init(enabled: Bool = false, distance: Float = 0.0, cropToFit: Float = 1.0) {
        self.enabled = enabled
        self.distance = distance
        self.cropToFit = cropToFit
    }
}

// MARK: - Shadows Midtones Highlights

public struct ShadowsMidtonesHighlightsSettings: Codable, Sendable {
    public var enabled: Bool
    public var shadows: SIMD4<Float>
    public var midtones: SIMD4<Float>
    public var highlights: SIMD4<Float>
    public var shadowsStart: Float
    public var shadowsEnd: Float
    public var highlightsStart: Float
    public var highlightsEnd: Float

    public init(
        enabled: Bool = false,
        shadows: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0),
        midtones: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0),
        highlights: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0),
        shadowsStart: Float = 0.0,
        shadowsEnd: Float = 0.3,
        highlightsStart: Float = 0.55,
        highlightsEnd: Float = 1.0
    ) {
        self.enabled = enabled
        self.shadows = shadows
        self.midtones = midtones
        self.highlights = highlights
        self.shadowsStart = shadowsStart
        self.shadowsEnd = shadowsEnd
        self.highlightsStart = highlightsStart
        self.highlightsEnd = highlightsEnd
    }
}

// MARK: - Split Toning

public struct SplitToningSettings: Codable, Sendable {
    public var enabled: Bool
    public var shadowsTint: SIMD3<Float>
    public var highlightsTint: SIMD3<Float>
    public var balance: Float

    public init(
        enabled: Bool = false,
        shadowsTint: SIMD3<Float> = SIMD3<Float>(0.5, 0.5, 0.5),
        highlightsTint: SIMD3<Float> = SIMD3<Float>(0.5, 0.5, 0.5),
        balance: Float = 0.0
    ) {
        self.enabled = enabled
        self.shadowsTint = shadowsTint
        self.highlightsTint = highlightsTint
        self.balance = balance
    }
}

// MARK: - Tonemapping

public enum TonemappingMode: String, CaseIterable, Codable, Sendable {
    case none = "None"
    case neutral = "Neutral"
    case aces = "ACES"
}

public struct TonemappingSettings: Codable, Sendable {
    public var enabled: Bool
    public var mode: TonemappingMode

    public init(enabled: Bool = false, mode: TonemappingMode = .aces) {
        self.enabled = enabled
        self.mode = mode
    }
}

// MARK: - Vignette

public struct VignetteSettings: Codable, Sendable {
    public var enabled: Bool
    public var color: SIMD3<Float>
    public var center: SIMD2<Float>
    public var intensity: Float
    public var smoothness: Float
    public var rounded: Bool

    public init(
        enabled: Bool = false,
        color: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        center: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        intensity: Float = 0.3,
        smoothness: Float = 0.3,
        rounded: Bool = false
    ) {
        self.enabled = enabled
        self.color = color
        self.center = center
        self.intensity = intensity
        self.smoothness = smoothness
        self.rounded = rounded
    }
}

// MARK: - White Balance

public struct WhiteBalanceSettings: Codable, Sendable {
    public var enabled: Bool
    public var temperature: Float
    public var tint: Float

    public init(enabled: Bool = false, temperature: Float = 0.0, tint: Float = 0.0) {
        self.enabled = enabled
        self.temperature = temperature
        self.tint = tint
    }
}

// MARK: - Ambient Occlusion (SSAO)

public struct AmbientOcclusionSettings: Codable, Sendable {
    public var enabled: Bool
    public var intensity: Float
    public var radius: Float
    public var sampleCount: Int

    public init(enabled: Bool = false, intensity: Float = 1.0, radius: Float = 0.5, sampleCount: Int = 16) {
        self.enabled = enabled
        self.intensity = intensity
        self.radius = radius
        self.sampleCount = sampleCount
    }
}

// MARK: - Anti-aliasing

public enum AntiAliasingMode: String, CaseIterable, Codable, Sendable {
    case none = "None"
    case fxaa = "FXAA"
    case smaa = "SMAA"
}

public struct AntiAliasingSettings: Codable, Sendable {
    public var enabled: Bool
    public var mode: AntiAliasingMode

    public init(enabled: Bool = false, mode: AntiAliasingMode = .fxaa) {
        self.enabled = enabled
        self.mode = mode
    }
}

// MARK: - Fullscreen Blur (MetalCaster Custom)

public enum FullscreenBlurMode: String, CaseIterable, Codable, Sendable {
    case highQuality = "High Quality"
    case highPerformance = "High Performance"
}

public struct FullscreenBlurSettings: Codable, Sendable {
    public var enabled: Bool
    public var mode: FullscreenBlurMode
    public var intensity: Float
    public var radius: Float

    public init(
        enabled: Bool = false,
        mode: FullscreenBlurMode = .highQuality,
        intensity: Float = 1.0,
        radius: Float = 5.0
    ) {
        self.enabled = enabled
        self.mode = mode
        self.intensity = intensity
        self.radius = radius
    }
}

// MARK: - Fullscreen Outline (MetalCaster Custom)

public enum FullscreenOutlineMode: String, CaseIterable, Codable, Sendable {
    case normalBased = "Normal"
    case colorBased = "Color"
    case depthBased = "Depth"
}

public struct FullscreenOutlineSettings: Codable, Sendable {
    public var enabled: Bool
    public var mode: FullscreenOutlineMode
    public var thickness: Float
    public var color: SIMD3<Float>
    public var threshold: Float

    public init(
        enabled: Bool = false,
        mode: FullscreenOutlineMode = .depthBased,
        thickness: Float = 1.0,
        color: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        threshold: Float = 0.1
    ) {
        self.enabled = enabled
        self.mode = mode
        self.thickness = thickness
        self.color = color
        self.threshold = threshold
    }
}

// MARK: - Post Process Volume Component

/// Defines a post-processing volume that applies effects to cameras within its bounds.
/// When `isGlobal` is true, the volume has infinite extents and affects all cameras.
public struct PostProcessVolumeComponent: Component {

    // MARK: Volume Properties

    /// When true, the volume has infinite extents.
    public var isGlobal: Bool

    /// Half-extents of the volume box (used when `isGlobal` is false).
    public var volumeExtents: SIMD3<Float>

    /// Higher priority volumes override lower ones.
    public var priority: Int

    /// Distance over which the volume blends with surrounding volumes.
    public var blendDistance: Float

    // MARK: Unity 6.0 URP Effects

    public var bloom: BloomSettings
    public var chromaticAberration: ChromaticAberrationSettings
    public var colorAdjustments: ColorAdjustmentsSettings
    public var channelMixer: ChannelMixerSettings
    public var depthOfField: DepthOfFieldSettings
    public var filmGrain: FilmGrainSettings
    public var lensDistortion: LensDistortionSettings
    public var liftGammaGain: LiftGammaGainSettings
    public var motionBlur: MotionBlurSettings
    public var paniniProjection: PaniniProjectionSettings
    public var shadowsMidtonesHighlights: ShadowsMidtonesHighlightsSettings
    public var splitToning: SplitToningSettings
    public var tonemapping: TonemappingSettings
    public var vignette: VignetteSettings
    public var whiteBalance: WhiteBalanceSettings
    public var ambientOcclusion: AmbientOcclusionSettings
    public var antiAliasing: AntiAliasingSettings

    // MARK: MetalCaster Custom Effects

    public var fullscreenBlur: FullscreenBlurSettings
    public var fullscreenOutline: FullscreenOutlineSettings

    public init(
        isGlobal: Bool = true,
        volumeExtents: SIMD3<Float> = SIMD3<Float>(10, 10, 10),
        priority: Int = 0,
        blendDistance: Float = 0,
        bloom: BloomSettings = .init(),
        chromaticAberration: ChromaticAberrationSettings = .init(),
        colorAdjustments: ColorAdjustmentsSettings = .init(),
        channelMixer: ChannelMixerSettings = .init(),
        depthOfField: DepthOfFieldSettings = .init(),
        filmGrain: FilmGrainSettings = .init(),
        lensDistortion: LensDistortionSettings = .init(),
        liftGammaGain: LiftGammaGainSettings = .init(),
        motionBlur: MotionBlurSettings = .init(),
        paniniProjection: PaniniProjectionSettings = .init(),
        shadowsMidtonesHighlights: ShadowsMidtonesHighlightsSettings = .init(),
        splitToning: SplitToningSettings = .init(),
        tonemapping: TonemappingSettings = .init(),
        vignette: VignetteSettings = .init(),
        whiteBalance: WhiteBalanceSettings = .init(),
        ambientOcclusion: AmbientOcclusionSettings = .init(),
        antiAliasing: AntiAliasingSettings = .init(),
        fullscreenBlur: FullscreenBlurSettings = .init(),
        fullscreenOutline: FullscreenOutlineSettings = .init()
    ) {
        self.isGlobal = isGlobal
        self.volumeExtents = volumeExtents
        self.priority = priority
        self.blendDistance = blendDistance
        self.bloom = bloom
        self.chromaticAberration = chromaticAberration
        self.colorAdjustments = colorAdjustments
        self.channelMixer = channelMixer
        self.depthOfField = depthOfField
        self.filmGrain = filmGrain
        self.lensDistortion = lensDistortion
        self.liftGammaGain = liftGammaGain
        self.motionBlur = motionBlur
        self.paniniProjection = paniniProjection
        self.shadowsMidtonesHighlights = shadowsMidtonesHighlights
        self.splitToning = splitToning
        self.tonemapping = tonemapping
        self.vignette = vignette
        self.whiteBalance = whiteBalance
        self.ambientOcclusion = ambientOcclusion
        self.antiAliasing = antiAliasing
        self.fullscreenBlur = fullscreenBlur
        self.fullscreenOutline = fullscreenOutline
    }
}
