import Foundation
import simd

// MARK: - Material Surface Properties

/// PBR surface properties for a material instance.
/// These values are uploaded to the GPU as a uniform buffer and
/// can vary per-entity even when sharing the same shader.
public struct MCMaterialProperties: Codable, Sendable, Equatable {
    public var baseColor: SIMD3<Float>
    public var metallic: Float
    public var roughness: Float
    public var emissiveColor: SIMD3<Float>
    public var emissiveIntensity: Float

    public var albedoTexturePath: String?
    public var normalMapPath: String?
    public var metallicRoughnessMapPath: String?

    public init(
        baseColor: SIMD3<Float> = SIMD3<Float>(0.8, 0.8, 0.8),
        metallic: Float = 0.0,
        roughness: Float = 0.5,
        emissiveColor: SIMD3<Float> = .zero,
        emissiveIntensity: Float = 0.0,
        albedoTexturePath: String? = nil,
        normalMapPath: String? = nil,
        metallicRoughnessMapPath: String? = nil
    ) {
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.emissiveColor = emissiveColor
        self.emissiveIntensity = emissiveIntensity
        self.albedoTexturePath = albedoTexturePath
        self.normalMapPath = normalMapPath
        self.metallicRoughnessMapPath = metallicRoughnessMapPath
    }
}

/// GPU-side material properties, bound at fragment buffer index 2.
/// Must match the MSL `MaterialProperties` struct in built-in shaders.
public struct GPUMaterialProperties {
    public var baseColor: SIMD3<Float> = SIMD3<Float>(0.8, 0.8, 0.8)
    public var metallic: Float = 0.0
    public var roughness: Float = 0.5
    public var _pad0: Float = 0
    public var emissiveColor: SIMD3<Float> = .zero
    public var emissiveIntensity: Float = 0.0
    public var hasAlbedoTexture: UInt32 = 0
    public var hasNormalMap: UInt32 = 0
    public var hasMetallicRoughnessMap: UInt32 = 0
    public var _pad1: UInt32 = 0

    public init(from props: MCMaterialProperties) {
        baseColor = props.baseColor
        metallic = props.metallic
        roughness = max(0.04, props.roughness)
        emissiveColor = props.emissiveColor
        emissiveIntensity = props.emissiveIntensity
        hasAlbedoTexture = props.albedoTexturePath != nil ? 1 : 0
        hasNormalMap = props.normalMapPath != nil ? 1 : 0
        hasMetallicRoughnessMap = props.metallicRoughnessMapPath != nil ? 1 : 0
    }
}

/// Represents a material definition that maps to a set of shaders and parameters.
///
/// Materials define the visual appearance of a surface. In the engine,
/// materials are stored as components and reference shader code + parameters.
/// Built-in materials are engine-provided and immutable; custom materials
/// are authored via ShaderCanvas.
public struct MCMaterial: Codable, Sendable {

    /// Unique identifier for this material.
    public let id: UUID

    /// Human-readable name.
    public var name: String

    /// Whether this material is engine-provided or user-created.
    public var materialType: MCMaterialType

    /// Render state configuration (blend, depth, cull, queue).
    public var renderState: MCRenderState

    /// The vertex shader source code (nil = use default).
    public var vertexShaderSource: String?

    /// The fragment shader source code.
    public var fragmentShaderSource: String

    /// Unified shader source containing both vertex and fragment functions.
    /// When set, this takes priority over separate vertex/fragment sources.
    public var unifiedShaderSource: String?

    /// Post-processing shader sources applied when this material is active.
    public var postProcessSources: [String]

    /// User-tunable parameters with their current values.
    public var parameters: [String: [Float]]

    /// The data flow configuration for this material's shaders.
    public var dataFlowConfig: DataFlowConfig

    /// PBR surface properties (base color, metallic, roughness, textures).
    public var surfaceProperties: MCMaterialProperties

    public init(
        id: UUID = UUID(),
        name: String = "Default Material",
        materialType: MCMaterialType = .custom,
        renderState: MCRenderState = .opaque,
        vertexShaderSource: String? = nil,
        fragmentShaderSource: String = "",
        unifiedShaderSource: String? = nil,
        postProcessSources: [String] = [],
        parameters: [String: [Float]] = [:],
        dataFlowConfig: DataFlowConfig = DataFlowConfig(),
        surfaceProperties: MCMaterialProperties = MCMaterialProperties()
    ) {
        self.id = id
        self.name = name
        self.materialType = materialType
        self.renderState = renderState
        self.vertexShaderSource = vertexShaderSource
        self.fragmentShaderSource = fragmentShaderSource
        self.unifiedShaderSource = unifiedShaderSource
        self.postProcessSources = postProcessSources
        self.parameters = parameters
        self.dataFlowConfig = dataFlowConfig
        self.surfaceProperties = surfaceProperties
    }

    // Custom Codable to maintain backward compatibility with scenes saved before
    // materialType / renderState / unifiedShaderSource were added.

