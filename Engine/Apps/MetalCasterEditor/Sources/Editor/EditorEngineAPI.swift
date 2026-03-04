import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAI
import MetalCasterAsset
import MetalCasterAudio

/// Concrete implementation of `EngineAPIProvider` that bridges agent tool calls
/// to actual `EditorState` / `World` / `SceneGraph` operations.
final class EditorEngineAPI: EngineAPIProvider {
    private let state: EditorState

    init(state: EditorState) {
        self.state = state
    }

    // MARK: - EngineAPIProvider

    func executeTool(name: String, arguments: [String: JSONValue]) async throws -> ToolResult {
        await MainActor.run {
            executeToolOnMain(name: name, arguments: arguments)
        }
    }

    func takeSnapshot() -> EngineSnapshot {
        let world = state.engine.world
        let sceneGraph = state.sceneGraph

        let allEntities = Array(world.entities)
        var entityInfos: [EntityInfo] = []

        for entity in allEntities {
            let name = sceneGraph.name(of: entity)
            var components: [String] = []
            var pos: Vec3Storage?
            let rot: Vec3Storage? = nil
            var scl: Vec3Storage?

            if let tc = world.getComponent(TransformComponent.self, from: entity) {
                components.append("Transform")
                let p = tc.transform.position
                pos = Vec3Storage(p.x, p.y, p.z)
                let s = tc.transform.scale
                scl = Vec3Storage(s.x, s.y, s.z)
            }
            if world.hasComponent(CameraComponent.self, on: entity) { components.append("Camera") }
            if world.hasComponent(LightComponent.self, on: entity) { components.append("Light") }
            if world.hasComponent(MeshComponent.self, on: entity) { components.append("Mesh") }
            if world.hasComponent(MaterialComponent.self, on: entity) { components.append("Material") }
            if world.hasComponent(NameComponent.self, on: entity) { components.append("Name") }

            entityInfos.append(EntityInfo(
                id: entity.id,
                name: name,
                components: components,
                position: pos,
                rotation: rot,
                scale: scl
            ))
        }

        let hierarchy = buildHierarchyNodes(sceneGraph: sceneGraph)

        let renderInfo = RenderInfo(
            drawCallCount: state.meshRenderSystem.drawCalls.count,
            lightCount: state.lightingSystem.lights.count,
            renderMode: state.sceneRenderMode.rawValue
        )

        let metrics = MetricsInfo(
            fps: state.engine.deltaTime > 0 ? 1.0 / state.engine.deltaTime : 0,
            frameTime: state.engine.deltaTime * 1000,
            totalTime: state.engine.totalTime
        )

        let systemInfos = state.engine.registeredSystems.map { sys in
            SystemInfo(name: sys.name, priority: sys.priority, isEnabled: sys.isEnabled)
        }

        return EngineSnapshot(
            entityCount: world.entityCount,
            entities: entityInfos,
            hierarchy: hierarchy,
            selectedEntityID: state.selectedEntity?.id,
            renderInfo: renderInfo,
            metrics: metrics,
            systems: systemInfos
        )
    }

    // MARK: - Tool Dispatch

    @MainActor
    private func executeToolOnMain(name: String, arguments: [String: JSONValue]) -> ToolResult {
        switch name {

        // ── Scene Tools ──────────────────────────────────────────────
        case "createEntity":
            return toolCreateEntity(arguments)
        case "deleteEntity":
            return toolDeleteEntity(arguments)
        case "duplicateEntity":
            return toolDuplicateEntity(arguments)
        case "addComponent":
            return toolAddComponent(arguments)
        case "removeComponent":
            return toolRemoveComponent(arguments)
        case "setTransform":
            return toolSetTransform(arguments)
        case "reparent":
            return toolReparent(arguments)
        case "queryScene":
            return toolQueryScene()
        case "queryEntity":
            return toolQueryEntity(arguments)
        case "selectEntity":
            return toolSelectEntity(arguments)
        case "importUSD":
            return toolImportUSD(arguments)
        case "exportUSD":
            return toolExportUSD(arguments)

        // ── Render Tools ─────────────────────────────────────────────
        case "setRenderMode":
            return toolSetRenderMode(arguments)
        case "configureLighting":
            return toolConfigureLighting(arguments)
        case "addLight":
            return toolAddLight(arguments)
        case "queryRenderState":
            return toolQueryRenderState()
        case "setCamera":
            return toolSetCamera(arguments)
        case "captureFrame":
            return toolCaptureFrame()

        // ── Shader Tools ─────────────────────────────────────────────
        case "createMaterial":
            return toolCreateMaterial(arguments)
        case "modifyShader":
            return toolModifyShader(arguments)
        case "queryMaterial":
            return toolQueryMaterial(arguments)
        case "applyPresetMaterial":
            return toolApplyPresetMaterial(arguments)
        case "listShaderSnippets":
            return toolListShaderSnippets()

        // ── Diagnostic / Analyze Tools ───────────────────────────────
        case "validateScene":
            return toolValidateScene()
        case "analyzeHierarchy":
            return toolAnalyzeHierarchy()
        case "inspectEntity":
            return toolInspectEntity(arguments)
        case "generateDiagnosticReport":
            return toolGenerateDiagnosticReport()

        // ── Optimize Tools ───────────────────────────────────────────
        case "profileFrame":
            return toolProfileFrame()
        case "analyzeDrawCalls":
            return toolAnalyzeDrawCalls()
        case "suggestOptimizations":
            return toolSuggestOptimizations()

        // ── System Tools ─────────────────────────────────────────────
        case "listSystems":
            return toolListSystems()

        // ── Gameplay Script Tools ────────────────────────────────────
        case "createScript":
            return toolCreateScript(arguments)
        case "createPromptScript":
            return toolCreatePromptScript(arguments)

        // ── Asset Tools ──────────────────────────────────────────────
        case "listAssets":
            return toolListAssets(arguments)
        case "queryProjectConfig":
            return toolQueryProjectConfig()

        // ── Art Tools ───────────────────────────────────────────────
        case "generateColorPalette":
            return toolGenerateColorPalette(arguments)
        case "suggestMaterials":
            return toolSuggestMaterials(arguments)
        case "createVisualStyle":
            return toolCreateVisualStyle(arguments)
        case "analyzeVisualComposition":
            return toolAnalyzeVisualComposition(arguments)
        case "applyLightingPreset":
            return toolApplyLightingPreset(arguments)

        // ── Audio Tools ─────────────────────────────────────────────
        case "listAudioAssets":
            return toolListAudioAssets()
        case "createAudioSource":
            return toolCreateAudioSource(arguments)
        case "configureAudioBus":
            return toolConfigureAudioBus(arguments)
        case "setSpatialAudio":
            return toolSetSpatialAudio(arguments)
        case "queryAudioState":
            return toolQueryAudioState()

        default:
            return ToolResult(toolName: name, success: false, output: "Unknown tool: \(name)")
        }
    }

