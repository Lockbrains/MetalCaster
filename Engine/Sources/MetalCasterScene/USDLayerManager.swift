import Foundation
import MetalCasterCore

/// A single scene layer in the USD layer stack.
/// Each layer is a separate `.usda` file that can override properties from layers below.
public struct SceneLayer: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var filePath: String
    public var isEnabled: Bool
    public var order: Int

    public init(name: String, filePath: String, isEnabled: Bool = true, order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.filePath = filePath
        self.isEnabled = isEnabled
        self.order = order
    }
}

/// Manages a stack of USD layers for non-destructive, composable scene editing.
///
/// Each layer is an independent `.usda` file. Layers higher in the stack override
/// properties from layers below via USD `over` prims. The manager provides:
/// - Layer creation, deletion, reordering, and enable/disable
/// - USDA generation with `subLayers` composition
/// - Layer flattening (merge all into one USDA)
/// - Layer diff (compare prim properties between two layers)
///
/// V1 uses text-level USDA manipulation rather than a full USD composition engine.
public final class USDLayerManager {

    /// The root directory where layer files are stored.
    public let layerDirectory: URL

    /// The ordered layer stack (lowest index = highest priority).
    public private(set) var layers: [SceneLayer] = []

    public init(layerDirectory: URL) {
        self.layerDirectory = layerDirectory
        try? FileManager.default.createDirectory(at: layerDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Layer Stack Operations

    /// Adds a new empty layer to the top of the stack.
    @discardableResult
    public func addLayer(name: String) -> SceneLayer {
        let fileName = sanitizeFileName(name) + ".usda"
        let filePath = fileName
        let fullURL = layerDirectory.appendingPathComponent(filePath)

        let emptyUSDA = generateEmptyLayer(name: name)
        try? emptyUSDA.write(to: fullURL, atomically: true, encoding: .utf8)

        let layer = SceneLayer(name: name, filePath: filePath, isEnabled: true, order: layers.count)
        layers.append(layer)
        return layer
    }

    /// Removes a layer from the stack and optionally deletes the file.
    public func removeLayer(id: UUID, deleteFile: Bool = false) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let layer = layers.remove(at: index)
        reindex()
        if deleteFile {
            let url = layerDirectory.appendingPathComponent(layer.filePath)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a layer to a new position in the stack.
    public func moveLayer(from: Int, to: Int) {
        guard from != to, from >= 0, from < layers.count, to >= 0, to < layers.count else { return }
        let layer = layers.remove(at: from)
        layers.insert(layer, at: to)
        reindex()
    }

    /// Toggles a layer's enabled state.
    public func toggleLayer(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].isEnabled.toggle()
    }

    /// Renames a layer (updates metadata only; does not rename the file).
    public func renameLayer(id: UUID, newName: String) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].name = newName
    }

    // MARK: - USDA Composition

    /// Generates a root USDA that references all enabled layers via `subLayers`.
    public func generateComposedUSDA() -> String {
        let enabledLayers = layers.filter(\.isEnabled)

        var usda = "#usda 1.0\n"
        usda += "(\n"
        usda += "    defaultPrim = \"Root\"\n"
        usda += "    metersPerUnit = 1.0\n"
        usda += "    upAxis = \"Y\"\n"

        if !enabledLayers.isEmpty {
            usda += "    subLayers = [\n"
            for layer in enabledLayers {
                usda += "        @./\(layer.filePath)@,\n"
            }
            usda += "    ]\n"
        }

        usda += ")\n\n"
        usda += "def Xform \"Root\"\n{\n}\n"
        return usda
    }

