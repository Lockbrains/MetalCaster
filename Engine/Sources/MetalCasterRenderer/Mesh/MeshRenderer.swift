import Metal
import MetalKit

/// Utility for encoding mesh draw commands into a render command encoder.
public struct MeshRenderer {

    /// Encodes draw commands for a single MTKMesh.
    ///
    /// - Parameters:
    ///   - mesh: The mesh to draw.
    ///   - encoder: The render command encoder to encode into.
    public static func draw(mesh: MTKMesh, with encoder: MTLRenderCommandEncoder) {
        for (index, vertexBuffer) in mesh.vertexBuffers.enumerated() {
            encoder.setVertexBuffer(
                vertexBuffer.buffer,
                offset: vertexBuffer.offset,
                index: index
            )
        }

        for submesh in mesh.submeshes {
            encoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }
    }

    /// Draws a fullscreen triangle (3 vertices, no vertex buffer needed).
    /// The vertex shader generates positions from vertex_id.
    public static func drawFullscreenTriangle(with encoder: MTLRenderCommandEncoder) {
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