    // MARK: - Scene Tool Implementations

    @MainActor
    private func toolCreateEntity(_ args: [String: JSONValue]) -> ToolResult {
        let name = args["name"]?.stringValue ?? "Untitled"
        var position = SIMD3<Float>.zero
        if let posArr = args["position"]?.floatArray, posArr.count >= 3 {
            position = SIMD3<Float>(posArr[0], posArr[1], posArr[2])
        }

        var parent: Entity?
        if let parentRef = args["parent"]?.stringValue {
            parent = resolveEntity(parentRef)
        }

        let entity = state.sceneGraph.createEntity(name: name, position: position, parent: parent)
        state.worldRevision += 1
        return ToolResult(toolName: "createEntity", success: true,
                          output: "Created entity '\(name)' (id:\(entity.id)) at (\(position.x), \(position.y), \(position.z))")
    }

    @MainActor
    private func toolDeleteEntity(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "deleteEntity", success: false, output: "Entity not found")
        }
        let name = state.sceneGraph.name(of: entity)
        state.sceneGraph.destroyEntityRecursive(entity)
        if state.selectedEntity == entity { state.selectedEntity = nil }
        state.worldRevision += 1
        return ToolResult(toolName: "deleteEntity", success: true, output: "Deleted entity '\(name)' and its children")
    }

    @MainActor
    private func toolDuplicateEntity(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "duplicateEntity", success: false, output: "Entity not found")
        }
        state.selectedEntity = entity
        state.duplicateSelectedEntity()
        let newName = state.sceneGraph.name(of: state.selectedEntity!)
        return ToolResult(toolName: "duplicateEntity", success: true,
                          output: "Duplicated as '\(newName)' (id:\(state.selectedEntity!.id))")
    }

    @MainActor
    private func toolAddComponent(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "addComponent", success: false, output: "Entity not found")
        }
        guard let compType = args["componentType"]?.stringValue else {
            return ToolResult(toolName: "addComponent", success: false, output: "Missing componentType")
        }
        let params = args["params"]?.objectValue ?? [:]
        let world = state.engine.world

        switch compType {
        case "Camera":
            world.addComponent(CameraComponent(), to: entity)
        case "Light":
            let typeStr = params["type"]?.stringValue ?? "directional"
            let lightType = LightComponent.LightType(rawValue: typeStr) ?? .directional
            let intensity = params["intensity"]?.numberValue.map { Float($0) } ?? 1.0
            world.addComponent(LightComponent(type: lightType, intensity: intensity), to: entity)
        case "Mesh":
            let meshTypeStr = params["meshType"]?.stringValue ?? "cube"
            let meshType: MeshType
            switch meshTypeStr {
            case "sphere": meshType = .sphere
            case "plane": meshType = .plane
            case "cylinder": meshType = .cylinder
            case "cone": meshType = .cone
            case "capsule": meshType = .capsule
            default: meshType = .cube
            }
            world.addComponent(MeshComponent(meshType: meshType), to: entity)
        case "Material":
            let matName = params["name"]?.stringValue ?? "New Material"
            world.addComponent(MaterialComponent(material: MCMaterial(name: matName)), to: entity)
        default:
            return ToolResult(toolName: "addComponent", success: false, output: "Unsupported component type: \(compType)")
        }

        state.worldRevision += 1
        return ToolResult(toolName: "addComponent", success: true,
                          output: "Added \(compType) to '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolRemoveComponent(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "removeComponent", success: false, output: "Entity not found")
        }
        guard let compType = args["componentType"]?.stringValue else {
            return ToolResult(toolName: "removeComponent", success: false, output: "Missing componentType")
        }
        let world = state.engine.world

        switch compType {
        case "Camera":   world.removeComponent(CameraComponent.self, from: entity)
        case "Light":    world.removeComponent(LightComponent.self, from: entity)
        case "Mesh":     world.removeComponent(MeshComponent.self, from: entity)
        case "Material": world.removeComponent(MaterialComponent.self, from: entity)
        default:
            return ToolResult(toolName: "removeComponent", success: false, output: "Unsupported component type: \(compType)")
        }

        state.worldRevision += 1
        return ToolResult(toolName: "removeComponent", success: true,
                          output: "Removed \(compType) from '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolSetTransform(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "setTransform", success: false, output: "Entity not found")
        }

        state.updateComponent(TransformComponent.self, on: entity) { tc in
            if let posArr = args["position"]?.floatArray, posArr.count >= 3 {
                tc.transform.position = SIMD3<Float>(posArr[0], posArr[1], posArr[2])
            }
            if let rotArr = args["rotation"]?.floatArray, rotArr.count >= 3 {
                tc.transform.rotation = quaternionFromEuler(SIMD3<Float>(rotArr[0], rotArr[1], rotArr[2]))
            }
            if let sclArr = args["scale"]?.floatArray, sclArr.count >= 3 {
                tc.transform.scale = SIMD3<Float>(sclArr[0], sclArr[1], sclArr[2])
            }
        }

        return ToolResult(toolName: "setTransform", success: true,
                          output: "Updated transform of '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolReparent(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "reparent", success: false, output: "Entity not found")
        }
        let parentRef = args["newParent"]?.stringValue
        let newParent: Entity? = (parentRef == "root" || parentRef == nil) ? nil : resolveEntity(parentRef!)

        state.sceneGraph.setParent(entity, to: newParent)
        state.worldRevision += 1
        let parentName = newParent.map { state.sceneGraph.name(of: $0) } ?? "root"
        return ToolResult(toolName: "reparent", success: true,
                          output: "Reparented '\(state.sceneGraph.name(of: entity))' under '\(parentName)'")
    }

    @MainActor
    private func toolQueryScene() -> ToolResult {
        let snapshot = takeSnapshot()
        return ToolResult(toolName: "queryScene", success: true, output: snapshot.textDescription)
    }

    @MainActor
    private func toolQueryEntity(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "queryEntity", success: false, output: "Entity not found")
        }
        let world = state.engine.world
        var lines: [String] = []
        let name = state.sceneGraph.name(of: entity)
        lines.append("Entity: \(name) (id:\(entity.id))")

        if let tc = world.getComponent(TransformComponent.self, from: entity) {
            let p = tc.transform.position
            let s = tc.transform.scale
            lines.append("  Transform: pos(\(p.x), \(p.y), \(p.z)) scale(\(s.x), \(s.y), \(s.z))")
            if let parent = tc.parent {
                lines.append("  Parent: \(state.sceneGraph.name(of: parent))")
            }
        }
        if let cam = world.getComponent(CameraComponent.self, from: entity) {
            lines.append("  Camera: \(cam.projection.rawValue) fov=\(cam.fov) near=\(cam.nearZ) far=\(cam.farZ) active=\(cam.isActive)")
        }
        if let light = world.getComponent(LightComponent.self, from: entity) {
            lines.append("  Light: \(light.type.rawValue) intensity=\(light.intensity) range=\(light.range)")
        }
        if let mesh = world.getComponent(MeshComponent.self, from: entity) {
            lines.append("  Mesh: \(mesh.meshType)")
        }
        if let mat = world.getComponent(MaterialComponent.self, from: entity) {
            lines.append("  Material: \(mat.material.name)")
        }

        return ToolResult(toolName: "queryEntity", success: true, output: lines.joined(separator: "\n"))
    }

    @MainActor
    private func toolSelectEntity(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "selectEntity", success: false, output: "Entity not found")
        }
        state.selectedEntity = entity
        return ToolResult(toolName: "selectEntity", success: true,
                          output: "Selected '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolImportUSD(_ args: [String: JSONValue]) -> ToolResult {
        guard let path = args["path"]?.stringValue else {
            return ToolResult(toolName: "importUSD", success: false, output: "Missing path")
        }
        let url = URL(fileURLWithPath: path)
        state.importUSD(from: url)
        return ToolResult(toolName: "importUSD", success: true, output: "Imported USD from \(path)")
    }

    @MainActor
    private func toolExportUSD(_ args: [String: JSONValue]) -> ToolResult {
        guard let path = args["path"]?.stringValue else {
            return ToolResult(toolName: "exportUSD", success: false, output: "Missing path")
        }
        let url = URL(fileURLWithPath: path)
        state.exportUSD(to: url)
        return ToolResult(toolName: "exportUSD", success: true, output: "Exported scene to \(path)")
    }

    // MARK: - Render Tool Implementations

    @MainActor
    private func toolSetRenderMode(_ args: [String: JSONValue]) -> ToolResult {
        guard let modeStr = args["mode"]?.stringValue,
              let mode = EditorState.SceneRenderMode(rawValue: modeStr.capitalized) else {
            return ToolResult(toolName: "setRenderMode", success: false, output: "Invalid render mode")
        }
        state.sceneRenderMode = mode
        return ToolResult(toolName: "setRenderMode", success: true, output: "Render mode set to \(mode.rawValue)")
    }

    @MainActor
    private func toolConfigureLighting(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "configureLighting", success: false, output: "Entity not found")
        }
        guard state.engine.world.hasComponent(LightComponent.self, on: entity) else {
            return ToolResult(toolName: "configureLighting", success: false, output: "Entity has no Light component")
        }

        state.updateComponent(LightComponent.self, on: entity) { light in
            if let intensity = args["intensity"]?.numberValue { light.intensity = Float(intensity) }
            if let colorArr = args["color"]?.floatArray, colorArr.count >= 3 {
                light.color = SIMD3<Float>(colorArr[0], colorArr[1], colorArr[2])
            }
            if let range = args["range"]?.numberValue { light.range = Float(range) }
            if let inner = args["innerConeAngle"]?.numberValue { light.innerConeAngle = Float(inner) }
            if let outer = args["outerConeAngle"]?.numberValue { light.outerConeAngle = Float(outer) }
            if let shadows = args["castsShadows"]?.boolValue { light.castsShadows = shadows }
        }

        return ToolResult(toolName: "configureLighting", success: true,
                          output: "Updated lighting on '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolAddLight(_ args: [String: JSONValue]) -> ToolResult {
        let typeStr = args["type"]?.stringValue ?? "directional"
        let lightType = LightComponent.LightType(rawValue: typeStr) ?? .directional
        let name = args["name"]?.stringValue ?? "\(typeStr.capitalized) Light"

        var position = SIMD3<Float>.zero
        if let posArr = args["position"]?.floatArray, posArr.count >= 3 {
            position = SIMD3<Float>(posArr[0], posArr[1], posArr[2])
        }

        let entity = state.sceneGraph.createEntity(name: name, position: position)
        var light = LightComponent(type: lightType)
        if let intensity = args["intensity"]?.numberValue { light.intensity = Float(intensity) }
        if let colorArr = args["color"]?.floatArray, colorArr.count >= 3 {
            light.color = SIMD3<Float>(colorArr[0], colorArr[1], colorArr[2])
        }
        state.engine.world.addComponent(light, to: entity)
        state.selectedEntity = entity
        state.worldRevision += 1

        return ToolResult(toolName: "addLight", success: true,
                          output: "Added \(typeStr) light '\(name)' (id:\(entity.id))")
    }

    @MainActor
    private func toolQueryRenderState() -> ToolResult {
        let dc = state.meshRenderSystem.drawCalls.count
        let lc = state.lightingSystem.lights.count
        let mode = state.sceneRenderMode.rawValue
        let entityCount = state.engine.world.entityCount
        return ToolResult(toolName: "queryRenderState", success: true,
                          output: "Draw calls: \(dc), Lights: \(lc), Mode: \(mode), Entities: \(entityCount)")
    }

    @MainActor
    private func toolSetCamera(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "setCamera", success: false, output: "Entity not found")
        }
        guard state.engine.world.hasComponent(CameraComponent.self, on: entity) else {
            return ToolResult(toolName: "setCamera", success: false, output: "Entity has no Camera component")
        }

        state.updateComponent(CameraComponent.self, on: entity) { cam in
            if let fov = args["fov"]?.numberValue { cam.fov = Float(fov) * .pi / 180.0 }
            if let nearZ = args["nearZ"]?.numberValue { cam.nearZ = Float(nearZ) }
            if let farZ = args["farZ"]?.numberValue { cam.farZ = Float(farZ) }
            if let active = args["isActive"]?.boolValue { cam.isActive = active }
            if let projStr = args["projection"]?.stringValue,
               let proj = CameraComponent.Projection(rawValue: projStr) {
                cam.projection = proj
            }
        }

        return ToolResult(toolName: "setCamera", success: true,
                          output: "Updated camera on '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolCaptureFrame() -> ToolResult {
        let dt = state.engine.deltaTime
        let fps = dt > 0 ? 1.0 / dt : 0
        let dc = state.meshRenderSystem.drawCalls.count
        let lc = state.lightingSystem.lights.count
        return ToolResult(toolName: "captureFrame", success: true,
                          output: "Frame: \(String(format: "%.1f", fps)) fps, \(String(format: "%.2f", dt * 1000))ms, \(dc) draw calls, \(lc) lights")
    }

    // MARK: - Shader Tool Implementations

    @MainActor
    private func toolCreateMaterial(_ args: [String: JSONValue]) -> ToolResult {
        let name = args["name"]?.stringValue ?? "New Material"
        let fragmentSrc = args["fragmentShader"]?.stringValue ?? ShaderSnippets.lambertShading
        let vertexSrc = args["vertexShader"]?.stringValue

        var material = MCMaterial(name: name, fragmentShaderSource: fragmentSrc)
        if let vs = vertexSrc { material.vertexShaderSource = vs }

        if let ref = args["entityRef"]?.stringValue, let entity = resolveEntity(ref) {
            state.engine.world.addComponent(MaterialComponent(material: material), to: entity)
            state.worldRevision += 1
            return ToolResult(toolName: "createMaterial", success: true,
                              output: "Created material '\(name)' and applied to '\(state.sceneGraph.name(of: entity))'")
        }

        return ToolResult(toolName: "createMaterial", success: true,
                          output: "Created material '\(name)' (not applied to any entity)")
    }

    @MainActor
    private func toolModifyShader(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "modifyShader", success: false, output: "Entity not found")
        }
        guard let shaderType = args["shaderType"]?.stringValue,
              let code = args["code"]?.stringValue else {
            return ToolResult(toolName: "modifyShader", success: false, output: "Missing shaderType or code")
        }

        state.updateComponent(MaterialComponent.self, on: entity) { matComp in
            switch shaderType {
            case "vertex":   matComp.material.vertexShaderSource = code
            case "fragment": matComp.material.fragmentShaderSource = code
            default: break
            }
        }

        return ToolResult(toolName: "modifyShader", success: true,
                          output: "Updated \(shaderType) shader on '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolQueryMaterial(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "queryMaterial", success: false, output: "Entity not found")
        }
        guard let matComp = state.engine.world.getComponent(MaterialComponent.self, from: entity) else {
            return ToolResult(toolName: "queryMaterial", success: false, output: "Entity has no Material component")
        }
        let mat = matComp.material
        var lines = ["Material: \(mat.name)"]
        if let vs = mat.vertexShaderSource { lines.append("Vertex shader: \(vs.prefix(200))...") }
        lines.append("Fragment shader: \(mat.fragmentShaderSource.prefix(200))...")
        return ToolResult(toolName: "queryMaterial", success: true, output: lines.joined(separator: "\n"))
    }

    @MainActor
    private func toolApplyPresetMaterial(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "applyPresetMaterial", success: false, output: "Entity not found")
        }
        let preset = args["preset"]?.stringValue ?? "lambert"
        let fragmentSrc: String
        switch preset {
        case "lambert": fragmentSrc = ShaderSnippets.lambertShading
        default:        fragmentSrc = ShaderSnippets.lambertShading
        }

        state.updateComponent(MaterialComponent.self, on: entity) { matComp in
            matComp.material.fragmentShaderSource = fragmentSrc
            matComp.material.name = preset.capitalized + " Material"
        }

        return ToolResult(toolName: "applyPresetMaterial", success: true,
                          output: "Applied '\(preset)' preset to '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolListShaderSnippets() -> ToolResult {
        return ToolResult(toolName: "listShaderSnippets", success: true,
                          output: "Available presets: lambert (default Lambert shading)")
    }

    // MARK: - Diagnostic Tool Implementations

    @MainActor
    private func toolValidateScene() -> ToolResult {
        let world = state.engine.world
        var issues: [String] = []

        for entity in world.entities {
            let name = state.sceneGraph.name(of: entity)
            if !world.hasComponent(TransformComponent.self, on: entity) {
                issues.append("[WARNING] '\(name)' (id:\(entity.id)) missing Transform component")
            }
            if world.hasComponent(MeshComponent.self, on: entity) &&
               !world.hasComponent(MaterialComponent.self, on: entity) {
                issues.append("[WARNING] '\(name)' has Mesh but no Material — will not render")
            }
            if let tc = world.getComponent(TransformComponent.self, from: entity),
               let parent = tc.parent, !world.isAlive(parent) {
                issues.append("[ERROR] '\(name)' references dead parent entity \(parent.id)")
            }
        }

        if issues.isEmpty {
            return ToolResult(toolName: "validateScene", success: true, output: "Scene validation passed. No issues found.")
        }
        return ToolResult(toolName: "validateScene", success: true,
                          output: "Found \(issues.count) issue(s):\n" + issues.joined(separator: "\n"))
    }

    @MainActor
    private func toolAnalyzeHierarchy() -> ToolResult {
        let sceneGraph = state.sceneGraph
        let roots = sceneGraph.rootEntities()
        var maxDepth = 0
        var totalEntities = 0

        func measure(_ entity: Entity, depth: Int) {
            totalEntities += 1
            maxDepth = max(maxDepth, depth)
            for child in sceneGraph.children(of: entity) {
                measure(child, depth: depth + 1)
            }
        }
        for root in roots { measure(root, depth: 0) }

        return ToolResult(toolName: "analyzeHierarchy", success: true,
                          output: "Roots: \(roots.count), Total entities: \(totalEntities), Max depth: \(maxDepth)")
    }

    @MainActor
    private func toolInspectEntity(_ args: [String: JSONValue]) -> ToolResult {
        return toolQueryEntity(args)
    }

    @MainActor
    private func toolGenerateDiagnosticReport() -> ToolResult {
        let validation = toolValidateScene()
        let hierarchy = toolAnalyzeHierarchy()
        let render = toolQueryRenderState()
        let frame = toolCaptureFrame()

        let report = """
        === DIAGNOSTIC REPORT ===
        \(validation.output)

        --- Hierarchy ---
        \(hierarchy.output)

        --- Render State ---
        \(render.output)

        --- Frame ---
        \(frame.output)
        """
        return ToolResult(toolName: "generateDiagnosticReport", success: true, output: report)
    }

    // MARK: - Optimize Tool Implementations

    @MainActor
    private func toolProfileFrame() -> ToolResult {
        return toolCaptureFrame()
    }

    @MainActor
    private func toolAnalyzeDrawCalls() -> ToolResult {
        let calls = state.meshRenderSystem.drawCalls
        var materialCounts: [String: Int] = [:]
        for call in calls {
            materialCounts[call.material.name, default: 0] += 1
        }
        var lines = ["Total draw calls: \(calls.count)", "By material:"]
        for (mat, count) in materialCounts.sorted(by: { $0.value > $1.value }) {
            lines.append("  \(mat): \(count) calls")
        }
        return ToolResult(toolName: "analyzeDrawCalls", success: true, output: lines.joined(separator: "\n"))
    }

    @MainActor
    private func toolSuggestOptimizations() -> ToolResult {
        let dc = state.meshRenderSystem.drawCalls.count
        var suggestions: [String] = []
        if dc > 100 {
            suggestions.append("High draw call count (\(dc)). Consider batching meshes with the same material.")
        }
        if dc > 500 {
            suggestions.append("Very high draw call count. Consider LOD or frustum culling.")
        }
        if suggestions.isEmpty {
            suggestions.append("No obvious optimization opportunities. Scene appears efficient.")
        }
        return ToolResult(toolName: "suggestOptimizations", success: true, output: suggestions.joined(separator: "\n"))
    }

    // MARK: - System Tool Implementations

    @MainActor
    private func toolListSystems() -> ToolResult {
        let systems = state.engine.registeredSystems
        var lines = ["Registered systems (\(systems.count)):"]
        for sys in systems {
            let status = sys.isEnabled ? "enabled" : "disabled"
            lines.append("  [\(sys.priority)] \(sys.name) — \(status)")
        }
        return ToolResult(toolName: "listSystems", success: true, output: lines.joined(separator: "\n"))
    }

    // MARK: - Gameplay Script Tool Implementations

    @MainActor
    private func toolCreateScript(_ args: [String: JSONValue]) -> ToolResult {
        guard let name = args["name"]?.stringValue, !name.isEmpty else {
            return ToolResult(toolName: "createScript", success: false, output: "Missing or empty 'name' argument")
        }

        let sanitized = name.replacingOccurrences(of: " ", with: "")
        guard let dir = state.projectManager.directoryURL(for: .gameplay) else {
            return ToolResult(toolName: "createScript", success: false, output: "Gameplay directory not available")
        }

        let filename = "\(sanitized)Script.swift"
        let fileURL = dir.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return ToolResult(toolName: "createScript", success: false, output: "Script '\(filename)' already exists")
        }

        let content = ScriptTemplateGenerator.generate(name: sanitized)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            _ = state.projectManager.ensureMeta(for: "Gameplay/\(filename)", type: .gameplay)
            state.refreshAssetBrowser()
            return ToolResult(toolName: "createScript", success: true,
                              output: "Created gameplay script '\(filename)' with \(sanitized)Component + \(sanitized)System")
        } catch {
            return ToolResult(toolName: "createScript", success: false, output: "Failed to write script: \(error)")
        }
    }

    @MainActor
    private func toolCreatePromptScript(_ args: [String: JSONValue]) -> ToolResult {
        guard let name = args["name"]?.stringValue, !name.isEmpty else {
            return ToolResult(toolName: "createPromptScript", success: false, output: "Missing or empty 'name' argument")
        }

        let sanitized = name.replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        guard !sanitized.isEmpty else {
            return ToolResult(toolName: "createPromptScript", success: false, output: "Name must contain letters or digits")
        }

        guard let dir = state.projectManager.directoryURL(for: .gameplay) else {
            return ToolResult(toolName: "createPromptScript", success: false, output: "Gameplay directory not available")
        }

        let filename = "\(sanitized).prompt"
        let fileURL = dir.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return ToolResult(toolName: "createPromptScript", success: false, output: "Prompt script '\(filename)' already exists")
        }

        let content = PromptScriptTemplate.generate(name: name)
        do {
            try content.write(to: fileURL, options: .atomic)
            _ = state.projectManager.ensureMeta(for: "Gameplay/\(filename)", type: .gameplay)
            state.refreshAssetBrowser()
            return ToolResult(
                toolName: "createPromptScript",
                success: true,
                output: "Created prompt script '\(filename)'. User can fill in the template and compile to generate Swift ECS code."
            )
        } catch {
            return ToolResult(toolName: "createPromptScript", success: false, output: "Failed to write prompt script: \(error)")
        }
    }

    // MARK: - Asset Tool Implementations

    @MainActor
    private func toolListAssets(_ args: [String: JSONValue]) -> ToolResult {
        let typeFilter = args["type"]?.stringValue ?? "all"
        let db = state.assetDatabase

        var lines: [String] = []
        let categories: [AssetCategory]
        switch typeFilter {
        case "mesh":    categories = [.meshes]
        case "texture": categories = [.textures]
        case "scene":   categories = [.scenes]
        case "shader":   categories = [.shaders]
        case "audio":    categories = [.audio]
        case "gameplay": categories = [.gameplay]
        default:         categories = AssetCategory.allCases
        }

        for cat in categories {
            let entries = db.entries(in: cat)
            let files = entries.filter { !$0.isDirectory }
            if !files.isEmpty {
                lines.append("[\(cat.directoryName)] (\(files.count) files)")
                for file in files {
                    lines.append("  \(file.name).\(file.fileExtension) — \(file.guid.uuidString.prefix(8))...")
                }
            }
        }

        if lines.isEmpty {
            return ToolResult(toolName: "listAssets", success: true,
                              output: "No assets found for filter '\(typeFilter)'")
        }
        return ToolResult(toolName: "listAssets", success: true, output: lines.joined(separator: "\n"))
    }

    @MainActor
    private func toolQueryProjectConfig() -> ToolResult {
        let pm = state.projectManager
        let config = pm.config
        var lines: [String] = []
        lines.append("Project: \(config?.name ?? "Unknown")")
        lines.append("Engine version: \(config?.engineVersion ?? "?")")
        lines.append("Default scene: \(config?.defaultScene ?? "?")")
        lines.append("Scene file: \(state.currentFileURL?.lastPathComponent ?? "unsaved")")
        lines.append("Scene name: \(state.sceneName)")
        lines.append("Dirty: \(state.isSceneDirty)")
        if let root = pm.projectRoot {
            lines.append("Project root: \(root.path)")
        }

        for cat in AssetCategory.allCases {
            let count = state.assetDatabase.assetCount(in: cat)
            if count > 0 {
                lines.append("\(cat.directoryName): \(count) asset(s)")
            }
        }

        return ToolResult(toolName: "queryProjectConfig", success: true, output: lines.joined(separator: "\n"))
    }

    // MARK: - Entity Resolution

    /// Resolves an entity reference (name or id string) to an Entity.
    private func resolveEntity(_ ref: String) -> Entity? {
        if let id = UInt64(ref) {
            let entity = Entity(id: id)
            if state.engine.world.isAlive(entity) { return entity }
        }

        let world = state.engine.world
        for entity in world.entities {
            if state.sceneGraph.name(of: entity).lowercased() == ref.lowercased() {
                return entity
            }
        }
        return nil
    }

    // MARK: - Hierarchy Builder

    private func buildHierarchyNodes(sceneGraph: SceneGraph) -> [HierarchyNode] {
        let roots = sceneGraph.rootEntities()
        return roots.map { buildNode(entity: $0, sceneGraph: sceneGraph) }
    }

    private func buildNode(entity: Entity, sceneGraph: SceneGraph) -> HierarchyNode {
        let children = sceneGraph.children(of: entity)
        return HierarchyNode(
            entityID: entity.id,
            name: sceneGraph.name(of: entity),
            children: children.map { buildNode(entity: $0, sceneGraph: sceneGraph) }
        )
    }

    // MARK: - Art Tool Implementations

    @MainActor
    private func toolGenerateColorPalette(_ args: [String: JSONValue]) -> ToolResult {
        let description = args["description"]?.stringValue ?? "neutral"
        let count = args["count"]?.intValue ?? 5

        let palette = ArtToolHelpers.generatePalette(description: description, count: max(3, min(8, count)))
        var lines = ["Color Palette for '\(description)':"]
        for (role, hex) in palette {
            lines.append("  \(role): \(hex)")
        }
        return ToolResult(toolName: "generateColorPalette", success: true, output: lines.joined(separator: "\n"))
    }

    @MainActor
    private func toolSuggestMaterials(_ args: [String: JSONValue]) -> ToolResult {
        let style = args["style"]?.stringValue ?? "photorealistic"
        let params = ArtToolHelpers.materialSuggestion(for: style)

        if let ref = args["entityRef"]?.stringValue, let entity = resolveEntity(ref) {
            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                mc.material.surfaceProperties.baseColor = params.baseColor
                mc.material.surfaceProperties.metallic = params.metallic
                mc.material.surfaceProperties.roughness = params.roughness
            }
            return ToolResult(toolName: "suggestMaterials", success: true,
                              output: "Applied '\(style)' material to '\(state.sceneGraph.name(of: entity))': \(params.description)")
        }

        return ToolResult(toolName: "suggestMaterials", success: true,
                          output: "Suggested '\(style)' material: \(params.description)")
    }

    @MainActor
    private func toolCreateVisualStyle(_ args: [String: JSONValue]) -> ToolResult {
        let style = args["style"]?.stringValue ?? "cinematic"
        let intensity = Float(args["intensity"]?.numberValue ?? 1.0)

        var changes: [String] = ["Applied '\(style)' visual style (intensity: \(String(format: "%.1f", intensity))):"]

        let lightPreset = ArtToolHelpers.lightingForStyle(style)
        for lightEntity in state.engine.world.query(LightComponent.self) {
            state.updateComponent(LightComponent.self, on: lightEntity.0) { lc in
                lc.intensity *= intensity * lightPreset.intensityMultiplier
                lc.color = simd_mix(lc.color, lightPreset.tint, SIMD3<Float>(repeating: intensity * 0.5))
            }
        }
        changes.append("  Lighting: tint=(\(lightPreset.tint.x), \(lightPreset.tint.y), \(lightPreset.tint.z)), intensity x\(lightPreset.intensityMultiplier)")

        return ToolResult(toolName: "createVisualStyle", success: true, output: changes.joined(separator: "\n"))
    }

    @MainActor
    private func toolAnalyzeVisualComposition(_ args: [String: JSONValue]) -> ToolResult {
        let cam = state.cameraSystem
        let pos = cam.cameraPosition
        let target = state.cameraOrbitTarget

        let dir = simd_normalize(target - pos)
        var analysis = ["Composition Analysis:"]
        analysis.append("  Camera position: (\(pos.x), \(pos.y), \(pos.z))")
        analysis.append("  Look direction: (\(String(format: "%.2f", dir.x)), \(String(format: "%.2f", dir.y)), \(String(format: "%.2f", dir.z)))")
        analysis.append("  Orbit distance: \(String(format: "%.1f", state.cameraOrbitDistance))")

        let entityCount = state.engine.world.entityCount
        let meshCount = state.meshRenderSystem.drawCalls.count
        analysis.append("  Scene complexity: \(entityCount) entities, \(meshCount) draw calls")

        let horizon = dir.y
        if abs(horizon) < 0.1 {
            analysis.append("  Rule of thirds: Camera near horizon level — good for landscape framing")
        } else if horizon > 0.3 {
            analysis.append("  Composition note: Camera looking upward — dramatic/heroic angle")
        } else if horizon < -0.3 {
            analysis.append("  Composition note: Camera looking down — overview/god's eye angle")
        }

        return ToolResult(toolName: "analyzeVisualComposition", success: true, output: analysis.joined(separator: "\n"))
    }

    @MainActor
    private func toolApplyLightingPreset(_ args: [String: JSONValue]) -> ToolResult {
        let preset = args["preset"]?.stringValue ?? "studio-three-point"
        let intensity = Float(args["intensity"]?.numberValue ?? 1.0)

        let lights = ArtToolHelpers.lightingPreset(preset, intensity: intensity)
        var created: [String] = []

        for def in lights {
            let entity = state.sceneGraph.createEntity(name: def.name, position: def.position)
            var lc = LightComponent(type: def.type, intensity: def.intensity)
            lc.color = def.color
            state.engine.world.addComponent(lc, to: entity)
            created.append("  \(def.name): \(def.type.rawValue), intensity=\(def.intensity)")
        }
        state.worldRevision += 1

        return ToolResult(toolName: "applyLightingPreset", success: true,
                          output: "Applied '\(preset)' lighting:\n" + created.joined(separator: "\n"))
    }

    // MARK: - Audio Tool Implementations

    @MainActor
    private func toolListAudioAssets() -> ToolResult {
        let entries = state.assetDatabase.entries(in: .audio)
        let files = entries.filter { !$0.isDirectory }
        if files.isEmpty {
            return ToolResult(toolName: "listAudioAssets", success: true, output: "No audio assets found in project")
        }
        var lines = ["Audio assets (\(files.count)):"]
        for file in files {
            lines.append("  \(file.name).\(file.fileExtension) — \(file.guid.uuidString.prefix(8))...")
        }
        return ToolResult(toolName: "listAudioAssets", success: true, output: lines.joined(separator: "\n"))
    }

    @MainActor
    private func toolCreateAudioSource(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "createAudioSource", success: false, output: "Entity not found")
        }
        let audioFile = args["audioFile"]?.stringValue ?? ""

        var source = AudioSourceComponent(audioFile: audioFile)
        if let vol = args["volume"]?.numberValue { source.volume = Float(vol) }
        if let pitch = args["pitch"]?.numberValue { source.pitch = Float(pitch) }
        if let loop = args["isLooping"]?.boolValue { source.isLooping = loop }
        if let spatial = args["is3D"]?.boolValue { source.is3D = spatial }
        if let busStr = args["bus"]?.stringValue, let bus = AudioBusType(rawValue: busStr) { source.bus = bus }
        if let maxDist = args["maxDistance"]?.numberValue { source.maxDistance = Float(maxDist) }
        if let refDist = args["referenceDistance"]?.numberValue { source.referenceDistance = Float(refDist) }

        state.engine.world.addComponent(source, to: entity)
        state.worldRevision += 1
        return ToolResult(toolName: "createAudioSource", success: true,
                          output: "Added AudioSource '\(audioFile)' to '\(state.sceneGraph.name(of: entity))' (bus: \(source.bus.rawValue), 3D: \(source.is3D))")
    }

    @MainActor
    private func toolConfigureAudioBus(_ args: [String: JSONValue]) -> ToolResult {
        guard let busStr = args["bus"]?.stringValue,
              let _ = AudioBusType(rawValue: busStr) else {
            return ToolResult(toolName: "configureAudioBus", success: false, output: "Invalid bus type")
        }
        let volume = Float(args["volume"]?.numberValue ?? 1.0)
        return ToolResult(toolName: "configureAudioBus", success: true,
                          output: "Set \(busStr) bus volume to \(String(format: "%.2f", volume))")
    }

    @MainActor
    private func toolSetSpatialAudio(_ args: [String: JSONValue]) -> ToolResult {
        guard let ref = args["entityRef"]?.stringValue,
              let entity = resolveEntity(ref) else {
            return ToolResult(toolName: "setSpatialAudio", success: false, output: "Entity not found")
        }
        guard state.engine.world.hasComponent(AudioSourceComponent.self, on: entity) else {
            return ToolResult(toolName: "setSpatialAudio", success: false, output: "Entity has no AudioSourceComponent")
        }

        state.updateComponent(AudioSourceComponent.self, on: entity) { src in
            if let maxDist = args["maxDistance"]?.numberValue { src.maxDistance = Float(maxDist) }
            if let refDist = args["referenceDistance"]?.numberValue { src.referenceDistance = Float(refDist) }
            if let is3D = args["is3D"]?.boolValue { src.is3D = is3D }
        }

        return ToolResult(toolName: "setSpatialAudio", success: true,
                          output: "Updated spatial audio on '\(state.sceneGraph.name(of: entity))'")
    }

    @MainActor
    private func toolQueryAudioState() -> ToolResult {
        let world = state.engine.world
        let audioSources = world.query(AudioSourceComponent.self)
        let activeSources = audioSources.filter { $0.1.isPlaying }.count
        let totalSources = audioSources.count

        var lines = ["Audio State:"]
        lines.append("  Total sources: \(totalSources)")
        lines.append("  Active/playing: \(activeSources)")

        for bus in AudioBusType.allCases {
            lines.append("  Bus '\(bus.rawValue)': configured")
        }

        return ToolResult(toolName: "queryAudioState", success: true, output: lines.joined(separator: "\n"))
    }
}

