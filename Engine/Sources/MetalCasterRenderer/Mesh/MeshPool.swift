import Metal
import MetalKit
import ModelIO

/// Manages shared mesh resources. Provides loading, caching, and
/// generation of 3D meshes from ModelIO.
public final class MeshPool {

    private let device: MTLDevice
    private let allocator: MTKMeshBufferAllocator
    private var cache: [String: MTKMesh] = [:]
    private var metadataCache: [String: MeshMetadata] = [:]
    private var extendedCache: [String: MTKMesh] = [:]

    /// Closure that resolves a mesh asset UUID to its file URL.
    /// Set by the editor to provide AssetDatabase resolution.
    public var assetResolver: ((UUID) -> URL?)?

    /// The standard vertex descriptor used by the main editor renderer.
    /// Layout: position(float3) + normal(float3) + texCoord(float2), stride = 32
    public static let standardVertexDescriptor: MDLVertexDescriptor = {
        let desc = MDLVertexDescriptor()
        desc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3, offset: 0, bufferIndex: 0
        )
        desc.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3, offset: MemoryLayout<Float>.stride * 3, bufferIndex: 0
        )
        desc.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2, offset: MemoryLayout<Float>.stride * 6, bufferIndex: 0
        )
        desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 8)
        return desc
    }()

    /// Extended vertex descriptor with tangent space data for Shader Canvas.
    /// Layout: position(float3) + normal(float3) + texCoord(float2) + tangent(float3) + bitangent(float3)
    /// stride = 56 bytes
    public static let extendedVertexDescriptor: MDLVertexDescriptor = {
        let s = MemoryLayout<Float>.stride
        let desc = MDLVertexDescriptor()
        desc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0
        )
        desc.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal, format: .float3, offset: s * 3, bufferIndex: 0
        )
        desc.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: s * 6, bufferIndex: 0
        )
        desc.attributes[3] = MDLVertexAttribute(
            name: MDLVertexAttributeTangent, format: .float3, offset: s * 8, bufferIndex: 0
        )
        desc.attributes[4] = MDLVertexAttribute(
            name: MDLVertexAttributeBitangent, format: .float3, offset: s * 11, bufferIndex: 0
        )
        desc.layouts[0] = MDLVertexBufferLayout(stride: s * 14)
        return desc
    }()

    /// Converts the standard vertex descriptor to a Metal vertex descriptor.
    public static var metalVertexDescriptor: MTLVertexDescriptor? {
        MTKMetalVertexDescriptorFromModelIO(standardVertexDescriptor)
    }

    /// Converts the extended vertex descriptor to a Metal vertex descriptor.
    public static var extendedMetalVertexDescriptor: MTLVertexDescriptor? {
        MTKMetalVertexDescriptorFromModelIO(extendedVertexDescriptor)
    }

    public init(device: MTLDevice) {
        self.device = device
        self.allocator = MTKMeshBufferAllocator(device: device)
    }

    /// Gets or creates a mesh for the given type (standard layout).
    public func mesh(for type: MeshType) -> MTKMesh? {
        let key = cacheKey(for: type)
        if let cached = cache[key] { return cached }
        let mesh = loadMesh(type: type, extended: false)
        if let mesh { cache[key] = mesh; metadataCache[key] = MeshMetadata.extract(from: mesh) }
        return mesh
    }

    /// Gets or creates a mesh with the extended layout (includes tangent/bitangent).
    /// Used by the Shader Canvas for TBN-space workflows.
    public func meshExtended(for type: MeshType) -> MTKMesh? {
        let key = cacheKey(for: type)
        if let cached = extendedCache[key] { return cached }
        let mesh = loadMesh(type: type, extended: true)
        if let mesh { extendedCache[key] = mesh }
        return mesh
    }

    /// Returns metadata for a cached mesh, or nil if not yet loaded.
    public func metadata(for type: MeshType) -> MeshMetadata? {
        metadataCache[cacheKey(for: type)]
    }

    /// Invalidates the cache for a specific mesh type.
    public func invalidate(_ type: MeshType) {
        let key = cacheKey(for: type)
        cache.removeValue(forKey: key)
        metadataCache.removeValue(forKey: key)
        extendedCache.removeValue(forKey: key)
    }

    /// Invalidates all cached meshes.
    public func invalidateAll() {
        cache.removeAll()
        metadataCache.removeAll()
        extendedCache.removeAll()
    }

    // MARK: - Private

    private func loadMesh(type: MeshType, extended: Bool) -> MTKMesh? {
        let vertexDescriptor = extended ? Self.extendedVertexDescriptor : Self.standardVertexDescriptor
        var mdlMesh: MDLMesh?

        switch type {
        case .sphere:
            mdlMesh = MDLMesh(
                sphereWithExtent: [2, 2, 2],
                segments: [60, 60],
                inwardNormals: false,
                geometryType: .triangles,
                allocator: allocator
            )
        case .cube:
            mdlMesh = MDLMesh(
                boxWithExtent: [2, 2, 2],
                segments: [1, 1, 1],
                inwardNormals: false,
                geometryType: .triangles,
                allocator: allocator
            )
        case .plane:
            mdlMesh = MDLMesh(
                planeWithExtent: [2, 0, 2],
                segments: [1, 1],
                geometryType: .triangles,
                allocator: allocator
            )
        case .cylinder:
            mdlMesh = MDLMesh(
                cylinderWithExtent: [2, 2, 2],
                segments: [60, 1],
                inwardNormals: false,
                topCap: true,
                bottomCap: true,
                geometryType: .triangles,
                allocator: allocator
            )
        case .cone:
            mdlMesh = MDLMesh(
                coneWithExtent: [2, 2, 2],
                segments: [60, 1],
                inwardNormals: false,
                cap: true,
                geometryType: .triangles,
                allocator: allocator
            )
        case .capsule:
            mdlMesh = MDLMesh(
                capsuleWithExtent: [1.5, 3, 1.5],
                cylinderSegments: [60, 12],
                hemisphereSegments: 20,
                inwardNormals: false,
                geometryType: .triangles,
                allocator: allocator
            )
        case .custom(let url):
            let asset = MDLAsset(
                url: url,
                vertexDescriptor: vertexDescriptor,
                bufferAllocator: allocator
            )
            if let first = asset.childObjects(of: MDLMesh.self).first as? MDLMesh {
                mdlMesh = first
            } else {
                return mesh(for: .sphere)
            }
        case .asset(let guid):
            if let resolver = assetResolver, let url = resolver(guid) {
                let asset = MDLAsset(
                    url: url,
                    vertexDescriptor: vertexDescriptor,
                    bufferAllocator: allocator
                )
                if let first = asset.childObjects(of: MDLMesh.self).first as? MDLMesh {
                    mdlMesh = first
                } else {
                    return mesh(for: .sphere)
                }
            } else {
                return mesh(for: .sphere)
            }
        }

        guard let mdl = mdlMesh else { return nil }

        if extended {
            mdl.addTangentBasis(
                forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                tangentAttributeNamed: MDLVertexAttributeTangent,
                bitangentAttributeNamed: MDLVertexAttributeBitangent
            )
        }

        mdl.vertexDescriptor = vertexDescriptor
        return try? MTKMesh(mesh: mdl, device: device)
    }

    /// Resolves a `.asset(UUID)` mesh type to `.custom(URL)` using an external resolver.
    /// Pass a closure that maps a UUID to a file URL (typically from AssetDatabase).
    public func resolveAssetMeshType(_ type: MeshType, resolver: (UUID) -> URL?) -> MeshType {
        if case .asset(let guid) = type, let url = resolver(guid) {
            return .custom(url)
        }
        return type
    }

    private func cacheKey(for type: MeshType) -> String {
        switch type {
        case .sphere: return "builtin:sphere"
        case .cube: return "builtin:cube"
        case .plane: return "builtin:plane"
        case .cylinder: return "builtin:cylinder"
        case .cone: return "builtin:cone"
        case .capsule: return "builtin:capsule"
        case .custom(let url): return "custom:\(url.path)"
        case .asset(let guid): return "asset:\(guid.uuidString)"
        }
    }
}
