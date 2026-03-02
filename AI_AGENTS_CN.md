# Metal Caster — AI Agent 系统

[English](AI_AGENTS.md) | **简体中文**

---

## 概述

Metal Caster 将 AI 视为**一等公民**，而非附属插件。引擎内建了 6 个专职 Agent 和一个中央编排器（Orchestrator），全部直接嵌入编辑器 UI。每个引擎子系统 — ECS、渲染、场景图、着色器、资产 — 都暴露了 Agent 可通过 LLM Function Calling 调用的结构化 API。

理想工作流：**描述你想要的 → Agent 团队构建 → 你在视觉上微调**。

---

## 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                         编辑器 UI                            │
│  ┌────────────────────────┐  ┌────────────────────────────┐ │
│  │     Agent Tab          │  │       Colab Tab            │ │
│  │   (直接与单个 Agent 对话) │  │  (Orchestrator 多 Agent 协作)│ │
│  └──────────┬─────────────┘  └──────────────┬─────────────┘ │
└─────────────┼───────────────────────────────┼───────────────┘
              │                               │
              ▼                               ▼
┌─────────────────────┐     ┌─────────────────────────────────┐
│   MCAgent（1 对 1）   │     │       AgentOrchestrator         │
│   直接工具调用        │     │   分解任务 → 分派 Agent → 汇总结果│
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
          │  (EngineAPIProvider 协议)              │
          │  executeTool(name, arguments) → Result│
          │  takeSnapshot() → EngineSnapshot      │
          └──────────────────┬───────────────────┘
                             ▼
          ┌──────────────────────────────────────┐
          │           引擎子系统                   │
          │  World · SceneGraph · Renderer ·      │
          │  AssetManager · LightingSystem · ...  │
          └──────────────────────────────────────┘
```

### 核心组件

| 组件 | 类型 | 位置 | 职责 |
|------|------|------|------|
| **MCAgent** | `@Observable class` | `MetalCasterAI/Agent/MCAgent.swift` | 封装系统提示词、工具定义和对话状态，处理完整的 LLM 交互循环 |
| **AgentRole** | `enum` | `MetalCasterAI/Agent/AgentRole.swift` | 6 种专业角色：Render、Scene、Shader、Asset、Optimize、Analyze |
| **AgentOrchestrator** | `@Observable class` | `MetalCasterAI/Agent/AgentOrchestrator.swift` | 将复杂请求分解为子任务，按依赖顺序分派给各 Agent |
| **AgentRegistry** | `@Observable class` | `MetalCasterAI/Agent/AgentRegistry.swift` | 生命周期管理 — 注册、查找、重置 Agent |
| **EngineAPIProvider** | `protocol` | `MetalCasterAI/EngineAPI/EngineAPI.swift` | 工具执行接口；由编辑器目标中的 `EditorEngineAPI` 实现 |
| **EngineSnapshot** | `struct` | `MetalCasterAI/EngineAPI/EngineSnapshot.swift` | 引擎完整状态的只读可序列化快照，注入 LLM 上下文 |

---

## 6 个专职 Agent

每个 Agent 专注于特定领域 — 拥有独立的系统提示词、精心策划的工具集，以及对其子系统的深度专业知识。

### 1. Scene Agent — 场景管理

| | |
|---|---|
| **图标** | `cube.transparent` |
| **领域** | 实体生命周期、层级管理、变换操作、USD 导入导出 |
| **工具** | `createEntity`、`deleteEntity`、`duplicateEntity`、`addComponent`、`removeComponent`、`setTransform`、`reparent`、`queryScene`、`queryEntity`、`selectEntity`、`importUSD`、`exportUSD` |

Scene Agent 是使用频率最高的 Agent。它直接管理 ECS World — 创建实体、构建层级、批量放置对象、导入导出 USD 场景。当用户说"创建一个 5×5 的方块网格"时，Scene Agent 会规划所有位置并在一次 LLM 响应中生成全部工具调用。

### 2. Render Agent — 渲染管线

| | |
|---|---|
| **图标** | `paintbrush.pointed` |
| **领域** | 渲染管线配置、光照设置、后处理效果、摄像机参数 |
| **工具** | `setRenderMode`、`configureLighting`、`addLight`、`addPostProcess`、`queryRenderState`、`setCamera`、`captureFrame` |

Render Agent 掌控一切视觉效果。它切换渲染模式（着色/线框/渲染）、配置灯光的完整参数（强度、颜色、范围、锥角、阴影）、设置摄像机，以及管理自定义 MSL 后处理 pass。

### 3. Shader Agent — 着色器专家

| | |
|---|---|
| **图标** | `function` |
| **领域** | MSL 着色器编写、材质创建与修改、着色器调试 |
| **工具** | `createMaterial`、`modifyShader`、`queryMaterial`、`applyPresetMaterial`、`listShaderSnippets` |

Shader Agent 是 Metal Shading Language 专家。它编写顶点和片段着色器、创建材质并应用到实体上。所有生成的着色器代码遵循引擎约定：`vertex_main` / `fragment_main` 入口函数、Uniforms 在 `buffer(1)`、用户参数通过 `// @param` 声明。

