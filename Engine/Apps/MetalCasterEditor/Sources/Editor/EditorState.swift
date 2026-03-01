import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAI
import MetalCasterAsset
#if canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

/// Central editor state. Observable by all editor views.
@Observable
public final class EditorState {

    // MARK: - Engine

    public let engine = Engine()
    public let sceneGraph: SceneGraph
    public let assetManager = AssetManager()
    public let projectManager = ProjectManager()
    public let usdImporter = USDImporter()
    public let usdExporter = USDExporter()
    public let sceneSerializer = SceneSerializer()

    // MARK: - Systems

    public let transformSystem = TransformSystem()
    public let cameraSystem = CameraSystem()
    public let lightingSystem = LightingSystem()
    public let meshRenderSystem = MeshRenderSystem()

    // MARK: - Selection

    public var selectedEntity: Entity? = nil

    /// Incremented whenever the ECS World is mutated.
    /// Inspector and other views read this to force SwiftUI re-evaluation.
    public var worldRevision: Int = 0

    /// Mutate the world and bump the revision counter so SwiftUI re-renders.
    public func updateComponent<C: Component>(_ type: C.Type, on entity: Entity, _ body: (inout C) -> Void) {
        guard var comp = engine.world.getComponent(type, from: entity) else { return }
        body(&comp)
        engine.world.addComponent(comp, to: entity)
        worldRevision += 1
    }

    // MARK: - Undo/Redo

    public var undoStack: [EditorCommand] = []
    public var redoStack: [EditorCommand] = []

    // MARK: - UI State

    public var showOpenPanel = false
    public var showSavePanel = false
    public var showImportPanel = false
    public var showAIChat = false
    public var currentFileURL: URL? = nil
    public var sceneName: String = "Untitled Scene"

    // MARK: - Build System

    public let buildSystem = BuildSystem()
    public var showBuildPanel = false
    public var buildTargetPlatform: TargetPlatform = .macOS

    // MARK: - AI

    public let aiSettings = AISettings()
    public var chatMessages: [ChatMessage] = []

    // MARK: - Scene Editor Tool Mode (QWER)

    public enum SceneToolMode: String, CaseIterable {
        case pan = "Pan"
        case translate = "Move"
        case scale = "Scale"
        case rotate = "Rotate"

        public var shortcut: String {
            switch self {
            case .pan: return "Q"
            case .translate: return "W"
            case .scale: return "E"
            case .rotate: return "R"
            }
        }

        public var icon: String {
            switch self {
            case .pan: return "hand.draw"
            case .translate: return "arrow.up.and.down.and.arrow.left.and.right"
            case .scale: return "arrow.up.left.and.arrow.down.right"
            case .rotate: return "arrow.trianglehead.2.clockwise.rotate.90"
            }
        }
    }
    public var sceneToolMode: SceneToolMode = .pan

    // MARK: - Scene Editor Render Mode

    public enum SceneRenderMode: String, CaseIterable {
        case shading = "Shading"
        case wireframe = "Wireframe"
        case rendered = "Rendered"
    }
    public var sceneRenderMode: SceneRenderMode = .rendered

    // MARK: - Scene Editor Display

    public var showGrid: Bool = true
    public var invertPan: Bool = false

    // MARK: - Scene Editor Camera

    public var isOrthographic: Bool = false
    public var orthoSize: Float = 10.0

    public enum OrthoPreset: String {
        case free = "Perspective"
        case front = "Front"
        case back = "Back"
        case right = "Right"
        case left = "Left"
        case top = "Top"
        case bottom = "Bottom"
    }
    public var orthoPreset: OrthoPreset = .free

    public func applyOrthoPreset(_ preset: OrthoPreset) {
        orthoPreset = preset
        switch preset {
        case .free:
            isOrthographic = false
        case .front:
            isOrthographic = true
            cameraOrbitYaw = 0
            cameraOrbitPitch = 0
        case .back:
            isOrthographic = true
            cameraOrbitYaw = .pi
            cameraOrbitPitch = 0
        case .right:
            isOrthographic = true
            cameraOrbitYaw = .pi / 2
            cameraOrbitPitch = 0
        case .left:
            isOrthographic = true
            cameraOrbitYaw = -.pi / 2
            cameraOrbitPitch = 0
        case .top:
            isOrthographic = true
            cameraOrbitYaw = 0
            cameraOrbitPitch = .pi / 2 - 0.001
        case .bottom:
            isOrthographic = true
            cameraOrbitYaw = 0
            cameraOrbitPitch = -.pi / 2 + 0.001
        }
    }

