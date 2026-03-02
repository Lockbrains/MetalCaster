import Foundation
import MetalCasterCore

/// Marks an entity as a predefined engine manager singleton.
/// Each ManagerType can only exist once in the scene.
public struct ManagerComponent: Component {
    public enum ManagerType: String, Codable, CaseIterable, Sendable {
        case game       = "Game Manager"
        case audio      = "Audio Manager"
        case input      = "Input Manager"
        case gui        = "GUI Manager"
        case physics    = "Physics Manager"
        case render     = "Render Manager"
    }

    public var managerType: ManagerType

    public init(managerType: ManagerType) {
        self.managerType = managerType
    }
}
