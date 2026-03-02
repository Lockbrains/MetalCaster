import Foundation

/// Coordinates multi-agent workflows by decomposing user requests into sub-tasks
/// and dispatching them to specialist agents in dependency order.
@Observable
public final class AgentOrchestrator {
    public var conversationHistory: [ChatMessage] = []
    public var status: AgentStatus = .idle
    public var activeTasks: [OrchestratorTask] = []

    private let registry: AgentRegistry
    private weak var engineAPI: EngineAPIProvider?

    public init(registry: AgentRegistry) {
        self.registry = registry
    }

    public func setEngineAPI(_ api: EngineAPIProvider) {
        self.engineAPI = api
    }

    // MARK: - Chat

    /// Processes a user message through the Orchestrator. The Orchestrator plans
    /// sub-tasks and dispatches them to specialist agents.
    public func chat(
        message: String,
        snapshot: EngineSnapshot,
        settings: AISettings
    ) async throws -> OrchestratorResponse {
        status = .thinking
        let userMessage = ChatMessage(role: .user, content: message)
        conversationHistory.append(userMessage)

        let systemPrompt = buildSystemPrompt(snapshot: snapshot)
        let aiService = AIService.shared

        do {
            let rawResponse = try await aiService.agentToolChat(
                messages: conversationHistory,
                systemPrompt: systemPrompt,
                settings: settings
            )

            let plan = parseOrchestratorPlan(rawResponse)

            if !plan.delegations.isEmpty {
                status = .executing
                var results: [DelegationResult] = []

                for delegation in plan.delegations {
                    let result = await executeDelegation(delegation, snapshot: snapshot, settings: settings)
                    results.append(result)
                }

                let summary = buildResultSummary(plan: plan, results: results)
                let assistantMessage = ChatMessage(role: .assistant, content: summary)
                conversationHistory.append(assistantMessage)
                status = .idle

                return OrchestratorResponse(
                    response: summary,
                    plan: plan,
                    results: results
                )
            } else {
                let assistantMessage = ChatMessage(role: .assistant, content: plan.response)
                conversationHistory.append(assistantMessage)
                status = .idle
                return OrchestratorResponse(response: plan.response, plan: plan, results: [])
            }
        } catch {
            status = .error
            let errorMsg = ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
            conversationHistory.append(errorMsg)
            throw error
        }
    }

    public func resetConversation() {
        conversationHistory.removeAll()
        activeTasks.removeAll()
        status = .idle
    }

    // MARK: - Delegation Execution