    // MARK: - Viewport (Primary — Scene Editor)

    public var cameraOrbitYaw: Float = 0
    public var cameraOrbitPitch: Float = 0.3
    public var cameraOrbitDistance: Float = 8.0
    public var cameraOrbitTarget: SIMD3<Float> = .zero

    // MARK: - Viewport (Secondary — Game Camera)

    public var camera2OrbitYaw: Float = 1.0
    public var camera2OrbitPitch: Float = 0.5
    public var camera2OrbitDistance: Float = 12.0
    public var camera2OrbitTarget: SIMD3<Float> = .zero

    // MARK: - Init

    public init() {
        self.sceneGraph = SceneGraph(world: engine.world)

        engine.addSystem(transformSystem)
        engine.addSystem(cameraSystem)
        engine.addSystem(lightingSystem)
        engine.addSystem(meshRenderSystem)

        setupDefaultScene()
        engine.start()

        initializeProject()
        tryLoadLastScene()
    }

    private func initializeProject() {
        let projectURL = Self.projectDirectory
        let configPath = projectURL.appendingPathComponent("project.json").path
        if FileManager.default.fileExists(atPath: configPath) {
            try? projectManager.openProject(at: projectURL)
        } else {
            try? projectManager.createProject(at: projectURL, name: "Default Project")
        }
    }

    // MARK: - Scene Setup

    public func setupDefaultScene() {
        let world = engine.world

        let cam = sceneGraph.createEntity(
            name: "Main Camera",
            position: SIMD3<Float>(0, 2, 8)
        )
        world.addComponent(CameraComponent(), to: cam)

        let light = sceneGraph.createEntity(name: "Directional Light")
        if var tc = world.getComponent(TransformComponent.self, from: light) {
            tc.transform.rotation = quaternionFromEuler(SIMD3<Float>(-0.5, 0.3, 0))
            world.addComponent(tc, to: light)
        }
        world.addComponent(LightComponent(type: .directional, intensity: 1.0), to: light)

        addMeshEntity(name: "Sphere", meshType: .sphere)
    }

    // MARK: - Entity Operations

    @discardableResult
    public func addEmptyEntity() -> Entity {
        let entity = sceneGraph.createEntity(name: "Empty Entity")
        selectedEntity = entity
        worldRevision += 1
        return entity
    }

    @discardableResult
    public func addMeshEntity(name: String, meshType: MeshType) -> Entity {
        let entity = sceneGraph.createEntity(name: name)
        engine.world.addComponent(
            MeshComponent(meshType: meshType),
            to: entity
        )
        engine.world.addComponent(
            MaterialComponent(material: MCMaterial(
                name: "\(name) Material",
                fragmentShaderSource: ShaderSnippets.lambertShading
            )),
            to: entity
        )
        selectedEntity = entity
        worldRevision += 1
        return entity
    }

    @discardableResult
    public func addCamera() -> Entity {
        let entity = sceneGraph.createEntity(
            name: "Camera",
            position: SIMD3<Float>(0, 2, 8)
        )
        engine.world.addComponent(CameraComponent(isActive: false), to: entity)
        selectedEntity = entity
        worldRevision += 1
        return entity
    }

    @discardableResult
    public func addDirectionalLight() -> Entity {
        let entity = sceneGraph.createEntity(name: "Directional Light")
        engine.world.addComponent(
            LightComponent(type: .directional),
            to: entity
        )
        selectedEntity = entity
        worldRevision += 1
        return entity
    }

    @discardableResult
    public func addPointLight() -> Entity {
        let entity = sceneGraph.createEntity(
            name: "Point Light",
            position: SIMD3<Float>(0, 3, 0)
        )
        engine.world.addComponent(
            LightComponent(type: .point, range: 10),
            to: entity
        )
        selectedEntity = entity
        worldRevision += 1
        return entity
    }

    public func deleteSelectedEntity() {
        guard let entity = selectedEntity else { return }
        sceneGraph.destroyEntityRecursive(entity)
        selectedEntity = nil
        worldRevision += 1
    }

