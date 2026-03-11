import Metal
import MetalKit
import simd
import MetalCasterRenderer

/// Renders an infinite ground-plane grid on the XZ plane (Y = 0)
/// via a fullscreen triangle with procedural lines and distance fade.
final class GridRenderer {

    private let pipeline: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    private struct GridUniforms {
        var viewProjectionMatrix: simd_float4x4
        var invViewProjectionMatrix: simd_float4x4
        var cameraPosition: SIMD4<Float>
    }

    init?(device: MTLDevice) {
        let shaderSource = ShaderSnippets.gridVertexShader
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "grid_vertex"),
              let fragFunc = library.makeFunction(name: "grid_fragment") else {
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
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = false
        guard let dss = device.makeDepthStencilState(descriptor: depthDesc) else {
            return nil
        }
        depthStencilState = dss
    }

    func draw(encoder: MTLRenderCommandEncoder,
              viewProjectionMatrix: simd_float4x4,
              cameraPosition: SIMD3<Float>) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)

        var uniforms = GridUniforms(
            viewProjectionMatrix: viewProjectionMatrix,
            invViewProjectionMatrix: viewProjectionMatrix.inverse,
            cameraPosition: SIMD4<Float>(cameraPosition, 0)
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GridUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GridUniforms>.stride, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
