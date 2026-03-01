import Foundation
import simd

// MARK: - Transform

/// 3D transform component data. Used by the ECS Transform component
/// and throughout the engine for spatial calculations.
public struct MCTransform: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>

    public init(
        position: SIMD3<Float> = .zero,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

// Manual Codable conformance because simd_quatf doesn't conform to Codable.
extension MCTransform: Codable {
    enum CodingKeys: String, CodingKey {
        case px, py, pz, rx, ry, rz, rw, sx, sy, sz
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.position = SIMD3<Float>(
            try c.decode(Float.self, forKey: .px),
            try c.decode(Float.self, forKey: .py),
            try c.decode(Float.self, forKey: .pz)
        )
        self.rotation = simd_quatf(
            ix: try c.decode(Float.self, forKey: .rx),
            iy: try c.decode(Float.self, forKey: .ry),
            iz: try c.decode(Float.self, forKey: .rz),
            r: try c.decode(Float.self, forKey: .rw)
        )
        self.scale = SIMD3<Float>(
            try c.decode(Float.self, forKey: .sx),
            try c.decode(Float.self, forKey: .sy),
            try c.decode(Float.self, forKey: .sz)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(position.x, forKey: .px)
        try c.encode(position.y, forKey: .py)
        try c.encode(position.z, forKey: .pz)
        try c.encode(rotation.imag.x, forKey: .rx)
        try c.encode(rotation.imag.y, forKey: .ry)
        try c.encode(rotation.imag.z, forKey: .rz)
        try c.encode(rotation.real, forKey: .rw)
        try c.encode(scale.x, forKey: .sx)
        try c.encode(scale.y, forKey: .sy)
        try c.encode(scale.z, forKey: .sz)
    }

    /// Computes the 4x4 model matrix: T * R * S
    public var matrix: simd_float4x4 {
        let t = matrix4x4Translation(position)
        let r = simd_float4x4(rotation)
        let s = matrix4x4Scale(scale)
        return t * r * s
    }

    /// The forward direction (-Z in local space), transformed by rotation.
    public var forward: SIMD3<Float> {
        rotation.act(SIMD3<Float>(0, 0, -1))
    }

    /// The right direction (+X in local space), transformed by rotation.
    public var right: SIMD3<Float> {
        rotation.act(SIMD3<Float>(1, 0, 0))
    }

    /// The up direction (+Y in local space), transformed by rotation.
    public var up: SIMD3<Float> {
        rotation.act(SIMD3<Float>(0, 1, 0))
    }

    public static let identity = MCTransform()
}

// MARK: - Matrix Helpers

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
    let a = normalize(axis)
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

/// Creates a right-handed perspective projection matrix.
/// Metal uses clip space Z range [0, 1].
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
    let f = normalize(target - eye)
    let s = normalize(cross(f, up))
    let u = cross(s, f)
    return simd_float4x4(columns: (
        SIMD4<Float>(s.x, u.x, -f.x, 0),
        SIMD4<Float>(s.y, u.y, -f.y, 0),
        SIMD4<Float>(s.z, u.z, -f.z, 0),
        SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
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

// MARK: - Euler ↔ Quaternion

/// Creates a quaternion from Euler angles (in radians), applied in YXZ order.
public func quaternionFromEuler(_ euler: SIMD3<Float>) -> simd_quatf {
    let qx = simd_quatf(angle: euler.x, axis: SIMD3<Float>(1, 0, 0))
    let qy = simd_quatf(angle: euler.y, axis: SIMD3<Float>(0, 1, 0))
    let qz = simd_quatf(angle: euler.z, axis: SIMD3<Float>(0, 0, 1))
    return qy * qx * qz
}
