import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

/// The lightweight game runtime. Loads a scene bundle and runs
/// the game loop with all registered systems.
@Observable
public final class MCRuntime {
    
    public let engine = Engine()
    public let sceneGraph: SceneGraph
    public let sceneSerializer = SceneSerializer()
    
    public let hierarchySystem = HierarchySystem()
    public let transformSystem = TransformSystem()
    public let cameraSystem = CameraSystem()
    public let lightingSystem = LightingSystem()
    public let meshRenderSystem = MeshRenderSystem()
    
    public var isRunning: Bool = false
    public var sceneName: String = "No Scene"
    
    public init() {
        self.sceneGraph = SceneGraph(world: engine.world)
        
        engine.addSystem(hierarchySystem)
        engine.addSystem(transformSystem)
        engine.addSystem(cameraSystem)
        engine.addSystem(lightingSystem)
        engine.addSystem(meshRenderSystem)
    }
    
    /// Loads a scene from a .mcscene JSON file.
    public func loadScene(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try sceneSerializer.deserialize(data: data, into: engine.world, sceneGraph: sceneGraph)
        sceneName = url.deletingPathExtension().lastPathComponent
    }
    
    /// Starts the runtime game loop.
    public func start() {
        engine.start()
        isRunning = true
    }
    
    /// Stops the runtime.
    public func stop() {
        engine.stop()
        isRunning = false
    }
    
    /// Performs one frame update.
    public func tick(deltaTime: Float) {
        guard isRunning else { return }
        engine.tick(deltaTime: deltaTime)
    }
}