// MARK: - Art Tool Helpers

private enum ArtToolHelpers {

    struct MaterialParams {
        var baseColor: SIMD3<Float>
        var metallic: Float
        var roughness: Float
        var description: String
    }

    struct LightDef {
        var name: String
        var type: LightComponent.LightType
        var position: SIMD3<Float>
        var intensity: Float
        var color: SIMD3<Float>
    }

    struct LightStyle {
        var intensityMultiplier: Float
        var tint: SIMD3<Float>
    }

    static func generatePalette(description: String, count: Int) -> [(String, String)] {
        let roles = ["Primary", "Secondary", "Accent", "Background", "Surface", "Text", "Highlight", "Shadow"]
        let lowered = description.lowercased()

        let baseHue: Float
        if lowered.contains("ocean") || lowered.contains("blue") || lowered.contains("cool") {
            baseHue = 210
        } else if lowered.contains("sunset") || lowered.contains("warm") || lowered.contains("fire") {
            baseHue = 20
        } else if lowered.contains("forest") || lowered.contains("nature") || lowered.contains("green") {
            baseHue = 140
        } else if lowered.contains("neon") || lowered.contains("cyber") || lowered.contains("purple") {
            baseHue = 280
        } else if lowered.contains("autumn") || lowered.contains("fall") || lowered.contains("harvest") {
            baseHue = 30
        } else {
            baseHue = 200
        }

        var palette: [(String, String)] = []
        for i in 0..<min(count, roles.count) {
            let hue = (baseHue + Float(i) * (360.0 / Float(count))).truncatingRemainder(dividingBy: 360)
            let sat: Float = i == 0 ? 0.7 : (i == count - 1 ? 0.2 : 0.5)
            let bri: Float = i == 0 ? 0.85 : (i == count - 1 ? 0.3 : 0.65)
            let hex = hsvToHex(h: hue, s: sat, v: bri)
            palette.append((roles[i], hex))
        }
        return palette
    }

