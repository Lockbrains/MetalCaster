import Foundation
import MetalCasterCore
import MetalCasterAsset

/// Compiles `.prompt` natural-language descriptions into Swift ECS source code
/// by calling an LLM with a carefully constructed system prompt containing
/// the full MetalCaster ECS API reference.
public actor PromptScriptCompiler {

    public static let shared = PromptScriptCompiler()

    private let aiService = AIService.shared

    public enum CompileError: LocalizedError, Sendable {
        case noSwiftCodeInResponse
        case aiNotConfigured
        case generationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noSwiftCodeInResponse:
                return "LLM response did not contain valid Swift code"
            case .aiNotConfigured:
                return "AI provider is not configured — set an API key in Settings"
            case .generationFailed(let msg):
                return "Code generation failed: \(msg)"
            }
        }
    }

    /// Compiles a `PromptScriptData` into Swift source code via LLM.
    public func compile(
        data: PromptScriptData,
        settings: AISettings
    ) async throws -> String {
        guard settings.isConfigured else {
            throw CompileError.aiNotConfigured
        }

        let userPrompt = buildUserPrompt(from: data)
        let message = ChatMessage(role: .user, content: userPrompt)

        let response = try await aiService.agentToolChat(
            messages: [message],
            systemPrompt: Self.systemPrompt,
            settings: settings
        )

        return try extractSwiftCode(from: response)
    }

    // MARK: - Prompt Construction

    private func buildUserPrompt(from data: PromptScriptData) -> String {
        var prompt = """
        Generate a MetalCaster ECS Component + System for the following behavior:

        **Component name**: \(data.swiftIdentifier)

        **Initial state**: \(data.initialState)

        **Per-frame behavior**: \(data.perFrameBehavior)

        **Public interface**: \(data.publicInterface)
        """

        let filled = data.customFields.filter {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !filled.isEmpty {
            prompt += "\n\n**Additional context from the user:**\n"
            for field in filled {
                prompt += "\n- **\(field.label)**: \(field.content)"
            }
        }

        prompt += "\n\nGenerate the complete Swift source file now. Output ONLY the Swift code, no explanations."
        return prompt
    }

    /// Extracts Swift source code from the LLM response, stripping markdown fences if present.
    private func extractSwiftCode(from response: String) throws -> String {
        var code = response.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePattern = #"```(?:swift)?\s*\n([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
           let range = Range(match.range(at: 1), in: code) {
            code = String(code[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard code.contains("Component") && code.contains("import") else {
            throw CompileError.noSwiftCodeInResponse
        }

        return code
    }

    // MARK: - System Prompt

    private static let systemPrompt = """
    You are a Swift code generator for the MetalCaster game engine's ECS (Entity Component System).
    Your job is to take a natural-language description and produce a SINGLE Swift source file containing:
    1. A `Component` struct (pure data, no behavior)
    2. A `System` class that operates on that component every frame

    You MUST follow these rules exactly:

    ## Output Rules
    - Output ONLY valid, compilable Swift code. No markdown fences, no explanations, no comments explaining what was generated.
    - The file must compile with Swift 5 strict concurrency checking.

    ## Imports
    ```
    import MetalCasterCore
    import MetalCasterScene
    import simd
    ```

    ## Component Requirements
    - Name: `{Name}Component` where {Name} is the identifier provided.
    - Must conform to `Component` (which is `Codable & Sendable`).
    - Must be a `public struct`.
    - All stored properties MUST have default values so `public init() {}` works.
    - Properties should reflect the "initial state" description.
    - Only use types that are `Codable & Sendable`: Bool, Int, Float, Double, String, SIMD3<Float>, simd_quatf, arrays/optionals of these.

    ## System Requirements
    - Name: `{Name}System`
    - Must be `public final class` conforming to `GameplayScript`.
    - associatedtype `Data` = `{Name}Component`
    - associatedtype `Target` = `TransformComponent`
    - Must have: `public nonisolated(unsafe) var isEnabled: Bool = true`
    - Must have: `public var priority: Int { 0 }`
    - Must have: `public init() {}`
    - Implement: `public func process(entity: Entity, _ data: {Name}Component, _ target: inout TransformComponent, context: UpdateContext)`

    ## Available APIs

    ### TransformComponent
    ```swift
    public struct TransformComponent: Component {
        public var transform: MCTransform  // .position: SIMD3<Float>, .rotation: simd_quatf, .scale: SIMD3<Float>
        public var parent: Entity?
        public var worldMatrix: simd_float4x4
    }
    ```

    ### MCTransform
    ```swift
    public struct MCTransform: Codable, Sendable {
        public var position: SIMD3<Float>
        public var rotation: simd_quatf
        public var scale: SIMD3<Float>
        public static let identity: MCTransform
    }
    ```

    ### UpdateContext
    ```swift
    public struct UpdateContext: Sendable {
        public let world: World       // ECS world for entity/component queries
        public let time: TimeState    // .deltaTime: Float, .totalTime: Float, .frameCount: UInt64
        public let input: InputManager
        public let events: EventBus
        public let engine: Engine
    }
    ```

    ### TimeState
    ```swift
    public struct TimeState: Sendable {
        public let deltaTime: Float      // seconds since last frame
        public let fixedDeltaTime: Float  // fixed timestep
        public let totalTime: Float      // seconds since start
        public let frameCount: UInt64
    }
    ```

    ### World (common queries)
    ```swift
    public func forEach<A: Component>(_ a: A.Type, body: (Entity, A) -> Void)
    public func forEach<A: Component, B: Component>(_ a: A.Type, _ b: B.Type, body: (Entity, A, B) -> Void)
    public func getComponent<C: Component>(_ type: C.Type, for entity: Entity) -> C?
    public func update<C: Component>(_ type: C.Type, on entity: Entity, body: (inout C) -> Void)
    ```

    ### GameplayScript protocol
    ```swift
    public protocol GameplayScript: System {
        associatedtype Data: Component
        associatedtype Target: Component
        func process(entity: Entity, _ data: Data, _ target: inout Target, context: UpdateContext)
    }
    // The engine automatically iterates all entities that have both Data and Target components.
    // You only implement `process` — iteration is handled for you.
    ```

    ### Entity
    ```swift
    public struct Entity: Hashable, Codable, Sendable {
        public let id: UInt64
    }
    ```

    ## Math helpers (simd)
    - `simd_float4x4`, `SIMD3<Float>`, `SIMD2<Float>`, `simd_quatf`
    - `simd_normalize(_:)`, `simd_length(_:)`, `simd_dot(_:_:)`, `simd_cross(_:_:)`
    - `sin(_:)`, `cos(_:)`, `atan2(_:_:)`, `min(_:_:)`, `max(_:_:)`, `abs(_:)`
    - `simd_slerp(_:_:_:)` for quaternion interpolation
    - `simd_mix(_:_:_:)` for linear interpolation

    ## Style
    - Keep the code clean, minimal, and idiomatic Swift.
    - Use MARK comments sparingly (only `// MARK: - Component` and `// MARK: - System`).
    - Do NOT add tutorial-style comments explaining what each line does.
    """
}
