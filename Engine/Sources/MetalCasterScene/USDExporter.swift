import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// Exports an ECS world to USD format.
///
/// Generates USDA (ASCII USD) text files that can be opened by
/// any USD-compatible tool (Reality Composer Pro, Houdini, etc.).
/// Engine-specific metadata is written to a companion `.mcmeta` sidecar.
public final class USDExporter {
    
    public init() {}
    
    // MARK: - USDA Export
    
    public func exportToUSDA(sceneGraph: SceneGraph, world: World) -> String {
        var usda = "#usda 1.0\n"
        usda += "(\n"
        usda += "    defaultPrim = \"Root\"\n"
        usda += "    metersPerUnit = 1.0\n"
        usda += "    upAxis = \"Y\"\n"
        usda += ")\n\n"
        
        usda += "def Xform \"Root\"\n{\n"
        
        for root in sceneGraph.rootEntities() {
            usda += exportEntity(root, world: world, sceneGraph: sceneGraph, indent: 1)
        }
        
        usda += "}\n"
        return usda
    }
    
    /// Writes a USDA file to disk.
    public func writeUSDA(sceneGraph: SceneGraph, world: World, to url: URL) throws {
        let usda = exportToUSDA(sceneGraph: sceneGraph, world: world)
        try usda.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Sidecar Metadata Export
    
    public func exportSidecar(sceneGraph: SceneGraph, world: World) throws -> Data {
        var sidecar = SceneSidecar()
        
        for (entity, _) in world.query(TransformComponent.self) {
            var entry = SceneSidecar.EntityMeta(entityName: sceneGraph.name(of: entity))
            
            if let mat = world.getComponent(MaterialComponent.self, from: entity) {
                entry.material = mat.material
            }
            if let cam = world.getComponent(CameraComponent.self, from: entity) {
                entry.camera = cam
            }
            if let mgr = world.getComponent(ManagerComponent.self, from: entity) {
                entry.manager = mgr
            }
            if let sky = world.getComponent(SkyboxComponent.self, from: entity) {
                entry.skybox = sky
            }
            
            sidecar.entities.append(entry)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sidecar)
    }
    
    /// Writes both `.usda` and `.mcmeta` sidecar for a scene.
    public func writeScene(sceneGraph: SceneGraph, world: World, to usdaURL: URL) throws {
        try writeUSDA(sceneGraph: sceneGraph, world: world, to: usdaURL)
        
        let sidecarURL = usdaURL.deletingPathExtension().appendingPathExtension("mcmeta")
        let sidecarData = try exportSidecar(sceneGraph: sceneGraph, world: world)
        try sidecarData.write(to: sidecarURL, options: .atomic)
    }
    
    // MARK: - Entity Export
    
    private func exportEntity(_ entity: Entity, world: World, sceneGraph: SceneGraph, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        let name = sanitizeUSDName(sceneGraph.name(of: entity))
        
        let primType = usdPrimType(for: entity, world: world)
        
        var usda = "\(pad)def \(primType) \"\(name)\"\n\(pad){\n"
        
        if let tc = world.getComponent(TransformComponent.self, from: entity) {
            usda += exportTransform(tc, indent: indent + 1)
        }
        
        if let mc = world.getComponent(MeshComponent.self, from: entity) {
            usda += exportMesh(mc, indent: indent + 1)
        }
        
        if let lc = world.getComponent(LightComponent.self, from: entity) {
            usda += exportLight(lc, indent: indent + 1)
        }
        
        if let cc = world.getComponent(CameraComponent.self, from: entity) {
            usda += exportCamera(cc, indent: indent + 1)
        }
        
        if let mgr = world.getComponent(ManagerComponent.self, from: entity) {
            usda += exportManager(mgr, indent: indent + 1)
        }
        
        for child in sceneGraph.children(of: entity) {
            usda += exportEntity(child, world: world, sceneGraph: sceneGraph, indent: indent + 1)
        }
        
        usda += "\(pad)}\n"
        return usda
    }
    
    private func usdPrimType(for entity: Entity, world: World) -> String {
        if world.hasComponent(CameraComponent.self, on: entity) {
            return "Camera"
        }
        if let lc = world.getComponent(LightComponent.self, from: entity) {
            switch lc.type {
            case .directional: return "DistantLight"
            case .point: return "SphereLight"
            case .spot: return "DiskLight"
            }
        }
        if world.hasComponent(MeshComponent.self, on: entity) {
            return "Mesh"
        }
        return "Xform"
    }
    
    // MARK: - Component Export Helpers
    
    private func exportTransform(_ tc: TransformComponent, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var usda = ""
        let t = tc.transform
        let p = t.position
        usda += "\(pad)double3 xformOp:translate = (\(p.x), \(p.y), \(p.z))\n"
        
        let s = t.scale
        usda += "\(pad)double3 xformOp:scale = (\(s.x), \(s.y), \(s.z))\n"
        
        let r = t.rotation
        usda += "\(pad)quatf xformOp:orient = (\(r.real), \(r.imag.x), \(r.imag.y), \(r.imag.z))\n"
        usda += "\(pad)uniform token[] xformOpOrder = [\"xformOp:translate\", \"xformOp:orient\", \"xformOp:scale\"]\n"
        return usda
    }
    
    private func exportMesh(_ mc: MeshComponent, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var usda = ""
        
        let typeName: String
        switch mc.meshType {
        case .sphere: typeName = "sphere"
        case .cube: typeName = "cube"
        case .plane: typeName = "plane"
        case .cylinder: typeName = "cylinder"
        case .cone: typeName = "cone"
        case .capsule: typeName = "capsule"
        case .custom(let url): typeName = "custom:\(url.lastPathComponent)"
        case .asset(let guid): typeName = "asset:\(guid.uuidString)"
        }
        usda += "\(pad)custom string mc:meshType = \"\(typeName)\"\n"
        usda += "\(pad)custom bool mc:castsShadows = \(mc.castsShadows)\n"
        usda += "\(pad)custom bool mc:receivesShadows = \(mc.receivesShadows)\n"
        return usda
    }
    
    private func exportLight(_ lc: LightComponent, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var usda = ""
        usda += "\(pad)color3f inputs:color = (\(lc.color.x), \(lc.color.y), \(lc.color.z))\n"
        usda += "\(pad)float inputs:intensity = \(lc.intensity)\n"
        if lc.type == .point || lc.type == .spot {
            usda += "\(pad)float inputs:radius = \(lc.range)\n"
        }
        if lc.type == .spot {
            usda += "\(pad)float inputs:shaping:cone:angle = \(lc.outerConeAngle * 180.0 / .pi)\n"
            usda += "\(pad)float inputs:shaping:cone:softness = \(lc.innerConeAngle / max(lc.outerConeAngle, 0.001))\n"
        }
        usda += "\(pad)custom bool mc:castsShadows = \(lc.castsShadows)\n"
        return usda
    }
    
    private func exportCamera(_ cc: CameraComponent, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var usda = ""

        // USD-standard camera attributes
        usda += "\(pad)float focalLength = \(cc.focalLength)\n"
        usda += "\(pad)float horizontalAperture = \(cc.sensorSizeMM.x)\n"
        usda += "\(pad)float verticalAperture = \(cc.sensorSizeMM.y)\n"
        usda += "\(pad)float fStop = \(cc.aperture)\n"
        usda += "\(pad)float focusDistance = \(cc.focusDistance)\n"
        usda += "\(pad)float2 clippingRange = (\(cc.nearZ), \(cc.farZ))\n"

        // Engine-specific metadata
        let fovDeg = cc.fov * 180.0 / .pi
        usda += "\(pad)custom string mc:projection = \"\(cc.projection.rawValue)\"\n"
        usda += "\(pad)custom float mc:fov = \(fovDeg)\n"
        usda += "\(pad)custom float mc:orthoSize = \(cc.orthoSize)\n"
        usda += "\(pad)custom bool mc:isActive = \(cc.isActive)\n"
        usda += "\(pad)custom bool mc:usePhysical = \(cc.usePhysicalProperties)\n"
        usda += "\(pad)custom string mc:sensorPreset = \"\(cc.sensorPreset.rawValue)\"\n"
        usda += "\(pad)custom float mc:focalLength = \(cc.focalLength)\n"
        usda += "\(pad)custom float mc:aperture = \(cc.aperture)\n"
        usda += "\(pad)custom float mc:iso = \(cc.iso)\n"
        usda += "\(pad)custom float mc:shutterSpeed = \(cc.shutterSpeed)\n"
        usda += "\(pad)custom float mc:focusDistance = \(cc.focusDistance)\n"
        usda += "\(pad)custom float mc:shutterAngle = \(cc.shutterAngle)\n"
        usda += "\(pad)custom bool mc:allowPostProcessing = \(cc.allowPostProcessing)\n"
        usda += "\(pad)custom bool mc:allowHDR = \(cc.allowHDR)\n"
        usda += "\(pad)custom string mc:backgroundType = \"\(cc.backgroundType.rawValue)\"\n"
        usda += "\(pad)custom int mc:renderingPriority = \(cc.renderingPriority)\n"

        return usda
    }
    
    private func exportManager(_ mgr: ManagerComponent, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        return "\(pad)custom string mc:managerType = \"\(mgr.managerType.rawValue)\"\n"
    }
    
    // MARK: - Utilities
    
    private func sanitizeUSDName(_ name: String) -> String {
        var result = name.replacingOccurrences(of: " ", with: "_")
        result = result.replacingOccurrences(of: "-", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        result = result.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        if result.isEmpty { result = "unnamed" }
        if let first = result.first, first.isNumber { result = "_" + result }
        return result
    }
}

// MARK: - Sidecar Data Model

/// Engine-specific metadata stored alongside USDA scene files.
/// Contains data that USD cannot natively represent (shader source, material params, etc.).
public struct SceneSidecar: Codable {
    public var version: Int = 1
    public var entities: [EntityMeta] = []
    
    public struct EntityMeta: Codable {
        public var entityName: String
        public var material: MCMaterial?
        public var camera: CameraComponent?
        public var manager: ManagerComponent?
        public var skybox: SkyboxComponent?
    }
}
