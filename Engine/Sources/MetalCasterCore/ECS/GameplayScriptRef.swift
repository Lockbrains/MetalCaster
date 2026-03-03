import Foundation

/// Attaches a gameplay script reference to an entity at edit-time.
///
/// The editor uses this to associate an entity with a named gameplay script
/// (either hand-written or AI-generated) without needing the concrete Swift type
/// at compile time. At Play time the build system maps `scriptName` to the real
/// `Component` + `System` types discovered via source scanning.
public struct GameplayScriptRef: Component {
    public static let componentName = "GameplayScriptRef"

    public var scriptName: String
    public var properties: [String: String]

    public init(scriptName: String = "", properties: [String: String] = [:]) {
        self.scriptName = scriptName
        self.properties = properties
    }
}
