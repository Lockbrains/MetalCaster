import Metal
import CoreGraphics

/// Manages offscreen HDR textures and executes the post-processing pass chain.
///
/// The stack owns ping-pong HDR render targets and a depth texture.
/// The viewport renders the scene into `sceneColorTexture` + `sceneDepthTexture`,
/// then calls `execute(...)` or `executeVolume(...)` to process and blit to the drawable.
public final class PostProcessStack {

    private let device: MTLDevice
    private var legacyLibrary: MTLLibrary?
    private var effectsLibrary: MTLLibrary?

    // Ping-pong HDR textures
    private(set) var hdrTextureA: MTLTexture?
    private(set) var hdrTextureB: MTLTexture?
    private(set) var sceneDepthTexture: MTLTexture?

    // Bloom mip chain (downsample/upsample)
    private var bloomMipTextures: [MTLTexture] = []
    private var bloomMipCount: Int = 0

    private var currentWidth: Int = 0
    private var currentHeight: Int = 0

    // MARK: - Legacy Pipeline States

    private var exposurePipeline: MTLRenderPipelineState?
    private var dofBlurHPipeline: MTLRenderPipelineState?
    private var dofBlurVPipeline: MTLRenderPipelineState?
    private var motionBlurPipeline: MTLRenderPipelineState?
    private var blitPipeline: MTLRenderPipelineState?

    // MARK: - Volume-Based Pipeline States

    private var bloomDownsamplePipeline: MTLRenderPipelineState?
    private var bloomUpsamplePipeline: MTLRenderPipelineState?
    private var bloomCompositePipeline: MTLRenderPipelineState?
    private var colorGradingPipeline: MTLRenderPipelineState?
    private var vignettePipeline: MTLRenderPipelineState?
    private var chromaticAberrationPipeline: MTLRenderPipelineState?
    private var filmGrainPipeline: MTLRenderPipelineState?
    private var lensDistortionPipeline: MTLRenderPipelineState?
    private var paniniPipeline: MTLRenderPipelineState?
    private var ssaoPipeline: MTLRenderPipelineState?
    private var fxaaPipeline: MTLRenderPipelineState?
    private var fullscreenBlurPipeline: MTLRenderPipelineState?
    private var fullscreenOutlinePipeline: MTLRenderPipelineState?

    private var noDepthState: MTLDepthStencilState?

    public init(device: MTLDevice) {
        self.device = device
        compileLegacyPipelines()
        compileEffectPipelines()
        setupDepthState()
    }

    // MARK: - Texture Management

    public func ensureTextures(width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }
        guard width != currentWidth || height != currentHeight else { return }

        currentWidth = width
        currentHeight = height

        hdrTextureA = makeHDRTexture(width: width, height: height, label: "PostProcess HDR A")
        hdrTextureB = makeHDRTexture(width: width, height: height, label: "PostProcess HDR B")
        sceneDepthTexture = makeDepthTexture(width: width, height: height, label: "PostProcess Depth")

