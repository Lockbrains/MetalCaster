import Foundation
import simd
import MetalCasterCore

/// Exports an ECS world to USD format.
///
/// Generates USDA (ASCII USD) text files that can be opened by
/// any USD-compatible tool (Reality Composer Pro, Houdini, etc.).
public final class USDExporter {
    
    public init() {}
    
    /// Exports the scene graph to a USDA string.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene graph to export.
    ///   - world: The ECS world containing component data.
    /// - Returns: A USDA formatted string.
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
    
    private func exportEntity(_ entity: Entity, world: World, sceneGraph: SceneGraph, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        let name = sanitizeUSDName(sceneGraph.name(of: entity))
        
        let hasMesh = world.hasComponent(MeshComponent.self, on: entity)
        let primType = hasMesh ? "Mesh" : "Xform"
        
        var usda = "\(pad)def \(primType) \"\(name)\"\n\(pad){\n"
        
        if let tc = world.getComponent(TransformComponent.self, from: entity) {
            let t = tc.transform
            let p = t.position
            usda += "\(pad)    double3 xformOp:translate = (\(p.x), \(p.y), \(p.z))\n"
            
            let s = t.scale
            usda += "\(pad)    double3 xformOp:scale = (\(s.x), \(s.y), \(s.z))\n"
            
            let r = t.rotation
            usda += "\(pad)    quatf xformOp:orient = (\(r.real), \(r.imag.x), \(r.imag.y), \(r.imag.z))\n"
            usda += "\(pad)    uniform token[] xformOpOrder = [\"xformOp:translate\", \"xformOp:orient\", \"xformOp:scale\"]\n"
        }
        
        if let lc = world.getComponent(LightComponent.self, from: entity) {
            usda += exportLight(lc, indent: indent + 1)
        }
        
        for child in sceneGraph.children(of: entity) {
            usda += exportEntity(child, world: world, sceneGraph: sceneGraph, indent: indent + 1)
        }
        
        usda += "\(pad)}\n"
        return usda
    }
    
    private func exportLight(_ lc: LightComponent, indent: Int) -> String {
        let pad = String(repeating: "    ", count: indent)
        var usda = ""
        usda += "\(pad)color3f inputs:color = (\(lc.color.x), \(lc.color.y), \(lc.color.z))\n"
        usda += "\(pad)float inputs:intensity = \(lc.intensity)\n"
        return usda
    }
    
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
