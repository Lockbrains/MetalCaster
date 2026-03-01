import Metal
import MetalKit
import simd
import MetalCasterRenderer

/// Renders a ground-plane grid on the XZ plane (Y = 0).
/// Major lines every 5 units, minor lines every 1 unit.
final class GridRenderer {

    private let pipeline: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let colorBuffer: MTLBuffer
    private let vertexCount: Int
    private let depthStencilState: MTLDepthStencilState

    private struct GridUniforms {
        var viewProjectionMatrix: simd_float4x4
    }

    init?(device: MTLDevice) {
        let halfExtent: Int = 20
        let step: Float = 1.0

        var positions: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []

        let majorColor = SIMD4<Float>(1, 1, 1, 0.25)
        let minorColor = SIMD4<Float>(1, 1, 1, 0.08)
        let axisXColor = SIMD4<Float>(0.85, 0.2, 0.2, 0.6)
        let axisZColor = SIMD4<Float>(0.2, 0.2, 0.85, 0.6)

        for i in -halfExtent...halfExtent {
            let f = Float(i) * step
            let color: SIMD4<Float>
            if i == 0 {
                // X axis line (red tinted)
                positions.append(SIMD3<Float>(Float(-halfExtent) * step, 0, f))
                positions.append(SIMD3<Float>(Float(halfExtent) * step, 0, f))
                colors.append(axisXColor)
                // Z axis line (blue tinted)
                positions.append(SIMD3<Float>(f, 0, Float(-halfExtent) * step))
                positions.append(SIMD3<Float>(f, 0, Float(halfExtent) * step))
                colors.append(axisZColor)
                continue
            }

            color = (i % 5 == 0) ? majorColor : minorColor

            // Line parallel to X axis
            positions.append(SIMD3<Float>(Float(-halfExtent) * step, 0, f))
            positions.append(SIMD3<Float>(Float(halfExtent) * step, 0, f))
            colors.append(color)

            // Line parallel to Z axis
            positions.append(SIMD3<Float>(f, 0, Float(-halfExtent) * step))
            positions.append(SIMD3<Float>(f, 0, Float(halfExtent) * step))
            colors.append(color)
        }

        vertexCount = positions.count
        guard vertexCount > 0 else { return nil }

        guard let vBuf = device.makeBuffer(
            bytes: positions,
            length: MemoryLayout<SIMD3<Float>>.stride * vertexCount,
            options: .storageModeShared
        ) else { return nil }
        vertexBuffer = vBuf

        guard let cBuf = device.makeBuffer(
            bytes: colors,
            length: MemoryLayout<SIMD4<Float>>.stride * colors.count,
            options: .storageModeShared
        ) else { return nil }
        colorBuffer = cBuf

        let shaderSource = ShaderSnippets.gridVertexShader
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "grid_vertex"),
              let fragFunc = library.makeFunction(name: "grid_fragment") else {
            return nil
        }

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.vertexFunction = vertexFunc
        pipeDesc.fragmentFunction = fragFunc
        pipeDesc.vertexDescriptor = vd
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
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = false
        guard let dss = device.makeDepthStencilState(descriptor: depthDesc) else {
            return nil
        }
        depthStencilState = dss
    }

    func draw(encoder: MTLRenderCommandEncoder, viewProjectionMatrix: simd_float4x4) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var uniforms = GridUniforms(viewProjectionMatrix: viewProjectionMatrix)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GridUniforms>.stride, index: 1)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 2)

        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
    }
}
