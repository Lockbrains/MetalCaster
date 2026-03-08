import Foundation

/// Central repository for all Metal Shading Language source code strings
/// and Data Flow header generation logic.
///
/// Extracted from the original macOSShaderCanvas for reuse across
/// both the Shader Canvas tool and the Metal Caster editor.
public struct ShaderSnippets {

    // MARK: - Data Flow Header Generation

    public static func generateSharedHeader(config: DataFlowConfig) -> String {
        var header = """
        #include <metal_stdlib>
        using namespace metal;
        
        #define normal normalOS
        #define texCoord uv
        #define modelViewProjectionMatrix mvpMatrix
        
        struct VertexIn {
            float3 positionOS [[attribute(0)]];
        """
        if config.normalEnabled    { header += "\n    float3 normalOS [[attribute(1)]];" }
        if config.uvEnabled        { header += "\n    float2 uv [[attribute(2)]];" }
        if config.tangentEnabled   { header += "\n    float3 tangentOS [[attribute(3)]];" }
        if config.bitangentEnabled { header += "\n    float3 bitangentOS [[attribute(4)]];" }
        header += "\n};\n\nstruct VertexOut {\n    float4 position [[position]];"
        if config.normalEnabled         { header += "\n    float3 normalOS;" }
        if config.uvEnabled             { header += "\n    float2 uv;" }
        if config.timeEnabled           { header += "\n    float time;" }
        if config.worldPositionEnabled  { header += "\n    float3 positionWS;" }
        if config.worldNormalEnabled    { header += "\n    float3 normalWS;" }
        if config.viewDirectionEnabled  { header += "\n    float3 viewDirWS;" }
        if config.tangentEnabled        { header += "\n    float3 tangentOS;" }
        if config.bitangentEnabled      { header += "\n    float3 bitangentOS;" }
        header += """
        
        };

        struct Uniforms {
            float4x4 mvpMatrix;
            float4x4 modelMatrix;
            float4x4 normalMatrix;
            float4   cameraPosition;
            float    time;
            float    studioLightOn;
            float    _pad1;
            float    _pad2;
        };

        """
        return header
    }

    public static func generateDefaultVertexShader(config: DataFlowConfig) -> String {
        var fn = """
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.mvpMatrix * float4(in.positionOS, 1.0);
        """
        if config.normalEnabled    { fn += "\n    out.normalOS = in.normalOS;" }
        if config.uvEnabled        { fn += "\n    out.uv = in.uv;" }
        if config.timeEnabled      { fn += "\n    out.time = uniforms.time;" }
        if config.tangentEnabled   { fn += "\n    out.tangentOS = in.tangentOS;" }
        if config.bitangentEnabled { fn += "\n    out.bitangentOS = in.bitangentOS;" }
        if config.worldPositionEnabled || config.viewDirectionEnabled {
            fn += "\n    float4 worldPos = uniforms.modelMatrix * float4(in.positionOS, 1.0);"
            fn += "\n    out.positionWS = worldPos.xyz;"
        }
        if config.worldNormalEnabled {
            fn += "\n    out.normalWS = normalize((uniforms.normalMatrix * float4(in.normalOS, 0.0)).xyz);"
        }
        if config.viewDirectionEnabled {
            fn += "\n    out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);"
        }
        fn += "\n    return out;\n}\n"
        return fn
    }

    public static func generateVertexDemo(config: DataFlowConfig) -> String {
        var fn = """
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            float3 pos = in.positionOS;
            
            float displacement = sin(pos.x * 5.0 + uniforms.time * 3.0) * 0.15 +
                                 cos(pos.z * 5.0 + uniforms.time * 3.0) * 0.15;
            pos.y += displacement;
            
            out.position = uniforms.mvpMatrix * float4(pos, 1.0);
        """
        if config.normalEnabled {
            fn += """
            
                float3 newNormal = in.normalOS;
                newNormal.x -= cos(pos.x * 5.0 + uniforms.time * 3.0) * 0.15 * 5.0;
                newNormal.z -= -sin(pos.z * 5.0 + uniforms.time * 3.0) * 0.15 * 5.0;
                out.normalOS = normalize(newNormal);
            """
        }
        if config.uvEnabled        { fn += "\n    out.uv = in.uv;" }
        if config.timeEnabled      { fn += "\n    out.time = uniforms.time;" }
        if config.tangentEnabled   { fn += "\n    out.tangentOS = in.tangentOS;" }
        if config.bitangentEnabled { fn += "\n    out.bitangentOS = in.bitangentOS;" }
        if config.worldPositionEnabled || config.viewDirectionEnabled {
            fn += "\n    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);"
            fn += "\n    out.positionWS = worldPos.xyz;"
        }
        if config.worldNormalEnabled {
            fn += "\n    out.normalWS = normalize((uniforms.normalMatrix * float4(out.normalOS, 0.0)).xyz);"
        }
        if config.viewDirectionEnabled {
            fn += "\n    out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);"
        }
        fn += "\n    return out;\n}\n"
        return fn
    }

