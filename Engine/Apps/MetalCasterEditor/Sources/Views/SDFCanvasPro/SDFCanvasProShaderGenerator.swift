import Foundation
import simd

/// Compiles an `SDFNode` tree into a complete MSL shader string
/// for real-time ray marching preview in the SDF Canvas viewport.
enum SDFShaderGenerator {

    // MARK: - Public API

    /// Generate a complete MSL shader from an SDF tree.
    static func generate(tree: SDFNode, maxSteps: Int = 128, threshold: Float = 0.001) -> String {
        var varCounter = 0
        let (sceneLines, resultVar) = emit(node: tree, counter: &varCounter)
        let sceneBody = sceneLines.joined(separator: "\n    ")

        return """
        #include <metal_stdlib>
        using namespace metal;

        // Uniforms

        struct SDFUniforms {
            float4x4 inverseViewProjection;
            float3   cameraPosition;
            float    time;
            float2   resolution;
            int      maxSteps;
            float    surfaceThreshold;
        };

        // SDF Primitives

        \(primitiveLibrary)

        // Boolean Operations

        \(booleanLibrary)

        // Domain Modifiers

        \(modifierLibrary)

        // Scene SDF

        float sdf_scene(float3 p) {
            \(sceneBody)
            return \(resultVar);
        }

        // Normal via Central Differences

        float3 sdf_normal(float3 p, float eps) {
            return normalize(float3(
                sdf_scene(p + float3(eps, 0, 0)) - sdf_scene(p - float3(eps, 0, 0)),
                sdf_scene(p + float3(0, eps, 0)) - sdf_scene(p - float3(0, eps, 0)),
                sdf_scene(p + float3(0, 0, eps)) - sdf_scene(p - float3(0, 0, eps))
            ));
        }

        // Soft Shadow

        float sdf_softShadow(float3 ro, float3 rd, float mint, float maxt, float k) {
            float res = 1.0;
            float t = mint;
            for (int i = 0; i < 64 && t < maxt; i++) {
                float h = sdf_scene(ro + rd * t);
                if (h < 0.0001) return 0.0;
                res = min(res, k * h / t);
                t += h;
            }
            return clamp(res, 0.0, 1.0);
        }

        // Ambient Occlusion

        float sdf_ao(float3 p, float3 n) {
            float occ = 0.0;
            float scale = 1.0;
            for (int i = 0; i < 5; i++) {
                float dist = 0.01 + 0.12 * float(i);
                float d = sdf_scene(p + n * dist);
                occ += (dist - d) * scale;
                scale *= 0.75;
            }
            return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
        }

        // Vertex Shader (Fullscreen Triangle)

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
            VertexOut out;
            out.uv = float2((vid << 1) & 2, vid & 2);
            out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
            out.uv.y = 1.0 - out.uv.y;
            return out;
        }

        // Fragment Shader (Ray March)

        fragment float4 fragment_main(
            VertexOut in [[stage_in]],
            constant SDFUniforms &uniforms [[buffer(0)]]
        ) {
            float2 ndc = in.uv * 2.0 - 1.0;

            float4 nearClip = uniforms.inverseViewProjection * float4(ndc, -1.0, 1.0);
            float4 farClip  = uniforms.inverseViewProjection * float4(ndc,  1.0, 1.0);
            float3 near = nearClip.xyz / nearClip.w;
            float3 far  = farClip.xyz  / farClip.w;

            float3 ro = uniforms.cameraPosition;
            float3 rd = normalize(far - near);

            // Ray march
            float t = 0.0;
            float d = 0.0;
            int steps = uniforms.maxSteps;
            float threshold = uniforms.surfaceThreshold;

            for (int i = 0; i < steps; i++) {
                float3 p = ro + rd * t;
                d = sdf_scene(p);
                if (d < threshold) break;
                t += d;
                if (t > 100.0) break;
            }

            if (d > threshold * 10.0) {
                // Background gradient
                float grad = 0.5 + 0.5 * rd.y;
                float3 bg = mix(float3(0.05, 0.05, 0.08), float3(0.12, 0.12, 0.18), grad);
                return float4(bg, 1.0);
            }

            float3 pos = ro + rd * t;
            float3 nor = sdf_normal(pos, 0.001);

            // Lighting
            float3 lightDir = normalize(float3(0.8, 1.0, 0.6));
            float3 lightColor = float3(1.0, 0.98, 0.95);

            float diff = max(dot(nor, lightDir), 0.0);
            float shadow = sdf_softShadow(pos + nor * 0.002, lightDir, 0.01, 10.0, 16.0);
            diff *= shadow;

            float3 halfVec = normalize(lightDir - rd);
            float spec = pow(max(dot(nor, halfVec), 0.0), 32.0) * shadow;

            float ao = sdf_ao(pos, nor);

            float3 ambient = float3(0.15, 0.17, 0.22) * ao;
            float3 baseColor = float3(0.75, 0.75, 0.78);

            float3 color = baseColor * (ambient + diff * lightColor) + spec * lightColor * 0.4;

            // Tone mapping (Reinhard)
            color = color / (color + 1.0);
            // Gamma
            color = pow(color, float3(1.0 / 2.2));

            return float4(color, 1.0);
        }
        """
    }

