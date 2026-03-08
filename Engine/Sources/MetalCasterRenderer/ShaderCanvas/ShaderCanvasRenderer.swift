#if canImport(AppKit)
import Metal
import MetalKit
import simd

/// Engine-integrated Shader Canvas renderer. Implements the same multi-pass pipeline
/// as the standalone macOSShaderCanvas (mesh pass -> PP chain -> blit) but uses
/// engine Metal infrastructure (MCMetalDevice, ResourcePool, MeshPool).
public final class ShaderCanvasRenderer {

    // MARK: - Metal State

    private var device: MCMetalDevice?
    private var resourcePool: ResourcePool?
    private var meshPool: MeshPool?
    private var shaderCompiler: ShaderCompiler?

    // MARK: - Pipelines

    private var meshPipeline: MTLRenderPipelineState?
    private var fullscreenPipelines: [UUID: MTLRenderPipelineState] = [:]
    private var blitPipeline: MTLRenderPipelineState?

    // MARK: - Textures

    private var offscreenA: MTLTexture?
    private var offscreenB: MTLTexture?
    private var depthTexture: MTLTexture?

    /// User-bound textures for the mesh fragment shader, keyed by binding index.
    private var userTextures: [Int: MTLTexture] = [:]
    private var loadedTexturePaths: [Int: String] = [:]

    // MARK: - Tracking

    private static let meshPipelineKey = UUID()
    private var lastShaderHashes: [UUID: Int] = [:]
    private var currentWidth: Int = 0
    private var currentHeight: Int = 0
    private var startTime = CFAbsoluteTimeGetCurrent()

    public init() {}

    // MARK: - Setup

    public func setup(metalDevice: MCMetalDevice) {
        self.device = metalDevice
        self.resourcePool = ResourcePool(device: metalDevice.device)
        self.meshPool = MeshPool(device: metalDevice.device)
        self.shaderCompiler = ShaderCompiler(device: metalDevice.device)
        compileBlit()
    }

    // MARK: - Render

    /// Renders the shader canvas state into the given drawable.
    public func render(
        state: ShaderCanvasState,
        in view: MTKView,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let _ = device,
              let _ = meshPool,
              let drawable = view.currentDrawable else { return }

        let w = Int(view.drawableSize.width)
        let h = Int(view.drawableSize.height)
        ensureTextures(width: w, height: h)

        updateUserTextures(state: state)
        updateShaders(state: state)

        let time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let aspect = Float(w) / Float(max(h, 1))

        // Always clear offscreenA so the blit never reads uninitialized content
        clearOffscreen(commandBuffer: commandBuffer)

        // Pass 1: Mesh
        encodeMeshPass(
            state: state,
            commandBuffer: commandBuffer,
            time: time,
            aspect: aspect
        )

        // Pass 2..N: Fullscreen post-processing chain (ping-pong)
        var source = offscreenA
        var dest = offscreenB
        for shader in state.fullscreenShaders {
            guard let pipeline = fullscreenPipelines[shader.id],
                  let srcTex = source, let dstTex = dest else { continue }
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                pipeline: pipeline,
                sourceTexture: srcTex,
                destTexture: dstTex,
                time: time
            )
            swap(&source, &dest)
        }