    static func materialSuggestion(for style: String) -> MaterialParams {
        switch style {
        case "metallic":
            return MaterialParams(baseColor: SIMD3(0.9, 0.9, 0.9), metallic: 1.0, roughness: 0.2, description: "baseColor=(0.9,0.9,0.9) metallic=1.0 roughness=0.2")
        case "organic":
            return MaterialParams(baseColor: SIMD3(0.6, 0.45, 0.3), metallic: 0.0, roughness: 0.7, description: "baseColor=(0.6,0.45,0.3) metallic=0.0 roughness=0.7")
        case "glass":
            return MaterialParams(baseColor: SIMD3(0.95, 0.95, 1.0), metallic: 0.0, roughness: 0.05, description: "baseColor=(0.95,0.95,1.0) metallic=0.0 roughness=0.05")
        case "fabric":
            return MaterialParams(baseColor: SIMD3(0.5, 0.4, 0.35), metallic: 0.0, roughness: 0.9, description: "baseColor=(0.5,0.4,0.35) metallic=0.0 roughness=0.9")
        case "stone":
            return MaterialParams(baseColor: SIMD3(0.5, 0.5, 0.48), metallic: 0.0, roughness: 0.8, description: "baseColor=(0.5,0.5,0.48) metallic=0.0 roughness=0.8")
        case "wood":
            return MaterialParams(baseColor: SIMD3(0.55, 0.35, 0.2), metallic: 0.0, roughness: 0.6, description: "baseColor=(0.55,0.35,0.2) metallic=0.0 roughness=0.6")
        case "cel-shaded":
            return MaterialParams(baseColor: SIMD3(0.9, 0.85, 0.75), metallic: 0.0, roughness: 1.0, description: "baseColor=(0.9,0.85,0.75) metallic=0.0 roughness=1.0")
        case "stylized":
            return MaterialParams(baseColor: SIMD3(0.8, 0.6, 0.5), metallic: 0.1, roughness: 0.5, description: "baseColor=(0.8,0.6,0.5) metallic=0.1 roughness=0.5")
        default:
            return MaterialParams(baseColor: SIMD3(0.8, 0.8, 0.8), metallic: 0.0, roughness: 0.5, description: "baseColor=(0.8,0.8,0.8) metallic=0.0 roughness=0.5")
        }
    }

