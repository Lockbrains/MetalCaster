# Metal Caster — AI Agent System

[English](AI_AGENTS.md) | [简体中文](AI_AGENTS_CN.md)

---

## Overview

Metal Caster treats AI as a **first-class citizen**, not a sidebar feature. The engine ships with a team of 6 specialist agents and a central Orchestrator, all embedded directly into the editor UI. Every engine subsystem — ECS, rendering, scene graph, shaders, assets — exposes structured APIs that agents can call through LLM function calling.

The ideal workflow: **describe what you want → agents build it → you refine visually**.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Editor UI                            │
│  ┌────────────────────────┐  ┌────────────────────────────┐ │
│  │     Agent Tab          │  │       Colab Tab            │ │
│  │  (Direct Agent Chat)   │  │  (Orchestrator Multi-Agent)│ │
│  └──────────┬─────────────┘  └──────────────┬─────────────┘ │
└─────────────┼───────────────────────────────┼───────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────┐     ┌─────────────────────────────────┐
│    MCAgent (1:1)    │     │       AgentOrchestrator         │
│  Direct tool calls  │     │  Decomposes → Delegates → Merges│
└──────────┬──────────┘     └──────────────┬──────────────────┘
           │                               │
           │         ┌─────────────────────┼──────────────────┐
           │         ▼                     ▼                  ▼
           │  ┌────────────┐  ┌────────────────┐  ┌────────────┐
           │  │ SceneAgent │  │  ShaderAgent   │  │ RenderAgent│
           │  └─────┬──────┘  └──────┬─────────┘  └─────┬──────┘
           │        │                │                   │
           └────────┼────────────────┼───────────────────┘
                    ▼                ▼
          ┌──────────────────────────────────────┐
          │       EditorEngineAPI                 │
          │  (EngineAPIProvider protocol)         │
          │  executeTool(name, arguments) → Result│
          │  takeSnapshot() → EngineSnapshot      │
          └──────────────────┬───────────────────┘
                             ▼
          ┌──────────────────────────────────────┐
          │        Engine Subsystems              │
          │  World · SceneGraph · Renderer ·      │
          │  AssetManager · LightingSystem · ...  │
          └──────────────────────────────────────┘
```

### Key Components

| Component | Type | Location | Role |
|-----------|------|----------|------|
| **MCAgent** | `@Observable class` | `MetalCasterAI/Agent/MCAgent.swift` | Wraps a system prompt, tool definitions, and conversation state. Handles full LLM round-trip. |
| **AgentRole** | `enum` | `MetalCasterAI/Agent/AgentRole.swift` | 6 specializations: Render, Scene, Shader, Asset, Optimize, Analyze |
| **AgentOrchestrator** | `@Observable class` | `MetalCasterAI/Agent/AgentOrchestrator.swift` | Decomposes complex requests into sub-tasks, delegates to agents in dependency order |
| **AgentRegistry** | `@Observable class` | `MetalCasterAI/Agent/AgentRegistry.swift` | Lifecycle management — registers, looks up, and resets agents |
| **EngineAPIProvider** | `protocol` | `MetalCasterAI/EngineAPI/EngineAPI.swift` | Tool execution interface; implemented by `EditorEngineAPI` in the editor target |
| **EngineSnapshot** | `struct` | `MetalCasterAI/EngineAPI/EngineSnapshot.swift` | Read-only serializable snapshot of the entire engine state for LLM context |

---

## The 6 Specialist Agents

Each agent is domain-specific — it has its own system prompt, a curated set of tools, and deep knowledge of its subsystem.

### 1. Scene Agent

| | |
|---|---|
| **Icon** | `cube.transparent` |
| **Domain** | Entity lifecycle, hierarchy, transforms, USD I/O |
| **Tools** | `createEntity`, `deleteEntity`, `duplicateEntity`, `addComponent`, `removeComponent`, `setTransform`, `reparent`, `queryScene`, `queryEntity`, `selectEntity`, `importUSD`, `exportUSD` |

The Scene Agent is the most frequently used agent. It manages the ECS World directly — creating entities, building hierarchies, batch-placing objects, and importing/exporting USD scenes. When a user says "create a 5×5 grid of cubes," the Scene Agent plans the positions and generates all the tool calls in a single LLM response.

### 2. Render Agent

| | |
|---|---|
| **Icon** | `paintbrush.pointed` |
| **Domain** | Rendering pipeline, lighting, post-processing, cameras |
| **Tools** | `setRenderMode`, `configureLighting`, `addLight`, `addPostProcess`, `queryRenderState`, `setCamera`, `captureFrame` |

The Render Agent controls everything visual. It switches render modes (shading/wireframe/rendered), configures lights with full parameter control (intensity, color, range, cone angles, shadows), sets up cameras, and manages post-processing passes with custom MSL shader code.

### 3. Shader Agent

| | |
|---|---|
| **Icon** | `function` |
| **Domain** | MSL authoring, materials, shader debugging |
| **Tools** | `createMaterial`, `modifyShader`, `queryMaterial`, `applyPresetMaterial`, `listShaderSnippets` |

The Shader Agent is a Metal Shading Language expert. It writes vertex and fragment shaders, creates materials, and applies them to entities. All generated shader code follows the engine's conventions: `vertex_main` / `fragment_main` entry points, uniforms at `buffer(1)`, and `// @param` declarations for user-tunable parameters.

