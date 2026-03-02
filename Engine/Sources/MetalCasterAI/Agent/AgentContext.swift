import Foundation

/// Context provided to an agent for a single interaction turn.
/// Wraps the engine snapshot with conversation-level metadata.
public struct AgentContext: Sendable {
    public let snapshot: EngineSnapshot
    public let conversationHistory: [ChatMessage]
    public let additionalContext: String?

    public init(snapshot: EngineSnapshot, conversationHistory: [ChatMessage] = [], additionalContext: String? = nil) {
        self.snapshot = snapshot
        self.conversationHistory = conversationHistory
        self.additionalContext = additionalContext
    }
}
