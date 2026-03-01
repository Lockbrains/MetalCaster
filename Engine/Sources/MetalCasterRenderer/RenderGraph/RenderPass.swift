import Metal
import CoreGraphics

/// Protocol for a single rendering pass in the render graph.
///
/// Each pass reads from input textures, writes to output textures,
/// and encodes GPU commands via a render command encoder.
public protocol RenderPass: AnyObject {
    /// Human-readable name for debugging.
    var name: String { get }

    /// Whether this pass is currently enabled.
    var isEnabled: Bool { get set }

    /// Encodes the pass's GPU commands into the given command buffer.
    ///
    /// - Parameters:
    ///   - commandBuffer: The frame's command buffer to encode into.
    ///   - device: The Metal device wrapper.
    ///   - context: Shared rendering context for this frame.
    func encode(
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        context: inout RenderContext
    )
}

/// Shared context passed through the render graph for a single frame.
/// Contains textures and state that passes read from and write to.
public struct RenderContext {
    /// Primary offscreen render target (ping-pong buffer A).
    public var offscreenTextureA: MTLTexture?

    /// Secondary offscreen render target (ping-pong buffer B).
    public var offscreenTextureB: MTLTexture?

    /// Depth buffer for the mesh rendering pass.
    public var depthTexture: MTLTexture?

    /// The current "source" texture (result of the last pass).
    public var currentSourceTexture: MTLTexture?

    /// The current "destination" texture (target for the next pass).
    public var currentDestTexture: MTLTexture?

    /// The background texture (user-uploaded image).
    public var backgroundTexture: MTLTexture?

    /// The drawable size in pixels.
    public var drawableSize: CGSize

    /// Per-frame uniforms.
    public var uniforms: Uniforms

    /// Active shader layers.
    public var activeShaders: [ActiveShader]

    /// Current user parameter values.
    public var paramValues: [String: [Float]]

    /// The data flow configuration.
    public var dataFlowConfig: DataFlowConfig

    public init(
        drawableSize: CGSize = .zero,
        uniforms: Uniforms = Uniforms(),
        activeShaders: [ActiveShader] = [],
        paramValues: [String: [Float]] = [:],
        dataFlowConfig: DataFlowConfig = DataFlowConfig()
    ) {
        self.drawableSize = drawableSize
        self.uniforms = uniforms
        self.activeShaders = activeShaders
        self.paramValues = paramValues
        self.dataFlowConfig = dataFlowConfig
    }

    /// Swaps the current source and destination textures (ping-pong).
    public mutating func swapPingPong() {
        let temp = currentSourceTexture
        currentSourceTexture = currentDestTexture
        currentDestTexture = temp
    }
}
