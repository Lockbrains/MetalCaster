import Foundation

/// MSL source strings for volume-based post-processing effects.
public struct PostProcessEffectShaders {

    // MARK: - Shared Header

    public static let sharedHeader: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct PPVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct BloomUniforms {
        float threshold;
        float intensity;
        float scatter;
        float tintR;
        float tintG;
        float tintB;
        float screenWidth;
        float screenHeight;
    };

    struct ColorGradingUniforms {
        float postExposure;
        float contrast;
        float colorFilterR;
        float colorFilterG;
        float colorFilterB;
        float hueShift;
        float saturation;
        float enableColorAdjustments;

        float temperature;
        float wbTint;
        float enableWhiteBalance;
        float _pad0;

        float mixerRedR;
        float mixerRedG;
        float mixerRedB;
        float enableChannelMixer;
        float mixerGreenR;
        float mixerGreenG;
        float mixerGreenB;
        float _pad1;
        float mixerBlueR;
        float mixerBlueG;
        float mixerBlueB;
        float _pad2;

        float4 lift;
        float4 gamma;
        float4 gain;
        float enableLGG;
        float _pad3;
        float _pad4;
        float _pad5;

        float splitShadowR;
        float splitShadowG;
        float splitShadowB;
        float splitBalance;
        float splitHighR;
        float splitHighG;
        float splitHighB;
        float enableSplitToning;

        float4 smhShadows;
        float4 smhMidtones;
        float4 smhHighlights;
        float smhShadowsStart;
        float smhShadowsEnd;
        float smhHighlightsStart;
        float smhHighlightsEnd;
        float enableSMH;
        float _pad6;
        float _pad7;
        float _pad8;

        float tonemappingMode;
        float _pad9;
        float _padA;
        float _padB;
    };

    struct VignetteUniforms {
        float colorR;
        float colorG;
        float colorB;
        float intensity;
        float centerX;
        float centerY;
        float smoothness;
        float rounded;
        float screenWidth;
        float screenHeight;
        float _pad0;
        float _pad1;
    };

    struct ChromaticAberrationUniforms {
        float intensity;
        float screenWidth;
        float screenHeight;
        float _pad0;
    };

    struct FilmGrainUniforms {
        float intensity;
        float response;
        float grainType;
        float time;
        float screenWidth;
        float screenHeight;
        float _pad0;
        float _pad1;
    };

    struct LensDistortionUniforms {
        float intensity;
        float xMultiplier;
        float yMultiplier;
        float scale;
        float centerX;
        float centerY;
        float screenWidth;
        float screenHeight;
    };

    struct PaniniUniforms {
        float distance;
        float cropToFit;
        float screenWidth;
        float screenHeight;
    };

    struct SSAOUniforms {
        float intensity;
        float radius;
        float sampleCount;
        float _pad0;
        float screenWidth;
        float screenHeight;
        float nearZ;
        float farZ;
    };

    struct FXAAUniforms {
        float screenWidth;
        float screenHeight;
        float _pad0;
        float _pad1;
    };

    struct FullscreenBlurUniforms {
        float intensity;
        float radius;
        float blurMode;
        float iteration;
        float screenWidth;
        float screenHeight;
        float _pad0;
        float _pad1;
    };

    struct FullscreenOutlineUniforms {
        float outlineMode;
        float thickness;
        float threshold;
        float colorR;
        float colorG;
        float colorB;
        float screenWidth;
        float screenHeight;
        float nearZ;
        float farZ;
        float _pad0;
        float _pad1;
    };

    """

    // MARK: - Fullscreen Vertex

    public static let fullscreenVertex: String = """
    vertex PPVertexOut pp_fullscreen_vertex(uint vid [[vertex_id]]) {
        PPVertexOut out;
        float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        float2 uvs[3] = { float2(0, 1), float2(2, 1), float2(0, -1) };
        out.position = float4(positions[vid], 0, 1);
        out.uv = uvs[vid];
        return out;
    }

