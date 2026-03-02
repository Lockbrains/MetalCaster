import Foundation

/// A configurable AI agent specialized for a specific engine domain.
///
/// Each agent wraps a system prompt, a set of tool definitions, and conversation state.
/// The `chat` method handles the full LLM round-trip: build prompt -> call LLM -> parse response.
@Observable
public final class MCAgent: Identifiable {
    public let id: String
    public let role: AgentRole
    public var status: AgentStatus
    public var conversationHistory: [ChatMessage]

    /// The base system prompt describing this agent's role and capabilities.
    public let systemPromptTemplate: String

    /// Tools this agent can invoke via LLM function calling.
    public let toolDefinitions: [AgentToolDefinition]

    public init(role: AgentRole, systemPrompt: String, tools: [AgentToolDefinition]) {
        self.id = role.rawValue
        self.role = role
        self.status = .idle
        self.conversationHistory = []
        self.systemPromptTemplate = systemPrompt
        self.toolDefinitions = tools
    }

    // MARK: - Chat

    /// Sends a user message to this agent and returns the response with any tool calls.
    /// The caller is responsible for executing tool calls via `EngineAPIProvider`.
    public func chat(
        message: String,
        snapshot: EngineSnapshot,
        settings: AISettings
    ) async throws -> AgentChatResponse {
        status = .thinking

        let userMessage = ChatMessage(role: .user, content: message)
        conversationHistory.append(userMessage)

        let systemPrompt = buildFullSystemPrompt(snapshot: snapshot)
        let aiService = AIService.shared

        do {
            let rawResponse = try await aiService.agentToolChat(
                messages: conversationHistory,
                systemPrompt: systemPrompt,
                settings: settings
            )

            let parsed = parseAgentChatResponse(rawResponse)

            let assistantMessage = ChatMessage(
                role: .assistant,
                content: parsed.response
            )
            conversationHistory.append(assistantMessage)
            status = parsed.toolCalls.isEmpty ? .idle : .executing

            return parsed
        } catch {
            status = .error
            let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            conversationHistory.append(errorMessage)
            throw error
        }
    }

    /// After tool calls are executed, feed results back and get the agent's follow-up.
    public func handleToolResults(
        _ results: [ToolResult],
        snapshot: EngineSnapshot,
        settings: AISettings
    ) async throws -> AgentChatResponse {
        status = .thinking

        var resultSummary = "Tool execution results:\n"
        for r in results {
            let status = r.success ? "OK" : "FAILED"
            resultSummary += "[\(r.toolName)] \(status): \(r.output)\n"
        }

        let followUp = ChatMessage(role: .user, content: resultSummary)
        conversationHistory.append(followUp)

        let systemPrompt = buildFullSystemPrompt(snapshot: snapshot)
        let aiService = AIService.shared

        do {
            let rawResponse = try await aiService.agentToolChat(
                messages: conversationHistory,
                systemPrompt: systemPrompt,
                settings: settings
            )
            let parsed = parseAgentChatResponse(rawResponse)
            let assistantMessage = ChatMessage(role: .assistant, content: parsed.response)
            conversationHistory.append(assistantMessage)
            status = .idle
            return parsed
        } catch {
            status = .error
            throw error
        }
    }

    /// Clears conversation history for a fresh session.
    public func resetConversation() {
        conversationHistory.removeAll()
        status = .idle
    }

    // MARK: - Prompt Building

    private func buildFullSystemPrompt(snapshot: EngineSnapshot) -> String {
        var prompt = systemPromptTemplate

        prompt += "\n\n## Current Engine State\n"
        prompt += snapshot.textDescription

        prompt += "\n\n## Available Tools\n"
        for tool in toolDefinitions {
            prompt += "\n" + tool.promptDescription + "\n"
        }

        prompt += """

        \n## Response Format
        You MUST respond with ONLY a valid JSON object. No markdown fences, no extra text.
        {
          "thinking": "your internal reasoning (not shown to user)",
          "actions": [
            {"tool": "toolName", "arguments": {"param1": "value1"}}
          ],
          "response": "your response to the user (same language as user)"
        }
        Set "actions" to [] when no tool calls are needed (e.g. answering a question).
        All tool names must match exactly from the Available Tools list.
        Always respond in the SAME LANGUAGE the user writes in.
        """

        return prompt
    }

    private func parseAgentChatResponse(_ raw: String) -> AgentChatResponse {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AgentChatResponse(response: cleaned, toolCalls: [])
        }

        let response = json["response"] as? String ?? cleaned

        var toolCalls: [ToolCallRequest] = []
        if let actions = json["actions"] as? [[String: Any]] {
            for action in actions {
                guard let toolName = action["tool"] as? String,
                      let args = action["arguments"] as? [String: Any] else { continue }
                let jsonArgs = args.mapValues { convertToJSONValue($0) }
                toolCalls.append(ToolCallRequest(tool: toolName, arguments: jsonArgs))
            }
        }

        return AgentChatResponse(response: response, toolCalls: toolCalls)
    }

    private func convertToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let s as String:   return .string(s)
        case let i as Int:      return .integer(i)
        case let d as Double:   return .number(d)
        case let f as Float:    return .number(Double(f))
        case let b as Bool:     return .boolean(b)
        case let a as [Any]:    return .array(a.map { convertToJSONValue($0) })
        case let o as [String: Any]: return .object(o.mapValues { convertToJSONValue($0) })
        default: return .null
        }
    }
}

/// The parsed response from an agent's LLM interaction.
public struct AgentChatResponse: Sendable {
    public let response: String
    public let toolCalls: [ToolCallRequest]

    public init(response: String, toolCalls: [ToolCallRequest]) {
        self.response = response
        self.toolCalls = toolCalls
    }
}