### 4. Asset Agent

| | |
|---|---|
| **Icon** | `folder` |
| **Domain** | Asset pipeline, import/export, project management |
| **Tools** | `listAssets`, `queryProjectConfig` |

The Asset Agent manages the project's asset ecosystem. It catalogs meshes, textures, shaders, and scene files, validates format compatibility during import, and handles project configuration queries.

### 5. Optimize Agent

| | |
|---|---|
| **Icon** | `gauge.with.dots.needle.67percent` |
| **Domain** | Performance profiling, GPU analysis, draw call optimization |
| **Tools** | `profileFrame`, `analyzeDrawCalls`, `suggestOptimizations` |

The Optimize Agent is a performance specialist for Apple Silicon GPUs. It profiles frames, analyzes draw call efficiency by material, and generates actionable optimization suggestions with expected benefits and risks. It understands Metal best practices: batching, LOD, frustum culling, texture memory, and bandwidth.

### 6. Analyze Agent

| | |
|---|---|
| **Icon** | `waveform.path.ecg` |
| **Domain** | Scene diagnostics, error detection, runtime debugging |
| **Tools** | `validateScene`, `analyzeHierarchy`, `inspectEntity`, `generateDiagnosticReport` |

The Analyze Agent is the engine's diagnostician. It validates scene integrity (orphaned entities, missing components, dead parent references), measures hierarchy complexity, and generates comprehensive diagnostic reports. Issues are sorted by severity (ERROR > WARNING > INFO).

---

## Agent Orchestrator (Colab)

The Orchestrator is the bridge between the user and the agent team. It does not directly manipulate the engine — instead, it **decomposes** complex requests into ordered sub-tasks and **delegates** each to the appropriate specialist agent.

### How It Works

```
User: "Create a cyberpunk street scene with neon lighting"
                    │
                    ▼
         ┌──── Orchestrator ────┐
         │  Plan:               │
         │  1. Scene Agent →    │
         │     create buildings │
         │  2. Shader Agent →   │
         │     neon materials   │
         │  3. Render Agent →   │
         │     atmosphere lights│
         └──────────┬───────────┘
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
   SceneAgent  ShaderAgent  RenderAgent
   (priority 1) (priority 2) (priority 3)
        │           │           │
        ▼           ▼           ▼
   12 entities   neon mats   3 lights
        │           │           │
        └───────────┼───────────┘
                    ▼
            Merged Summary
            → User
```

