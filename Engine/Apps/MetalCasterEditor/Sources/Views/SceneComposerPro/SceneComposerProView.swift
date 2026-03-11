import SwiftUI
import MetalCasterScene
import MetalCasterRenderer
#if os(macOS)
import AppKit
#endif

struct SceneComposerProView: View {
    @Environment(EditorState.self) private var editorState

    // MARK: - Document State

    @State private var documentName: String = "Untitled"
    @State private var terrain: TerrainComponent? = TerrainComponent(
        heightmapResolution: 512,
        worldSize: SIMD2<Float>(200, 200),
        maxHeight: 30,
        lodLevels: 4
    )

    // MARK: - Camera

    @State private var cameraYaw: Float = 0.6
    @State private var cameraPitch: Float = 0.85
    @State private var cameraDistance: Float = 280

    // MARK: - Terrain Params (synced to renderer)

    @State private var worldSize: SIMD2<Float> = SIMD2<Float>(200, 200)
    @State private var maxHeight: Float = 30
    @State private var noiseFrequency: Float = 1.0
    @State private var noiseOctaves: Int = 4
    @State private var noiseSeed: UInt32 = 0
    @State private var needsRegeneration: Bool = true
    @State private var erosionEnabled: Bool = false
    @State private var erosionStrength: Float = 1.0
    @State private var needsErosion: Bool = false

    // MARK: - Tools

    @State private var selectedTool: ComposerToolMode = .terrain
    @State private var brushSettings = ComposerBrushSettings()

    // MARK: - Water

    @State private var waterLevel: Float = 5.0
    @State private var showWater: Bool = false
    @State private var waterDeepColor: SIMD3<Float> = SIMD3<Float>(0.02, 0.08, 0.18)
    @State private var waterShallowColor: SIMD3<Float> = SIMD3<Float>(0.05, 0.25, 0.35)
    @State private var waterOpacity: Float = 0.75
    @State private var waterWaveScale: Float = 1.0
    @State private var waterWaveSpeed: Float = 1.0

    // MARK: - Sky

    @State private var sunAltitude: Float = 0.4
    @State private var sunAzimuth: Float = 0.8
    @State private var fogDensity: Float = 0.002

    // MARK: - Layers

    @State private var layers: [ComposerLayer] = [
        ComposerLayer(name: "Terrain", kind: .terrain),
        ComposerLayer(name: "Vegetation", kind: .vegetation),
        ComposerLayer(name: "Water", kind: .water),
        ComposerLayer(name: "Atmosphere", kind: .atmosphere),
        ComposerLayer(name: "Objects", kind: .objects),
    ]
    @State private var selectedLayerID: UUID?

    // MARK: - AI Chat

    @State private var chatMessages: [ComposerChatMessage] = []
    @State private var chatInput: String = ""
    @State private var currentPlan: CompositionPlan?

    // MARK: - Selection

    @State private var selectedWorldPosition: SIMD3<Float>? = nil

    // MARK: - Inline Prompt

    @State private var showInlinePrompt: Bool = false
    @State private var inlinePromptAnchor: CGPoint = .zero
    @State private var inlinePromptContext: InlinePromptContext = .sceneGlobal
    @State private var spatialMode: SpatialCoordinateMode = .screenSpace

    // MARK: - File State

    @State private var currentFileURL: URL? = nil
    @State private var showSavePanel: Bool = false
    @State private var showOpenPanel: Bool = false

    // MARK: - Undo

    @State private var undoStack: [TerrainComponent?] = []
    @State private var redoStack: [TerrainComponent?] = []