    public static func generateVertexTemplate(config: DataFlowConfig) -> String {
        var fn = """
        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            float3 pos = in.positionOS;

            out.position = uniforms.mvpMatrix * float4(pos, 1.0);
        """
        if config.normalEnabled    { fn += "\n    out.normalOS = in.normalOS;" }
        if config.uvEnabled        { fn += "\n    out.uv = in.uv;" }
        if config.timeEnabled      { fn += "\n    out.time = uniforms.time;" }
        if config.tangentEnabled   { fn += "\n    out.tangentOS = in.tangentOS;" }
        if config.bitangentEnabled { fn += "\n    out.bitangentOS = in.bitangentOS;" }
        if config.worldPositionEnabled || config.viewDirectionEnabled {
            fn += "\n    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);"
            fn += "\n    out.positionWS = worldPos.xyz;"
        }
        if config.worldNormalEnabled {
            fn += "\n    out.normalWS = normalize((uniforms.normalMatrix * float4(in.normalOS, 0.0)).xyz);"
        }
        if config.viewDirectionEnabled {
            fn += "\n    out.viewDirWS = normalize(uniforms.cameraPosition.xyz - worldPos.xyz);"
        }
        fn += "\n    return out;\n}\n"
        return fn
    }

    public static func generateStructPreview(config: DataFlowConfig) -> String {
        var preview = "struct VertexIn {\n    float3 positionOS [[attribute(0)]];"
        if config.normalEnabled    { preview += "\n    float3 normalOS [[attribute(1)]];" }
        if config.uvEnabled        { preview += "\n    float2 uv [[attribute(2)]];" }
        if config.tangentEnabled   { preview += "\n    float3 tangentOS [[attribute(3)]];" }
        if config.bitangentEnabled { preview += "\n    float3 bitangentOS [[attribute(4)]];" }
        preview += "\n};\n\nstruct VertexOut {\n    float4 position [[position]];"
        if config.normalEnabled         { preview += "\n    float3 normalOS;" }
        if config.uvEnabled             { preview += "\n    float2 uv;" }
        if config.timeEnabled           { preview += "\n    float time;" }
        if config.worldPositionEnabled  { preview += "\n    float3 positionWS;" }
        if config.worldNormalEnabled    { preview += "\n    float3 normalWS;" }
        if config.viewDirectionEnabled  { preview += "\n    float3 viewDirWS;" }
        if config.tangentEnabled        { preview += "\n    float3 tangentOS;" }
        if config.bitangentEnabled      { preview += "\n    float3 bitangentOS;" }
        preview += "\n};\n\nstruct Uniforms {\n    float4x4 mvpMatrix;"
        preview += "\n    float4x4 modelMatrix;"
        preview += "\n    float4x4 normalMatrix;"
        preview += "\n    float4   cameraPosition;"
        preview += "\n    float    time;\n};"
        return preview
    }

    // MARK: - Texture Declarations

    /// Generates MSL fragment function parameter declarations for bound texture slots.
    /// These are injected into the fragment_main signature when texture slots are active.
    public static func textureDeclarations(for slots: [TextureSlot]) -> String {
        guard !slots.isEmpty else { return "" }
        return slots.map { slot in
            "texture2d<float> \(slot.name) [[texture(\(slot.bindingIndex))]]"
        }.joined(separator: ",\n                             ")
    }

