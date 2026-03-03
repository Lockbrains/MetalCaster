import simd

/// An infinite line defined by a point and direction.
public struct MCLine: Sendable, Codable, Equatable {
    public var origin: SIMD3<Float>
    public var direction: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = simd_normalize(direction)
    }

    /// Creates a line passing through two points.
    public init(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        self.origin = a
        self.direction = simd_normalize(b - a)
    }

    /// Returns the point on the line at parameter `t`.
    @inlinable
    public func point(at t: Float) -> SIMD3<Float> {
        origin + direction * t
    }

    /// Returns the closest point on the line to the given point.
    @inlinable
    public func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let t = simd_dot(point - origin, direction)
        return origin + direction * t
    }

    /// Distance from a point to this line.
    @inlinable
    public func distance(to point: SIMD3<Float>) -> Float {
        let cp = closestPoint(to: point)
        return simd_distance(cp, point)
    }

    /// Closest distance between two lines. Returns the pair of closest points.
    public func closestApproach(to other: MCLine) -> (pointOnSelf: SIMD3<Float>, pointOnOther: SIMD3<Float>, distance: Float) {
        let w0 = origin - other.origin
        let a = simd_dot(direction, direction)
        let b = simd_dot(direction, other.direction)
        let c = simd_dot(other.direction, other.direction)
        let d = simd_dot(direction, w0)
        let e = simd_dot(other.direction, w0)

        let denom = a * c - b * b
        let s: Float
        let t: Float

        if abs(denom) < mc_epsilon {
            s = 0
            t = d / b
        } else {
            s = (b * e - c * d) / denom
            t = (a * e - b * d) / denom
        }

        let p1 = point(at: s)
        let p2 = other.point(at: t)
        return (p1, p2, simd_distance(p1, p2))
    }
}

// MARK: - Line Segment

/// A finite line segment defined by two endpoints.
public struct MCSegment: Sendable, Codable, Equatable {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>

    public init(start: SIMD3<Float>, end: SIMD3<Float>) {
        self.start = start
        self.end = end
    }

    @inlinable public var direction: SIMD3<Float> { simd_normalize(end - start) }
    @inlinable public var length: Float { simd_distance(start, end) }
    @inlinable public var lengthSquared: Float { simd_distance_squared(start, end) }
    @inlinable public var midpoint: SIMD3<Float> { (start + end) * 0.5 }

    /// Returns the closest point on the segment to the given point.
    @inlinable
    public func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let ab = end - start
        let ap = point - start
        let lenSq = simd_length_squared(ab)
        guard lenSq > mc_epsilonSq else { return start }
        let t = (simd_dot(ap, ab) / lenSq).clamped(to: 0...1)
        return start + ab * t
    }

    /// Distance from a point to this segment.
    @inlinable
    public func distance(to point: SIMD3<Float>) -> Float {
        simd_distance(closestPoint(to: point), point)
    }

    /// Returns the point at parametric position `t` (0 = start, 1 = end).
    @inlinable
    public func point(at t: Float) -> SIMD3<Float> {
        start + (end - start) * t
    }

    /// Converts to an MCRay originating at `start`.
    @inlinable
    public var asRay: MCRay {
        MCRay(origin: start, direction: end - start)
    }
}