### 4. Asset Agent — 资产管理

| | |
|---|---|
| **图标** | `folder` |
| **领域** | 资产管线管理、导入导出、项目配置 |
| **工具** | `listAssets`、`queryProjectConfig` |

Asset Agent 管理项目的资产生态。它对网格、纹理、着色器和场景文件进行分类编目，在导入时验证格式兼容性，并处理项目配置查询。

### 5. Optimize Agent — 性能优化

| | |
|---|---|
| **图标** | `gauge.with.dots.needle.67percent` |
| **领域** | 性能剖析、GPU 利用率分析、Draw Call 优化 |
| **工具** | `profileFrame`、`analyzeDrawCalls`、`suggestOptimizations` |

Optimize Agent 是 Apple Silicon GPU 性能优化专家。它剖析帧性能、按材质分析 Draw Call 效率，并生成可执行的优化建议（附预期收益和潜在风险）。它精通 Metal 最佳实践：合批、LOD、视锥裁剪、纹理内存和带宽优化。

### 6. Analyze Agent — 场景诊断

| | |
|---|---|
| **图标** | `waveform.path.ecg` |
| **领域** | 场景诊断、错误检测、运行时调试 |
| **工具** | `validateScene`、`analyzeHierarchy`、`inspectEntity`、`generateDiagnosticReport` |

Analyze Agent 是引擎的诊断医生。它验证场景完整性（孤立实体、缺失组件、无效父引用）、衡量层级复杂度，并生成全面的诊断报告。问题按严重程度排序（ERROR > WARNING > INFO）。

---

## Agent Orchestrator（Colab 模式）

Orchestrator 是用户与 Agent 团队之间的桥梁。它不直接操作引擎 — 而是将复杂请求**分解**为有序的子任务，并**分派**给相应的专职 Agent。

### 工作流程

```
用户："创建一个赛博朋克风格的城市街道场景"
                    │
                    ▼
         ┌──── Orchestrator ────┐
         │  任务规划：             │
         │  1. Scene Agent →    │
         │     创建建筑实体       │
         │  2. Shader Agent →   │
         │     霓虹材质          │
         │  3. Render Agent →   │
         │     氛围灯光          │
         └──────────┬───────────┘
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
   SceneAgent  ShaderAgent  RenderAgent
   (优先级 1)   (优先级 2)   (优先级 3)
        │           │           │
        ▼           ▼           ▼
   12 个实体    霓虹材质     3 个灯光
        │           │           │
        └───────────┼───────────┘
                    ▼
              汇总报告
              → 用户
```

### Orchestrator 响应协议

Orchestrator 使用带优先级的 JSON 分派格式：

