# Metal Caster

首个 Apple 原生游戏引擎 —— 基于 Metal、SwiftUI 和 ECS，专为 Apple Silicon 打造。

[English](README.md) | **简体中文**

---

## 愿景

Metal Caster 是一个高度精简、观点鲜明的游戏引擎，从零开始为 Apple 平台设计。当 Unity 和 Unreal 试图做所有人的所有事时，Metal Caster 选择了相反的路：更少的选择、更好的默认值、AI 作为主要的开发界面。

把它想象成**游戏引擎中的徕卡** —— 为特定生态精密打造，每个细节都经过深思熟虑。

---

## 设计哲学

### 1. 少即是多

引擎替用户做决定。文件布局、ECS 模式、键盘快捷键和视觉默认值都已预配置且不可自定义。当某件事可以自动决定时，就不会有开关。

> "我们给用户好的设计，而不是让用户自己搭建的工具包。"

### 2. AI 优先的开发方式

AI 不是插件 —— 它是用户构建游戏的主要方式。每个子系统都暴露 AI Agent 可调用的 API。理想的工作流：**描述你想要的 → AI 构建 → 你在视觉上微调**。

所有内部数据结构（ECS World、SceneGraph、Components）都可被 AI 通过结构化上下文内省。MCP（Model Context Protocol）兼容性是外部 AI 工具集成的长期目标。

### 3. Apple 生态，别无他选

目标平台：**iOS、macOS、tvOS、visionOS**。永远不会考虑其他平台。

- 图形：仅 Metal，针对 Apple Silicon 统一内存架构深度优化
- UI：仅 SwiftUI
- 语言：所有用户层代码仅 Swift
- 多设备：Apple 设备间的无感同步与切换是核心目标

### 4. 视觉至上

引擎本身必须有顶级工具的质感。纯黑 UI 配细描边面板、流畅的 60fps 编辑器交互、Apple 硬件上一流的渲染表现。

视觉相关功能要比竞品引擎更聪明、更直接、更具设计感。

### 5. 开放与可观测

Metal Caster 设计为开源友好。所有引擎模块都是干净的 SPM 包，拥有公共 API。性能分析器内建，暴露帧时序、绘制调用、内存使用和 GPU 利用率 —— 开发者和 AI Agent 均可查询。

### 6. USD 原生协作

Universal Scene Description 是标准场景格式。USD 的分层和组合系统支持非破坏性多人编辑。场景文件使用文本格式 USDA，便于 git diff 和版本控制。

---

## 架构

```
MetalCaster/
├── Engine/                           # SPM 包
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MetalCasterCore/          # ECS、数学、引擎循环、事件
│   │   ├── MetalCasterRenderer/      # Metal 抽象、渲染图、着色器
│   │   ├── MetalCasterScene/         # 场景图、USD 导入导出、组件
│   │   ├── MetalCasterAsset/         # 资产管线、纹理压缩、打包
│   │   ├── MetalCasterInput/         # 跨平台输入抽象
│   │   ├── MetalCasterPhysics/       # 物理系统
│   │   ├── MetalCasterAudio/         # AVAudioEngine 封装
│   │   └── MetalCasterAI/            # AI 服务层
│   ├── Apps/
│   │   ├── MetalCasterEditor/        # macOS 编辑器（SwiftUI）
│   │   └── MCRuntime/                # 轻量级游戏运行时
│   └── Tests/
│       └── MetalCasterCoreTests/
│
├── macOSShaderCanvas/                # 独立着色器工作台
├── MetalCaster.xcworkspace           # 在 Xcode 中打开所有内容
└── .cursor/rules/                    # AI 开发准则
```

---

## 引擎模块

| 模块 | 职责 |
|------|------|
| **MetalCasterCore** | 实体-组件-系统、数学工具（simd 封装）、引擎 tick 循环、类型化事件总线 |
| **MetalCasterRenderer** | Metal 设备/队列抽象、渲染图、运行时 MSL 编译、管线缓存、网格池、材质系统 |
| **MetalCasterScene** | 带父子层级的场景图、内置组件（Transform、Camera、Light、Mesh、Material、Name）、USD 导入导出、JSON 场景序列化、相机/灯光/网格渲染系统 |
| **MetalCasterAsset** | 带缓存的资产管理器、MSL→.metallib 预编译、ASTC/BC 纹理压缩、.mcbundle 场景打包 |
| **MetalCasterInput** | 抽象输入动作与设备绑定、visionOS 手势追踪支持 |
| **MetalCasterPhysics** | 物理体/碰撞体组件、基础重力和碰撞系统 |
| **MetalCasterAudio** | 音频源组件、AVAudioEngine 封装与 3D 空间音频 |
| **MetalCasterAI** | 多提供商 AI 服务（OpenAI、Anthropic、Gemini）、场景感知对话 |

---

## 编辑器

Metal Caster 编辑器是一个 macOS 应用，采用 3×2 面板布局：