    public func duplicateSelectedEntity() {
        guard let entity = selectedEntity else { return }
        let world = engine.world
        let name = sceneGraph.name(of: entity) + " Copy"
        let copy = sceneGraph.createEntity(name: name)

        if let tc = world.getComponent(TransformComponent.self, from: entity) {
            var newTC = tc
            newTC.transform.position.x += 1
            newTC.parent = tc.parent
            world.addComponent(newTC, to: copy)
        }
        if let mc = world.getComponent(MeshComponent.self, from: entity) {
            world.addComponent(mc, to: copy)
        }
        if let mat = world.getComponent(MaterialComponent.self, from: entity) {
            world.addComponent(mat, to: copy)
        }
        if let cam = world.getComponent(CameraComponent.self, from: entity) {
            world.addComponent(cam, to: copy)
        }
        if let light = world.getComponent(LightComponent.self, from: entity) {
            world.addComponent(light, to: copy)
        }

        selectedEntity = copy
        worldRevision += 1
    }

    // MARK: - Scene IO

    public static let projectDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("MetalCaster", isDirectory: true)
    }()

    public static let scenesDirectory: URL = {
        projectDirectory.appendingPathComponent("Scenes", isDirectory: true)
    }()

    public static let defaultSceneURL: URL = {
        scenesDirectory.appendingPathComponent("default.mcscene")
    }()

    private static let lastOpenedSceneKey = "MetalCaster.lastOpenedScene"

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.scenesDirectory, withIntermediateDirectories: true)
    }

    public func newScene() {
        engine.world.clear()
        selectedEntity = nil
        currentFileURL = nil
        sceneName = "Untitled Scene"
        setupDefaultScene()
        worldRevision += 1
    }

    public func saveScene() {
        if let url = currentFileURL {
            saveScene(to: url)
        } else {
            ensureDirectories()
            saveScene(to: Self.defaultSceneURL)
        }
    }

    public func saveScene(to url: URL) {
        ensureDirectories()
        do {
            let data = try sceneSerializer.serialize(sceneGraph: sceneGraph, world: engine.world)
            try data.write(to: url)
            currentFileURL = url
            sceneName = url.deletingPathExtension().lastPathComponent
            UserDefaults.standard.set(url.path, forKey: Self.lastOpenedSceneKey)
        } catch {
            print("[MetalCaster] Failed to save scene: \(error)")
        }
    }

    public func saveSceneAs() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = "Save Scene"
        panel.nameFieldStringValue = sceneName + ".mcscene"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = Self.scenesDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.saveScene(to: url)
            }
        }
        #endif
    }

    public func loadScene(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try sceneSerializer.deserialize(data: data, into: engine.world, sceneGraph: sceneGraph)
            currentFileURL = url
            sceneName = url.deletingPathExtension().lastPathComponent
            selectedEntity = nil
            worldRevision += 1
            UserDefaults.standard.set(url.path, forKey: Self.lastOpenedSceneKey)
        } catch {
            print("[MetalCaster] Failed to load scene: \(error)")
        }
    }

    public func tryLoadLastScene() {
        if let path = UserDefaults.standard.string(forKey: Self.lastOpenedSceneKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                loadScene(from: url)
                return
            }
        }
        if FileManager.default.fileExists(atPath: Self.defaultSceneURL.path) {
            loadScene(from: Self.defaultSceneURL)
        }
    }

    public func importUSD(from url: URL) {
        usdImporter.importAsset(from: url, into: engine.world, sceneGraph: sceneGraph)
        worldRevision += 1
    }

    public func exportUSD(to url: URL) {
        try? usdExporter.writeUSDA(sceneGraph: sceneGraph, world: engine.world, to: url)
    }

    // MARK: - Build

    public func buildProject(to outputDirectory: URL) {
        let config = BuildConfiguration(
            targetPlatform: buildTargetPlatform,
            outputDirectory: outputDirectory,
            projectName: sceneName.replacingOccurrences(of: " ", with: ""),
            bundleIdentifier: "com.metalcaster.\(sceneName.lowercased().replacingOccurrences(of: " ", with: ""))"
        )
        Task {
            await buildSystem.build(
                scene: sceneGraph,
                world: engine.world,
                config: config
            )
        }
    }

    public func playInEditor() {
        Task {
            await buildSystem.runInEditor(scene: sceneGraph, world: engine.world)
        }
    }

    // MARK: - Tick

    public func tick(deltaTime: Float) {
        engine.tick(deltaTime: deltaTime)
    }
}

// MARK: - Undo/Redo Command

public protocol EditorCommand {
    func execute(state: EditorState)
    func undo(state: EditorState)
    var description: String { get }
}
