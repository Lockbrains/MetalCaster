import Foundation
import simd

// MARK: - Shader Category

/// Represents the three types of shader layers supported by the rendering pipeline.
public enum ShaderCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case vertex = "Vertex"
    case fragment = "Fragment"
    case fullscreen = "Fullscreen"

    public var id: String { self.rawValue }

    public var icon: String {
        switch self {
        case .vertex: return "move.3d"
        case .fragment: return "paintbrush.fill"
        case .fullscreen: return "display"
        }
    }
}

// MARK: - Mesh Type

/// Defines the 3D mesh geometry to render.
public enum MeshType: Equatable, Codable, Sendable {
    case sphere
    case cube
    case plane
    case cylinder
    case cone
    case capsule
    case custom(URL)
    /// References a mesh asset by its project GUID, resolved at load time via AssetDatabase.
    case asset(UUID)

    /// All built-in primitive types available in the editor.
    public static let builtinPrimitives: [MeshType] = [.cube, .sphere, .plane, .cylinder, .cone, .capsule]

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .sphere: return "Sphere"
        case .cube: return "Cube"
        case .plane: return "Plane"
        case .cylinder: return "Cylinder"
        case .cone: return "Cone"
        case .capsule: return "Capsule"
        case .custom: return "Custom Mesh"
        case .asset: return "Asset Mesh"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, path, guid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sphere:
            try container.encode("sphere", forKey: .type)
        case .cube:
            try container.encode("cube", forKey: .type)
        case .plane:
            try container.encode("plane", forKey: .type)
        case .cylinder:
            try container.encode("cylinder", forKey: .type)
        case .cone:
            try container.encode("cone", forKey: .type)
        case .capsule:
            try container.encode("capsule", forKey: .type)
        case .custom(let url):
            try container.encode("custom", forKey: .type)
            try container.encode(url.path, forKey: .path)
        case .asset(let guid):
            try container.encode("asset", forKey: .type)
            try container.encode(guid.uuidString, forKey: .guid)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "cube": self = .cube
        case "plane": self = .plane
        case "cylinder": self = .cylinder
        case "cone": self = .cone
        case "capsule": self = .capsule
        case "custom":
            let path = try container.decode(String.self, forKey: .path)
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                self = .custom(url)
            } else {
                self = .sphere
            }
        case "asset":
            let guidString = try container.decode(String.self, forKey: .guid)
            if let guid = UUID(uuidString: guidString) {
                self = .asset(guid)
            } else {
                self = .sphere
            }
        default:
            self = .sphere
        }
    }
}

// MARK: - Active Shader

/// Represents a single shader layer in the workspace.
public struct ActiveShader: Identifiable, Codable, Sendable {
    public let id: UUID
    public let category: ShaderCategory
    public var name: String
    public var code: String

    public init(id: UUID = UUID(), category: ShaderCategory, name: String, code: String) {
        self.id = id
        self.category = category
        self.name = name
        self.code = code
    }
}

// MARK: - Data Flow Configuration

/// Configurable vertex data fields shared across all mesh shaders.
public struct DataFlowConfig: Codable, Equatable, Sendable {
    public var normalEnabled: Bool
    public var uvEnabled: Bool
    public var timeEnabled: Bool
    public var worldPositionEnabled: Bool
    public var worldNormalEnabled: Bool
    public var viewDirectionEnabled: Bool

    public init(
        normalEnabled: Bool = true,
        uvEnabled: Bool = true,
        timeEnabled: Bool = true,
        worldPositionEnabled: Bool = false,
        worldNormalEnabled: Bool = false,
        viewDirectionEnabled: Bool = false
    ) {
        self.normalEnabled = normalEnabled
        self.uvEnabled = uvEnabled
        self.timeEnabled = timeEnabled
        self.worldPositionEnabled = worldPositionEnabled
        self.worldNormalEnabled = worldNormalEnabled
        self.viewDirectionEnabled = viewDirectionEnabled
    }

