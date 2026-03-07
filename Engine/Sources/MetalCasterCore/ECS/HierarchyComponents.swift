import Foundation

/// Marks an entity as a child of another entity.
/// Attach this to a child entity to establish a parent-child relationship.
/// The inverse (parent -> children) is maintained automatically by `HierarchySystem`.
public struct ParentComponent: Component {
    public var entity: Entity

    public init(_ entity: Entity) {
        self.entity = entity
    }
}

/// Caches the ordered list of child entities.
/// Automatically maintained by `HierarchySystem` — do not edit directly.
/// Read this component to efficiently enumerate an entity's children in O(1).
public struct ChildrenComponent: Component {
    public var entities: [Entity]

    public init(_ entities: [Entity] = []) {
        self.entities = entities
    }
}
