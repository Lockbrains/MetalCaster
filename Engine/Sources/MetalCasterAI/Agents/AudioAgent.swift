import Foundation

/// System prompt and tool definitions for the Audio Agent.
/// Manages audio sources, spatial audio configuration, bus mixing, and sound design.
public enum AudioAgentPrompt {

    public static let systemPrompt = """
    You are the Audio Agent for the MetalCaster game engine.

    YOUR ROLE:
    You manage the audio landscape of the scene. You create and configure audio sources
    on entities, set up spatial 3D audio, manage audio bus volumes, and help users design
    the sonic experience of their project.

    CAPABILITIES:
    - List all audio assets available in the project
    - Create audio sources on entities with full parameter control
    - Configure audio bus volumes (master, music, sfx, voice, ambient)
    - Set up 3D spatial audio parameters (rolloff, distance attenuation)
    - Query the current audio engine state (active sources, bus levels, listener position)

    EXPERTISE:
    - 3D spatial audio design and attenuation models
    - Audio bus architecture and mixing
    - Sound design principles for interactive media
    - AVAudioEngine and Apple spatial audio capabilities

    WORKFLOW:
    1. Query the audio state to understand what is currently playing.
    2. Determine what audio changes achieve the user's goal.
    3. Execute changes through tool calls.
    4. Explain the audio design choices.

    RULES:
    - Audio file references must match assets available in the project.
    - Volume values are normalized 0.0-1.0 unless otherwise specified.
    - Distance values for spatial audio are in scene units (meters).
    - Respond in the SAME LANGUAGE as the user.
    """

    public static let tools: [AgentToolDefinition] = [
        AgentToolDefinition(
            name: "listAudioAssets",
            description: "Lists all audio assets (wav, mp3, m4a, caf, aiff) available in the project.",
            parameters: []
        ),
        AgentToolDefinition(
            name: "createAudioSource",
            description: "Adds an AudioSourceComponent to an entity, configuring it for playback.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the target entity"),
                ToolParameter(name: "audioFile", type: .string, description: "Name of the audio asset to play"),
                ToolParameter(name: "volume", type: .number, description: "Playback volume (0.0-1.0)", required: false),
                ToolParameter(name: "pitch", type: .number, description: "Pitch multiplier (0.5-2.0)", required: false),
                ToolParameter(name: "isLooping", type: .boolean, description: "Whether playback loops", required: false),
                ToolParameter(name: "is3D", type: .boolean, description: "Enable 3D spatialization", required: false),
                ToolParameter(name: "bus", type: .string, description: "Audio bus to route to",
                              required: false,
                              enumValues: ["master", "music", "sfx", "voice", "ambient"]),
                ToolParameter(name: "maxDistance", type: .number, description: "Maximum audible distance for 3D audio", required: false),
                ToolParameter(name: "referenceDistance", type: .number, description: "Distance at which volume is at full level", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "configureAudioBus",
            description: "Sets the volume level for an audio bus.",
            parameters: [
                ToolParameter(name: "bus", type: .string, description: "Bus to configure",
                              enumValues: ["master", "music", "sfx", "voice", "ambient"]),
                ToolParameter(name: "volume", type: .number, description: "Volume level (0.0-1.0)"),
            ]
        ),
        AgentToolDefinition(
            name: "setSpatialAudio",
            description: "Configures the 3D spatial audio parameters on an entity's AudioSourceComponent.",
            parameters: [
                ToolParameter(name: "entityRef", type: .string, description: "Name or id of the entity with an AudioSourceComponent"),
                ToolParameter(name: "maxDistance", type: .number, description: "Maximum audible distance", required: false),
                ToolParameter(name: "referenceDistance", type: .number, description: "Reference distance for attenuation", required: false),
                ToolParameter(name: "is3D", type: .boolean, description: "Toggle 3D spatialization", required: false),
            ]
        ),
        AgentToolDefinition(
            name: "queryAudioState",
            description: "Returns the current audio engine state: active source count, bus volumes, loaded audio names.",
            parameters: []
        ),
    ]
}
