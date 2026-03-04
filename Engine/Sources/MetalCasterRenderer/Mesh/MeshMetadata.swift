import Metal
import MetalKit
import ModelIO
import simd

/// Extracted metadata for a loaded mesh, useful for culling, LOD selection, and diagnostics.
public struct MeshMetadata: Sendable {
    public let vertexCount: Int
    public let indexCount: Int
    public let triangleCount: Int
    public let submeshCount: Int
    public let boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    public let boundingSphereRadius: Float
    public let vertexBufferBytes: Int

    public init(
        vertexCount: Int,
        indexCount: Int,
        triangleCount: Int,
        submeshCount: Int,
        boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>),
        vertexBufferBytes: Int
    ) {
        self.vertexCount = vertexCount
        self.indexCount = indexCount
        self.triangleCount = triangleCount
        self.submeshCount = submeshCount
        self.boundingBox = boundingBox
        self.vertexBufferBytes = vertexBufferBytes

        let center = (boundingBox.min + boundingBox.max) * 0.5
        let halfExtent = (boundingBox.max - boundingBox.min) * 0.5
        self.boundingSphereRadius = length(halfExtent)
        _ = center
    }

    /// Extracts metadata from an MTKMesh.
    public static func extract(from mesh: MTKMesh) -> MeshMetadata {
        let vCount = mesh.vertexCount
        let iCount = mesh.submeshes.reduce(0) { $0 + $1.indexCount }
        let triCount = mesh.submeshes.reduce(0) { $0 + $1.indexCount / 3 }
        let bufferBytes = mesh.vertexBuffers.reduce(0) { $0 + $1.buffer.length }

        return MeshMetadata(
            vertexCount: vCount,
            indexCount: iCount,
            triangleCount: triCount,
            submeshCount: mesh.submeshes.count,
            boundingBox: (min: .zero, max: .zero),
            vertexBufferBytes: bufferBytes
        )
    }

    /// Extracts metadata from an MDLMesh (with accurate bounding box).
    public static func extract(from mesh: MDLMesh) -> MeshMetadata {
        let bb = mesh.boundingBox
        let minBB = SIMD3<Float>(bb.minBounds.x, bb.minBounds.y, bb.minBounds.z)
        let maxBB = SIMD3<Float>(bb.maxBounds.x, bb.maxBounds.y, bb.maxBounds.z)

        var indexTotal = 0
        for sub in mesh.submeshes as? [MDLSubmesh] ?? [] {
            indexTotal += sub.indexCount
        }

        return MeshMetadata(
            vertexCount: mesh.vertexCount,
            indexCount: indexTotal,
            triangleCount: indexTotal / 3,
            submeshCount: mesh.submeshes?.count ?? 0,
            boundingBox: (min: minBB, max: maxBB),
            vertexBufferBytes: 0
        )
    }
}

/// Optimizes mesh data using ModelIO's built-in capabilities.
public struct MeshOptimizer {

    /// Generates normals for an MDLMesh if not already present.
    public static func ensureNormals(_ mesh: MDLMesh) {
        mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
    }

    /// Generates tangent basis for normal mapping.
    public static func generateTangents(_ mesh: MDLMesh) {
        mesh.addTangentBasis(
            forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
            normalAttributeNamed: MDLVertexAttributeNormal,
            tangentAttributeNamed: MDLVertexAttributeTangent
        )
    }

    /// Makes vertices unique, enabling per-face normals and further optimization.
    public static func makeVerticesUnique(_ mesh: MDLMesh) {
        try? mesh.makeVerticesUniqueAndReturnError()
    }
}
