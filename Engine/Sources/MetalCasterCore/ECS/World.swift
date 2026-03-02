import Foundation

/// The central ECS data store. Holds all entities and their components.
///
/// Uses sparse-set storage: `[ComponentType: [EntityID: Component]]`.
/// This is simple and efficient for iteration and random access.
/// Can be upgraded to archetype storage later for cache-friendly iteration.
public final class World: @unchecked Sendable {

    // MARK: - Storage

    private var nextEntityID: UInt64 = 0
    private var aliveEntities: Set<Entity> = []
    private var storage: [ComponentTypeKey: [Entity: any Component]] = [:]

    public init() {}

    // MARK: - Entity Lifecycle

    /// Creates a new entity with a unique ID.
    @discardableResult
    public func createEntity() -> Entity {
        let entity = Entity(id: nextEntityID)
        nextEntityID += 1
        aliveEntities.insert(entity)
        return entity
    }

    /// Destroys an entity and removes all its components.
    public func destroyEntity(_ entity: Entity) {
        aliveEntities.remove(entity)
        for key in storage.keys {
            storage[key]?.removeValue(forKey: entity)
        }
    }

    /// Returns true if the entity is alive in this world.
    public func isAlive(_ entity: Entity) -> Bool {
        aliveEntities.contains(entity)
    }

    /// Returns all living entities.
    public var entities: Set<Entity> { aliveEntities }

    /// Returns the total number of living entities.
    public var entityCount: Int { aliveEntities.count }

    // MARK: - Component Operations

    /// Adds or replaces a component on an entity.
    @discardableResult
    public func addComponent<C: Component>(_ component: C, to entity: Entity) -> C {
        let key = ComponentTypeKey(C.self)
        if storage[key] == nil {
            storage[key] = [:]
        }
        storage[key]![entity] = component
        return component
    }

    /// Retrieves a component of the given type from an entity.
    public func getComponent<C: Component>(_ type: C.Type, from entity: Entity) -> C? {
        let key = ComponentTypeKey(C.self)
        return storage[key]?[entity] as? C
    }

    /// Returns true if the entity has a component of the given type.
    public func hasComponent<C: Component>(_ type: C.Type, on entity: Entity) -> Bool {
        let key = ComponentTypeKey(C.self)
        return storage[key]?[entity] != nil
    }

    /// Removes a component of the given type from an entity.
    @discardableResult
    public func removeComponent<C: Component>(_ type: C.Type, from entity: Entity) -> C? {
        let key = ComponentTypeKey(C.self)
        return storage[key]?.removeValue(forKey: entity) as? C
    }

    /// Returns all entities that have the given component type.
    public func entitiesWith<C: Component>(_ type: C.Type) -> [Entity] {
        let key = ComponentTypeKey(C.self)
        guard let map = storage[key] else { return [] }
        return Array(map.keys)
    }

    // MARK: - Queries

    /// Queries all entities that have a specific component, returning (entity, component) pairs.
    public func query<C: Component>(_ type: C.Type) -> [(Entity, C)] {
        let key = ComponentTypeKey(C.self)
        guard let map = storage[key] else { return [] }
        return map.compactMap { (entity, component) in
            guard let c = component as? C else { return nil }
            return (entity, c)
        }
    }

    /// Queries all entities that have two specific components.
    public func query<A: Component, B: Component>(
        _ typeA: A.Type,
        _ typeB: B.Type
    ) -> [(Entity, A, B)] {
        let keyA = ComponentTypeKey(A.self)
        let keyB = ComponentTypeKey(B.self)
        guard let mapA = storage[keyA], let mapB = storage[keyB] else { return [] }

        let smaller = mapA.count <= mapB.count ? mapA : mapB
        var results: [(Entity, A, B)] = []

        for entity in smaller.keys {
            if let a = mapA[entity] as? A, let b = mapB[entity] as? B {
                results.append((entity, a, b))
            }
        }
        return results
    }

    /// Queries all entities that have three specific components.
    public func query<A: Component, B: Component, C: Component>(
        _ typeA: A.Type,
        _ typeB: B.Type,
        _ typeC: C.Type
    ) -> [(Entity, A, B, C)] {
        let keyA = ComponentTypeKey(A.self)
        let keyB = ComponentTypeKey(B.self)
        let keyC = ComponentTypeKey(C.self)
        guard let mapA = storage[keyA], let mapB = storage[keyB], let mapC = storage[keyC] else { return [] }

        let smallest = [mapA, mapB, mapC].min(by: { $0.count < $1.count })!
        var results: [(Entity, A, B, C)] = []

        for entity in smallest.keys {
            if let a = mapA[entity] as? A,
               let b = mapB[entity] as? B,
               let c = mapC[entity] as? C {
                results.append((entity, a, b, c))
            }
        }
        return results
    }

    /// Queries all entities that have four specific components.
    public func query<A: Component, B: Component, C: Component, D: Component>(
        _ typeA: A.Type,
        _ typeB: B.Type,
        _ typeC: C.Type,
        _ typeD: D.Type
    ) -> [(Entity, A, B, C, D)] {
        let keyA = ComponentTypeKey(A.self)
        let keyB = ComponentTypeKey(B.self)
        let keyC = ComponentTypeKey(C.self)
        let keyD = ComponentTypeKey(D.self)
        guard let mapA = storage[keyA], let mapB = storage[keyB],
              let mapC = storage[keyC], let mapD = storage[keyD] else { return [] }

        let smallest = [mapA, mapB, mapC, mapD].min(by: { $0.count < $1.count })!
        var results: [(Entity, A, B, C, D)] = []

        for entity in smallest.keys {
            if let a = mapA[entity] as? A,
               let b = mapB[entity] as? B,
               let c = mapC[entity] as? C,
               let d = mapD[entity] as? D {
                results.append((entity, a, b, c, d))
            }
        }
        return results
    }

