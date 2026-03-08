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

    /// Identifies which shader this material uses.
    /// Built-in shaders: "builtin/lit", "builtin/unlit", "builtin/toon".
    /// Project shaders: relative path e.g. "Shaders/MyShader.metal".
    /// When set, the engine resolves the actual shader source from this reference
    /// rather than from `unifiedShaderSource` / `fragmentShaderSource` directly.
    public var shaderReference: String?

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
        surfaceProperties: MCMaterialProperties = MCMaterialProperties(),
        shaderReference: String? = nil
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
        self.shaderReference = shaderReference
    }

    // Custom Codable to maintain backward compatibility with scenes saved before
    // materialType / renderState / unifiedShaderSource were added.

    private enum CodingKeys: String, CodingKey {
        case id, name, materialType, renderState
        case vertexShaderSource, fragmentShaderSource, unifiedShaderSource
        case postProcessSources, parameters, dataFlowConfig, surfaceProperties
        case shaderReference
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
        shaderReference = try c.decodeIfPresent(String.self, forKey: .shaderReference)
    }

    /// Whether this material uses light data (buffer index 3/4).
    public var needsLighting: Bool {
        if let ref = shaderReference {
            switch ref {
            case "builtin/lit", "builtin/toon": return true
            case "builtin/unlit": return false
            default: break
            }
        }

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
    public let isHDR: Bool

    public init(shaderSourceHash: Int, blendMode: MCBlendMode, depthWrite: Bool, cullMode: MCCullMode, isHDR: Bool = false) {
        self.shaderSourceHash = shaderSourceHash
        self.blendMode = blendMode
        self.depthWrite = depthWrite
        self.cullMode = cullMode
        self.isHDR = isHDR
    }

    public func withHDR(_ hdr: Bool) -> PipelineCacheKey {
        PipelineCacheKey(shaderSourceHash: shaderSourceHash, blendMode: blendMode, depthWrite: depthWrite, cullMode: cullMode, isHDR: hdr)
    }
}

// MARK: - CanvasDocument Conversion

extension MCMaterial {

    /// Creates a custom material from a ShaderCanvas workspace document.
    ///
    /// Extracts the active vertex and fragment shaders, combines them with the
    /// shared header from DataFlowConfig, and packages parameters into a material.
    /// Creates an MCMaterial from a Shader Canvas Pro document.
    /// Generates a self-contained `unifiedShaderSource` that includes all
    /// required definitions (header, studio lighting, helpers, params).
    public init(from document: CanvasDocument) {
        let vertexCode = document.shaders.last(where: { $0.category == .vertex })?.code
        let fragmentCode = document.shaders.last(where: { $0.category == .fragment })?.code ?? ""
        let fullscreenShaders = document.shaders.filter { $0.category == .fullscreen }
        let helpers = document.shaders
            .filter { $0.category == .helper }
            .map(\.code)
            .joined(separator: "\n\n")

        let hasMeshShaders = !fragmentCode.isEmpty || vertexCode != nil

        var unified: String? = nil
        if hasMeshShaders {
            var src = ShaderSnippets.generateSharedHeader(config: document.dataFlow)

            let needsStudioPreamble = fragmentCode.contains("studioLights")
                || fragmentCode.contains("studioLightCount")
                || fragmentCode.contains("StudioLight")
            if needsStudioPreamble {
                src += ShaderSnippets.studioLightPreamble + "\n"
            }

            if !helpers.isEmpty {
                src += "\n// === Helper Functions ===\n" + helpers + "\n// === End Helpers ===\n\n"
            }

            let params = ShaderSnippets.parseParams(from: fragmentCode)
            src += ShaderSnippets.generateParamHeader(params: params)

            src += vertexCode ?? ShaderSnippets.generateDefaultVertexShader(config: document.dataFlow)
            src += "\n\n"

            // Inject `constant float *params [[buffer(2)]]` into fragment_main
            // if params exist but the signature doesn't already declare it.
            var processedFragment = fragmentCode
            if !params.isEmpty {
                processedFragment = ShaderSnippets.injectParamsBuffer(
                    into: processedFragment, paramCount: params.count)
            }

            // Remap fragment params buffer from Canvas convention (index 2)
            // to main editor convention (index 5).
            let adaptedFragment = processedFragment
                .replacingOccurrences(of: "[[buffer(2)]]", with: "[[buffer(5)]]")
            src += adaptedFragment

            unified = src
        }

        self.init(
            name: document.name,
            materialType: .custom,
            vertexShaderSource: vertexCode,
            fragmentShaderSource: fragmentCode,
            unifiedShaderSource: unified,
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

// MARK: - Shader Parameter Annotations

/// A parameter exposed by a shader via `// @param` annotations.
/// Format: `// @param <name> <type> <default> [<min> <max>]`
///
/// Supported types: `float`, `float2`, `float3`, `float4`, `color3`, `color4`
///
/// Example:
/// ```
/// // @param brightness float 1.0 0.0 5.0
/// // @param tintColor color3 1.0 0.5 0.2
/// // @param offset float2 0.0 0.0
/// ```
public struct ShaderParameter: Codable, Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let type: ParamType
    public var defaultValue: [Float]
    public var minValue: Float?
    public var maxValue: Float?

    public enum ParamType: String, Codable, Sendable {
        case float, float2, float3, float4, color3, color4

        public var componentCount: Int {
            switch self {
            case .float:  return 1
            case .float2: return 2
            case .float3, .color3: return 3
            case .float4, .color4: return 4
            }
        }

        public var isColor: Bool {
            self == .color3 || self == .color4
        }
    }
}

/// Parses `// @param` annotations from MSL shader source.
public struct ShaderParameterParser {

    public static func parse(source: String) -> [ShaderParameter] {
        var params: [ShaderParameter] = []

        for line in source.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("// @param ") else { continue }

            let tokens = trimmed.dropFirst("// @param ".count)
                .split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard tokens.count >= 2 else { continue }

            let name = tokens[0]
            guard let type = ShaderParameter.ParamType(rawValue: tokens[1]) else { continue }

            let componentCount = type.componentCount
            var defaultValue = [Float](repeating: 0, count: componentCount)
            var minVal: Float? = nil
            var maxVal: Float? = nil

            let remaining = Array(tokens.dropFirst(2))

            for i in 0..<min(componentCount, remaining.count) {
                if let f = Float(remaining[i]) {
                    defaultValue[i] = f
                }
            }

            let afterDefault = remaining.dropFirst(componentCount)
            if afterDefault.count >= 2 {
                minVal = Float(afterDefault[afterDefault.startIndex])
                maxVal = Float(afterDefault[afterDefault.startIndex + 1])
            }

            params.append(ShaderParameter(
                name: name,
                type: type,
                defaultValue: defaultValue,
                minValue: minVal,
                maxValue: maxVal
            ))
        }

        return params
    }

    /// Packs material parameter values into a flat float array for GPU binding.
    /// Parameters are packed in declaration order from the shader.
    public static func packParameters(
        params: [ShaderParameter],
        values: [String: [Float]]
    ) -> [Float] {
        var packed: [Float] = []
        for param in params {
            let val = values[param.name] ?? param.defaultValue
            let count = param.type.componentCount
            for i in 0..<count {
                packed.append(i < val.count ? val[i] : 0)
            }
        }
        return packed
    }
}
