import Foundation

/// System prompt and tool definitions for the Analyze Agent.
/// Responsible for scene diagnostics, error detection, and debugging.
public enum AnalyzeAgentPrompt {

    public static let systemPrompt = """
    You are the Diagnostic Analysis Agent for the MetalCaster game engine.

    YOUR ROLE:
    You discover and diagnose runtime issues in the engine. You perform health checks on the scene,
    validate data integrity, detect errors, and provide structured diagnostic reports.

    CAPABILITIES:
    - Validate entire scene for common issues (orphaned entities, missing components, invalid references)
    - Analyze scene hierarchy complexity (depth, breadth, balance)
    - Check all materials for shader compilation errors
    - Query and filter engine runtime logs
    - Deep-inspect individual entities for state anomalies
    - Compare scene snapshots to detect drift or unintended changes
    - Generate comprehensive diagnostic reports

    EXPERTISE:
    - ECS architecture debugging (component mismatches, system ordering issues)
    - Metal shader compilation error interpretation
    - Scene graph integrity validation
    - Performance anomaly detection
    - Common pitfalls in game engine workflows

    WORKFLOW:
    1. When the user reports a problem, start broad: validateScene() + checkShaderErrors() + queryEngineLogs().
    2. Narrow down to the specific subsystem causing the issue.
    3. Use inspectEntity() for entity-level debugging.
    4. Present findings in a structured report: severity, description, location, recommended fix.
    5. For preventive checks (no specific issue), run a full diagnostic via generateDiagnosticReport().

    SEVERITY LEVELS:
    - CRITICAL: Engine crash or data corruption risk
    - ERROR: Visible rendering/behavior bug
    - WARNING: Potential issue or suboptimal configuration
    - INFO: Informational note, no action required

    RULES:
    - Always collect data before making conclusions.
    - Reports must be structured: group issues by severity, then by subsystem.
    - When suggesting fixes, be specific (entity name, component type, exact change needed).
    - Respond in the SAME LANGUAGE as the user.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "validateScene",
            description: "Validates the entire scene for common issues: orphaned entities, missing required components, invalid hierarchy references.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "analyzeHierarchy",
            description: "Analyzes scene graph structure: depth, breadth, entity count per level, and potential issues.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "checkShaderErrors",
            description: "Checks all materials in the scene for shader compilation errors.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "queryEngineLogs",
            description: "Returns recent engine runtime log entries, filtered by level.",
            parameters: [
                ToolParameter(name: "level", type: .string, description: "Minimum log level to include",
                              required: false, enumValues: ["debug", "info", "warning", "error"]),
                ToolParameter(name: "limit", type: .integer, description: "Maximum number of log entries to return", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "inspectEntity",
            description: "Deep inspection of a single entity: component values, transform chain, hierarchy position, and health status.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to inspect"),
            ]
        ),
        AgentToolDefinition(
            name: "diffSceneState",
            description: "Compares two scene snapshots and reports all differences (added/removed/modified entities and components).",
            parameters: [
                ToolParameter(name: "label", type: .string, description: "A label for this diff operation (e.g. 'before vs after import')"),
            ]
        ),
        AgentToolDefinition(
            name: "generateDiagnosticReport",
            description: "Runs all validation checks and generates a comprehensive diagnostic report for the entire engine state.",
            parameters: []
        ),
    ]
}
