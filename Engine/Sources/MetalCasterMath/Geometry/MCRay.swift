import simd

/// An infinite ray defined by an origin and a direction.
public struct MCRay: Sendable, Codable, Equatable {
    public var origin: SIMD3<Float>
    public var direction: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = simd_normalize(direction)
    }

    /// Returns the point along the ray at parameter `t`.
    @inlinable
    public func point(at t: Float) -> SIMD3<Float> {
        origin + direction * t
    }

    /// Returns the closest point on the ray to the given point.
    @inlinable
    public func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let t = max(0, simd_dot(point - origin, direction))
        return origin + direction * t
    }

    /// Squared distance from a point to the ray.
    @inlinable
    public func distanceSquared(to point: SIMD3<Float>) -> Float {
        let cp = closestPoint(to: point)
        return simd_distance_squared(cp, point)
    }

    /// Distance from a point to the ray.
    @inlinable
    public func distance(to point: SIMD3<Float>) -> Float {
        sqrt(distanceSquared(to: point))
    }

    /// Returns a ray transformed by a 4x4 matrix.
    @inlinable
    public func transformed(by m: simd_float4x4) -> MCRay {
        MCRay(
            origin: m.transformPoint(origin),
            direction: m.transformDirection(direction)
        )
    }
}
