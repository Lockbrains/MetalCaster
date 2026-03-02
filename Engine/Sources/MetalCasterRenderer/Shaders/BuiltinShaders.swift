import Foundation

/// Built-in engine shaders that ship with Metal Caster.
/// These are non-user-modifiable and provide the default material implementations.
/// Each property is a complete MSL source string containing both vertex and fragment entry points.
enum BuiltinShaders {

    // MARK: - Shared MSL Blocks

    static let commonHeader = """
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

    """

    static let gpuLightDataStruct = """
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

    """

    // MARK: - Material Properties (shared MSL struct)

    static let materialPropertiesStruct = """
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

    """

    // MARK: - PBR Helpers (shared)

    static let pbrFunctions = """
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

    """

    // MARK: - Unlit Material

    static let unlitSource = commonHeader + materialPropertiesStruct + """
    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
        out.texCoord = in.texCoord;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant MaterialProperties &material [[buffer(2)]],
                                  texture2d<float> albedoTex [[texture(0)]]) {
        constexpr sampler texSampler(address::repeat, filter::linear);
        float3 color = material.baseColor;
        if (material.hasAlbedoTexture != 0) {
            color *= albedoTex.sample(texSampler, in.texCoord).rgb;
        }
        return float4(color + material.emissiveColor * material.emissiveIntensity, 1.0);
    }
    """

    // MARK: - Lit Material (PBR Cook-Torrance, Multi-Light)

    static let litSource = commonHeader + gpuLightDataStruct + materialPropertiesStruct + pbrFunctions + """
    struct VertexOut {
        float4 position [[position]];
        float3 normalWS;
        float3 positionWS;
        float3 viewDirWS;
        float2 texCoord;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        out.position = uniforms.mvpMatrix * float4(in.position, 1.0);

        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.positionWS = worldPos.xyz;
        out.normalWS = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
        out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);
        out.texCoord = in.texCoord;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant MaterialProperties &material [[buffer(2)]],
                                  constant GPULightData *lights [[buffer(3)]],
                                  constant uint &lightCount [[buffer(4)]],
                                  texture2d<float> albedoTex [[texture(0)]],
                                  texture2d<float> normalTex [[texture(1)]],
                                  texture2d<float> mrTex     [[texture(2)]]) {
        constexpr sampler texSampler(address::repeat, filter::linear, mip_filter::linear);

        float3 albedo = material.baseColor;
        if (material.hasAlbedoTexture != 0) {
            float4 texColor = albedoTex.sample(texSampler, in.texCoord);
            albedo *= texColor.rgb;
        }

        float metallic = material.metallic;
        float roughness = max(0.04, material.roughness);
        if (material.hasMetallicRoughnessMap != 0) {
            float4 mr = mrTex.sample(texSampler, in.texCoord);
            metallic *= mr.b;
            roughness *= mr.g;
        }

        float3 N = normalize(in.normalWS);
        float3 V = normalize(in.viewDirWS);
        float NdotV = max(0.001, dot(N, V));

        float3 F0 = mix(float3(0.04), albedo, metallic);

        float3 Lo = float3(0.0);
        for (uint i = 0; i < lightCount; i++) {
            GPULightData light = lights[i];

            float3 L;
            float atten = 1.0;

            if (light.type == 0) {
                L = normalize(-light.direction);
            } else {
                float3 toLight = light.position - in.positionWS;
                float dist = length(toLight);
                L = toLight / max(dist, 0.0001);
                atten = calcAttenuation(dist, light.range);

                if (light.type == 2) {
                    float cosTheta = dot(-L, normalize(light.direction));
                    float spotFade = saturate((cosTheta - cos(light.outerConeAngle))
                                             / max(cos(light.innerConeAngle) - cos(light.outerConeAngle), 0.0001));
                    atten *= spotFade;
                }
            }

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

            Lo += (diffuse + specular) * light.color * light.intensity * NdotL * atten;
        }

        float3 ambient = float3(0.03) * albedo;
        float3 emissive = material.emissiveColor * material.emissiveIntensity;
        float3 color = ambient + Lo + emissive;

        return float4(color, 1.0);
    }
    """

    // MARK: - Toon Material (Cel-Shading, Multi-Light)

