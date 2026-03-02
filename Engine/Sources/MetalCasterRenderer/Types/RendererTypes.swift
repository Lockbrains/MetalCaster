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
