import Foundation

/// System prompt and tool definitions for the Asset Agent.
/// Responsible for asset pipeline management, importing/exporting, and project bundling.
public enum AssetAgentPrompt {

    public static let systemPrompt = """
    You are the Asset Management Agent for the MetalCaster game engine.

    YOUR ROLE:
    You manage the project's asset pipeline: 3D models (USD/USDZ/OBJ), textures, shader libraries,
    and scene files. You handle importing, exporting, organizing, and bundling assets.

    CAPABILITIES:
    - List and query project assets by type
    - Import external asset files (USD, USDZ, OBJ, PNG, JPEG, etc.)
    - Load textures into the engine runtime
    - Bundle the project into a distributable .mcbundle package
    - Create and organize project directory structures
    - Query project configuration and asset metadata

    EXPERTISE:
    - Universal Scene Description (USD/USDA/USDC/USDZ) format
    - Apple's asset pipeline (ModelIO, Metal textures)
    - Texture formats and compression (ASTC, BC, etc.)
    - Project organization best practices

    WORKFLOW:
    1. Query current project state and asset catalog.
    2. Determine the operation the user needs (import, export, organize, bundle).
    3. Validate inputs (file formats, paths, compatibility).
    4. Execute the operation via tools.
    5. Report results with any warnings.

    RULES:
    - Always verify file format compatibility before importing.
    - When bundling, ensure all dependent assets are included.
    - Supported mesh formats: .usd, .usda, .usdc, .usdz, .obj
    - Supported texture formats: .png, .jpg, .jpeg, .exr, .hdr
    - Respond in the SAME LANGUAGE as the user.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "listAssets",
            description: "Lists all assets in the project, optionally filtered by type.",
            parameters: [
                ToolParameter(name: "type", type: .string, description: "Asset type filter",
                              required: false, enumValues: ["mesh", "texture", "scene", "shader", "all"]),
            ]
        ),
        AgentToolDefinition(
            name: "importAsset",
            description: "Imports an external asset file into the project.",
            parameters: [
                ToolParameter(name: "path", type: .string, description: "File path or URL of the asset to import"),
                ToolParameter(name: "type", type: .string, description: "Asset type hint",
                              required: false, enumValues: ["mesh", "texture", "scene", "shader"]),
            ]
        ),
        AgentToolDefinition(
            name: "queryAssetMeta",
            description: "Returns metadata for a specific asset (GUID, type, size, last modified).",
            parameters: [
                ToolParameter(name: "path", type: .string, description: "Asset path within the project"),
            ]
        ),
        AgentToolDefinition(
            name: "loadTexture",
            description: "Loads a texture from the asset catalog into GPU memory.",
            parameters: [
                ToolParameter(name: "path", type: .string, description: "Path to the texture file"),
            ]
        ),
        AgentToolDefinition(
            name: "bundleProject",
            description: "Packages the project into a .mcbundle for distribution.",
            parameters: [
                ToolParameter(name: "platform", type: .string, description: "Target platform",
                              enumValues: ["macOS", "iOS", "tvOS", "visionOS"]),
                ToolParameter(name: "outputDir", type: .string, description: "Output directory for the bundle"),
            ]
        ),
        AgentToolDefinition(
            name: "createProjectStructure",
            description: "Creates a standard project directory structure at the given path.",
            parameters: [
                ToolParameter(name: "name", type: .string, description: "Project name"),
            ]
        ),
        AgentToolDefinition(
            name: "queryProjectConfig",
            description: "Returns the current project configuration (name, paths, platform targets).",
            parameters: []
        ),
    ]
}
