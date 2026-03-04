import Foundation
import simd
import MetalCasterCore

/// Sequential Impulse constraint solver for rigid body collision response.
/// Resolves penetration and applies friction using iterative impulse accumulation.
public final class ContactSolver {

    /// Number of solver iterations per step. Higher = more stable stacking.
    public var iterations: Int = 8

    /// Baumgarte stabilization factor for position correction.
    public var baumgarte: Float = 0.2

    /// Penetration slop: small overlaps below this threshold aren't corrected.
    public var slop: Float = 0.005

    /// Restitution velocity threshold: below this, bouncing is suppressed.
    public var restitutionThreshold: Float = 0.5

    public init() {}

    /// Solves all contact manifolds, updating velocities on the provided body map.
    public func solve(
        manifolds: [ContactManifold],
        bodies: inout [Entity: BodyState],
        dt: Float
    ) {
        guard dt > 0 else { return }
        let invDt = 1.0 / dt

        var constraints: [ContactConstraint] = []
        constraints.reserveCapacity(manifolds.count * 2)

        for manifold in manifolds where !manifold.isTrigger {
            guard let bodyA = bodies[manifold.entityA],
                  let bodyB = bodies[manifold.entityB] else { continue }

            for contact in manifold.contacts {
                let rA = contact.position - bodyA.position
                let rB = contact.position - bodyB.position
                let n = contact.normal

                let relVel = (bodyB.velocity + simd_cross(bodyB.angularVelocity, rB))
                           - (bodyA.velocity + simd_cross(bodyA.angularVelocity, rA))
                let relVelN = simd_dot(relVel, n)

                let restitution: Float = relVelN < -restitutionThreshold
                    ? max(bodyA.restitution, bodyB.restitution) : 0

                let raCrossN = simd_cross(rA, n)
                let rbCrossN = simd_cross(rB, n)
                let normalMass = bodyA.invMass + bodyB.invMass
                    + simd_dot(raCrossN, bodyA.invInertia * raCrossN)
                    + simd_dot(rbCrossN, bodyB.invInertia * rbCrossN)

                guard normalMass > 1e-10 else { continue }

                let bias = max(contact.penetration - slop, 0) * baumgarte * invDt

                constraints.append(ContactConstraint(
                    entityA: manifold.entityA,
                    entityB: manifold.entityB,
                    contact: contact,
                    rA: rA, rB: rB,
                    normalMass: 1.0 / normalMass,
                    restitution: restitution,
                    bias: bias,
                    accumulatedNormalImpulse: 0,
                    accumulatedFrictionImpulse1: 0,
                    accumulatedFrictionImpulse2: 0,
                    tangent1: .zero,
                    tangent2: .zero,
                    frictionMass1: 0,
                    frictionMass2: 0,
                    friction: sqrt(bodyA.friction * bodyB.friction)
                ))

                let lastIdx = constraints.count - 1
                computeFrictionBasis(&constraints[lastIdx], bodyA: bodyA, bodyB: bodyB)
            }
        }

        for _ in 0..<iterations {
            for i in 0..<constraints.count {
                solveNormalConstraint(&constraints[i], bodies: &bodies)
                solveFrictionConstraint(&constraints[i], bodies: &bodies)
            }
        }
    }

    // MARK: - Normal Constraint

    private func solveNormalConstraint(_ c: inout ContactConstraint, bodies: inout [Entity: BodyState]) {
        guard var bodyA = bodies[c.entityA], var bodyB = bodies[c.entityB] else { return }

        let relVel = (bodyB.velocity + simd_cross(bodyB.angularVelocity, c.rB))
                   - (bodyA.velocity + simd_cross(bodyA.angularVelocity, c.rA))
        let relVelN = simd_dot(relVel, c.contact.normal)

        var lambda = c.normalMass * (-(relVelN + c.restitution * relVelN) + c.bias)
        let oldImpulse = c.accumulatedNormalImpulse
        c.accumulatedNormalImpulse = max(oldImpulse + lambda, 0)
        lambda = c.accumulatedNormalImpulse - oldImpulse

        let impulse = c.contact.normal * lambda
        bodyA.velocity -= impulse * bodyA.invMass
        bodyA.angularVelocity -= bodyA.invInertia * simd_cross(c.rA, impulse)
        bodyB.velocity += impulse * bodyB.invMass
        bodyB.angularVelocity += bodyB.invInertia * simd_cross(c.rB, impulse)

        bodies[c.entityA] = bodyA
        bodies[c.entityB] = bodyB
    }

