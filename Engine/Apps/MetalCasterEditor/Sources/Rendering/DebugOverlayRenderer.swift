import Metal
import MetalKit
import simd
import MetalCasterRenderer
import MetalCasterScene

/// Renders debug visualizations for selected cameras (frustum) and lights (direction/range/cone).
/// Uses line primitives for wireframe shapes and triangle primitives for filled indicators.
final class DebugOverlayRenderer {

    private let pipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    private struct Uniforms {
        var viewProjectionMatrix: simd_float4x4
    }

    struct Vertex {
        var position: SIMD3<Float>
        var color: SIMD4<Float>
    }

    static let cameraColor      = SIMD4<Float>(1.0, 0.85, 0.2, 0.7)
    static let cameraFillColor  = SIMD4<Float>(1.0, 0.85, 0.2, 0.06)
    static let cameraDimColor   = SIMD4<Float>(1.0, 0.85, 0.2, 0.25)

    init?(device: MTLDevice) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct DebugVertex {
            float3 position;
            float4 color;
        };

        struct DebugOut {
            float4 position [[position]];
            float4 color;
        };

        struct DebugUniforms {
            float4x4 viewProjectionMatrix;
        };

        vertex DebugOut debug_overlay_vertex(const device DebugVertex *vertices [[buffer(0)]],
                                              constant DebugUniforms &uniforms [[buffer(1)]],
                                              uint vid [[vertex_id]]) {
            DebugOut out;
            out.position = uniforms.viewProjectionMatrix * float4(vertices[vid].position, 1.0);
            out.color = vertices[vid].color;
            return out;
        }