    /// Writes the composed USDA to a file.
    public func writeComposedUSDA(to url: URL) throws {
        let usda = generateComposedUSDA()
        try usda.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Layer Content

    /// Reads the USDA content of a layer.
    public func readLayerContent(id: UUID) -> String? {
        guard let layer = layers.first(where: { $0.id == id }) else { return nil }
        let url = layerDirectory.appendingPathComponent(layer.filePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Writes USDA content to a layer file.
    public func writeLayerContent(id: UUID, content: String) throws {
        guard let layer = layers.first(where: { $0.id == id }) else { return }
        let url = layerDirectory.appendingPathComponent(layer.filePath)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Appends an `over` prim to a layer, overriding a specific property.
    public func appendOverride(layerID: UUID, primPath: String, property: String, value: String) throws {
        guard let layer = layers.first(where: { $0.id == layerID }) else { return }
        let url = layerDirectory.appendingPathComponent(layer.filePath)
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? generateEmptyLayer(name: layer.name)

        let closingBrace = content.range(of: "}", options: .backwards)
        let insertPoint = closingBrace?.lowerBound ?? content.endIndex

        let overPrim = """

            over Xform "\(primPath)"
            {
                \(property) = \(value)
            }

        """

        content.insert(contentsOf: overPrim, at: insertPoint)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Flatten

    /// Flattens all enabled layers into a single USDA string.
    /// Properties from higher-priority layers (lower index) win.
    public func flatten() -> String {
        let enabledLayers = layers.filter(\.isEnabled)
        var allProperties: [String: [String: String]] = [:]

        for layer in enabledLayers.reversed() {
            let url = layerDirectory.appendingPathComponent(layer.filePath)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let prims = parsePrimProperties(from: content)
            for (primName, properties) in prims {
                for (prop, val) in properties {
                    if allProperties[primName] == nil {
                        allProperties[primName] = [:]
                    }
                    allProperties[primName]![prop] = val
                }
            }
        }

        var usda = "#usda 1.0\n"
        usda += "(\n"
        usda += "    defaultPrim = \"Root\"\n"
        usda += "    metersPerUnit = 1.0\n"
        usda += "    upAxis = \"Y\"\n"
        usda += ")\n\n"
        usda += "def Xform \"Root\"\n{\n"

        for (primName, properties) in allProperties.sorted(by: { $0.key < $1.key }) {
            usda += "    def Xform \"\(primName)\"\n    {\n"
            for (prop, val) in properties.sorted(by: { $0.key < $1.key }) {
                usda += "        \(prop) = \(val)\n"
            }
            usda += "    }\n"
        }

        usda += "}\n"
        return usda
    }

    // MARK: - Layer Diff

    /// Compares two layers and returns property differences per prim.
    public func diff(layerA: UUID, layerB: UUID) -> [String: [(property: String, valueA: String?, valueB: String?)]] {
        let contentA = readLayerContent(id: layerA) ?? ""
        let contentB = readLayerContent(id: layerB) ?? ""

        let primsA = parsePrimProperties(from: contentA)
        let primsB = parsePrimProperties(from: contentB)

        let allPrims = Set(primsA.keys).union(primsB.keys)
        var result: [String: [(property: String, valueA: String?, valueB: String?)]] = [:]

        for prim in allPrims {
            let propsA = primsA[prim] ?? [:]
            let propsB = primsB[prim] ?? [:]
            let allProps = Set(propsA.keys).union(propsB.keys)

            var diffs: [(String, String?, String?)] = []
            for prop in allProps {
                let valA = propsA[prop]
                let valB = propsB[prop]
                if valA != valB {
                    diffs.append((prop, valA, valB))
                }
            }

            if !diffs.isEmpty {
                result[prim] = diffs
            }
        }

        return result
    }

    // MARK: - Persistence

    /// Saves the layer stack metadata to a JSON file.
    public func saveManifest(to url: URL) throws {
        let data = try JSONEncoder().encode(layers)
        try data.write(to: url, options: .atomic)
    }

    /// Loads the layer stack metadata from a JSON file.
    public func loadManifest(from url: URL) throws {
        let data = try Data(contentsOf: url)
        layers = try JSONDecoder().decode([SceneLayer].self, from: data)
    }

    // MARK: - Private

    private func reindex() {
        for i in layers.indices {
            layers[i].order = i
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    private func generateEmptyLayer(name: String) -> String {
        """
        #usda 1.0
        (
            defaultPrim = "Root"
            doc = "Layer: \(name)"
        )

        def Xform "Root"
        {
        }
        """
    }

    private func parsePrimProperties(from usda: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        let lines = usda.components(separatedBy: .newlines)

        var currentPrim: String?
        var depth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let match = parsePrimName(trimmed) {
                currentPrim = match
                depth = 0
            } else if trimmed == "{" {
                depth += 1
            } else if trimmed == "}" {
                depth -= 1
                if depth <= 0 { currentPrim = nil }
            } else if let prim = currentPrim, trimmed.contains("=") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    if !key.starts(with: "//") && !key.isEmpty {
                        if result[prim] == nil { result[prim] = [:] }
                        result[prim]![key] = value
                    }
                }
            }
        }

        return result
    }

    private func parsePrimName(_ line: String) -> String? {
        let prefixes = ["def Xform", "def Mesh", "def Camera", "over Xform", "over Mesh"]
        for prefix in prefixes {
            if line.hasPrefix(prefix),
               let firstQuote = line.firstIndex(of: "\""),
               let lastQuote = line.lastIndex(of: "\""),
               firstQuote != lastQuote {
                return String(line[line.index(after: firstQuote)..<lastQuote])
            }
        }
        return nil
    }
}
