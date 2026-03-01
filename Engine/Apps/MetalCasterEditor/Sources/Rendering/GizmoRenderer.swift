import Metal
import MetalKit
import simd
import MetalCasterRenderer

/// Draws a 3-axis translation gizmo (RGB = XYZ) with visible shafts and arrow tips.
final class GizmoRenderer {

    private let pipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    private struct GizmoUniforms {
        var viewProjectionMatrix: simd_float4x4
    }

    struct Vertex {
        var position: SIMD3<Float>
        var color: SIMD4<Float>
    }

    init?(device: MTLDevice) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct GizmoVertex {
            float3 position;
            float4 color;
        };

        struct GizmoOut {
            float4 position [[position]];
            float4 color;
        };

        struct GizmoUniforms {
            float4x4 viewProjectionMatrix;
        };

        vertex GizmoOut gizmo_vertex(const device GizmoVertex *vertices [[buffer(0)]],
                                      constant GizmoUniforms &uniforms [[buffer(1)]],
                                      uint vid [[vertex_id]]) {
            GizmoOut out;
            out.position = uniforms.viewProjectionMatrix * float4(vertices[vid].position, 1.0);
            out.color = vertices[vid].color;
            return out;
        }

        fragment float4 gizmo_fragment(GizmoOut in [[stage_in]]) {
            return in.color;
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "gizmo_vertex"),
              let fragFunc = library.makeFunction(name: "gizmo_fragment") else {
            return nil
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertexFunc
        pipeDesc.fragmentFunction = fragFunc
        pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeDesc.colorAttachments[0].isBlendingEnabled = true
        pipeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeDesc.depthAttachmentPixelFormat = .depth32Float

        guard let pso = try? device.makeRenderPipelineState(descriptor: pipeDesc) else {
            return nil
        }
        pipeline = pso

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .always
        depthDesc.isDepthWriteEnabled = false
        guard let dss = device.makeDepthStencilState(descriptor: depthDesc) else {
            return nil
        }
        depthStencilState = dss
    }

    func draw(encoder: MTLRenderCommandEncoder,
              viewProjectionMatrix: simd_float4x4,
              worldPosition: SIMD3<Float>,
              scale: Float,
              device: MTLDevice) {

        let eye = extractCameraPosition(from: viewProjectionMatrix)
        let viewDir = normalize(worldPosition - eye)

        var vertices: [Vertex] = []

        let xColor = SIMD4<Float>(0.95, 0.15, 0.15, 1.0)
        let yColor = SIMD4<Float>(0.25, 0.9, 0.15, 1.0)
        let zColor = SIMD4<Float>(0.2, 0.35, 0.95, 1.0)

        let shaftLen = scale
        let shaftWidth = scale * 0.025
        let headLen = scale * 0.18
        let headWidth = scale * 0.06

        let axes: [(SIMD3<Float>, SIMD4<Float>)] = [
            (SIMD3<Float>(1, 0, 0), xColor),
            (SIMD3<Float>(0, 1, 0), yColor),
            (SIMD3<Float>(0, 0, 1), zColor),
        ]

        for (axisDir, color) in axes {
            let perp = shaftPerpendicular(axis: axisDir, viewDir: viewDir)

            let p = worldPosition
            let tip = p + axisDir * shaftLen

            let a = p + perp * shaftWidth
            let b = p - perp * shaftWidth
            let c = tip + perp * shaftWidth
            let d = tip - perp * shaftWidth

            vertices.append(contentsOf: [
                Vertex(position: a, color: color),
                Vertex(position: b, color: color),
                Vertex(position: c, color: color),
                Vertex(position: b, color: color),
                Vertex(position: d, color: color),
                Vertex(position: c, color: color),
            ])

            let arrowTip = p + axisDir * (shaftLen + headLen)
            let ha = tip + perp * headWidth
            let hb = tip - perp * headWidth

            vertices.append(contentsOf: [
                Vertex(position: ha, color: color),
                Vertex(position: hb, color: color),
                Vertex(position: arrowTip, color: color),
            ])

            let perp2 = shaftPerpendicular2(axis: axisDir, perp1: perp)
            let ha2 = tip + perp2 * headWidth
            let hb2 = tip - perp2 * headWidth
            vertices.append(contentsOf: [
                Vertex(position: ha2, color: color),
                Vertex(position: hb2, color: color),
                Vertex(position: arrowTip, color: color),
            ])
        }

        let centerSize = scale * 0.04
        let cColor = SIMD4<Float>(0.8, 0.8, 0.8, 0.8)
        let cp = worldPosition
        let cu = SIMD3<Float>(0, 1, 0) * centerSize
        let cr = SIMD3<Float>(1, 0, 0) * centerSize
        let cf = SIMD3<Float>(0, 0, 1) * centerSize
        vertices.append(contentsOf: [
            Vertex(position: cp + cu, color: cColor),
            Vertex(position: cp + cr, color: cColor),
            Vertex(position: cp + cf, color: cColor),
            Vertex(position: cp - cu, color: cColor),
            Vertex(position: cp - cr, color: cColor),
            Vertex(position: cp - cf, color: cColor),
        ])

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)

        var uniforms = GizmoUniforms(viewProjectionMatrix: viewProjectionMatrix)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GizmoUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func shaftPerpendicular(axis: SIMD3<Float>, viewDir: SIMD3<Float>) -> SIMD3<Float> {
        var perp = cross(axis, viewDir)
        if length(perp) < 0.001 {
            let fallback = abs(dot(axis, SIMD3<Float>(0, 1, 0))) < 0.99
                ? SIMD3<Float>(0, 1, 0)
                : SIMD3<Float>(1, 0, 0)
            perp = cross(axis, fallback)
        }
        return normalize(perp)
    }

    private func shaftPerpendicular2(axis: SIMD3<Float>, perp1: SIMD3<Float>) -> SIMD3<Float> {
        normalize(cross(axis, perp1))
    }

    private func extractCameraPosition(from vpMatrix: simd_float4x4) -> SIMD3<Float> {
        let inv = vpMatrix.inverse
        return SIMD3<Float>(inv.columns.3.x, inv.columns.3.y, inv.columns.3.z) / inv.columns.3.w
    }
}