### Orchestrator Protocol

The Orchestrator uses a JSON response format with prioritized delegations:

```json
{
  "thinking": "The user wants a cyberpunk scene. I need Scene for geometry, Shader for materials, Render for lighting. Scene must go first since materials need entities to attach to.",
  "delegations": [
    { "agent": "Scene",  "task": "Create 12 building entities in a street layout", "priority": 1 },
    { "agent": "Shader", "task": "Create neon-glow materials for the buildings",   "priority": 2 },
    { "agent": "Render", "task": "Add colored point lights for neon atmosphere",    "priority": 3 }
  ],
  "response": "I'll create a cyberpunk street with 12 buildings, neon materials, and atmospheric lighting."
}
```

Delegations are executed sequentially by priority (lower = first). Same-priority tasks can theoretically run in parallel.

---

## Tool System

### Tool Definition Schema

Every tool exposed to agents follows a strict schema (`AgentToolDefinition`) that is rendered into the LLM's system prompt:

```swift
AgentToolDefinition(
    name: "createEntity",
    description: "Creates a new entity in the scene graph.",
    parameters: [
        ToolParameter(name: "name",     type: .string, description: "Display name", required: true),
        ToolParameter(name: "position", type: .array,  description: "[x, y, z]",    required: false),
        ToolParameter(name: "parent",   type: .string, description: "Parent entity", required: false),
    ]
)
```

### Tool Execution Flow

```
LLM Response (JSON)
    │
    ▼
Parse ToolCallRequest[]
    │
    ▼
EditorEngineAPI.executeTool(name, arguments)
    │
    ▼
@MainActor: Direct mutation of World / SceneGraph / Renderer
    │
    ▼
ToolResult { toolName, success, output }
    │
    ▼
Fed back to agent for follow-up response
```

All tool calls execute on `@MainActor` to ensure thread-safe mutation of the ECS World. Each call returns a `ToolResult` with human-readable output that gets fed back to the agent for conversational continuity.

### Entity Resolution

Tools reference entities by name or numeric ID. The `resolveEntity` function first attempts `UInt64` parsing (for IDs), then falls back to case-insensitive name matching across all live entities.

---

## Engine Snapshot

Before each LLM call, an `EngineSnapshot` captures the full engine state as serializable text:

- **Entity list** with components, positions, and hierarchy
- **Scene hierarchy** as an indented tree
- **Render state** (draw call count, light count, render mode)
- **Performance metrics** (FPS, frame time)
- **Selected entity** information

This snapshot is injected into the system prompt so the agent always has up-to-date context about the engine state, enabling informed decisions without additional query calls.

---

## Editor UI Integration

The agent system is surfaced through the **Agent Discussion** panel in the editor's 3×2 layout (bottom-right position). It uses `MCTabBar` for tab switching:

| Tab | View | Function |
|-----|------|----------|
| **Agent** | `AgentListView` → `AgentChatView` | Browse all 6 agents with live status indicators. Select one to enter a direct 1:1 chat session. |
| **Colab** | `ColabChatView` | Chat with the Orchestrator. Describe complex goals and watch as it plans, delegates, and coordinates agents. |

### Agent Status Indicators

Each agent displays a real-time status dot:

| Status | Color | Meaning |
|--------|-------|---------|
| Idle | Green | Ready to accept requests |
| Thinking | Blue | Waiting for LLM response |
| Executing | Blue | Tool calls in progress |
| Error | Red | Last operation failed |

---

## AI Service Layer

All LLM communication flows through `AIService.shared`, which supports three providers:

| Provider | Model | Notes |
|----------|-------|-------|
| **OpenAI** | GPT-4o, GPT-4o-mini | Best tool-calling reliability |
| **Anthropic** | Claude 3.5 Sonnet | Strong reasoning |
| **Gemini** | Gemini Pro | Google integration |