    private enum CodingKeys: String, CodingKey {
        case id, name, materialType, renderState
        case vertexShaderSource, fragmentShaderSource, unifiedShaderSource
        case postProcessSources, parameters, dataFlowConfig, surfaceProperties
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        materialType = try c.decodeIfPresent(MCMaterialType.self, forKey: .materialType) ?? .custom
        renderState = try c.decodeIfPresent(MCRenderState.self, forKey: .renderState) ?? .opaque
        vertexShaderSource = try c.decodeIfPresent(String.self, forKey: .vertexShaderSource)
        fragmentShaderSource = try c.decodeIfPresent(String.self, forKey: .fragmentShaderSource) ?? ""
        unifiedShaderSource = try c.decodeIfPresent(String.self, forKey: .unifiedShaderSource)
        postProcessSources = try c.decodeIfPresent([String].self, forKey: .postProcessSources) ?? []
        parameters = try c.decodeIfPresent([String: [Float]].self, forKey: .parameters) ?? [:]
        dataFlowConfig = try c.decodeIfPresent(DataFlowConfig.self, forKey: .dataFlowConfig) ?? DataFlowConfig()
        surfaceProperties = try c.decodeIfPresent(MCMaterialProperties.self, forKey: .surfaceProperties) ?? MCMaterialProperties()
    }

    /// Whether this material uses light data (buffer index 3/4).
    public var needsLighting: Bool {
        switch name {
        case "MC_Lit", "MC_Toon": return true
        default:
            guard let source = unifiedShaderSource ?? fragmentShaderSource.nilIfEmpty else {
                return false
            }
            return source.contains("GPULightData") || source.contains("lightCount")
        }
    }

    /// A stable hash suitable for pipeline cache lookup (based on shader source + render state).
    public var pipelineCacheKey: PipelineCacheKey {
        let sourceHash: Int
        if let unified = unifiedShaderSource {
            sourceHash = unified.hashValue
        } else {
            var hasher = Hasher()
            hasher.combine(vertexShaderSource ?? "")
            hasher.combine(fragmentShaderSource)
            sourceHash = hasher.finalize()
        }
        return PipelineCacheKey(
            shaderSourceHash: sourceHash,
            blendMode: renderState.blendMode,
            depthWrite: renderState.depthWrite,
            cullMode: renderState.cullMode
        )
    }
}

/// Composite key for pipeline state caching that includes both shader identity and render state.
public struct PipelineCacheKey: Hashable, Sendable {
    public let shaderSourceHash: Int
    public let blendMode: MCBlendMode
    public let depthWrite: Bool
    public let cullMode: MCCullMode

    public init(shaderSourceHash: Int, blendMode: MCBlendMode, depthWrite: Bool, cullMode: MCCullMode) {
        self.shaderSourceHash = shaderSourceHash
        self.blendMode = blendMode
        self.depthWrite = depthWrite
        self.cullMode = cullMode
    }
}

// MARK: - CanvasDocument Conversion

extension MCMaterial {

    /// Creates a custom material from a ShaderCanvas workspace document.
    ///
    /// Extracts the active vertex and fragment shaders, combines them with the
    /// shared header from DataFlowConfig, and packages parameters into a material.
    public init(from document: CanvasDocument) {
        let vertexShader = document.shaders.last(where: { $0.category == .vertex })
        let fragmentShader = document.shaders.last(where: { $0.category == .fragment })
        let fullscreenShaders = document.shaders.filter { $0.category == .fullscreen }

        self.init(
            name: document.name,
            materialType: .custom,
            vertexShaderSource: vertexShader?.code,
            fragmentShaderSource: fragmentShader?.code ?? "",
            postProcessSources: fullscreenShaders.map { $0.code },
            parameters: document.paramValues,
            dataFlowConfig: document.dataFlow
        )
    }

    /// Exports this material back to a CanvasDocument for editing in ShaderCanvas.
    public func toCanvasDocument(meshType: MeshType = .sphere) -> CanvasDocument {
        var shaders: [ActiveShader] = []

        if let vs = vertexShaderSource {
            shaders.append(ActiveShader(category: .vertex, name: "Vertex", code: vs))
        }
        if !fragmentShaderSource.isEmpty {
            shaders.append(ActiveShader(category: .fragment, name: "Fragment", code: fragmentShaderSource))
        }
        for (i, pp) in postProcessSources.enumerated() {
            shaders.append(ActiveShader(category: .fullscreen, name: "PostProcess \(i + 1)", code: pp))
        }

        return CanvasDocument(
            name: name,
            meshType: meshType,
            shaders: shaders,
            dataFlow: dataFlowConfig,
            paramValues: parameters
        )
    }
}

// MARK: - .mcmat File I/O

extension MCMaterial {

    /// Saves this material to a `.mcmat` file (JSON format).
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Loads a material from a `.mcmat` file.
    public static func load(from url: URL) throws -> MCMaterial {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MCMaterial.self, from: data)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