```
┌──────────────────┬──────────────────┬──────────────────┐
│                  │                  │                  │
│     视口         │     实体         │     检视器       │
│   摄像机 01      │     层级树       │      输入        │
│                  │                  │                  │
├──────────────────┼──────────────────┼──────────────────┤
│                  │                  │                  │
│     视口         │     项目         │     组件         │
│   摄像机 02      │     资产         │     工具箱       │
│                  │                  │                  │
└──────────────────┴──────────────────┴──────────────────┘
  场景预览 | 后处理 | 场景热力图 | 场景图
```

- **双 3D 视口**，独立摄像机控制
- **实体层级**按组件类型分组（Cameras、Materials、Scene、Managers）
- **检视器**为每个组件提供可折叠的编辑面板
- **项目资产**浏览器，分类列表
- **组件工具箱**，点击添加组件到实体
- **AI 聊天**面板，具备场景上下文感知
- **构建与运行**系统，生成可部署的 SPM 项目

### 视觉风格

纯黑背景、1px 描边面板、白色排版、彩色状态指示。隐藏标题栏，内容全出血。所有样式通过集中式 `MCTheme` 设计系统管理。

---

## 快速开始

### 系统要求

- macOS 15+（Sequoia）
- Xcode 16+
- 推荐 Apple Silicon

### 在 Xcode 中打开

```bash
git clone https://github.com/user/MetalCaster.git
cd MetalCaster
open MetalCaster.xcworkspace
```

在 Scheme 选择器中选择 **MetalCasterEditor**，按 ⌘R 运行。

### 命令行

```bash
cd MetalCaster/Engine

# 构建全部
swift build

# 运行编辑器
swift run MetalCasterEditor

# 运行游戏运行时
swift run MCRuntime

# 运行测试
swift test
```

### 可用 Scheme

| Scheme | 说明 |
|--------|------|
| **MetalCasterEditor** | 完整编辑器应用 |
| **MCRuntime** | 轻量级游戏运行时 |
| **macOSShaderCanvas** | 独立着色器工作台 |

---

## Shader Canvas

Metal Caster 包含一个独立的 **Shader Canvas** —— 为技术美术设计的轻量级 Metal 着色器工作台。提供实时 MSL 编辑，基于图层的顶点、片段和后处理着色器，可在 3D 网格上预览。

功能：10 种片段预设、5 种后处理预设、网格切换（球体/立方体/USD）、交互式 9 步教程、AI 辅助着色器开发、工作区持久化。

Shader Canvas 作为独立的 Xcode 项目（`macOSShaderCanvas.xcodeproj`）存在于工作区中。

---

## ECS 架构

Metal Caster 采用严格的实体-组件-系统架构：

- **Entity** — 一个 `UInt64` 标识符，仅此而已
- **Component** — 遵循 `Component` 协议的 Swift 结构体（要求 `Codable` + `Sendable`）
- **World** — 稀疏集存储（`[ComponentType: [Entity: Component]]`）
- **System** — 无状态处理器，通过 `update(world:deltaTime:)` 方法运行
- **Query** — 类型安全的组件查询：`world.query(TransformComponent.self, MeshComponent.self)`

### 内置组件

| 组件 | 字段 |
|------|------|
| `TransformComponent` | 位置、旋转、缩放、父实体、世界矩阵 |
| `CameraComponent` | 投影类型、FOV、近远裁剪面、激活标志 |
| `LightComponent` | 灯光类型、颜色、强度、范围、阴影投射 |
| `MeshComponent` | 网格类型引用 |
| `MaterialComponent` | 着色器源码、参数、数据流配置 |
| `NameComponent` | 显示名称、标签 |

---

## 键盘快捷键

| 快捷键 | 操作 |
|--------|------|
| ⌘N | 新建场景 |
| ⌘O | 打开场景 |
| ⌘S | 保存场景 |
| ⇧⌘S | 场景另存为 |
| ⇧⌘E | 添加空实体 |
| ⇧⌘I | 导入 USD |
| ⌘R | 在编辑器内播放 |
| ⌘B | 构建项目 |
| ⌘L | 切换 AI 聊天 |

---

## 贡献

Metal Caster 设计为开源项目，欢迎贡献：

1. Fork 仓库
2. 创建功能分支
3. 遵循项目设计哲学（见 `.cursor/rules/`）
4. 提交 Pull Request

特别欢迎以下方向的贡献：
- 渲染功能（PBR、全局光照、粒子系统）
- visionOS 和空间计算支持
- USD 管线改进
- AI Agent 能力
- 性能分析工具

---

## 免责声明

> **AI 辅助开发**：本代码库的部分内容由 AI 工具生成或优化。虽然代码已经过审查和测试，但 AI 生成的内容可能包含不准确或次优的模式。请在使用前仔细审查。欢迎贡献和修正。

---

## 许可证

本项目用于教育和研究目的。
