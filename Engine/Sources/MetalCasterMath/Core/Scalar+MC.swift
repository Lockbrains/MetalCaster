import Foundation

// MARK: - Float Extensions

extension Float {

    /// Degrees-to-radians conversion factor.
    public static let deg2Rad: Float = .pi / 180.0
    /// Radians-to-degrees conversion factor.
    public static let rad2Deg: Float = 180.0 / .pi

    /// Clamps this value to the given closed range.
    @inlinable
    public func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    /// Remaps this value from one range to another.
    @inlinable
    public func remapped(from source: ClosedRange<Float>, to dest: ClosedRange<Float>) -> Float {
        let t = (self - source.lowerBound) / (source.upperBound - source.lowerBound)
        return dest.lowerBound + t * (dest.upperBound - dest.lowerBound)
    }

    /// Returns true if this value is approximately equal to `other`.
    @inlinable
    public func approxEqual(_ other: Float, epsilon: Float = mc_epsilon) -> Bool {
        abs(self - other) <= epsilon
    }

    /// Returns true if this value is approximately zero.
    @inlinable
    public func approxZero(epsilon: Float = mc_epsilon) -> Bool {
        abs(self) <= epsilon
    }

    /// Returns -1, 0, or 1 based on the sign of this value.
    @inlinable
    public var signValue: Float {
        if self > 0 { return 1 }
        if self < 0 { return -1 }
        return 0
    }

    /// Returns the fractional part of this value.
    @inlinable
    public var fract: Float {
        self - floor(self)
    }

    /// Converts degrees to radians.
    @inlinable
    public var toRadians: Float {
        self * .deg2Rad
    }

    /// Converts radians to degrees.
    @inlinable
    public var toDegrees: Float {
        self * .rad2Deg
    }

    /// Wraps the angle in radians to the range [-pi, pi).
    @inlinable
    public var wrappedAngle: Float {
        var a = self.truncatingRemainder(dividingBy: mc_twoPi)
        if a > .pi { a -= mc_twoPi }
        if a < -.pi { a += mc_twoPi }
        return a
    }

    /// Snaps this value to the nearest multiple of `grid`.
    @inlinable
    public func snapped(to grid: Float) -> Float {
        guard grid > 0 else { return self }
        return (self / grid).rounded() * grid
    }

    /// Moves this value towards `target` by at most `maxDelta`.
    @inlinable
    public func moved(towards target: Float, maxDelta: Float) -> Float {
        let delta = target - self
        if abs(delta) <= maxDelta { return target }
        return self + maxDelta * delta.signValue
    }
}

// MARK: - Double Extensions

extension Double {

    public static let deg2Rad: Double = .pi / 180.0
    public static let rad2Deg: Double = 180.0 / .pi

    @inlinable
    public func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    @inlinable
    public func remapped(from source: ClosedRange<Double>, to dest: ClosedRange<Double>) -> Double {
        let t = (self - source.lowerBound) / (source.upperBound - source.lowerBound)
        return dest.lowerBound + t * (dest.upperBound - dest.lowerBound)
    }

    @inlinable
    public func approxEqual(_ other: Double, epsilon: Double = mc_epsilonD) -> Bool {
        abs(self - other) <= epsilon
    }

    @inlinable
    public func approxZero(epsilon: Double = mc_epsilonD) -> Bool {
        abs(self) <= epsilon
    }

    @inlinable
    public var signValue: Double {
        if self > 0 { return 1 }
        if self < 0 { return -1 }
        return 0
    }

    @inlinable
    public var fract: Double {
        self - floor(self)
    }

    @inlinable
    public var toRadians: Double {
        self * .deg2Rad
    }

    @inlinable
    public var toDegrees: Double {
        self * .rad2Deg
    }
}
