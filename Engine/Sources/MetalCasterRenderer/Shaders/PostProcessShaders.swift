import Foundation

/// MSL source strings for post-processing passes (Exposure, DoF, Motion Blur, Blit).
public struct PostProcessShaders {

    // MARK: - Shared Types

    public static let sharedHeader: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct PostProcessUniforms {
        float exposureMultiplier;
        float focusDistance;
        float aperture;
        float focalLengthM;
        float sensorHeightM;
        float shutterAngle;
        float nearZ;
        float farZ;
        float screenWidth;
        float screenHeight;
        float _pad0;
        float _pad1;
    };

    struct MotionBlurUniforms {
        float4x4 viewProjectionMatrix;
        float4x4 previousViewProjectionMatrix;
        float4x4 inverseViewProjectionMatrix;
        float shutterAngle;
        float screenWidth;
        float screenHeight;
        float _pad0;
    };

    struct FullscreenVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    """

    // MARK: - Fullscreen Triangle Vertex Shader

    public static let fullscreenVertex: String = """
    vertex FullscreenVertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
        FullscreenVertexOut out;
        // Fullscreen triangle: 3 vertices cover the entire screen
        float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[3] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        out.position = float4(positions[vid], 0, 1);
        out.uv = uvs[vid];
        return out;
    }

    """

    // MARK: - Exposure + ACES Tone Mapping

    public static let exposureToneMapping: String = """
    // ACES filmic tone mapping (Narkowicz 2015 approximation)
    static float3 ACESFilm(float3 x) {
        float a = 2.51f;
        float b = 0.03f;
        float c = 2.43f;
        float d = 0.59f;
        float e = 0.14f;
        return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
    }

    fragment float4 exposure_tonemapping_fragment(
        FullscreenVertexOut in [[stage_in]],
        texture2d<float> hdrTexture [[texture(0)]],
        constant PostProcessUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 hdr = hdrTexture.sample(s, in.uv);

        // Apply physical exposure
        float3 exposed = hdr.rgb * params.exposureMultiplier;

        // ACES tone mapping
        float3 tonemapped = ACESFilm(exposed);

        return float4(tonemapped, hdr.a);
    }

    """

    // MARK: - Depth of Field

    public static let depthOfField: String = """
    // Linearize depth from reverse-Z or standard depth buffer
    static float linearizeDepth(float d, float nearZ, float farZ) {
        return nearZ * farZ / (farZ - d * (farZ - nearZ));
    }

    // Circle of Confusion diameter in pixels
    static float computeCoC(float depth, float focusDistance, float aperture, float focalLengthM, float sensorHeightM, float screenHeight) {
        float focalLengthPx = focalLengthM * screenHeight / sensorHeightM;
        float coc = abs(aperture * focalLengthPx * (focusDistance - depth) / (depth * (focusDistance - focalLengthM)));
        return clamp(coc, 0.0f, 40.0f);
    }

    // Horizontal blur pass
    fragment float4 dof_blur_h_fragment(
        FullscreenVertexOut in [[stage_in]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> depthTexture [[texture(1)]],
        constant PostProcessUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);

        float depth = depthTexture.sample(s, in.uv).r;
        float linearDepth = linearizeDepth(depth, params.nearZ, params.farZ);
        float coc = computeCoC(linearDepth, params.focusDistance, params.aperture, params.focalLengthM, params.sensorHeightM, params.screenHeight);

        float radius = coc * 0.5;
        if (radius < 0.5) {
            return colorTexture.sample(s, in.uv);
        }

        int samples = clamp(int(radius), 1, 20);
        float4 color = float4(0);
        float totalWeight = 0;

        for (int i = -samples; i <= samples; i++) {
            float weight = exp(-0.5 * float(i * i) / (radius * radius * 0.25 + 0.01));
            float2 offset = float2(float(i) * texelSize.x, 0);
            color += colorTexture.sample(s, in.uv + offset) * weight;
            totalWeight += weight;
        }

        return color / max(totalWeight, 0.001);
    }

    // Vertical blur pass
    fragment float4 dof_blur_v_fragment(
        FullscreenVertexOut in [[stage_in]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> depthTexture [[texture(1)]],
        constant PostProcessUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);

        float depth = depthTexture.sample(s, in.uv).r;
        float linearDepth = linearizeDepth(depth, params.nearZ, params.farZ);
        float coc = computeCoC(linearDepth, params.focusDistance, params.aperture, params.focalLengthM, params.sensorHeightM, params.screenHeight);

        float radius = coc * 0.5;
        if (radius < 0.5) {
            return colorTexture.sample(s, in.uv);
        }

        int samples = clamp(int(radius), 1, 20);
        float4 color = float4(0);
        float totalWeight = 0;

        for (int i = -samples; i <= samples; i++) {
            float weight = exp(-0.5 * float(i * i) / (radius * radius * 0.25 + 0.01));
            float2 offset = float2(0, float(i) * texelSize.y);
            color += colorTexture.sample(s, in.uv + offset) * weight;
            totalWeight += weight;
        }

        return color / max(totalWeight, 0.001);
    }

    """

    // MARK: - Motion Blur (camera-based)

    public static let motionBlur: String = """
    fragment float4 motion_blur_fragment(
        FullscreenVertexOut in [[stage_in]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> depthTexture [[texture(1)]],
        constant MotionBlurUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float depth = depthTexture.sample(s, in.uv).r;

        // Reconstruct world position from depth
        float2 ndc = in.uv * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float4 clipPos = float4(ndc, depth, 1.0);
        float4 worldPos = params.inverseViewProjectionMatrix * clipPos;
        worldPos /= worldPos.w;

        // Project to previous frame
        float4 prevClip = params.previousViewProjectionMatrix * worldPos;
        prevClip /= prevClip.w;
        float2 prevUV = prevClip.xy * 0.5 + 0.5;
        prevUV.y = 1.0 - prevUV.y;

        // Velocity
        float2 velocity = (in.uv - prevUV) * (params.shutterAngle / 360.0);

        // Clamp velocity magnitude
        float velocityMag = length(velocity);
        float maxVelocity = 0.05;
        if (velocityMag > maxVelocity) {
            velocity = velocity / velocityMag * maxVelocity;
        }

        // Skip if near-zero motion
        if (velocityMag < 0.0001) {
            return colorTexture.sample(s, in.uv);
        }

        const int NUM_SAMPLES = 16;
        float4 color = float4(0);
        for (int i = 0; i < NUM_SAMPLES; i++) {
            float t = float(i) / float(NUM_SAMPLES - 1) - 0.5;
            float2 sampleUV = in.uv + velocity * t;
            sampleUV = clamp(sampleUV, float2(0.001), float2(0.999));
            color += colorTexture.sample(s, sampleUV);
        }

        return color / float(NUM_SAMPLES);
    }

    """

    // MARK: - Blit (simple copy)

    public static let blit: String = """
    fragment float4 blit_fragment(
        FullscreenVertexOut in [[stage_in]],
        texture2d<float> sourceTexture [[texture(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return sourceTexture.sample(s, in.uv);
    }

    """

    // MARK: - Combined Source

    /// Full MSL source for all post-processing shaders.
    public static var allSource: String {
        sharedHeader + fullscreenVertex + exposureToneMapping + depthOfField + motionBlur + blit
    }
}
