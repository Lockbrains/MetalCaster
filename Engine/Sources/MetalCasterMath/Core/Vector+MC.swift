import simd

// MARK: - SIMD2<Float>

extension SIMD2 where Scalar == Float {

    /// Unit vector pointing right (+X).
    public static let right = SIMD2<Float>(1, 0)
    /// Unit vector pointing up (+Y).
    public static let up    = SIMD2<Float>(0, 1)
    /// All components set to one.
    public static let one   = SIMD2<Float>(1, 1)

    @inlinable public var magnitude: Float { simd_length(self) }
    @inlinable public var magnitudeSquared: Float { simd_length_squared(self) }
    @inlinable public var normalized: SIMD2<Float> { simd_normalize(self) }

    /// Returns the perpendicular vector (rotated 90 degrees counter-clockwise).
    @inlinable
    public var perpendicular: SIMD2<Float> {
        SIMD2<Float>(-y, x)
    }

    @inlinable
    public func dot(_ other: SIMD2<Float>) -> Float {
        simd_dot(self, other)
    }

    /// 2D cross product (returns scalar: the z-component of the 3D cross product).
    @inlinable
    public func cross(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }

    @inlinable
    public func distance(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }

    @inlinable
    public func distanceSquared(to other: SIMD2<Float>) -> Float {
        simd_distance_squared(self, other)
    }

    @inlinable
    public func angle(to other: SIMD2<Float>) -> Float {
        atan2(cross(other), dot(other))
    }

    @inlinable
    public func clamped(maxLength: Float) -> SIMD2<Float> {
        let sq = magnitudeSquared
        guard sq > maxLength * maxLength else { return self }
        return self * (maxLength / sqrt(sq))
    }

    @inlinable
    public func approxEqual(_ other: SIMD2<Float>, epsilon: Float = mc_epsilon) -> Bool {
        abs(x - other.x) <= epsilon && abs(y - other.y) <= epsilon
    }

    @inlinable
    public func projected(onto v: SIMD2<Float>) -> SIMD2<Float> {
        v * (dot(v) / v.dot(v))
    }
}

// MARK: - SIMD3<Float>

extension SIMD3 where Scalar == Float {

    /// Right-handed coordinate directions.
    public static let right   = SIMD3<Float>(1, 0, 0)
    public static let up      = SIMD3<Float>(0, 1, 0)
    public static let forward = SIMD3<Float>(0, 0, -1)
    public static let one     = SIMD3<Float>(1, 1, 1)

    @inlinable public var magnitude: Float { simd_length(self) }
    @inlinable public var magnitudeSquared: Float { simd_length_squared(self) }
    @inlinable public var normalized: SIMD3<Float> { simd_normalize(self) }

    @inlinable
    public func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }

    @inlinable
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    @inlinable
    public func distance(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    @inlinable
    public func distanceSquared(to other: SIMD3<Float>) -> Float {
        simd_distance_squared(self, other)
    }

    /// Angle in radians between this vector and `other`.
    @inlinable
    public func angle(to other: SIMD3<Float>) -> Float {
        let d = simd_dot(simd_normalize(self), simd_normalize(other))
        return acos(d.clamped(to: -1...1))
    }

    @inlinable
    public func clamped(maxLength: Float) -> SIMD3<Float> {
        let sq = magnitudeSquared
        guard sq > maxLength * maxLength else { return self }
        return self * (maxLength / sqrt(sq))
    }

    /// Projects this vector onto `v`.
    @inlinable
    public func projected(onto v: SIMD3<Float>) -> SIMD3<Float> {
        v * (dot(v) / v.dot(v))
    }

    /// Projects this vector onto the plane defined by `normal`.
    @inlinable
    public func projectedOnPlane(normal n: SIMD3<Float>) -> SIMD3<Float> {
        self - projected(onto: n)
    }

    /// Reflects this vector off a surface with the given `normal`.
    @inlinable
    public func reflected(normal: SIMD3<Float>) -> SIMD3<Float> {
        self - 2 * dot(normal) * normal
    }

    @inlinable
    public func approxEqual(_ other: SIMD3<Float>, epsilon: Float = mc_epsilon) -> Bool {
        abs(x - other.x) <= epsilon &&
        abs(y - other.y) <= epsilon &&
        abs(z - other.z) <= epsilon
    }

    /// Extends to SIMD4 with the given w component.
    @inlinable
    public func toSIMD4(w: Float = 0) -> SIMD4<Float> {
        SIMD4<Float>(x, y, z, w)
    }

    /// Swizzle: xy components as SIMD2.
    @inlinable public var xy: SIMD2<Float> { SIMD2<Float>(x, y) }
    /// Swizzle: xz components as SIMD2.
    @inlinable public var xz: SIMD2<Float> { SIMD2<Float>(x, z) }
}

// MARK: - SIMD4<Float>

extension SIMD4 where Scalar == Float {

    public static let one = SIMD4<Float>(1, 1, 1, 1)

    @inlinable public var magnitude: Float { simd_length(self) }
    @inlinable public var magnitudeSquared: Float { simd_length_squared(self) }
    @inlinable public var normalized: SIMD4<Float> { simd_normalize(self) }

    @inlinable
    public func dot(_ other: SIMD4<Float>) -> Float {
        simd_dot(self, other)
    }

    @inlinable
    public func approxEqual(_ other: SIMD4<Float>, epsilon: Float = mc_epsilon) -> Bool {
        abs(x - other.x) <= epsilon &&
        abs(y - other.y) <= epsilon &&
        abs(z - other.z) <= epsilon &&
        abs(w - other.w) <= epsilon
    }

    /// Extracts the xyz components.
    @inlinable
    public var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }

    /// Extracts the xy components.
    @inlinable
    public var xy: SIMD2<Float> {
        SIMD2<Float>(x, y)
    }
}