    """

    // MARK: - Bloom

    public static let bloom: String = """
    fragment float4 bloom_downsample_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant BloomUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);

        // 13-tap downsample (dual filtering)
        float4 A = srcTexture.sample(s, in.uv);
        float4 B = srcTexture.sample(s, in.uv + float2(-1, -1) * texelSize);
        float4 C = srcTexture.sample(s, in.uv + float2( 1, -1) * texelSize);
        float4 D = srcTexture.sample(s, in.uv + float2(-1,  1) * texelSize);
        float4 E = srcTexture.sample(s, in.uv + float2( 1,  1) * texelSize);

        float4 color = A * 0.5 + (B + C + D + E) * 0.125;

        // Threshold (only on first pass, check if screenWidth corresponds to full res)
        float brightness = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        float knee = params.threshold * 0.5;
        float soft = clamp(brightness - params.threshold + knee, 0.0, 2.0 * knee);
        soft = soft * soft / (4.0 * knee + 0.00001);
        float contribution = max(soft, brightness - params.threshold) / max(brightness, 0.00001);
        color.rgb *= contribution;

        return color;
    }

    fragment float4 bloom_upsample_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant BloomUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);

        // 9-tap tent filter upsample
        float4 color = float4(0);
        color += srcTexture.sample(s, in.uv + float2(-1, -1) * texelSize) * 1.0;
        color += srcTexture.sample(s, in.uv + float2( 0, -1) * texelSize) * 2.0;
        color += srcTexture.sample(s, in.uv + float2( 1, -1) * texelSize) * 1.0;
        color += srcTexture.sample(s, in.uv + float2(-1,  0) * texelSize) * 2.0;
        color += srcTexture.sample(s, in.uv)                              * 4.0;
        color += srcTexture.sample(s, in.uv + float2( 1,  0) * texelSize) * 2.0;
        color += srcTexture.sample(s, in.uv + float2(-1,  1) * texelSize) * 1.0;
        color += srcTexture.sample(s, in.uv + float2( 0,  1) * texelSize) * 2.0;
        color += srcTexture.sample(s, in.uv + float2( 1,  1) * texelSize) * 1.0;
        color /= 16.0;

        color.rgb *= params.scatter;
        return color;
    }

    fragment float4 bloom_composite_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> sceneTexture [[texture(0)]],
        texture2d<float> bloomTexture [[texture(1)]],
        constant BloomUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 scene = sceneTexture.sample(s, in.uv);
        float4 bloom = bloomTexture.sample(s, in.uv);
        float3 tint = float3(params.tintR, params.tintG, params.tintB);
        scene.rgb += bloom.rgb * params.intensity * tint;
        return scene;
    }

    """

    // MARK: - Color Grading (combined pass)

    public static let colorGrading: String = """
    // Stephen Hill ACES fit — includes sRGB→ACEScg input and ACEScg→sRGB output matrices
    // so the RRT+ODT operates in the correct color space with proper highlight rolloff.
    static float3 RRTAndODTFit(float3 v) {
        float3 a = v * (v + 0.0245786) - 0.000090537;
        float3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
        return a / b;
    }

    static float3 ACESFilm(float3 color) {
        // sRGB → XYZ → D65_2_D60 → AP1 → RRT_SAT  (column-major for Metal)
        float3x3 ACESInputMat = float3x3(
            float3(0.59719, 0.07600, 0.02840),
            float3(0.35458, 0.90834, 0.13383),
            float3(0.04823, 0.01566, 0.83777)
        );
        // ODT_SAT → XYZ → D60_2_D65 → sRGB  (column-major for Metal)
        float3x3 ACESOutputMat = float3x3(
            float3( 1.60475, -0.10208, -0.00327),
            float3(-0.53108,  1.10813, -0.07276),
            float3(-0.07367, -0.00605,  1.07602)
        );
        color = ACESInputMat * color;
        color = RRTAndODTFit(color);
        color = ACESOutputMat * color;
        return saturate(color);
    }

    static float3 NeutralTonemap(float3 x) {
        // Hable (Uncharted 2) filmic curve
        float A = 0.15; float B = 0.50; float C = 0.10;
        float D = 0.20; float E = 0.02; float F = 0.30;
        float W = 11.2;
        float3 num = ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
        float  den = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;
        return num / den;
    }

    static float3 RGBtoHSV(float3 c) {
        float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
        float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y);
        float ee = 1.0e-10;
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + ee)), d / (q.x + ee), q.x);
    }

    static float3 HSVtoRGB(float3 c) {
        float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
        float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    static float3 whiteBalanceTransform(float3 color, float temperature, float tint) {
        // Linear sRGB -> LMS (Hunt-Pointer-Estévez, column-major for Metal)
        float3x3 LIN_2_LMS = float3x3(
            float3(3.90405e-1, 7.08416e-2, 2.31082e-2),
            float3(5.49941e-1, 9.63172e-1, 1.28021e-1),
            float3(8.92632e-3, 1.35775e-3, 9.36245e-1)
        );
        float3x3 LMS_2_LIN = float3x3(
            float3( 2.85847e+0, -2.10182e-1, -4.18120e-2),
            float3(-1.62879e+0,  1.15820e+0, -1.18169e-1),
            float3(-2.48910e-2,  3.24281e-4,  1.06867e+0)
        );

        // D65 reference white in this LMS space (LIN_2_LMS * (1,1,1))
        float3 d65LMS = float3(0.949237, 1.03542, 1.08728);

        // Compute target illuminant chromaticity from temperature/tint
        float t1 = temperature / 65.0;
        float t2 = tint / 65.0;
        float x = 0.31271 - t1 * (t1 < 0.0 ? 0.1 : 0.05);
        float y = 2.87 * x - 3.0 * x * x - 0.27509507 + t2 * 0.05;

        // Target illuminant in XYZ
        float X = x / y;
        float Z = (1.0 - x - y) / y;

        // Target illuminant in LMS (CAT02-like adaptation)
        float3 targetLMS = float3(
            0.7328 * X + 0.4296 - 0.1624 * Z,
           -0.7036 * X + 1.6975 + 0.0061 * Z,
            0.0030 * X + 0.0136 + 0.9834 * Z
        );

        float3 balance = d65LMS / targetLMS;

        float3 lms = LIN_2_LMS * color;
        lms *= balance;
        return LMS_2_LIN * lms;
    }

    fragment float4 color_grading_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant ColorGradingUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float3 color = srcTexture.sample(s, in.uv).rgb;

        // White Balance
        if (params.enableWhiteBalance > 0.5) {
            color = whiteBalanceTransform(color, params.temperature, params.wbTint);
        }

        // Color Adjustments
        if (params.enableColorAdjustments > 0.5) {
            color *= pow(2.0, params.postExposure);
            float contrastFactor = (params.contrast + 100.0) / 100.0;
            color = ((color - 0.5) * contrastFactor + 0.5);
            color *= float3(params.colorFilterR, params.colorFilterG, params.colorFilterB);
            float3 hsv = RGBtoHSV(max(color, float3(0)));
            hsv.x = fract(hsv.x + params.hueShift / 360.0);
            hsv.y = clamp(hsv.y * (1.0 + params.saturation / 100.0), 0.0, 1.0);
            color = HSVtoRGB(hsv);
        }

        // Channel Mixer
        if (params.enableChannelMixer > 0.5) {
            float3 mixed;
            mixed.r = dot(color, float3(params.mixerRedR, params.mixerRedG, params.mixerRedB) / 100.0);
            mixed.g = dot(color, float3(params.mixerGreenR, params.mixerGreenG, params.mixerGreenB) / 100.0);
            mixed.b = dot(color, float3(params.mixerBlueR, params.mixerBlueG, params.mixerBlueB) / 100.0);
            color = mixed;
        }

        // Lift Gamma Gain (ASC CDL-style: gain * color + lift offset, raised to 1/gamma)
        // Identity: lift=(1,1,1,0), gamma=(1,1,1,0), gain=(1,1,1,0)
        if (params.enableLGG > 0.5) {
            float3 liftOff = params.lift.rgb + params.lift.w - 1.0;
            float3 gammaVal = max(params.gamma.rgb + params.gamma.w, float3(0.001));
            float3 gainMul = params.gain.rgb + params.gain.w;
            color = pow(max(gainMul * color + liftOff, float3(0.0)), 1.0 / gammaVal);
        }

        // Split Toning
        if (params.enableSplitToning > 0.5) {
            float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
            float balance = (params.splitBalance + 100.0) / 200.0;
            float3 shadowTint = float3(params.splitShadowR, params.splitShadowG, params.splitShadowB);
            float3 highTint = float3(params.splitHighR, params.splitHighG, params.splitHighB);
            float shadowW = saturate(1.0 - luminance / balance);
            float highW = saturate((luminance - balance) / (1.0 - balance));
            color = mix(color, color * shadowTint * 2.0, shadowW * 0.5);
            color = mix(color, color * highTint * 2.0, highW * 0.5);
        }

        // Shadows Midtones Highlights
        if (params.enableSMH > 0.5) {
            float lum = dot(color, float3(0.2126, 0.7152, 0.0722));
            float shadowW = 1.0 - smoothstep(params.smhShadowsStart, params.smhShadowsEnd, lum);
            float highW = smoothstep(params.smhHighlightsStart, params.smhHighlightsEnd, lum);
            float midW = 1.0 - shadowW - highW;
            color *= params.smhShadows.rgb * shadowW + params.smhMidtones.rgb * midW + params.smhHighlights.rgb * highW;
        }

        // Tonemapping
        if (params.tonemappingMode > 0.5) {
            if (params.tonemappingMode > 1.5) {
                color = ACESFilm(color);
            } else {
                color = NeutralTonemap(color);
            }
        }

        return float4(max(color, float3(0)), 1.0);
    }

    """

    // MARK: - Vignette

    public static let vignette: String = """
    fragment float4 vignette_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant VignetteUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 color = srcTexture.sample(s, in.uv);

        float2 center = float2(params.centerX, params.centerY);
        float2 dist = in.uv - center;

        if (params.rounded > 0.5) {
            float aspect = params.screenWidth / params.screenHeight;
            dist.x *= aspect;
        }

        float factor = dot(dist, dist);
        float vignette = 1.0 - smoothstep(params.intensity - params.smoothness, params.intensity, factor);

        float3 vignetteColor = float3(params.colorR, params.colorG, params.colorB);
        color.rgb = mix(vignetteColor, color.rgb, vignette);
        return color;
    }

    """

    // MARK: - Chromatic Aberration

    public static let chromaticAberration: String = """
    fragment float4 chromatic_aberration_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant ChromaticAberrationUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float2 center = float2(0.5, 0.5);
        float2 dir = in.uv - center;
        float2 offset = dir * params.intensity * 0.02;

        float r = srcTexture.sample(s, in.uv - offset).r;
        float g = srcTexture.sample(s, in.uv).g;
        float b = srcTexture.sample(s, in.uv + offset).b;

        return float4(r, g, b, 1.0);
    }

    """

    // MARK: - Film Grain

    public static let filmGrain: String = """
    static float ppHash12(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    fragment float4 film_grain_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant FilmGrainUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 color = srcTexture.sample(s, in.uv);

        float2 pixelCoord = in.uv * float2(params.screenWidth, params.screenHeight);
        float grainScale = 1.0 + params.grainType;
        float2 grainUV = pixelCoord / grainScale + float2(params.time * 17.0, params.time * 13.0);

        float grain = ppHash12(grainUV) * 2.0 - 1.0;
        float luminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        float response = mix(1.0, luminance, params.response);
        color.rgb += grain * params.intensity * response * 0.15;

        return color;
    }

    """

    // MARK: - Lens Distortion

    public static let lensDistortion: String = """
    fragment float4 lens_distortion_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant LensDistortionUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float2 center = float2(params.centerX, params.centerY);
        float2 uv = (in.uv - center) / params.scale;
        uv.x *= params.xMultiplier;
        uv.y *= params.yMultiplier;

        float r2 = dot(uv, uv);
        float distortion = 1.0 + r2 * params.intensity;
        uv *= distortion;

        uv.x /= params.xMultiplier;
        uv.y /= params.yMultiplier;
        uv = uv * params.scale + center;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0, 0, 0, 1);
        }

        return srcTexture.sample(s, uv);
    }

    """

    // MARK: - Panini Projection

    public static let panini: String = """
    fragment float4 panini_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant PaniniUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float2 uv = in.uv * 2.0 - 1.0;
        float d = params.distance;

        float S = (d + 1.0) / (d + cos(uv.x * 1.5707963));
        float2 paniniUV;
        paniniUV.x = S * sin(uv.x * 1.5707963);
        paniniUV.y = S * uv.y;

        paniniUV = mix(uv, paniniUV, d);
        paniniUV *= params.cropToFit;
        paniniUV = paniniUV * 0.5 + 0.5;

        if (paniniUV.x < 0.0 || paniniUV.x > 1.0 || paniniUV.y < 0.0 || paniniUV.y > 1.0) {
            return float4(0, 0, 0, 1);
        }

        return srcTexture.sample(s, paniniUV);
    }

    """

    // MARK: - SSAO

    public static let ssao: String = """
    static float linearizeDepthSSAO(float d, float nearZ, float farZ) {
        return nearZ * farZ / (farZ - d * (farZ - nearZ));
    }

    static float2 ssaoHash(float2 p) {
        float3 a = fract(p.xyx * float3(0.1031, 0.1030, 0.0973));
        a += dot(a, a.yzx + 33.33);
        return fract((a.xx + a.yz) * a.zy);
    }

    fragment float4 ssao_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> depthTexture [[texture(1)]],
        constant SSAOUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 color = colorTexture.sample(s, in.uv);
        float depth = depthTexture.sample(s, in.uv).r;

        float linearDepth = linearizeDepthSSAO(depth, params.nearZ, params.farZ);

        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);
        int samples = int(params.sampleCount);
        float occlusion = 0.0;

        for (int i = 0; i < samples; i++) {
            float2 rnd = ssaoHash(in.uv * 1000.0 + float2(float(i) * 7.0, float(i) * 13.0));
            float2 offset = (rnd * 2.0 - 1.0) * params.radius * texelSize * 20.0;
            float sampleDepth = depthTexture.sample(s, in.uv + offset).r;
            float sampleLinear = linearizeDepthSSAO(sampleDepth, params.nearZ, params.farZ);

            float rangeCheck = smoothstep(0.0, 1.0, params.radius / abs(linearDepth - sampleLinear + 0.001));
            occlusion += step(sampleLinear + 0.01, linearDepth) * rangeCheck;
        }

        occlusion = 1.0 - (occlusion / float(samples)) * params.intensity;
        color.rgb *= saturate(occlusion);

        return color;
    }

    """

    // MARK: - FXAA

    public static let fxaa: String = """
    fragment float4 fxaa_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant FXAAUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);

        float3 rgbNW = srcTexture.sample(s, in.uv + float2(-1, -1) * texelSize).rgb;
        float3 rgbNE = srcTexture.sample(s, in.uv + float2( 1, -1) * texelSize).rgb;
        float3 rgbSW = srcTexture.sample(s, in.uv + float2(-1,  1) * texelSize).rgb;
        float3 rgbSE = srcTexture.sample(s, in.uv + float2( 1,  1) * texelSize).rgb;
        float3 rgbM  = srcTexture.sample(s, in.uv).rgb;

        float3 luma = float3(0.299, 0.587, 0.114);
        float lumaNW = dot(rgbNW, luma);
        float lumaNE = dot(rgbNE, luma);
        float lumaSW = dot(rgbSW, luma);
        float lumaSE = dot(rgbSE, luma);
        float lumaM  = dot(rgbM, luma);

        float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
        float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

        float lumaRange = lumaMax - lumaMin;
        if (lumaRange < max(0.0312, lumaMax * 0.125)) {
            return float4(rgbM, 1.0);
        }

        float2 dir;
        dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
        dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

        float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.03125, 1.0/128.0);
        float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
        dir = clamp(dir * rcpDirMin, float2(-8.0), float2(8.0)) * texelSize;

        float3 rgbA = 0.5 * (
            srcTexture.sample(s, in.uv + dir * (1.0/3.0 - 0.5)).rgb +
            srcTexture.sample(s, in.uv + dir * (2.0/3.0 - 0.5)).rgb
        );
        float3 rgbB = rgbA * 0.5 + 0.25 * (
            srcTexture.sample(s, in.uv + dir * -0.5).rgb +
            srcTexture.sample(s, in.uv + dir *  0.5).rgb
        );

        float lumaB = dot(rgbB, luma);
        if (lumaB < lumaMin || lumaB > lumaMax) {
            return float4(rgbA, 1.0);
        }
        return float4(rgbB, 1.0);
    }

    """

    // MARK: - Fullscreen Blur

    public static let fullscreenBlur: String = """
    fragment float4 fullscreen_blur_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> srcTexture [[texture(0)]],
        constant FullscreenBlurUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);

        if (params.blurMode < 0.5) {
            // High Quality: Gaussian blur (separable, two-pass via iteration)
            float radius = params.radius;
            int samples = clamp(int(radius * 2.0), 1, 32);
            float sigma = radius * 0.5 + 0.001;

            float4 color = float4(0);
            float totalWeight = 0;
            bool horizontal = params.iteration < 0.5;

            for (int i = -samples; i <= samples; i++) {
                float weight = exp(-0.5 * float(i * i) / (sigma * sigma));
                float2 offset = horizontal
                    ? float2(float(i) * texelSize.x, 0)
                    : float2(0, float(i) * texelSize.y);
                color += srcTexture.sample(s, in.uv + offset) * weight;
                totalWeight += weight;
            }
            return (color / max(totalWeight, 0.001)) * params.intensity
                 + srcTexture.sample(s, in.uv) * (1.0 - params.intensity);

        } else {
            // High Performance: Kawase blur
            float offset = params.iteration + 0.5;
            float4 color = float4(0);
            color += srcTexture.sample(s, in.uv + float2(-offset, -offset) * texelSize);
            color += srcTexture.sample(s, in.uv + float2( offset, -offset) * texelSize);
            color += srcTexture.sample(s, in.uv + float2(-offset,  offset) * texelSize);
            color += srcTexture.sample(s, in.uv + float2( offset,  offset) * texelSize);
            color *= 0.25;
            return color * params.intensity + srcTexture.sample(s, in.uv) * (1.0 - params.intensity);
        }
    }

    """

    // MARK: - Fullscreen Outline

    public static let fullscreenOutline: String = """
    static float linearizeDepthOutline(float d, float nearZ, float farZ) {
        return nearZ * farZ / (farZ - d * (farZ - nearZ));
    }

    fragment float4 fullscreen_outline_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> depthTexture [[texture(1)]],
        constant FullscreenOutlineUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float2 texelSize = float2(1.0 / params.screenWidth, 1.0 / params.screenHeight);
        float4 center = colorTexture.sample(s, in.uv);
        float thickness = params.thickness;

        float edge = 0.0;

        if (params.outlineMode < 0.5) {
            // Normal-based edge detection (using color luminance as proxy without G-buffer)
            float3 luma = float3(0.2126, 0.7152, 0.0722);
            float cL = dot(center.rgb, luma);
            float uL = dot(colorTexture.sample(s, in.uv + float2(0, -thickness) * texelSize).rgb, luma);
            float dL = dot(colorTexture.sample(s, in.uv + float2(0,  thickness) * texelSize).rgb, luma);
            float lL = dot(colorTexture.sample(s, in.uv + float2(-thickness, 0) * texelSize).rgb, luma);
            float rL = dot(colorTexture.sample(s, in.uv + float2( thickness, 0) * texelSize).rgb, luma);
            edge = abs(uL - dL) + abs(lL - rL);

        } else if (params.outlineMode < 1.5) {
            // Color-based edge detection (Sobel on RGB)
            float3 u = colorTexture.sample(s, in.uv + float2(0, -thickness) * texelSize).rgb;
            float3 d = colorTexture.sample(s, in.uv + float2(0,  thickness) * texelSize).rgb;
            float3 l = colorTexture.sample(s, in.uv + float2(-thickness, 0) * texelSize).rgb;
            float3 r = colorTexture.sample(s, in.uv + float2( thickness, 0) * texelSize).rgb;
            float3 diff = abs(u - d) + abs(l - r);
            edge = (diff.r + diff.g + diff.b) / 3.0;

        } else {
            // Depth-based edge detection
            float cD = linearizeDepthOutline(depthTexture.sample(s, in.uv).r, params.nearZ, params.farZ);
            float uD = linearizeDepthOutline(depthTexture.sample(s, in.uv + float2(0, -thickness) * texelSize).r, params.nearZ, params.farZ);
            float dD = linearizeDepthOutline(depthTexture.sample(s, in.uv + float2(0,  thickness) * texelSize).r, params.nearZ, params.farZ);
            float lD = linearizeDepthOutline(depthTexture.sample(s, in.uv + float2(-thickness, 0) * texelSize).r, params.nearZ, params.farZ);
            float rD = linearizeDepthOutline(depthTexture.sample(s, in.uv + float2( thickness, 0) * texelSize).r, params.nearZ, params.farZ);
            edge = abs(uD - cD) + abs(dD - cD) + abs(lD - cD) + abs(rD - cD);
            edge = edge / cD;
        }

        float edgeMask = step(params.threshold, edge);
        float3 outlineColor = float3(params.colorR, params.colorG, params.colorB);
        center.rgb = mix(center.rgb, outlineColor, edgeMask);

        return center;
    }

    """

    // MARK: - Height Fog

    public static let heightFog: String = """

    struct HeightFogUniforms {
        float fogColorR;
        float fogColorG;
        float fogColorB;
        float density;
        float baseHeight;
        float heightFalloff;
        float maxOpacity;
        float startDistance;
        float inscatterColorR;
        float inscatterColorG;
        float inscatterColorB;
        float inscatterIntensity;
        float inscatterExponent;
        float mode;   // 0=exp, 1=exp²
        float nearZ;
        float farZ;
        float cameraPositionX;
        float cameraPositionY;
        float cameraPositionZ;
        float screenWidth;
        float screenHeight;
        float _pad0;
        float _pad1;
        float _pad2;
        float4x4 inverseViewProjection;
    };

    float3 reconstructWorldPos(float2 uv, float depth, float4x4 invVP) {
        float2 ndc = uv * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float4 clipPos = float4(ndc, depth, 1.0);
        float4 worldPos = invVP * clipPos;
        return worldPos.xyz / worldPos.w;
    }

    fragment float4 height_fog_fragment(
        PPVertexOut in [[stage_in]],
        texture2d<float> colorTexture [[texture(0)]],
        texture2d<float> depthTexture [[texture(1)]],
        constant HeightFogUniforms &params [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 color = colorTexture.sample(s, in.uv);
        float depth = depthTexture.sample(s, in.uv).r;

        // Skip sky pixels (depth at far plane)
        if (depth >= 1.0) return color;

        float3 worldPos = reconstructWorldPos(in.uv, depth, params.inverseViewProjection);
        float3 cameraPos = float3(params.cameraPositionX, params.cameraPositionY, params.cameraPositionZ);

        float dist = length(worldPos - cameraPos);
        float effectiveDist = max(dist - params.startDistance, 0.0);

        float heightDiff = worldPos.y - params.baseHeight;
        float heightFactor = exp(-max(heightDiff, 0.0) * params.heightFalloff);

        float fogAmount;
        if (params.mode < 0.5) {
            fogAmount = 1.0 - exp(-params.density * effectiveDist * heightFactor);
        } else {
            float d = params.density * effectiveDist * heightFactor;
            fogAmount = 1.0 - exp(-d * d);
        }
        fogAmount = min(fogAmount, params.maxOpacity);

        float3 fogColor = float3(params.fogColorR, params.fogColorG, params.fogColorB);

        // Inscattering (sun glow effect toward light direction)
        if (params.inscatterIntensity > 0.001) {
            float3 viewDir = normalize(worldPos - cameraPos);
            // Approximate: inscatter toward the brightest direction (up-hemisphere sun)
            float3 lightDir = normalize(float3(0.4, -0.9, -0.5));
            float sunDot = max(dot(viewDir, -lightDir), 0.0);
            float inscatter = pow(sunDot, params.inscatterExponent) * params.inscatterIntensity;
            float3 inscatterColor = float3(params.inscatterColorR, params.inscatterColorG, params.inscatterColorB);
            fogColor = mix(fogColor, inscatterColor, saturate(inscatter));
        }

        color.rgb = mix(color.rgb, fogColor, fogAmount);
        return color;
    }

    """

    // MARK: - Combined Source

    public static var allSource: String {
        sharedHeader + fullscreenVertex + bloom + colorGrading + vignette +
        chromaticAberration + filmGrain + lensDistortion + panini + ssao +
        fxaa + fullscreenBlur + fullscreenOutline + heightFog
    }
}
