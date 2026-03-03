import simd

/// Result of a ray intersection test that returns contact information.
public struct MCHit: Sendable, Equatable {
    /// The intersection point in world space.
    public var point: SIMD3<Float>
    /// The surface normal at the intersection point.
    public var normal: SIMD3<Float>
    /// The parametric distance along the ray (point = ray.origin + ray.direction * distance).
    public var distance: Float

    public init(point: SIMD3<Float>, normal: SIMD3<Float>, distance: Float) {
        self.point = point
        self.normal = normal
        self.distance = distance
    }
}

/// Centralized intersection testing between geometric primitives.
public enum MCIntersection {

    // MARK: - Ray vs Plane

    /// Returns the hit where a ray intersects a plane, or nil if parallel / behind origin.
    public static func test(_ ray: MCRay, _ plane: MCPlane) -> MCHit? {
        let denom = simd_dot(plane.normal, ray.direction)
        guard abs(denom) > mc_epsilon else { return nil }

        let t = -(simd_dot(plane.normal, ray.origin) + plane.distance) / denom
        guard t >= 0 else { return nil }

        return MCHit(
            point: ray.point(at: t),
            normal: plane.normal,
            distance: t
        )
    }

    // MARK: - Ray vs Sphere

    public static func test(_ ray: MCRay, _ sphere: MCSphere) -> MCHit? {
        let oc = ray.origin - sphere.center
        let b = simd_dot(oc, ray.direction)
        let c = simd_dot(oc, oc) - sphere.radius * sphere.radius
        let disc = b * b - c
        guard disc >= 0 else { return nil }

        let sqrtDisc = sqrt(disc)
        var t = -b - sqrtDisc
        if t < 0 { t = -b + sqrtDisc }
        guard t >= 0 else { return nil }

        let p = ray.point(at: t)
        let n = simd_normalize(p - sphere.center)
        return MCHit(point: p, normal: n, distance: t)
    }

    // MARK: - Ray vs AABB (Slab method)

    public static func test(_ ray: MCRay, _ aabb: MCAABB) -> MCHit? {
        let invDir = SIMD3<Float>(
            abs(ray.direction.x) > mc_epsilon ? 1.0 / ray.direction.x : (ray.direction.x >= 0 ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude),
            abs(ray.direction.y) > mc_epsilon ? 1.0 / ray.direction.y : (ray.direction.y >= 0 ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude),
            abs(ray.direction.z) > mc_epsilon ? 1.0 / ray.direction.z : (ray.direction.z >= 0 ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude)
        )

        let t1 = (aabb.min - ray.origin) * invDir
        let t2 = (aabb.max - ray.origin) * invDir

        let tMin3 = simd_min(t1, t2)
        let tMax3 = simd_max(t1, t2)

        let tEnter = max(tMin3.x, max(tMin3.y, tMin3.z))
        let tExit  = min(tMax3.x, min(tMax3.y, tMax3.z))

        guard tExit >= tEnter && tExit >= 0 else { return nil }

        let t = tEnter >= 0 ? tEnter : tExit
        let p = ray.point(at: t)

        var normal = SIMD3<Float>.zero
        let c = aabb.center
        let d = p - c
        let halfSize = aabb.halfExtents
        let bias: Float = 1.0 + mc_epsilon
        if abs(d.x / halfSize.x) * bias >= abs(d.y / halfSize.y) && abs(d.x / halfSize.x) * bias >= abs(d.z / halfSize.z) {
            normal.x = d.x > 0 ? 1 : -1
        } else if abs(d.y / halfSize.y) * bias >= abs(d.z / halfSize.z) {
            normal.y = d.y > 0 ? 1 : -1
        } else {
            normal.z = d.z > 0 ? 1 : -1
        }

        return MCHit(point: p, normal: normal, distance: t)
    }

    // MARK: - Ray vs OBB

