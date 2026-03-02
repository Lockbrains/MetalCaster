import Foundation

/// Protocol for engine-side tool execution. Implemented in the editor target
/// where `EditorState`, `World`, and `SceneGraph` are accessible.
public protocol EngineAPIProvider: AnyObject {
    /// Execute a named tool with the given arguments. Returns a result with success/failure and output text.
    func executeTool(name: String, arguments: [String: JSONValue]) async throws -> ToolResult

    /// Capture the current engine state as a serializable snapshot.
    func takeSnapshot() -> EngineSnapshot
}