    // MARK: - Introspection

    /// All component type keys currently registered in this world.
    public var registeredComponentTypes: [ComponentTypeKey] {
        Array(storage.keys)
    }

    /// Returns the component type keys attached to a specific entity.
    public func componentTypeKeys(of entity: Entity) -> [ComponentTypeKey] {
        storage.compactMap { (key, map) in
            map[entity] != nil ? key : nil
        }
    }

    /// The set of component type names for an entity, used to compute virtual archetypes.
    public func archetypeSignature(of entity: Entity) -> Set<String> {
        Set(componentTypeKeys(of: entity).map(\.name))
    }

    /// Returns all entities whose component type set matches the given key (type-erased).
    public func entitiesWithComponent(key: ComponentTypeKey) -> [Entity] {
        guard let map = storage[key] else { return [] }
        return Array(map.keys)
    }

    /// Estimated memory stride for a component type, derived from any stored instance.
    public func estimatedComponentSize(for key: ComponentTypeKey) -> Int? {
        guard let map = storage[key], let anyComponent = map.values.first else { return nil }
        return type(of: anyComponent).estimatedSize
    }

    /// Returns all components attached to an entity as type-erased key-value pairs.
    public func allComponents(of entity: Entity) -> [(ComponentTypeKey, any Component)] {
        storage.compactMap { (key, map) in
            guard let component = map[entity] else { return nil }
            return (key, component)
        }
    }

    // MARK: - forEach Queries (allocation-free)

    /// Iterates all entities with a specific component, invoking a closure for each match.
    public func forEach<A: Component>(
        _ a: A.Type,
        body: (Entity, A) -> Void
    ) {
        let keyA = ComponentTypeKey(A.self)
        guard let mapA = storage[keyA] else { return }
        for (entity, component) in mapA {
            if let ca = component as? A {
                body(entity, ca)
            }
        }
    }

    /// Iterates all entities with two specific components.
    public func forEach<A: Component, B: Component>(
        _ a: A.Type, _ b: B.Type,
        body: (Entity, A, B) -> Void
    ) {
        let keyA = ComponentTypeKey(A.self)
        let keyB = ComponentTypeKey(B.self)
        guard let mapA = storage[keyA], let mapB = storage[keyB] else { return }

        let smaller = mapA.count <= mapB.count ? mapA : mapB
        for entity in smaller.keys {
            if let ca = mapA[entity] as? A, let cb = mapB[entity] as? B {
                body(entity, ca, cb)
            }
        }
    }

    /// Iterates all entities with three specific components.
    public func forEach<A: Component, B: Component, C: Component>(
        _ a: A.Type, _ b: B.Type, _ c: C.Type,
        body: (Entity, A, B, C) -> Void
    ) {
        let keyA = ComponentTypeKey(A.self)
        let keyB = ComponentTypeKey(B.self)
        let keyC = ComponentTypeKey(C.self)
        guard let mapA = storage[keyA], let mapB = storage[keyB], let mapC = storage[keyC] else { return }

        let smallest = [mapA, mapB, mapC].min(by: { $0.count < $1.count })!
        for entity in smallest.keys {
            if let ca = mapA[entity] as? A,
               let cb = mapB[entity] as? B,
               let cc = mapC[entity] as? C {
                body(entity, ca, cb, cc)
            }
        }
    }

    /// Iterates all entities with four specific components.
    public func forEach<A: Component, B: Component, C: Component, D: Component>(
        _ a: A.Type, _ b: B.Type, _ c: C.Type, _ d: D.Type,
        body: (Entity, A, B, C, D) -> Void
    ) {
        let keyA = ComponentTypeKey(A.self)
        let keyB = ComponentTypeKey(B.self)
        let keyC = ComponentTypeKey(C.self)
        let keyD = ComponentTypeKey(D.self)
        guard let mapA = storage[keyA], let mapB = storage[keyB],
              let mapC = storage[keyC], let mapD = storage[keyD] else { return }

        let smallest = [mapA, mapB, mapC, mapD].min(by: { $0.count < $1.count })!
        for entity in smallest.keys {
            if let ca = mapA[entity] as? A,
               let cb = mapB[entity] as? B,
               let cc = mapC[entity] as? C,
               let cd = mapD[entity] as? D {
                body(entity, ca, cb, cc, cd)
            }
        }
    }

    // MARK: - Component Mutation Helper

    /// Mutates a component in-place on an entity. Does nothing if the component is absent.
    public func update<C: Component>(_ type: C.Type, on entity: Entity, _ mutate: (inout C) -> Void) {
        guard var component = getComponent(type, from: entity) else { return }
        mutate(&component)
        addComponent(component, to: entity)
    }

    // MARK: - Bulk Operations

    /// Removes all entities and components.
    public func clear() {
        aliveEntities.removeAll()
        storage.removeAll()
        nextEntityID = 0
    }

    /// Convenience: create an entity with initial components.
    @discardableResult
    public func spawn(_ components: any Component...) -> Entity {
        let entity = createEntity()
        for component in components {
            let key = ComponentTypeKey(name: type(of: component).componentName)
            if storage[key] == nil {
                storage[key] = [:]
            }
            storage[key]![entity] = component
        }
        return entity
    }
}
