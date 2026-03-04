import Metal
import MetalKit
import simd

/// Deferred rendering path: Shadow -> GBuffer -> Lighting -> Skybox -> PostProcess -> Blit.
/// Geometry is rendered once into a G-Buffer, then lighting is computed in screen space.
public final class DeferredRenderPath: MCRenderPath {
    public let name = "Deferred"

    private var gBuffer: GBufferPass?
    private var lightingPass: DeferredLightingPass?
    private var shadowPass: ShadowPass?
    private var resourcePool: ResourcePool?
    private var postProcessStack: PostProcessStack?
    private var meshPool: MeshPool?

    private var hdrColorTexture: MTLTexture?
    private var currentWidth = 0
    private var currentHeight = 0

    public init() {}

    public func setup(device: MCMetalDevice) throws {
        resourcePool = ResourcePool(device: device.device)
        postProcessStack = PostProcessStack(device: device.device)
        meshPool = MeshPool(device: device.device)

        gBuffer = GBufferPass()
        gBuffer?.setup(device: device)

        lightingPass = DeferredLightingPass()
        lightingPass?.setup(device: device)

        shadowPass = ShadowPass()
        shadowPass?.setup(device: device)
    }

    public func resize(width: Int, height: Int) {
        guard width != currentWidth || height != currentHeight else { return }
        currentWidth = width
        currentHeight = height
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
            gBuffer?.resize(device: device.device, width: w, height: h)
            hdrColorTexture = resourcePool?.colorTexture(width: w, height: h, label: "deferredHDR")
        }

        // 1. Shadow pass
        shadowPass?.execute(frame: frame, commandBuffer: commandBuffer, device: device, meshPool: meshPool)

        // 2. G-Buffer pass
        gBuffer?.encode(frame: frame, commandBuffer: commandBuffer, device: device, meshPool: meshPool)

        // 3. Deferred lighting
        let outputTex = frame.enablePostProcess ? (postProcessStack?.hdrTextureA ?? frame.drawableTexture) : frame.drawableTexture
        if let gBuf = gBuffer {
            lightingPass?.encode(
                commandBuffer: commandBuffer,
                gBuffer: gBuf,
                outputTexture: outputTex,
                frame: frame
            )
        }

        // 4. Skybox compositing (draw on top of lit scene)
        if frame.skyboxEnabled, let skyPipeline = frame.skyboxPipeline {
            encodeSkybox(
                frame: frame,
                commandBuffer: commandBuffer,
                device: device,
                renderTarget: outputTex,
                skyboxPipeline: skyPipeline
            )
        }

        // 5. Post-processing
        if frame.enablePostProcess, let ppStack = postProcessStack {
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

    // MARK: - Skybox

    private func encodeSkybox(
        frame: FrameDescriptor,
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        renderTarget: MTLTexture,
        skyboxPipeline: MTLRenderPipelineState
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = renderTarget
        rpd.colorAttachments[0].loadAction = .load
        rpd.colorAttachments[0].storeAction = .store

        if let depth = gBuffer?.depthTexture {
            rpd.depthAttachment.texture = depth
            rpd.depthAttachment.loadAction = .load
            rpd.depthAttachment.storeAction = .dontCare
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let dssDesc = MTLDepthStencilDescriptor()
        dssDesc.depthCompareFunction = .lessEqual
        dssDesc.isDepthWriteEnabled = false
        if let dss = device.device.makeDepthStencilState(descriptor: dssDesc) {
            encoder.setDepthStencilState(dss)
        }

        encoder.setRenderPipelineState(skyboxPipeline)
        encoder.setCullMode(.front)

        if var skyU = frame.skyboxUniforms {
            encoder.setVertexBytes(&skyU, length: MemoryLayout<SkyboxUniforms>.stride, index: 1)
        }
        if let skyTex = frame.skyboxTexture {
            encoder.setFragmentTexture(skyTex, index: 0)
        }
        if let cubeMesh = meshPool?.mesh(for: .cube) {
            MeshRenderer.draw(mesh: cubeMesh, with: encoder)
        }

        encoder.endEncoding()
    }
}
