import Foundation
import simd

// MARK: - Euler ↔ Quaternion (free functions, migrated from MCMath.swift)

/// Creates a quaternion from Euler angles (in radians), applied in YXZ order.
public func quaternionFromEuler(_ euler: SIMD3<Float>) -> simd_quatf {
    let qx = simd_quatf(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
    let qy = simd_quatf(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
    let qz = simd_quatf(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
    return qy * qx * qz
}

/// Extracts Euler angles (in radians) from a quaternion, using YXZ decomposition.
/// Returns (pitch, yaw, roll) as SIMD3<Float>.
public func eulerFromQuaternion(_ q: simd_quatf) -> SIMD3<Float> {
    let m = simd_float3x3(q)
    let sinP = -m[1][2]
    let pitch: Float
    let yaw: Float
    let roll: Float

    if abs(sinP) >= 0.9999 {
        pitch = copysign(Float.pi / 2, sinP)
        yaw = atan2(-m[2][0], m[0][0])
        roll = 0
    } else {
        pitch = asin(sinP)
        yaw = atan2(m[0][2], m[2][2])
        roll = atan2(m[1][0], m[1][1])
    }
    return SIMD3<Float>(pitch, yaw, roll)
}

// MARK: - simd_quatf Extensions

extension simd_quatf {

    /// Creates a quaternion that rotates from the identity forward (-Z) to `forward`, with the given `up` hint.
    @inlinable
    public static func lookRotation(forward: SIMD3<Float>, up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) -> simd_quatf {
        let f = simd_normalize(forward)
        let r = simd_normalize(simd_cross(up, f))
        let u = simd_cross(f, r)

        let m = simd_float3x3(r, u, f)
        return simd_quatf(m)
    }

    /// The rotation angle in radians.
    @inlinable
    public var angle: Float {
        2 * acos(abs(real).clamped(to: 0...1))
    }

    /// The rotation axis (unit vector). Returns (0,1,0) for identity rotations.
    @inlinable
    public var axis: SIMD3<Float> {
        let sinHalf = simd_length(imag)
        guard sinHalf > mc_epsilon else {
            return SIMD3<Float>(0, 1, 0)
        }
        return imag / sinHalf
    }

    /// Euler angles in radians (pitch, yaw, roll) using YXZ decomposition.
    @inlinable
    public var eulerAngles: SIMD3<Float> {
        eulerFromQuaternion(self)
    }

    /// Spherical linear interpolation towards `target`.
    @inlinable
    public func slerp(to target: simd_quatf, t: Float) -> simd_quatf {
        simd_slerp(self, target, t)
    }

    /// Spherical linear interpolation with the shortest path.
    @inlinable
    public func slerpShortest(to target: simd_quatf, t: Float) -> simd_quatf {
        simd_slerp_longest(self, target, t)
    }

    /// Rotates towards `target` by at most `maxRadiansDelta`.
    @inlinable
    public func rotatedTowards(_ target: simd_quatf, maxRadiansDelta: Float) -> simd_quatf {
        let angleBetween = acos((2 * pow(simd_dot(self, target), 2) - 1).clamped(to: -1...1))
        guard angleBetween > mc_epsilon else { return target }
        let t = min(1, maxRadiansDelta / angleBetween)
        return simd_slerp(self, target, t)
    }

    /// The forward direction (-Z) rotated by this quaternion.
    @inlinable
    public var forward: SIMD3<Float> {
        act(SIMD3<Float>(0, 0, -1))
    }

    /// The right direction (+X) rotated by this quaternion.
    @inlinable
    public var right: SIMD3<Float> {
        act(SIMD3<Float>(1, 0, 0))
    }

    /// The up direction (+Y) rotated by this quaternion.
    @inlinable
    public var up: SIMD3<Float> {
        act(SIMD3<Float>(0, 1, 0))
    }

    /// The angle in radians between this quaternion and `other`.
    @inlinable
    public func angle(to other: simd_quatf) -> Float {
        let d = abs(simd_dot(self, other)).clamped(to: 0...1)
        return 2 * acos(d)
    }

    /// Returns the conjugate (inverse rotation for unit quaternions).
    @inlinable
    public var conjugated: simd_quatf {
        simd_quatf(ix: -imag.x, iy: -imag.y, iz: -imag.z, r: real)
    }
}