        rebuildBloomMipChain(width: width, height: height)
    }

    public var sceneColorTexture: MTLTexture? { hdrTextureA }

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

    // MARK: - Legacy Execute (backward compatible)

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

        if enableDoF, let pipeline = dofBlurHPipeline {
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &ppU, bufferLength: MemoryLayout<PostProcessUniforms>.stride)
            swap(&currentSource, &currentDest)
        }
        if enableDoF, let pipeline = dofBlurVPipeline {
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &ppU, bufferLength: MemoryLayout<PostProcessUniforms>.stride)
            swap(&currentSource, &currentDest)
        }
        if enableMotionBlur, let pipeline = motionBlurPipeline {
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &mbU, bufferLength: MemoryLayout<MotionBlurUniforms>.stride)
            swap(&currentSource, &currentDest)
        }
        if enableExposure, let pipeline = exposurePipeline {
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &ppU, bufferLength: MemoryLayout<PostProcessUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        if let pipeline = blitPipeline {
            encodeBlitPass(commandBuffer: commandBuffer, pipeline: pipeline, source: currentSource, destination: drawableTexture)
        }
    }

    // MARK: - Volume-Based Execute

    /// Executes the full volume-driven post-processing chain.
    ///
    /// Order: SSAO -> Bloom -> DoF -> Motion Blur -> Panini -> Color Grading ->
    /// Chromatic Aberration -> Lens Distortion -> Vignette -> Film Grain ->
    /// Fullscreen Blur -> Fullscreen Outline -> FXAA -> Blit
    public func executeVolume(
        commandBuffer: MTLCommandBuffer,
        drawableTexture: MTLTexture,
        settings: VolumePostProcessSettings
    ) {
        guard let texA = hdrTextureA, let texB = hdrTextureB, let depthTex = sceneDepthTexture else { return }

        var currentSource = texA
        var currentDest = texB

        // SSAO
        if settings.enableSSAO, let pipeline = ssaoPipeline {
            var u = settings.ssaoUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &u, bufferLength: MemoryLayout<SSAOUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Bloom (downsample -> upsample -> composite)
        if settings.enableBloom, let dsPipeline = bloomDownsamplePipeline,
           let usPipeline = bloomUpsamplePipeline, let compPipeline = bloomCompositePipeline,
           bloomMipTextures.count >= 2 {
            var bu = settings.bloomUniforms
            encodeBloomChain(commandBuffer: commandBuffer, source: currentSource, bloomUniforms: &bu,
                downsamplePipeline: dsPipeline, upsamplePipeline: usPipeline)
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: compPipeline, outputTexture: currentDest,
                textures: [currentSource, bloomMipTextures[0]], bufferData: &bu, bufferLength: MemoryLayout<BloomUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Depth of Field
        if settings.enableDoF, let hPipeline = dofBlurHPipeline, let vPipeline = dofBlurVPipeline {
            var u = settings.ppUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: hPipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &u, bufferLength: MemoryLayout<PostProcessUniforms>.stride)
            swap(&currentSource, &currentDest)
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: vPipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &u, bufferLength: MemoryLayout<PostProcessUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Motion Blur
        if settings.enableMotionBlur, let pipeline = motionBlurPipeline {
            var u = settings.mbUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &u, bufferLength: MemoryLayout<MotionBlurUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Panini Projection
        if settings.enablePanini, let pipeline = paniniPipeline {
            var u = settings.paniniUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<PaniniUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Color Grading (combined pass)
        if settings.enableColorGrading, let pipeline = colorGradingPipeline {
            var u = settings.colorGradingUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<ColorGradingUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Chromatic Aberration
        if settings.enableChromaticAberration, let pipeline = chromaticAberrationPipeline {
            var u = settings.chromaticAberrationUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<ChromaticAberrationUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Lens Distortion
        if settings.enableLensDistortion, let pipeline = lensDistortionPipeline {
            var u = settings.lensDistortionUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<LensDistortionUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Vignette
        if settings.enableVignette, let pipeline = vignettePipeline {
            var u = settings.vignetteUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<VignetteUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Film Grain
        if settings.enableFilmGrain, let pipeline = filmGrainPipeline {
            var u = settings.filmGrainUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<FilmGrainUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Fullscreen Blur
        if settings.enableFullscreenBlur, let pipeline = fullscreenBlurPipeline {
            var u = settings.fullscreenBlurUniforms
            let passes = u.blurMode == 0 ? 2 : max(1, Int(u.radius / 2))
            for i in 0..<passes {
                u.iteration = Float(i)
                encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                    textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<FullscreenBlurUniforms>.stride)
                swap(&currentSource, &currentDest)
            }
        }

        // Fullscreen Outline
        if settings.enableFullscreenOutline, let pipeline = fullscreenOutlinePipeline {
            var u = settings.fullscreenOutlineUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource, depthTex], bufferData: &u, bufferLength: MemoryLayout<FullscreenOutlineUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // FXAA
        if settings.enableFXAA, let pipeline = fxaaPipeline {
            var u = settings.fxaaUniforms
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: pipeline, outputTexture: currentDest,
                textures: [currentSource], bufferData: &u, bufferLength: MemoryLayout<FXAAUniforms>.stride)
            swap(&currentSource, &currentDest)
        }

        // Final Blit
        if let pipeline = blitPipeline {
            encodeBlitPass(commandBuffer: commandBuffer, pipeline: pipeline, source: currentSource, destination: drawableTexture)
        }
    }

    // MARK: - Bloom Chain

    private func encodeBloomChain(
        commandBuffer: MTLCommandBuffer,
        source: MTLTexture,
        bloomUniforms: inout BloomUniforms,
        downsamplePipeline: MTLRenderPipelineState,
        upsamplePipeline: MTLRenderPipelineState
    ) {
        guard bloomMipTextures.count >= 2 else { return }

        // Downsample from source to mip 0, then mip[i] -> mip[i+1]
        let savedThreshold = bloomUniforms.threshold
        var src = source
        for i in 0..<bloomMipTextures.count {
            bloomUniforms.screenWidth = Float(src.width)
            bloomUniforms.screenHeight = Float(src.height)
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: downsamplePipeline,
                outputTexture: bloomMipTextures[i], textures: [src],
                bufferData: &bloomUniforms, bufferLength: MemoryLayout<BloomUniforms>.stride)
            src = bloomMipTextures[i]
            bloomUniforms.threshold = 0
        }
        bloomUniforms.threshold = savedThreshold

        // Upsample: mip[n-1] -> mip[n-2] -> ... -> mip[0]
        for i in stride(from: bloomMipTextures.count - 1, through: 1, by: -1) {
            bloomUniforms.screenWidth = Float(bloomMipTextures[i - 1].width)
            bloomUniforms.screenHeight = Float(bloomMipTextures[i - 1].height)
            encodeFullscreenPass(commandBuffer: commandBuffer, pipeline: upsamplePipeline,
                outputTexture: bloomMipTextures[i - 1], textures: [bloomMipTextures[i]],
                bufferData: &bloomUniforms, bufferLength: MemoryLayout<BloomUniforms>.stride)
        }
    }

    private func rebuildBloomMipChain(width: Int, height: Int) {
        bloomMipTextures.removeAll()
        var w = width / 2
        var h = height / 2
        bloomMipCount = 0
        while w >= 2 && h >= 2 && bloomMipCount < 6 {
            if let tex = makeHDRTexture(width: w, height: h, label: "Bloom Mip \(bloomMipCount)") {
                bloomMipTextures.append(tex)
            }
            w /= 2; h /= 2; bloomMipCount += 1
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

    // MARK: - Pipeline Compilation

    private func compileLegacyPipelines() {
        let source = PostProcessShaders.allSource
        guard let lib = try? device.makeLibrary(source: source, options: nil) else {
            print("[PostProcessStack] Failed to compile legacy post-process shaders")
            return
        }
        self.legacyLibrary = lib

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

    private func compileEffectPipelines() {
        let source = PostProcessEffectShaders.allSource
        guard let lib = try? device.makeLibrary(source: source, options: nil) else {
            print("[PostProcessStack] Failed to compile effect shaders")
            return
        }
        self.effectsLibrary = lib

        guard let vertexFunc = lib.makeFunction(name: "pp_fullscreen_vertex") else {
            print("[PostProcessStack] Missing pp_fullscreen_vertex function")
            return
        }

        let hdr = MTLPixelFormat.rgba16Float
        bloomDownsamplePipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "bloom_downsample_fragment", format: hdr)
        bloomUpsamplePipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "bloom_upsample_fragment", format: hdr)
        bloomCompositePipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "bloom_composite_fragment", format: hdr)
        colorGradingPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "color_grading_fragment", format: hdr)
        vignettePipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "vignette_fragment", format: hdr)
        chromaticAberrationPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "chromatic_aberration_fragment", format: hdr)
        filmGrainPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "film_grain_fragment", format: hdr)
        lensDistortionPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "lens_distortion_fragment", format: hdr)
        paniniPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "panini_fragment", format: hdr)
        ssaoPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "ssao_fragment", format: hdr)
        fxaaPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "fxaa_fragment", format: hdr)
        fullscreenBlurPipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "fullscreen_blur_fragment", format: hdr)
        fullscreenOutlinePipeline = makePipeline(lib: lib, vertex: vertexFunc, fragment: "fullscreen_outline_fragment", format: hdr)
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
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        tex?.label = label
        return tex
    }

    private func makeDepthTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        tex?.label = label
        return tex
    }
}

