import Metal
import simd

/// G-Buffer write pass for deferred rendering.
/// Outputs position, normal, albedo, and PBR parameters to multiple render targets.
public final class GBufferPass {

    /// G-Buffer textures (MRT output)
    public private(set) var albedoMetallicTexture: MTLTexture?
    public private(set) var normalRoughnessTexture: MTLTexture?
    public private(set) var positionTexture: MTLTexture?
    public private(set) var depthTexture: MTLTexture?

    private var gBufferPipeline: MTLRenderPipelineState?
    private var currentWidth = 0
    private var currentHeight = 0

    public init() {}

    public func setup(device: MCMetalDevice) {
        compileGBufferPipeline(device: device.device)
    }

    public func resize(device: MTLDevice, width: Int, height: Int) {
        guard width != currentWidth || height != currentHeight else { return }
        currentWidth = width
        currentHeight = height

        albedoMetallicTexture = makeTexture(device: device, width: width, height: height,
                                             format: .rgba8Unorm_srgb, label: "gbuffer_albedoMetallic")
        normalRoughnessTexture = makeTexture(device: device, width: width, height: height,
                                              format: .rgba16Float, label: "gbuffer_normalRoughness")
        positionTexture = makeTexture(device: device, width: width, height: height,
                                       format: .rgba32Float, label: "gbuffer_position")

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false
        )
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDesc)
        depthTexture?.label = "gbuffer_depth"
    }

    public func encode(
        frame: FrameDescriptor,
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        meshPool: MeshPool?
    ) {
        guard let albedo = albedoMetallicTexture,
              let normal = normalRoughnessTexture,
              let position = positionTexture,
              let depth = depthTexture,
              let pipeline = gBufferPipeline else { return }

        let rpd = MTLRenderPassDescriptor()

        rpd.colorAttachments[0].texture = albedo
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        rpd.colorAttachments[1].texture = normal
        rpd.colorAttachments[1].loadAction = .clear
        rpd.colorAttachments[1].storeAction = .store
        rpd.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        rpd.colorAttachments[2].texture = position
        rpd.colorAttachments[2].loadAction = .clear
        rpd.colorAttachments[2].storeAction = .store
        rpd.colorAttachments[2].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        rpd.depthAttachment.texture = depth
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .store
        rpd.depthAttachment.clearDepth = 1.0

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.label = "GBufferPass"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setDepthStencilState(device.depthStencilState)

        let vp = frame.projectionMatrix * frame.viewMatrix

        for entry in frame.meshDrawCalls {
            let mvp = vp * entry.worldMatrix
            var uniforms = Uniforms(
                mvpMatrix: mvp,
                modelMatrix: entry.worldMatrix,
                normalMatrix: entry.normalMatrix,
                cameraPosition: SIMD4<Float>(frame.cameraPosition.x, frame.cameraPosition.y, frame.cameraPosition.z, 0),
                time: frame.totalTime
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            var gpuMat = GPUMaterialProperties(from: entry.material.surfaceProperties)
            encoder.setFragmentBytes(&gpuMat, length: MemoryLayout<GPUMaterialProperties>.stride, index: 2)

            if let mesh = meshPool?.mesh(for: entry.meshType) {
                MeshRenderer.draw(mesh: mesh, with: encoder)
            }
        }

        encoder.endEncoding()
    }

    // MARK: - Internal

    private func makeTexture(device: MTLDevice, width: Int, height: Int, format: MTLPixelFormat, label: String) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        tex?.label = label
        return tex
    }

    private func compileGBufferPipeline(device: MTLDevice) {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float3 position [[attribute(0)]];
            float3 normal   [[attribute(1)]];
            float2 texCoord [[attribute(2)]];
        };

        struct Uniforms {
            float4x4 mvpMatrix;
            float4x4 modelMatrix;
            float4x4 normalMatrix;
            float4   cameraPosition;
            float    time;
            float    _pad0;
            float    _pad1;
            float    _pad2;
        };

        struct MaterialProperties {
            float3 baseColor;
            float metallic;
            float roughness;
            float _pad0;
            float3 emissiveColor;
            float emissiveIntensity;
            uint hasAlbedoTexture;
            uint hasNormalMap;
            uint hasMetallicRoughnessMap;
            uint _pad1;
        };

        struct GBufferOut {
            float4 albedoMetallic [[color(0)]];
            float4 normalRoughness [[color(1)]];
            float4 position [[color(2)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float3 normalWS;
            float3 positionWS;
            float2 texCoord;
        };

        vertex VertexOut gbuffer_vertex(VertexIn in [[stage_in]],
                                         constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
            float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
            out.positionWS = worldPos.xyz;
            out.normalWS = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
            out.texCoord = in.texCoord;
            return out;
        }

        fragment GBufferOut gbuffer_fragment(VertexOut in [[stage_in]],
                                             constant MaterialProperties &material [[buffer(2)]]) {
            GBufferOut out;
            out.albedoMetallic = float4(material.baseColor, material.metallic);
            out.normalRoughness = float4(normalize(in.normalWS) * 0.5 + 0.5, material.roughness);
            out.position = float4(in.positionWS, 1.0);
            return out;
        }
        """

        guard let lib = try? device.makeLibrary(source: source, options: nil),
              let vf = lib.makeFunction(name: "gbuffer_vertex"),
              let ff = lib.makeFunction(name: "gbuffer_fragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf
        desc.fragmentFunction = ff
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm_srgb
        desc.colorAttachments[1].pixelFormat = .rgba16Float
        desc.colorAttachments[2].pixelFormat = .rgba32Float
        desc.depthAttachmentPixelFormat = .depth32Float
        if let vd = MeshPool.metalVertexDescriptor { desc.vertexDescriptor = vd }

        gBufferPipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }
}
