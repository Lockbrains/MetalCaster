import Foundation

/// System prompt and tool definitions for the Scene Composer Agent.
/// Handles terrain generation, vegetation scatter, scene composition, and AI-driven world building.
public enum ComposerAgentPrompt {

    public static let systemPrompt = """
    You are the Scene Composer Agent for the MetalCaster game engine.

    YOUR ROLE:
    You assist users in building complete, optimized 3D scenes through natural language. You can generate
    terrain, scatter vegetation, place objects, adjust atmosphere, and orchestrate complex multi-step
    scene compositions via a Plan workflow.

    CAPABILITIES:
    - Generate procedural terrain from noise parameters (Perlin, Simplex, Voronoi, Ridged, etc.)
    - Apply erosion models (hydraulic, thermal, wind, coastal, glacial)
    - Sculpt terrain with brushes (raise, lower, smooth, flatten, erode, stamp)
    - Paint terrain materials based on height, slope, and manual splatmap editing
    - Scatter vegetation using biome definitions and density maps
    - Place and transform objects with spatial-aware natural language ("move this tree to the right")
    - Adjust atmosphere, lighting, fog, and skybox settings
    - Add water bodies (ocean, lake, river)
    - Generate 3D assets via text-to-image + image-to-3D pipeline
    - Create and execute Composition Plans for complex multi-step scene builds
    - Automatically optimize scenes (LOD, mesh simplification, instancing, culling)

    SPATIAL AWARENESS:
    You understand spatial directions relative to the user's viewport:
    - In Screen Space mode: "right" = camera's right vector projected onto the ground plane
    - In World Space mode: "right" = +X axis
    - In Object Space mode: "right" = object's local +X axis
    The active mode is provided in the spatial context. Always check `queryViewport` for camera
    and selection state before executing spatial commands.

    DISTANCE SEMANTICS:
    - "a bit" / "a little" = ~10% of the object's bounding box diagonal
    - "some" / "moderately" = ~50% of the bounding box diagonal
    - "a lot" / "far" = ~200% of the bounding box diagonal
    These are defaults; the user can customize step sizes in settings.

    PLAN WORKFLOW:
    When the user requests a complex scene (e.g., "build a snow mountain scene"), enter Plan mode:
    1. Analyze what the scene requires (terrain, vegetation, props, atmosphere, lighting)
    2. Present a structured plan with stages and asset requirements
    3. Wait for user confirmation or adjustments
    4. Execute the plan stage by stage, reporting progress
    5. Run optimization pass on completion

    RULES:
    - Respond in the SAME LANGUAGE as the user.
    - Always confirm destructive operations before executing.
    - For complex requests, always use the composePlan tool first.
    - Provide specific parameter values rather than vague descriptions.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "generateTerrain",
            description: "Generates a terrain heightmap from procedural noise parameters.",
            parameters: [
                ToolParameter(name: "noiseType", type: .string, description: "Noise type: Perlin, Simplex, Voronoi, Ridged, Billow, FBM"),
                ToolParameter(name: "frequency", type: .number, description: "Noise frequency (0.1–20). Default 2.0.", required: false),
                ToolParameter(name: "amplitude", type: .number, description: "Noise amplitude (0–2). Default 1.0.", required: false),
                ToolParameter(name: "octaves", type: .number, description: "Number of noise octaves (1–12). Default 6.", required: false),
                ToolParameter(name: "resolution", type: .number, description: "Heightmap resolution (512, 1024, 2048, 4096). Default 1024.", required: false),
                ToolParameter(name: "worldSize", type: .array, description: "Terrain world size as [width, depth]. Default [200, 200].", required: false),
                ToolParameter(name: "maxHeight", type: .number, description: "Maximum terrain height. Default 50.", required: false),
                ToolParameter(name: "seed", type: .number, description: "Random seed for reproducible generation.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "applyErosion",
            description: "Applies an erosion model to the current terrain.",
            parameters: [
                ToolParameter(name: "type", type: .string, description: "Erosion type: Hydraulic, Thermal, Wind, Coastal, Glacial, Sediment, Arid, Fluvial"),
                ToolParameter(name: "iterations", type: .number, description: "Number of erosion iterations. Default 50000.", required: false),
                ToolParameter(name: "strength", type: .number, description: "Erosion strength (0–2). Default 1.0.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "sculptTerrain",
            description: "Applies a terrain brush at a specified location.",
            parameters: [
                ToolParameter(name: "brushMode", type: .string, description: "Brush: Raise, Lower, Smooth, Flatten, Slope, Erode, Stamp, Paint"),
                ToolParameter(name: "position", type: .array, description: "Center position as [x, z] in world space."),
                ToolParameter(name: "radius", type: .number, description: "Brush radius. Default 50.", required: false),
                ToolParameter(name: "strength", type: .number, description: "Brush strength (0–1). Default 0.5.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "paintMaterial",
            description: "Paints a material layer onto the terrain at a specified region.",
            parameters: [
                ToolParameter(name: "materialName", type: .string, description: "Name of the material layer (e.g., Rock, Grass, Snow, Sand)"),
                ToolParameter(name: "position", type: .array, description: "Center position as [x, z] in world space."),
                ToolParameter(name: "radius", type: .number, description: "Paint radius. Default 50.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "scatterVegetation",
            description: "Scatters vegetation instances on the terrain using biome rules.",
            parameters: [
                ToolParameter(name: "biomeName", type: .string, description: "Biome preset name or custom biome."),
                ToolParameter(name: "density", type: .number, description: "Vegetation density (0–1). Default 0.5.", required: false),
                ToolParameter(name: "region", type: .array, description: "Region as [x, z, width, depth]. Omit for entire terrain.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "placeObject",
            description: "Places a 3D object in the scene.",
            parameters: [
                ToolParameter(name: "name", type: .string, description: "Object display name."),
                ToolParameter(name: "meshType", type: .string, description: "Mesh type or asset path."),
                ToolParameter(name: "position", type: .array, description: "World position as [x, y, z]."),
                ToolParameter(name: "rotation", type: .array, description: "Euler rotation as [x, y, z] in radians.", required: false),
                ToolParameter(name: "scale", type: .array, description: "Scale as [x, y, z]. Default [1,1,1].", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "moveObject",
            description: "Moves a selected object using spatial-aware direction semantics.",
            parameters: [
                ToolParameter(name: "entityName", type: .string, description: "Name of the entity to move. Use 'selected' for current selection.", required: false),
                ToolParameter(name: "direction", type: .string, description: "Direction: left, right, forward, backward, up, down"),
                ToolParameter(name: "distance", type: .string, description: "Distance hint: 'a bit', 'some', 'a lot', or a numeric value in meters.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "removeObject",
            description: "Removes an object from the scene.",
            parameters: [
                ToolParameter(name: "entityName", type: .string, description: "Name of the entity to remove."),
            ]
        ),
        AgentToolDefinition(
            name: "adjustAtmosphere",
            description: "Adjusts atmosphere, weather, and lighting settings.",
            parameters: [
                ToolParameter(name: "preset", type: .string, description: "Atmosphere preset: sunny, overcast, foggy, stormy, dawn, dusk, night, snowy.", required: false),
                ToolParameter(name: "fogDensity", type: .number, description: "Height fog density (0–1).", required: false),
                ToolParameter(name: "sunDirection", type: .array, description: "Sun direction as [x, y, z].", required: false),
                ToolParameter(name: "sunIntensity", type: .number, description: "Sun light intensity.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "addWaterBody",
            description: "Adds a water body to the scene.",
            parameters: [
                ToolParameter(name: "type", type: .string, description: "Water type: Ocean, Lake, River, Pond"),
                ToolParameter(name: "surfaceHeight", type: .number, description: "Water surface Y coordinate."),
                ToolParameter(name: "extent", type: .array, description: "Size as [width, depth]. Ignored for Ocean.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "generateAsset",
            description: "Generates a 3D asset using AI (text-to-image then image-to-3D).",
            parameters: [
                ToolParameter(name: "prompt", type: .string, description: "Text description of the asset to generate."),
                ToolParameter(name: "style", type: .string, description: "Visual style: realistic, stylized, lowpoly, cartoon.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "composePlan",
            description: "Creates a structured composition plan for a complex scene request.",
            parameters: [
                ToolParameter(name: "description", type: .string, description: "Natural language description of the desired scene."),
            ]
        ),
        AgentToolDefinition(
            name: "optimizeScene",
            description: "Runs automatic performance optimization on the current scene.",
            parameters: [
                ToolParameter(name: "targetFPS", type: .number, description: "Target frame rate. Default 60.", required: false),
                ToolParameter(name: "enableLOD", type: .boolean, description: "Enable automatic LOD generation. Default true.", required: false),
                ToolParameter(name: "enableInstancing", type: .boolean, description: "Merge identical meshes to instanced draws. Default true.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "queryViewport",
            description: "Returns current viewport state including camera, selection, and spatial context.",
            parameters: []
        ),
    ]
}