    /// Transforms the ray into OBB local space, then uses the AABB slab test.
    public static func test(_ ray: MCRay, _ obb: MCOBB) -> MCHit? {
        let invQ = obb.rotation.conjugated
        let localOrigin = invQ.act(ray.origin - obb.center)
        let localDir = invQ.act(ray.direction)
        let localRay = MCRay(origin: localOrigin, direction: localDir)
        let localAABB = MCAABB(center: .zero, halfExtents: obb.halfExtents)

        guard var hit = test(localRay, localAABB) else { return nil }
        hit.point = obb.rotation.act(hit.point) + obb.center
        hit.normal = obb.rotation.act(hit.normal)
        return hit
    }

    // MARK: - Ray vs Triangle (Moller-Trumbore)

    public static func test(_ ray: MCRay, _ tri: MCTriangle) -> MCHit? {
        let e1 = tri.b - tri.a
        let e2 = tri.c - tri.a
        let h = simd_cross(ray.direction, e2)
        let a = simd_dot(e1, h)

        guard abs(a) > mc_epsilon else { return nil }

        let f = 1.0 / a
        let s = ray.origin - tri.a
        let u = f * simd_dot(s, h)
        guard u >= 0 && u <= 1 else { return nil }

        let q = simd_cross(s, e1)
        let v = f * simd_dot(ray.direction, q)
        guard v >= 0 && u + v <= 1 else { return nil }

        let t = f * simd_dot(e2, q)
        guard t > mc_epsilon else { return nil }

        return MCHit(
            point: ray.point(at: t),
            normal: tri.normal,
            distance: t
        )
    }

    // MARK: - Ray vs Rect3D

    public static func test(_ ray: MCRay, _ rect: MCRect3D) -> MCHit? {
        guard let planeHit = test(ray, rect.plane) else { return nil }
        guard rect.contains(planeHit.point) else { return nil }
        return planeHit
    }

    // MARK: - Sphere vs Sphere

    public static func test(_ a: MCSphere, _ b: MCSphere) -> Bool {
        let rSum = a.radius + b.radius
        return simd_distance_squared(a.center, b.center) <= rSum * rSum
    }

    // MARK: - Sphere vs AABB

    public static func test(_ sphere: MCSphere, _ aabb: MCAABB) -> Bool {
        aabb.distanceSquared(to: sphere.center) <= sphere.radius * sphere.radius
    }

    // MARK: - AABB vs AABB

    public static func test(_ a: MCAABB, _ b: MCAABB) -> Bool {
        a.intersects(b)
    }

    // MARK: - AABB vs Frustum

    public static func test(_ aabb: MCAABB, _ frustum: MCFrustum) -> Bool {
        frustum.intersects(aabb)
    }

    // MARK: - Sphere vs Frustum

    public static func test(_ sphere: MCSphere, _ frustum: MCFrustum) -> Bool {
        frustum.intersects(sphere)
    }

    // MARK: - OBB vs OBB (Separating Axis Theorem)

    public static func test(_ a: MCOBB, _ b: MCOBB) -> Bool {
        let (aX, aY, aZ) = a.axes
        let (bX, bY, bZ) = b.axes
        let aAxes = [aX, aY, aZ]
        let bAxes = [bX, bY, bZ]

        let t = b.center - a.center

        let aE = [a.halfExtents.x, a.halfExtents.y, a.halfExtents.z]
        let bE = [b.halfExtents.x, b.halfExtents.y, b.halfExtents.z]

        var r = [[Float]](repeating: [Float](repeating: 0, count: 3), count: 3)
        var absR = [[Float]](repeating: [Float](repeating: 0, count: 3), count: 3)

        for i in 0..<3 {
            for j in 0..<3 {
                r[i][j] = simd_dot(aAxes[i], bAxes[j])
                absR[i][j] = abs(r[i][j]) + mc_epsilon
            }
        }

        for i in 0..<3 {
            let ra = aE[i]
            let rb = bE[0] * absR[i][0] + bE[1] * absR[i][1] + bE[2] * absR[i][2]
            if abs(simd_dot(t, aAxes[i])) > ra + rb { return false }
        }

        for j in 0..<3 {
            let ra = aE[0] * absR[0][j] + aE[1] * absR[1][j] + aE[2] * absR[2][j]
            let rb = bE[j]
            if abs(simd_dot(t, bAxes[j])) > ra + rb { return false }
        }

        // Cross product axes (9 tests)
        for i in 0..<3 {
            for j in 0..<3 {
                let i1 = (i + 1) % 3, i2 = (i + 2) % 3
                let j1 = (j + 1) % 3, j2 = (j + 2) % 3
                let ra = aE[i1] * absR[i2][j] + aE[i2] * absR[i1][j]
                let rb = bE[j1] * absR[i][j2] + bE[j2] * absR[i][j1]
                let proj = abs(simd_dot(t, aAxes[i1]) * r[i2][j] - simd_dot(t, aAxes[i2]) * r[i1][j])
                if proj > ra + rb { return false }
            }
        }

        return true
    }

