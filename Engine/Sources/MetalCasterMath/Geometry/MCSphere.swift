import simd

/// A sphere defined by a center point and radius.
public struct MCSphere: Sendable, Codable, Equatable {
    public var center: SIMD3<Float>
    public var radius: Float

    public init(center: SIMD3<Float> = .zero, radius: Float = 1) {
        self.center = center
        self.radius = radius
    }

    /// Creates a bounding sphere that encloses the given points.
    public init(enclosing points: [SIMD3<Float>]) {
        guard !points.isEmpty else {
            self.center = .zero
            self.radius = 0
            return
        }

        var sum = SIMD3<Float>.zero
        for p in points { sum += p }
        let c = sum / Float(points.count)

        var maxDistSq: Float = 0
        for p in points {
            maxDistSq = max(maxDistSq, simd_distance_squared(c, p))
        }

        self.center = c
        self.radius = sqrt(maxDistSq)
    }

    /// Returns true if the point is inside or on the sphere.
    @inlinable
    public func contains(_ point: SIMD3<Float>) -> Bool {
        simd_distance_squared(center, point) <= radius * radius + mc_epsilon
    }

    /// Returns a point on the surface given spherical coordinates (theta, phi in radians).
    @inlinable
    public func surfacePoint(theta: Float, phi: Float) -> SIMD3<Float> {
        let sinPhi = sin(phi)
        return center + radius * SIMD3<Float>(
            sinPhi * cos(theta),
            cos(phi),
            sinPhi * sin(theta)
        )
    }

    /// Volume of the sphere.
    @inlinable
    public var volume: Float {
        (4.0 / 3.0) * .pi * radius * radius * radius
    }

    /// Surface area of the sphere.
    @inlinable
    public var surfaceArea: Float {
        4.0 * .pi * radius * radius
    }

    /// Grows the sphere to also enclose the given point.
    @inlinable
    public mutating func encapsulate(_ point: SIMD3<Float>) {
        let dist = simd_distance(center, point)
        if dist > radius {
            let newRadius = (radius + dist) * 0.5
            let k = (newRadius - radius) / dist
            center += (point - center) * k
            radius = newRadius
        }
    }

    /// Grows the sphere to also enclose another sphere.
    @inlinable
    public mutating func encapsulate(_ other: MCSphere) {
        let d = simd_distance(center, other.center)
        if d + other.radius <= radius { return }
        if d + radius <= other.radius {
            center = other.center
            radius = other.radius
            return
        }
        let newRadius = (d + radius + other.radius) * 0.5
        let k = (newRadius - radius) / d
        center += (other.center - center) * k
        radius = newRadius
    }
}
