import Foundation
import simd
import MetalCasterCore
import MetalCasterScene
import MetalCasterMath

/// Narrowphase collision detection using shape-specific algorithms.
/// Generates ContactManifold with accurate contact points and normals.
public enum Narrowphase {

    /// Tests two colliders and returns a manifold if they overlap.
    public static func test(
        entityA: Entity, posA: SIMD3<Float>, rotA: simd_quatf, colliderA: ColliderComponent,
        entityB: Entity, posB: SIMD3<Float>, rotB: simd_quatf, colliderB: ColliderComponent
    ) -> ContactManifold? {
        let isTrigger = colliderA.isTrigger || colliderB.isTrigger

        let contact: ContactPoint?
        switch (colliderA.shape, colliderB.shape) {
        case (.sphere, .sphere):
            contact = sphereVsSphere(posA: posA, rA: colliderA.radius, posB: posB, rB: colliderB.radius)
        case (.sphere, .box):
            contact = sphereVsBox(
                spherePos: posA, sphereR: colliderA.radius,
                boxPos: posB, boxRot: rotB, boxHalf: colliderB.halfExtents
            )
        case (.box, .sphere):
            if let c = sphereVsBox(
                spherePos: posB, sphereR: colliderB.radius,
                boxPos: posA, boxRot: rotA, boxHalf: colliderA.halfExtents
            ) {
                contact = ContactPoint(position: c.position, normal: -c.normal, penetration: c.penetration)
            } else {
                contact = nil
            }
        case (.box, .box):
            contact = boxVsBox(
                posA: posA, rotA: rotA, halfA: colliderA.halfExtents,
                posB: posB, rotB: rotB, halfB: colliderB.halfExtents
            )
        case (.sphere, .capsule):
            contact = sphereVsCapsule(
                spherePos: posA, sphereR: colliderA.radius,
                capPos: posB, capRot: rotB, capR: colliderB.radius, capHalf: colliderB.halfExtents.y
            )
        case (.capsule, .sphere):
            if let c = sphereVsCapsule(
                spherePos: posB, sphereR: colliderB.radius,
                capPos: posA, capRot: rotA, capR: colliderA.radius, capHalf: colliderA.halfExtents.y
            ) {
                contact = ContactPoint(position: c.position, normal: -c.normal, penetration: c.penetration)
            } else {
                contact = nil
            }
        case (.capsule, .capsule):
            contact = capsuleVsCapsule(
                posA: posA, rotA: rotA, rA: colliderA.radius, halfA: colliderA.halfExtents.y,
                posB: posB, rotB: rotB, rB: colliderB.radius, halfB: colliderB.halfExtents.y
            )
        case (.capsule, .box), (.box, .capsule):
            // Approximate capsule as sphere at closest segment point
            let (capIdx, boxIdx) = colliderA.shape == .capsule ? (0, 1) : (1, 0)
            let capPos = capIdx == 0 ? posA : posB
            let capRot = capIdx == 0 ? rotA : rotB
            let capR = capIdx == 0 ? colliderA.radius : colliderB.radius
            let capH = capIdx == 0 ? colliderA.halfExtents.y : colliderB.halfExtents.y
            let boxPos2 = boxIdx == 0 ? posA : posB
            let boxRot2 = boxIdx == 0 ? rotA : rotB
            let boxHalf2 = boxIdx == 0 ? colliderA.halfExtents : colliderB.halfExtents

            let up = capRot.act(SIMD3<Float>(0, 1, 0))
            let capA = capPos + up * capH
            let capB = capPos - up * capH
            let closest = closestPointOnSegment(point: boxPos2, a: capA, b: capB)

            if let c = sphereVsBox(spherePos: closest, sphereR: capR, boxPos: boxPos2, boxRot: boxRot2, boxHalf: boxHalf2) {
                if capIdx == 0 {
                    contact = c
                } else {
                    contact = ContactPoint(position: c.position, normal: -c.normal, penetration: c.penetration)
                }
            } else {
                contact = nil
            }
        }

        guard let c = contact else { return nil }
        return ContactManifold(entityA: entityA, entityB: entityB, contacts: [c], isTrigger: isTrigger)
    }

    // MARK: - Sphere vs Sphere

    private static func sphereVsSphere(posA: SIMD3<Float>, rA: Float, posB: SIMD3<Float>, rB: Float) -> ContactPoint? {
        let diff = posB - posA
        let dist = simd_length(diff)
        let sumR = rA + rB
        guard dist < sumR else { return nil }

        let normal = dist > 1e-6 ? diff / dist : SIMD3<Float>(0, 1, 0)
        let penetration = sumR - dist
        let point = posA + normal * (rA - penetration * 0.5)
        return ContactPoint(position: point, normal: normal, penetration: penetration)
    }

    // MARK: - Sphere vs Box (OBB)

    private static func sphereVsBox(
        spherePos: SIMD3<Float>, sphereR: Float,
        boxPos: SIMD3<Float>, boxRot: simd_quatf, boxHalf: SIMD3<Float>
    ) -> ContactPoint? {
        let obb = MCOBB(center: boxPos, halfExtents: boxHalf, rotation: boxRot)
        let closest = obb.closestPoint(to: spherePos)
        let diff = spherePos - closest
        let distSq = simd_length_squared(diff)

        guard distSq < sphereR * sphereR else { return nil }

        let dist = sqrt(distSq)
        let normal = dist > 1e-6 ? diff / dist : SIMD3<Float>(0, 1, 0)
        let penetration = sphereR - dist
        return ContactPoint(position: closest, normal: -normal, penetration: penetration)
    }

