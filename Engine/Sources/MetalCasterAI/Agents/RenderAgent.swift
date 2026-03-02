import Foundation

/// System prompt and tool definitions for the Render Agent.
/// Responsible for rendering pipeline configuration, lighting, post-processing, and camera setup.
public enum RenderAgentPrompt {

    public static let systemPrompt = """
    You are the Render Agent for the MetalCaster game engine.

    YOUR ROLE:
    You configure and optimize the Metal rendering pipeline. You manage lighting setups,
    post-processing effects, render modes, and camera parameters.

    CAPABILITIES:
    - Switch between shading, wireframe, and rendered display modes
    - Add and configure lights (directional, point, spot) with full parameter control
    - Set up cameras with perspective/orthographic projection and custom parameters
    - Add post-processing passes with custom MSL shader code
    - Query the current render state (draw calls, light count, mode)
    - Capture frame-level information for analysis

    EXPERTISE:
    - Metal API and Apple Silicon GPU architecture
    - PBR (Physically Based Rendering) lighting models
    - Post-processing techniques (bloom, tone mapping, color grading, SSAO, etc.)
    - Camera composition and cinematic framing

    WORKFLOW:
    1. Query current render state to understand the scene.
    2. Determine the best rendering approach for the user's visual goal.
    3. Execute changes through tool calls.
    4. Explain what you changed and why.

    RULES:
    - All post-process shader code must be valid MSL and self-contained.
    - Light intensities use physically-based units where possible.
    - Always consider performance impact when adding lights or effects.
    - Respond in the SAME LANGUAGE as the user.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "setRenderMode",
            description: "Switches the viewport render mode.",
            parameters: [
                ToolParameter(name: "mode", type: .string, description: "The render mode to set",
                              enumValues: ["shading", "wireframe", "rendered"]),
            ]
        ),
        AgentToolDefinition(
            name: "configureLighting",
            description: "Adjusts the lighting parameters of a light entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the light entity"),
                ToolParameter(name: "intensity", type: .number, description: "Light intensity value", required: false),
                ToolParameter(name: "color", type: .array, description: "RGB color as [r, g, b] (0-1 range)", required: false),
                ToolParameter(name: "range", type: .number, description: "Range for point/spot lights", required: false),
                ToolParameter(name: "innerConeAngle", type: .number, description: "Inner cone angle in degrees for spot lights", required: false),
                ToolParameter(name: "outerConeAngle", type: .number, description: "Outer cone angle in degrees for spot lights", required: false),
                ToolParameter(name: "castsShadows", type: .boolean, description: "Whether the light casts shadows", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "addLight",
            description: "Creates a new light entity in the scene.",
            parameters: [
                ToolParameter(name: "type", type: .string, description: "Light type",
                              enumValues: ["directional", "point", "spot"]),
                ToolParameter(name: "name", type: .string, description: "Name for the light entity", required: false),
                ToolParameter(name: "position", type: .array, description: "Position as [x, y, z]", required: false),
                ToolParameter(name: "intensity", type: .number, description: "Light intensity", required: false),
                ToolParameter(name: "color", type: .array, description: "RGB color as [r, g, b]", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "addPostProcess",
            description: "Adds a fullscreen post-processing pass with custom MSL shader code.",
            parameters: [
                ToolParameter(name: "name", type: .string, description: "Name for the post-process effect"),
                ToolParameter(name: "shaderCode", type: .string, description: "Complete MSL shader code for the fullscreen pass. Must include #include <metal_stdlib>, vertex_main, and fragment_main."),
            ]
        ),
        AgentToolDefinition(
            name: "queryRenderState",
            description: "Returns current render pipeline state: draw call count, light count, render mode, and camera info.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "setCamera",
            description: "Configures camera parameters on a camera entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the camera entity"),
                ToolParameter(name: "fov", type: .number, description: "Field of view in degrees", required: false),
                ToolParameter(name: "nearZ", type: .number, description: "Near clipping plane distance", required: false),
                ToolParameter(name: "farZ", type: .number, description: "Far clipping plane distance", required: false),
                ToolParameter(name: "isActive", type: .boolean, description: "Whether this is the active camera", required: false),
                ToolParameter(name: "projection", type: .string, description: "Projection mode", required: false,
                              enumValues: ["perspective", "orthographic"]),
            ]
        ),
        AgentToolDefinition(
            name: "captureFrame",
            description: "Captures information about the current frame: timing, draw calls, shader passes, and GPU workload.",
            parameters: []
        ),
    ]
}
