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
        case .openai: return "gpt-5.2"
        case .anthropic: return "claude-sonnet-4-6"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    public var availableModels: [String] {
        switch self {
        case .openai: return [
            "gpt-5.3-codex",
            "gpt-5.2",
            "gpt-5.2-codex",
            "o4-mini",
            "gpt-4.1",
            "gpt-4.1-mini",
            "gpt-4.1-nano",
            "codex-mini-latest",
        ]
        case .anthropic: return [
            "claude-opus-4-6",
            "claude-sonnet-4-6",
            "claude-opus-4-20250514",
            "claude-sonnet-4-20250514",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001",
        ]
        case .gemini: return [
            "gemini-3.1-pro-preview",
            "gemini-3-flash-preview",
            "gemini-2.5-pro",
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite",
        ]
        }
    }

    /// Human-readable display name for each model ID.
    public func displayName(for model: String) -> String {
        switch model {
        case "gpt-5.3-codex":              return "GPT-5.3 Codex"
        case "gpt-5.2":                    return "GPT-5.2"
        case "gpt-5.2-codex":              return "GPT-5.2 Codex"
        case "o4-mini":                    return "o4-mini"
        case "gpt-4.1":                    return "GPT-4.1"
        case "gpt-4.1-mini":               return "GPT-4.1 Mini"
        case "gpt-4.1-nano":               return "GPT-4.1 Nano"
        case "codex-mini-latest":           return "Codex Mini"
        case "claude-opus-4-6":             return "Claude Opus 4.6"
        case "claude-sonnet-4-6":           return "Claude Sonnet 4.6"
        case "claude-opus-4-20250514":      return "Claude Opus 4"
        case "claude-sonnet-4-20250514":    return "Claude Sonnet 4"
        case "claude-sonnet-4-5-20250929":  return "Claude Sonnet 4.5"
        case "claude-haiku-4-5-20251001":   return "Claude Haiku 4.5"
        case "gemini-3.1-pro-preview":      return "Gemini 3.1 Pro"
        case "gemini-3-flash-preview":      return "Gemini 3 Flash"
        case "gemini-2.5-pro":              return "Gemini 2.5 Pro"
        case "gemini-2.5-flash":            return "Gemini 2.5 Flash"
        case "gemini-2.5-flash-lite":       return "Gemini 2.5 Flash Lite"
        default:                            return model
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
        case .apiError(let p, let s, let m):
            if let data = m.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return "\(p) (\(s)): \(message)"
            }
            return "\(p) error (\(s)): \(String(m.prefix(300)))"
        case .invalidResponse(let d): return "Invalid AI response: \(d)"
        }
    }
}