    // MARK: - Box vs Box (SAT with contact point)

    private static func boxVsBox(
        posA: SIMD3<Float>, rotA: simd_quatf, halfA: SIMD3<Float>,
        posB: SIMD3<Float>, rotB: simd_quatf, halfB: SIMD3<Float>
    ) -> ContactPoint? {
        let axesA = [rotA.act(SIMD3<Float>(1, 0, 0)), rotA.act(SIMD3<Float>(0, 1, 0)), rotA.act(SIMD3<Float>(0, 0, 1))]
        let axesB = [rotB.act(SIMD3<Float>(1, 0, 0)), rotB.act(SIMD3<Float>(0, 1, 0)), rotB.act(SIMD3<Float>(0, 0, 1))]
        let halfAArr = [halfA.x, halfA.y, halfA.z]
        let halfBArr = [halfB.x, halfB.y, halfB.z]

        let t = posB - posA
        var minOverlap: Float = .greatestFiniteMagnitude
        var minAxis = SIMD3<Float>(0, 1, 0)

        func testAxis(_ axis: SIMD3<Float>) -> Bool {
            let len = simd_length(axis)
            guard len > 1e-6 else { return true }
            let n = axis / len

            var projA: Float = 0
            for i in 0..<3 { projA += halfAArr[i] * abs(simd_dot(axesA[i], n)) }
            var projB: Float = 0
            for i in 0..<3 { projB += halfBArr[i] * abs(simd_dot(axesB[i], n)) }

            let d = abs(simd_dot(t, n))
            let overlap = projA + projB - d
            guard overlap > 0 else { return false }

            if overlap < minOverlap {
                minOverlap = overlap
                minAxis = simd_dot(t, n) < 0 ? -n : n
            }
            return true
        }

        for i in 0..<3 { if !testAxis(axesA[i]) { return nil } }
        for i in 0..<3 { if !testAxis(axesB[i]) { return nil } }

        for i in 0..<3 {
            for j in 0..<3 {
                let cross = simd_cross(axesA[i], axesB[j])
                if !testAxis(cross) { return nil }
            }
        }

        let contactPos = posA + minAxis * (minOverlap * 0.5)
        return ContactPoint(position: contactPos, normal: minAxis, penetration: minOverlap)
    }

    // MARK: - Sphere vs Capsule

    private static func sphereVsCapsule(
        spherePos: SIMD3<Float>, sphereR: Float,
        capPos: SIMD3<Float>, capRot: simd_quatf, capR: Float, capHalf: Float
    ) -> ContactPoint? {
        let up = capRot.act(SIMD3<Float>(0, 1, 0))
        let capA = capPos + up * capHalf
        let capB = capPos - up * capHalf
        let closest = closestPointOnSegment(point: spherePos, a: capA, b: capB)
        return sphereVsSphere(posA: spherePos, rA: sphereR, posB: closest, rB: capR)
    }

    // MARK: - Capsule vs Capsule

    private static func capsuleVsCapsule(
        posA: SIMD3<Float>, rotA: simd_quatf, rA: Float, halfA: Float,
        posB: SIMD3<Float>, rotB: simd_quatf, rB: Float, halfB: Float
    ) -> ContactPoint? {
        let upA = rotA.act(SIMD3<Float>(0, 1, 0))
        let a0 = posA - upA * halfA, a1 = posA + upA * halfA
        let upB = rotB.act(SIMD3<Float>(0, 1, 0))
        let b0 = posB - upB * halfB, b1 = posB + upB * halfB

        let (closestA, closestB) = closestPointsBetweenSegments(a0: a0, a1: a1, b0: b0, b1: b1)
        return sphereVsSphere(posA: closestA, rA: rA, posB: closestB, rB: rB)
    }

    // MARK: - Geometry Helpers

    private static func closestPointOnSegment(point: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a
        let lenSq = simd_length_squared(ab)
        guard lenSq > 1e-10 else { return a }
        let t = simd_clamp(simd_dot(point - a, ab) / lenSq, 0, 1)
        return a + ab * t
    }

    private static func closestPointsBetweenSegments(
        a0: SIMD3<Float>, a1: SIMD3<Float>, b0: SIMD3<Float>, b1: SIMD3<Float>
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        let d1 = a1 - a0
        let d2 = b1 - b0
        let r = a0 - b0
        let a = simd_dot(d1, d1)
        let e = simd_dot(d2, d2)
        let f = simd_dot(d2, r)

        var s: Float = 0, t: Float = 0

        if a <= 1e-10 && e <= 1e-10 {
            return (a0, b0)
        }

        if a <= 1e-10 {
            t = simd_clamp(f / e, 0, 1)
        } else {
            let c = simd_dot(d1, r)
            if e <= 1e-10 {
                s = simd_clamp(-c / a, 0, 1)
            } else {
                let b = simd_dot(d1, d2)
                let denom = a * e - b * b
                if denom != 0 {
                    s = simd_clamp((b * f - c * e) / denom, 0, 1)
                }
                t = (b * s + f) / e
                if t < 0 {
                    t = 0; s = simd_clamp(-c / a, 0, 1)
                } else if t > 1 {
                    t = 1; s = simd_clamp((b - c) / a, 0, 1)
                }
            }
        }

        return (a0 + d1 * s, b0 + d2 * t)
    }
}
