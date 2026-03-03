import simd

/// Core interpolation functions.
public enum MCInterp {

    // MARK: - Scalar Interpolation

    /// Linear interpolation between `a` and `b`. Unclamped (t outside [0,1] extrapolates).
    @inlinable
    public static func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    /// Linear interpolation, clamped so t is in [0,1].
    @inlinable
    public static func lerpClamped(_ a: Float, _ b: Float, t: Float) -> Float {
        lerp(a, b, t: t.clamped(to: 0...1))
    }

    /// Inverse lerp: returns the `t` value such that lerp(a, b, t) == value.
    @inlinable
    public static func inverseLerp(_ a: Float, _ b: Float, value: Float) -> Float {
        let d = b - a
        guard abs(d) > mc_epsilon else { return 0 }
        return (value - a) / d
    }

    /// Remaps `value` from one range to another.
    @inlinable
    public static func remap(
        _ value: Float,
        from inRange: ClosedRange<Float>,
        to outRange: ClosedRange<Float>
    ) -> Float {
        let t = inverseLerp(inRange.lowerBound, inRange.upperBound, value: value)
        return lerp(outRange.lowerBound, outRange.upperBound, t: t)
    }

    /// Hermite smoothstep: smooth transition from 0 to 1 when x is between edge0 and edge1.
    @inlinable
    public static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * (3 - 2 * t)
    }

    /// Ken Perlin's smootherstep (C2 continuous).
    @inlinable
    public static func smootherstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = ((x - edge0) / (edge1 - edge0)).clamped(to: 0...1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Step function: returns 0 if x < edge, else 1.
    @inlinable
    public static func step(_ edge: Float, _ x: Float) -> Float {
        x < edge ? 0 : 1
    }

    /// Moves `current` towards `target` by at most `maxDelta`.
    @inlinable
    public static func moveTowards(_ current: Float, _ target: Float, maxDelta: Float) -> Float {
        current.moved(towards: target, maxDelta: maxDelta)
    }

    /// Framerate-independent exponential decay (useful for smooth camera follow, etc.).
    /// `lambda` controls the speed (higher = faster), `dt` is the delta time.
    @inlinable
    public static func damp(_ a: Float, _ b: Float, lambda: Float, dt: Float) -> Float {
        lerp(a, b, t: 1 - exp(-lambda * dt))
    }

    /// Critically damped spring. Returns the new (value, velocity) pair.
    public static func dampedSpring(
        current: Float,
        target: Float,
        velocity: inout Float,
        smoothTime: Float,
        deltaTime: Float,
        maxSpeed: Float = .greatestFiniteMagnitude
    ) -> Float {
        let omega = 2.0 / max(smoothTime, mc_epsilon)
        let x = omega * deltaTime
        let exp_factor = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
        var change = current - target
        let maxChange = maxSpeed * smoothTime
        change = change.clamped(to: -maxChange...maxChange)
        let adjustedTarget = current - change
        let temp = (velocity + omega * change) * deltaTime
        velocity = (velocity - omega * temp) * exp_factor
        var result = adjustedTarget + (change + temp) * exp_factor
        if (adjustedTarget - current > 0) == (result > adjustedTarget) {
            result = adjustedTarget
            velocity = (result - adjustedTarget) / max(deltaTime, mc_epsilon)
        }
        return result
    }

    // MARK: - Vector Interpolation

    @inlinable
    public static func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, t: Float) -> SIMD2<Float> {
        a + (b - a) * t
    }

    @inlinable
    public static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    @inlinable
    public static func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        a + (b - a) * t
    }

    @inlinable
    public static func damp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, lambda: Float, dt: Float) -> SIMD3<Float> {
        lerp(a, b, t: 1 - exp(-lambda * dt))
    }

    /// Moves a point towards a target, clamped by maxDistanceDelta.
    @inlinable
    public static func moveTowards(
        _ current: SIMD3<Float>,
        _ target: SIMD3<Float>,
        maxDistanceDelta: Float
    ) -> SIMD3<Float> {
        let diff = target - current
        let dist = simd_length(diff)
        guard dist > mc_epsilon && dist > maxDistanceDelta else { return target }
        return current + diff / dist * maxDistanceDelta
    }

    // MARK: - Angle Interpolation

    /// Lerps between two angles in radians, taking the shortest path.
    @inlinable
    public static func lerpAngle(_ a: Float, _ b: Float, t: Float) -> Float {
        var delta = (b - a).truncatingRemainder(dividingBy: mc_twoPi)
        if delta > .pi { delta -= mc_twoPi }
        if delta < -.pi { delta += mc_twoPi }
        return a + delta * t
    }

    // MARK: - Bilinear Interpolation

    /// Bilinear interpolation between four corner values.
    @inlinable
    public static func biLerp(
        _ a00: Float, _ a10: Float, _ a01: Float, _ a11: Float,
        tx: Float, ty: Float
    ) -> Float {
        let top = lerp(a00, a10, t: tx)
        let bot = lerp(a01, a11, t: tx)
        return lerp(top, bot, t: ty)
    }
}
