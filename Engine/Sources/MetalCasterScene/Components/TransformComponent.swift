import Foundation
import simd
import MetalCasterCore

/// Spatial transform component. Stores local position, rotation, and scale.
/// Parent-child hierarchy is managed separately via `ParentComponent` / `ChildrenComponent`.
public struct TransformComponent: Component {
    public var transform: MCTransform

    /// Cached world matrix, computed by TransformSystem each frame.
    public var worldMatrix: simd_float4x4 = matrix_identity_float4x4

    public init(transform: MCTransform = .identity) {
        self.transform = transform
    }

    public init(position: SIMD3<Float> = .zero, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3<Float> = SIMD3<Float>(1,1,1)) {
        self.transform = MCTransform(position: position, rotation: rotation, scale: scale)
    }

    enum CodingKeys: String, CodingKey {
        case transform
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transform = try c.decode(MCTransform.self, forKey: .transform)
        worldMatrix = matrix_identity_float4x4
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transform, forKey: .transform)
    }
}