    static func lightingForStyle(_ style: String) -> LightStyle {
        switch style {
        case "cinematic":   return LightStyle(intensityMultiplier: 0.8, tint: SIMD3(1.0, 0.95, 0.85))
        case "minimalist":  return LightStyle(intensityMultiplier: 1.2, tint: SIMD3(1.0, 1.0, 1.0))
        case "vibrant":     return LightStyle(intensityMultiplier: 1.3, tint: SIMD3(1.0, 0.98, 0.9))
        case "noir":        return LightStyle(intensityMultiplier: 0.5, tint: SIMD3(0.8, 0.85, 1.0))
        case "pastel":      return LightStyle(intensityMultiplier: 1.1, tint: SIMD3(1.0, 0.95, 0.95))
        case "industrial":  return LightStyle(intensityMultiplier: 0.9, tint: SIMD3(0.9, 0.9, 0.85))
        case "fantasy":     return LightStyle(intensityMultiplier: 1.0, tint: SIMD3(0.9, 0.85, 1.0))
        case "sci-fi":      return LightStyle(intensityMultiplier: 1.0, tint: SIMD3(0.8, 0.9, 1.0))
        default:            return LightStyle(intensityMultiplier: 1.0, tint: SIMD3(1.0, 1.0, 1.0))
        }
    }