    /// Injects texture parameters into fragment_main signatures.
    public static func injectTextureParams(into code: String, slots: [TextureSlot]) -> String {
        guard !slots.isEmpty else { return code }
        var result = code
        let injection = slots.map { slot in
            ",\n                             texture2d<float> \(slot.name) [[texture(\(slot.bindingIndex))]]"
        }.joined()
        let pattern = #"(fragment_main\s*\([\s\S]*?)\)\s*\{"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                let innerRange = match.range(at: 1)
                let inner = nsResult.substring(with: innerRange)
                if slots.allSatisfy({ inner.contains($0.name) }) { continue }
                let replacement = inner + injection + ") {"
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        return result
    }

    // MARK: - Helper Function Injection

    /// Injects user-defined helper functions between the header and main shader code.
    public static func injectHelperFunctions(_ helpers: String, into code: String) -> String {
        guard !helpers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return code }
        return "\n// === Helper Functions ===\n" + helpers + "\n// === End Helpers ===\n\n" + code
    }

    // MARK: - Parameter System

    public static func parseParams(from code: String) -> [ShaderParam] {
        var params: [ShaderParam] = []
        let pattern = #"//\s*@param\s+(\w+)\s+(float[234]?|color)\s+(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return params }

        let nsCode = code as NSString
        let matches = regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))

        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let name = nsCode.substring(with: match.range(at: 1))
            let typeStr = nsCode.substring(with: match.range(at: 2))
            let valuesStr = nsCode.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)

            guard let type = ParamType(rawValue: typeStr == "color" ? "color" : typeStr) else { continue }

            let numbers = valuesStr.split(separator: " ").compactMap { Float($0) }
            guard !numbers.isEmpty else { continue }

            var defaultValue: [Float]
            var minValue: Float? = nil
            var maxValue: Float? = nil

            if type == .float && numbers.count >= 3 {
                defaultValue = [numbers[0]]
                minValue = numbers[1]
                maxValue = numbers[2]
            } else {
                defaultValue = Array(numbers.prefix(type.componentCount))
                while defaultValue.count < type.componentCount {
                    defaultValue.append(0)
                }
            }

            params.append(ShaderParam(name: name, type: type, defaultValue: defaultValue, minValue: minValue, maxValue: maxValue))
        }
        return params
    }

    public static func generateParamHeader(params: [ShaderParam]) -> String {
        guard !params.isEmpty else { return "" }
        var header = "\n// === User Parameters (buffer index 2) ===\n"
        var offset = 0
        for param in params {
            switch param.type.componentCount {
            case 1:
                header += "#define \(param.name) (params[\(offset)])\n"
            case 2:
                header += "#define \(param.name) float2(params[\(offset)], params[\(offset+1)])\n"
            case 3:
                header += "#define \(param.name) float3(params[\(offset)], params[\(offset+1)], params[\(offset+2)])\n"
            case 4:
                header += "#define \(param.name) float4(params[\(offset)], params[\(offset+1)], params[\(offset+2)], params[\(offset+3)])\n"
            default:
                break
            }
            offset += param.type.componentCount
        }
        header += "// === End User Parameters ===\n\n"
        return header
    }

    public static func injectParamsBuffer(into code: String, paramCount: Int) -> String {
        guard paramCount > 0 else { return code }
        var result = code
        let injection = ",\n                             constant float *params [[buffer(2)]]"
        let pattern = #"((vertex_main|fragment_main)\s*\([\s\S]*?)\)\s*\{"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsResult = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                let fullRange = match.range
                let innerRange = match.range(at: 1)
                let inner = nsResult.substring(with: innerRange)
                if inner.contains("buffer(2)") { continue }
                let replacement = inner + injection + ") {"
                result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
            }
        }
        return result
    }

    public static func packParamBuffer(params: [ShaderParam], values: [String: [Float]]) -> [Float] {
        var buffer: [Float] = []
        for param in params {
            let vals = values[param.name] ?? param.defaultValue
            for i in 0..<param.type.componentCount {
                buffer.append(i < vals.count ? vals[i] : 0)
            }
        }
        return buffer
    }

    public static func stripStructDefinitions(from code: String) -> String {
        var result = code
        let structPattern = #"struct\s+(VertexIn|VertexOut|Uniforms)\s*\{[^}]*\}\s*;?"#
        if let regex = try? NSRegularExpression(pattern: structPattern, options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        let linePatterns = [
            #"^\s*#include\s+<metal_stdlib>\s*$"#,
            #"^\s*using\s+namespace\s+metal\s*;\s*$"#,
        ]
        for pattern in linePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        return result
    }

    // MARK: - Default Shaders

    public static let defaultFragment = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
        float intensity = max(0.2, dot(in.normalOS, lightDir));
        return float4(float3(0.5) * intensity, 1.0);
    }
    """

    public static let blitShader = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        return inTexture.sample(s, in.texCoord);
    }
    """

    public static let fragmentDemo = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float r = 0.5 + 0.5 * cos(in.time + in.normalOS.x * 5.0);
        float g = 0.5 + 0.5 * cos(in.time + in.normalOS.y * 5.0 + 2.0);
        float b = 0.5 + 0.5 * cos(in.time + in.normalOS.z * 5.0 + 4.0);
        
        float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
        float intensity = max(0.3, dot(in.normalOS, lightDir));
        
        return float4(float3(r, g, b) * intensity, 1.0);
    }
    """

    public static let fullscreenDemo = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        
        float2 uv = in.texCoord;
        float4 baseColor = inTexture.sample(s, uv);
        
        float d = length(uv - 0.5);
        float c = sin(d * 40.0 - in.time * 5.0) * 0.5 + 0.5;
        
        float r = sin(uv.x * 10.0 + in.time) * 0.5 + 0.5;
        float g = cos(uv.y * 10.0 - in.time) * 0.5 + 0.5;
        
        float4 effectColor = float4(c * r, c * g, 1.0 - c, 1.0);
        
        return mix(baseColor, effectColor, 0.4);
    }
    """

    // MARK: - Shading Model Presets

    public static let shadingModelNames = [
        "Lambert", "Half Lambert", "NdotL", "Phong", "Blinn-Phong",
        "Fresnel", "Rim Light", "Cel/Toon", "Gooch", "Minnaert"
    ]

    public static func shadingModel(named name: String) -> String? {
        switch name {
        case "Lambert":      return lambertShading
        case "Half Lambert":  return halfLambertShading
        case "NdotL":        return ndotlShading
        case "Phong":        return phongShading
        case "Blinn-Phong":  return blinnPhongShading
        case "Fresnel":      return fresnelShading
        case "Rim Light":    return rimLightShading
        case "Cel/Toon":     return celShading
        case "Gooch":        return goochShading
        case "Minnaert":     return minnaertShading
        default: return nil
        }
    }

    public static let lambertShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 baseColor = float3(0.8, 0.3, 0.2);
        float diffuse = max(0.0, dot(N, L));
        float ambient = 0.1;
        float3 color = baseColor * (ambient + diffuse);
        return float4(color, 1.0);
    }
    """

    public static let halfLambertShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 baseColor = float3(0.7, 0.5, 0.3);
        float halfLambert = dot(N, L) * 0.5 + 0.5;
        halfLambert *= halfLambert;
        float3 color = baseColor * halfLambert;
        return float4(color, 1.0);
    }
    """

    public static let ndotlShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(sin(in.time), 1.0, cos(in.time)));
        float NdotL = dot(N, L);
        float3 color = mix(float3(0.1, 0.1, 0.6), float3(1.0, 0.3, 0.1), NdotL * 0.5 + 0.5);
        return float4(color, 1.0);
    }
    """

    public static let phongShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 R = reflect(-L, N);
        float3 baseColor = float3(0.2, 0.5, 0.8);
        float ambient = 0.1;
        float diffuse = max(0.0, dot(N, L));
        float specular = pow(max(0.0, dot(R, V)), 32.0);
        float3 color = baseColor * (ambient + diffuse) + float3(1.0) * specular;
        return float4(color, 1.0);
    }
    """

    public static let blinnPhongShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 H = normalize(L + V);
        float3 baseColor = float3(0.3, 0.6, 0.9);
        float ambient = 0.1;
        float diffuse = max(0.0, dot(N, L));
        float specular = pow(max(0.0, dot(N, H)), 64.0);
        float3 color = baseColor * (ambient + diffuse) + float3(1.0) * specular;
        return float4(color, 1.0);
    }
    """

    public static let fresnelShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float fresnel = pow(1.0 - max(0.0, dot(N, V)), 3.0);
        float diffuse = max(0.0, dot(N, L));
        float3 baseColor = float3(0.1, 0.1, 0.2);
        float3 rimColor = float3(0.3, 0.6, 1.0);
        float3 color = baseColor * (0.1 + diffuse) + rimColor * fresnel;
        return float4(color, 1.0);
    }
    """

    public static let rimLightShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float diffuse = max(0.0, dot(N, L));
        float rim = 1.0 - max(0.0, dot(N, V));
        rim = pow(rim, 2.5);
        float3 baseColor = float3(0.4, 0.2, 0.6) * (0.15 + diffuse);
        float3 rimColor = float3(1.0, 0.5, 0.8) * rim;
        return float4(baseColor + rimColor, 1.0);
    }
    """

    public static let celShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float NdotL = dot(N, L);
        float toon;
        if (NdotL > 0.6)       toon = 1.0;
        else if (NdotL > 0.2)  toon = 0.6;
        else if (NdotL > -0.1) toon = 0.35;
        else                    toon = 0.15;
        float3 baseColor = float3(0.9, 0.4, 0.3);
        float rim = 1.0 - max(0.0, dot(N, V));
        float outline = step(0.65, rim);
        float3 color = baseColor * toon * (1.0 - outline * 0.7);
        return float4(color, 1.0);
    }
    """

    public static let goochShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float3 baseColor = float3(0.6, 0.3, 0.2);
        float3 coolColor = float3(0.0, 0.0, 0.55) + 0.25 * baseColor;
        float3 warmColor = float3(0.55, 0.45, 0.0) + 0.25 * baseColor;
        float t = (dot(N, L) + 1.0) * 0.5;
        float3 color = mix(coolColor, warmColor, t);
        float3 R = reflect(-L, N);
        float specular = pow(max(0.0, dot(R, V)), 24.0);
        color += float3(1.0) * specular * 0.5;
        return float4(color, 1.0);
    }
    """

    public static let minnaertShading = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalOS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float3 V = normalize(float3(0.0, 0.0, 1.0));
        float NdotL = max(0.0, dot(N, L));
        float NdotV = max(0.0, dot(N, V));
        float darkness = 1.5;
        float minnaert = NdotL * pow(NdotL * NdotV, darkness - 1.0);
        float3 baseColor = float3(0.75, 0.7, 0.6);
        float3 color = baseColor * (0.05 + minnaert);
        return float4(color, 1.0);
    }
    """

    // MARK: - Editor-Specific Shaders

    public static let editorShadingFragment = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalWS);
        float3 L = normalize(float3(0.4, 0.9, 0.5));
        float NdotL = max(0.0, dot(N, L));
        float3 baseColor = float3(0.6);
        float3 color = baseColor * (0.08 + NdotL * 0.92);
        return float4(color, 1.0);
    }
    """

    public static let editorRenderedFragment = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(in.normalWS);
        float3 L = normalize(float3(1.0, 1.0, 1.0));
        float NdotL = max(0.0, dot(N, L));
        float3 baseColor = float3(0.5);
        float3 color = baseColor * (0.1 + NdotL * 0.9);
        return float4(color, 1.0);
    }
    """

    public static let outlineFragment = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        return float4(0.95, 0.55, 0.1, 1.0);
    }
    """

    // MARK: - Object ID Pass (GPU Picking & Outline)

    /// Renders each entity with a unique uint ID into an r32Uint texture.
    /// Used for pixel-perfect picking and post-process outline detection.
    public static let entityIDShader = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float3 positionOS [[attribute(0)]];
        float3 normalOS   [[attribute(1)]];
        float2 uv         [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
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

    vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        out.position = uniforms.mvpMatrix * float4(in.positionOS, 1.0);
        return out;
    }

    fragment uint4 fragment_main(VertexOut in [[stage_in]],
                                 constant uint &entityID [[buffer(6)]]) {
        return uint4(entityID, 0, 0, 0);
    }
    """

    /// Post-process outline from Object ID texture.
    /// Detects edges where the selected entity borders other entities or background.
    public static let outlineCompositeShader = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<uint> idTexture [[texture(0)]],
                                  constant uint &selectedID [[buffer(0)]]) {
        if (selectedID == 0) return float4(0.0);

        uint2 coord = uint2(in.position.xy);
        uint currentID = idTexture.read(coord).r;
        bool isSelected = (currentID == selectedID);

        for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
                if (dx == 0 && dy == 0) continue;
                uint nID = idTexture.read(uint2(int2(coord) + int2(dx, dy))).r;
                if (isSelected != (nID == selectedID)) {
                    return float4(0.95, 0.55, 0.1, 1.0);
                }
            }
        }
        return float4(0.0);
    }
    """

    public static let gridVertexShader = """
    #include <metal_stdlib>
    using namespace metal;

    struct GridVertexIn {
        float3 position [[attribute(0)]];
    };

    struct GridVertexOut {
        float4 position [[position]];
        float4 color;
    };

    struct GridUniforms {
        float4x4 viewProjectionMatrix;
    };

    vertex GridVertexOut grid_vertex(GridVertexIn in [[stage_in]],
                                     constant GridUniforms &uniforms [[buffer(1)]],
                                     constant float4 *colors [[buffer(2)]],
                                     uint vid [[vertex_id]]) {
        GridVertexOut out;
        out.position = uniforms.viewProjectionMatrix * float4(in.position, 1.0);
        out.color = colors[vid / 2];
        return out;
    }

    fragment float4 grid_fragment(GridVertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    // MARK: - Lit Material Template (PBR-friendly)

    /// Studio lighting preamble injected only during Shader Canvas compilation.
    public static let studioLightPreamble = """
    struct StudioLight {
        float3 direction;
        float3 color;
        float  intensity;
    };

    constant StudioLight studioLights[3] = {
        { float3( 0.5657,  0.7071,  0.4243), float3(1.00, 0.96, 0.90), 2.5 },
        { float3(-0.7682,  0.3841,  0.5121), float3(0.40, 0.45, 0.55), 1.0 },
        { float3(-0.1761,  0.4402, -0.8805), float3(0.60, 0.60, 0.70), 1.2 },
    };
    constant int studioLightCount = 3;
    """

    /// A PBR-inspired fragment shader for the Lit Material template.
    /// Uses world-space normals, view direction, and a simplified Cook-Torrance BRDF.
    /// When `uniforms.studioLightOn > 0.5`, uses 3-point studio lighting; otherwise single key light.
    public static let litMaterialFragment = """
    // @param _baseColor color 0.8 0.3 0.2
    // @param _metallic float 0.0 0.0 1.0
    // @param _roughness float 0.5 0.04 1.0
    // @param _ambientIntensity float 0.12 0.0 0.5
    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   constant float *params [[buffer(2)]]) {
        float3 N = normalize(in.normalWS);
        float3 V = normalize(in.viewDirWS);
        float NdotV = max(0.001, dot(N, V));

        float3 baseColor = _baseColor;
        float metallic = _metallic;
        float roughness = max(0.04, _roughness);
        float alpha = roughness * roughness;
        float a2 = alpha * alpha;

        float3 F0 = mix(float3(0.04), baseColor, metallic);
        float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;

        float3 totalColor = float3(0.0);

        int lightCount = (uniforms.studioLightOn > 0.5) ? studioLightCount : 1;
        for (int i = 0; i < lightCount; i++) {
            float3 L = studioLights[i].direction;
            float3 H = normalize(L + V);

            float NdotL = max(0.0, dot(N, L));
            float NdotH = max(0.0, dot(N, H));
            float HdotV = max(0.0, dot(H, V));

            float3 fresnel = F0 + (1.0 - F0) * pow(1.0 - HdotV, 5.0);

            float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
            float D = a2 / (3.14159265 * denom * denom);

            float Gv = NdotV / (NdotV * (1.0 - k) + k);
            float Gl = NdotL / (NdotL * (1.0 - k) + k);
            float G = Gv * Gl;

            float3 specular = (D * G * fresnel) / max(4.0 * NdotV * NdotL, 0.001);
            float3 kD = (1.0 - fresnel) * (1.0 - metallic);
            float3 diffuse = kD * baseColor / 3.14159265;

            totalColor += (diffuse + specular) * NdotL * studioLights[i].color * studioLights[i].intensity;
        }

        totalColor += baseColor * _ambientIntensity;
        return float4(totalColor, 1.0);
    }
    """

    // MARK: - Templates

    public static let fragmentTemplate = """
    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        return float4(1.0, 1.0, 1.0, 1.0);
    }
    """

    public static let fullscreenTemplate = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float time;
    };

    struct Uniforms {
        float4x4 modelViewProjectionMatrix;
        float time;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y;
        out.time = uniforms.time;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.texCoord;
        float4 baseColor = inTexture.sample(s, uv);
        return baseColor;
    }
    """

    // MARK: - Post Processing Presets

    public static let ppPresetNames = [
        "Bloom", "Gaussian Blur", "HSV Adjustment", "Tone Mapping", "Edge Detection"
    ]

    public static func ppPreset(named name: String) -> String? {
        switch name {
        case "Bloom":            return ppBloom
        case "Gaussian Blur":    return ppGaussianBlur
        case "HSV Adjustment":   return ppHSVAdjustment
        case "Tone Mapping":     return ppToneMapping
        case "Edge Detection":   return ppEdgeDetection
        default: return nil
        }
    }

    // PP presets are long shader strings — stored as public statics for access
    public static let ppBloom = """
    // @param _threshold float 0.6 0.0 1.0
    // @param _knee float 0.3 0.0 1.0
    // @param _bloomIntensity float 0.7 0.0 2.0
    // @param _blurRadius float 2.0 0.5 6.0
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 texCoord; float time; };
    struct Uniforms { float4x4 modelViewProjectionMatrix; float time; };
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out; float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0); out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y; out.time = uniforms.time; return out; }
    fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.texCoord; float2 texelSize = 1.0 / float2(inTexture.get_width(), inTexture.get_height());
        float4 baseColor = inTexture.sample(s, uv);
        const int HALF = 6; float gw[7] = { 0.1964, 0.1748, 0.1226, 0.0677, 0.0294, 0.0101, 0.0027 };
        float4 bloom = float4(0.0); float wSum = 0.0;
        for (int dy = -HALF; dy <= HALF; dy++) { float wy = gw[abs(dy)];
            for (int dx = -HALF; dx <= HALF; dx++) { if (abs(dx) + abs(dy) > HALF + 2) continue;
                float wx = gw[abs(dx)]; float w = wx * wy;
                float2 offset = float2(float(dx), float(dy)) * texelSize * _blurRadius;
                float4 sc = inTexture.sample(s, uv + offset);
                float lum = dot(sc.rgb, float3(0.2126, 0.7152, 0.0722));
                float bright = smoothstep(_threshold - _knee, _threshold + _knee, lum);
                bloom += sc * bright * w; wSum += w; } }
        bloom /= wSum; return baseColor + bloom * _bloomIntensity; }
    """

    public static let ppGaussianBlur = """
    // @param _blurScale float 2.0 0.5 8.0
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 texCoord; float time; };
    struct Uniforms { float4x4 modelViewProjectionMatrix; float time; };
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out; float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0); out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y; out.time = uniforms.time; return out; }
    fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.texCoord; float2 texelSize = 1.0 / float2(inTexture.get_width(), inTexture.get_height());
        const int HALF = 6; float w[7] = { 0.1964, 0.1748, 0.1226, 0.0677, 0.0294, 0.0101, 0.0027 };
        float4 color = float4(0.0); float totalW = 0.0;
        for (int dy = -HALF; dy <= HALF; dy++) { float wy = w[abs(dy)];
            for (int dx = -HALF; dx <= HALF; dx++) { if (abs(dx) + abs(dy) > HALF + 2) continue;
                float wx = w[abs(dx)]; float weight = wx * wy;
                float2 offset = float2(float(dx), float(dy)) * texelSize * _blurScale;
                color += inTexture.sample(s, uv + offset) * weight; totalW += weight; } }
        return color / totalW; }
    """

    public static let ppHSVAdjustment = """
    // @param _hueShift float 0.05 0.0 1.0
    // @param _saturation float 1.3 0.0 3.0
    // @param _brightness float 1.05 0.0 2.0
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 texCoord; float time; };
    struct Uniforms { float4x4 modelViewProjectionMatrix; float time; };
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out; float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0); out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y; out.time = uniforms.time; return out; }
    float3 rgb2hsv(float3 c) { float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
        float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
        float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
        float d = q.x - min(q.w, q.y); float e = 1.0e-10;
        return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x); }
    float3 hsv2rgb(float3 c) { float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
        float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y); }
    fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float4 baseColor = inTexture.sample(s, in.texCoord);
        float3 hsv = rgb2hsv(baseColor.rgb); hsv.x = fract(hsv.x + _hueShift);
        hsv.y = clamp(hsv.y * _saturation, 0.0, 1.0); hsv.z = clamp(hsv.z * _brightness, 0.0, 1.0);
        return float4(hsv2rgb(hsv), baseColor.a); }
    """

    public static let ppToneMapping = """
    // @param _exposure float 1.5 0.1 5.0
    // @param _gamma float 0.455 0.1 2.0
    // @param _vignetteOuter float 0.8 0.3 1.5
    // @param _vignetteInner float 0.35 0.0 1.0
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 texCoord; float time; };
    struct Uniforms { float4x4 modelViewProjectionMatrix; float time; };
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out; float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0); out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y; out.time = uniforms.time; return out; }
    float3 acesFilm(float3 x) { float a=2.51; float b=0.03; float c=2.43; float d=0.59; float e=0.14;
        return clamp((x*(a*x+b))/(x*(c*x+d)+e), 0.0, 1.0); }
    fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float4 baseColor = inTexture.sample(s, in.texCoord);
        float3 hdr = baseColor.rgb * _exposure; float3 mapped = acesFilm(hdr);
        mapped = pow(mapped, float3(_gamma));
        float d = length(in.texCoord - 0.5); float vignette = smoothstep(_vignetteOuter, _vignetteInner, d);
        mapped *= vignette; return float4(mapped, 1.0); }
    """

    public static let ppEdgeDetection = """
    // @param _edgeThreshold float 0.15 0.0 1.0
    // @param _edgeStrength float 0.85 0.0 1.0
    // @param _edgeColor color 1.0 0.9 0.7
    #include <metal_stdlib>
    using namespace metal;
    struct VertexOut { float4 position [[position]]; float2 texCoord; float time; };
    struct Uniforms { float4x4 modelViewProjectionMatrix; float time; };
    vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant Uniforms &uniforms [[buffer(1)]]) {
        VertexOut out; float2 positions[3] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
        out.position = float4(positions[vertexID], 0.0, 1.0); out.texCoord = positions[vertexID] * 0.5 + 0.5;
        out.texCoord.y = 1.0 - out.texCoord.y; out.time = uniforms.time; return out; }
    float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
    fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> inTexture [[texture(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 uv = in.texCoord; float2 texelSize = 1.0 / float2(inTexture.get_width(), inTexture.get_height());
        float tl = luminance(inTexture.sample(s, uv + float2(-1,-1)*texelSize).rgb);
        float tm = luminance(inTexture.sample(s, uv + float2(0,-1)*texelSize).rgb);
        float tr = luminance(inTexture.sample(s, uv + float2(1,-1)*texelSize).rgb);
        float ml = luminance(inTexture.sample(s, uv + float2(-1,0)*texelSize).rgb);
        float mr = luminance(inTexture.sample(s, uv + float2(1,0)*texelSize).rgb);
        float bl = luminance(inTexture.sample(s, uv + float2(-1,1)*texelSize).rgb);
        float bm = luminance(inTexture.sample(s, uv + float2(0,1)*texelSize).rgb);
        float br = luminance(inTexture.sample(s, uv + float2(1,1)*texelSize).rgb);
        float gx = -tl-2.0*ml-bl+tr+2.0*mr+br; float gy = -tl-2.0*tm-tr+bl+2.0*bm+br;
        float edge = sqrt(gx*gx+gy*gy); edge = smoothstep(_edgeThreshold, _edgeThreshold+0.1, edge);
        float4 baseColor = inTexture.sample(s, uv);
        float3 result = mix(baseColor.rgb, _edgeColor, edge * _edgeStrength);
        return float4(result, 1.0); }
    """
}
