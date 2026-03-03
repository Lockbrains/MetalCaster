import simd

/// A plane in 3D space defined by a normal and distance from origin.
/// The plane equation is: dot(normal, point) + distance = 0.
public struct MCPlane: Sendable, Codable, Equatable {
    public var normal: SIMD3<Float>
    /// Signed distance from the origin along the normal. Positive means the
    /// origin is on the back side of the plane.
    public var distance: Float

    public init(normal: SIMD3<Float>, distance: Float) {
        self.normal = simd_normalize(normal)
        self.distance = distance
    }

    /// Creates a plane from a normal and a point on the plane.
    public init(normal: SIMD3<Float>, point: SIMD3<Float>) {
        let n = simd_normalize(normal)
        self.normal = n
        self.distance = -simd_dot(n, point)
    }

    /// Creates a plane from three non-collinear points (CCW winding).
    public init(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) {
        let n = simd_normalize(simd_cross(b - a, c - a))
        self.normal = n
        self.distance = -simd_dot(n, a)
    }

    /// Signed distance from the plane to a point.
    /// Positive = front side (same side as normal), negative = back side.
    @inlinable
    public func signedDistance(to point: SIMD3<Float>) -> Float {
        simd_dot(normal, point) + distance
    }

    /// Unsigned distance from the plane to a point.
    @inlinable
    public func distance(to point: SIMD3<Float>) -> Float {
        abs(signedDistance(to: point))
    }

    /// Projects a point onto the plane.
    @inlinable
    public func project(_ point: SIMD3<Float>) -> SIMD3<Float> {
        point - signedDistance(to: point) * normal
    }

    /// Returns which side of the plane a point is on.
    @inlinable
    public func side(of point: SIMD3<Float>) -> PlaneSide {
        let d = signedDistance(to: point)
        if d > mc_epsilon { return .front }
        if d < -mc_epsilon { return .back }
        return .on
    }

    /// The flipped plane (facing the opposite direction).
    @inlinable
    public var flipped: MCPlane {
        MCPlane(normal: -normal, distance: -distance)
    }

    /// The closest point on the plane to the origin.
    @inlinable
    public var closestPointToOrigin: SIMD3<Float> {
        -normal * distance
    }
}

public enum PlaneSide: Sendable {
    case front, back, on
}
