import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer
import ModelIO

/// Imports USD/USDZ/OBJ files into the ECS world as entities with components.
///
/// Uses Apple's ModelIO framework for USD parsing. Currently supports:
/// - Mesh geometry import
/// - Basic material property extraction
/// - Scene hierarchy reconstruction
public final class USDImporter {
    
    public init() {}
    
    /// Imports a 3D asset file into the given world.
    ///
    /// Creates entities with TransformComponent, MeshComponent, MaterialComponent,
    /// and NameComponent for each mesh object found in the file.
    ///
    /// - Parameters:
    ///   - url: The file URL of the USD/USDZ/OBJ asset.
    ///   - world: The ECS world to populate.
    ///   - sceneGraph: The scene graph for hierarchy management.
    /// - Returns: The root entity containing all imported objects.
    @discardableResult
    public func importAsset(
        from url: URL,
        into world: World,
        sceneGraph: SceneGraph
    ) -> Entity? {
        let vertexDescriptor = MeshPool.standardVertexDescriptor
        let asset = MDLAsset(
            url: url,
            vertexDescriptor: vertexDescriptor,
            bufferAllocator: nil
        )
        
        guard asset.count > 0 else { return nil }
        
        let fileName = url.deletingPathExtension().lastPathComponent
        let rootEntity = sceneGraph.createEntity(name: fileName)
        
        let meshes = asset.childObjects(of: MDLMesh.self)
        
        for (index, obj) in meshes.enumerated() {
            guard let mdlMesh = obj as? MDLMesh else { continue }
            
            let meshName = mdlMesh.name.isEmpty ? "\(fileName)_mesh_\(index)" : mdlMesh.name
            let meshEntity = sceneGraph.createEntity(name: meshName, parent: rootEntity)
            
            // Extract transform from MDLTransformComponent if available
            if let mdlTransform = mdlMesh.transform {
                let localMatrix = mdlTransform.matrix
                var tc = world.getComponent(TransformComponent.self, from: meshEntity)!
                tc.transform.position = SIMD3<Float>(
                    Float(localMatrix.columns.3.x),
                    Float(localMatrix.columns.3.y),
                    Float(localMatrix.columns.3.z)
                )
                world.addComponent(tc, to: meshEntity)
            }
            
            world.addComponent(
                MeshComponent(meshType: .custom(url)),
                to: meshEntity
            )
            
            // Extract basic material properties
            var material = MCMaterial(name: meshName + "_material")
            if let mdlSubmesh = mdlMesh.submeshes?.firstObject as? MDLSubmesh,
               let mdlMaterial = mdlSubmesh.material {
                material.name = mdlMaterial.name
                
                if let baseColor = mdlMaterial.property(with: .baseColor) {
                    if baseColor.type == .float3 {
                        let c = baseColor.float3Value
                        material.fragmentShaderSource = """
                        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
                            float3 N = normalize(in.normalOS);
                            float3 L = normalize(float3(1.0, 1.0, 1.0));
                            float diffuse = max(0.1, dot(N, L));
                            float3 baseColor = float3(\(c.x), \(c.y), \(c.z));
                            return float4(baseColor * diffuse, 1.0);
                        }
                        """
                    }
                }
            }
            
            if material.fragmentShaderSource.isEmpty {
                material.fragmentShaderSource = ShaderSnippets.defaultFragment
            }
            
            world.addComponent(MaterialComponent(material: material), to: meshEntity)
        }
        
        return rootEntity
    }
}