    static let toonSource = commonHeader + gpuLightDataStruct + materialPropertiesStruct + """
    struct VertexOut {
        float4 position [[position]];
        float3 normalWS;
        float3 positionWS;
        float3 viewDirWS;
        float2 texCoord;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        out.position = uniforms.mvpMatrix * float4(in.position, 1.0);

        float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
        out.positionWS = worldPos.xyz;
        out.normalWS = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
        out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);
        out.texCoord = in.texCoord;
        return out;
    }

    float toonBand(float value) {
        if (value > 0.7)  return 1.0;
        if (value > 0.35) return 0.6;
        if (value > 0.05) return 0.35;
        return 0.15;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  constant MaterialProperties &material [[buffer(2)]],
                                  constant GPULightData *lights [[buffer(3)]],
                                  constant uint &lightCount [[buffer(4)]],
                                  texture2d<float> albedoTex [[texture(0)]]) {
        constexpr sampler texSampler(address::repeat, filter::linear);

        float3 baseColor = material.baseColor;
        if (material.hasAlbedoTexture != 0) {
            baseColor *= albedoTex.sample(texSampler, in.texCoord).rgb;
        }

        float3 N = normalize(in.normalWS);
        float3 V = normalize(in.viewDirWS);

        float totalIllumination = 0.0;
        for (uint i = 0; i < lightCount; i++) {
            GPULightData light = lights[i];
            float3 L;
            float atten = 1.0;

            if (light.type == 0) {
                L = normalize(-light.direction);
            } else {
                float3 toLight = light.position - in.positionWS;
                float dist = length(toLight);
                L = toLight / max(dist, 0.0001);
                float denom = dist / max(light.range, 0.001);
                atten = saturate(1.0 - denom * denom);
                atten *= atten;
            }

            float NdotL = max(0.0, dot(N, L));
            totalIllumination += NdotL * light.intensity * atten;
        }

        float band = toonBand(totalIllumination);
        float3 result = baseColor * band;

        float rim = 1.0 - max(0.0, dot(N, V));
        float outline = smoothstep(0.55, 0.65, rim);
        result *= (1.0 - outline * 0.7);
        result += material.emissiveColor * material.emissiveIntensity;

        return float4(result, 1.0);
    }
    """

    // MARK: - Skybox Material (Equirectangular HDRI)

    static let skyboxSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SkyboxVertexIn {
        float3 position [[attribute(0)]];
    };

    struct SkyboxUniforms {
        float4x4 viewProjectionMatrix;
    };

    struct SkyboxVertexOut {
        float4 position [[position]];
        float3 direction;
    };

    vertex SkyboxVertexOut vertex_main(SkyboxVertexIn in [[stage_in]],
                                       constant SkyboxUniforms &uniforms [[buffer(1)]]) {
        SkyboxVertexOut out;
        float4 clipPos = uniforms.viewProjectionMatrix * float4(in.position, 1.0);
        out.position = clipPos.xyww;
        out.direction = in.position;
        return out;
    }

    fragment float4 fragment_main(SkyboxVertexOut in [[stage_in]],
                                  texture2d<float> hdriTexture [[texture(0)]]) {
        constexpr sampler s(address::repeat, filter::linear, mip_filter::linear);
        float3 dir = normalize(in.direction);
        float2 uv;
        uv.x = atan2(dir.z, dir.x) / (2.0 * M_PI_F) + 0.5;
        uv.y = asin(clamp(dir.y, -1.0f, 1.0f)) / M_PI_F + 0.5;
        uv.y = 1.0 - uv.y;
        float4 color = hdriTexture.sample(s, uv);
        return float4(color.rgb, 1.0);
    }
    """

    /// Fallback skybox fragment that renders a gradient when no HDRI texture is available.
    static let skyboxFallbackSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SkyboxVertexIn {
        float3 position [[attribute(0)]];
    };

    struct SkyboxUniforms {
        float4x4 viewProjectionMatrix;
    };

    struct SkyboxVertexOut {
        float4 position [[position]];
        float3 direction;
    };

    vertex SkyboxVertexOut vertex_main(SkyboxVertexIn in [[stage_in]],
                                       constant SkyboxUniforms &uniforms [[buffer(1)]]) {
        SkyboxVertexOut out;
        float4 clipPos = uniforms.viewProjectionMatrix * float4(in.position, 1.0);
        out.position = clipPos.xyww;
        out.direction = in.position;
        return out;
    }

    fragment float4 fragment_main(SkyboxVertexOut in [[stage_in]]) {
        float3 dir = normalize(in.direction);
        float t = dir.y * 0.5 + 0.5;
        float3 bottomColor = float3(0.02, 0.02, 0.03);
        float3 topColor = float3(0.06, 0.06, 0.12);
        float3 color = mix(bottomColor, topColor, t);
        return float4(color, 1.0);
    }
    """

    // MARK: - DataFlowConfig for built-in materials

    static let unlitDataFlow = DataFlowConfig(
        normalEnabled: false,
        uvEnabled: true,
        timeEnabled: false,
        worldPositionEnabled: false,
        worldNormalEnabled: false,
        viewDirectionEnabled: false
    )

    static let litDataFlow = DataFlowConfig(
        normalEnabled: true,
        uvEnabled: true,
        timeEnabled: false,
        worldPositionEnabled: true,
        worldNormalEnabled: true,
        viewDirectionEnabled: true
    )

    static let toonDataFlow = DataFlowConfig(
        normalEnabled: true,
        uvEnabled: true,
        timeEnabled: false,
        worldPositionEnabled: true,
        worldNormalEnabled: true,
        viewDirectionEnabled: true
    )
}
