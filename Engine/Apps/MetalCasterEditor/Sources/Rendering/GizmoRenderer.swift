import Metal
import MetalKit
import simd
import MetalCasterRenderer

/// Renders context-sensitive gizmos: Translate (arrows), Scale (cubes), Rotate (rings).
final class GizmoRenderer {

    enum Mode {
        case translate
        case scale
        case rotate
    }

    private let pipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    private struct GizmoUniforms {
        var viewProjectionMatrix: simd_float4x4
    }

    struct Vertex {
        var position: SIMD3<Float>
        var color: SIMD4<Float>
    }

    static let xColor = SIMD4<Float>(0.95, 0.15, 0.15, 1.0)
    static let yColor = SIMD4<Float>(0.25, 0.9, 0.15, 1.0)
    static let zColor = SIMD4<Float>(0.2, 0.35, 0.95, 1.0)
    static let viewRingColor = SIMD4<Float>(0.85, 0.85, 0.85, 0.7)
    static let centerColor = SIMD4<Float>(0.8, 0.8, 0.8, 0.8)

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

    // MARK: - Public Draw

    func draw(encoder: MTLRenderCommandEncoder,
              viewProjectionMatrix: simd_float4x4,
              worldPosition: SIMD3<Float>,
              scale: Float,
              mode: Mode,
              device: MTLDevice) {

        let eye = extractCameraPosition(from: viewProjectionMatrix)
        let viewDir = normalize(worldPosition - eye)

        var vertices: [Vertex] = []

        switch mode {
        case .translate:
            buildTranslateGizmo(into: &vertices, pos: worldPosition, scale: scale, viewDir: viewDir)
        case .scale:
            buildScaleGizmo(into: &vertices, pos: worldPosition, scale: scale, viewDir: viewDir)
        case .rotate:
            buildRotateGizmo(into: &vertices, pos: worldPosition, scale: scale, viewDir: viewDir)
        }

        buildCenterDot(into: &vertices, pos: worldPosition, scale: scale)

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)

        var uniforms = GizmoUniforms(viewProjectionMatrix: viewProjectionMatrix)
        let byteLength = MemoryLayout<Vertex>.stride * vertices.count
        if byteLength <= 4096 {
            encoder.setVertexBytes(&vertices, length: byteLength, index: 0)
        } else {
            guard let buffer = device.makeBuffer(bytes: &vertices, length: byteLength, options: .storageModeShared) else { return }
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GizmoUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    // MARK: - Translate Gizmo (arrows)

    private func buildTranslateGizmo(into vertices: inout [Vertex], pos: SIMD3<Float>, scale: Float, viewDir: SIMD3<Float>) {
        let shaftLen = scale
        let shaftWidth = scale * 0.025
        let headLen = scale * 0.18
        let headWidth = scale * 0.06

        for (axisDir, color) in axesAndColors() {
            let perp = perpendicular(to: axisDir, viewDir: viewDir)
            let tip = pos + axisDir * shaftLen

            addQuad(into: &vertices, color: color,
                    a: pos + perp * shaftWidth, b: pos - perp * shaftWidth,
                    c: tip + perp * shaftWidth, d: tip - perp * shaftWidth)

            let arrowTip = pos + axisDir * (shaftLen + headLen)
            addTriangle(into: &vertices, color: color,
                        a: tip + perp * headWidth, b: tip - perp * headWidth, c: arrowTip)

            let perp2 = normalize(cross(axisDir, perp))
            addTriangle(into: &vertices, color: color,
                        a: tip + perp2 * headWidth, b: tip - perp2 * headWidth, c: arrowTip)
        }
    }

    // MARK: - Scale Gizmo (cubes at endpoints)

    private func buildScaleGizmo(into vertices: inout [Vertex], pos: SIMD3<Float>, scale: Float, viewDir: SIMD3<Float>) {
        let shaftLen = scale
        let shaftWidth = scale * 0.025
        let cubeHalf = scale * 0.05

        for (axisDir, color) in axesAndColors() {
            let perp = perpendicular(to: axisDir, viewDir: viewDir)
            let tip = pos + axisDir * shaftLen

            addQuad(into: &vertices, color: color,
                    a: pos + perp * shaftWidth, b: pos - perp * shaftWidth,
                    c: tip + perp * shaftWidth, d: tip - perp * shaftWidth)

            let perp2 = normalize(cross(axisDir, perp))
            addCube(into: &vertices, color: color, center: tip, halfSize: cubeHalf,
                    right: perp, up: perp2, forward: axisDir)
        }

        let centerHalf = scale * 0.06
        let cColor = SIMD4<Float>(0.9, 0.9, 0.9, 0.85)
        addCube(into: &vertices, color: cColor, center: pos, halfSize: centerHalf,
                right: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 1, 0), forward: SIMD3<Float>(0, 0, 1))
    }

    // MARK: - Rotate Gizmo (rings)

