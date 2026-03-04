import Metal
import MetalKit
import simd

/// Forward rendering path: Shadow -> Skybox -> Mesh+Lighting -> PostProcess -> Blit.
/// All opaque geometry is rendered in a single pass with per-pixel lighting.
public final class ForwardRenderPath: MCRenderPath {
    public let name = "Forward"

    private var resourcePool: ResourcePool?
    private var postProcessStack: PostProcessStack?
    private var meshPool: MeshPool?

    private var sceneColorTexture: MTLTexture?
    private var sceneDepthTexture: MTLTexture?
    private var shadowMap: ShadowPass?
    private var currentWidth = 0
    private var currentHeight = 0

    public init() {}

    public func setup(device: MCMetalDevice) throws {
        resourcePool = ResourcePool(device: device.device)
        postProcessStack = PostProcessStack(device: device.device)
        meshPool = MeshPool(device: device.device)
        shadowMap = ShadowPass()
        shadowMap?.setup(device: device)
    }

    public func resize(width: Int, height: Int) {
        guard width != currentWidth || height != currentHeight else { return }
        currentWidth = width
        currentHeight = height

        sceneColorTexture = resourcePool?.colorTexture(
            width: width, height: height, label: "forwardColor"
        )
        sceneDepthTexture = resourcePool?.depthTexture(
            width: width, height: height, label: "forwardDepth"
        )
        postProcessStack?.ensureTextures(width: width, height: height)
    }

    public func execute(
        frame: FrameDescriptor,
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice
    ) {
        let w = Int(frame.drawableSize.width)
        let h = Int(frame.drawableSize.height)
        if w != currentWidth || h != currentHeight {
            resize(width: w, height: h)
        }

        let renderTarget: MTLTexture
        let useOffscreen = frame.enablePostProcess
        if useOffscreen, let hdrTex = postProcessStack?.hdrTextureA {
            renderTarget = hdrTex
        } else {
            renderTarget = frame.drawableTexture
        }

        // Shadow pass (directional light)
        shadowMap?.execute(frame: frame, commandBuffer: commandBuffer, device: device, meshPool: meshPool)

        // Main scene pass
        encodeScenePass(
            frame: frame,
            commandBuffer: commandBuffer,
            device: device,
            renderTarget: renderTarget,
            depthTexture: useOffscreen ? postProcessStack?.sceneDepthTexture : frame.depthTexture
        )

        // Post-processing
        if useOffscreen, let ppStack = postProcessStack {
            if let volSettings = frame.volumeSettings {
                ppStack.executeVolume(
                    commandBuffer: commandBuffer,
                    drawableTexture: frame.drawableTexture,
                    settings: volSettings
                )
            } else if let ppU = frame.ppUniforms, let mbU = frame.mbUniforms {
                ppStack.execute(
                    commandBuffer: commandBuffer,
                    drawableTexture: frame.drawableTexture,
                    ppUniforms: ppU,
                    mbUniforms: mbU,
                    enableDoF: true,
                    enableExposure: true,
                    enableMotionBlur: true
                )
            }
        }
    }

    // MARK: - Scene Encoding

    private func encodeScenePass(
        frame: FrameDescriptor,
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        renderTarget: MTLTexture,
        depthTexture: MTLTexture?
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = renderTarget
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = frame.clearColor

        if let depth = depthTexture {
            rpd.depthAttachment.texture = depth
            rpd.depthAttachment.loadAction = .clear
            rpd.depthAttachment.storeAction = .store
            rpd.depthAttachment.clearDepth = 1.0
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setFrontFacing(.counterClockwise)
        encoder.setDepthStencilState(device.depthStencilState)

        // Skybox
        if frame.skyboxEnabled, let skyPipeline = frame.skyboxPipeline,
           var skyU = frame.skyboxUniforms {
            let dssDesc = MTLDepthStencilDescriptor()
            dssDesc.depthCompareFunction = .lessEqual
            dssDesc.isDepthWriteEnabled = false
            if let skyDSS = device.device.makeDepthStencilState(descriptor: dssDesc) {
                encoder.setDepthStencilState(skyDSS)
            }
            encoder.setRenderPipelineState(skyPipeline)
            encoder.setCullMode(.front)
            encoder.setVertexBytes(&skyU, length: MemoryLayout<SkyboxUniforms>.stride, index: 1)
            if let skyTex = frame.skyboxTexture {
                encoder.setFragmentTexture(skyTex, index: 0)
            }
            if let cubeMesh = meshPool?.mesh(for: .cube) {
                MeshRenderer.draw(mesh: cubeMesh, with: encoder)
            }
            encoder.setCullMode(.back)
            encoder.setDepthStencilState(device.depthStencilState)
        }

        // Mesh draws
        let vp = frame.projectionMatrix * frame.viewMatrix
        let eye = frame.cameraPosition

        for entry in frame.meshDrawCalls {
            let mvp = vp * entry.worldMatrix
            var uniforms = Uniforms(
                mvpMatrix: mvp,
                modelMatrix: entry.worldMatrix,
                normalMatrix: entry.normalMatrix,
                cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 0),
                time: frame.totalTime
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            if let pso = entry.pipeline {
                encoder.setRenderPipelineState(pso)
            }

            var gpuMat = GPUMaterialProperties(from: entry.material.surfaceProperties)
            encoder.setFragmentBytes(&gpuMat, length: MemoryLayout<GPUMaterialProperties>.stride, index: 2)

            if let mesh = meshPool?.mesh(for: entry.meshType) {
                MeshRenderer.draw(mesh: mesh, with: encoder)
            }
        }

        encoder.endEncoding()
    }
}
