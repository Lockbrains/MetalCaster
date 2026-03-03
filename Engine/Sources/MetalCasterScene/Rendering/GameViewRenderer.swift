#if canImport(AppKit)
import Foundation
import simd
import MetalKit
import Metal
import MetalCasterCore
import MetalCasterRenderer

/// A full-featured MTKViewDelegate that renders the game scene with
/// materials, skybox, lighting, and post-processing — matching what
/// the editor's Game Viewport shows. Used by Play-in-Editor preview
/// and standalone game builds.
public final class GameViewRenderer: NSObject, MTKViewDelegate {

    // MARK: - Engine Systems

    public let engine: Engine
    public let cameraSystem: CameraSystem
    public let lightingSystem: LightingSystem
    public let meshRenderSystem: MeshRenderSystem
    public let skyboxSystem: SkyboxSystem
    public var postProcessVolumeSystem: PostProcessVolumeSystem?

    // MARK: - Metal State

    private var metalDevice: MCMetalDevice?
    private var meshPool: MeshPool?
    private var shaderCompiler: ShaderCompiler?
    private var materialPipelineCache: PipelineCache?
    private var postProcessStack: PostProcessStack?

    // MARK: - Pipelines

    private var renderedPipeline: MTLRenderPipelineState?
    private var hdrRenderedPipeline: MTLRenderPipelineState?
    private var skyboxFallbackPipeline: MTLRenderPipelineState?
    private var hdrSkyboxFallbackPipeline: MTLRenderPipelineState?

    // MARK: - Skybox Texture Cache

    private var customSkyboxTexture: MTLTexture?
    private var cachedSkyboxPath: String?

    // MARK: - Init

    public init(
        engine: Engine,
        cameraSystem: CameraSystem,
        lightingSystem: LightingSystem,
        meshRenderSystem: MeshRenderSystem,
        skyboxSystem: SkyboxSystem,
        postProcessVolumeSystem: PostProcessVolumeSystem? = nil
    ) {
        self.engine = engine
        self.cameraSystem = cameraSystem
        self.lightingSystem = lightingSystem
        self.meshRenderSystem = meshRenderSystem
        self.skyboxSystem = skyboxSystem
        self.postProcessVolumeSystem = postProcessVolumeSystem
        super.init()
    }

    // MARK: - Setup

    public func setup(device: MTLDevice) {
        metalDevice = MCMetalDevice(device: device)
        meshPool = MeshPool(device: device)
        shaderCompiler = ShaderCompiler(device: device)

        if let compiler = shaderCompiler {
            materialPipelineCache = PipelineCache(compiler: compiler)
        }

        if let vd = MeshPool.metalVertexDescriptor {
            MaterialRegistry.shared.warmup(
                device: device,
                vertexDescriptor: vd,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float
            )
            skyboxFallbackPipeline = MaterialRegistry.shared.compileSkyboxFallback(
                device: device,
                vertexDescriptor: vd,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float
            )
            hdrSkyboxFallbackPipeline = MaterialRegistry.shared.compileSkyboxFallback(
                device: device,
                vertexDescriptor: vd,
                colorFormat: .rgba16Float,
                depthFormat: .depth32Float
            )
        }

        let config = DataFlowConfig()
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let defaultVS = header + ShaderSnippets.generateDefaultVertexShader(config: config)
        renderedPipeline = try? shaderCompiler?.compilePipeline(
            vertexSource: defaultVS,
            fragmentSource: header + ShaderSnippets.defaultFragment,
            colorFormat: .bgra8Unorm_srgb,
            depthFormat: .depth32Float,
            vertexDescriptor: MeshPool.metalVertexDescriptor
        )
        hdrRenderedPipeline = try? shaderCompiler?.compilePipeline(
            vertexSource: defaultVS,
            fragmentSource: header + ShaderSnippets.defaultFragment,
            colorFormat: .rgba16Float,
            depthFormat: .depth32Float,
            vertexDescriptor: MeshPool.metalVertexDescriptor
        )
        postProcessStack = PostProcessStack(device: device)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cameraSystem.aspectRatio = Float(size.width / size.height)
    }

