import simd

/// Spline and curve evaluation utilities.
public enum MCSpline {

    // MARK: - Bezier Curves

    /// Evaluates a quadratic Bezier curve at parameter `t`.
    @inlinable
    public static func quadraticBezier(
        _ p0: SIMD3<Float>,
        _ p1: SIMD3<Float>,
        _ p2: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let u = 1 - t
        return u * u * p0 + 2 * u * t * p1 + t * t * p2
    }

    /// Evaluates a cubic Bezier curve at parameter `t`.
    @inlinable
    public static func cubicBezier(
        _ p0: SIMD3<Float>,
        _ p1: SIMD3<Float>,
        _ p2: SIMD3<Float>,
        _ p3: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return uu * u * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + tt * t * p3
    }

    /// Tangent of a cubic Bezier at parameter `t` (first derivative).
    @inlinable
    public static func cubicBezierTangent(
        _ p0: SIMD3<Float>,
        _ p1: SIMD3<Float>,
        _ p2: SIMD3<Float>,
        _ p3: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let u = 1 - t
        return 3 * u * u * (p1 - p0) + 6 * u * t * (p2 - p1) + 3 * t * t * (p3 - p2)
    }

    /// Scalar cubic Bezier for easing curves.
    @inlinable
    public static func cubicBezier1D(
        _ p0: Float,
        _ p1: Float,
        _ p2: Float,
        _ p3: Float,
        t: Float
    ) -> Float {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return uu * u * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + tt * t * p3
    }

    // MARK: - Catmull-Rom Spline

    /// Evaluates a Catmull-Rom spline segment at parameter `t`.
    /// `p0` and `p3` are the neighboring control points used for tangent computation.
    @inlinable
    public static func catmullRom(
        _ p0: SIMD3<Float>,
        _ p1: SIMD3<Float>,
        _ p2: SIMD3<Float>,
        _ p3: SIMD3<Float>,
        t: Float,
        alpha: Float = 0.5
    ) -> SIMD3<Float> {
        let tt = t * t
        let ttt = tt * t

        let q0 = -alpha * p0 + (2 - alpha) * p1 + (alpha - 2) * p2 + alpha * p3
        let q1 = 2 * alpha * p0 + (alpha - 3) * p1 + (3 - 2 * alpha) * p2 - alpha * p3
        let q2 = -alpha * p0 + alpha * p2
        let q3 = p1

        return q0 * ttt + q1 * tt + q2 * t + q3
    }

    /// Evaluates a Catmull-Rom spline along a path of points at a global parameter `t` in [0, 1].
    public static func catmullRomPath(
        _ points: [SIMD3<Float>],
        t: Float,
        alpha: Float = 0.5,
        closed: Bool = false
    ) -> SIMD3<Float> {
        guard points.count >= 2 else {
            return points.first ?? .zero
        }

        let segmentCount = closed ? points.count : points.count - 1
        let scaled = t.clamped(to: 0...1) * Float(segmentCount)
        let segment = min(Int(scaled), segmentCount - 1)
        let localT = scaled - Float(segment)

        func point(_ index: Int) -> SIMD3<Float> {
            if closed {
                return points[((index % points.count) + points.count) % points.count]
            }
            return points[min(max(index, 0), points.count - 1)]
        }

        return catmullRom(
            point(segment - 1),
            point(segment),
            point(segment + 1),
            point(segment + 2),
            t: localT,
            alpha: alpha
        )
    }

    // MARK: - Hermite Spline

    /// Evaluates a cubic Hermite spline segment.
    /// `m0` and `m1` are the tangent vectors at `p0` and `p1`.
    @inlinable
    public static func hermite(
        _ p0: SIMD3<Float>,
        _ m0: SIMD3<Float>,
        _ p1: SIMD3<Float>,
        _ m1: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let tt = t * t
        let ttt = tt * t

        let h00 = 2 * ttt - 3 * tt + 1
        let h10 = ttt - 2 * tt + t
        let h01 = -2 * ttt + 3 * tt
        let h11 = ttt - tt

        return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1
    }

    /// Tangent of a Hermite spline at parameter `t`.
    @inlinable
    public static func hermiteTangent(
        _ p0: SIMD3<Float>,
        _ m0: SIMD3<Float>,
        _ p1: SIMD3<Float>,
        _ m1: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let tt = t * t
        let dh00 = 6 * tt - 6 * t
        let dh10 = 3 * tt - 4 * t + 1
        let dh01 = -6 * tt + 6 * t
        let dh11 = 3 * tt - 2 * t

        return dh00 * p0 + dh10 * m0 + dh01 * p1 + dh11 * m1
    }

    // MARK: - 2D Bezier (for UI curves)

    @inlinable
    public static func quadraticBezier2D(
        _ p0: SIMD2<Float>,
        _ p1: SIMD2<Float>,
        _ p2: SIMD2<Float>,
        t: Float
    ) -> SIMD2<Float> {
        let u = 1 - t
        return u * u * p0 + 2 * u * t * p1 + t * t * p2
    }

    @inlinable
    public static func cubicBezier2D(
        _ p0: SIMD2<Float>,
        _ p1: SIMD2<Float>,
        _ p2: SIMD2<Float>,
        _ p3: SIMD2<Float>,
        t: Float
    ) -> SIMD2<Float> {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return uu * u * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + tt * t * p3
    }
}
