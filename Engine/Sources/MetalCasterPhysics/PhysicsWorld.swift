import Foundation
import simd
import MetalCasterCore
import MetalCasterScene
import MetalCasterMath

// MARK: - Collider AABB Extension

extension ColliderComponent {
    /// Computes the world-space AABB for broadphase, given a world position and rotation.
    public func worldAABB(position: SIMD3<Float>, rotation: simd_quatf) -> MCAABB {
        let worldPos = position + rotation.act(offset)
        switch shape {
        case .sphere:
            let r = SIMD3<Float>(repeating: radius)
            return MCAABB(min: worldPos - r, max: worldPos + r)
        case .box:
            let obb = MCOBB(center: worldPos, halfExtents: halfExtents, rotation: rotation)
            return obb.toAABB()
        case .capsule:
            let up = rotation.act(SIMD3<Float>(0, 1, 0))
            let tipA = worldPos + up * halfExtents.y
            let tipB = worldPos - up * halfExtents.y
            let r = SIMD3<Float>(repeating: radius)
            var aabb = MCAABB(min: tipA - r, max: tipA + r)
            aabb.encapsulate(MCAABB(min: tipB - r, max: tipB + r))
            return aabb
        }
    }
}

// MARK: - Physics System

/// Full 3D rigid body physics system with broadphase, narrowphase, and constraint solving.
public final class PhysicsSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { 5 }

    public nonisolated(unsafe) var gravity: SIMD3<Float> = SIMD3<Float>(0, -9.81, 0)

    private let broadphase = Broadphase()
    private let solver = ContactSolver()

    /// Previous frame's collision pairs for enter/exit event detection.
    private var previousPairs: Set<CollisionPairKey> = []

    /// Physics sub-step accumulator for fixed timestep.
    private var accumulator: Float = 0

    /// Maximum number of sub-steps per frame to prevent spiral of death.
    public var maxSubSteps: Int = 4

    public init() {}

    public func setup(world: World) {
        MCLog.info(.physics, "PhysicsSystem initialized (gravity: \(gravity))")
    }

    public func update(context: UpdateContext) {
        let world = context.world
        let fixedDt = context.time.fixedDeltaTime
        accumulator += context.time.deltaTime

        var steps = 0
        while accumulator >= fixedDt && steps < maxSubSteps {
            step(world: world, dt: fixedDt, events: context.events)
            accumulator -= fixedDt
            steps += 1
        }

        if accumulator > fixedDt { accumulator = 0 }
    }

    // MARK: - Physics Step

    private func step(world: World, dt: Float, events: EventBus) {
        let bodies = world.query(TransformComponent.self, PhysicsBodyComponent.self, ColliderComponent.self)

        // 1. Build body states and apply forces
        var bodyStates: [Entity: BodyState] = [:]
        bodyStates.reserveCapacity(bodies.count)

        broadphase.clear()

        for (entity, tc, physics, collider) in bodies {
            var vel = physics.velocity
            var angVel = physics.angularVelocity

            if physics.bodyType == .dynamicBody {
                if physics.useGravity {
                    vel += gravity * dt
                }
                vel *= (1.0 - physics.linearDamping)
                angVel *= (1.0 - physics.angularDamping)
            }

            let pos = tc.transform.position
            let rot = tc.transform.rotation

            bodyStates[entity] = BodyState(
                position: pos,
                rotation: rot,
                velocity: vel,
                angularVelocity: angVel,
                invMass: physics.inverseMass,
                invInertia: physics.inverseInertia,
                restitution: physics.restitution,
                friction: physics.friction
            )

            broadphase.insert(entity: entity, aabb: collider.worldAABB(position: pos, rotation: rot))
        }

        // 2. Broadphase
        let pairs = broadphase.findPairs()

        // 3. Narrowphase
        var manifolds: [ContactManifold] = []
        var currentPairs = Set<CollisionPairKey>()

        for pair in pairs {
            guard let stateA = bodyStates[pair.a], let stateB = bodyStates[pair.b] else { continue }

            let colliderA = world.getComponent(ColliderComponent.self, from: pair.a)!
            let colliderB = world.getComponent(ColliderComponent.self, from: pair.b)!

            if let manifold = Narrowphase.test(
                entityA: pair.a, posA: stateA.position, rotA: stateA.rotation, colliderA: colliderA,
                entityB: pair.b, posB: stateB.position, rotB: stateB.rotation, colliderB: colliderB
            ) {
                manifolds.append(manifold)
                currentPairs.insert(pair)
            }
        }

        // 4. Solve constraints
        solver.solve(manifolds: manifolds, bodies: &bodyStates, dt: dt)

        // 5. Integrate and write back
        for (entity, tc, physics, _) in bodies {
            guard let state = bodyStates[entity] else { continue }
            guard physics.bodyType == .dynamicBody else { continue }

            var updatedTC = tc
            var updatedBody = physics

            updatedTC.transform.position = state.position + state.velocity * dt
            updatedBody.velocity = state.velocity
            updatedBody.angularVelocity = state.angularVelocity

            let angSpeed = simd_length(state.angularVelocity)
            if angSpeed > 1e-6 {
                let axis = state.angularVelocity / angSpeed
                let angle = angSpeed * dt
                let dq = simd_quatf(angle: angle, axis: axis)
                updatedTC.transform.rotation = simd_normalize(dq * updatedTC.transform.rotation)
            }

            world.addComponent(updatedTC, to: entity)
            world.addComponent(updatedBody, to: entity)
        }

        // 6. Emit collision events
        emitEvents(current: currentPairs, manifolds: manifolds, events: events)
        previousPairs = currentPairs
    }

    // MARK: - Collision Events

    private func emitEvents(current: Set<CollisionPairKey>, manifolds: [ContactManifold], events: EventBus) {
        let entered = current.subtracting(previousPairs)
        let exited = previousPairs.subtracting(current)

        for pair in entered {
            if let m = manifolds.first(where: { CollisionPairKey($0.entityA, $0.entityB) == pair }) {
                if m.isTrigger {
                    events.publish(TriggerEnterEvent(entityA: pair.a, entityB: pair.b))
                } else {
                    events.publish(CollisionEnterEvent(manifold: m))
                }
            }
        }

        for pair in current.intersection(previousPairs) {
            if let m = manifolds.first(where: { CollisionPairKey($0.entityA, $0.entityB) == pair }) {
                if !m.isTrigger {
                    events.publish(CollisionStayEvent(manifold: m))
                }
            }
        }

        for pair in exited {
            events.publish(CollisionExitEvent(entityA: pair.a, entityB: pair.b))
        }
    }

    // MARK: - Raycasting

    /// Casts a ray against all colliders and returns the closest hit.
    public func raycast(world: World, origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float = 1000) -> RaycastHit? {
        let ray = MCRay(origin: origin, direction: simd_normalize(direction))
        var closestHit: RaycastHit?
        var closestDist: Float = maxDistance

        let entities = world.query(TransformComponent.self, ColliderComponent.self)
        for (entity, tc, collider) in entities {
            let pos = tc.transform.position + tc.transform.rotation.act(collider.offset)
            let hit: MCHit?

            switch collider.shape {
            case .sphere:
                hit = MCIntersection.test(ray, MCSphere(center: pos, radius: collider.radius))
            case .box:
                let obb = MCOBB(center: pos, halfExtents: collider.halfExtents, rotation: tc.transform.rotation)
                hit = MCIntersection.test(ray, obb)
            case .capsule:
                let sphere = MCSphere(center: pos, radius: collider.radius + collider.halfExtents.y)
                hit = MCIntersection.test(ray, sphere)
            }

            if let h = hit, h.distance < closestDist {
                closestDist = h.distance
                closestHit = RaycastHit(entity: entity, point: h.point, normal: h.normal, distance: h.distance)
            }
        }

        return closestHit
    }
}
