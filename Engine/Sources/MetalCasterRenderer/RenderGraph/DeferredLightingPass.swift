import Metal
import simd

/// Deferred lighting pass that reads G-Buffer textures and computes
/// PBR lighting in screen space. Outputs to an HDR color texture.
public final class DeferredLightingPass {

    private var lightingPipeline: MTLRenderPipelineState?

    public init() {}

    public func setup(device: MCMetalDevice) {
        compileLightingPipeline(device: device.device)
    }

    public func encode(
        commandBuffer: MTLCommandBuffer,
        gBuffer: GBufferPass,
        outputTexture: MTLTexture,
        frame: FrameDescriptor
    ) {
        guard let pipeline = lightingPipeline,
              let albedoTex = gBuffer.albedoMetallicTexture,
              let normalTex = gBuffer.normalRoughnessTexture,
              let positionTex = gBuffer.positionTexture else { return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = outputTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = frame.clearColor

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        encoder.label = "DeferredLighting"
        encoder.setRenderPipelineState(pipeline)

        encoder.setFragmentTexture(albedoTex, index: 0)
        encoder.setFragmentTexture(normalTex, index: 1)
        encoder.setFragmentTexture(positionTex, index: 2)

        var camPos = SIMD4<Float>(frame.cameraPosition.x, frame.cameraPosition.y, frame.cameraPosition.z, 0)
        encoder.setFragmentBytes(&camPos, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: - Internal

    private func compileLightingPipeline(device: MTLDevice) {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut deferred_light_vertex(uint vid [[vertex_id]]) {
            VertexOut out;
            float2 positions[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
            float2 texCoords[3] = {float2(0,1), float2(2,1), float2(0,-1)};
            out.position = float4(positions[vid], 0, 1);
            out.texCoord = texCoords[vid];
            return out;
        }

        float calcAttenuation(float dist, float range) {
            float denom = dist / max(range, 0.001);
            float atten = saturate(1.0 - denom * denom);
            return atten * atten / max(dist * dist, 0.0001);
        }

        float distributionGGX(float NdotH, float roughness) {
            float a = roughness * roughness;
            float a2 = a * a;
            float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
            return a2 / (M_PI_F * denom * denom + 0.0001);
        }

        float geometrySchlickGGX(float NdotV, float roughness) {
            float r = roughness + 1.0;
            float k = (r * r) / 8.0;
            return NdotV / (NdotV * (1.0 - k) + k + 0.0001);
        }

        float geometrySmith(float NdotV, float NdotL, float roughness) {
            return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
        }

        float3 fresnelSchlick(float cosTheta, float3 F0) {
            return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
        }

        struct GPULightData {
            float3 position;
            float _pad0;
            float3 direction;
            float _pad1;
            float3 color;
            float intensity;
            float range;
            float innerConeAngle;
            float outerConeAngle;
            uint type;
        };

        fragment float4 deferred_light_fragment(
            VertexOut in [[stage_in]],
            texture2d<float> albedoMetallicTex [[texture(0)]],
            texture2d<float> normalRoughnessTex [[texture(1)]],
            texture2d<float> positionTex [[texture(2)]],
            constant float4 &cameraPosition [[buffer(0)]]
        ) {
            constexpr sampler s(address::clamp_to_edge, filter::nearest);
            float4 albedoMetallic = albedoMetallicTex.sample(s, in.texCoord);
            float4 normalRoughness = normalRoughnessTex.sample(s, in.texCoord);
            float4 positionData = positionTex.sample(s, in.texCoord);

            float3 albedo = albedoMetallic.rgb;
            float metallic = albedoMetallic.a;
            float3 N = normalize(normalRoughness.rgb * 2.0 - 1.0);
            float roughness = max(0.04, normalRoughness.a);
            float3 worldPos = positionData.xyz;

            if (positionData.w < 0.5) { return float4(0, 0, 0, 1); }

            float3 V = normalize(cameraPosition.xyz - worldPos);
            float NdotV = max(0.001, dot(N, V));
            float3 F0 = mix(float3(0.04), albedo, metallic);

            // Single directional light for deferred demo
            float3 L = normalize(float3(0.5, 1.0, 0.3));
            float3 H = normalize(V + L);
            float NdotL = max(0.0, dot(N, L));
            float NdotH = max(0.0, dot(N, H));
            float HdotV = max(0.0, dot(H, V));

            float D = distributionGGX(NdotH, roughness);
            float G = geometrySmith(NdotV, NdotL, roughness);
            float3 F = fresnelSchlick(HdotV, F0);

            float3 kD = (1.0 - F) * (1.0 - metallic);
            float3 specular = (D * G * F) / (4.0 * NdotV * NdotL + 0.0001);
            float3 diffuse = kD * albedo / M_PI_F;

            float3 Lo = (diffuse + specular) * float3(1.0) * 1.5 * NdotL;
            float3 ambient = float3(0.03) * albedo;
            float3 color = ambient + Lo;

            return float4(color, 1.0);
        }
        """

        guard let lib = try? device.makeLibrary(source: source, options: nil),
              let vf = lib.makeFunction(name: "deferred_light_vertex"),
              let ff = lib.makeFunction(name: "deferred_light_fragment") else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf
        desc.fragmentFunction = ff
        desc.colorAttachments[0].pixelFormat = .rgba16Float

        lightingPipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }
}
