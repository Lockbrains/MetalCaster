import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAI
import MetalCasterAsset
import MetalCasterAudio
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
    public let assetDatabase: AssetDatabase
    public let usdImporter = USDImporter()
    public let usdExporter = USDExporter()
    public let sceneSerializer = SceneSerializer()

    // MARK: - Systems

    public let hierarchySystem = HierarchySystem()
    public let transformSystem = TransformSystem()
    public let cameraSystem = CameraSystem()
    public let lightingSystem = LightingSystem()
    public let meshRenderSystem = MeshRenderSystem()
    public let skyboxSystem = SkyboxSystem()
    public let postProcessVolumeSystem = PostProcessVolumeSystem()

    // MARK: - Audio

    public let audioEngine = MCAudioEngine()
    public let audioSystem: AudioSystem

    // MARK: - Selection

    public var selectedEntity: Entity? = nil
    public var selectedCollectionID: UUID? = nil

    // MARK: - Inline Rename

    public let renameManager = RenameManager()

    public var renamingAssetGUID: UUID? {
        get {
            if case .asset(let guid) = renameManager.target { return guid }
            return nil
        }
        set {
            if let guid = newValue { renameManager.beginRename(.asset(guid)) }
            else if case .asset = renameManager.target { renameManager.endRename() }
        }
    }

    public var renamingEntityID: Entity? {
        get {
            if case .entity(let e) = renameManager.target { return e }
            return nil
        }
        set {
            if let e = newValue { renameManager.beginRename(.entity(e)) }
            else if case .entity = renameManager.target { renameManager.endRename() }
        }
    }

    public var renamingCollectionID: UUID? {
        get {
            if case .collection(let id) = renameManager.target { return id }
            return nil
        }
        set {
            if let id = newValue { renameManager.beginRename(.collection(id)) }
            else if case .collection = renameManager.target { renameManager.endRename() }
        }
    }

    /// Incremented whenever the ECS World is mutated.
    /// Inspector and other views read this to force SwiftUI re-evaluation.
    public var worldRevision: Int = 0

    // MARK: - Collections

    public var collections: [SceneCollection] = []

    /// Mutate the world and bump the revision counter so SwiftUI re-renders.
    /// Edits are coalesced: rapid successive changes to the same entity become a single undo entry.
    public func updateComponent<C: Component>(_ type: C.Type, on entity: Entity, _ body: (inout C) -> Void) {
        if pendingEdit?.entity != entity {
            commitPendingEdit()
            pendingEdit = PendingComponentEdit(
                entity: entity,
                beforeSnapshot: EntitySnapshot.capture(entity: entity, world: engine.world)
            )
        }

        guard var comp = engine.world.getComponent(type, from: entity) else { return }
        body(&comp)
        engine.world.addComponent(comp, to: entity)
        worldRevision += 1
        markDirty()

        pendingEditTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.commitPendingEdit()
        }
        pendingEditTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: timer)
    }

    private struct PendingComponentEdit {
        let entity: Entity
        let beforeSnapshot: EntitySnapshot
    }

    private var pendingEdit: PendingComponentEdit?
    private var pendingEditTimer: DispatchWorkItem?

    /// Flush any pending component edit as a single undo command.
    public func commitPendingEdit() {
        pendingEditTimer?.cancel()
        pendingEditTimer = nil
        guard let edit = pendingEdit else { return }
        pendingEdit = nil
        guard engine.world.isAlive(edit.entity) else { return }
        let afterSnapshot = EntitySnapshot.capture(entity: edit.entity, world: engine.world)
        recordCommand(ComponentChangeCommand(
            entityID: edit.entity.id,
            beforeSnapshot: edit.beforeSnapshot,
            afterSnapshot: afterSnapshot
        ))
    }

    /// Marks the current scene as having unsaved changes.
    public func markDirty() {
        isSceneDirty = true
        scheduleAutoSave()
    }

    private var autoSaveTask: DispatchWorkItem?

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveFadeTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveScene()
            self.isSceneDirty = false
            self.autoSaveStatus = .saved
            let fade = DispatchWorkItem { [weak self] in
                if self?.autoSaveStatus == .saved {
                    self?.autoSaveStatus = .idle
                }
            }
            self.autoSaveFadeTask = fade
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fade)
        }
        autoSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }

    // MARK: - Undo/Redo

    public var undoStack: [EditorCommand] = []
    public var redoStack: [EditorCommand] = []

    // MARK: - Clipboard

    public var entityClipboard: EntitySnapshot? = nil

    // MARK: - UI State

    public var showOpenPanel = false
    public var showSavePanel = false
    public var showImportPanel = false
    public var showAIChat = false
    public var showAISettings = false
    public var showShaderCanvas = false
    public var showSDFCanvas = false
    public var showProfiler = false
    public var showFrameDebugger = false
    public var currentFileURL: URL? = nil
    public var sceneName: String = "Untitled Scene"
    public var isSceneDirty: Bool = false

    public enum AutoSaveStatus { case idle, saved }
    public var autoSaveStatus: AutoSaveStatus = .idle
    private var autoSaveFadeTask: DispatchWorkItem?

    /// Shown when the user attempts a destructive scene action while dirty.
    public var showSaveDirtyAlert: Bool = false
    /// The action to perform after the user resolves the dirty alert.
    public var pendingSceneAction: (() -> Void)?

    // MARK: - Asset Browser State

    public var selectedAssetCategory: AssetCategory = .scenes
    public var assetBrowserSubfolder: String? = nil
    public var assetBrowserSearchQuery: String = ""
    public var selectedAssetEntry: AssetEntry? = nil {
        didSet { loadSelectedMaterialAsset() }
    }
    public var assetViewMode: AssetViewMode = .list

    /// The material currently being edited as a standalone asset (not on an entity).
    public var editingMaterialAsset: MCMaterial? = nil
    /// The file URL of the material asset being edited.
    public var editingMaterialAssetURL: URL? = nil
    /// Incremented to force SwiftUI to re-read asset entries from disk.
    public var assetBrowserRevision: Int = 0

    public enum AssetViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
    }

    // MARK: - Build System

    public let buildSystem = BuildSystem()
    public var showBuildPanel = false
    public var buildTargetPlatform: TargetPlatform = .macOS

    // MARK: - AI

    public let aiSettings = AISettings()
    public var chatMessages: [ChatMessage] = []

    // MARK: - Agent System

    public let agentRegistry = AgentRegistry()
    public let orchestrator: AgentOrchestrator
    private(set) var engineAPI: EditorEngineAPI!

    // MARK: - Prompt Script System

    public let promptFileWatcher = PromptFileWatcher()
    public var promptCompileStatuses: [String: PromptCompileStatus] = [:]
    public var editingPromptURL: URL? = nil

    // MARK: - Version Control

    public var gitClient: MCGitClient?
    public var showVersionControl: Bool = false

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

    // MARK: - Project Render Target

    public var renderTargetConfig = RenderTargetConfig()

    // MARK: - Scene Editor Display

    public var showGrid: Bool = true
    public var invertPan: Bool = true

    /// Updated by ViewportCoordinator every frame. Excluded from observation to prevent per-frame SwiftUI rebuilds.
    @ObservationIgnored public var viewportFPS: Int = 0

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

    // MARK: - Output Camera Selection

    public var selectedOutputCamera: Entity?

    /// All entities in the scene that carry a CameraComponent.
    public var cameraEntities: [(entity: Entity, name: String)] {
        engine.world.query(TransformComponent.self, CameraComponent.self).map { (entity, _, _) in
            (entity: entity, name: sceneGraph.name(of: entity))
        }
    }

    /// The camera entity used for the Output viewport.
    /// Falls back to the first active camera, then the first camera overall.
    public var resolvedOutputCamera: Entity? {
        if let selected = selectedOutputCamera,
           engine.world.getComponent(CameraComponent.self, from: selected) != nil {
            return selected
        }
        let cameras = engine.world.query(TransformComponent.self, CameraComponent.self)
        return cameras.first(where: { $0.2.isActive })?.0 ?? cameras.first?.0
    }

    // MARK: - Viewport Camera Actions

    /// Moves the orbit camera to frame the selected entity.
    /// Keeps current yaw/pitch and adjusts target + distance based on entity bounds.
    public func focusOnSelectedEntity() {
        guard let entity = selectedEntity,
              let tc = engine.world.getComponent(TransformComponent.self, from: entity) else { return }

        let worldPosition = SIMD3<Float>(
            tc.worldMatrix.columns.3.x,
            tc.worldMatrix.columns.3.y,
            tc.worldMatrix.columns.3.z
        )

        let scale = tc.transform.scale
        let maxExtent = max(scale.x, max(scale.y, scale.z))
        let framingDistance = max(maxExtent * 3.0, 2.0)

        cameraOrbitTarget = worldPosition
        cameraOrbitDistance = framingDistance
    }

    /// Aligns the selected entity's transform to the current editor camera pose.
    /// Sets position to the camera eye and rotation to look toward the orbit target.
    public func alignSelectedEntityToView() {
        guard let entity = selectedEntity,
              engine.world.hasComponent(TransformComponent.self, on: entity) else { return }

        let eye = cameraOrbitTarget + SIMD3<Float>(
            cameraOrbitDistance * cos(cameraOrbitPitch) * sin(cameraOrbitYaw),
            cameraOrbitDistance * sin(cameraOrbitPitch),
            cameraOrbitDistance * cos(cameraOrbitPitch) * cos(cameraOrbitYaw)
        )
        let forward = simd_normalize(cameraOrbitTarget - eye)
        let rotation = simd_quatf.lookRotation(forward: forward)

        updateComponent(TransformComponent.self, on: entity) { tc in
            tc.transform.position = eye
            tc.transform.rotation = rotation
        }
    }

    // MARK: - Init

    /// Opens an existing project or initializes at the given URL.
    public init(projectURL: URL) {
        self.sceneGraph = SceneGraph(world: engine.world)
        self.orchestrator = AgentOrchestrator(registry: agentRegistry)
        self.assetDatabase = AssetDatabase(projectManager: projectManager)
        self.audioSystem = AudioSystem(audioEngine: audioEngine)

        engine.addSystem(hierarchySystem)
        engine.addSystem(transformSystem)
        engine.addSystem(cameraSystem)
        engine.addSystem(lightingSystem)
        engine.addSystem(skyboxSystem)
        engine.addSystem(postProcessVolumeSystem)
        engine.addSystem(meshRenderSystem)
        engine.addSystem(audioSystem)

        try? audioEngine.start()

        audioSystem.resolveAudioFile = { [weak self] filename in
            guard let self else { return nil }
            let entries = self.assetDatabase.allFiles(in: .audio)
            if let match = entries.first(where: {
                "\($0.name).\($0.fileExtension)" == filename
            }) {
                return self.assetDatabase.resolveURL(for: match.guid)
            }
            return nil
        }

        setupDefaultScene()
        engine.start()

        initializeProject(at: projectURL)
        tryLoadLastScene()

        setupAgentSystem()
        setupPromptFileWatcher()
    }

    private func setupAgentSystem() {
        agentRegistry.registerBuiltinAgents()
        let api = EditorEngineAPI(state: self)
        self.engineAPI = api
        orchestrator.setEngineAPI(api)
    }

    private func initializeProject(at projectURL: URL) {
        let configPath = projectURL.appendingPathComponent("project.json").path
        if FileManager.default.fileExists(atPath: configPath) {
            try? projectManager.openProject(at: projectURL)
        } else {
            let name = projectURL.deletingPathExtension().lastPathComponent
            try? projectManager.createProject(at: projectURL, name: name)
        }
        gitClient = MCGitClient(workingDirectory: projectURL)
    }

    // MARK: - Scene Setup

    public func setupDefaultScene() {
        let world = engine.world

        let skybox = sceneGraph.createEntity(name: "Skybox")
        world.addComponent(SkyboxComponent(), to: skybox)

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
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Empty Entity")
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addMeshEntity(name: String, meshType: MeshType) -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: name)
        engine.world.addComponent(MeshComponent(meshType: meshType), to: entity)
        engine.world.addComponent(
            MaterialComponent(material: MaterialRegistry.litMaterial),
            to: entity
        )
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addCamera() -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Camera", position: SIMD3<Float>(0, 2, 8))
        engine.world.addComponent(CameraComponent(isActive: false), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addDirectionalLight() -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Directional Light")
        engine.world.addComponent(LightComponent(type: .directional), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addPointLight() -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Point Light", position: SIMD3<Float>(0, 3, 0))
        engine.world.addComponent(LightComponent(type: .point, range: 10), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addSkybox(hdriTexturePath: String? = nil) -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Skybox")
        engine.world.addComponent(SkyboxComponent(hdriTexturePath: hdriTexturePath), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addSpotLight() -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Spot Light", position: SIMD3<Float>(0, 3, 0))
        engine.world.addComponent(LightComponent(type: .spot, range: 15), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    @discardableResult
    public func addPostProcessVolume() -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Post Process Volume")
        engine.world.addComponent(PostProcessVolumeComponent(), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    /// Creates a new entity with default-initialized components matching the given archetype signature.
    @discardableResult
    public func addEntityFromArchetype(componentNames: Set<String>) -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "New Entity")
        let world = engine.world

        for name in componentNames {
            switch name {
            case NameComponent.componentName:
                break // already added by createEntity
            case TransformComponent.componentName:
                break // already added by createEntity
            case MeshComponent.componentName:
                world.addComponent(MeshComponent(meshType: .cube), to: entity)
            case MaterialComponent.componentName:
                world.addComponent(
                    MaterialComponent(material: MaterialRegistry.litMaterial),
                    to: entity
                )
            case CameraComponent.componentName:
                world.addComponent(CameraComponent(isActive: false), to: entity)
            case LightComponent.componentName:
                world.addComponent(LightComponent(type: .directional), to: entity)
            case PostProcessVolumeComponent.componentName:
                world.addComponent(PostProcessVolumeComponent(), to: entity)
            case GameplayScriptRef.componentName:
                world.addComponent(GameplayScriptRef(), to: entity)
            case ManagerComponent.componentName:
                break // managers should not be spawned this way
            default:
                break
            }
        }

        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    // MARK: - Manager Operations

    @discardableResult
    public func addManager(_ type: ManagerComponent.ManagerType) -> Entity? {
        commitPendingEdit()
        let existing = engine.world.query(ManagerComponent.self)
        if existing.contains(where: { $0.1.managerType == type }) { return nil }

        let entity = sceneGraph.createEntity(name: type.rawValue)
        engine.world.addComponent(ManagerComponent(managerType: type), to: entity)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    public func removeManager(_ type: ManagerComponent.ManagerType) {
        commitPendingEdit()
        let managers = engine.world.query(ManagerComponent.self)
        guard let (entity, _) = managers.first(where: { $0.1.managerType == type }) else { return }
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(DeleteEntityCommand(entityID: entity.id, snapshot: snapshot))
        sceneGraph.destroyEntityRecursive(entity)
        if selectedEntity == entity { selectedEntity = nil }
        worldRevision += 1
        markDirty()
    }

    public func deleteSelectedEntity() {
        commitPendingEdit()
        guard let entity = selectedEntity else { return }
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(DeleteEntityCommand(entityID: entity.id, snapshot: snapshot))
        sceneGraph.destroyEntityRecursive(entity)
        selectedEntity = nil
        worldRevision += 1
        markDirty()
    }

    public func duplicateSelectedEntity() {
        commitPendingEdit()
        guard let entity = selectedEntity else { return }
        let world = engine.world
        if world.hasComponent(ManagerComponent.self, on: entity) { return }

        var snapshot = EntitySnapshot.capture(entity: entity, world: world)
        if var tc = snapshot.transform {
            tc.transform.position.x += 1
            snapshot.transform = tc
        }
        if var name = snapshot.name {
            name.name += " Copy"
            snapshot.name = name
        }
        snapshot.manager = nil
        executeCommand(CreateEntityCommand(snapshot: snapshot))
    }

    // MARK: - Hierarchy Operations

    @discardableResult
    public func addChildEntity(parent: Entity) -> Entity {
        commitPendingEdit()
        let entity = sceneGraph.createEntity(name: "Empty Entity", parent: parent)
        selectedEntity = entity
        let snapshot = EntitySnapshot.capture(entity: entity, world: engine.world)
        recordCommand(CreateEntityCommand(snapshot: snapshot, initialEntityID: entity.id))
        worldRevision += 1
        markDirty()
        return entity
    }

    public func reparentEntity(_ entity: Entity, to newParent: Entity?) {
        commitPendingEdit()
        sceneGraph.setParent(entity, to: newParent)
        worldRevision += 1
        markDirty()
    }

    // MARK: - Collection Operations

    @discardableResult
    public func createCollection(name: String = "New Collection") -> SceneCollection {
        let collection = SceneCollection(name: name)
        collections.append(collection)
        worldRevision += 1
        markDirty()
        return collection
    }

    public func deleteCollection(id: UUID) {
        collections.removeAll { $0.id == id }
        if selectedCollectionID == id { selectedCollectionID = nil }
        worldRevision += 1
        markDirty()
    }

    public func renameCollection(id: UUID, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].name = name
        worldRevision += 1
        markDirty()
    }

    public func addEntityToCollection(_ entity: Entity, collectionID: UUID) {
        removeEntityFromAllCollections(entity)
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].memberEntityIDs.append(entity.id)
        worldRevision += 1
        markDirty()
    }

    public func removeEntityFromCollection(_ entity: Entity, collectionID: UUID) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].memberEntityIDs.removeAll { $0 == entity.id }
        worldRevision += 1
        markDirty()
    }

    public func removeEntityFromAllCollections(_ entity: Entity) {
        for i in collections.indices {
            collections[i].memberEntityIDs.removeAll { $0 == entity.id }
        }
    }

    public func collectionContaining(_ entity: Entity) -> SceneCollection? {
        collections.first { $0.memberEntityIDs.contains(entity.id) }
    }

    /// Cmd+Shift+N context-aware creation:
    /// - If an entity inside a collection is selected, creates a new empty entity in that collection.
    /// - Otherwise, creates a new collection and selects it.
    public func createCollectionOrEntityInCollection() {
        if let entity = selectedEntity,
           let collection = collectionContaining(entity) {
            let newEntity = addEmptyEntity()
            addEntityToCollection(newEntity, collectionID: collection.id)
        } else {
            let collection = createCollection()
            selectedCollectionID = collection.id
            selectedEntity = nil
            selectedAssetEntry = nil
        }
    }

    // MARK: - Collection Persistence

    private func collectionsFileURL(for sceneURL: URL) -> URL {
        sceneURL.deletingPathExtension().appendingPathExtension("mccoll")
    }

    private func saveCollections(for sceneURL: URL) {
        let url = collectionsFileURL(for: sceneURL)
        var file = SceneCollectionsFile()
        for c in collections {
            file.collections.append(SceneCollectionData(
                id: c.id,
                name: c.name,
                memberNames: c.memberNames(sceneGraph: sceneGraph)
            ))
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[MetalCaster] Failed to save collections: \(error)")
        }
    }

    private func loadCollections(for sceneURL: URL) {
        let url = collectionsFileURL(for: sceneURL)
        guard FileManager.default.fileExists(atPath: url.path) else {
            collections = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(SceneCollectionsFile.self, from: data)

            let world = engine.world
            let nameToEntity: [String: Entity] = {
                var map: [String: Entity] = [:]
                for entity in world.entities {
                    map[sceneGraph.name(of: entity)] = entity
                }
                return map
            }()

            collections = file.collections.map { cd in
                let memberIDs = cd.memberNames.compactMap { name in
                    nameToEntity[name]?.id
                }
                var c = SceneCollection(name: cd.name, memberEntityIDs: memberIDs)
                c.id = cd.id
                return c
            }
        } catch {
            print("[MetalCaster] Failed to load collections: \(error)")
            collections = []
        }
    }

    // MARK: - Clipboard

    public func copySelectedEntity() {
        guard let entity = selectedEntity else { return }
        entityClipboard = EntitySnapshot.capture(entity: entity, world: engine.world)
    }

    public func pasteEntity() {
        commitPendingEdit()
        guard var snapshot = entityClipboard else { return }
        if var tc = snapshot.transform {
            tc.transform.position.x += 1
            snapshot.transform = tc
        }
        if var name = snapshot.name {
            name.name += " Copy"
            snapshot.name = name
        }
        executeCommand(CreateEntityCommand(snapshot: snapshot))
    }

    // MARK: - Scene IO

    private var scenesDirectory: URL? {
        projectManager.scenesDirectory()
    }

    private var defaultSceneURL: URL? {
        scenesDirectory?.appendingPathComponent("default.usda")
    }

    private static let lastOpenedSceneKey = "MetalCaster.lastOpenedScene"

    private func ensureDirectories() {
        guard let scenesDir = scenesDirectory else { return }
        try? FileManager.default.createDirectory(at: scenesDir, withIntermediateDirectories: true)
    }

    public func newScene() {
        engine.world.clear()
        collections = []
        selectedEntity = nil
        selectedCollectionID = nil
        sceneName = "Untitled Scene"
        isSceneDirty = false
        setupDefaultScene()
        worldRevision += 1

        let url = nextAvailableSceneURL(baseName: "Untitled Scene")
        currentFileURL = url
        if let url = url {
            sceneName = url.deletingPathExtension().lastPathComponent
            saveScene(to: url)
        }
    }

    private func nextAvailableSceneURL(baseName: String) -> URL? {
        guard let dir = scenesDirectory else { return nil }
        ensureDirectories()
        let fm = FileManager.default
        let sanitized = baseName.replacingOccurrences(of: " ", with: "_")
        var candidate = dir.appendingPathComponent("\(sanitized).usda")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(sanitized)_\(counter).usda")
            counter += 1
        }
        return candidate
    }

    public func saveScene() {
        if let url = currentFileURL {
            saveScene(to: url)
        } else if let defaultURL = defaultSceneURL {
            ensureDirectories()
            saveScene(to: defaultURL)
        }
    }

    public func saveScene(to url: URL) {
        ensureDirectories()
        do {
            let usdaURL: URL
            if url.pathExtension == "usda" {
                usdaURL = url
            } else {
                usdaURL = url.deletingPathExtension().appendingPathExtension("usda")
            }
            try usdExporter.writeScene(sceneGraph: sceneGraph, world: engine.world, to: usdaURL)
            saveCollections(for: usdaURL)
            currentFileURL = usdaURL
            sceneName = usdaURL.deletingPathExtension().lastPathComponent
            isSceneDirty = false
            UserDefaults.standard.set(usdaURL.path, forKey: Self.lastOpenedSceneKey)
        } catch {
            print("[MetalCaster] Failed to save scene: \(error)")
        }
    }

    public func saveSceneAs() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = "Save Scene"
        panel.nameFieldStringValue = sceneName + ".usda"
        panel.allowedContentTypes = [UTType(filenameExtension: "usda") ?? .plainText]
        panel.directoryURL = scenesDirectory
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.saveScene(to: url)
            }
        }
        #endif
    }

    public func loadScene(from url: URL) {
        autoSaveTask?.cancel()
        do {
            if url.pathExtension == "usda" {
                try usdImporter.loadScene(from: url, into: engine.world, sceneGraph: sceneGraph)
            } else {
                let data = try Data(contentsOf: url)
                try sceneSerializer.deserialize(data: data, into: engine.world, sceneGraph: sceneGraph)
            }
            currentFileURL = url
            sceneName = url.deletingPathExtension().lastPathComponent
            selectedEntity = nil
            selectedCollectionID = nil
            isSceneDirty = false
            loadCollections(for: url)
            worldRevision += 1
            UserDefaults.standard.set(url.path, forKey: Self.lastOpenedSceneKey)
        } catch {
            print("[MetalCaster] Failed to load scene: \(error)")
        }
    }

    /// Requests a scene load, prompting save if the current scene has unsaved changes.
    public func requestLoadScene(from url: URL) {
        guard isSceneDirty else {
            loadScene(from: url)
            return
        }
        pendingSceneAction = { [weak self] in
            self?.loadScene(from: url)
        }
        showSaveDirtyAlert = true
    }

    /// Requests a new scene, prompting save if the current scene has unsaved changes.
    public func requestNewScene() {
        guard isSceneDirty else {
            newScene()
            return
        }
        pendingSceneAction = { [weak self] in
            self?.newScene()
        }
        showSaveDirtyAlert = true
    }

    /// Saves the current scene and then executes the pending action.
    public func saveAndExecutePendingAction() {
        saveScene()
        let action = pendingSceneAction
        pendingSceneAction = nil
        action?()
    }

    /// Discards changes and executes the pending action.
    public func discardAndExecutePendingAction() {
        isSceneDirty = false
        autoSaveTask?.cancel()
        let action = pendingSceneAction
        pendingSceneAction = nil
        action?()
    }

    /// Cancels the pending scene action.
    public func cancelPendingAction() {
        pendingSceneAction = nil
    }

    public func tryLoadLastScene() {
        if let snapshot = projectManager.config?.editorSnapshot,
           let lastScene = snapshot.lastOpenScene,
           let root = projectManager.projectRoot {
            let url = root.appendingPathComponent(lastScene)
            if FileManager.default.fileExists(atPath: url.path) {
                loadScene(from: url)
                return
            }
        }

        if let path = UserDefaults.standard.string(forKey: Self.lastOpenedSceneKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                loadScene(from: url)
                return
            }
        }

        if let defaultURL = defaultSceneURL,
           FileManager.default.fileExists(atPath: defaultURL.path) {
            loadScene(from: defaultURL)
            return
        }

        if let defaultURL = defaultSceneURL {
            ensureDirectories()
            currentFileURL = defaultURL
            sceneName = "default"
            saveScene(to: defaultURL)
        }
    }

    public func importUSD(from url: URL) {
        usdImporter.importAsset(from: url, into: engine.world, sceneGraph: sceneGraph)
        worldRevision += 1
        markDirty()
    }

    /// Forces the asset browser to re-read from disk.
    public func refreshAssetBrowser() {
        assetBrowserRevision += 1
    }

    /// Creates a new gameplay script from the template and places it in the Gameplay directory.
    public func createGameplayScript(named name: String) {
        guard let dir = projectManager.directoryURL(for: .gameplay) else {
            print("[MetalCaster] Gameplay directory not available")
            return
        }

        let sanitized = name.replacingOccurrences(of: " ", with: "")
        let filename = "\(sanitized)Script.swift"
        let fileURL = dir.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[MetalCaster] Script already exists: \(filename)")
            return
        }

        let content = ScriptTemplateGenerator.generate(name: sanitized)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            _ = projectManager.ensureMeta(
                for: "Gameplay/\(filename)",
                type: .gameplay
            )
            selectedAssetCategory = .gameplay
            assetBrowserSubfolder = nil
            refreshAssetBrowser()
        } catch {
            print("[MetalCaster] Failed to create script: \(error)")
        }
    }

    // MARK: - Prompt Script Operations

    private func setupPromptFileWatcher() {
        guard let gameplayDir = projectManager.directoryURL(for: .gameplay) else { return }
        promptFileWatcher.onPromptChanged = { [weak self] url in
            guard let self else { return }
            // Don't auto-compile if the user has the file open in the built-in editor;
            // the editor provides an explicit "Generate" button instead.
            guard self.editingPromptURL != url else { return }
            Task { @MainActor in
                await self.compilePromptScript(at: url)
            }
        }
        promptFileWatcher.startWatching(directory: gameplayDir)
    }

    /// Creates a new `.prompt` file from the template and places it in the Gameplay directory.
    public func createPromptScript(named name: String) {
        guard let dir = projectManager.directoryURL(for: .gameplay) else {
            print("[MetalCaster] Gameplay directory not available")
            return
        }

        let sanitized = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        guard !sanitized.isEmpty else {
            print("[MetalCaster] Invalid prompt script name")
            return
        }

        let filename = "\(sanitized).prompt"
        let fileURL = dir.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[MetalCaster] Prompt script already exists: \(filename)")
            return
        }

        let data = PromptScriptTemplate.generate(name: name.trimmingCharacters(in: .whitespaces))
        do {
            try data.write(to: fileURL, options: .atomic)
            _ = projectManager.ensureMeta(for: "Gameplay/\(filename)", type: .gameplay)
            selectedAssetCategory = .gameplay
            assetBrowserSubfolder = nil
            refreshAssetBrowser()
            editingPromptURL = fileURL
        } catch {
            print("[MetalCaster] Failed to create prompt script: \(error)")
        }
    }

    /// Compiles a single `.prompt` file by loading its JSON and calling the LLM.
    public func compilePromptScript(at url: URL) async {
        let key = url.lastPathComponent
        promptCompileStatuses[key] = .compiling

        do {
            let data = try PromptScriptTemplate.load(from: url)
            let errors = PromptScriptValidator.validate(data)
            guard errors.isEmpty else {
                promptCompileStatuses[key] = .failed(errors.first ?? "Validation failed")
                return
            }

            guard let genURL = projectManager.generatedScriptURL(for: url) else {
                promptCompileStatuses[key] = .failed("Could not determine output path")
                return
            }

            let swiftCode = try await PromptScriptCompiler.shared.compile(
                data: data,
                settings: aiSettings
            )

            try swiftCode.write(to: genURL, atomically: true, encoding: .utf8)
            promptCompileStatuses[key] = .success
            refreshAssetBrowser()
            print("[MetalCaster] Compiled prompt script: \(key) -> \(genURL.lastPathComponent)")
        } catch {
            promptCompileStatuses[key] = .failed(error.localizedDescription)
            print("[MetalCaster] Failed to compile prompt script \(key): \(error)")
        }
    }

    /// Compiles all `.prompt` files in the Gameplay directory.
    public func compileAllPromptScripts() async {
        guard let dir = projectManager.directoryURL(for: .gameplay) else { return }
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents where url.pathExtension.lowercased() == "prompt" {
            await compilePromptScript(at: url)
        }
    }

    /// Returns the generated Swift URL for a given `.prompt` entry, if it exists.
    public func generatedScriptURL(for promptEntry: AssetEntry) -> URL? {
        guard promptEntry.fileExtension == "prompt",
              let root = projectManager.projectRoot else { return nil }
        let promptURL = root.appendingPathComponent(promptEntry.relativePath)
        return projectManager.generatedScriptURL(for: promptURL)
    }

    /// Whether a generated Swift file exists for the given prompt entry.
    public func hasGeneratedScript(for promptEntry: AssetEntry) -> Bool {
        guard let url = generatedScriptURL(for: promptEntry) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Imports a file into the project via AssetDatabase.
    public func importAssetFile(from url: URL) {
        do {
            let entry = try assetDatabase.importAsset(from: url)
            selectedAssetCategory = entry.category
            selectedAssetEntry = entry
            assetBrowserSubfolder = nil
            refreshAssetBrowser()
        } catch {
            print("[MetalCaster] Failed to import asset: \(error)")
        }
    }

    // MARK: - Material Asset Creation

    /// Creates a new material asset (.mcmat) in the Materials directory.
    public func createMaterialAsset(named name: String, baseShader: String = "lit") {
        guard let dir = projectManager.directoryURL(for: .materials) else {
            print("[MetalCaster] Materials directory not available")
            return
        }

        let sanitized = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(sanitized).mcmat"
        var fileURL = dir
        if let sub = assetBrowserSubfolder {
            fileURL = fileURL.appendingPathComponent(sub)
        }
        fileURL = fileURL.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[MetalCaster] Material already exists: \(filename)")
            return
        }

        let shaderRef: String
        switch baseShader {
        case "unlit": shaderRef = "builtin/unlit"
        case "toon":  shaderRef = "builtin/toon"
        default:      shaderRef = "builtin/lit"
        }

        let material = MCMaterial(
            name: sanitized,
            materialType: .custom,
            surfaceProperties: MCMaterialProperties(),
            shaderReference: shaderRef
        )

        do {
            try material.save(to: fileURL)
            let relPath = "Materials/\(assetBrowserSubfolder.map { $0 + "/" } ?? "")\(filename)"
            _ = projectManager.ensureMeta(for: relPath, type: .materials)
            selectedAssetCategory = .materials
            refreshAssetBrowser()
        } catch {
            print("[MetalCaster] Failed to create material: \(error)")
        }
    }

    /// Creates a new shader asset (.metal) in the Shaders directory.
    public func createShaderAsset(named name: String) {
        guard let dir = projectManager.directoryURL(for: .shaders) else {
            print("[MetalCaster] Shaders directory not available")
            return
        }

        let sanitized = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(sanitized).metal"
        var fileURL = dir
        if let sub = assetBrowserSubfolder {
            fileURL = fileURL.appendingPathComponent(sub)
        }
        fileURL = fileURL.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[MetalCaster] Shader already exists: \(filename)")
            return
        }

        let template = Self.shaderTemplate(name: sanitized)

        do {
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
            let relPath = "Shaders/\(assetBrowserSubfolder.map { $0 + "/" } ?? "")\(filename)"
            _ = projectManager.ensureMeta(for: relPath, type: .shaders)
            selectedAssetCategory = .shaders
            refreshAssetBrowser()
        } catch {
            print("[MetalCaster] Failed to create shader: \(error)")
        }
    }

    private func loadSelectedMaterialAsset() {
        guard let entry = selectedAssetEntry,
              entry.fileExtension == "mcmat",
              let url = assetDatabase.resolveURL(for: entry.guid) else {
            editingMaterialAsset = nil
            editingMaterialAssetURL = nil
            return
        }
        do {
            editingMaterialAsset = try MCMaterial.load(from: url)
            editingMaterialAssetURL = url
        } catch {
            print("[MetalCaster] Failed to load material asset for editing: \(error)")
            editingMaterialAsset = nil
            editingMaterialAssetURL = nil
        }
    }

    /// Saves the currently editing material asset back to disk
    /// and propagates parameter changes to any entities using this material.
    public func saveEditingMaterialAsset() {
        guard let mat = editingMaterialAsset, let url = editingMaterialAssetURL else { return }
        do {
            try mat.save(to: url)
            let entities = engine.world.entitiesWith(MaterialComponent.self)
            for entity in entities {
                guard let mc = engine.world.getComponent(MaterialComponent.self, from: entity) else { continue }
                if mc.material.name == mat.name {
                    var updated = mc.material
                    updated.parameters = mat.parameters
                    updated.surfaceProperties = mat.surfaceProperties
                    engine.world.addComponent(MaterialComponent(material: updated), to: entity)
                }
            }
            worldRevision += 1
        } catch {
            print("[MetalCaster] Failed to save material asset: \(error)")
        }
    }

    /// Loads a .mcmat file and assigns it to the selected entity.
    public func assignMaterialAsset(from url: URL) {
        guard let entity = selectedEntity else {
            print("[MetalCaster] No entity selected to assign material")
            return
        }
        assignMaterialAsset(from: url, to: entity)
    }

    /// Loads a .mcmat file and assigns it to a specific entity.
    public func assignMaterialAsset(from url: URL, to entity: Entity) {
        do {
            let material = try MCMaterial.load(from: url)
            if engine.world.hasComponent(MaterialComponent.self, on: entity) {
                updateComponent(MaterialComponent.self, on: entity) { mc in
                    mc.material = material
                }
            } else {
                engine.world.addComponent(MaterialComponent(material: material), to: entity)
                worldRevision += 1
                markDirty()
            }
        } catch {
            print("[MetalCaster] Failed to load material asset: \(error)")
        }
    }

    /// Re-applies an updated material to all entities currently using it (matched by name).
    /// Also invalidates the pipeline cache so the new shader gets compiled.
    public func reloadMaterialOnEntities(from url: URL, material: MCMaterial) {
        let entities = engine.world.entitiesWith(MaterialComponent.self)
        for entity in entities {
            guard let mc = engine.world.getComponent(MaterialComponent.self, from: entity) else { continue }
            if mc.material.name == material.name {
                updateComponent(MaterialComponent.self, on: entity) { $0.material = material }
            }
        }
        if let entry = selectedAssetEntry, entry.fileExtension == "mcmat" {
            editingMaterialAsset = material
            editingMaterialAssetURL = url
        }
    }

    private static func shaderTemplate(name: String) -> String {
        """
        #include <metal_stdlib>
        using namespace metal;

        // Metal Caster — Custom Shader: \(name)
        //
        // ========== Shader Parameters ==========
        // Declare parameters with @param annotations.
        // The engine parses these and generates Inspector UI automatically.
        // Format: // @param <name> <type> <default...> [<min> <max>]
        // Types:  float, float2, float3, float4, color3, color4
        //
        // @param brightness float 1.0 0.0 5.0
        // @param tintColor color3 1.0 1.0 1.0
        // @param waveSpeed float 1.0 0.0 10.0
        // ========================================
        //
        // Access custom parameters via: customParams[0], customParams[1], ...
        // They are packed in declaration order. For the above:
        //   customParams[0] = brightness  (1 float)
        //   customParams[1..3] = tintColor (3 floats)
        //   customParams[4] = waveSpeed   (1 float)

        struct VertexIn {
            float3 position [[attribute(0)]];
            float3 normal   [[attribute(1)]];
            float2 texCoord [[attribute(2)]];
        };

        struct Uniforms {
            float4x4 mvpMatrix;
            float4x4 modelMatrix;
            float4x4 normalMatrix;
            float4   cameraPosition;
            float    time;
            float    _pad0;
            float    _pad1;
            float    _pad2;
        };

        struct MaterialProperties {
            float3 baseColor;
            float metallic;
            float roughness;
            float _pad0;
            float3 emissiveColor;
            float emissiveIntensity;
            uint hasAlbedoTexture;
            uint hasNormalMap;
            uint hasMetallicRoughnessMap;
            uint _pad1;
        };

        struct VertexOut {
            float4 position [[position]];
            float3 normalWS;
            float3 positionWS;
            float2 texCoord;
        };

        vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            VertexOut out;
            out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
            float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
            out.positionWS = worldPos.xyz;
            out.normalWS = normalize((uniforms.normalMatrix * float4(in.normal, 0.0)).xyz);
            out.texCoord = in.texCoord;
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant MaterialProperties &material [[buffer(2)]],
                                      constant float *customParams [[buffer(5)]],
                                      texture2d<float> albedoTex [[texture(0)]]) {
            constexpr sampler texSampler(address::repeat, filter::linear);

            float brightness = customParams[0];
            float3 tintColor = float3(customParams[1], customParams[2], customParams[3]);
            float waveSpeed = customParams[4];

            float3 color = material.baseColor * tintColor;
            if (material.hasAlbedoTexture != 0) {
                color *= albedoTex.sample(texSampler, in.texCoord).rgb;
            }

            // Animated hemisphere lighting
            float3 N = normalize(in.normalWS);
            float wave = sin(in.positionWS.x * 3.0 + in.positionWS.z * 3.0 + uniforms.time * waveSpeed) * 0.5 + 0.5;
            float NdotUp = dot(N, float3(0, 1, 0)) * 0.5 + 0.5;
            color *= mix(0.3, 1.0, NdotUp) * brightness;
            color = mix(color, color * (0.8 + 0.2 * wave), 0.3);

            color += material.emissiveColor * material.emissiveIntensity;
            return float4(color, 1.0);
        }
        """
    }

    /// Navigates the asset browser into a subfolder.
    public func enterAssetSubfolder(_ name: String) {
        if let current = assetBrowserSubfolder {
            assetBrowserSubfolder = current + "/" + name
        } else {
            assetBrowserSubfolder = name
        }
    }

    /// Navigates the asset browser up one level.
    public func exitAssetSubfolder() {
        guard let current = assetBrowserSubfolder else { return }
        if let lastSlash = current.lastIndex(of: "/") {
            assetBrowserSubfolder = String(current[current.startIndex..<lastSlash])
        } else {
            assetBrowserSubfolder = nil
        }
    }

    /// Returns breadcrumb path components for the current asset browser location.
    public var assetBreadcrumbs: [String] {
        var crumbs = [selectedAssetCategory.directoryName]
        if let sub = assetBrowserSubfolder {
            crumbs.append(contentsOf: sub.split(separator: "/").map(String.init))
        }
        return crumbs
    }

    /// Saves editor snapshot to project config on shutdown.
    public func saveEditorSnapshot() {
        var snapshot = ProjectManager.EditorSnapshot()
        if let url = currentFileURL, let root = projectManager.projectRoot {
            let relPath = projectManager.relativePath(for: url, from: root)
            snapshot.lastOpenScene = relPath
        }
        snapshot.selectedEntityID = selectedEntity?.id
        snapshot.cameraYaw = cameraOrbitYaw
        snapshot.cameraPitch = cameraOrbitPitch
        snapshot.cameraDistance = cameraOrbitDistance
        projectManager.updateEditorSnapshot(snapshot)
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
        if buildSystem.isPlaying {
            stopPlaying()
            return
        }

        saveScene()

        var gameplayDirs: [URL] = []
        if let gameplayDir = projectManager.directoryURL(for: .gameplay) {
            gameplayDirs.append(gameplayDir)
            let genDir = gameplayDir.appendingPathComponent(".generated")
            if FileManager.default.fileExists(atPath: genDir.path) {
                gameplayDirs.append(genDir)
            }
        }

        guard let enginePath = Self.resolveEnginePackagePath() else {
            buildSystem.buildLog.append("[Error] Cannot locate Engine package — cannot play")
            buildSystem.status = .failed(error: "Cannot locate Engine Package.swift. Make sure you are running from the source tree.")
            return
        }

        Task {
            await buildSystem.runInEditor(
                scene: sceneGraph,
                world: engine.world,
                gameplayDirectories: gameplayDirs,
                enginePackagePath: enginePath
            )
        }
    }

    public func stopPlaying() {
        buildSystem.stopPreview()
    }

    /// Locates the Engine SPM package directory.
    /// Primary: walk up from this source file's compile-time path.
    /// Fallback: walk up from the running executable.
    private static func resolveEnginePackagePath() -> URL? {
        func walkUp(from start: URL) -> URL? {
            var dir: URL? = start
            for _ in 0..<12 {
                guard let current = dir else { return nil }
                let candidate = current.appendingPathComponent("Package.swift")
                if FileManager.default.fileExists(atPath: candidate.path),
                   let contents = try? String(contentsOf: candidate, encoding: .utf8),
                   contents.contains("MetalCasterCore") {
                    return current
                }
                dir = current.deletingLastPathComponent()
            }
            return nil
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        if let found = walkUp(from: sourceFileURL.deletingLastPathComponent()) {
            return found
        }

        #if os(macOS)
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            return walkUp(from: execDir)
        }
        #endif
        return nil
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