    // MARK: - Recursive Emitter

    /// Recursively emit MSL code for a node, returning (lines, variable_name).
    private static func emit(node: SDFNode, counter: inout Int) -> ([String], String) {
        let varName = "d\(counter)"
        counter += 1

        switch node {
        case .sphere(_, let r):
            return (["float \(varName) = sdSphere(p, \(f(r)));"], varName)

        case .box(_, let s):
            return (["float \(varName) = sdBox(p, \(v3(s)));"], varName)

        case .roundedBox(_, let s, let r):
            return (["float \(varName) = sdRoundBox(p, \(v3(s)), \(f(r)));"], varName)

        case .cylinder(_, let r, let h):
            return (["float \(varName) = sdCylinder(p, \(f(r)), \(f(h)));"], varName)

        case .torus(_, let major, let minor):
            return (["float \(varName) = sdTorus(p, float2(\(f(major)), \(f(minor))));"], varName)

        case .capsule(_, let r, let h):
            return (["float \(varName) = sdCapsule(p, \(f(r)), \(f(h)));"], varName)

        case .cone(_, let r, let h):
            return (["float \(varName) = sdCone(p, \(f(r)), \(f(h)));"], varName)

        // Boolean operations
        case .union(_, let a, let b):
            return emitBinary(a, b, op: "opUnion", counter: &counter, varName: varName)

        case .subtraction(_, let a, let b):
            return emitBinary(a, b, op: "opSubtraction", counter: &counter, varName: varName)

        case .intersection(_, let a, let b):
            return emitBinary(a, b, op: "opIntersection", counter: &counter, varName: varName)

        case .smoothUnion(_, let a, let b, let k):
            return emitBinary(a, b, op: "opSmoothUnion", extra: f(k), counter: &counter, varName: varName)

        case .smoothSubtraction(_, let a, let b, let k):
            return emitBinary(a, b, op: "opSmoothSubtraction", extra: f(k), counter: &counter, varName: varName)

        case .smoothIntersection(_, let a, let b, let k):
            return emitBinary(a, b, op: "opSmoothIntersection", extra: f(k), counter: &counter, varName: varName)

        // Transform
        case .transform(_, let child, let pos, let rot, let scl):
            let localP = "tp\(counter)"
            counter += 1

            let invRot = rot.inverse
            let col0 = invRot.act(SIMD3<Float>(1, 0, 0))
            let col1 = invRot.act(SIMD3<Float>(0, 1, 0))
            let col2 = invRot.act(SIMD3<Float>(0, 0, 1))

            var lines: [String] = []
            lines.append("float3 \(localP) = p - \(v3(pos));")
            lines.append("float3x3 invRot_\(localP) = float3x3(\(v3(col0)), \(v3(col1)), \(v3(col2)));")
            lines.append("\(localP) = invRot_\(localP) * \(localP);")
            lines.append("\(localP) /= \(v3(scl));")

            lines.append("float3 savedP_\(localP) = p;")
            lines.append("p = \(localP);")

            let (childLines, childVar) = emit(node: child, counter: &counter)
            lines.append(contentsOf: childLines)

            let minScale = min(scl.x, min(scl.y, scl.z))
            lines.append("float \(varName) = \(childVar) * \(f(minScale));")
            lines.append("p = savedP_\(localP);")

            return (lines, varName)

        // Modifiers
        case .round(_, let child, let r):
            let (childLines, childVar) = emit(node: child, counter: &counter)
            var lines = childLines
            lines.append("float \(varName) = \(childVar) - \(f(r));")
            return (lines, varName)

        case .onion(_, let child, let t):
            let (childLines, childVar) = emit(node: child, counter: &counter)
            var lines = childLines
            lines.append("float \(varName) = abs(\(childVar)) - \(f(t));")
            return (lines, varName)

        case .twist(_, let child, let amount):
            return emitDomainMod(child, counter: &counter, varName: varName) { pLocal in
                [
                    "float c_\(pLocal) = cos(\(f(amount)) * \(pLocal).y);",
                    "float s_\(pLocal) = sin(\(f(amount)) * \(pLocal).y);",
                    "\(pLocal) = float3(c_\(pLocal) * \(pLocal).x - s_\(pLocal) * \(pLocal).z, \(pLocal).y, s_\(pLocal) * \(pLocal).x + c_\(pLocal) * \(pLocal).z);"
                ]
            }

        case .bend(_, let child, let amount):
            return emitDomainMod(child, counter: &counter, varName: varName) { pLocal in
                [
                    "float c_\(pLocal) = cos(\(f(amount)) * \(pLocal).x);",
                    "float s_\(pLocal) = sin(\(f(amount)) * \(pLocal).x);",
                    "\(pLocal) = float3(c_\(pLocal) * \(pLocal).x - s_\(pLocal) * \(pLocal).y, s_\(pLocal) * \(pLocal).x + c_\(pLocal) * \(pLocal).y, \(pLocal).z);"
                ]
            }

        case .elongate(_, let child, let h):
            return emitDomainMod(child, counter: &counter, varName: varName) { pLocal in
                ["\(pLocal) = \(pLocal) - clamp(\(pLocal), -\(v3(h)), \(v3(h)));"]
            }

        case .repeatSpace(_, let child, let period):
            return emitDomainMod(child, counter: &counter, varName: varName) { pLocal in
                ["\(pLocal) = \(pLocal) - \(v3(period)) * round(\(pLocal) / \(v3(period)));"]
            }
        }
    }

