import Foundation
import simd
import MetalCasterCore

// MARK: - Contact Point

/// A single contact point between two colliding bodies.
public struct ContactPoint: Sendable {
    /// World-space contact position.
    public var position: SIMD3<Float>
    /// Contact normal pointing from body A to body B.
    public var normal: SIMD3<Float>
    /// Penetration depth (positive = overlapping).
    public var penetration: Float

    public init(position: SIMD3<Float>, normal: SIMD3<Float>, penetration: Float) {
        self.position = position
        self.normal = normal
        self.penetration = penetration
    }
}

// MARK: - Contact Manifold

/// A set of contact points between two bodies for a single frame.
public struct ContactManifold: Sendable {
    public var entityA: Entity
    public var entityB: Entity
    public var contacts: [ContactPoint]
    public var isTrigger: Bool

    public init(entityA: Entity, entityB: Entity, contacts: [ContactPoint] = [], isTrigger: Bool = false) {
        self.entityA = entityA
        self.entityB = entityB
        self.contacts = contacts
        self.isTrigger = isTrigger
    }

    /// Average contact normal.
    public var averageNormal: SIMD3<Float> {
        guard !contacts.isEmpty else { return SIMD3<Float>(0, 1, 0) }
        var sum = SIMD3<Float>.zero
        for c in contacts { sum += c.normal }
        return simd_normalize(sum)
    }

    /// Maximum penetration depth among all contacts.
    public var maxPenetration: Float {
        contacts.map(\.penetration).max() ?? 0
    }
}

// MARK: - Collision Pair Key

/// Canonical pair of entities for collision tracking, order-independent.
public struct CollisionPairKey: Hashable, Sendable {
    public let a: Entity
    public let b: Entity

    public init(_ a: Entity, _ b: Entity) {
        if a.id < b.id {
            self.a = a; self.b = b
        } else {
            self.a = b; self.b = a
        }
    }
}

// MARK: - Physics Events

public struct CollisionEnterEvent: MCEvent {
    public let manifold: ContactManifold
    public init(manifold: ContactManifold) { self.manifold = manifold }
}

public struct CollisionStayEvent: MCEvent {
    public let manifold: ContactManifold
    public init(manifold: ContactManifold) { self.manifold = manifold }
}

public struct CollisionExitEvent: MCEvent {
    public let entityA: Entity
    public let entityB: Entity
    public init(entityA: Entity, entityB: Entity) { self.entityA = entityA; self.entityB = entityB }
}

public struct TriggerEnterEvent: MCEvent {
    public let entityA: Entity
    public let entityB: Entity
    public init(entityA: Entity, entityB: Entity) { self.entityA = entityA; self.entityB = entityB }
}

public struct TriggerExitEvent: MCEvent {
    public let entityA: Entity
    public let entityB: Entity
    public init(entityA: Entity, entityB: Entity) { self.entityA = entityA; self.entityB = entityB }
}

// MARK: - Raycast Result

public struct RaycastHit: Sendable {
    public let entity: Entity
    public let point: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let distance: Float
}
