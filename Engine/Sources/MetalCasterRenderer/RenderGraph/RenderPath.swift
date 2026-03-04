import Metal
import MetalKit
import simd

// MARK: - Render Path Protocol

/// Defines a complete rendering strategy (e.g., Forward, Deferred).
/// Each path configures and executes a specific sequence of render passes.
public protocol MCRenderPath: AnyObject {
    var name: String { get }

    /// One-time setup with the Metal device.
    func setup(device: MCMetalDevice) throws

    /// Called when the drawable size changes.
    func resize(width: Int, height: Int)

    /// Executes the full render path for a single frame.
    func execute(
        frame: FrameDescriptor,
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice
    )
}

// MARK: - Frame Descriptor

/// All the data needed to render one frame, passed to the RenderPath.
/// References types defined in MaterialSystem (MCMaterial, GPUMaterialProperties)
/// and LightingSystem (GPULightData) to avoid duplication.
public struct FrameDescriptor {
    public var drawableTexture: MTLTexture
    public var depthTexture: MTLTexture?
    public var drawableSize: CGSize

    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var cameraPosition: SIMD3<Float>
    public var clearColor: MTLClearColor

    /// References to mesh data + materials, pre-sorted by the scene layer.
    public var meshDrawCalls: [MeshDrawEntry]

    public var totalTime: Float
    public var deltaTime: Float

    /// Skybox configuration
    public var skyboxEnabled: Bool
    public var skyboxUniforms: SkyboxUniforms?
    public var skyboxTexture: MTLTexture?
    public var skyboxPipeline: MTLRenderPipelineState?

    /// Post-processing configuration
    public var enablePostProcess: Bool
    public var volumeSettings: VolumePostProcessSettings?
    public var ppUniforms: PostProcessUniforms?
    public var mbUniforms: MotionBlurUniforms?

    public init(
        drawableTexture: MTLTexture,
        drawableSize: CGSize,
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        cameraPosition: SIMD3<Float> = .zero,
        clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) {
        self.drawableTexture = drawableTexture
        self.drawableSize = drawableSize
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.cameraPosition = cameraPosition
        self.clearColor = clearColor
        self.meshDrawCalls = []
        self.totalTime = 0
        self.deltaTime = 0
        self.skyboxEnabled = false
        self.enablePostProcess = false
    }
}

// MARK: - Mesh Draw Entry

/// A lightweight draw entry referencing all GPU-ready data for one mesh.
/// Decoupled from scene-layer DrawCall for use in the render path.
public struct MeshDrawEntry {
    public var meshType: MeshType
    public var worldMatrix: simd_float4x4
    public var normalMatrix: simd_float4x4
    public var pipeline: MTLRenderPipelineState?
    public var material: MCMaterial
    public var castsShadow: Bool

    public init(
        meshType: MeshType,
        worldMatrix: simd_float4x4,
        normalMatrix: simd_float4x4,
        pipeline: MTLRenderPipelineState? = nil,
        material: MCMaterial,
        castsShadow: Bool = true
    ) {
        self.meshType = meshType
        self.worldMatrix = worldMatrix
        self.normalMatrix = normalMatrix
        self.pipeline = pipeline
        self.material = material
        self.castsShadow = castsShadow
    }
}

// MARK: - Render Path Type

/// The available render path strategies.
public enum RenderPathType: String, CaseIterable, Sendable {
    case forward = "Forward"
    case deferred = "Deferred"
}
