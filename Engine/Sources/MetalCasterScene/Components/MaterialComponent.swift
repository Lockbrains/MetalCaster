import Foundation
import MetalCasterCore
import MetalCasterRenderer

/// References a material for surface appearance.
public struct MaterialComponent: Component {
    /// The material definition.
    public var material: MCMaterial

    public init(material: MCMaterial = MCMaterial()) {
        self.material = material
    }
}