    public func draw(in view: MTKView) {
        engine.tick(deltaTime: 1.0 / Float(view.preferredFramesPerSecond.nonZeroOr(60)))

        guard let device = metalDevice,
              let commandBuffer = device.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let pool = meshPool else { return }

        let camSys = cameraSystem
        let hasVolumePostProcess = postProcessVolumeSystem?.hasActiveVolume ?? false
        let usePostProcess = camSys.allowPostProcessing
            && (camSys.usePhysicalProperties || hasVolumePostProcess)
            && postProcessStack != nil
            && hdrRenderedPipeline != nil

        let viewMatrix = camSys.viewMatrix
        let projMatrix = camSys.projectionMatrix
        let eye = camSys.cameraPosition

        let activePipeline = usePostProcess ? hdrRenderedPipeline : renderedPipeline
        guard let pipeline = activePipeline else { return }

        // Build render pass descriptor
        let rpd: MTLRenderPassDescriptor
        if usePostProcess, let ppStack = postProcessStack {
            let w = Int(view.drawableSize.width)
            let h = Int(view.drawableSize.height)
            ppStack.ensureTextures(width: w, height: h)
            let cc = camSys.clearColor
            let clearColor = MTLClearColor(
                red: Double(cc.x), green: Double(cc.y),
                blue: Double(cc.z), alpha: Double(cc.w)
            )
            guard let offscreenRPD = ppStack.sceneRenderPassDescriptor(clearColor: clearColor) else { return }
            rpd = offscreenRPD
        } else {
            guard let viewRPD = view.currentRenderPassDescriptor else { return }
            rpd = viewRPD
        }

        // Scene rendering pass
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            encoder.setFrontFacing(.counterClockwise)
            encoder.setDepthStencilState(device.depthStencilState)

            drawSkybox(
                encoder: encoder, device: device, pool: pool,
                viewMatrix: viewMatrix, projMatrix: projMatrix,
                useHDR: usePostProcess
            )

            encoder.setDepthStencilState(device.depthStencilState)

            var lightsData = lightingSystem.lights
            var lightCount = lightingSystem.lightCount

            for drawCall in meshRenderSystem.drawCalls {
                let mvp = projMatrix * viewMatrix * drawCall.worldMatrix
                var uniforms = Uniforms(
                    mvpMatrix: mvp,
                    modelMatrix: drawCall.worldMatrix,
                    normalMatrix: drawCall.normalMatrix,
                    cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 0),
                    time: engine.totalTime
                )
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

                if let materialPSO = resolveMaterialPipeline(
                    for: drawCall.material, device: device, useHDR: usePostProcess
                ) {
                    encoder.setRenderPipelineState(materialPSO)
                    let rs = drawCall.material.renderState
                    encoder.setCullMode(rs.cullMode.metalCullMode)
                    if let dss = materialPipelineCache?.depthStencilState(for: rs, device: device.device) {
                        encoder.setDepthStencilState(dss)
                    }
                } else {
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setCullMode(.none)
                    encoder.setDepthStencilState(device.depthStencilState)
                }

                var gpuMat = GPUMaterialProperties(from: drawCall.material.surfaceProperties)
                encoder.setFragmentBytes(&gpuMat, length: MemoryLayout<GPUMaterialProperties>.stride, index: 2)

                bindTextures(encoder: encoder, material: drawCall.material, device: device.device)

                if drawCall.material.needsLighting && !lightsData.isEmpty {
                    encoder.setFragmentBytes(
                        &lightsData,
                        length: MemoryLayout<GPULightData>.stride * lightsData.count,
                        index: 3
                    )
                    encoder.setFragmentBytes(&lightCount, length: MemoryLayout<UInt32>.stride, index: 4)
                }

                bindCustomShaderParams(encoder: encoder, material: drawCall.material)

                if let mesh = pool.mesh(for: drawCall.meshType) {
                    MeshRenderer.draw(mesh: mesh, with: encoder)
                }
            }

