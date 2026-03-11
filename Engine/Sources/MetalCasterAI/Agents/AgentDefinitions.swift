import Foundation

/// Factory methods that produce fully-configured `MCAgent` instances
/// for each engine domain. Each agent comes with a system prompt and
/// a complete set of tool definitions.
public enum AgentDefinitions {

    // MARK: - Scene Agent

    public static func sceneAgent() -> MCAgent {
        MCAgent(
            role: .scene,
            systemPrompt: SceneAgentPrompt.systemPrompt,
            tools: SceneAgentPrompt.tools
        )
    }

    // MARK: - Render Agent

    public static func renderAgent() -> MCAgent {
        MCAgent(
            role: .render,
            systemPrompt: RenderAgentPrompt.systemPrompt,
            tools: RenderAgentPrompt.tools
        )
    }

    // MARK: - Shader Agent

    public static func shaderAgent() -> MCAgent {
        MCAgent(
            role: .shader,
            systemPrompt: ShaderAgentPrompt.systemPrompt,
            tools: ShaderAgentPrompt.tools
        )
    }

    // MARK: - Asset Agent

    public static func assetAgent() -> MCAgent {
        MCAgent(
            role: .asset,
            systemPrompt: AssetAgentPrompt.systemPrompt,
            tools: AssetAgentPrompt.tools
        )
    }

    // MARK: - Optimize Agent

    public static func optimizeAgent() -> MCAgent {
        MCAgent(
            role: .optimize,
            systemPrompt: OptimizeAgentPrompt.systemPrompt,
            tools: OptimizeAgentPrompt.tools
        )
    }

    // MARK: - Analyze Agent

    public static func analyzeAgent() -> MCAgent {
        MCAgent(
            role: .analyze,
            systemPrompt: AnalyzeAgentPrompt.systemPrompt,
            tools: AnalyzeAgentPrompt.tools
        )
    }

    // MARK: - Art Agent

    public static func artAgent() -> MCAgent {
        MCAgent(
            role: .art,
            systemPrompt: ArtAgentPrompt.systemPrompt,
            tools: ArtAgentPrompt.tools
        )
    }

    // MARK: - Audio Agent

    public static func audioAgent() -> MCAgent {
        MCAgent(
            role: .audio,
            systemPrompt: AudioAgentPrompt.systemPrompt,
            tools: AudioAgentPrompt.tools
        )
    }

    // MARK: - Composer Agent

    public static func composerAgent() -> MCAgent {
        MCAgent(
            role: .composer,
            systemPrompt: ComposerAgentPrompt.systemPrompt,
            tools: ComposerAgentPrompt.tools
        )
    }
}
