import Foundation

/// Generates Swift source templates for gameplay scripts.
///
/// Each generated file contains a Component struct (data) and a System class (logic),
/// using the `GameplayScript` protocol for minimal boilerplate.
public struct ScriptTemplateGenerator {

    /// Generates a gameplay script file with the given name.
    ///
    /// - Parameter name: The base name (e.g. "PlayerMovement"). Produces `PlayerMovementComponent` + `PlayerMovementSystem`.
    /// - Returns: The full Swift source code for the script file.
    public static func generate(name: String) -> String {
        let n = name.replacingOccurrences(of: " ", with: "")
        return """
        import MetalCasterCore
        import MetalCasterScene
        import simd

        // MARK: - Component

        public struct \(n)Component: Component {
            public init() {}
        }

        // MARK: - System

        public final class \(n)System: GameplayScript {
            public nonisolated(unsafe) var isEnabled: Bool = true
            public var priority: Int { -105 }
            public init() {}

            public func process(entity: Entity, _ data: \(n)Component, _ target: inout TransformComponent, context: UpdateContext) {
                // Your per-frame logic here
            }
        }

        """
    }
}