    // MARK: - Emission Helpers

    private static func emitBinary(
        _ a: SDFNode, _ b: SDFNode,
        op: String, extra: String? = nil,
        counter: inout Int, varName: String
    ) -> ([String], String) {
        let (linesA, varA) = emit(node: a, counter: &counter)
        let (linesB, varB) = emit(node: b, counter: &counter)
        var lines = linesA + linesB
        if let extra {
            lines.append("float \(varName) = \(op)(\(varA), \(varB), \(extra));")
        } else {
            lines.append("float \(varName) = \(op)(\(varA), \(varB));")
        }
        return (lines, varName)
    }

    private static func emitDomainMod(
        _ child: SDFNode,
        counter: inout Int, varName: String,
        transform: (String) -> [String]
    ) -> ([String], String) {
        let pLocal = "mp\(counter)"
        counter += 1

        var lines: [String] = []
        lines.append("float3 \(pLocal) = p;")
        lines.append(contentsOf: transform(pLocal))
        lines.append("float3 savedP_\(pLocal) = p;")
        lines.append("p = \(pLocal);")

        let (childLines, childVar) = emit(node: child, counter: &counter)
        lines.append(contentsOf: childLines)

        lines.append("float \(varName) = \(childVar);")
        lines.append("p = savedP_\(pLocal);")

        return (lines, varName)
    }

    // MARK: - Formatting Helpers

    private static func f(_ v: Float) -> String {
        if v == Float(Int(v)) {
            return String(format: "%.1f", v)
        }
        return String(format: "%.6f", v)
    }

    private static func v3(_ v: SIMD3<Float>) -> String {
        "float3(\(f(v.x)), \(f(v.y)), \(f(v.z)))"
    }

    // MARK: - MSL Libraries

    private static let primitiveLibrary = """
    float sdSphere(float3 p, float r) {
        return length(p) - r;
    }

    float sdBox(float3 p, float3 b) {
        float3 q = abs(p) - b * 0.5;
        return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
    }

    float sdRoundBox(float3 p, float3 b, float r) {
        float3 q = abs(p) - b * 0.5 + r;
        return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
    }

    float sdCylinder(float3 p, float r, float h) {
        float2 d = float2(length(p.xz) - r, abs(p.y) - h * 0.5);
        return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
    }

    float sdTorus(float3 p, float2 t) {
        float2 q = float2(length(p.xz) - t.x, p.y);
        return length(q) - t.y;
    }

    float sdCapsule(float3 p, float r, float h) {
        p.y -= clamp(p.y, -h * 0.5, h * 0.5);
        return length(p) - r;
    }

    float sdCone(float3 p, float r, float h) {
        float2 q = float2(length(p.xz), p.y);
        float2 tip = float2(0.0, h);
        float2 cb = float2(r, 0.0);
        float2 ba = cb - tip;
        float2 pa = q - tip;
        float2 x = pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float2 y = pa - float2(cb.x * clamp(pa.x / cb.x, 0.0, 1.0), cb.y);
        float d = min(dot(x, x), dot(y, y));
        float s = max(-pa.y, pa.x * ba.y - pa.y * ba.x) > 0.0 ? 1.0 : -1.0;
        return s * sqrt(d);
    }
    """

    private static let booleanLibrary = """
    float opUnion(float d1, float d2) {
        return min(d1, d2);
    }

    float opSubtraction(float d1, float d2) {
        return max(d1, -d2);
    }

    float opIntersection(float d1, float d2) {
        return max(d1, d2);
    }

    float opSmoothUnion(float d1, float d2, float k) {
        float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
        return mix(d2, d1, h) - k * h * (1.0 - h);
    }

    float opSmoothSubtraction(float d1, float d2, float k) {
        float h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0.0, 1.0);
        return mix(d1, -d2, h) + k * h * (1.0 - h);
    }

    float opSmoothIntersection(float d1, float d2, float k) {
        float h = clamp(0.5 - 0.5 * (d2 - d1) / k, 0.0, 1.0);
        return mix(d2, d1, h) + k * h * (1.0 - h);
    }
    """

    private static let modifierLibrary = """
    // Domain modifiers are inlined by the generator into sdf_scene().
    // This section is reserved for future shared modifier utilities.
    """
}