// MARK: - Volume Post Process Settings

/// Aggregated settings struct passed to `executeVolume()`, built from resolved volume data.
public struct VolumePostProcessSettings {
    public var enableBloom: Bool = false
    public var enableDoF: Bool = false
    public var enableMotionBlur: Bool = false
    public var enableColorGrading: Bool = false
    public var enableVignette: Bool = false
    public var enableChromaticAberration: Bool = false
    public var enableFilmGrain: Bool = false
    public var enableLensDistortion: Bool = false
    public var enablePanini: Bool = false
    public var enableSSAO: Bool = false
    public var enableFXAA: Bool = false
    public var enableFullscreenBlur: Bool = false
    public var enableFullscreenOutline: Bool = false

    public var bloomUniforms: BloomUniforms = .init()
    public var ppUniforms: PostProcessUniforms = .init()
    public var mbUniforms: MotionBlurUniforms = .init()
    public var colorGradingUniforms: ColorGradingUniforms = .init()
    public var vignetteUniforms: VignetteUniforms = .init()
    public var chromaticAberrationUniforms: ChromaticAberrationUniforms = .init()
    public var filmGrainUniforms: FilmGrainUniforms = .init()
    public var lensDistortionUniforms: LensDistortionUniforms = .init()
    public var paniniUniforms: PaniniUniforms = .init()
    public var ssaoUniforms: SSAOUniforms = .init()
    public var fxaaUniforms: FXAAUniforms = .init()
    public var fullscreenBlurUniforms: FullscreenBlurUniforms = .init()
    public var fullscreenOutlineUniforms: FullscreenOutlineUniforms = .init()

    public init() {}
}
