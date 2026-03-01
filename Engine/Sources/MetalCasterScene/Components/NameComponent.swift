import Foundation
import MetalCasterCore

/// Human-readable name and tags for an entity.
public struct NameComponent: Component {
    public var name: String
    public var tags: Set<String>

    public init(name: String, tags: Set<String> = []) {
        self.name = name
        self.tags = tags
    }
}
