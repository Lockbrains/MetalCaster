import Foundation
import MetalCasterScene
import UniformTypeIdentifiers

/// Handles serialization and deserialization of `.mcterrain` documents.
enum SceneComposerProDocumentManager {

    // MARK: - Save

    static func save(document: SceneComposerDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    static func load(from url: URL) throws -> SceneComposerDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(SceneComposerDocument.self, from: data)
    }

    // MARK: - Build Document from State

    static func buildDocument(
        name: String,
        terrain: TerrainComponent?,
        vegetation: VegetationComponent?,
        waterBodies: [WaterBodyComponent],
        layers: [ComposerLayer],
        cameraYaw: Float,
        cameraPitch: Float,
        cameraDistance: Float,
        spatialMode: SpatialCoordinateMode
    ) -> SceneComposerDocument {
        var doc = SceneComposerDocument(name: name)
        doc.terrain = terrain
        doc.vegetation = vegetation
        doc.waterBodies = waterBodies
        doc.layers = layers.map { layer in
            SceneComposerDocument.ComposerLayerData(
                name: layer.name,
                kind: layer.kind.rawValue,
                isVisible: layer.isVisible,
                isLocked: layer.isLocked
            )
        }
        doc.cameraYaw = cameraYaw
        doc.cameraPitch = cameraPitch
        doc.cameraDistance = cameraDistance
        doc.spatialMode = spatialMode
        return doc
    }

    // MARK: - Restore State from Document

    static func restoreLayers(from doc: SceneComposerDocument) -> [ComposerLayer] {
        doc.layers.compactMap { data in
            guard let kind = ComposerLayer.LayerKind(rawValue: data.kind) else { return nil }
            var layer = ComposerLayer(name: data.name, kind: kind)
            layer.isVisible = data.isVisible
            layer.isLocked = data.isLocked
            return layer
        }
    }
}

// MARK: - UTType for .mcterrain

extension UTType {
    static let mcterrain = UTType(exportedAs: "com.metalcaster.mcterrain")
}

// MARK: - Notification Names

extension NSNotification.Name {
    static let sceneComposerNew = NSNotification.Name("sceneComposerNew")
    static let sceneComposerSave = NSNotification.Name("sceneComposerSave")
    static let sceneComposerSaveAs = NSNotification.Name("sceneComposerSaveAs")
    static let sceneComposerOpen = NSNotification.Name("sceneComposerOpen")
    static let sceneComposerExportUSDA = NSNotification.Name("sceneComposerExportUSDA")
}