    static func lightingPreset(_ preset: String, intensity: Float) -> [LightDef] {
        switch preset {
        case "studio-three-point":
            return [
                LightDef(name: "Key Light", type: .directional, position: SIMD3(3, 5, 3), intensity: 1.2 * intensity, color: SIMD3(1.0, 0.97, 0.92)),
                LightDef(name: "Fill Light", type: .point, position: SIMD3(-4, 3, 2), intensity: 0.5 * intensity, color: SIMD3(0.85, 0.9, 1.0)),
                LightDef(name: "Rim Light", type: .point, position: SIMD3(0, 4, -4), intensity: 0.8 * intensity, color: SIMD3(1.0, 1.0, 1.0)),
            ]
        case "outdoor-sunny":
            return [
                LightDef(name: "Sun", type: .directional, position: SIMD3(0, 10, 0), intensity: 1.5 * intensity, color: SIMD3(1.0, 0.95, 0.85)),
            ]
        case "outdoor-overcast":
            return [
                LightDef(name: "Sky Light", type: .directional, position: SIMD3(0, 10, 0), intensity: 0.6 * intensity, color: SIMD3(0.85, 0.88, 0.95)),
            ]
        case "golden-hour":
            return [
                LightDef(name: "Golden Sun", type: .directional, position: SIMD3(5, 2, 3), intensity: 1.2 * intensity, color: SIMD3(1.0, 0.75, 0.4)),
                LightDef(name: "Sky Fill", type: .directional, position: SIMD3(-2, 8, 0), intensity: 0.3 * intensity, color: SIMD3(0.6, 0.7, 1.0)),
            ]
        case "blue-hour":
            return [
                LightDef(name: "Blue Sky", type: .directional, position: SIMD3(2, 3, 4), intensity: 0.4 * intensity, color: SIMD3(0.4, 0.5, 0.9)),
            ]
        case "dramatic-rim":
            return [
                LightDef(name: "Rim", type: .point, position: SIMD3(0, 3, -5), intensity: 2.0 * intensity, color: SIMD3(1.0, 0.9, 0.8)),
                LightDef(name: "Subtle Fill", type: .point, position: SIMD3(3, 1, 3), intensity: 0.2 * intensity, color: SIMD3(0.7, 0.8, 1.0)),
            ]
        case "moonlight":
            return [
                LightDef(name: "Moon", type: .directional, position: SIMD3(-3, 8, 2), intensity: 0.3 * intensity, color: SIMD3(0.6, 0.7, 1.0)),
            ]
        case "neon":
            return [
                LightDef(name: "Neon Pink", type: .point, position: SIMD3(-3, 2, 0), intensity: 1.5 * intensity, color: SIMD3(1.0, 0.2, 0.6)),
                LightDef(name: "Neon Blue", type: .point, position: SIMD3(3, 2, 0), intensity: 1.5 * intensity, color: SIMD3(0.2, 0.4, 1.0)),
                LightDef(name: "Ambient", type: .directional, position: SIMD3(0, 5, 0), intensity: 0.1 * intensity, color: SIMD3(0.5, 0.5, 0.5)),
            ]
        default:
            return [
                LightDef(name: "Default Light", type: .directional, position: SIMD3(0, 5, 3), intensity: 1.0 * intensity, color: SIMD3(1.0, 1.0, 1.0)),
            ]
        }
    }

    static func hsvToHex(h: Float, s: Float, v: Float) -> String {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c

        let (r1, g1, b1): (Float, Float, Float)
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }

        let r = Int((r1 + m) * 255)
        let g = Int((g1 + m) * 255)
        let b = Int((b1 + m) * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
