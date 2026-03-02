import Foundation

/// System prompt and tool definitions for the Scene Agent.
/// Responsible for entity lifecycle, hierarchy management, transforms, and USD I/O.
public enum SceneAgentPrompt {

    public static let systemPrompt = """
    You are the Scene Management Agent for the MetalCaster game engine.

    YOUR ROLE:
    You manage the Entity-Component-System (ECS) world: creating, deleting, and modifying entities;
    managing the scene hierarchy; setting transforms; and handling USD import/export.

    CAPABILITIES:
    - Create entities with arbitrary names, positions, and parent relationships
    - Add or remove components (Transform, Camera, Light, Mesh, Material, Physics, Audio, Name)
    - Manipulate the scene graph hierarchy (reparenting, recursive deletion)
    - Batch-create complex layouts (walls, grids, procedural arrangements)
    - Import/export scenes in USD format
    - Query scene state to make informed decisions

    WORKFLOW:
    1. When the user describes a scene requirement, first call queryScene() to understand the current state.
    2. Plan the entity structure (names, positions, hierarchy, components).
    3. Execute tool calls in logical order: create parent entities first, then children, then add components.
    4. For batch operations (e.g. "create a 5x5 grid of cubes"), generate all tool calls in a single response.

    RULES:
    - Entity names must be descriptive and unique when possible.
    - Positions use right-handed Y-up coordinate system: +X right, +Y up, +Z toward camera.
    - Rotations are Euler angles in radians (YXZ order).
    - Scale defaults to (1, 1, 1) if not specified.
    - When adding a Mesh component, also add a Material component unless the user explicitly says otherwise.
    - Always confirm destructive operations (delete, clear) in your response text before executing.
    - Respond in the SAME LANGUAGE as the user.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "createEntity",
            description: "Creates a new entity in the scene graph with a name and optional position/parent.",
            parameters: [
                ToolParameter(name: "name", type: .string, description: "Display name for the entity"),
                ToolParameter(name: "position", type: .array, description: "World position as [x, y, z]. Defaults to [0,0,0].", required: false),
                ToolParameter(name: "parent", type: .string, description: "Name of the parent entity. Omit for root-level.", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "deleteEntity",
            description: "Deletes an entity and all its children from the scene.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to delete"),
            ]
        ),
        AgentToolDefinition(
            name: "duplicateEntity",
            description: "Duplicates an entity (and its components). The copy is offset by +1 on the X axis.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to duplicate"),
            ]
        ),
        AgentToolDefinition(
            name: "addComponent",
            description: "Adds a component to an existing entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "componentType", type: .string, description: "Component type to add",
                              enumValues: ["Camera", "Light", "Mesh", "Material", "PhysicsBody", "Collider", "AudioSource"]),
                ToolParameter(name: "params", type: .object, description: "Component-specific parameters (e.g. {\"meshType\": \"cube\"} for Mesh, {\"type\": \"point\", \"intensity\": 2.0} for Light)", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "removeComponent",
            description: "Removes a component from an entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "componentType", type: .string, description: "Component type to remove",
                              enumValues: ["Camera", "Light", "Mesh", "Material", "PhysicsBody", "Collider", "AudioSource"]),
            ]
        ),
        AgentToolDefinition(
            name: "setTransform",
            description: "Sets the transform (position, rotation, scale) of an entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "position", type: .array, description: "Position as [x, y, z]", required: false),
                ToolParameter(name: "rotation", type: .array, description: "Euler rotation in radians as [x, y, z]", required: false),
                ToolParameter(name: "scale", type: .array, description: "Scale as [x, y, z]", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "reparent",
            description: "Changes the parent of an entity in the scene hierarchy.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to move"),
                ToolParameter(name: "newParent", type: .string, description: "Name or id of the new parent. Use \"root\" for top-level."),
            ]
        ),
        AgentToolDefinition(
            name: "queryScene",
            description: "Returns the full scene hierarchy with all entities, their components, and transforms.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "queryEntity",
            description: "Returns detailed information about a specific entity including all its components and their values.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to inspect"),
            ]
        ),
        AgentToolDefinition(
            name: "selectEntity",
            description: "Sets the editor selection to the specified entity.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity to select"),
            ]
        ),
        AgentToolDefinition(
            name: "importUSD",
            description: "Imports a USD/USDZ asset file into the current scene.",
            parameters: [
                ToolParameter(name: "path", type: .string, description: "File path or URL of the USD asset"),
            ]
        ),
        AgentToolDefinition(
            name: "exportUSD",
            description: "Exports the current scene to USDA format.",
            parameters: [
                ToolParameter(name: "path", type: .string, description: "Output file path for the USDA file"),
            ]
        ),
    ]
}
