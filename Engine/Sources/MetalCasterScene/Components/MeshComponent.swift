import Foundation
import MetalCasterCore
import MetalCasterRenderer

/// References a mesh asset for rendering.
public struct MeshComponent: Component {
    /// The type of mesh to render.
    public var meshType: MeshType

    /// Whether this mesh casts shadows (future use).
    public var castsShadows: Bool

    /// Whether this mesh receives shadows (future use).
    public var receivesShadows: Bool

    public init(meshType: MeshType = .sphere, castsShadows: Bool = true, receivesShadows: Bool = true) {
        self.meshType = meshType
        self.castsShadows = castsShadows
        self.receivesShadows = receivesShadows
    }
}
