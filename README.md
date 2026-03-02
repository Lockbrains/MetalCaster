# Metal Caster

The first native Apple game engine — built exclusively for Apple Silicon with Metal, SwiftUI, and ECS.

[English](README.md) | [简体中文](README_CN.md)

---

## Vision

Metal Caster is a highly opinionated, minimalist game engine designed from the ground up for Apple platforms. Where Unity and Unreal try to be everything for everyone, Metal Caster takes the opposite approach: fewer choices, better defaults, and AI as the primary development interface.

Think of it as **the Leica of game engines** — precision-engineered for a specific ecosystem, with every detail intentional.

---

## Design Philosophy

### 1. Less Is More

The engine makes decisions for you. File layout, ECS patterns, keyboard shortcuts, and visual defaults are pre-configured and not customizable. When something can be decided automatically, there is no toggle.

> "We give users great design, not a toolkit to build their own."

### 2. AI-First Development

AI is not a plugin — it is the primary way users build games. Every subsystem exposes APIs that AI agents can call. The ideal workflow: **describe what you want → AI builds it → you refine visually**.

All internal data structures (ECS World, SceneGraph, Components) are introspectable by AI through structured context. MCP (Model Context Protocol) compatibility is a long-term goal for external AI tool integration.

See [AI Agent System Documentation](AI_AGENTS.md) for the full agent architecture, tools, and Orchestrator protocol.

### 3. Apple Ecosystem, Exclusively

Target platforms: **iOS, macOS, tvOS, visionOS**. No other platforms will ever be considered.

- Graphics: Metal only, optimized aggressively for Apple Silicon unified memory
- UI: SwiftUI only
- Language: Swift only for all user-facing code
- Multi-device: Seamless handoff and synchronization across Apple devices is a core ambition

### 4. Visual Excellence

The engine must feel like a premium instrument. Pure black UI with thin-stroke panels, smooth 60fps editor interactions, and rendering features that are best-in-class on Apple hardware.

Visual-related functionality should be smarter, more direct, and more design-conscious than competing engines.

### 5. Open & Observable

Metal Caster is designed to be open-source friendly. All engine modules are clean SPM packages with public APIs. Performance analyzers are built-in, exposing frame timing, draw calls, memory usage, and GPU utilization through structured APIs — queryable by both developers and AI agents.

### 6. USD-Native Collaboration

Universal Scene Description is the canonical scene format. USD's layering and composition system enables non-destructive multi-user editing. Scene files use text-based USDA for git-friendly diffing and version control.

---

## Architecture

```
MetalCaster/
├── Engine/                           # SPM Package
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MetalCasterCore/          # ECS, Math, Engine Loop, Events
│   │   ├── MetalCasterRenderer/      # Metal Abstraction, Render Graph, Shaders
│   │   ├── MetalCasterScene/         # Scene Graph, USD Import/Export, Components
│   │   ├── MetalCasterAsset/         # Asset Pipeline, Texture Compression, Bundling
│   │   ├── MetalCasterInput/         # Cross-platform Input Abstraction
│   │   ├── MetalCasterPhysics/       # Physics System
│   │   ├── MetalCasterAudio/         # AVAudioEngine Wrapper
│   │   └── MetalCasterAI/            # AI Service Layer
│   ├── Apps/
│   │   ├── MetalCasterEditor/        # macOS Editor (SwiftUI)
│   │   └── MCRuntime/                # Lightweight Game Runtime
│   └── Tests/
│       └── MetalCasterCoreTests/
│
├── macOSShaderCanvas/                # Standalone Shader Workbench
├── MetalCaster.xcworkspace           # Opens everything in Xcode
└── .cursor/rules/                    # AI development guidelines
```

### Module Dependency Graph

```
MetalCasterCore          (zero platform deps)
    ├── MetalCasterRenderer  (Metal/MetalKit)
    │       ├── MetalCasterScene     (ModelIO, Components, Systems)
    │       │       └── MetalCasterPhysics
    │       └── MetalCasterAsset     (Pipeline, Bundling)
    ├── MetalCasterInput     (GameController, ARKit)
    ├── MetalCasterAudio     (AVAudioEngine)
    └── MetalCasterAI        (Foundation only)
```

---

## Engine Modules

| Module | Responsibility |
|--------|---------------|
| **MetalCasterCore** | Entity-Component-System, math utilities (simd wrappers), engine tick loop, typed event bus |
| **MetalCasterRenderer** | Metal device/queue abstraction, render graph, runtime MSL compilation, pipeline caching, mesh pool, material system |
| **MetalCasterScene** | Scene graph with parent-child hierarchy, built-in components (Transform, Camera, Light, Mesh, Material, Name), USD import/export, JSON scene serialization, camera/lighting/mesh render systems |
| **MetalCasterAsset** | Asset manager with caching, MSL→.metallib precompilation, ASTC/BC texture compression, .mcbundle scene packaging |
| **MetalCasterInput** | Abstract input actions with device bindings, visionOS hand tracking support |
| **MetalCasterPhysics** | Physics body/collider components, basic gravity and collision system |
| **MetalCasterAudio** | Audio source component, AVAudioEngine wrapper with 3D spatial audio |
| **MetalCasterAI** | Multi-provider AI service (OpenAI, Anthropic, Gemini), 6 specialist agents with tool calling, Orchestrator for multi-agent coordination |