```json
{
  "thinking": "用户想要一个赛博朋克场景。需要 Scene 创建几何体、Shader 制作材质、Render 设置灯光。Scene 必须先执行，因为材质需要附着到实体上。",
  "delegations": [
    { "agent": "Scene",  "task": "在街道布局中创建 12 个建筑实体", "priority": 1 },
    { "agent": "Shader", "task": "为建筑创建霓虹发光材质",        "priority": 2 },
    { "agent": "Render", "task": "添加彩色点光源营造霓虹氛围",     "priority": 3 }
  ],
  "response": "我将创建一条赛博朋克街道，包含 12 座建筑、霓虹材质和氛围灯光。"
}
```

分派按优先级顺序执行（数字越小越先执行）。相同优先级的任务理论上可以并行运行。

---

## 工具系统

### 工具定义模式

Agent 暴露给 LLM 的每个工具都遵循严格的 schema（`AgentToolDefinition`），并被渲染为 LLM 系统提示词的一部分：

```swift
AgentToolDefinition(
    name: "createEntity",
    description: "在场景图中创建新实体。",
    parameters: [
        ToolParameter(name: "name",     type: .string, description: "显示名称", required: true),
        ToolParameter(name: "position", type: .array,  description: "[x, y, z]", required: false),
        ToolParameter(name: "parent",   type: .string, description: "父实体",    required: false),
    ]
)
```

### 工具执行流程

```
LLM 响应（JSON）
    │
    ▼
解析 ToolCallRequest[]
    │
    ▼
EditorEngineAPI.executeTool(name, arguments)
    │
    ▼
@MainActor: 直接变更 World / SceneGraph / Renderer
    │
    ▼
ToolResult { toolName, success, output }
    │
    ▼
反馈给 Agent 用于后续对话
```

所有工具调用在 `@MainActor` 上执行，确保 ECS World 的线程安全变更。每次调用返回一个 `ToolResult`，包含人类可读的输出，被反馈给 Agent 以保持对话连续性。

### 实体解析

工具通过名称或数字 ID 引用实体。`resolveEntity` 函数首先尝试 `UInt64` 解析（按 ID 查找），失败后回退到对所有存活实体进行大小写不敏感的名称匹配。

---

## 引擎状态快照

每次 LLM 调用前，一个 `EngineSnapshot` 捕获引擎的完整状态，作为可序列化文本：

- **实体列表**，包含组件、位置和层级信息
- **场景层级树**，缩进格式
- **渲染状态**（Draw Call 数、灯光数、渲染模式）
- **性能指标**（FPS、帧时间）
- **当前选中实体**

该快照注入系统提示词，使 Agent 始终拥有最新的引擎状态上下文，无需额外查询即可做出明智决策。

---

## 编辑器 UI 集成

Agent 系统通过编辑器 3×2 布局中右下角的 **Agent Discussion** 面板呈现，使用 `MCTabBar` 实现 Tab 切换：

| Tab | 视图 | 功能 |
|-----|------|------|
| **Agent** | `AgentListView` → `AgentChatView` | 浏览全部 6 个 Agent 及实时状态指示灯。选中后进入 1 对 1 专属对话。 |
| **Colab** | `ColabChatView` | 与 Orchestrator 对话。描述复杂目标，观看它规划、分派并协调 Agent 团队。 |

### Agent 状态指示灯

每个 Agent 显示实时状态圆点：

| 状态 | 颜色 | 含义 |
|------|------|------|
| Idle | 绿色 | 就绪，可接受请求 |
| Thinking | 蓝色 | 等待 LLM 响应 |
| Executing | 蓝色 | 工具调用执行中 |
| Error | 红色 | 最近的操作失败 |

---

## AI 服务层

所有 LLM 通信通过 `AIService.shared` 进行，支持三个提供商：

| 提供商 | 模型 | 说明 |
|--------|------|------|
| **OpenAI** | GPT-4o、GPT-4o-mini | 工具调用可靠性最佳 |
| **Anthropic** | Claude 3.5 Sonnet | 推理能力强 |
| **Gemini** | Gemini Pro | Google 生态集成 |

`agentToolChat` 方法处理通用的 Agent 交互循环：消息 + 系统提示词 → 提供商 API → 原始文本响应。每个 Agent 的 `MCAgent.chat()` 方法随后解析 JSON 响应，提取工具调用和面向用户的文本。

---

