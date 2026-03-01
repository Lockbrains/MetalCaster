import Foundation

/// Marker protocol for all ECS components.
/// Components are pure data containers — no behavior.
/// Codable conformance enables scene serialization.
public protocol Component: Codable, Sendable {
    /// A unique string identifying this component type for serialization and reflection.
    static var componentName: String { get }
}

extension Component {
    public static var componentName: String {
        String(describing: Self.self)
    }
}

/// Type-erased component storage key, used internally by World.
public struct ComponentTypeKey: Hashable, Sendable {
    public let name: String

    public init<C: Component>(_ type: C.Type) {
        self.name = type.componentName
    }

    public init(name: String) {
        self.name = name
    }
}
