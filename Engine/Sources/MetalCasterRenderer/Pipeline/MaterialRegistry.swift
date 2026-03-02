import Metal
import MetalKit
import Foundation

/// Central registry for engine-provided built-in materials.
///
/// Built-in materials cannot be modified by users. They provide
/// production-quality defaults for common rendering needs.
/// Call `warmup(device:vertexDescriptor:)` during engine initialization
/// to pre-compile all built-in pipeline states.
public final class MaterialRegistry: @unchecked Sendable {

    public static let shared = MaterialRegistry()

    // MARK: - Built-in Material IDs (deterministic, stable across sessions)

    public static let unlitMaterialID  = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let litMaterialID    = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    public static let toonMaterialID   = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    public static let skyboxMaterialID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    // MARK: - Built-in Material Definitions

    public static let unlitMaterial = MCMaterial(
        id: unlitMaterialID,
        name: "MC_Unlit",
        materialType: .builtin,
        renderState: .opaque,
        unifiedShaderSource: BuiltinShaders.unlitSource,
        dataFlowConfig: BuiltinShaders.unlitDataFlow
    )

    public static let litMaterial = MCMaterial(
        id: litMaterialID,
        name: "MC_Lit",
        materialType: .builtin,
        renderState: .opaque,
        unifiedShaderSource: BuiltinShaders.litSource,
        dataFlowConfig: BuiltinShaders.litDataFlow
    )

    public static let toonMaterial = MCMaterial(
        id: toonMaterialID,
        name: "MC_Toon",
        materialType: .builtin,
        renderState: .opaque,
        unifiedShaderSource: BuiltinShaders.toonSource,
        dataFlowConfig: BuiltinShaders.toonDataFlow
    )

    public static let skyboxMaterial = MCMaterial(
        id: skyboxMaterialID,
        name: "MC_Skybox",
        materialType: .builtin,
        renderState: .skybox,
        unifiedShaderSource: BuiltinShaders.skyboxSource
    )

    // MARK: - Registry Storage

    private var materials: [UUID: MCMaterial] = [:]
    private var pipelineStates: [UUID: MTLRenderPipelineState] = [:]
    private var depthStencilStates: [UUID: MTLDepthStencilState] = [:]
    private var isWarmedUp = false

    /// The default engine HDRI skybox texture (loaded from Bundle.module).
    public private(set) var defaultSkyboxTexture: MTLTexture?

    /// 1x1 white placeholder texture, bound when a material has no real texture.
    public private(set) var placeholderWhiteTexture: MTLTexture?

    /// Cache for material textures keyed by file path.
    private var textureCache: [String: MTLTexture] = [:]
    private var textureCacheLock = NSLock()

    private init() {
        register(Self.unlitMaterial)
        register(Self.litMaterial)
        register(Self.toonMaterial)
        register(Self.skyboxMaterial)
    }

    // MARK: - Registration

    private func register(_ material: MCMaterial) {
        materials[material.id] = material
    }

    // MARK: - Queries

    /// Returns the built-in material definition for the given ID, or nil if not registered.
    public func builtinMaterial(_ id: UUID) -> MCMaterial? {
        materials[id]
    }

    /// Whether the given material ID is a built-in material.
    public func isBuiltin(_ id: UUID) -> Bool {
        materials[id] != nil
    }

    /// All registered built-in materials.
    public var allBuiltinMaterials: [MCMaterial] {
        Array(materials.values)
    }

    /// Returns the pre-compiled pipeline state for a built-in material.
    public func pipelineState(for materialID: UUID) -> MTLRenderPipelineState? {
        pipelineStates[materialID]
    }

    /// Returns the pre-compiled depth stencil state for a built-in material.
    public func depthStencilState(for materialID: UUID) -> MTLDepthStencilState? {
        depthStencilStates[materialID]
    }

    // MARK: - Warmup

    /// Pre-compiles all built-in material pipeline states.
    /// Call this once during engine initialization.
    ///
    /// - Parameters:
    ///   - device: The Metal device to compile against.
    ///   - vertexDescriptor: The standard mesh vertex descriptor.
    ///   - colorFormat: Target color pixel format.
    ///   - depthFormat: Target depth pixel format.
    public func warmup(
        device: MTLDevice,
        vertexDescriptor: MTLVertexDescriptor,
        colorFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float
    ) {
        guard !isWarmedUp else { return }

        let compiler = ShaderCompiler(device: device)

        for (id, material) in materials {
            guard let source = material.unifiedShaderSource else { continue }

            do {
                let pso = try compiler.compileUnifiedPipeline(
                    source: source,
                    renderState: material.renderState,
                    colorFormat: colorFormat,
                    depthFormat: depthFormat,
                    vertexDescriptor: vertexDescriptor
                )
                pipelineStates[id] = pso
            } catch {
                print("[MaterialRegistry] Failed to compile \(material.name): \(error)")
            }

            let depthDesc = MTLDepthStencilDescriptor()
            depthDesc.depthCompareFunction = material.renderState.depthTest.metalCompareFunction
            depthDesc.isDepthWriteEnabled = material.renderState.depthWrite
            if let dss = device.makeDepthStencilState(descriptor: depthDesc) {
                depthStencilStates[id] = dss
            }
        }

        let loader = TextureLoader(device: device)
        defaultSkyboxTexture = loader.loadDefaultSkyboxHDRI()
        if defaultSkyboxTexture != nil {
            print("[MaterialRegistry] Default skybox HDRI loaded")
        }

        placeholderWhiteTexture = Self.createPlaceholderTexture(device: device)

        isWarmedUp = true
    }

    /// Loads a skybox HDRI texture from an arbitrary file URL.
    /// Used when a scene's SkyboxComponent specifies a custom HDRI path.
    public func loadSkyboxTexture(from url: URL, device: MTLDevice) -> MTLTexture? {
        let loader = TextureLoader(device: device)
        return loader.loadTexture(from: url, sRGB: false)
    }

    /// Compiles the skybox fallback pipeline (gradient sky, no HDRI texture).
    public func compileSkyboxFallback(
        device: MTLDevice,
        vertexDescriptor: MTLVertexDescriptor,
        colorFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .depth32Float
    ) -> MTLRenderPipelineState? {
        let compiler = ShaderCompiler(device: device)
        return try? compiler.compileUnifiedPipeline(
            source: BuiltinShaders.skyboxFallbackSource,
            renderState: .skybox,
            colorFormat: colorFormat,
            depthFormat: depthFormat,
            vertexDescriptor: vertexDescriptor
        )
    }

    /// Resets all compiled state (e.g. after device loss).
    public func invalidate() {
        pipelineStates.removeAll()
        depthStencilStates.removeAll()
        textureCache.removeAll()
        placeholderWhiteTexture = nil
        isWarmedUp = false
    }

    /// Returns a cached texture for the given path, loading it on first access.
    public func texture(forPath path: String, device: MTLDevice) -> MTLTexture? {
        textureCacheLock.lock()
        defer { textureCacheLock.unlock() }

        if let cached = textureCache[path] { return cached }
        let url = URL(fileURLWithPath: path)
        let loader = TextureLoader(device: device)
        guard let tex = loader.loadTexture(from: url, sRGB: true) else { return nil }
        textureCache[path] = tex
        return tex
    }

    private static func createPlaceholderTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        var white: [UInt8] = [255, 255, 255, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: &white, bytesPerRow: 4)
        return tex
    }
}
