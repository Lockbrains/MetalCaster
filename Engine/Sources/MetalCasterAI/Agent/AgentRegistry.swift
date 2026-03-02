import Foundation

/// Manages the lifecycle of all registered agents.
/// Provides lookup by role and tracks active agent state.
@Observable
public final class AgentRegistry {
    public private(set) var agents: [AgentRole: MCAgent] = [:]

    public init() {}

    /// Registers an agent. Replaces any existing agent with the same role.
    public func register(_ agent: MCAgent) {
        agents[agent.role] = agent
    }

    /// Returns the agent for a given role, if registered.
    public func agent(for role: AgentRole) -> MCAgent? {
        agents[role]
    }

    /// All currently registered agents, sorted by role order.
    public var allAgents: [MCAgent] {
        AgentRole.allCases.compactMap { agents[$0] }
    }

    /// Registers all built-in agents using the factory definitions.
    public func registerBuiltinAgents() {
        register(AgentDefinitions.sceneAgent())
        register(AgentDefinitions.renderAgent())
        register(AgentDefinitions.shaderAgent())
        register(AgentDefinitions.assetAgent())
        register(AgentDefinitions.optimizeAgent())
        register(AgentDefinitions.analyzeAgent())
    }

    /// Resets all agents' conversation history.
    public func resetAll() {
        for agent in agents.values {
            agent.resetConversation()
        }
    }
}