    // MARK: - Sphere vs OBB

    public static func test(_ sphere: MCSphere, _ obb: MCOBB) -> Bool {
        let closest = obb.closestPoint(to: sphere.center)
        return simd_distance_squared(closest, sphere.center) <= sphere.radius * sphere.radius
    }

    // MARK: - Point containment helpers

    /// Returns true if a point is inside a triangle.
    public static func pointInTriangle(_ point: SIMD3<Float>, _ tri: MCTriangle) -> Bool {
        tri.contains(point)
    }

    /// Returns true if a point is inside a sphere.
    public static func pointInSphere(_ point: SIMD3<Float>, _ sphere: MCSphere) -> Bool {
        sphere.contains(point)
    }

    /// Returns true if a point is inside an AABB.
    public static func pointInAABB(_ point: SIMD3<Float>, _ aabb: MCAABB) -> Bool {
        aabb.contains(point)
    }

    /// Returns true if a point is inside an OBB.
    public static func pointInOBB(_ point: SIMD3<Float>, _ obb: MCOBB) -> Bool {
        obb.contains(point)
    }

    // MARK: - Segment vs Plane

    /// Returns the intersection point of a segment and a plane, or nil.
    public static func test(_ segment: MCSegment, _ plane: MCPlane) -> MCHit? {
        let dir = segment.end - segment.start
        let len = simd_length(dir)
        guard len > mc_epsilon else { return nil }
        let ray = MCRay(origin: segment.start, direction: dir / len)
        guard let hit = test(ray, plane), hit.distance <= len else { return nil }
        return hit
    }

    // MARK: - Segment vs Sphere

    public static func test(_ segment: MCSegment, _ sphere: MCSphere) -> MCHit? {
        let dir = segment.end - segment.start
        let len = simd_length(dir)
        guard len > mc_epsilon else { return nil }
        let ray = MCRay(origin: segment.start, direction: dir / len)
        guard let hit = test(ray, sphere), hit.distance <= len else { return nil }
        return hit
    }

    // MARK: - Segment vs AABB

    public static func test(_ segment: MCSegment, _ aabb: MCAABB) -> MCHit? {
        let dir = segment.end - segment.start
        let len = simd_length(dir)
        guard len > mc_epsilon else { return nil }
        let ray = MCRay(origin: segment.start, direction: dir / len)
        guard let hit = test(ray, aabb), hit.distance <= len else { return nil }
        return hit
    }

    // MARK: - Segment vs Triangle

    public static func test(_ segment: MCSegment, _ tri: MCTriangle) -> MCHit? {
        let dir = segment.end - segment.start
        let len = simd_length(dir)
        guard len > mc_epsilon else { return nil }
        let ray = MCRay(origin: segment.start, direction: dir / len)
        guard let hit = test(ray, tri), hit.distance <= len else { return nil }
        return hit
    }

    // MARK: - Plane vs Plane (line of intersection)

    /// Returns the line of intersection of two non-parallel planes, or nil.
    public static func test(_ a: MCPlane, _ b: MCPlane) -> MCLine? {
        let dir = simd_cross(a.normal, b.normal)
        let denom = simd_dot(dir, dir)
        guard denom > mc_epsilonSq else { return nil }

        let point = (simd_cross(dir, b.normal) * a.distance + simd_cross(a.normal, dir) * b.distance) / denom
        return MCLine(origin: point, direction: dir)
    }
}