        // Final blit to drawable
        encodeBlitPass(
            commandBuffer: commandBuffer,
            sourceTexture: source ?? offscreenA,
            drawableTexture: drawable.texture
        )
    }

    // MARK: - User Texture Loading

    private func updateUserTextures(state: ShaderCanvasState) {
        guard let dev = device else { return }
        for slot in state.textureSlots {
            guard let path = slot.filePath, !path.isEmpty else {
                userTextures[slot.bindingIndex] = nil
                loadedTexturePaths[slot.bindingIndex] = nil
                continue
            }
            if loadedTexturePaths[slot.bindingIndex] == path { continue }

            let url = URL(fileURLWithPath: path)
            let loader = dev.textureLoader
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue,
                .SRGB: true
            ]
            if let texture = try? loader.newTexture(URL: url, options: options) {
                userTextures[slot.bindingIndex] = texture
                loadedTexturePaths[slot.bindingIndex] = path
            }
        }
    }

    // MARK: - Shader Compilation

    private func updateShaders(state: ShaderCanvasState) {
        let (vertex, fragment) = state.activeMeshShaders

        var hasher = Hasher()
        hasher.combine(vertex?.code)
        hasher.combine(fragment?.code)
        hasher.combine(state.dataFlowConfig)
        hasher.combine(state.helperFunctions)
        hasher.combine(state.textureSlots.map(\.name))
        let meshHash = hasher.finalize()
        if lastShaderHashes[Self.meshPipelineKey] != meshHash {
            compileMeshPipeline(state: state, vertex: vertex, fragment: fragment)
            lastShaderHashes[Self.meshPipelineKey] = meshHash
        }

        for shader in state.fullscreenShaders {
            let hash = shader.code.hashValue
            if lastShaderHashes[shader.id] != hash {
                compileFullscreenPipeline(shader: shader)
                lastShaderHashes[shader.id] = hash
            }
        }
    }

    private func compileMeshPipeline(state: ShaderCanvasState, vertex: ActiveShader?, fragment: ActiveShader?) {
        guard let compiler = shaderCompiler else { return }

        let config = state.dataFlowConfig
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let helpers = state.helperFunctions

        var vertexCode = vertex?.code ?? ShaderSnippets.generateDefaultVertexShader(config: config)
        vertexCode = ShaderSnippets.injectHelperFunctions(helpers, into: vertexCode)
        let vertexSource = header + vertexCode

        var fragmentCode = fragment?.code ?? ShaderSnippets.defaultFragment

        let params = ShaderSnippets.parseParams(from: fragmentCode)
        let paramHeader = ShaderSnippets.generateParamHeader(params: params)
        if !params.isEmpty {
            fragmentCode = ShaderSnippets.injectParamsBuffer(into: fragmentCode, paramCount: params.count)
        }

        fragmentCode = ShaderSnippets.injectHelperFunctions(helpers, into: fragmentCode)
        fragmentCode = ShaderSnippets.injectTextureParams(into: fragmentCode, slots: state.textureSlots)
        let fragmentSource = header + paramHeader + fragmentCode

        do {
            meshPipeline = try compiler.compilePipeline(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
            state.compilationError = nil
        } catch {
            state.compilationError = ShaderCompiler.extractMSLErrors(from: error.localizedDescription)
        }
    }

    private func compileFullscreenPipeline(shader: ActiveShader) {
        guard let compiler = shaderCompiler else { return }
        do {
            let pipeline = try compiler.compileFullscreenPipeline(
                source: shader.code,
                colorFormat: .bgra8Unorm_srgb
            )
            fullscreenPipelines[shader.id] = pipeline
        } catch {
            // Fullscreen compilation errors are non-fatal
        }
    }

    private func compileBlit() {
        guard let compiler = shaderCompiler else { return }
        let blitSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut { float4 position [[position]]; float2 texCoord; };

        vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
            float2 positions[4] = {float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1)};
            float2 texCoords[4] = {float2(0,1), float2(1,1), float2(0,0), float2(1,0)};
            VertexOut out;
            out.position = float4(positions[vid], 0, 1);
            out.texCoord = texCoords[vid];
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """
        blitPipeline = try? compiler.compileFullscreenPipeline(source: blitSource, colorFormat: .bgra8Unorm_srgb)
    }

    // MARK: - Pass Encoding

    private func clearOffscreen(commandBuffer: MTLCommandBuffer) {
        guard let target = offscreenA else { return }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.endEncoding()
    }

    private func encodeMeshPass(
        state: ShaderCanvasState,
        commandBuffer: MTLCommandBuffer,
        time: Float,
        aspect: Float
    ) {
        guard let pipeline = meshPipeline,
              let target = offscreenA,
              let depth = depthTexture,
              let dev = device,
              let pool = meshPool else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .load
        rpd.colorAttachments[0].storeAction = .store
        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(dev.depthStencilState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)

        let projection = perspectiveProjection(fovY: Float.pi / 4, aspect: aspect, near: 0.1, far: 100)
        let view = lookAt(eye: SIMD3<Float>(0, 0, 3), center: .zero, up: SIMD3<Float>(0, 1, 0))
        let model = matrix_identity_float4x4

        var uniforms = Uniforms(
            mvpMatrix: projection * view * model,
            modelMatrix: model,
            normalMatrix: model,
            cameraPosition: SIMD4<Float>(0, 0, 3, 0),
            time: time
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Pack user parameters
        let params = ShaderSnippets.parseParams(
            from: state.activeMeshShaders.fragment?.code ?? ""
        )
        if !params.isEmpty {
            var packed = ShaderSnippets.packParamBuffer(params: params, values: state.paramValues)
            if !packed.isEmpty {
                encoder.setFragmentBytes(&packed, length: MemoryLayout<Float>.stride * packed.count, index: 2)
            }
        }

        for (index, texture) in userTextures {
            encoder.setFragmentTexture(texture, index: index)
        }

        if let mesh = pool.mesh(for: state.meshType) {
            MeshRenderer.draw(mesh: mesh, with: encoder)
        }

        encoder.endEncoding()
    }

    private func encodeFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        sourceTexture: MTLTexture,
        destTexture: MTLTexture,
        time: Float
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = destTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)

        var ppTime = time
        encoder.setFragmentBytes(&ppTime, length: MemoryLayout<Float>.stride, index: 1)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func encodeBlitPass(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture?,
        drawableTexture: MTLTexture
    ) {
        guard let blit = blitPipeline, let src = sourceTexture else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawableTexture
        rpd.colorAttachments[0].loadAction = .dontCare
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.setRenderPipelineState(blit)
        encoder.setFragmentTexture(src, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    // MARK: - Texture Management

    private func ensureTextures(width: Int, height: Int) {
        guard width != currentWidth || height != currentHeight else { return }
        currentWidth = width
        currentHeight = height

        offscreenA = resourcePool?.colorTexture(width: width, height: height, label: "canvasA")
        offscreenB = resourcePool?.colorTexture(width: width, height: height, label: "canvasB")
        depthTexture = resourcePool?.depthTexture(width: width, height: height, label: "canvasDepth")
    }

    // MARK: - Math Helpers

    private func perspectiveProjection(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let sy = 1 / tan(fovY * 0.5)
        let sx = sy / aspect
        let zRange = far - near
        return simd_float4x4(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, -(far + near) / zRange, -1),
            SIMD4<Float>(0, 0, -2 * far * near / zRange, 0)
        ))
    }

    private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }
}
#endif