        fragment float4 debug_overlay_fragment(DebugOut in [[stage_in]]) {
            return in.color;
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "debug_overlay_vertex"),
              let fragFunc = library.makeFunction(name: "debug_overlay_fragment") else {
            return nil
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertexFunc
        pipeDesc.fragmentFunction = fragFunc
        pipeDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeDesc.colorAttachments[0].isBlendingEnabled = true
        pipeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipeDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
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

    // MARK: - Camera Frustum

    func drawCameraFrustum(
        encoder: MTLRenderCommandEncoder,
        viewProjectionMatrix: simd_float4x4,
        camera: CameraComponent,
        cameraWorldMatrix: simd_float4x4,
        aspectRatio: Float,
        device: MTLDevice
    ) {
        var lineVerts: [Vertex] = []
        var triVerts: [Vertex] = []

        let right   = normalize(SIMD3<Float>(cameraWorldMatrix.columns.0.x, cameraWorldMatrix.columns.0.y, cameraWorldMatrix.columns.0.z))
        let up      = normalize(SIMD3<Float>(cameraWorldMatrix.columns.1.x, cameraWorldMatrix.columns.1.y, cameraWorldMatrix.columns.1.z))
        let forward = -normalize(SIMD3<Float>(cameraWorldMatrix.columns.2.x, cameraWorldMatrix.columns.2.y, cameraWorldMatrix.columns.2.z))
        let pos     = SIMD3<Float>(cameraWorldMatrix.columns.3.x, cameraWorldMatrix.columns.3.y, cameraWorldMatrix.columns.3.z)

        let nearZ = camera.nearZ
        let displayFarZ = min(camera.farZ, nearZ + 8.0)

        let nearHH: Float, nearHW: Float, farHH: Float, farHW: Float
        switch camera.projection {
        case .perspective:
            nearHH = nearZ * tan(camera.fov * 0.5)
            nearHW = nearHH * aspectRatio
            farHH  = displayFarZ * tan(camera.fov * 0.5)
            farHW  = farHH * aspectRatio
        case .orthographic:
            nearHH = camera.orthoSize
            nearHW = nearHH * aspectRatio
            farHH  = nearHH
            farHW  = nearHW
        }

        let nc = pos + forward * nearZ
        let fc = pos + forward * displayFarZ

        let ntl = nc + up * nearHH - right * nearHW
        let ntr = nc + up * nearHH + right * nearHW
        let nbr = nc - up * nearHH + right * nearHW
        let nbl = nc - up * nearHH - right * nearHW

        let ftl = fc + up * farHH - right * farHW
        let ftr = fc + up * farHH + right * farHW
        let fbr = fc - up * farHH + right * farHW
        let fbl = fc - up * farHH - right * farHW

        let c = Self.cameraColor

        // Near plane
        addLine(&lineVerts, ntl, ntr, c)
        addLine(&lineVerts, ntr, nbr, c)
        addLine(&lineVerts, nbr, nbl, c)
        addLine(&lineVerts, nbl, ntl, c)

        // Far plane
        addLine(&lineVerts, ftl, ftr, c)
        addLine(&lineVerts, ftr, fbr, c)
        addLine(&lineVerts, fbr, fbl, c)
        addLine(&lineVerts, fbl, ftl, c)

        // Connecting edges
        addLine(&lineVerts, ntl, ftl, c)
        addLine(&lineVerts, ntr, ftr, c)
        addLine(&lineVerts, nbr, fbr, c)
        addLine(&lineVerts, nbl, fbl, c)

        // Lines from camera origin to near plane corners
        let dimC = Self.cameraDimColor
        addLine(&lineVerts, pos, ntl, dimC)
        addLine(&lineVerts, pos, ntr, dimC)
        addLine(&lineVerts, pos, nbr, dimC)
        addLine(&lineVerts, pos, nbl, dimC)

        // Semi-transparent near plane fill
        addTri(&triVerts, ntl, ntr, nbr, Self.cameraFillColor)
        addTri(&triVerts, ntl, nbr, nbl, Self.cameraFillColor)

        // "Up" indicator triangle on top of near plane
        let upSize = nearHW * 0.3
        let upBase = nc + up * nearHH
        let upTip = upBase + up * upSize
        let upL = upBase - right * upSize * 0.5
        let upR = upBase + right * upSize * 0.5
        addLine(&lineVerts, upL, upR, c)
        addLine(&lineVerts, upL, upTip, c)
        addLine(&lineVerts, upR, upTip, c)

        flush(encoder: encoder, vpMatrix: viewProjectionMatrix, lines: lineVerts, tris: triVerts, device: device)
    }

    // MARK: - Directional Light

    func drawDirectionalLight(
        encoder: MTLRenderCommandEncoder,
        viewProjectionMatrix: simd_float4x4,
        light: LightComponent,
        worldMatrix: simd_float4x4,
        device: MTLDevice
    ) {
        var lineVerts: [Vertex] = []
        let color = SIMD4<Float>(light.color.x, light.color.y, light.color.z, 0.7)

        let right   = normalize(SIMD3<Float>(worldMatrix.columns.0.x, worldMatrix.columns.0.y, worldMatrix.columns.0.z))
        let up      = normalize(SIMD3<Float>(worldMatrix.columns.1.x, worldMatrix.columns.1.y, worldMatrix.columns.1.z))
        let forward = -normalize(SIMD3<Float>(worldMatrix.columns.2.x, worldMatrix.columns.2.y, worldMatrix.columns.2.z))
        let pos     = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)

        let rayLen: Float = 2.5
        let spread: Float = 0.8
        let headLen: Float = 0.2
        let headW: Float = 0.08

        // Source disc
        addCircle(&lineVerts, center: pos, normal: forward, radius: spread, segments: 24, color: color)

        // Parallel rays with arrowheads
        let offsets: [SIMD2<Float>] = [
            .zero,
            SIMD2<Float>( 1,  0), SIMD2<Float>(-1,  0),
            SIMD2<Float>( 0,  1), SIMD2<Float>( 0, -1),
        ]

        for off in offsets {
            let base = pos + right * off.x * spread + up * off.y * spread
            let tip = base + forward * rayLen

            addLine(&lineVerts, base, tip, color)

            addLine(&lineVerts, tip, tip - forward * headLen + right * headW, color)
            addLine(&lineVerts, tip, tip - forward * headLen - right * headW, color)
            addLine(&lineVerts, tip, tip - forward * headLen + up * headW, color)
            addLine(&lineVerts, tip, tip - forward * headLen - up * headW, color)
        }

        flush(encoder: encoder, vpMatrix: viewProjectionMatrix, lines: lineVerts, tris: [], device: device)
    }

