import Foundation
import simd

/// A named texture slot that binds an image file to a Metal texture index.
public struct TextureSlot: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var filePath: String?
    public var bindingIndex: Int

    public init(id: UUID = UUID(), name: String, filePath: String? = nil, bindingIndex: Int) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.bindingIndex = bindingIndex
    }
}

/// Observable state container for a Shader Canvas workspace within the engine.
/// Mirrors the macOSShaderCanvas state model but uses engine types.
public final class ShaderCanvasState: @unchecked Sendable {

    /// Active shader layers in the workspace.
    public var activeShaders: [ActiveShader] = []

    /// Current mesh geometry type.
    public var meshType: MeshType = .sphere

    /// Data flow configuration (which vertex attributes are enabled).
    public var dataFlowConfig: DataFlowConfig = DataFlowConfig()

    /// User-defined parameter values, keyed by parameter name.
    public var paramValues: [String: [Float]] = [:]

    /// Texture slots for binding images to fragment shader texture indices.
    public var textureSlots: [TextureSlot] = []

    /// User-defined helper functions injected between the header and main shader code.
    public var helperFunctions: String = ""

    /// The currently selected shader layer for editing.
    public var editingShaderID: UUID?

    /// Last compilation error, if any.
    public var compilationError: String?

    /// Whether the canvas has unsaved changes.
    public var isDirty: Bool = false

    public init() {}

    // MARK: - Layer Management

    public func addShader(category: ShaderCategory, name: String, code: String) -> ActiveShader {
        let shader = ActiveShader(category: category, name: name, code: code)
        activeShaders.append(shader)
        isDirty = true
        return shader
    }

    public func removeShader(id: UUID) {
        activeShaders.removeAll { $0.id == id }
        if editingShaderID == id { editingShaderID = nil }
        isDirty = true
    }

    public func updateShaderCode(id: UUID, code: String) {
        guard let idx = activeShaders.firstIndex(where: { $0.id == id }) else { return }
        activeShaders[idx].code = code
        isDirty = true
    }

    /// Returns the last vertex shader and last fragment shader (used for mesh rendering).
    public var activeMeshShaders: (vertex: ActiveShader?, fragment: ActiveShader?) {
        let vertex = activeShaders.last { $0.category == .vertex }
        let fragment = activeShaders.last { $0.category == .fragment }
        return (vertex, fragment)
    }

    /// Returns all fullscreen (post-processing) shaders in order.
    public var fullscreenShaders: [ActiveShader] {
        activeShaders.filter { $0.category == .fullscreen }
    }

    // MARK: - Serialization

    public func toDocument(name: String = "Untitled") -> CanvasDocument {
        CanvasDocument(
            name: name,
            meshType: meshType,
            shaders: activeShaders,
            dataFlow: dataFlowConfig,
            paramValues: paramValues
        )
    }

    public func load(from document: CanvasDocument) {
        activeShaders = document.shaders
        meshType = document.meshType
        dataFlowConfig = document.dataFlow
        paramValues = document.paramValues
        editingShaderID = nil
        compilationError = nil
        isDirty = false
    }
}
