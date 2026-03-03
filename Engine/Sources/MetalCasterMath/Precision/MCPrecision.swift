import Foundation
import simd

/// Precision and safety utilities for floating-point operations.
public enum MCPrecision {

    // MARK: - Approximate Equality

    /// Returns true if two floats are approximately equal within `epsilon`.
    @inlinable
    public static func approxEqual(_ a: Float, _ b: Float, epsilon: Float = mc_epsilon) -> Bool {
        abs(a - b) <= epsilon
    }

    /// Returns true if the value is approximately zero.
    @inlinable
    public static func approxZero(_ value: Float, epsilon: Float = mc_epsilon) -> Bool {
        abs(value) <= epsilon
    }

    /// Returns true if two vectors are approximately equal.
    @inlinable
    public static func approxEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, epsilon: Float = mc_epsilon) -> Bool {
        abs(a.x - b.x) <= epsilon &&
        abs(a.y - b.y) <= epsilon &&
        abs(a.z - b.z) <= epsilon
    }

    /// Returns true if two vectors are approximately equal.
    @inlinable
    public static func approxEqual(_ a: SIMD4<Float>, _ b: SIMD4<Float>, epsilon: Float = mc_epsilon) -> Bool {
        abs(a.x - b.x) <= epsilon &&
        abs(a.y - b.y) <= epsilon &&
        abs(a.z - b.z) <= epsilon &&
        abs(a.w - b.w) <= epsilon
    }

    /// Relative epsilon comparison for values of differing magnitudes.
    @inlinable
    public static func relativeEqual(_ a: Float, _ b: Float, relEpsilon: Float = mc_epsilon, absEpsilon: Float = mc_epsilon) -> Bool {
        let diff = abs(a - b)
        if diff <= absEpsilon { return true }
        let largest = max(abs(a), abs(b))
        return diff <= largest * relEpsilon
    }

    // MARK: - Safe Arithmetic

    /// Safe division: returns `fallback` if divisor is near zero.
    @inlinable
    public static func safeDiv(_ a: Float, _ b: Float, fallback: Float = 0) -> Float {
        abs(b) > mc_epsilon ? a / b : fallback
    }

    /// Safe normalization: returns zero vector if input is too small to normalize.
    @inlinable
    public static func safeNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let lenSq = simd_length_squared(v)
        guard lenSq > mc_epsilonSq else { return .zero }
        return v * (1.0 / sqrt(lenSq))
    }

    /// Safe normalization for SIMD2.
    @inlinable
    public static func safeNormalize(_ v: SIMD2<Float>) -> SIMD2<Float> {
        let lenSq = simd_length_squared(v)
        guard lenSq > mc_epsilonSq else { return .zero }
        return v * (1.0 / sqrt(lenSq))
    }

    /// Safe acos: clamps input to [-1, 1] to avoid NaN.
    @inlinable
    public static func safeAcos(_ x: Float) -> Float {
        acos(x.clamped(to: -1...1))
    }

    /// Safe asin: clamps input to [-1, 1] to avoid NaN.
    @inlinable
    public static func safeAsin(_ x: Float) -> Float {
        asin(x.clamped(to: -1...1))
    }

    /// Safe sqrt: returns 0 for negative inputs instead of NaN.
    @inlinable
    public static func safeSqrt(_ x: Float) -> Float {
        sqrt(max(0, x))
    }

    // MARK: - Large / Small Number Handling

    /// Safe log10: handles zero and negative values gracefully.
    @inlinable
    public static func log10Safe(_ x: Float) -> Float {
        guard x > 0 else { return -Float.greatestFiniteMagnitude }
        return log10(x)
    }

    /// Safe natural log: handles zero and negative values.
    @inlinable
    public static func logSafe(_ x: Float) -> Float {
        guard x > 0 else { return -Float.greatestFiniteMagnitude }
        return log(x)
    }

    /// Safe power function that avoids overflow/underflow edge cases.
    @inlinable
    public static func safePow(_ base: Float, _ exponent: Float) -> Float {
        guard base > 0 else {
            if base == 0 { return exponent > 0 ? 0 : Float.greatestFiniteMagnitude }
            return 0
        }
        let result = pow(base, exponent)
        if result.isNaN || result.isInfinite { return Float.greatestFiniteMagnitude }
        return result
    }

    /// Clamps value to the finite float range, replacing infinity/NaN.
    @inlinable
    public static func clampFinite(_ value: Float, fallback: Float = 0) -> Float {
        if value.isNaN { return fallback }
        if value.isInfinite { return value > 0 ? Float.greatestFiniteMagnitude : -Float.greatestFiniteMagnitude }
        return value
    }

    /// Returns true if a float is finite and not NaN.
    @inlinable
    public static func isFinite(_ value: Float) -> Bool {
        !value.isNaN && !value.isInfinite
    }

    /// Clamps the magnitude of a value.
    @inlinable
    public static func clampMagnitude(_ value: Float, min minVal: Float, max maxVal: Float) -> Float {
        let mag = abs(value)
        if mag < minVal { return value >= 0 ? minVal : -minVal }
        if mag > maxVal { return value >= 0 ? maxVal : -maxVal }
        return value
    }

    // MARK: - Double Precision

    @inlinable
    public static func approxEqual(_ a: Double, _ b: Double, epsilon: Double = mc_epsilonD) -> Bool {
        abs(a - b) <= epsilon
    }

    @inlinable
    public static func approxZero(_ value: Double, epsilon: Double = mc_epsilonD) -> Bool {
        abs(value) <= epsilon
    }

    @inlinable
    public static func safeDiv(_ a: Double, _ b: Double, fallback: Double = 0) -> Double {
        abs(b) > mc_epsilonD ? a / b : fallback
    }

    @inlinable
    public static func clampFinite(_ value: Double, fallback: Double = 0) -> Double {
        if value.isNaN { return fallback }
        if value.isInfinite { return value > 0 ? Double.greatestFiniteMagnitude : -Double.greatestFiniteMagnitude }
        return value
    }

    // MARK: - Kahan Summation (for stable accumulation of many small values)

    /// Performs Kahan compensated summation to reduce floating-point error
    /// when summing many values.
    public static func kahanSum(_ values: [Float]) -> Float {
        var sum: Float = 0
        var compensation: Float = 0
        for value in values {
            let y = value - compensation
            let t = sum + y
            compensation = (t - sum) - y
            sum = t
        }
        return sum
    }

    /// Kahan summation for Double.
    public static func kahanSum(_ values: [Double]) -> Double {
        var sum: Double = 0
        var compensation: Double = 0
        for value in values {
            let y = value - compensation
            let t = sum + y
            compensation = (t - sum) - y
            sum = t
        }
        return sum
    }
}
