import Foundation
import simd

// MARK: - Matrix Construction (free functions, migrated from MCMath.swift)

/// Creates a 4x4 translation matrix.
public func matrix4x4Translation(_ t: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(t.x, t.y, t.z, 1)
    ))
}

/// Creates a 4x4 scale matrix.
public func matrix4x4Scale(_ s: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(s.x, 0, 0, 0),
        SIMD4<Float>(0, s.y, 0, 0),
        SIMD4<Float>(0, 0, s.z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

/// Creates a rotation matrix around an arbitrary axis using Rodrigues' formula.
public func matrix4x4Rotation(_ radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let a = simd_normalize(axis)
    let c = cos(radians)
    let s = sin(radians)
    let mc = 1 - c
    let x = a.x, y = a.y, z = a.z
    return simd_float4x4(columns: (
        SIMD4<Float>(c + x*x*mc,     x*y*mc + z*s,   x*z*mc - y*s, 0),
        SIMD4<Float>(x*y*mc - z*s,   c + y*y*mc,     y*z*mc + x*s, 0),
        SIMD4<Float>(x*z*mc + y*s,   y*z*mc - x*s,   c + z*z*mc,   0),
        SIMD4<Float>(0,              0,              0,             1)
    ))
}

/// Creates a right-handed perspective projection matrix (Metal clip Z [0, 1]).
public func matrix4x4PerspectiveRightHand(
    fovyRadians fovy: Float,
    aspectRatio: Float,
    nearZ: Float,
    farZ: Float
) -> simd_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return simd_float4x4(columns: (
        SIMD4<Float>(xs, 0,  0,          0),
        SIMD4<Float>(0,  ys, 0,          0),
        SIMD4<Float>(0,  0,  zs,        -1),
        SIMD4<Float>(0,  0,  nearZ * zs, 0)
    ))
}

/// Creates a right-handed look-at view matrix.
public func matrix4x4LookAt(
    eye: SIMD3<Float>,
    target: SIMD3<Float>,
    up: SIMD3<Float>
) -> simd_float4x4 {
    let f = simd_normalize(target - eye)
    let s = simd_normalize(simd_cross(f, up))
    let u = simd_cross(s, f)
    return simd_float4x4(columns: (
        SIMD4<Float>(s.x, u.x, -f.x, 0),
        SIMD4<Float>(s.y, u.y, -f.y, 0),
        SIMD4<Float>(s.z, u.z, -f.z, 0),
        SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
    ))
}

/// Creates an orthographic projection matrix.
public func matrix4x4Orthographic(
    left: Float, right: Float,
    bottom: Float, top: Float,
    nearZ: Float, farZ: Float
) -> simd_float4x4 {
    let sx = 2.0 / (right - left)
    let sy = 2.0 / (top - bottom)
    let sz = 1.0 / (nearZ - farZ)
    let tx = -(right + left) / (right - left)
    let ty = -(top + bottom) / (top - bottom)
    let tz = nearZ / (nearZ - farZ)
    return simd_float4x4(columns: (
        SIMD4<Float>(sx, 0,  0,  0),
        SIMD4<Float>(0,  sy, 0,  0),
        SIMD4<Float>(0,  0,  sz, 0),
        SIMD4<Float>(tx, ty, tz, 1)
    ))
}

/// Creates a 4x4 TRS (Translation * Rotation * Scale) matrix.
public func matrix4x4TRS(
    translation t: SIMD3<Float>,
    rotation q: simd_quatf,
    scale s: SIMD3<Float>
) -> simd_float4x4 {
    matrix4x4Translation(t) * simd_float4x4(q) * matrix4x4Scale(s)
}

// MARK: - simd_float4x4 Extensions

extension simd_float4x4 {

    /// The translation component (column 3, xyz).
    @inlinable
    public var translation: SIMD3<Float> {
        get { SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z) }
        set {
            columns.3.x = newValue.x
            columns.3.y = newValue.y
            columns.3.z = newValue.z
        }
    }

    /// Extracts the upper-left 3x3 sub-matrix.
    @inlinable
    public var upperLeft3x3: simd_float3x3 {
        simd_float3x3(
            SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z),
            SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z),
            SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
        )
    }

    /// Computes the normal matrix (transpose of inverse of upper-left 3x3).
    @inlinable
    public var normalMatrix: simd_float3x3 {
        simd_transpose(upperLeft3x3.inverse)
    }

    /// Extracts the scale factor from each column.
    @inlinable
    public var extractedScale: SIMD3<Float> {
        SIMD3<Float>(
            simd_length(SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z)),
            simd_length(SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z)),
            simd_length(SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z))
        )
    }

    /// Extracts rotation as a quaternion (assumes uniform or near-uniform scale).
    @inlinable
    public var extractedRotation: simd_quatf {
        let s = extractedScale
        let rotMat = simd_float3x3(
            SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z) / s.x,
            SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z) / s.y,
            SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z) / s.z
        )
        return simd_quatf(rotMat)
    }

    /// Decomposes this matrix into translation, rotation, and scale.
    @inlinable
    public func decompose() -> (translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        (translation, extractedRotation, extractedScale)
    }

    /// The forward direction (-Z axis of this matrix's rotation).
    @inlinable
    public var forwardDirection: SIMD3<Float> {
        -simd_normalize(SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z))
    }

    /// The right direction (+X axis of this matrix's rotation).
    @inlinable
    public var rightDirection: SIMD3<Float> {
        simd_normalize(SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z))
    }

    /// The up direction (+Y axis of this matrix's rotation).
    @inlinable
    public var upDirection: SIMD3<Float> {
        simd_normalize(SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z))
    }

    /// Transforms a point (w=1).
    @inlinable
    public func transformPoint(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = self * SIMD4<Float>(p.x, p.y, p.z, 1)
        return SIMD3<Float>(v.x, v.y, v.z)
    }

    /// Transforms a direction (w=0), ignoring translation.
    @inlinable
    public func transformDirection(_ d: SIMD3<Float>) -> SIMD3<Float> {
        let v = self * SIMD4<Float>(d.x, d.y, d.z, 0)
        return SIMD3<Float>(v.x, v.y, v.z)
    }
}

// MARK: - simd_float4x3 Extensions

extension simd_float4x3 {

    /// Constructs a 4x3 matrix from a 4x4 matrix by dropping the last row.
    @inlinable
    public init(_ m: simd_float4x4) {
        self.init(
            SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z),
            SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        )
    }

    /// Expands to a 4x4 matrix with the last row set to [0, 0, 0, 1].
    @inlinable
    public var to4x4: simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(columns.0, 0),
            SIMD4<Float>(columns.1, 0),
            SIMD4<Float>(columns.2, 0),
            SIMD4<Float>(columns.3, 1)
        )
    }
}

// MARK: - simd_float3x3 Extensions

extension simd_float3x3 {

    /// Constructs a 3x3 matrix from the upper-left of a 4x4 matrix.
    @inlinable
    public init(upperLeftOf m: simd_float4x4) {
        self.init(
            SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        )
    }

    /// Creates a 2D rotation matrix (around Z axis) embedded in 3x3.
    @inlinable
    public static func rotation2D(radians: Float) -> simd_float3x3 {
        let c = cos(radians), s = sin(radians)
        return simd_float3x3(
            SIMD3<Float>(c, s, 0),
            SIMD3<Float>(-s, c, 0),
            SIMD3<Float>(0, 0, 1)
        )
    }

    /// Creates a scale matrix.
    @inlinable
    public static func scale(_ s: SIMD3<Float>) -> simd_float3x3 {
        simd_float3x3(diagonal: s)
    }
}
