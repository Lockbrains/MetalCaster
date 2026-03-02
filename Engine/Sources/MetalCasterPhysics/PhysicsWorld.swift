import Foundation
import simd
import MetalCasterCore
import MetalCasterScene

/// Simple physics component for entities.
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
    
    public init(
        bodyType: BodyType = .dynamicBody,
        mass: Float = 1.0,
        velocity: SIMD3<Float> = .zero,
        angularVelocity: SIMD3<Float> = .zero,
        restitution: Float = 0.3,
        friction: Float = 0.5,
        useGravity: Bool = true
    ) {
        self.bodyType = bodyType
        self.mass = mass
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.restitution = restitution
        self.friction = friction
        self.useGravity = useGravity
    }
}

/// Collider shapes for physics simulation.
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
    
    public init(shape: Shape = .sphere, radius: Float = 1.0, halfExtents: SIMD3<Float> = SIMD3<Float>(0.5, 0.5, 0.5), isTrigger: Bool = false) {
        self.shape = shape
        self.radius = radius
        self.halfExtents = halfExtents
        self.isTrigger = isTrigger
    }
}

/// Simple physics simulation system.
///
/// Applies gravity, integrates velocity, and performs basic AABB collision detection.
/// This is a placeholder for integration with Apple's physics frameworks.
public final class PhysicsSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { 10 }
    
    public nonisolated(unsafe) var gravity: SIMD3<Float> = SIMD3<Float>(0, -9.81, 0)
    
    public init() {}
    
    public func update(context: UpdateContext) {
        let world = context.world
        let dt = context.time.deltaTime
        let bodies = world.query(TransformComponent.self, PhysicsBodyComponent.self)
        
        for (entity, tc, body) in bodies {
            guard body.bodyType == .dynamicBody else { continue }
            
            var updatedBody = body
            var updatedTC = tc
            
            if body.useGravity {
                updatedBody.velocity += gravity * dt
            }
            
            updatedTC.transform.position += updatedBody.velocity * dt
            
            // Simple ground plane collision at y=0
            if updatedTC.transform.position.y < 0 {
                updatedTC.transform.position.y = 0
                updatedBody.velocity.y = -updatedBody.velocity.y * body.restitution
                if abs(updatedBody.velocity.y) < 0.1 {
                    updatedBody.velocity.y = 0
                }
            }
            
            world.addComponent(updatedTC, to: entity)
            world.addComponent(updatedBody, to: entity)
        }
    }
}