    // MARK: - Friction Constraint

    private func solveFrictionConstraint(_ c: inout ContactConstraint, bodies: inout [Entity: BodyState]) {
        guard var bodyA = bodies[c.entityA], var bodyB = bodies[c.entityB] else { return }

        let relVel = (bodyB.velocity + simd_cross(bodyB.angularVelocity, c.rB))
                   - (bodyA.velocity + simd_cross(bodyA.angularVelocity, c.rA))

        let maxFriction = c.friction * c.accumulatedNormalImpulse

        // Tangent 1
        if c.frictionMass1 > 1e-10 {
            let vt1 = simd_dot(relVel, c.tangent1)
            var lambda1 = -vt1 / c.frictionMass1
            let old1 = c.accumulatedFrictionImpulse1
            c.accumulatedFrictionImpulse1 = max(-maxFriction, min(old1 + lambda1, maxFriction))
            lambda1 = c.accumulatedFrictionImpulse1 - old1

            let impulse1 = c.tangent1 * lambda1
            bodyA.velocity -= impulse1 * bodyA.invMass
            bodyA.angularVelocity -= bodyA.invInertia * simd_cross(c.rA, impulse1)
            bodyB.velocity += impulse1 * bodyB.invMass
            bodyB.angularVelocity += bodyB.invInertia * simd_cross(c.rB, impulse1)
        }

        // Tangent 2
        if c.frictionMass2 > 1e-10 {
            let vt2 = simd_dot(relVel, c.tangent2)
            var lambda2 = -vt2 / c.frictionMass2
            let old2 = c.accumulatedFrictionImpulse2
            c.accumulatedFrictionImpulse2 = max(-maxFriction, min(old2 + lambda2, maxFriction))
            lambda2 = c.accumulatedFrictionImpulse2 - old2

            let impulse2 = c.tangent2 * lambda2
            bodyA.velocity -= impulse2 * bodyA.invMass
            bodyA.angularVelocity -= bodyA.invInertia * simd_cross(c.rA, impulse2)
            bodyB.velocity += impulse2 * bodyB.invMass
            bodyB.angularVelocity += bodyB.invInertia * simd_cross(c.rB, impulse2)
        }

        bodies[c.entityA] = bodyA
        bodies[c.entityB] = bodyB
    }

    // MARK: - Friction Basis

    private func computeFrictionBasis(_ c: inout ContactConstraint, bodyA: BodyState, bodyB: BodyState) {
        let n = c.contact.normal
        var t1: SIMD3<Float>
        if abs(n.x) < 0.9 {
            t1 = simd_cross(n, SIMD3<Float>(1, 0, 0))
        } else {
            t1 = simd_cross(n, SIMD3<Float>(0, 1, 0))
        }
        t1 = simd_normalize(t1)
        let t2 = simd_cross(n, t1)

        c.tangent1 = t1
        c.tangent2 = t2

        let raCrossT1 = simd_cross(c.rA, t1)
        let rbCrossT1 = simd_cross(c.rB, t1)
        c.frictionMass1 = bodyA.invMass + bodyB.invMass
            + simd_dot(raCrossT1, bodyA.invInertia * raCrossT1)
            + simd_dot(rbCrossT1, bodyB.invInertia * rbCrossT1)

        let raCrossT2 = simd_cross(c.rA, t2)
        let rbCrossT2 = simd_cross(c.rB, t2)
        c.frictionMass2 = bodyA.invMass + bodyB.invMass
            + simd_dot(raCrossT2, bodyA.invInertia * raCrossT2)
            + simd_dot(rbCrossT2, bodyB.invInertia * rbCrossT2)
    }
}

// MARK: - Body State

/// Transient per-frame physics state used by the solver.
public struct BodyState {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var velocity: SIMD3<Float>
    public var angularVelocity: SIMD3<Float>
    public var invMass: Float
    public var invInertia: SIMD3<Float>
    public var restitution: Float
    public var friction: Float
}

// MARK: - Contact Constraint

struct ContactConstraint {
    var entityA: Entity
    var entityB: Entity
    var contact: ContactPoint
    var rA: SIMD3<Float>
    var rB: SIMD3<Float>
    var normalMass: Float
    var restitution: Float
    var bias: Float
    var accumulatedNormalImpulse: Float
    var accumulatedFrictionImpulse1: Float
    var accumulatedFrictionImpulse2: Float
    var tangent1: SIMD3<Float>
    var tangent2: SIMD3<Float>
    var frictionMass1: Float
    var frictionMass2: Float
    var friction: Float
}
