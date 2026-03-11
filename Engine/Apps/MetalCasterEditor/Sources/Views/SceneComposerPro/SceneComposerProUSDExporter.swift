import Foundation
import simd
import MetalCasterScene

/// Exports Scene Composer Pro scenes to USDA format for integration into the engine's scene graph.
enum SceneComposerProUSDExporter {

    /// Exports the full composer scene as USDA text.
    static func exportToUSDA(
        terrain: TerrainComponent?,
        vegetation: VegetationComponent?,
        waterBodies: [WaterBodyComponent],
        sceneName: String
    ) -> String {
        var lines: [String] = []
        lines.append("#usda 1.0")
        lines.append("(")
        lines.append("    defaultPrim = \"SceneComposerRoot\"")
        lines.append("    metersPerUnit = 1")
        lines.append("    upAxis = \"Y\"")
        lines.append("    doc = \"Exported from MetalCaster Scene Composer Pro\"")
        lines.append(")")
        lines.append("")
        lines.append("def Xform \"SceneComposerRoot\"")
        lines.append("{")

        if let t = terrain {
            lines.append(contentsOf: exportTerrain(t))
        }

        if let v = vegetation {
            lines.append(contentsOf: exportVegetation(v))
        }

        for (i, water) in waterBodies.enumerated() {
            lines.append(contentsOf: exportWaterBody(water, index: i))
        }

        lines.append("}")

        return lines.joined(separator: "\n")
    }

    // MARK: - Terrain Export

    private static func exportTerrain(_ terrain: TerrainComponent) -> [String] {
        var lines: [String] = []
        lines.append("")
        lines.append("    def Xform \"Terrain\"")
        lines.append("    {")
        lines.append("        custom uint mc:terrainResolution = \(terrain.heightmapResolution)")
        lines.append("        custom float2 mc:terrainWorldSize = (\(terrain.worldSize.x), \(terrain.worldSize.y))")
        lines.append("        custom float mc:terrainMaxHeight = \(terrain.maxHeight)")
        lines.append("        custom int mc:terrainLODLevels = \(terrain.lodLevels)")

        for (i, noise) in terrain.noiseLayers.enumerated() {
            lines.append("")
            lines.append("        def Xform \"NoiseLayer_\(i)\"")
            lines.append("        {")
            lines.append("            custom string mc:noiseType = \"\(noise.noiseType.rawValue)\"")
            lines.append("            custom float mc:frequency = \(noise.frequency)")
            lines.append("            custom float mc:amplitude = \(noise.amplitude)")
            lines.append("            custom int mc:octaves = \(noise.octaves)")
            lines.append("            custom uint mc:seed = \(noise.seed)")
            lines.append("            custom bool mc:enabled = \(noise.isEnabled ? "true" : "false")")
            lines.append("        }")
        }

        for (i, erosion) in terrain.erosionConfigs.enumerated() {
            lines.append("")
            lines.append("        def Xform \"Erosion_\(i)\"")
            lines.append("        {")
            lines.append("            custom string mc:erosionType = \"\(erosion.type.rawValue)\"")
            lines.append("            custom int mc:iterations = \(erosion.iterations)")
            lines.append("            custom float mc:strength = \(erosion.strength)")
            lines.append("            custom bool mc:enabled = \(erosion.isEnabled ? "true" : "false")")
            lines.append("        }")
        }

        for (i, layer) in terrain.materialLayers.enumerated() {
            lines.append("")
            lines.append("        def Xform \"MaterialLayer_\(i)\"")
            lines.append("        {")
            lines.append("            custom string mc:layerName = \"\(layer.name)\"")
            lines.append("            custom float2 mc:heightRange = (\(layer.heightRange.lowerBound), \(layer.heightRange.upperBound))")
            lines.append("            custom float2 mc:slopeRange = (\(layer.slopeRange.lowerBound), \(layer.slopeRange.upperBound))")
            lines.append("            custom float mc:blendSharpness = \(layer.blendSharpness)")
            if let albedo = layer.albedoTexturePath {
                lines.append("            custom string mc:albedoTexture = \"\(albedo)\"")
            }
            lines.append("        }")
        }

        lines.append("    }")
        return lines
    }

    // MARK: - Vegetation Export

    private static func exportVegetation(_ vegetation: VegetationComponent) -> [String] {
        var lines: [String] = []
        lines.append("")
        lines.append("    def Xform \"Vegetation\"")
        lines.append("    {")
        lines.append("        custom string mc:biomeName = \"\(vegetation.biome.name)\"")
        lines.append("        custom int mc:instanceCount = \(vegetation.instances.count)")

        for (i, inst) in vegetation.instances.prefix(1000).enumerated() {
            lines.append("")
            lines.append("        def Xform \"Instance_\(i)\"")
            lines.append("        {")
            lines.append("            float3 xformOp:translate = (\(inst.position.x), \(inst.position.y), \(inst.position.z))")
            lines.append("            float xformOp:rotateY = \(inst.rotation)")
            lines.append("            float3 xformOp:scale = (\(inst.scale), \(inst.scale), \(inst.scale))")
            lines.append("            uniform token[] xformOpOrder = [\"xformOp:translate\", \"xformOp:rotateY\", \"xformOp:scale\"]")
            lines.append("        }")
        }

        if vegetation.instances.count > 1000 {
            lines.append("        # ... \(vegetation.instances.count - 1000) more instances (truncated in USDA, full data in .mcterrain)")
        }

        lines.append("    }")
        return lines
    }

    // MARK: - Water Export

    private static func exportWaterBody(_ water: WaterBodyComponent, index: Int) -> [String] {
        var lines: [String] = []
        let name = "\(water.waterType.rawValue)_\(index)"
        lines.append("")
        lines.append("    def Xform \"\(name)\"")
        lines.append("    {")
        lines.append("        custom string mc:waterType = \"\(water.waterType.rawValue)\"")
        lines.append("        custom float mc:surfaceHeight = \(water.surfaceHeight)")
        lines.append("        custom float2 mc:extent = (\(water.extent.x), \(water.extent.y))")
        lines.append("        custom float mc:waveAmplitude = \(water.waveAmplitude)")
        lines.append("        custom float mc:waveFrequency = \(water.waveFrequency)")
        lines.append("        custom float3 mc:waterColor = (\(water.color.x), \(water.color.y), \(water.color.z))")
        lines.append("        custom float mc:transparency = \(water.transparency)")
        lines.append("    }")
        return lines
    }

    // MARK: - Save to Disk

    /// Writes the USDA file and returns the URL.
    static func save(
        terrain: TerrainComponent?,
        vegetation: VegetationComponent?,
        waterBodies: [WaterBodyComponent],
        sceneName: String,
        directory: URL
    ) throws -> URL {
        let usda = exportToUSDA(
            terrain: terrain,
            vegetation: vegetation,
            waterBodies: waterBodies,
            sceneName: sceneName
        )

        let sanitized = sceneName.replacingOccurrences(of: " ", with: "_")
        let fileURL = directory.appendingPathComponent("\(sanitized).usda")
        try usda.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