    private func executeDelegation(
        _ delegation: TaskDelegation,
        snapshot: EngineSnapshot,
        settings: AISettings
    ) async -> DelegationResult {
        guard let agent = registry.agent(for: delegation.targetAgent) else {
            return DelegationResult(
                delegation: delegation,
                success: false,
                output: "Agent \(delegation.targetAgent.rawValue) is not registered."
            )
        }

        do {
            let response = try await agent.chat(
                message: delegation.taskDescription,
                snapshot: snapshot,
                settings: settings
            )

            if !response.toolCalls.isEmpty, let api = engineAPI {
                var toolResults: [ToolResult] = []
                for call in response.toolCalls {
                    let result = try await api.executeTool(name: call.tool, arguments: call.arguments)
                    toolResults.append(result)
                }
                let allSucceeded = toolResults.allSatisfy { $0.success }
                let output = toolResults.map { "[\($0.toolName)] \($0.output)" }.joined(separator: "\n")
                return DelegationResult(
                    delegation: delegation,
                    success: allSucceeded,
                    output: "\(response.response)\n\nTool results:\n\(output)"
                )
            }

            return DelegationResult(
                delegation: delegation,
                success: true,
                output: response.response
            )
        } catch {
            return DelegationResult(
                delegation: delegation,
                success: false,
                output: "Error: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(snapshot: EngineSnapshot) -> String {
        var agentList = ""
        for agent in registry.allAgents {
            agentList += "- \(agent.role.rawValue): \(agent.role.tagline) (status: \(agent.status.rawValue))\n"
        }

        return """
        You are the MetalCaster Orchestrator — the central coordinator for the engine's AI agent team.

        YOUR ROLE:
        You are the bridge between the user and the specialist agents. You decompose complex requests
        into sub-tasks and delegate them to the appropriate agents in the correct order.

        AVAILABLE AGENTS:
        \(agentList)

        CURRENT ENGINE STATE:
        \(snapshot.textDescription)

        WORKFLOW:
        1. Analyze the user's request and determine which agents are needed.
        2. Plan the execution order (respect dependencies: create entities before adding materials).
        3. For each sub-task, specify which agent handles it and what they should do.
        4. If the request is ambiguous, ask the user to clarify before delegating.

        RESPONSE FORMAT:
        You MUST respond with ONLY a valid JSON object:
        {
          "thinking": "your reasoning about task decomposition",
          "delegations": [
            {
              "agent": "Scene|Render|Shader|Asset|Optimize|Analyze",
              "task": "specific instruction for the agent",
              "priority": 1
            }
          ],
          "response": "summary message for the user (same language as user)"
        }

        Set "delegations" to [] when no agent action is needed (e.g. answering a question).
        Order delegations by priority (lower number = execute first).
        Delegations with the same priority can run in parallel.
        Always respond in the SAME LANGUAGE as the user.
        """
    }

    // MARK: - Response Parsing

    private func parseOrchestratorPlan(_ raw: String) -> OrchestratorPlan {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let fencePattern = #"```(?:json)?\s*([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return OrchestratorPlan(thinking: "", delegations: [], response: cleaned)
        }

        let thinking = json["thinking"] as? String ?? ""
        let response = json["response"] as? String ?? cleaned

        var delegations: [TaskDelegation] = []
        if let dels = json["delegations"] as? [[String: Any]] {
            for del in dels {
                guard let agentName = del["agent"] as? String,
                      let role = AgentRole(rawValue: agentName),
                      let task = del["task"] as? String else { continue }
                let priority = del["priority"] as? Int ?? 0
                delegations.append(TaskDelegation(targetAgent: role, taskDescription: task, priority: priority))
            }
        }
        delegations.sort { $0.priority < $1.priority }

        return OrchestratorPlan(thinking: thinking, delegations: delegations, response: response)
    }

    private func buildResultSummary(plan: OrchestratorPlan, results: [DelegationResult]) -> String {
        var summary = plan.response + "\n\n"
        for result in results {
            let icon = result.success ? "OK" : "FAILED"
            summary += "[\(result.delegation.targetAgent.rawValue)] \(icon): \(result.output)\n"
        }
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Types

public struct OrchestratorTask: Identifiable, Sendable {
    public let id: String
    public let description: String
    public let targetAgent: AgentRole
    public var status: AgentStatus

    public init(id: String = UUID().uuidString, description: String, targetAgent: AgentRole, status: AgentStatus = .idle) {
        self.id = id
        self.description = description
        self.targetAgent = targetAgent
        self.status = status
    }
}

public struct TaskDelegation: Sendable {
    public let targetAgent: AgentRole
    public let taskDescription: String
    public let priority: Int

    public init(targetAgent: AgentRole, taskDescription: String, priority: Int = 0) {
        self.targetAgent = targetAgent
        self.taskDescription = taskDescription
        self.priority = priority
    }
}

public struct OrchestratorPlan: Sendable {
    public let thinking: String
    public let delegations: [TaskDelegation]
    public let response: String
}

public struct DelegationResult: Sendable {
    public let delegation: TaskDelegation
    public let success: Bool
    public let output: String
}

public struct OrchestratorResponse: Sendable {
    public let response: String
    public let plan: OrchestratorPlan
    public let results: [DelegationResult]
}
