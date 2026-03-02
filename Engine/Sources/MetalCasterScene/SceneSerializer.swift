import Foundation
import MetalCasterCore

/// Serializes/deserializes a complete scene (entities + components) to/from JSON.
///
/// The scene format stores entities as an array of dictionaries,
/// each containing the entity ID and all attached components.
public final class SceneSerializer {
    
    /// Scene file format version.
    public static let formatVersion = 1
    
    public init() {}
    
    /// Serializes the scene to JSON data.
    public func serialize(sceneGraph: SceneGraph, world: World) throws -> Data {
        var sceneData = SceneData(version: Self.formatVersion)
        
        for (entity, tc) in world.query(TransformComponent.self) {
            var entityData = EntityData(id: entity.id)
            entityData.transform = tc
            
            if let name = world.getComponent(NameComponent.self, from: entity) {
                entityData.name = name
            }
            if let mesh = world.getComponent(MeshComponent.self, from: entity) {
                entityData.mesh = mesh
            }
            if let material = world.getComponent(MaterialComponent.self, from: entity) {
                entityData.material = material
            }
            if let camera = world.getComponent(CameraComponent.self, from: entity) {
                entityData.camera = camera
            }
            if let light = world.getComponent(LightComponent.self, from: entity) {
                entityData.light = light
            }
            if let manager = world.getComponent(ManagerComponent.self, from: entity) {
                entityData.manager = manager
            }
            
            sceneData.entities.append(entityData)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sceneData)
    }
    
    /// Deserializes a scene from JSON data into the world.
    public func deserialize(data: Data, into world: World, sceneGraph: SceneGraph) throws {
        let decoder = JSONDecoder()
        let sceneData = try decoder.decode(SceneData.self, from: data)
        
        world.clear()
        
        // First pass: create all entities
        var entityMap: [UInt64: Entity] = [:]
        for ed in sceneData.entities {
            let entity = world.createEntity()
            entityMap[ed.id] = entity
        }
        
        // Second pass: add components
        for ed in sceneData.entities {
            guard let entity = entityMap[ed.id] else { continue }
            
            if var tc = ed.transform {
                // Remap parent entity ID
                if let parentID = tc.parent?.id, let newParent = entityMap[parentID] {
                    tc.parent = newParent
                } else {
                    tc.parent = nil
                }
                world.addComponent(tc, to: entity)
            }
            if let name = ed.name {
                world.addComponent(name, to: entity)
            }
            if let mesh = ed.mesh {
                world.addComponent(mesh, to: entity)
            }
            if let material = ed.material {
                world.addComponent(material, to: entity)
            }
            if let camera = ed.camera {
                world.addComponent(camera, to: entity)
            }
            if let light = ed.light {
                world.addComponent(light, to: entity)
            }
            if let manager = ed.manager {
                world.addComponent(manager, to: entity)
            }
        }
    }
}

// MARK: - Serialization Data Structures

struct SceneData: Codable {
    var version: Int
    var entities: [EntityData] = []
}

struct EntityData: Codable {
    var id: UInt64
    var transform: TransformComponent?
    var name: NameComponent?
    var mesh: MeshComponent?
    var material: MaterialComponent?
    var camera: CameraComponent?
    var light: LightComponent?
    var manager: ManagerComponent?
}