---

## Editor

The Metal Caster Editor is a macOS application with a 3×2 panel layout:

```
┌──────────────────┬──────────────────┬──────────────────┐
│                  │                  │                  │
│    Viewport      │     Entity       │    Inspector     │
│   Camera 01      │    Hierarchy     │      Input       │
│                  │                  │                  │
├──────────────────┼──────────────────┼──────────────────┤
│                  │                  │                  │
│    Viewport      │     Project      │     Agent        │
│   Camera 02      │     Assets       │   Discussion     │
│                  │                  │                  │
└──────────────────┴──────────────────┴──────────────────┘
```

- **Dual 3D viewports** with independent camera controls
- **Entity Hierarchy** grouped by component type (Cameras, Materials, Scene, Managers)
- **Inspector** with collapsible sections for every component
- **Project Assets** browser with categorized asset listing
- **Agent Discussion** panel with dual-tab interface — chat directly with specialist agents or use the Orchestrator to coordinate multi-agent workflows
- **AI Chat** modal with scene-aware context
- **Build & Run** system generating deployable SPM projects

### Visual Style

Pure black background, 1px stroke panels, white typography, colored status indicators. Hidden title bar with full-bleed content. All styling through the centralized `MCTheme` design system.

---

## Getting Started

### Requirements

- macOS 15+ (Sequoia)
- Xcode 16+
- Apple Silicon recommended

### Open in Xcode

```bash
git clone https://github.com/user/MetalCaster.git
cd MetalCaster
open MetalCaster.xcworkspace
```

Select **MetalCasterEditor** from the scheme picker and press ⌘R.

### Command Line

```bash
cd MetalCaster/Engine

# Build everything
swift build

# Run the editor
swift run MetalCasterEditor

# Run the game runtime
swift run MCRuntime

# Run tests
swift test
```

### Available Schemes

| Scheme | Description |
|--------|-------------|
| **MetalCasterEditor** | Full editor application |
| **MCRuntime** | Lightweight game runtime |
| **macOSShaderCanvas** | Standalone shader workbench |

---

## Shader Canvas

Metal Caster includes a standalone **Shader Canvas** — a lightweight Metal shader workbench for Technical Artists. It provides real-time MSL editing with layer-based vertex, fragment, and post-processing shaders on 3D meshes.

Features: 10 fragment presets, 5 post-processing presets, mesh switching (sphere/cube/USD), interactive 9-step tutorial, AI-powered shader assistance, and workspace persistence.

The Shader Canvas exists as an independent Xcode project (`macOSShaderCanvas.xcodeproj`) within the workspace.

---

## ECS Architecture

Metal Caster uses a strict Entity-Component-System architecture:

- **Entity** — a `UInt64` identifier, nothing more
- **Component** — Swift structs conforming to `Component` protocol (requires `Codable` + `Sendable`)
- **World** — sparse-set storage (`[ComponentType: [Entity: Component]]`)
- **System** — stateless processors with `update(world:deltaTime:)` method
- **Query** — type-safe component queries: `world.query(TransformComponent.self, MeshComponent.self)`

### Built-in Components

| Component | Fields |
|-----------|--------|
| `TransformComponent` | position, rotation, scale, parent entity, world matrix |
| `CameraComponent` | projection type, FOV, near/far planes, active flag |
| `LightComponent` | light type, color, intensity, range, shadow casting |
| `MeshComponent` | mesh type reference |
| `MaterialComponent` | shader sources, parameters, data flow config |
| `NameComponent` | display name, tags |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New Scene |
| ⌘O | Open Scene |
| ⌘S | Save Scene |
| ⇧⌘S | Save Scene As |
| ⇧⌘E | Add Empty Entity |
| ⇧⌘I | Import USD |
| ⌘R | Play in Editor |
| ⌘B | Build Project |
| ⌘L | Toggle AI Chat |

---

## Contributing

Metal Caster is designed to be open-source. Contributions are welcome:

1. Fork the repository
2. Create a feature branch
3. Follow the project's design philosophy (see `.cursor/rules/`)
4. Submit a pull request

Areas where help is especially valuable:
- Rendering features (PBR, global illumination, particle systems)
- visionOS and spatial computing support
- USD pipeline improvements
- AI agent capabilities
- Performance profiling tools

---

## Disclaimer

> **AI-Assisted Development**: Parts of this codebase were generated or refined with AI tools. While the code has been reviewed and tested, AI-generated content may contain inaccuracies or suboptimal patterns. Please review carefully. Contributions and corrections are welcome.

---

## License

This project is for educational and research purposes.