The `agentToolChat` method handles the generic agent round-trip: messages + system prompt → provider API → raw text response. Each agent's `MCAgent.chat()` method then parses the JSON response to extract tool calls and user-facing text.

---

## File Structure

```
Engine/Sources/MetalCasterAI/
├── AIService.swift                  # LLM communication (multi-provider)
├── AISettings.swift                 # Provider/model/API key configuration
├── AITypes.swift                    # ChatMessage, AIProvider, shared types
├── Agent/
│   ├── MCAgent.swift                # Core agent class (prompt, tools, chat loop)
│   ├── AgentRole.swift              # Role enum + AgentStatus
│   ├── AgentTool.swift              # Tool schema, ToolCallRequest, JSONValue, ToolResult
│   ├── AgentContext.swift           # Per-turn context wrapper
│   ├── AgentRegistry.swift          # Agent lifecycle management
│   └── AgentOrchestrator.swift      # Multi-agent task decomposition and delegation
├── Agents/
│   ├── AgentDefinitions.swift       # Factory methods for all 6 agents
│   ├── SceneAgent.swift             # Scene Agent prompt + tools
│   ├── RenderAgent.swift            # Render Agent prompt + tools
│   ├── ShaderAgent.swift            # Shader Agent prompt + tools
│   ├── AssetAgent.swift             # Asset Agent prompt + tools
│   ├── OptimizeAgent.swift          # Optimize Agent prompt + tools
│   └── AnalyzeAgent.swift           # Analyze Agent prompt + tools
└── EngineAPI/
    ├── EngineAPI.swift              # EngineAPIProvider protocol
    └── EngineSnapshot.swift         # Read-only engine state snapshot

Engine/Apps/MetalCasterEditor/Sources/
├── Editor/
│   ├── EditorState.swift            # Hosts agentRegistry, orchestrator, engineAPI
│   └── EditorEngineAPI.swift        # Concrete EngineAPIProvider (tool dispatch)
└── Views/
    ├── AgentDiscussionView.swift    # MCTabBar (Agent / Colab)
    ├── AgentListView.swift          # Agent browser with status
    ├── AgentChatView.swift          # 1:1 agent chat interface
    └── ColabChatView.swift          # Orchestrator chat interface
```

---

## Adding a New Agent

1. **Define the role** — Add a case to `AgentRole` with `displayName`, `icon`, and `tagline`.

2. **Create the prompt file** — Add `Engine/Sources/MetalCasterAI/Agents/NewAgent.swift` with a `NewAgentPrompt` enum containing `systemPrompt` and `tools` arrays.

3. **Add the factory** — Add a static method in `AgentDefinitions`:
   ```swift
   public static func newAgent() -> MCAgent {
       MCAgent(role: .newRole, systemPrompt: NewAgentPrompt.systemPrompt, tools: NewAgentPrompt.tools)
   }
   ```

4. **Register** — Call `register(AgentDefinitions.newAgent())` in `AgentRegistry.registerBuiltinAgents()`.

5. **Implement tools** — Add `case "toolName":` entries in `EditorEngineAPI.executeToolOnMain()` with the actual engine mutations.

The agent will automatically appear in the Agent Discussion panel and be available to the Orchestrator for delegation.

---

## Design Principles

1. **Agents operate through tools, not code generation** — Agents never ask users to paste code. All actions flow through the tool system to ensure type safety and transactional integrity.

2. **Snapshot-driven context** — Every interaction starts with a fresh `EngineSnapshot`, giving the agent accurate, up-to-date knowledge of the scene state.

3. **Language-agnostic responses** — All agents are instructed to respond in the same language the user writes in.

4. **Fail-safe execution** — Tool calls return `ToolResult` with explicit `success` flags. Failed operations produce descriptive error messages without crashing the engine.

5. **Observable state** — All agent classes use `@Observable`, enabling SwiftUI views to reactively update as agent status, conversation history, or tool results change.
