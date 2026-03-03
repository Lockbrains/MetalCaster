import simd

/// A triangle defined by three vertices.
public struct MCTriangle: Sendable, Codable, Equatable {
    public var a: SIMD3<Float>
    public var b: SIMD3<Float>
    public var c: SIMD3<Float>

    public init(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) {
        self.a = a
        self.b = b
        self.c = c
    }

    /// Face normal (CCW winding), not normalized.
    @inlinable
    public var normalUnnormalized: SIMD3<Float> {
        simd_cross(b - a, c - a)
    }

    /// Unit face normal (CCW winding).
    @inlinable
    public var normal: SIMD3<Float> {
        simd_normalize(normalUnnormalized)
    }

    /// Area of the triangle.
    @inlinable
    public var area: Float {
        simd_length(normalUnnormalized) * 0.5
    }

    /// Centroid (average of vertices).
    @inlinable
    public var centroid: SIMD3<Float> {
        (a + b + c) / 3.0
    }

    /// The plane containing this triangle.
    @inlinable
    public var plane: MCPlane {
        MCPlane(a: a, b: b, c: c)
    }

    /// Computes barycentric coordinates of a point with respect to this triangle.
    /// The point is assumed to lie on the triangle's plane.
    public func barycentric(of point: SIMD3<Float>) -> SIMD3<Float> {
        let v0 = b - a
        let v1 = c - a
        let v2 = point - a

        let d00 = simd_dot(v0, v0)
        let d01 = simd_dot(v0, v1)
        let d11 = simd_dot(v1, v1)
        let d20 = simd_dot(v2, v0)
        let d21 = simd_dot(v2, v1)

        let denom = d00 * d11 - d01 * d01
        guard abs(denom) > mc_epsilonSq else {
            return SIMD3<Float>(1, 0, 0)
        }

        let v = (d11 * d20 - d01 * d21) / denom
        let w = (d00 * d21 - d01 * d20) / denom
        let u = 1.0 - v - w
        return SIMD3<Float>(u, v, w)
    }

    /// Returns true if the point (assumed on the triangle's plane) is inside the triangle.
    @inlinable
    public func contains(_ point: SIMD3<Float>) -> Bool {
        let bary = barycentric(of: point)
        return bary.x >= -mc_epsilon && bary.y >= -mc_epsilon && bary.z >= -mc_epsilon
    }

    /// Returns the three edges as segments.
    @inlinable
    public var edges: (MCSegment, MCSegment, MCSegment) {
        (MCSegment(start: a, end: b), MCSegment(start: b, end: c), MCSegment(start: c, end: a))
    }

    /// Closest point on the triangle to the given point.
    public func closestPoint(to p: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return a }

        let bp = p - b
        let d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return b }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            let v = d1 / (d1 - d3)
            return a + ab * v
        }

        let cp = p - c
        let d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return c }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            let w = d2 / (d2 - d6)
            return a + ac * w
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return b + (c - b) * w
        }

        let denom = 1.0 / (va + vb + vc)
        let v = vb * denom
        let w = vc * denom
        return a + ab * v + ac * w
    }
}
