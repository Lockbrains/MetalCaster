import Foundation

// MARK: - AI Provider

/// The supported AI service providers.
public enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"

    public var id: String { rawValue }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4.1"
        case .anthropic: return "claude-sonnet-4-6-20260217"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    public var availableModels: [String] {
        switch self {
        case .openai: return ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "gpt-5.2", "gpt-5-mini", "gpt-5-nano", "gpt-4o", "gpt-4o-mini", "o4-mini"]
        case .anthropic: return ["claude-sonnet-4-6-20260217", "claude-opus-4-6-20260205", "claude-sonnet-4-20250514", "claude-4-opus-20250514", "claude-3-5-haiku-20241022"]
        case .gemini: return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash", "gemini-3.1-pro-preview", "gemini-3-flash-preview"]
        }
    }
}

// MARK: - Chat Message

/// A single message in the AI chat conversation.
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public let timestamp: Date
    public var executedActions: [AgentAction]?
    public var barriers: [String]?

    public enum MessageRole: String, Sendable { case user, assistant, system }

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        executedActions: [AgentAction]? = nil,
        barriers: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.executedActions = executedActions
        self.barriers = barriers
    }
}

// MARK: - Agent Types

/// The type of action the AI Agent can perform on the workspace.
public enum AgentActionType: String, Codable, Sendable {
    case addLayer
    case modifyLayer
}

/// A single action the AI Agent wants to perform on the shader workspace.
public struct AgentAction: Codable, Sendable {
    public let type: AgentActionType
    public let category: String
    public let name: String
    public let code: String
    public let targetLayerName: String?

    public init(type: AgentActionType, category: String, name: String, code: String, targetLayerName: String? = nil) {
        self.type = type
        self.category = category
        self.name = name
        self.code = code
        self.targetLayerName = targetLayerName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(AgentActionType.self, forKey: .type)
        category = try container.decode(String.self, forKey: .category)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        code = try container.decode(String.self, forKey: .code)
        targetLayerName = try container.decodeIfPresent(String.self, forKey: .targetLayerName)
    }
}

/// Structured response from the AI Agent.
public struct AgentResponse: Codable, Sendable {
    public let canFulfill: Bool
    public let explanation: String
    public let actions: [AgentAction]
    public let barriers: [String]?

    public static func plainText(_ text: String) -> AgentResponse {
        AgentResponse(canFulfill: true, explanation: text, actions: [], barriers: nil)
    }

    public init(canFulfill: Bool, explanation: String, actions: [AgentAction], barriers: [String]?) {
        self.canFulfill = canFulfill
        self.explanation = explanation
        self.actions = actions
        self.barriers = barriers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canFulfill = try container.decodeIfPresent(Bool.self, forKey: .canFulfill) ?? true
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        actions = try container.decodeIfPresent([AgentAction].self, forKey: .actions) ?? []
        barriers = try container.decodeIfPresent([String].self, forKey: .barriers)
    }
}

// MARK: - Tutorial Step

/// A single step in a tutorial progression.
public struct TutorialStep: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let subtitle: String
    public let instructions: String
    public let goal: String
    public let hint: String
    public let category: String
    public let starterCode: String
    public let solutionCode: String

    public init(id: Int, title: String, subtitle: String, instructions: String, goal: String, hint: String, category: String, starterCode: String, solutionCode: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.instructions = instructions
        self.goal = goal
        self.hint = hint
        self.category = category
        self.starterCode = starterCode
        self.solutionCode = solutionCode
    }
}

// MARK: - AI Error

/// Errors that can occur during AI API interactions.
public enum AIError: LocalizedError, Sendable {
    case notConfigured
    case apiError(provider: String, status: Int, message: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "No API key configured."
        case .apiError(let p, let s, let m): return "\(p) error (\(s)): \(String(m.prefix(200)))"
        case .invalidResponse(let d): return "Invalid AI response: \(d)"
        }
    }
}