    public mutating func resolveDependencies() {
        if worldNormalEnabled && !normalEnabled { normalEnabled = true }
        if viewDirectionEnabled && !worldPositionEnabled { worldPositionEnabled = true }
        if !normalEnabled { worldNormalEnabled = false }
        if !worldPositionEnabled { viewDirectionEnabled = false }
    }
}

// MARK: - Shader Parameters

/// The type of a user-declared shader parameter.
public enum ParamType: String, Codable, Sendable {
    case float = "float"
    case float2 = "float2"
    case float3 = "float3"
    case float4 = "float4"
    case color = "color"

    public var componentCount: Int {
        switch self {
        case .float: return 1
        case .float2: return 2
        case .float3, .color: return 3
        case .float4: return 4
        }
    }
}

/// A user-declared shader parameter parsed from `// @param` directives.
public struct ShaderParam: Equatable, Codable, Sendable {
    public var name: String
    public var type: ParamType
    public var defaultValue: [Float]
    public var minValue: Float?
    public var maxValue: Float?

    public init(name: String, type: ParamType, defaultValue: [Float], minValue: Float? = nil, maxValue: Float? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

// MARK: - Uniforms (CPU ↔ GPU)

/// Fixed-layout uniform buffer passed to all mesh shaders each frame.
/// Memory layout must match the MSL `Uniforms` struct exactly.
public struct Uniforms: Sendable {
    public var mvpMatrix: simd_float4x4
    public var modelMatrix: simd_float4x4
    public var normalMatrix: simd_float4x4
    public var cameraPosition: simd_float4
    public var time: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0
    public var _pad2: Float = 0

    public init(
        mvpMatrix: simd_float4x4 = matrix_identity_float4x4,
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        normalMatrix: simd_float4x4 = matrix_identity_float4x4,
        cameraPosition: simd_float4 = .zero,
        time: Float = 0
    ) {
        self.mvpMatrix = mvpMatrix
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        self.cameraPosition = cameraPosition
        self.time = time
    }
}

// MARK: - Skybox Uniforms (CPU ↔ GPU)

/// Uniform buffer for skybox rendering.
/// Contains a view-projection matrix with translation zeroed out.
/// Memory layout must match the MSL `SkyboxUniforms` struct exactly.
public struct SkyboxUniforms: Sendable {
    public var viewProjectionMatrix: simd_float4x4

    public init(viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4) {
        self.viewProjectionMatrix = viewProjectionMatrix
    }
}

// MARK: - Post-Process Uniforms (CPU ↔ GPU)

/// Uniform buffer for post-processing passes.
/// Memory layout must match the MSL `PostProcessUniforms` struct exactly.
public struct PostProcessUniforms: Sendable {
    public var exposureMultiplier: Float
    public var focusDistance: Float
    public var aperture: Float
    public var focalLengthM: Float
    public var sensorHeightM: Float
    public var shutterAngle: Float
    public var nearZ: Float
    public var farZ: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0

    public init(
        exposureMultiplier: Float = 1.0,
        focusDistance: Float = 10.0,
        aperture: Float = 2.8,
        focalLengthM: Float = 0.05,
        sensorHeightM: Float = 0.024,
        shutterAngle: Float = 180.0,
        nearZ: Float = 0.1,
        farZ: Float = 1000.0,
        screenWidth: Float = 1920,
        screenHeight: Float = 1080
    ) {
        self.exposureMultiplier = exposureMultiplier
        self.focusDistance = focusDistance
        self.aperture = aperture
        self.focalLengthM = focalLengthM
        self.sensorHeightM = sensorHeightM
        self.shutterAngle = shutterAngle
        self.nearZ = nearZ
        self.farZ = farZ
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

/// Uniform buffer for motion blur (previous frame data).
/// Memory layout must match the MSL `MotionBlurUniforms` struct exactly.
public struct MotionBlurUniforms: Sendable {
    public var viewProjectionMatrix: simd_float4x4
    public var previousViewProjectionMatrix: simd_float4x4
    public var inverseViewProjectionMatrix: simd_float4x4
    public var shutterAngle: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0

    public init(
        viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        previousViewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        inverseViewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        shutterAngle: Float = 180.0,
        screenWidth: Float = 1920,
        screenHeight: Float = 1080
    ) {
        self.viewProjectionMatrix = viewProjectionMatrix
        self.previousViewProjectionMatrix = previousViewProjectionMatrix
        self.inverseViewProjectionMatrix = inverseViewProjectionMatrix
        self.shutterAngle = shutterAngle
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }
}

// MARK: - Bloom Uniforms (CPU ↔ GPU)

public struct BloomUniforms: Sendable {
    public var threshold: Float
    public var intensity: Float
    public var scatter: Float
    public var tintR: Float
    public var tintG: Float
    public var tintB: Float
    public var screenWidth: Float
    public var screenHeight: Float

    public init(
        threshold: Float = 0.9, intensity: Float = 1.0, scatter: Float = 0.7,
        tintR: Float = 1, tintG: Float = 1, tintB: Float = 1,
        screenWidth: Float = 1920, screenHeight: Float = 1080
    ) {
        self.threshold = threshold; self.intensity = intensity; self.scatter = scatter
        self.tintR = tintR; self.tintG = tintG; self.tintB = tintB
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }
}

// MARK: - Color Grading Uniforms (CPU ↔ GPU)

/// Combined uniform for all color grading effects in a single pass:
/// Color Adjustments, White Balance, Channel Mixer, Lift/Gamma/Gain,
/// Split Toning, Shadows/Midtones/Highlights, Tonemapping.
public struct ColorGradingUniforms: Sendable {
    // Color Adjustments
    public var postExposure: Float
    public var contrast: Float
    public var colorFilterR: Float
    public var colorFilterG: Float
    public var colorFilterB: Float
    public var hueShift: Float
    public var saturation: Float
    public var enableColorAdjustments: Float

    // White Balance
    public var temperature: Float
    public var wbTint: Float
    public var enableWhiteBalance: Float
    public var _pad0: Float = 0

    // Channel Mixer (row-major 3x3)
    public var mixerRedR: Float
    public var mixerRedG: Float
    public var mixerRedB: Float
    public var enableChannelMixer: Float
    public var mixerGreenR: Float
    public var mixerGreenG: Float
    public var mixerGreenB: Float
    public var _pad1: Float = 0
    public var mixerBlueR: Float
    public var mixerBlueG: Float
    public var mixerBlueB: Float
    public var _pad2: Float = 0

    // Lift Gamma Gain
    public var lift: SIMD4<Float>
    public var gamma: SIMD4<Float>
    public var gain: SIMD4<Float>
    public var enableLGG: Float
    public var _pad3: Float = 0
    public var _pad4: Float = 0
    public var _pad5: Float = 0

    // Split Toning
    public var splitShadowR: Float
    public var splitShadowG: Float
    public var splitShadowB: Float
    public var splitBalance: Float
    public var splitHighR: Float
    public var splitHighG: Float
    public var splitHighB: Float
    public var enableSplitToning: Float

    // Shadows Midtones Highlights
    public var smhShadows: SIMD4<Float>
    public var smhMidtones: SIMD4<Float>
    public var smhHighlights: SIMD4<Float>
    public var smhShadowsStart: Float
    public var smhShadowsEnd: Float
    public var smhHighlightsStart: Float
    public var smhHighlightsEnd: Float
    public var enableSMH: Float
    public var _pad6: Float = 0
    public var _pad7: Float = 0
    public var _pad8: Float = 0

    // Tonemapping
    public var tonemappingMode: Float
    public var _pad9: Float = 0
    public var _padA: Float = 0
    public var _padB: Float = 0

    public init() {
        postExposure = 0; contrast = 0
        colorFilterR = 1; colorFilterG = 1; colorFilterB = 1
        hueShift = 0; saturation = 0; enableColorAdjustments = 0
        temperature = 0; wbTint = 0; enableWhiteBalance = 0
        mixerRedR = 1; mixerRedG = 0; mixerRedB = 0; enableChannelMixer = 0
        mixerGreenR = 0; mixerGreenG = 1; mixerGreenB = 0
        mixerBlueR = 0; mixerBlueG = 0; mixerBlueB = 1
        lift = SIMD4<Float>(1, 1, 1, 0)
        gamma = SIMD4<Float>(1, 1, 1, 0)
        gain = SIMD4<Float>(1, 1, 1, 0)
        enableLGG = 0
        splitShadowR = 0.5; splitShadowG = 0.5; splitShadowB = 0.5; splitBalance = 0
        splitHighR = 0.5; splitHighG = 0.5; splitHighB = 0.5; enableSplitToning = 0
        smhShadows = SIMD4<Float>(1, 1, 1, 0)
        smhMidtones = SIMD4<Float>(1, 1, 1, 0)
        smhHighlights = SIMD4<Float>(1, 1, 1, 0)
        smhShadowsStart = 0; smhShadowsEnd = 0.3
        smhHighlightsStart = 0.55; smhHighlightsEnd = 1
        enableSMH = 0
        tonemappingMode = 0
    }
}

// MARK: - Vignette Uniforms (CPU ↔ GPU)

public struct VignetteUniforms: Sendable {
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var intensity: Float
    public var centerX: Float
    public var centerY: Float
    public var smoothness: Float
    public var rounded: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0

    public init() {
        colorR = 0; colorG = 0; colorB = 0; intensity = 0.3
        centerX = 0.5; centerY = 0.5; smoothness = 0.3; rounded = 0
        screenWidth = 1920; screenHeight = 1080
    }
}

// MARK: - Chromatic Aberration Uniforms (CPU ↔ GPU)

public struct ChromaticAberrationUniforms: Sendable {
    public var intensity: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0

    public init() { intensity = 0.1; screenWidth = 1920; screenHeight = 1080 }

    public init(intensity: Float, screenWidth: Float, screenHeight: Float) {
        self.intensity = intensity; self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }
}

// MARK: - Film Grain Uniforms (CPU ↔ GPU)

public struct FilmGrainUniforms: Sendable {
    public var intensity: Float
    public var response: Float
    public var grainType: Float
    public var time: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0

    public init() {
        intensity = 0.5; response = 0.8; grainType = 1; time = 0
        screenWidth = 1920; screenHeight = 1080
    }
}

// MARK: - Lens Distortion Uniforms (CPU ↔ GPU)

public struct LensDistortionUniforms: Sendable {
    public var intensity: Float
    public var xMultiplier: Float
    public var yMultiplier: Float
    public var scale: Float
    public var centerX: Float
    public var centerY: Float
    public var screenWidth: Float
    public var screenHeight: Float

    public init() {
        intensity = 0; xMultiplier = 1; yMultiplier = 1; scale = 1
        centerX = 0.5; centerY = 0.5; screenWidth = 1920; screenHeight = 1080
    }

    public init(intensity: Float, xMultiplier: Float, yMultiplier: Float, scale: Float,
                centerX: Float, centerY: Float, screenWidth: Float, screenHeight: Float) {
        self.intensity = intensity; self.xMultiplier = xMultiplier
        self.yMultiplier = yMultiplier; self.scale = scale
        self.centerX = centerX; self.centerY = centerY
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }
}

// MARK: - Panini Projection Uniforms (CPU ↔ GPU)

public struct PaniniUniforms: Sendable {
    public var distance: Float
    public var cropToFit: Float
    public var screenWidth: Float
    public var screenHeight: Float

    public init() { distance = 0; cropToFit = 1; screenWidth = 1920; screenHeight = 1080 }

    public init(distance: Float, cropToFit: Float, screenWidth: Float, screenHeight: Float) {
        self.distance = distance; self.cropToFit = cropToFit
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }
}

// MARK: - SSAO Uniforms (CPU ↔ GPU)

public struct SSAOUniforms: Sendable {
    public var intensity: Float
    public var radius: Float
    public var sampleCount: Float
    public var _pad0: Float = 0
    public var screenWidth: Float
    public var screenHeight: Float
    public var nearZ: Float
    public var farZ: Float

    public init() {
        intensity = 1; radius = 0.5; sampleCount = 16
        screenWidth = 1920; screenHeight = 1080; nearZ = 0.1; farZ = 1000
    }
}

// MARK: - FXAA Uniforms (CPU ↔ GPU)

public struct FXAAUniforms: Sendable {
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0

    public init() { screenWidth = 1920; screenHeight = 1080 }

    public init(screenWidth: Float, screenHeight: Float) {
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
    }
}

// MARK: - Fullscreen Blur Uniforms (CPU ↔ GPU)

public struct FullscreenBlurUniforms: Sendable {
    public var intensity: Float
    public var radius: Float
    public var blurMode: Float
    public var iteration: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0

    public init() {
        intensity = 1; radius = 5; blurMode = 0; iteration = 0
        screenWidth = 1920; screenHeight = 1080
    }
}

// MARK: - Fullscreen Outline Uniforms (CPU ↔ GPU)

public struct FullscreenOutlineUniforms: Sendable {
    public var outlineMode: Float
    public var thickness: Float
    public var threshold: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var screenWidth: Float
    public var screenHeight: Float
    public var nearZ: Float
    public var farZ: Float
    public var _pad0: Float = 0
    public var _pad1: Float = 0

    public init() {
        outlineMode = 2; thickness = 1; threshold = 0.1
        colorR = 0; colorG = 0; colorB = 0
        screenWidth = 1920; screenHeight = 1080; nearZ = 0.1; farZ = 1000
    }
}

// MARK: - Canvas Document

/// The top-level serializable workspace state for Shader Canvas.
public struct CanvasDocument: Codable, Sendable {
    public var name: String
    public var meshType: MeshType
    public var shaders: [ActiveShader]
    public var dataFlow: DataFlowConfig
    public var paramValues: [String: [Float]]

    public init(
        name: String,
        meshType: MeshType,
        shaders: [ActiveShader],
        dataFlow: DataFlowConfig = DataFlowConfig(),
        paramValues: [String: [Float]] = [:]
    ) {
        self.name = name
        self.meshType = meshType
        self.shaders = shaders
        self.dataFlow = dataFlow
        self.paramValues = paramValues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        meshType = try container.decode(MeshType.self, forKey: .meshType)
        shaders = try container.decode([ActiveShader].self, forKey: .shaders)
        dataFlow = try container.decodeIfPresent(DataFlowConfig.self, forKey: .dataFlow) ?? DataFlowConfig()
        paramValues = try container.decodeIfPresent([String: [Float]].self, forKey: .paramValues) ?? [:]
    }
}

// MARK: - Notification Names

#if canImport(AppKit)
import AppKit

extension NSNotification.Name {
    public static let shaderCompilationResult = NSNotification.Name("shaderCompilationResult")
    public static let canvasNew = NSNotification.Name("canvasNew")
    public static let canvasSave = NSNotification.Name("canvasSave")
    public static let canvasSaveAs = NSNotification.Name("canvasSaveAs")
    public static let canvasOpen = NSNotification.Name("canvasOpen")
    public static let canvasTutorial = NSNotification.Name("canvasTutorial")
    public static let aiSettings = NSNotification.Name("aiSettings")
    public static let aiChat = NSNotification.Name("aiChat")
}
#endif
