import Foundation

/// Standard easing functions. All take `t` in [0, 1] and return a value in [0, 1]
/// (some overshoot slightly, e.g. elastic/back).
///
/// Reference: https://easings.net
public enum MCEasing {

    // MARK: - Linear

    @inlinable public static func linear(_ t: Float) -> Float { t }

    // MARK: - Quadratic

    @inlinable public static func easeInQuad(_ t: Float) -> Float { t * t }
    @inlinable public static func easeOutQuad(_ t: Float) -> Float { t * (2 - t) }
    @inlinable public static func easeInOutQuad(_ t: Float) -> Float {
        t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    // MARK: - Cubic

    @inlinable public static func easeInCubic(_ t: Float) -> Float { t * t * t }
    @inlinable public static func easeOutCubic(_ t: Float) -> Float {
        let p = t - 1; return p * p * p + 1
    }
    @inlinable public static func easeInOutCubic(_ t: Float) -> Float {
        t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
    }

    // MARK: - Quartic

    @inlinable public static func easeInQuart(_ t: Float) -> Float { t * t * t * t }
    @inlinable public static func easeOutQuart(_ t: Float) -> Float {
        let p = t - 1; return 1 - p * p * p * p
    }
    @inlinable public static func easeInOutQuart(_ t: Float) -> Float {
        if t < 0.5 { return 8 * t * t * t * t }
        let p = t - 1; return 1 - 8 * p * p * p * p
    }

    // MARK: - Quintic

    @inlinable public static func easeInQuint(_ t: Float) -> Float { t * t * t * t * t }
    @inlinable public static func easeOutQuint(_ t: Float) -> Float {
        let p = t - 1; return 1 + p * p * p * p * p
    }
    @inlinable public static func easeInOutQuint(_ t: Float) -> Float {
        if t < 0.5 { return 16 * t * t * t * t * t }
        let p = t - 1; return 1 + 16 * p * p * p * p * p
    }

    // MARK: - Sine

    @inlinable public static func easeInSine(_ t: Float) -> Float {
        1 - cos(t * .pi / 2)
    }
    @inlinable public static func easeOutSine(_ t: Float) -> Float {
        sin(t * .pi / 2)
    }
    @inlinable public static func easeInOutSine(_ t: Float) -> Float {
        0.5 * (1 - cos(.pi * t))
    }

    // MARK: - Exponential

    @inlinable public static func easeInExpo(_ t: Float) -> Float {
        t == 0 ? 0 : pow(2, 10 * (t - 1))
    }
    @inlinable public static func easeOutExpo(_ t: Float) -> Float {
        t == 1 ? 1 : 1 - pow(2, -10 * t)
    }
    @inlinable public static func easeInOutExpo(_ t: Float) -> Float {
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        if t < 0.5 { return 0.5 * pow(2, 20 * t - 10) }
        return 1 - 0.5 * pow(2, -20 * t + 10)
    }

    // MARK: - Circular

    @inlinable public static func easeInCirc(_ t: Float) -> Float {
        1 - sqrt(1 - t * t)
    }
    @inlinable public static func easeOutCirc(_ t: Float) -> Float {
        let p = t - 1; return sqrt(1 - p * p)
    }
    @inlinable public static func easeInOutCirc(_ t: Float) -> Float {
        if t < 0.5 { return 0.5 * (1 - sqrt(1 - 4 * t * t)) }
        let p = 2 * t - 2; return 0.5 * (sqrt(1 - p * p) + 1)
    }

    // MARK: - Back

    @inlinable public static func easeInBack(_ t: Float) -> Float {
        let s: Float = 1.70158
        return t * t * ((s + 1) * t - s)
    }
    @inlinable public static func easeOutBack(_ t: Float) -> Float {
        let s: Float = 1.70158
        let p = t - 1
        return p * p * ((s + 1) * p + s) + 1
    }
    @inlinable public static func easeInOutBack(_ t: Float) -> Float {
        let s: Float = 1.70158 * 1.525
        if t < 0.5 {
            return 0.5 * (4 * t * t * ((s + 1) * 2 * t - s))
        }
        let p = 2 * t - 2
        return 0.5 * (p * p * ((s + 1) * p + s) + 2)
    }

    // MARK: - Elastic

    @inlinable public static func easeInElastic(_ t: Float) -> Float {
        if t == 0 || t == 1 { return t }
        return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * mc_twoPi / 3)
    }
    @inlinable public static func easeOutElastic(_ t: Float) -> Float {
        if t == 0 || t == 1 { return t }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * mc_twoPi / 3) + 1
    }
    @inlinable public static func easeInOutElastic(_ t: Float) -> Float {
        if t == 0 || t == 1 { return t }
        if t < 0.5 {
            return -0.5 * pow(2, 20 * t - 10) * sin((20 * t - 11.125) * mc_twoPi / 4.5)
        }
        return pow(2, -20 * t + 10) * sin((20 * t - 11.125) * mc_twoPi / 4.5) * 0.5 + 1
    }

    // MARK: - Bounce

    public static func easeOutBounce(_ t: Float) -> Float {
        if t < 1.0 / 2.75 {
            return 7.5625 * t * t
        } else if t < 2.0 / 2.75 {
            let p = t - 1.5 / 2.75
            return 7.5625 * p * p + 0.75
        } else if t < 2.5 / 2.75 {
            let p = t - 2.25 / 2.75
            return 7.5625 * p * p + 0.9375
        } else {
            let p = t - 2.625 / 2.75
            return 7.5625 * p * p + 0.984375
        }
    }

    public static func easeInBounce(_ t: Float) -> Float {
        1 - easeOutBounce(1 - t)
    }

    public static func easeInOutBounce(_ t: Float) -> Float {
        if t < 0.5 {
            return easeInBounce(t * 2) * 0.5
        }
        return easeOutBounce(t * 2 - 1) * 0.5 + 0.5
    }

    // MARK: - Spring (physically based)

    /// Single-iteration spring ease. `damping` in [0,1]: 0 = no damping, 1 = critically damped.
    public static func spring(_ t: Float, damping: Float = 0.5) -> Float {
        let freq: Float = 4.71238898 // 3π/2
        let decay = max(mc_epsilon, damping)
        return 1 - exp(-decay * 10 * t) * cos(freq * (1 - decay) * 10 * t)
    }
}