            encoder.endEncoding()
        }

        // Post-processing
        if usePostProcess, let ppStack = postProcessStack {
            let screenW = Float(view.drawableSize.width)
            let screenH = Float(view.drawableSize.height)

            if let ppVolSys = postProcessVolumeSystem, ppVolSys.hasActiveVolume {
                let settings = buildVolumeSettings(
                    from: ppVolSys.resolvedSettings,
                    camera: camSys,
                    viewMatrix: viewMatrix, projMatrix: projMatrix,
                    screenW: screenW, screenH: screenH
                )
                ppStack.executeVolume(
                    commandBuffer: commandBuffer,
                    drawableTexture: drawable.texture,
                    settings: settings
                )
            } else {
                let ppUniforms = PostProcessUniforms(
                    exposureMultiplier: camSys.exposureMultiplier,
                    focusDistance: camSys.focusDistance,
                    aperture: camSys.apertureValue,
                    focalLengthM: camSys.focalLengthMM * 0.001,
                    sensorHeightM: camSys.sensorHeightMM * 0.001,
                    shutterAngle: camSys.shutterAngleValue,
                    nearZ: camSys.nearZ, farZ: camSys.farZ,
                    screenWidth: screenW, screenHeight: screenH
                )
                let vpMatrix = projMatrix * viewMatrix
                let mbUniforms = MotionBlurUniforms(
                    viewProjectionMatrix: vpMatrix,
                    previousViewProjectionMatrix: camSys.previousViewProjectionMatrix,
                    inverseViewProjectionMatrix: vpMatrix.inverse,
                    shutterAngle: camSys.shutterAngleValue,
                    screenWidth: screenW, screenHeight: screenH
                )
                ppStack.execute(
                    commandBuffer: commandBuffer,
                    drawableTexture: drawable.texture,
                    ppUniforms: ppUniforms,
                    mbUniforms: mbUniforms,
                    enableDoF: true,
                    enableExposure: true,
                    enableMotionBlur: true
                )
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Material Pipeline Resolution

    private func resolveMaterialPipeline(
        for material: MCMaterial,
        device: MCMetalDevice,
        useHDR: Bool = false
    ) -> MTLRenderPipelineState? {
        let colorFormat: MTLPixelFormat = useHDR ? .rgba16Float : .bgra8Unorm_srgb
        let registry = MaterialRegistry.shared

        if registry.isBuiltin(material.id) {
            return useHDR ? registry.hdrPipelineState(for: material.id) : registry.pipelineState(for: material.id)
        }

        if let ref = material.shaderReference, ref.hasPrefix("builtin/") {
            let builtinID: UUID
            switch ref {
            case "builtin/unlit": builtinID = MaterialRegistry.unlitMaterialID
            case "builtin/toon":  builtinID = MaterialRegistry.toonMaterialID
            default:              builtinID = MaterialRegistry.litMaterialID
            }
            return useHDR ? registry.hdrPipelineState(for: builtinID) : registry.pipelineState(for: builtinID)
        }

        let cacheKey = material.pipelineCacheKey.withHDR(useHDR)

        if let unified = material.unifiedShaderSource {
            return try? materialPipelineCache?.getOrCompile(materialKey: cacheKey) {
                try shaderCompiler!.compileUnifiedPipeline(
                    source: unified,
                    renderState: material.renderState,
                    colorFormat: colorFormat,
                    depthFormat: .depth32Float,
                    vertexDescriptor: MeshPool.metalVertexDescriptor
                )
            }
        }

        guard !material.fragmentShaderSource.isEmpty else { return nil }

        let config = material.dataFlowConfig
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let vertexSource = header + (material.vertexShaderSource
            ?? ShaderSnippets.generateDefaultVertexShader(config: config))
        let fragmentSource = header + material.fragmentShaderSource

        return try? materialPipelineCache?.getOrCompile(materialKey: cacheKey) {
            try shaderCompiler!.compilePipeline(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource,
                colorFormat: colorFormat,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
        }
    }

    // MARK: - Texture Binding

    private func bindTextures(
        encoder: MTLRenderCommandEncoder,
        material: MCMaterial,
        device: MTLDevice
    ) {
        let registry = MaterialRegistry.shared
        let placeholder = registry.placeholderWhiteTexture
        let props = material.surfaceProperties

        if let path = props.albedoTexturePath,
           let tex = registry.texture(forPath: path, device: device) {
            encoder.setFragmentTexture(tex, index: 0)
        } else if let ph = placeholder {
            encoder.setFragmentTexture(ph, index: 0)
        }

        if let path = props.normalMapPath,
           let tex = registry.texture(forPath: path, device: device) {
            encoder.setFragmentTexture(tex, index: 1)
        } else if let ph = placeholder {
            encoder.setFragmentTexture(ph, index: 1)
        }

        if let path = props.metallicRoughnessMapPath,
           let tex = registry.texture(forPath: path, device: device) {
            encoder.setFragmentTexture(tex, index: 2)
        } else if let ph = placeholder {
            encoder.setFragmentTexture(ph, index: 2)
        }
    }

    // MARK: - Custom Shader Parameters

    private func bindCustomShaderParams(
        encoder: MTLRenderCommandEncoder,
        material: MCMaterial
    ) {
        let shaderSource = material.unifiedShaderSource ?? material.fragmentShaderSource
        guard !shaderSource.isEmpty else { return }
        let shaderParams = ShaderParameterParser.parse(source: shaderSource)
        guard !shaderParams.isEmpty else { return }
        var packed = ShaderParameterParser.packParameters(
            params: shaderParams, values: material.parameters
        )
        if !packed.isEmpty {
            encoder.setFragmentBytes(
                &packed,
                length: MemoryLayout<Float>.stride * packed.count,
                index: 5
            )
        }
    }

    // MARK: - Skybox Rendering

    private func drawSkybox(
        encoder: MTLRenderCommandEncoder,
        device: MCMetalDevice,
        pool: MeshPool,
        viewMatrix: simd_float4x4,
        projMatrix: simd_float4x4,
        useHDR: Bool = false
    ) {
        guard skyboxSystem.isActive else { return }

        skyboxSystem.computeUniforms(viewMatrix: viewMatrix, projectionMatrix: projMatrix)

        let hdriTexture = resolveHDRITexture(device: device)

        let registry = MaterialRegistry.shared
        let skyboxPSO: MTLRenderPipelineState
        if hdriTexture != nil {
            if useHDR, let hdrPSO = registry.hdrPipelineState(for: MaterialRegistry.skyboxMaterialID) {
                skyboxPSO = hdrPSO
            } else if let sdrPSO = registry.pipelineState(for: MaterialRegistry.skyboxMaterialID) {
                skyboxPSO = sdrPSO
            } else {
                return
            }
        } else if useHDR, let hdrFallback = hdrSkyboxFallbackPipeline {
            skyboxPSO = hdrFallback
        } else if let fallback = skyboxFallbackPipeline {
            skyboxPSO = fallback
        } else {
            return
        }

        if let dss = registry.depthStencilState(for: MaterialRegistry.skyboxMaterialID) {
            encoder.setDepthStencilState(dss)
        } else {
            let desc = MTLDepthStencilDescriptor()
            desc.depthCompareFunction = .lessEqual
            desc.isDepthWriteEnabled = false
            if let fallbackDSS = device.device.makeDepthStencilState(descriptor: desc) {
                encoder.setDepthStencilState(fallbackDSS)
            }
        }

        encoder.setRenderPipelineState(skyboxPSO)
        encoder.setCullMode(.front)

        var skyUniforms = skyboxSystem.skyboxUniforms
        encoder.setVertexBytes(&skyUniforms, length: MemoryLayout<SkyboxUniforms>.stride, index: 1)

        if let tex = hdriTexture {
            encoder.setFragmentTexture(tex, index: 0)
        }

        if let cubeMesh = pool.mesh(for: .cube) {
            MeshRenderer.draw(mesh: cubeMesh, with: encoder)
        }

        encoder.setCullMode(.back)
    }

    private func resolveHDRITexture(device: MCMetalDevice) -> MTLTexture? {
        if let customPath = skyboxSystem.hdriTexturePath, !customPath.isEmpty {
            if let cached = customSkyboxTexture, cachedSkyboxPath == customPath {
                return cached
            }
            let url = URL(fileURLWithPath: customPath)
            let tex = MaterialRegistry.shared.loadSkyboxTexture(from: url, device: device.device)
            customSkyboxTexture = tex
            cachedSkyboxPath = customPath
            return tex
        }
        return MaterialRegistry.shared.defaultSkyboxTexture
    }

    // MARK: - Volume Post-Process Settings Builder

    private func buildVolumeSettings(
        from vol: PostProcessVolumeComponent,
        camera camSys: CameraSystem,
        viewMatrix: simd_float4x4,
        projMatrix: simd_float4x4,
        screenW: Float,
        screenH: Float
    ) -> VolumePostProcessSettings {
        var settings = VolumePostProcessSettings()

        settings.enableBloom = vol.bloom.enabled
        if settings.enableBloom {
            settings.bloomUniforms = BloomUniforms(
                threshold: vol.bloom.threshold, intensity: vol.bloom.intensity,
                scatter: vol.bloom.scatter,
                tintR: vol.bloom.tint.x, tintG: vol.bloom.tint.y, tintB: vol.bloom.tint.z,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        settings.enableDoF = vol.depthOfField.enabled
        if settings.enableDoF {
            settings.ppUniforms = PostProcessUniforms(
                exposureMultiplier: camSys.exposureMultiplier,
                focusDistance: vol.depthOfField.focusDistance,
                aperture: vol.depthOfField.aperture,
                focalLengthM: vol.depthOfField.focalLength * 0.001,
                sensorHeightM: camSys.sensorHeightMM * 0.001,
                shutterAngle: camSys.shutterAngleValue,
                nearZ: camSys.nearZ, farZ: camSys.farZ,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        let vpMatrix = projMatrix * viewMatrix
        settings.enableMotionBlur = vol.motionBlur.enabled
        if settings.enableMotionBlur {
            settings.mbUniforms = MotionBlurUniforms(
                viewProjectionMatrix: vpMatrix,
                previousViewProjectionMatrix: camSys.previousViewProjectionMatrix,
                inverseViewProjectionMatrix: vpMatrix.inverse,
                shutterAngle: camSys.shutterAngleValue * vol.motionBlur.intensity,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        settings.enablePanini = vol.paniniProjection.enabled
        if settings.enablePanini {
            settings.paniniUniforms = PaniniUniforms(
                distance: vol.paniniProjection.distance,
                cropToFit: vol.paniniProjection.cropToFit,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        let needsColorGrading = vol.colorAdjustments.enabled || vol.whiteBalance.enabled
            || vol.channelMixer.enabled || vol.liftGammaGain.enabled
            || vol.splitToning.enabled || vol.shadowsMidtonesHighlights.enabled
            || vol.tonemapping.enabled
        settings.enableColorGrading = needsColorGrading
        if needsColorGrading {
            var cg = ColorGradingUniforms()
            if vol.colorAdjustments.enabled {
                cg.enableColorAdjustments = 1
                cg.postExposure = vol.colorAdjustments.postExposure
                cg.contrast = vol.colorAdjustments.contrast
                cg.colorFilterR = vol.colorAdjustments.colorFilter.x
                cg.colorFilterG = vol.colorAdjustments.colorFilter.y
                cg.colorFilterB = vol.colorAdjustments.colorFilter.z
                cg.hueShift = vol.colorAdjustments.hueShift
                cg.saturation = vol.colorAdjustments.saturation
            }
            if vol.whiteBalance.enabled {
                cg.enableWhiteBalance = 1
                cg.temperature = vol.whiteBalance.temperature
                cg.wbTint = vol.whiteBalance.tint
            }
            if vol.channelMixer.enabled {
                cg.enableChannelMixer = 1
                cg.mixerRedR = vol.channelMixer.redOutRed
                cg.mixerRedG = vol.channelMixer.redOutGreen
                cg.mixerRedB = vol.channelMixer.redOutBlue
                cg.mixerGreenR = vol.channelMixer.greenOutRed
                cg.mixerGreenG = vol.channelMixer.greenOutGreen
                cg.mixerGreenB = vol.channelMixer.greenOutBlue
                cg.mixerBlueR = vol.channelMixer.blueOutRed
                cg.mixerBlueG = vol.channelMixer.blueOutGreen
                cg.mixerBlueB = vol.channelMixer.blueOutBlue
            }
            if vol.liftGammaGain.enabled {
                cg.enableLGG = 1
                cg.lift = vol.liftGammaGain.lift
                cg.gamma = vol.liftGammaGain.gamma
                cg.gain = vol.liftGammaGain.gain
            }
            if vol.splitToning.enabled {
                cg.enableSplitToning = 1
                cg.splitShadowR = vol.splitToning.shadowsTint.x
                cg.splitShadowG = vol.splitToning.shadowsTint.y
                cg.splitShadowB = vol.splitToning.shadowsTint.z
                cg.splitHighR = vol.splitToning.highlightsTint.x
                cg.splitHighG = vol.splitToning.highlightsTint.y
                cg.splitHighB = vol.splitToning.highlightsTint.z
                cg.splitBalance = vol.splitToning.balance
            }
            if vol.shadowsMidtonesHighlights.enabled {
                cg.enableSMH = 1
                cg.smhShadows = vol.shadowsMidtonesHighlights.shadows
                cg.smhMidtones = vol.shadowsMidtonesHighlights.midtones
                cg.smhHighlights = vol.shadowsMidtonesHighlights.highlights
                cg.smhShadowsStart = vol.shadowsMidtonesHighlights.shadowsStart
                cg.smhShadowsEnd = vol.shadowsMidtonesHighlights.shadowsEnd
                cg.smhHighlightsStart = vol.shadowsMidtonesHighlights.highlightsStart
                cg.smhHighlightsEnd = vol.shadowsMidtonesHighlights.highlightsEnd
            }
            if vol.tonemapping.enabled {
                switch vol.tonemapping.mode {
                case .none: cg.tonemappingMode = 0
                case .neutral: cg.tonemappingMode = 1
                case .aces: cg.tonemappingMode = 2
                }
            }
            settings.colorGradingUniforms = cg
        }

        settings.enableChromaticAberration = vol.chromaticAberration.enabled
        if settings.enableChromaticAberration {
            settings.chromaticAberrationUniforms = ChromaticAberrationUniforms(
                intensity: vol.chromaticAberration.intensity,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        settings.enableLensDistortion = vol.lensDistortion.enabled
        if settings.enableLensDistortion {
            settings.lensDistortionUniforms = LensDistortionUniforms(
                intensity: vol.lensDistortion.intensity,
                xMultiplier: vol.lensDistortion.xMultiplier,
                yMultiplier: vol.lensDistortion.yMultiplier,
                scale: vol.lensDistortion.scale,
                centerX: vol.lensDistortion.center.x,
                centerY: vol.lensDistortion.center.y,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        settings.enableVignette = vol.vignette.enabled
        if settings.enableVignette {
            var vu = VignetteUniforms()
            vu.colorR = vol.vignette.color.x
            vu.colorG = vol.vignette.color.y
            vu.colorB = vol.vignette.color.z
            vu.intensity = vol.vignette.intensity
            vu.centerX = vol.vignette.center.x
            vu.centerY = vol.vignette.center.y
            vu.smoothness = vol.vignette.smoothness
            vu.rounded = vol.vignette.rounded ? 1 : 0
            vu.screenWidth = screenW
            vu.screenHeight = screenH
            settings.vignetteUniforms = vu
        }

        settings.enableFilmGrain = vol.filmGrain.enabled
        if settings.enableFilmGrain {
            var fg = FilmGrainUniforms()
            fg.intensity = vol.filmGrain.intensity
            fg.response = vol.filmGrain.response
            switch vol.filmGrain.type {
            case .thin: fg.grainType = 0
            case .medium: fg.grainType = 1
            case .large: fg.grainType = 2
            }
            fg.time = engine.totalTime
            fg.screenWidth = screenW
            fg.screenHeight = screenH
            settings.filmGrainUniforms = fg
        }

        settings.enableSSAO = vol.ambientOcclusion.enabled
        if settings.enableSSAO {
            var su = SSAOUniforms()
            su.intensity = vol.ambientOcclusion.intensity
            su.radius = vol.ambientOcclusion.radius
            su.sampleCount = Float(vol.ambientOcclusion.sampleCount)
            su.screenWidth = screenW; su.screenHeight = screenH
            su.nearZ = camSys.nearZ; su.farZ = camSys.farZ
            settings.ssaoUniforms = su
        }

        settings.enableFXAA = vol.antiAliasing.enabled && vol.antiAliasing.mode == .fxaa
        if settings.enableFXAA {
            settings.fxaaUniforms = FXAAUniforms(screenWidth: screenW, screenHeight: screenH)
        }

        settings.enableFullscreenBlur = vol.fullscreenBlur.enabled
        if settings.enableFullscreenBlur {
            var bu = FullscreenBlurUniforms()
            bu.intensity = vol.fullscreenBlur.intensity
            bu.radius = vol.fullscreenBlur.radius
            bu.blurMode = vol.fullscreenBlur.mode == .highQuality ? 0 : 1
            bu.screenWidth = screenW; bu.screenHeight = screenH
            settings.fullscreenBlurUniforms = bu
        }

        settings.enableFullscreenOutline = vol.fullscreenOutline.enabled
        if settings.enableFullscreenOutline {
            var ou = FullscreenOutlineUniforms()
            switch vol.fullscreenOutline.mode {
            case .normalBased: ou.outlineMode = 0
            case .colorBased: ou.outlineMode = 1
            case .depthBased: ou.outlineMode = 2
            }
            ou.thickness = vol.fullscreenOutline.thickness
            ou.threshold = vol.fullscreenOutline.threshold
            ou.colorR = vol.fullscreenOutline.color.x
            ou.colorG = vol.fullscreenOutline.color.y
            ou.colorB = vol.fullscreenOutline.color.z
            ou.screenWidth = screenW; ou.screenHeight = screenH
            ou.nearZ = camSys.nearZ; ou.farZ = camSys.farZ
            settings.fullscreenOutlineUniforms = ou
        }

        return settings
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int {
        self != 0 ? self : fallback
    }
}
#endif
