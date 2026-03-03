import Foundation
import simd

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
        matrix4x4TRS(translation: position, rotation: rotation, scale: scale)
    }

    /// The forward direction (-Z in local space), transformed by rotation.
    public var forward: SIMD3<Float> { rotation.forward }

    /// The right direction (+X in local space), transformed by rotation.
    public var right: SIMD3<Float> { rotation.right }

    /// The up direction (+Y in local space), transformed by rotation.
    public var up: SIMD3<Float> { rotation.up }

    public static let identity = MCTransform()

    /// Creates a transform from a 4x4 matrix by decomposing it.
    public init(matrix m: simd_float4x4) {
        let (t, r, s) = m.decompose()
        self.init(position: t, rotation: r, scale: s)
    }

    /// Linearly interpolates between two transforms.
    public func lerped(to other: MCTransform, t: Float) -> MCTransform {
        MCTransform(
            position: position + (other.position - position) * t,
            rotation: rotation.slerp(to: other.rotation, t: t),
            scale: scale + (other.scale - scale) * t
        )
    }
}
