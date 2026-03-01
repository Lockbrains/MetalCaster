import Foundation

/// Represents a material definition that maps to a set of shaders and parameters.
///
/// Materials define the visual appearance of a surface. In the engine,
/// materials are stored as components and reference shader code + parameters.
/// Future: USD-based material definitions via UsdShade.
public struct MCMaterial: Codable, Sendable {

    /// Unique identifier for this material.
    public let id: UUID

    /// Human-readable name.
    public var name: String

    /// The vertex shader source code (nil = use default).
    public var vertexShaderSource: String?

    /// The fragment shader source code.
    public var fragmentShaderSource: String

    /// Post-processing shader sources applied when this material is active.
    public var postProcessSources: [String]

    /// User-tunable parameters with their current values.
    public var parameters: [String: [Float]]

    /// The data flow configuration for this material's shaders.
    public var dataFlowConfig: DataFlowConfig

    public init(
        id: UUID = UUID(),
        name: String = "Default Material",
        vertexShaderSource: String? = nil,
        fragmentShaderSource: String = "",
        postProcessSources: [String] = [],
        parameters: [String: [Float]] = [:],
        dataFlowConfig: DataFlowConfig = DataFlowConfig()
    ) {
        self.id = id
        self.name = name
        self.vertexShaderSource = vertexShaderSource
        self.fragmentShaderSource = fragmentShaderSource
        self.postProcessSources = postProcessSources
        self.parameters = parameters
        self.dataFlowConfig = dataFlowConfig
    }
}