    var body: some View {
        VStack(spacing: 0) {
            commandBar
            Divider().background(MCTheme.panelBorder)
            mainContent
            Divider().background(MCTheme.panelBorder)
            bottomBar
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
        .onChange(of: terrain) { _, newTerrain in
            syncTerrainToRenderer(newTerrain)
        }
    }

    // MARK: - Command Bar

    private var commandBar: some View {
        HStack(spacing: 12) {
            Text("Scene")
                .font(MCTheme.fontPanelLabel)
                .foregroundStyle(MCTheme.textSecondary)
            Text("Composer Pro")
                .font(MCTheme.fontPanelLabelBold)
                .foregroundStyle(MCTheme.textPrimary)

            Spacer()

            HStack(spacing: 8) {
                Button("New") { documentName = "Untitled"; terrain = TerrainComponent(); needsRegeneration = true }
                Button("Open") { openDocument() }
                Button("Save") { saveDocument() }
            }
            .font(MCTheme.fontCaption)
            .buttonStyle(.plain)
            .foregroundStyle(MCTheme.textSecondary)

            Text(documentName)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)

            Spacer()

            Button("Export USDA") {
                exportToUSDA()
            }
            .font(MCTheme.fontCaption)
            .buttonStyle(.plain)
            .foregroundStyle(MCTheme.textSecondary)

            Button("Optimize") {
                optimizeScene()
            }
            .font(MCTheme.fontCaption)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        HSplitView {
            // Left: Tools + AI Chat
            VStack(spacing: 0) {
                SceneComposerProToolPanel(
                    selectedTool: $selectedTool,
                    brushSettings: $brushSettings
                )
                .frame(minHeight: 200)

                Divider().background(MCTheme.panelBorder)

                SceneComposerProAIChat(
                    messages: $chatMessages,
                    inputText: $chatInput,
                    currentPlan: $currentPlan,
                    onSend: sendChatMessage
                )
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            // Center: 3D Viewport
            ZStack {
                #if os(macOS)
                SceneComposerProMetalView(
                    cameraYaw: $cameraYaw,
                    cameraPitch: $cameraPitch,
                    cameraDistance: $cameraDistance,
                    worldSize: $worldSize,
                    maxHeight: $maxHeight,
                    noiseFrequency: $noiseFrequency,
                    noiseOctaves: $noiseOctaves,
                    noiseSeed: $noiseSeed,
                    needsRegeneration: $needsRegeneration,
                    erosionEnabled: $erosionEnabled,
                    erosionStrength: $erosionStrength,
                    needsErosion: $needsErosion,
                    selectedWorldPosition: $selectedWorldPosition,
                    selectedTool: selectedTool,
                    brushSettings: brushSettings,
                    waterLevel: waterLevel,
                    showWater: showWater,
                    waterDeepColor: waterDeepColor,
                    waterShallowColor: waterShallowColor,
                    waterOpacity: waterOpacity,
                    waterWaveScale: waterWaveScale,
                    waterWaveSpeed: waterWaveSpeed,
                    sunAltitude: sunAltitude,
                    sunAzimuth: sunAzimuth,
                    fogDensity: fogDensity,
                    onSpacePressed: handleSpacePressed
                )
                #endif

                viewportOverlay

                if showInlinePrompt {
                    SceneComposerProInlinePrompt(
                        anchorPoint: inlinePromptAnchor,
                        context: inlinePromptContext,
                        spatialMode: spatialMode,
                        viewportSize: CGSize(width: 800, height: 600),
                        onSpatialModeChanged: { spatialMode = $0 },
                        onSubmit: handleInlineSubmit,
                        onDismiss: { showInlinePrompt = false }
                    )
                }
            }

            // Right: Inspector + Layers
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch selectedTool {
                        case .terrain, .brush:
                            SceneComposerProInspector(
                                terrain: $terrain,
                                needsRegeneration: $needsRegeneration
                            )
                        case .water:
                            waterInspector
                        case .atmosphere:
                            atmosphereInspector
                        default:
                            SceneComposerProInspector(
                                terrain: $terrain,
                                needsRegeneration: $needsRegeneration
                            )
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 200)

                Divider().background(MCTheme.panelBorder)

                SceneComposerProLayerPanel(
                    layers: $layers,
                    selectedLayerID: $selectedLayerID
                )
                .frame(minHeight: 140)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 380)
        }
    }

    // MARK: - Viewport Overlay

    private var viewportOverlay: some View {
        VStack {
            HStack {
                if let pos = selectedWorldPosition {
                    selectionBadge(pos)
                        .padding(8)
                }
                Spacer()
                spatialModeIndicator
                    .padding(8)
            }
            Spacer()
            HStack {
                statsOverlay
                    .padding(8)
                Spacer()
                Text("Space: AI Prompt")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(8)
            }
        }
    }

    private func selectionBadge(_ pos: SIMD3<Float>) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(MCTheme.statusOrange)
                .frame(width: 6, height: 6)
            Text(String(format: "%.0f, %.0f, %.0f", pos.x, pos.y, pos.z))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Button {
                selectedWorldPosition = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var spatialModeIndicator: some View {
        Menu {
            ForEach(SpatialCoordinateMode.allCases) { mode in
                Button {
                    spatialMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: spatialMode.icon)
                    .font(.system(size: 9))
                Text(spatialMode.rawValue)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var statsOverlay: some View {
        HStack(spacing: 12) {
            if let t = terrain {
                Text("Heightmap: \(t.heightmapResolution)x\(t.heightmapResolution)")
                Text("LOD: \(t.lodLevels)")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white.opacity(0.4))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text("Scene Composer Pro")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)

            Spacer()

            if let t = terrain {
                Text("\(Int(t.worldSize.x))x\(Int(t.worldSize.y))m | \(Int(t.maxHeight))m height")
                    .font(MCTheme.fontMono)
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Water Inspector

    private var waterInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader("WATER")

            Toggle("Show Water", isOn: $showWater)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            if showWater {
                inspectorSlider("Water Level", value: $waterLevel, range: 0...maxHeight)
                inspectorSlider("Opacity", value: $waterOpacity, range: 0.1...1.0)

                Divider().background(MCTheme.panelBorder)
                inspectorHeader("WAVES")
                inspectorSlider("Scale", value: $waterWaveScale, range: 0...4)
                inspectorSlider("Speed", value: $waterWaveSpeed, range: 0...3)

                Divider().background(MCTheme.panelBorder)
                inspectorHeader("COLOR")

                colorRow("Deep", r: $waterDeepColor.x, g: $waterDeepColor.y, b: $waterDeepColor.z)
                colorRow("Shallow", r: $waterShallowColor.x, g: $waterShallowColor.y, b: $waterShallowColor.z)

                HStack(spacing: 6) {
                    presetButton("Ocean") {
                        waterDeepColor = SIMD3<Float>(0.02, 0.06, 0.18)
                        waterShallowColor = SIMD3<Float>(0.04, 0.20, 0.30)
                    }
                    presetButton("Lake") {
                        waterDeepColor = SIMD3<Float>(0.03, 0.10, 0.15)
                        waterShallowColor = SIMD3<Float>(0.08, 0.28, 0.32)
                    }
                    presetButton("Tropical") {
                        waterDeepColor = SIMD3<Float>(0.01, 0.12, 0.22)
                        waterShallowColor = SIMD3<Float>(0.05, 0.40, 0.45)
                    }
                    presetButton("Murky") {
                        waterDeepColor = SIMD3<Float>(0.04, 0.05, 0.06)
                        waterShallowColor = SIMD3<Float>(0.10, 0.12, 0.08)
                    }
                }
            }
        }
    }

    // MARK: - Atmosphere Inspector

    private var atmosphereInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorHeader("SUN")
            inspectorSlider("Altitude", value: $sunAltitude, range: 0.05...1.5)
            inspectorSlider("Azimuth", value: $sunAzimuth, range: 0...Float.pi * 2)

            Divider().background(MCTheme.panelBorder)
            inspectorHeader("FOG")
            inspectorSlider("Density", value: $fogDensity, range: 0...0.02, format: "%.4f")
        }
    }

    // MARK: - Inspector Helpers

    private func inspectorHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MCTheme.textTertiary)
            .tracking(0.8)
    }

    private func inspectorSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, format: String = "%.2f") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(MCTheme.fontCaption).foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(MCTheme.fontMono).foregroundStyle(MCTheme.textTertiary)
            }
            Slider(value: value, in: range).controlSize(.mini)
        }
    }

    private func colorRow(_ label: String, r: Binding<Float>, g: Binding<Float>, b: Binding<Float>) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: Double(r.wrappedValue), green: Double(g.wrappedValue), blue: Double(b.wrappedValue)))
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.2), lineWidth: 1))
            Text(label).font(MCTheme.fontCaption).foregroundStyle(MCTheme.textSecondary)
            Spacer()
            Text(String(format: "%.2f %.2f %.2f", r.wrappedValue, g.wrappedValue, b.wrappedValue))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(MCTheme.textTertiary)
        }
    }

    private func presetButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(name, action: action)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(MCTheme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func syncTerrainToRenderer(_ terrain: TerrainComponent?) {
        guard let t = terrain else { return }
        worldSize = t.worldSize
        maxHeight = t.maxHeight
        if let firstNoise = t.noiseLayers.first {
            noiseFrequency = firstNoise.frequency
            noiseOctaves = firstNoise.octaves
            noiseSeed = firstNoise.seed
        }
    }

    private func handleSpacePressed() {
        if let pos = selectedWorldPosition {
            inlinePromptContext = .terrainPoint(pos)
        } else {
            inlinePromptContext = .sceneGlobal
        }
        inlinePromptAnchor = CGPoint(x: 400, y: 300)
        showInlinePrompt = true
    }

    private func handleInlineSubmit(_ text: String) {
        chatMessages.append(ComposerChatMessage(content: text, isUser: true))
        chatMessages.append(ComposerChatMessage(
            content: "Received: \"\(text)\" — AI composer agent integration pending.",
            isUser: false
        ))
        showInlinePrompt = false
    }

    private func sendChatMessage() {
        guard !chatInput.isEmpty else { return }
        let text = chatInput
        chatInput = ""
        chatMessages.append(ComposerChatMessage(content: text, isUser: true))
        chatMessages.append(ComposerChatMessage(
            content: "Received: \"\(text)\" — AI composer agent integration pending.",
            isUser: false
        ))
    }

    private func exportToUSDA() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "usda") ?? .data]
        panel.nameFieldStringValue = "\(documentName).usda"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            _ = try SceneComposerProUSDExporter.save(
                terrain: terrain,
                vegetation: nil,
                waterBodies: [],
                sceneName: documentName,
                directory: url.deletingLastPathComponent()
            )
        } catch {
            print("[SceneComposerPro] USDA export error: \(error)")
        }
    }

    private func optimizeScene() {
        let optimizer = SceneOptimizer()
        let report = optimizer.analyze(
            entityCount: layers.count,
            totalTriangles: (terrain?.heightmapResolution ?? 256) * (terrain?.heightmapResolution ?? 256) * 2,
            drawCalls: layers.count + 1,
            uniqueMeshCount: 1,
            duplicateMeshGroups: 0
        )

        chatMessages.append(ComposerChatMessage(
            content: report.summary,
            isUser: false
        ))
    }

    // MARK: - Undo / Redo

    private func pushUndo() {
        undoStack.append(terrain)
        redoStack.removeAll()
    }

    private func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(terrain)
        terrain = previous
        needsRegeneration = true
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(terrain)
        terrain = next
        needsRegeneration = true
    }

    // MARK: - Save / Load

    private func saveDocument() {
        guard let url = currentFileURL else {
            saveDocumentAs()
            return
        }

        let doc = SceneComposerProDocumentManager.buildDocument(
            name: documentName,
            terrain: terrain,
            vegetation: nil,
            waterBodies: [],
            layers: layers,
            cameraYaw: cameraYaw,
            cameraPitch: cameraPitch,
            cameraDistance: cameraDistance,
            spatialMode: spatialMode
        )

        try? SceneComposerProDocumentManager.save(document: doc, to: url)
    }

    private func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mcterrain]
        panel.nameFieldStringValue = "\(documentName).mcterrain"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentFileURL = url
        saveDocument()
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mcterrain]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let doc = try? SceneComposerProDocumentManager.load(from: url) else { return }
        documentName = doc.name
        terrain = doc.terrain
        layers = SceneComposerProDocumentManager.restoreLayers(from: doc)
        cameraYaw = doc.cameraYaw
        cameraPitch = doc.cameraPitch
        cameraDistance = doc.cameraDistance
        spatialMode = doc.spatialMode
        currentFileURL = url
        needsRegeneration = true
    }
}