## 文件结构

```
Engine/Sources/MetalCasterAI/
├── AIService.swift                  # LLM 通信（多提供商）
├── AISettings.swift                 # 提供商/模型/API Key 配置
├── AITypes.swift                    # ChatMessage、AIProvider 等共享类型
├── Agent/
│   ├── MCAgent.swift                # 核心 Agent 类（提示词、工具、对话循环）
│   ├── AgentRole.swift              # 角色枚举 + AgentStatus
│   ├── AgentTool.swift              # 工具 Schema、ToolCallRequest、JSONValue、ToolResult
│   ├── AgentContext.swift           # 单轮上下文包装器
│   ├── AgentRegistry.swift          # Agent 生命周期管理
│   └── AgentOrchestrator.swift      # 多 Agent 任务分解与分派
├── Agents/
│   ├── AgentDefinitions.swift       # 6 个 Agent 的工厂方法
│   ├── SceneAgent.swift             # Scene Agent 提示词 + 工具定义
│   ├── RenderAgent.swift            # Render Agent 提示词 + 工具定义
│   ├── ShaderAgent.swift            # Shader Agent 提示词 + 工具定义
│   ├── AssetAgent.swift             # Asset Agent 提示词 + 工具定义
│   ├── OptimizeAgent.swift          # Optimize Agent 提示词 + 工具定义
│   └── AnalyzeAgent.swift           # Analyze Agent 提示词 + 工具定义
└── EngineAPI/
    ├── EngineAPI.swift              # EngineAPIProvider 协议
    └── EngineSnapshot.swift         # 引擎状态只读快照

Engine/Apps/MetalCasterEditor/Sources/
├── Editor/
│   ├── EditorState.swift            # 持有 agentRegistry、orchestrator、engineAPI
│   └── EditorEngineAPI.swift        # EngineAPIProvider 具体实现（工具分发）
└── Views/
    ├── AgentDiscussionView.swift    # MCTabBar（Agent / Colab 双 Tab）
    ├── AgentListView.swift          # Agent 浏览列表（含状态指示灯）
    ├── AgentChatView.swift          # 1 对 1 Agent 对话界面
    └── ColabChatView.swift          # Orchestrator 对话界面
```

---

## 如何添加新 Agent

1. **定义角色** — 在 `AgentRole` 中添加 case，设置 `displayName`、`icon` 和 `tagline`。

2. **创建提示词文件** — 在 `Engine/Sources/MetalCasterAI/Agents/` 下添加 `NewAgent.swift`，包含 `NewAgentPrompt` 枚举，定义 `systemPrompt` 和 `tools` 数组。

3. **添加工厂方法** — 在 `AgentDefinitions` 中添加：
   ```swift
   public static func newAgent() -> MCAgent {
       MCAgent(role: .newRole, systemPrompt: NewAgentPrompt.systemPrompt, tools: NewAgentPrompt.tools)
   }
   ```

4. **注册** — 在 `AgentRegistry.registerBuiltinAgents()` 中调用 `register(AgentDefinitions.newAgent())`。

5. **实现工具** — 在 `EditorEngineAPI.executeToolOnMain()` 中添加 `case "toolName":` 分支，编写实际的引擎操作逻辑。

新 Agent 将自动出现在 Agent Discussion 面板中，并可被 Orchestrator 进行任务分派。

---

## 设计原则

1. **Agent 通过工具操作，不生成代码** — Agent 不会让用户粘贴代码。所有操作通过工具系统执行，确保类型安全和事务完整性。

2. **快照驱动的上下文** — 每次交互前生成全新的 `EngineSnapshot`，给 Agent 提供准确、实时的场景状态。

3. **语言自适应** — 所有 Agent 被指示使用与用户相同的语言回复。

4. **安全执行** — 工具调用返回带有 `success` 标志的 `ToolResult`。失败操作生成描述性错误消息，不会导致引擎崩溃。

5. **可观测状态** — 所有 Agent 类使用 `@Observable`，使 SwiftUI 视图能在 Agent 状态、对话历史或工具结果变化时响应式更新。