    // MARK: - Point Light

    func drawPointLight(
        encoder: MTLRenderCommandEncoder,
        viewProjectionMatrix: simd_float4x4,
        light: LightComponent,
        worldMatrix: simd_float4x4,
        device: MTLDevice
    ) {
        var lineVerts: [Vertex] = []
        let color = SIMD4<Float>(light.color.x, light.color.y, light.color.z, 0.45)
        let pos = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)

        // Three orthogonal circles showing range sphere
        addCircle(&lineVerts, center: pos, normal: SIMD3<Float>(1, 0, 0), radius: light.range, segments: 48, color: color)
        addCircle(&lineVerts, center: pos, normal: SIMD3<Float>(0, 1, 0), radius: light.range, segments: 48, color: color)
        addCircle(&lineVerts, center: pos, normal: SIMD3<Float>(0, 0, 1), radius: light.range, segments: 48, color: color)

        // Center cross
        let s: Float = 0.25
        let bright = SIMD4<Float>(light.color.x, light.color.y, light.color.z, 0.8)
        addLine(&lineVerts, pos - SIMD3<Float>(s, 0, 0), pos + SIMD3<Float>(s, 0, 0), bright)
        addLine(&lineVerts, pos - SIMD3<Float>(0, s, 0), pos + SIMD3<Float>(0, s, 0), bright)
        addLine(&lineVerts, pos - SIMD3<Float>(0, 0, s), pos + SIMD3<Float>(0, 0, s), bright)

