import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterAudio
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
    
    // MARK: - USDA Scene Loading (with sidecar)
    
    /// Loads a MetalCaster scene from a `.usda` file with its `.mcmeta` sidecar.
    /// The USDA provides geometry/hierarchy; the sidecar restores engine-specific data.
    public func loadScene(
        from usdaURL: URL,
        into world: World,
        sceneGraph: SceneGraph
    ) throws {
        let usdaString = try String(contentsOf: usdaURL, encoding: .utf8)
        
        world.clear()
        
        let sidecarURL = usdaURL.deletingPathExtension().appendingPathExtension("mcmeta")
        var sidecar: SceneSidecar? = nil
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            let data = try Data(contentsOf: sidecarURL)
            sidecar = try JSONDecoder().decode(SceneSidecar.self, from: data)
        }
        
        let sidecarLookup = buildSidecarLookup(sidecar)
        let lines = usdaString.components(separatedBy: .newlines)
        
        parsePrims(lines: lines, into: world, sceneGraph: sceneGraph, sidecarMap: sidecarLookup, parent: nil)
    }
    
    // MARK: - USDA Parser
    
    private func parsePrims(
        lines: [String],
        into world: World,
        sceneGraph: SceneGraph,
        sidecarMap: SidecarLookup,
        parent: Entity?
    ) {
        var i = 0
        
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            
            if let (primType, primName) = parseDefLine(trimmed) {
                i += 1
                let (blockContent, endIndex) = extractBlock(lines: lines, from: i)
                i = endIndex
                
                let isRoot = (primName == "Root" && primType == "Xform")
                let childParent: Entity?
                
                if isRoot {
                    childParent = nil
                } else {
                    childParent = createEntityFromPrim(
                        primType: primType,
                        primName: primName,
                        propertyLines: blockContent,
                        world: world,
                        sceneGraph: sceneGraph,
                        sidecarMap: sidecarMap,
                        parent: parent
                    )
                }
                
                parsePrims(
                    lines: blockContent,
                    into: world,
                    sceneGraph: sceneGraph,
                    sidecarMap: sidecarMap,
                    parent: childParent
                )
            } else {
                i += 1
            }
        }
    }
    
    private func parseDefLine(_ line: String) -> (String, String)? {
        let pattern = #"^def\s+(\w+)\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3 else { return nil }
        
        let primType = String(line[Range(match.range(at: 1), in: line)!])
        let primName = String(line[Range(match.range(at: 2), in: line)!])
        return (primType, primName)
    }
    
    /// Finds the `{` ... `}` block starting at `start`, returns the content
    /// lines (excluding braces) and the index after the closing `}`.
    private func extractBlock(lines: [String], from start: Int) -> ([String], Int) {
        var depth = 0
        var content: [String] = []
        var i = start
        var collecting = false
        
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            
            if trimmed == "{" || trimmed.hasSuffix("{") {
                depth += 1
                if depth == 1 {
                    collecting = true
                    i += 1
                    continue
                }
            }
            if trimmed == "}" {
                depth -= 1
                if depth == 0 {
                    i += 1
                    return (content, i)
                }
            }
            if collecting {
                content.append(lines[i])
            }
            i += 1
        }
        return (content, i)
    }
    
    private func createEntityFromPrim(
        primType: String,
        primName: String,
        propertyLines: [String],
        world: World,
        sceneGraph: SceneGraph,
        sidecarMap: SidecarLookup,
        parent: Entity?
    ) -> Entity {
        // Recover original display name from sidecar if available
        let entityID = parseEntityID(from: propertyLines)
        let meta = sidecarMap.lookup(entityID: entityID, primName: primName)
        let displayName = meta?.entityName ?? primName.replacingOccurrences(of: "_", with: " ")
        let entity = sceneGraph.createEntity(name: displayName, parent: parent)
        
        if let transform = parseTransform(from: propertyLines) {
            var tc = world.getComponent(TransformComponent.self, from: entity)!
            tc.transform = transform
            world.addComponent(tc, to: entity)
        }
        
        switch primType {
        case "Camera":
            let cam = meta?.camera ?? parseCameraFromLines(propertyLines)
            world.addComponent(cam, to: entity)
            
        case "DistantLight":
            var lc = parseLightFromLines(propertyLines)
            lc.type = .directional
            world.addComponent(lc, to: entity)
            
        case "SphereLight":
            var lc = parseLightFromLines(propertyLines)
            lc.type = .point
            world.addComponent(lc, to: entity)
            
        case "DiskLight":
            var lc = parseLightFromLines(propertyLines)
            lc.type = .spot
            world.addComponent(lc, to: entity)
            
        case "Mesh":
            let meshType = parseMeshType(from: propertyLines)
            var meshComp = MeshComponent(meshType: meshType)
            meshComp.castsShadows = parseBoolValue(from: propertyLines, key: "mc:castsShadows") ?? true
            meshComp.receivesShadows = parseBoolValue(from: propertyLines, key: "mc:receivesShadows") ?? true
            world.addComponent(meshComp, to: entity)
            
            let material: MCMaterial
            if let mat = meta?.material {
                material = mat
            } else {
                material = MCMaterial(
                    name: "\(displayName) Material",
                    fragmentShaderSource: ShaderSnippets.lambertShading
                )
            }
            world.addComponent(MaterialComponent(material: material), to: entity)
            
        case "Xform":
            if let mgr = meta?.manager {
                world.addComponent(mgr, to: entity)
            }
            if let sky = meta?.skybox {
                world.addComponent(sky, to: entity)
            }
            if let ppv = meta?.postProcessVolume {
                world.addComponent(ppv, to: entity)
            }
            
        default:
            break
        }

        if let scriptRef = meta?.gameplayScriptRef {
            world.addComponent(scriptRef, to: entity)
        }
        if let audioSource = meta?.audioSource {
            world.addComponent(audioSource, to: entity)
        }
        if let audioListener = meta?.audioListener {
            world.addComponent(audioListener, to: entity)
        }
        if let lod = meta?.lod {
            world.addComponent(lod, to: entity)
        }
        if let physicsBody = meta?.physicsBody {
            world.addComponent(physicsBody, to: entity)
        }
        if let collider = meta?.collider {
            world.addComponent(collider, to: entity)
        }
        if let uiCanvas = meta?.uiCanvas {
            world.addComponent(uiCanvas, to: entity)
        }
        if let uiElement = meta?.uiElement {
            world.addComponent(uiElement, to: entity)
        }
        if let uiLabel = meta?.uiLabel {
            world.addComponent(uiLabel, to: entity)
        }
        if let uiImage = meta?.uiImage {
            world.addComponent(uiImage, to: entity)
        }
        if let uiPanel = meta?.uiPanel {
            world.addComponent(uiPanel, to: entity)
        }
        if let lightmap = meta?.lightmap {
            world.addComponent(lightmap, to: entity)
        }
        if let lightProbe = meta?.lightProbe {
            world.addComponent(lightProbe, to: entity)
        }
        if let reflectionProbe = meta?.reflectionProbe {
            world.addComponent(reflectionProbe, to: entity)
        }
        if let heightFog = meta?.heightFog {
            world.addComponent(heightFog, to: entity)
        }
        
        return entity
    }
    
    // MARK: - Line Parsers
    
    private func parseTransform(from lines: [String]) -> MCTransform? {
        var position: SIMD3<Float>?
        var scale: SIMD3<Float>?
        var rotation: simd_quatf?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.contains("xformOp:translate") && !trimmed.contains("xformOpOrder") {
                position = parseFloat3(from: trimmed)
            }
            if trimmed.contains("xformOp:scale") && !trimmed.contains("xformOpOrder") {
                scale = parseFloat3(from: trimmed)
            }
            if trimmed.contains("xformOp:orient") && !trimmed.contains("xformOpOrder") {
                rotation = parseQuat(from: trimmed)
            }
        }
        
        guard position != nil || scale != nil || rotation != nil else { return nil }
        
        var t = MCTransform()
        if let p = position { t.position = p }
        if let s = scale { t.scale = s }
        if let r = rotation { t.rotation = r }
        return t
    }
    
    private func parseLightFromLines(_ lines: [String]) -> LightComponent {
        var lc = LightComponent()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("inputs:color") {
                if let v = parseFloat3(from: trimmed) {
                    lc.color = v
                }
            }
            if trimmed.contains("inputs:intensity") {
                if let v = parseFloatValue(from: trimmed) {
                    lc.intensity = v
                }
            }
            if trimmed.contains("inputs:radius") {
                if let v = parseFloatValue(from: trimmed) {
                    lc.range = v
                }
            }
        }
        return lc
    }
    
    private func parseCameraFromLines(_ lines: [String]) -> CameraComponent {
        var cc = CameraComponent()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Base properties
            if trimmed.contains("mc:fov") && !trimmed.contains("mc:focalLength") {
                if let v = parseFloatValue(from: trimmed) {
                    cc.fov = v * .pi / 180.0
                }
            }
            if trimmed.contains("mc:orthoSize") {
                if let v = parseFloatValue(from: trimmed) { cc.orthoSize = v }
            }
            if trimmed.contains("mc:projection") {
                if let v = parseStringValue(from: trimmed) {
                    cc.projection = CameraComponent.Projection(rawValue: v) ?? .perspective
                }
            }
            if trimmed.contains("mc:isActive") {
                cc.isActive = trimmed.contains("true")
            }
            if trimmed.contains("clippingRange") {
                if let range = parseFloat2(from: trimmed) {
                    cc.nearZ = range.x
                    cc.farZ = range.y
                }
            }

            // Physical camera properties
            if trimmed.contains("mc:usePhysical") {
                cc.usePhysicalProperties = trimmed.contains("true")
            }
            if trimmed.contains("mc:sensorPreset") {
                if let v = parseStringValue(from: trimmed) {
                    cc.sensorPreset = SensorPreset(rawValue: v) ?? .fullFrame
                }
            }
            if trimmed.contains("mc:focalLength") {
                if let v = parseFloatValue(from: trimmed) { cc.focalLength = v }
            }
            if trimmed.contains("mc:aperture") {
                if let v = parseFloatValue(from: trimmed) { cc.aperture = v }
            }
            if trimmed.contains("mc:iso") {
                if let v = parseFloatValue(from: trimmed) { cc.iso = v }
            }
            if trimmed.contains("mc:shutterSpeed") {
                if let v = parseFloatValue(from: trimmed) { cc.shutterSpeed = v }
            }
            if trimmed.contains("mc:focusDistance") {
                if let v = parseFloatValue(from: trimmed) { cc.focusDistance = v }
            }
            if trimmed.contains("mc:shutterAngle") {
                if let v = parseFloatValue(from: trimmed) { cc.shutterAngle = v }
            }

            // Rendering settings
            if trimmed.contains("mc:allowPostProcessing") {
                cc.allowPostProcessing = trimmed.contains("true")
            }
            if trimmed.contains("mc:allowHDR") {
                cc.allowHDR = trimmed.contains("true")
            }
            if trimmed.contains("mc:backgroundType") {
                if let v = parseStringValue(from: trimmed) {
                    cc.backgroundType = CameraBackgroundType(rawValue: v) ?? .solidColor
                }
            }
            if trimmed.contains("mc:renderingPriority") {
                if let v = parseFloatValue(from: trimmed) { cc.renderingPriority = Int(v) }
            }
        }
        return cc
    }
    
    private func parseMeshType(from lines: [String]) -> MeshType {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("mc:meshType") {
                if let val = parseStringValue(from: trimmed) {
                    switch val {
                    case "sphere": return .sphere
                    case "cube": return .cube
                    case "plane": return .plane
                    case "cylinder": return .cylinder
                    case "cone": return .cone
                    case "capsule": return .capsule
                    default:
                        if val.hasPrefix("custom:") { break }
                        if val.hasPrefix("asset:") {
                            let uuidStr = String(val.dropFirst("asset:".count))
                            if let uuid = UUID(uuidString: uuidStr) { return .asset(uuid) }
                        }
                    }
                }
            }
        }
        return .sphere
    }
    
    // MARK: - Value Parsers
    
    private func parseFloat3(from line: String) -> SIMD3<Float>? {
        guard let openParen = line.lastIndex(of: "("),
              let closeParen = line.lastIndex(of: ")") else { return nil }
        let inner = line[line.index(after: openParen)..<closeParen]
        let parts = inner.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return SIMD3<Float>(parts[0], parts[1], parts[2])
    }
    
    private func parseFloat2(from line: String) -> SIMD2<Float>? {
        guard let openParen = line.lastIndex(of: "("),
              let closeParen = line.lastIndex(of: ")") else { return nil }
        let inner = line[line.index(after: openParen)..<closeParen]
        let parts = inner.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2 else { return nil }
        return SIMD2<Float>(parts[0], parts[1])
    }
    
    private func parseQuat(from line: String) -> simd_quatf? {
        guard let openParen = line.lastIndex(of: "("),
              let closeParen = line.lastIndex(of: ")") else { return nil }
        let inner = line[line.index(after: openParen)..<closeParen]
        let parts = inner.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 4 else { return nil }
        return simd_quatf(real: parts[0], imag: SIMD3<Float>(parts[1], parts[2], parts[3]))
    }
    
    private func parseFloatValue(from line: String) -> Float? {
        let parts = line.split(separator: "=")
        guard parts.count >= 2 else { return nil }
        return Float(parts.last!.trimmingCharacters(in: .whitespaces))
    }
    
    private func parseBoolValue(from lines: [String], key: String) -> Bool? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(key) {
                if trimmed.hasSuffix("true") { return true }
                if trimmed.hasSuffix("false") { return false }
            }
        }
        return nil
    }
    
    private func parseStringValue(from line: String) -> String? {
        guard let firstQuote = line.lastIndex(of: "\"") else { return nil }
        let beforeLast = line[line.startIndex..<firstQuote]
        guard let secondQuote = beforeLast.lastIndex(of: "\"") else { return nil }
        return String(line[line.index(after: secondQuote)..<firstQuote])
    }
    
    // MARK: - Entity ID Parser

    private func parseEntityID(from lines: [String]) -> UInt64? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("mc:entityID") {
                let parts = trimmed.split(separator: "=")
                guard parts.count >= 2 else { continue }
                let valStr = parts.last!.trimmingCharacters(in: .whitespaces)
                return UInt64(valStr)
            }
        }
        return nil
    }

    // MARK: - Sidecar Helpers

    /// Dual-key lookup: entity ID (primary, unique) → prim name (fallback for legacy sidecars).
    struct SidecarLookup {
        var byID: [UInt64: SceneSidecar.EntityMeta] = [:]
        var byPrimName: [String: SceneSidecar.EntityMeta] = [:]

        func lookup(entityID: UInt64?, primName: String) -> SceneSidecar.EntityMeta? {
            if let eid = entityID, let meta = byID[eid] { return meta }
            return byPrimName[primName]
        }
    }

    private func buildSidecarLookup(_ sidecar: SceneSidecar?) -> SidecarLookup {
        guard let sidecar = sidecar else { return SidecarLookup() }
        var lookup = SidecarLookup()
        for entry in sidecar.entities {
            if let eid = entry.entityID {
                lookup.byID[eid] = entry
            }
            // Prim name fallback (for legacy or as secondary key)
            if let pn = entry.primName {
                lookup.byPrimName[pn] = entry
            } else {
                var sanitized = entry.entityName
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "-", with: "_")
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
                sanitized = sanitized.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
                if sanitized.isEmpty { sanitized = "unnamed" }
                if let first = sanitized.first, first.isNumber { sanitized = "_" + sanitized }
                lookup.byPrimName[sanitized] = entry
            }
        }
        return lookup
    }
}