    private func buildRotateGizmo(into vertices: inout [Vertex], pos: SIMD3<Float>, scale: Float, viewDir: SIMD3<Float>) {
        let ringRadius = scale * 0.9
        let ringWidth = scale * 0.045
        let segments = 48

        let axisRings: [(SIMD3<Float>, SIMD3<Float>, SIMD4<Float>)] = [
            (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), Self.xColor),
            (SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1), Self.yColor),
            (SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0), Self.zColor),
        ]

        for (normal, startVec, color) in axisRings {
            addRing(into: &vertices, color: color, center: pos,
                    normal: normal, startVec: startVec,
                    radius: ringRadius, width: ringWidth, segments: segments, viewDir: viewDir)
        }

        let viewNormal = normalize(-viewDir)
        var viewStart = cross(viewNormal, SIMD3<Float>(0, 1, 0))
        if length(viewStart) < 0.001 {
            viewStart = cross(viewNormal, SIMD3<Float>(1, 0, 0))
        }
        viewStart = normalize(viewStart)

        addRing(into: &vertices, color: Self.viewRingColor, center: pos,
                normal: viewNormal, startVec: viewStart,
                radius: ringRadius * 1.15, width: ringWidth * 1.3, segments: segments, viewDir: viewDir)
    }

    // MARK: - Primitives

    private func axesAndColors() -> [(SIMD3<Float>, SIMD4<Float>)] {
        [
            (SIMD3<Float>(1, 0, 0), Self.xColor),
            (SIMD3<Float>(0, 1, 0), Self.yColor),
            (SIMD3<Float>(0, 0, 1), Self.zColor),
        ]
    }

    private func addQuad(into vertices: inout [Vertex], color: SIMD4<Float>,
                         a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, d: SIMD3<Float>) {
        vertices.append(contentsOf: [
            Vertex(position: a, color: color), Vertex(position: b, color: color), Vertex(position: c, color: color),
            Vertex(position: b, color: color), Vertex(position: d, color: color), Vertex(position: c, color: color),
        ])
    }

    private func addTriangle(into vertices: inout [Vertex], color: SIMD4<Float>,
                             a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) {
        vertices.append(contentsOf: [
            Vertex(position: a, color: color), Vertex(position: b, color: color), Vertex(position: c, color: color),
        ])
    }

    private func addCube(into vertices: inout [Vertex], color: SIMD4<Float>,
                         center: SIMD3<Float>, halfSize: Float,
                         right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
        let r = right * halfSize
        let u = up * halfSize
        let f = forward * halfSize

        let c0: SIMD3<Float> = center - r - u - f
        let c1: SIMD3<Float> = center + r - u - f
        let c2: SIMD3<Float> = center + r + u - f
        let c3: SIMD3<Float> = center - r + u - f
        let c4: SIMD3<Float> = center - r - u + f
        let c5: SIMD3<Float> = center + r - u + f
        let c6: SIMD3<Float> = center + r + u + f
        let c7: SIMD3<Float> = center - r + u + f

        addQuad(into: &vertices, color: color, a: c0, b: c1, c: c3, d: c2) // -Z
        addQuad(into: &vertices, color: color, a: c5, b: c4, c: c6, d: c7) // +Z
        addQuad(into: &vertices, color: color, a: c4, b: c0, c: c7, d: c3) // -X
        addQuad(into: &vertices, color: color, a: c1, b: c5, c: c2, d: c6) // +X
        addQuad(into: &vertices, color: color, a: c3, b: c2, c: c7, d: c6) // +Y
        addQuad(into: &vertices, color: color, a: c4, b: c5, c: c0, d: c1) // -Y
    }

    private func addRing(into vertices: inout [Vertex], color: SIMD4<Float>,
                         center: SIMD3<Float>, normal: SIMD3<Float>, startVec: SIMD3<Float>,
                         radius: Float, width: Float, segments: Int, viewDir: SIMD3<Float>) {
        let bitangent = normalize(cross(normal, startVec))
        let tangent = normalize(startVec)

        for i in 0..<segments {
            let angle0 = Float(i) / Float(segments) * Float.pi * 2
            let angle1 = Float(i + 1) / Float(segments) * Float.pi * 2

            let dir0 = tangent * cos(angle0) + bitangent * sin(angle0)
            let dir1 = tangent * cos(angle1) + bitangent * sin(angle1)

            let p0 = center + dir0 * radius
            let p1 = center + dir1 * radius

            let segTangent0 = normalize(dir1 - dir0)
            let segTangent1 = segTangent0

            var perp0 = cross(segTangent0, viewDir)
            if length(perp0) < 0.001 { perp0 = cross(segTangent0, SIMD3<Float>(0, 1, 0)) }
            perp0 = normalize(perp0) * width

            var perp1 = cross(segTangent1, viewDir)
            if length(perp1) < 0.001 { perp1 = cross(segTangent1, SIMD3<Float>(0, 1, 0)) }
            perp1 = normalize(perp1) * width

            addQuad(into: &vertices, color: color,
                    a: p0 + perp0, b: p0 - perp0,
                    c: p1 + perp1, d: p1 - perp1)
        }
    }

    private func buildCenterDot(into vertices: inout [Vertex], pos: SIMD3<Float>, scale: Float) {
        let s = scale * 0.04
        let c = Self.centerColor
        let u = SIMD3<Float>(0, 1, 0) * s
        let r = SIMD3<Float>(1, 0, 0) * s
        let f = SIMD3<Float>(0, 0, 1) * s
        vertices.append(contentsOf: [
            Vertex(position: pos + u, color: c), Vertex(position: pos + r, color: c), Vertex(position: pos + f, color: c),
            Vertex(position: pos - u, color: c), Vertex(position: pos - r, color: c), Vertex(position: pos - f, color: c),
        ])
    }

    // MARK: - Math Helpers

    private func perpendicular(to axis: SIMD3<Float>, viewDir: SIMD3<Float>) -> SIMD3<Float> {
        var perp = cross(axis, viewDir)
        if length(perp) < 0.001 {
            let fallback = abs(dot(axis, SIMD3<Float>(0, 1, 0))) < 0.99
                ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            perp = cross(axis, fallback)
        }
        return normalize(perp)
    }

    private func extractCameraPosition(from vpMatrix: simd_float4x4) -> SIMD3<Float> {
        let inv = vpMatrix.inverse
        return SIMD3<Float>(inv.columns.3.x, inv.columns.3.y, inv.columns.3.z) / inv.columns.3.w
    }
}
