import Foundation
import simd
import MetalCasterCore

/// Spatial transform component. Stores position, rotation, scale and parent entity for hierarchy.
public struct TransformComponent: Component {
    public var transform: MCTransform
    public var parent: Entity?

    /// Cached world matrix, computed by TransformSystem each frame.
    public var worldMatrix: simd_float4x4 = matrix_identity_float4x4

    public init(transform: MCTransform = .identity, parent: Entity? = nil) {
        self.transform = transform
        self.parent = parent
    }

    public init(position: SIMD3<Float> = .zero, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3<Float> = SIMD3<Float>(1,1,1), parent: Entity? = nil) {
        self.transform = MCTransform(position: position, rotation: rotation, scale: scale)
        self.parent = parent
    }

    // Manual Codable because simd_float4x4 isn't Codable
    enum CodingKeys: String, CodingKey {
        case transform, parent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transform = try c.decode(MCTransform.self, forKey: .transform)
        parent = try c.decodeIfPresent(Entity.self, forKey: .parent)
        worldMatrix = matrix_identity_float4x4
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transform, forKey: .transform)
        try c.encodeIfPresent(parent, forKey: .parent)
    }
}
