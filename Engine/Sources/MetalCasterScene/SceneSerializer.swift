import Foundation
import MetalCasterCore
import MetalCasterAudio

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
            if let skybox = world.getComponent(SkyboxComponent.self, from: entity) {
                entityData.skybox = skybox
            }
            if let ppVolume = world.getComponent(PostProcessVolumeComponent.self, from: entity) {
                entityData.postProcessVolume = ppVolume
            }
            if let scriptRef = world.getComponent(GameplayScriptRef.self, from: entity) {
                entityData.gameplayScriptRef = scriptRef
            }
            if let audioSource = world.getComponent(AudioSourceComponent.self, from: entity) {
                var saved = audioSource
                saved.isPlaying = false
                saved._playerID = nil
                entityData.audioSource = saved
            }
            if let audioListener = world.getComponent(AudioListenerComponent.self, from: entity) {
                entityData.audioListener = audioListener
            }
            if let lod = world.getComponent(LODComponent.self, from: entity) {
                entityData.lod = lod
            }
            if let physicsBody = world.getComponent(PhysicsBodyComponent.self, from: entity) {
                entityData.physicsBody = physicsBody
            }
            if let collider = world.getComponent(ColliderComponent.self, from: entity) {
                entityData.collider = collider
            }
            if let uiCanvas = world.getComponent(UICanvasComponent.self, from: entity) {
                entityData.uiCanvas = uiCanvas
            }
            if let uiElement = world.getComponent(UIElementComponent.self, from: entity) {
                entityData.uiElement = uiElement
            }
            if let uiLabel = world.getComponent(UILabelComponent.self, from: entity) {
                entityData.uiLabel = uiLabel
            }
            if let uiImage = world.getComponent(UIImageComponent.self, from: entity) {
                entityData.uiImage = uiImage
            }
            if let uiPanel = world.getComponent(UIPanelComponent.self, from: entity) {
                entityData.uiPanel = uiPanel
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
            if let skybox = ed.skybox {
                world.addComponent(skybox, to: entity)
            }
            if let ppVolume = ed.postProcessVolume {
                world.addComponent(ppVolume, to: entity)
            }
            if let scriptRef = ed.gameplayScriptRef {
                world.addComponent(scriptRef, to: entity)
            }
            if let audioSource = ed.audioSource {
                world.addComponent(audioSource, to: entity)
            }
            if let audioListener = ed.audioListener {
                world.addComponent(audioListener, to: entity)
            }
            if let lod = ed.lod {
                world.addComponent(lod, to: entity)
            }
            if let physicsBody = ed.physicsBody {
                world.addComponent(physicsBody, to: entity)
            }
            if let collider = ed.collider {
                world.addComponent(collider, to: entity)
            }
            if let uiCanvas = ed.uiCanvas {
                world.addComponent(uiCanvas, to: entity)
            }
            if let uiElement = ed.uiElement {
                world.addComponent(uiElement, to: entity)
            }
            if let uiLabel = ed.uiLabel {
                world.addComponent(uiLabel, to: entity)
            }
            if let uiImage = ed.uiImage {
                world.addComponent(uiImage, to: entity)
            }
            if let uiPanel = ed.uiPanel {
                world.addComponent(uiPanel, to: entity)
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
    var skybox: SkyboxComponent?
    var postProcessVolume: PostProcessVolumeComponent?
    var gameplayScriptRef: GameplayScriptRef?
    var audioSource: AudioSourceComponent?
    var audioListener: AudioListenerComponent?
    var lod: LODComponent?
    var physicsBody: PhysicsBodyComponent?
    var collider: ColliderComponent?
    var uiCanvas: UICanvasComponent?
    var uiElement: UIElementComponent?
    var uiLabel: UILabelComponent?
    var uiImage: UIImageComponent?
    var uiPanel: UIPanelComponent?
}
