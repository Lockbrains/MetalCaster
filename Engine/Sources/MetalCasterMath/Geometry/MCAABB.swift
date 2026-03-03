import simd

/// An axis-aligned bounding box defined by minimum and maximum corners.
public struct MCAABB: Sendable, Codable, Equatable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    /// Creates an AABB from a center and half-extents.
    public init(center: SIMD3<Float>, halfExtents: SIMD3<Float>) {
        self.min = center - halfExtents
        self.max = center + halfExtents
    }

    /// Creates a bounding box enclosing the given points.
    public init(enclosing points: [SIMD3<Float>]) {
        guard let first = points.first else {
            self.min = .zero
            self.max = .zero
            return
        }
        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        self.min = lo
        self.max = hi
    }

    /// A zero-sized AABB at the origin.
    public static let zero = MCAABB(min: .zero, max: .zero)

    /// An "inverted" AABB used as a starting point for encapsulation.
    public static let inverted = MCAABB(
        min: SIMD3<Float>(repeating: Float.greatestFiniteMagnitude),
        max: SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
    )

    @inlinable public var center: SIMD3<Float> { (min + max) * 0.5 }
    @inlinable public var size: SIMD3<Float> { max - min }
    @inlinable public var halfExtents: SIMD3<Float> { (max - min) * 0.5 }
    @inlinable public var volume: Float { let s = size; return s.x * s.y * s.z }
    @inlinable public var surfaceArea: Float {
        let s = size
        return 2 * (s.x * s.y + s.y * s.z + s.z * s.x)
    }

    /// Returns true if the point is inside or on the AABB.
    @inlinable
    public func contains(_ point: SIMD3<Float>) -> Bool {
        point.x >= min.x && point.x <= max.x &&
        point.y >= min.y && point.y <= max.y &&
        point.z >= min.z && point.z <= max.z
    }

    /// Returns true if this AABB fully contains another.
    @inlinable
    public func contains(_ other: MCAABB) -> Bool {
        other.min.x >= min.x && other.max.x <= max.x &&
        other.min.y >= min.y && other.max.y <= max.y &&
        other.min.z >= min.z && other.max.z <= max.z
    }

    /// Returns true if this AABB intersects another.
    @inlinable
    public func intersects(_ other: MCAABB) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x &&
        min.y <= other.max.y && max.y >= other.min.y &&
        min.z <= other.max.z && max.z >= other.min.z
    }

    /// Grows this AABB to include the given point.
    @inlinable
    public mutating func encapsulate(_ point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    /// Grows this AABB to include another AABB.
    @inlinable
    public mutating func encapsulate(_ other: MCAABB) {
        min = simd_min(min, other.min)
        max = simd_max(max, other.max)
    }

    /// Returns the union of two AABBs.
    @inlinable
    public func union(_ other: MCAABB) -> MCAABB {
        MCAABB(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }

    /// Returns the intersection of two AABBs, or nil if they don't overlap.
    @inlinable
    public func intersection(_ other: MCAABB) -> MCAABB? {
        let lo = simd_max(min, other.min)
        let hi = simd_min(max, other.max)
        guard lo.x <= hi.x && lo.y <= hi.y && lo.z <= hi.z else { return nil }
        return MCAABB(min: lo, max: hi)
    }

    /// Returns the closest point on or inside the AABB to the given point.
    @inlinable
    public func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        simd_clamp(point, min, max)
    }

    /// Squared distance from a point to the AABB surface.
    @inlinable
    public func distanceSquared(to point: SIMD3<Float>) -> Float {
        let cp = closestPoint(to: point)
        return simd_distance_squared(cp, point)
    }

    /// Expands the AABB by `amount` on each side.
    @inlinable
    public func expanded(by amount: Float) -> MCAABB {
        let e = SIMD3<Float>(repeating: amount)
        return MCAABB(min: min - e, max: max + e)
    }

    /// Returns the eight corners of the AABB.
    public var corners: [SIMD3<Float>] {
        [
            SIMD3<Float>(min.x, min.y, min.z),
            SIMD3<Float>(max.x, min.y, min.z),
            SIMD3<Float>(min.x, max.y, min.z),
            SIMD3<Float>(max.x, max.y, min.z),
            SIMD3<Float>(min.x, min.y, max.z),
            SIMD3<Float>(max.x, min.y, max.z),
            SIMD3<Float>(min.x, max.y, max.z),
            SIMD3<Float>(max.x, max.y, max.z),
        ]
    }

    /// Transforms this AABB by a 4x4 matrix, returning a new AABB enclosing the result.
    public func transformed(by m: simd_float4x4) -> MCAABB {
        var result = MCAABB.inverted
        for corner in corners {
            result.encapsulate(m.transformPoint(corner))
        }
        return result
    }
}
