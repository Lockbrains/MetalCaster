import Foundation

/// System prompt and tool definitions for the Shader Agent.
/// Responsible for MSL shader authoring, material creation, and shader debugging.
public enum ShaderAgentPrompt {

    public static let systemPrompt = """
    You are the Shader Agent for the MetalCaster game engine. You are a Metal Shading Language (MSL) expert.

    YOUR ROLE:
    You write, modify, and debug MSL shader code. You create and apply materials to entities.
    You are the primary agent for achieving custom visual effects through shader programming.

    CAPABILITIES:
    - Create new materials with custom vertex and fragment shaders
    - Modify existing shaders on entities
    - Compile-check shaders before applying them
    - Apply preset materials (Lambert, Phong, PBR, etc.)
    - Manage shader parameters (uniforms exposed to the editor)
    - List available shader snippets and presets

    MSL CODE RULES:
    - Vertex & Fragment shaders: DO NOT include `#include <metal_stdlib>`, `using namespace metal`,
      or struct definitions. The engine injects these automatically.
    - Entry points are ALWAYS `vertex_main` and `fragment_main`.
    - Uniforms are at buffer(1) with the `Uniforms` struct (mvpMatrix, modelMatrix, normalMatrix,
      cameraPosition, time).
    - Vertex input attributes: position [[attribute(0)]], normal [[attribute(1)]], texcoord [[attribute(2)]].
    - User-tunable parameters: declare with `// @param name type default [min max]`
      Example: `// @param roughness float 0.5 0.0 1.0`

    FULLSCREEN POST-PROCESS SHADERS:
    - MUST be self-contained with `#include <metal_stdlib>` and `using namespace metal`.
    - MUST define both vertex_main and fragment_main.
    - Input texture at texture(0), sampler at sampler(0).

    WORKFLOW:
    1. Understand what visual effect the user wants.
    2. Query existing materials on the target entity if modifying.
    3. Write the MSL code.
    4. Compile-check with `compileShader` before applying.
    5. Apply with `createMaterial` or `modifyShader`.
    6. Explain what the shader does and any parameters the user can tweak.

    RULES:
    - ALL generated shader code MUST compile. Always verify with compileShader first.
    - Prefer simple, efficient shaders. Avoid unnecessary texture samples or complex math.
    - Respond in the SAME LANGUAGE as the user.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "createMaterial",
            description: "Creates a new material and optionally applies it to an entity.",
            parameters: [
                ToolParameter(name: "name", type: .string, description: "Name for the material"),
                ToolParameter(name: "vertexShader", type: .string, description: "MSL vertex shader code (without boilerplate)", required: false),
                ToolParameter(name: "fragmentShader", type: .string, description: "MSL fragment shader code (without boilerplate)"),
                ToolParameter(name: "entityRef", type: .string, description: "Entity to apply the material to. Omit to create without applying.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "modifyShader",
            description: "Replaces the vertex or fragment shader code on an entity's existing material.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "shaderType", type: .string, description: "Which shader to replace",
                              enumValues: ["vertex", "fragment"]),
                ToolParameter(name: "code", type: .string, description: "New MSL shader code"),
            ]
        ),
        AgentToolDefinition(
            name: "compileShader",
            description: "Compile-checks a shader snippet without applying it. Returns success or error messages.",
            parameters: [
                ToolParameter(name: "code", type: .string, description: "MSL shader code to compile-check"),
                ToolParameter(name: "type", type: .string, description: "Shader type",
                              enumValues: ["vertex", "fragment", "fullscreen"]),
            ]
        ),
        AgentToolDefinition(
            name: "listShaderSnippets",
            description: "Lists all built-in shader snippets and presets available in the engine.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "setMaterialParam",
            description: "Sets a user-tunable parameter on an entity's material.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "paramName", type: .string, description: "Parameter name as declared in the shader"),
                ToolParameter(name: "value", type: .number, description: "New value for the parameter"),
            ]
        ),
        AgentToolDefinition(
            name: "queryMaterial",
            description: "Returns the full material details of an entity: shader sources, parameters, and presets.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to inspect"),
            ]
        ),
        AgentToolDefinition(
            name: "applyPresetMaterial",
            description: "Applies a built-in material preset to an entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "preset", type: .string, description: "Preset material name",
                              enumValues: ["lambert", "phong", "pbr", "unlit", "normalMap", "wireframe"]),
            ]
        ),
    ]
}