        flush(encoder: encoder, vpMatrix: viewProjectionMatrix, lines: lineVerts, tris: [], device: device)
    }

    // MARK: - Spot Light

    func drawSpotLight(
        encoder: MTLRenderCommandEncoder,
        viewProjectionMatrix: simd_float4x4,
        light: LightComponent,
        worldMatrix: simd_float4x4,
        device: MTLDevice
    ) {
        var lineVerts: [Vertex] = []
        let color = SIMD4<Float>(light.color.x, light.color.y, light.color.z, 0.6)
        let innerColor = SIMD4<Float>(light.color.x, light.color.y, light.color.z, 0.3)

        let forward = -normalize(SIMD3<Float>(worldMatrix.columns.2.x, worldMatrix.columns.2.y, worldMatrix.columns.2.z))
        let pos     = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)

        let range = light.range
        let outerR = range * tan(light.outerConeAngle)
        let innerR = range * tan(light.innerConeAngle)
        let endCenter = pos + forward * range

        // Outer cone circle at range
        addCircle(&lineVerts, center: endCenter, normal: forward, radius: outerR, segments: 32, color: color)

        // Inner cone circle at range
        addCircle(&lineVerts, center: endCenter, normal: forward, radius: innerR, segments: 32, color: innerColor)

        // Cone edge lines (8 directions for smooth appearance)
        let coneSegments = 8
        var tangent = cross(forward, SIMD3<Float>(0, 1, 0))
        if length(tangent) < 0.001 { tangent = cross(forward, SIMD3<Float>(1, 0, 0)) }
        tangent = normalize(tangent)
        let bitangent = normalize(cross(forward, tangent))

        for i in 0..<coneSegments {
            let angle = Float(i) / Float(coneSegments) * Float.pi * 2
            let dir = tangent * cos(angle) + bitangent * sin(angle)
            let edgePt = endCenter + dir * outerR
            addLine(&lineVerts, pos, edgePt, color)
        }

        // Center axis
        addLine(&lineVerts, pos, endCenter, innerColor)

        flush(encoder: encoder, vpMatrix: viewProjectionMatrix, lines: lineVerts, tris: [], device: device)
    }

    // MARK: - Dispatch

    func drawForEntity(
        encoder: MTLRenderCommandEncoder,
        viewProjectionMatrix: simd_float4x4,
        camera: CameraComponent?,
        light: LightComponent?,
        entityWorldMatrix: simd_float4x4,
        aspectRatio: Float,
        device: MTLDevice
    ) {
        if let cam = camera {
            drawCameraFrustum(
                encoder: encoder,
                viewProjectionMatrix: viewProjectionMatrix,
                camera: cam,
                cameraWorldMatrix: entityWorldMatrix,
                aspectRatio: aspectRatio,
                device: device
            )
        }

        if let light = light {
            switch light.type {
            case .directional:
                drawDirectionalLight(encoder: encoder, viewProjectionMatrix: viewProjectionMatrix,
                                     light: light, worldMatrix: entityWorldMatrix, device: device)
            case .point:
                drawPointLight(encoder: encoder, viewProjectionMatrix: viewProjectionMatrix,
                               light: light, worldMatrix: entityWorldMatrix, device: device)
            case .spot:
                drawSpotLight(encoder: encoder, viewProjectionMatrix: viewProjectionMatrix,
                              light: light, worldMatrix: entityWorldMatrix, device: device)
            }
        }
    }

    // MARK: - Primitive Helpers

    private func addLine(_ verts: inout [Vertex], _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ color: SIMD4<Float>) {
        verts.append(Vertex(position: a, color: color))
        verts.append(Vertex(position: b, color: color))
    }

    private func addTri(_ verts: inout [Vertex], _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ color: SIMD4<Float>) {
        verts.append(Vertex(position: a, color: color))
        verts.append(Vertex(position: b, color: color))
        verts.append(Vertex(position: c, color: color))
    }

    private func addCircle(_ verts: inout [Vertex], center: SIMD3<Float>, normal: SIMD3<Float>,
                            radius: Float, segments: Int, color: SIMD4<Float>) {
        var tangent = cross(normal, SIMD3<Float>(0, 1, 0))
        if length(tangent) < 0.001 { tangent = cross(normal, SIMD3<Float>(1, 0, 0)) }
        tangent = normalize(tangent)
        let bitangent = normalize(cross(normal, tangent))

        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * .pi * 2
            let a1 = Float(i + 1) / Float(segments) * .pi * 2
            let p0 = center + (tangent * cos(a0) + bitangent * sin(a0)) * radius
            let p1 = center + (tangent * cos(a1) + bitangent * sin(a1)) * radius
            addLine(&verts, p0, p1, color)
        }
    }

    // MARK: - GPU Submission

    private func flush(encoder: MTLRenderCommandEncoder, vpMatrix: simd_float4x4,
                       lines: [Vertex], tris: [Vertex], device: MTLDevice) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)

        var uniforms = Uniforms(viewProjectionMatrix: vpMatrix)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        if !lines.isEmpty {
            submitVertices(lines, as: .line, encoder: encoder, device: device)
        }
        if !tris.isEmpty {
            submitVertices(tris, as: .triangle, encoder: encoder, device: device)
        }
    }

    private func submitVertices(_ vertices: [Vertex], as primitiveType: MTLPrimitiveType,
                                encoder: MTLRenderCommandEncoder, device: MTLDevice) {
        var verts = vertices
        let byteLen = MemoryLayout<Vertex>.stride * verts.count
        if byteLen <= 4096 {
            encoder.setVertexBytes(&verts, length: byteLen, index: 0)
        } else {
            guard let buf = device.makeBuffer(bytes: &verts, length: byteLen, options: .storageModeShared) else { return }
            encoder.setVertexBuffer(buf, offset: 0, index: 0)
        }
        encoder.drawPrimitives(type: primitiveType, vertexStart: 0, vertexCount: verts.count)
    }
}
