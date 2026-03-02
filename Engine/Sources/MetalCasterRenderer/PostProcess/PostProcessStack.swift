import Metal
import CoreGraphics

/// Manages offscreen HDR textures and executes the post-processing pass chain.
///
/// The stack owns ping-pong HDR render targets and a depth texture.
/// The viewport renders the scene into `sceneColorTexture` + `sceneDepthTexture`,
/// then calls `execute(...)` to run DoF -> Exposure -> Motion Blur -> blit to drawable.
public final class PostProcessStack {

    private let device: MTLDevice
    private var library: MTLLibrary?

    // Ping-pong HDR textures
    private(set) var hdrTextureA: MTLTexture?
    private(set) var hdrTextureB: MTLTexture?
    private(set) var sceneDepthTexture: MTLTexture?

    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    // Pipeline states
    private var exposurePipeline: MTLRenderPipelineState?
    private var dofBlurHPipeline: MTLRenderPipelineState?
    private var dofBlurVPipeline: MTLRenderPipelineState?
    private var motionBlurPipeline: MTLRenderPipelineState?
    private var blitPipeline: MTLRenderPipelineState?

    // Depth stencil state (no depth for fullscreen passes)
    private var noDepthState: MTLDepthStencilState?

    public init(device: MTLDevice) {
        self.device = device
        compilePipelines()
        setupDepthState()
    }

    // MARK: - Texture Management

    /// Ensures HDR textures exist at the given size. Recreates if size changed.
    public func ensureTextures(width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }
        guard width != currentWidth || height != currentHeight else { return }

        currentWidth = width
        currentHeight = height

        hdrTextureA = makeHDRTexture(width: width, height: height, label: "PostProcess HDR A")
        hdrTextureB = makeHDRTexture(width: width, height: height, label: "PostProcess HDR B")
        sceneDepthTexture = makeDepthTexture(width: width, height: height, label: "PostProcess Depth")
    }

    /// The scene color render target (HDR). Render your scene into this.
    public var sceneColorTexture: MTLTexture? { hdrTextureA }

    /// Render pass descriptor configured for scene rendering into offscreen targets.
    public func sceneRenderPassDescriptor(clearColor: MTLClearColor) -> MTLRenderPassDescriptor? {
        guard let color = hdrTextureA, let depth = sceneDepthTexture else { return nil }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = color
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = clearColor

        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0

        return rpd
    }

    // MARK: - Execute Post-Processing Chain

    /// Runs the full post-processing chain and blits the result to the given drawable texture.
    ///
    /// - Parameters:
    ///   - commandBuffer: The frame's command buffer.
    ///   - drawableTexture: The final output (e.g., MTKView's currentDrawable.texture).
    ///   - ppUniforms: Exposure/DoF parameters.
    ///   - mbUniforms: Motion blur parameters.
    ///   - enableDoF: Whether depth of field is active.
    ///   - enableExposure: Whether exposure/tone mapping is active.
    ///   - enableMotionBlur: Whether motion blur is active.
    public func execute(
        commandBuffer: MTLCommandBuffer,
        drawableTexture: MTLTexture,
        ppUniforms: PostProcessUniforms,
        mbUniforms: MotionBlurUniforms,
        enableDoF: Bool,
        enableExposure: Bool,
        enableMotionBlur: Bool
    ) {
        guard let texA = hdrTextureA, let texB = hdrTextureB, let depthTex = sceneDepthTexture else { return }

        var currentSource = texA
        var currentDest = texB

        var ppU = ppUniforms
        var mbU = mbUniforms

        // Pass 1: Depth of Field (horizontal)
        if enableDoF, let pipeline = dofBlurHPipeline {
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                pipeline: pipeline,
                outputTexture: currentDest,
                textures: [currentSource, depthTex],
                bufferData: &ppU,
                bufferLength: MemoryLayout<PostProcessUniforms>.stride
            )
            swap(&currentSource, &currentDest)
        }

        // Pass 2: Depth of Field (vertical)
        if enableDoF, let pipeline = dofBlurVPipeline {
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                pipeline: pipeline,
                outputTexture: currentDest,
                textures: [currentSource, depthTex],
                bufferData: &ppU,
                bufferLength: MemoryLayout<PostProcessUniforms>.stride
            )
            swap(&currentSource, &currentDest)
        }

        // Pass 3: Motion Blur
        if enableMotionBlur, let pipeline = motionBlurPipeline {
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                pipeline: pipeline,
                outputTexture: currentDest,
                textures: [currentSource, depthTex],
                bufferData: &mbU,
                bufferLength: MemoryLayout<MotionBlurUniforms>.stride
            )
            swap(&currentSource, &currentDest)
        }

        // Pass 4: Exposure + Tone Mapping
        if enableExposure, let pipeline = exposurePipeline {
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                pipeline: pipeline,
                outputTexture: currentDest,
                textures: [currentSource],
                bufferData: &ppU,
                bufferLength: MemoryLayout<PostProcessUniforms>.stride
            )
            swap(&currentSource, &currentDest)
        }

        // Final Blit to drawable
        if let pipeline = blitPipeline {
            encodeBlitPass(
                commandBuffer: commandBuffer,
                pipeline: pipeline,
                source: currentSource,
                destination: drawableTexture
            )
        }
    }

    // MARK: - Private Helpers

    private func encodeFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        outputTexture: MTLTexture,
        textures: [MTLTexture],
        bufferData: UnsafeMutableRawPointer,
        bufferLength: Int
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = outputTexture
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(pipeline)

        for (index, tex) in textures.enumerated() {
            encoder.setFragmentTexture(tex, index: index)
        }
        encoder.setFragmentBytes(bufferData, length: bufferLength, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeBlitPass(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        source: MTLTexture,
        destination: MTLTexture
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = destination
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func compilePipelines() {
        let source = PostProcessShaders.allSource
        guard let lib = try? device.makeLibrary(source: source, options: nil) else {
            print("[PostProcessStack] Failed to compile post-process shaders")
            return
        }
        self.library = lib

        guard let vertexFunc = lib.makeFunction(name: "fullscreen_vertex") else {
            print("[PostProcessStack] Missing fullscreen_vertex function")
            return
        }

        exposurePipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "exposure_tonemapping_fragment", format: .rgba16Float)
        dofBlurHPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "dof_blur_h_fragment", format: .rgba16Float)
        dofBlurVPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "dof_blur_v_fragment", format: .rgba16Float)
        motionBlurPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "motion_blur_fragment", format: .rgba16Float)
        blitPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "blit_fragment", format: .bgra8Unorm_srgb)
    }

    private func makePipeline(lib: MTLLibrary, vertex: MTLFunction, fragment fragName: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        guard let fragFunc = lib.makeFunction(name: fragName) else {
            print("[PostProcessStack] Missing function: \(fragName)")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = format
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func setupDepthState() {
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = .always
        desc.isDepthWriteEnabled = false
        noDepthState = device.makeDepthStencilState(descriptor: desc)
    }

    private func makeHDRTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        tex?.label = label
        return tex
    }

    private func makeDepthTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        tex?.label = label
        return tex
    }
}
