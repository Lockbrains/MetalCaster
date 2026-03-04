import Foundation
import simd
import MetalCasterCore

// MARK: - Physics Body Component

public struct PhysicsBodyComponent: Component {
    public enum BodyType: String, Codable, Sendable {
        case staticBody
        case dynamicBody
        case kinematic
    }

    public var bodyType: BodyType
    public var mass: Float
    public var velocity: SIMD3<Float>
    public var angularVelocity: SIMD3<Float>
    public var restitution: Float
    public var friction: Float
    public var useGravity: Bool
    public var linearDamping: Float
    public var angularDamping: Float

    public init(
        bodyType: BodyType = .dynamicBody,
        mass: Float = 1.0,
        velocity: SIMD3<Float> = .zero,
        angularVelocity: SIMD3<Float> = .zero,
        restitution: Float = 0.3,
        friction: Float = 0.5,
        useGravity: Bool = true,
        linearDamping: Float = 0.01,
        angularDamping: Float = 0.05
    ) {
        self.bodyType = bodyType
        self.mass = mass
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.restitution = restitution
        self.friction = friction
        self.useGravity = useGravity
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
    }

    public var inverseMass: Float {
        bodyType == .dynamicBody && mass > 0 ? 1.0 / mass : 0
    }

    public var inverseInertia: SIMD3<Float> {
        guard bodyType == .dynamicBody, mass > 0 else { return .zero }
        let i = mass / 6.0
        return SIMD3<Float>(repeating: 1.0 / i)
    }
}

// MARK: - Collider Component

public struct ColliderComponent: Component {
    public enum Shape: String, Codable, Sendable {
        case sphere
        case box
        case capsule
    }

    public var shape: Shape
    public var radius: Float
    public var halfExtents: SIMD3<Float>
    public var isTrigger: Bool
    public var offset: SIMD3<Float>

    public init(
        shape: Shape = .sphere,
        radius: Float = 1.0,
        halfExtents: SIMD3<Float> = SIMD3<Float>(0.5, 0.5, 0.5),
        isTrigger: Bool = false,
        offset: SIMD3<Float> = .zero
    ) {
        self.shape = shape
        self.radius = radius
        self.halfExtents = halfExtents
        self.isTrigger = isTrigger
        self.offset = offset
    }
}
