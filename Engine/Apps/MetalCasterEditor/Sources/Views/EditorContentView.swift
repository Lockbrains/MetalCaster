import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAI
import MetalCasterAsset

struct EditorContentView: View {
    @Environment(EditorState.self) private var state
    @State private var agentTab = 0
    @State private var hierarchyTab = 0
    @State private var assetsTab = 0

    var body: some View {
        VSplitView {
            HSplitView {
                MCPanelCustomTitle {
                    SceneEditorView()
                } title: {
                    sceneEditorPanelTitle
                }
                .frame(minWidth: 300, minHeight: 200)

                MCPanelCustomTitle {
                    SceneHierarchyView(selectedTab: $hierarchyTab)
                } title: {
                    hierarchyPanelTitle
                }
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)

                MCPanel(titleNormal: "Inspector", titleBold: "Input") {
                    InspectorView()
                }
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 420)
            }

            HSplitView {
                MCPanelCustomTitle {
                    GameViewportView()
                } title: {
                    outputCameraPanelTitle
                }
                .frame(minWidth: 300, minHeight: 140)

                MCPanelCustomTitle {
                    switch assetsTab {
                    case 0: ProjectAssetsView()
                    case 1: ConsoleView()
                    case 2: VersionControlView()
                    default: ProjectAssetsView()
                    }
                } title: {
                    assetsPanelTitle
                }
                .frame(minWidth: 280, idealWidth: 380, maxWidth: 600)

                MCPanelCustomTitle {
                    AgentDiscussionView(selectedTab: $agentTab)
                } title: {
                    agentPanelTitle
                }
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 420)
            }
        }
        .padding(MCTheme.panelGap)
        .background(MCTheme.background)
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(
            get: { state.showAIChat },
            set: { state.showAIChat = $0 }
        )) {
            AIChatPanel()
                .environment(state)
                .frame(width: 500, height: 600)
        }
        .fileImporter(
            isPresented: Binding(
                get: { state.showOpenPanel },
                set: { state.showOpenPanel = $0 }
            ),
            allowedContentTypes: [.json],
            onCompletion: { result in
                if case .success(let url) = result {
                    state.requestLoadScene(from: url)
                }
            }
        )
        .fileImporter(
            isPresented: Binding(
                get: { state.showImportPanel },
                set: { state.showImportPanel = $0 }
            ),
            allowedContentTypes: [.usdz, .item],
            onCompletion: { result in
                if case .success(let url) = result {
                    state.importUSD(from: url)
                }
            }
        )
        .sheet(isPresented: Binding(
            get: { state.showBuildPanel },
            set: { state.showBuildPanel = $0 }
        )) {
            BuildPanelView()
                .environment(state)
                .frame(width: 500, height: 420)
        }
        .sheet(isPresented: Binding(
            get: { state.showAISettings },
            set: { state.showAISettings = $0 }
        )) {
            AISettingsPanel()
                .environment(state)
                .frame(width: 520, height: 480)
        }
        .onChange(of: state.showShaderCanvas) { _, show in
            if show { ToolWindowManager.open(.shaderCanvas, state: state) }
        }
        .onChange(of: state.showSDFCanvas) { _, show in
            if show { ToolWindowManager.open(.sdfCanvas, state: state) }
        }
        .onChange(of: state.showProfiler) { _, show in
            if show { ToolWindowManager.open(.profiler, state: state) }
        }
        .onChange(of: state.showFrameDebugger) { _, show in
            if show { ToolWindowManager.open(.frameDebugger, state: state) }
        }
        .alert(
            "Unsaved Changes",
            isPresented: Binding(
                get: { state.showSaveDirtyAlert },
                set: { state.showSaveDirtyAlert = $0 }
            )
        ) {
            Button("Save") {
                state.saveAndExecutePendingAction()
            }
            .keyboardShortcut(.defaultAction)
            Button("Discard", role: .destructive) {
                state.discardAndExecutePendingAction()
            }
            Button("Cancel", role: .cancel) {
                state.cancelPendingAction()
            }
        } message: {
            Text("Scene \"\(state.sceneName)\" has unsaved changes. Do you want to save before continuing?")
        }
        .sheet(isPresented: Binding(
            get: { state.editingPromptURL != nil },
            set: { if !$0 { state.editingPromptURL = nil } }
        )) {
            if let url = state.editingPromptURL {
                PromptScriptEditorView(fileURL: url)
                    .environment(state)
                    .frame(minWidth: 600, idealWidth: 700, minHeight: 550, idealHeight: 650)
            }
        }
        .alert(
            "Install Xcode Integration",
            isPresented: Binding(
                get: { state.showXcodeIntegrationPrompt },
                set: { state.showXcodeIntegrationPrompt = $0 }
            )
        ) {
            Button("Install") {
                state.installXcodeIntegration()
            }
            .keyboardShortcut(.defaultAction)
            Button("Skip", role: .cancel) {
                state.showXcodeIntegrationPrompt = false
            }
        } message: {
            if let error = state.xcodeIntegrationError {
                Text("Failed: \(error)")
            } else {
                Text("Install .prompt syntax highlighting into Xcode? This enables colored comments, keywords, and bracket content when editing Prompt Scripts. Requires admin privileges and a restart of Xcode.")
            }
        }
    }

    private var sceneEditorPanelTitle: some View {
        HStack(spacing: 4) {
            Text("Scene")
                .font(MCTheme.fontPanelLabel)
                .foregroundStyle(MCTheme.textSecondary)
            Text("Editor")
                .font(MCTheme.fontPanelLabelBold)
                .foregroundStyle(MCTheme.textPrimary)
            Spacer()
            playButton
        }
    }

    private var isBuilding: Bool {
        if case .building = state.buildSystem.status { return true }
        return false
    }

    private var playButton: some View {
        Button {
            state.playInEditor()
        } label: {
            if isBuilding {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                    Text("Compiling...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
            } else {
                Text(state.buildSystem.isPlaying ? "Stop" : "Play")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isBuilding)
        .keyboardShortcut("r")
    }

    private var outputCameraPanelTitle: some View {
        HStack(spacing: 4) {
            Text("Output")
                .font(MCTheme.fontPanelLabel)
                .foregroundStyle(MCTheme.textSecondary)

            let cameras = state.cameraEntities
            let resolved = state.resolvedOutputCamera
            let selectedName = resolved.map { state.sceneGraph.name(of: $0) } ?? "No Camera"

            Menu {
                ForEach(cameras, id: \.entity.id) { entry in
                    Button(entry.name) {
                        state.selectedOutputCamera = entry.entity
                    }
                }
                if cameras.isEmpty {
                    Text("No cameras in scene")
                }
            } label: {
                Text(selectedName)
                    .font(MCTheme.fontPanelLabelBold)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
    }

    private var hierarchyPanelTitle: some View {
        HStack(spacing: 4) {
            Button { hierarchyTab = 0 } label: {
                Text("Entity")
                    .font(hierarchyTab == 0 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                    .foregroundStyle(hierarchyTab == 0 ? MCTheme.textPrimary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Button { hierarchyTab = 1 } label: {
                Text("Archetype")
                    .font(hierarchyTab == 1 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                    .foregroundStyle(hierarchyTab == 1 ? MCTheme.textPrimary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var assetsPanelTitle: some View {
        HStack(spacing: 4) {
            Button { assetsTab = 0 } label: {
                Text("Assets")
                    .font(assetsTab == 0 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                    .foregroundStyle(assetsTab == 0 ? MCTheme.textPrimary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Button { assetsTab = 1 } label: {
                HStack(spacing: 3) {
                    Text("Console")
                        .font(assetsTab == 1 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                        .foregroundStyle(assetsTab == 1 ? MCTheme.textPrimary : MCTheme.textTertiary)
                    if !state.buildSystem.buildLog.isEmpty {
                        Text("\(state.buildSystem.buildLog.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                {
                                    if case .failed = state.buildSystem.status {
                                        return MCTheme.statusRed
                                    }
                                    return Color.white.opacity(0.2)
                                }()
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .buttonStyle(.plain)

            Button { assetsTab = 2 } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text("VCS")
                        .font(assetsTab == 2 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                        .foregroundStyle(assetsTab == 2 ? MCTheme.textPrimary : MCTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var agentPanelTitle: some View {
        HStack(spacing: 4) {
            Button { agentTab = 0 } label: {
                Text("Agent")
                    .font(agentTab == 0 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                    .foregroundStyle(agentTab == 0 ? MCTheme.textPrimary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Button { agentTab = 1 } label: {
                Text("Colab")
                    .font(agentTab == 1 ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                    .foregroundStyle(agentTab == 1 ? MCTheme.textPrimary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Build Panel (dark-themed)

struct BuildPanelView: View {
    @Environment(EditorState.self) private var state
    @State private var outputPath: String = NSHomeDirectory() + "/Desktop"

    var body: some View {
        VStack(spacing: 16) {
            Text("Build Project")
                .font(MCTheme.fontTitle)
                .foregroundStyle(MCTheme.textPrimary)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Platform")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .trailing)
                    Picker("", selection: Binding(
                        get: { state.buildTargetPlatform },
                        set: { state.buildTargetPlatform = $0 }
                    )) {
                        ForEach(TargetPlatform.allCases, id: \.rawValue) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("Output")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .trailing)
                    TextField("", text: $outputPath)
                        .textFieldStyle(.plain)
                        .mcInputStyle()
                }
            }
            .padding(.horizontal, 24)

            if !state.buildSystem.buildLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(state.buildSystem.buildLog.indices, id: \.self) { i in
                            Text(state.buildSystem.buildLog[i])
                                .font(MCTheme.fontMono)
                                .foregroundStyle(MCTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(MCTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxHeight: 150)
                .padding(.horizontal, 24)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    state.showBuildPanel = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if case .succeeded(let url) = state.buildSystem.status {
                    #if os(macOS)
                    Button("Open in Xcode") {
                        state.buildSystem.openInXcode(projectURL: url)
                    }
                    #endif
                }

                Button("Build") {
                    let url = URL(fileURLWithPath: outputPath, isDirectory: true)
                    state.buildProject(to: url)
                }
                .buttonStyle(.borderedProminent)
                .disabled({
                    if case .building = state.buildSystem.status { return true }
                    return false
                }())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }
}

// MARK: - AI Settings Panel

struct AISettingsPanel: View {
    @Environment(EditorState.self) private var state
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var geminiKey: String = ""
    @State private var didLoad = false

    var body: some View {
        let settings = state.aiSettings

        VStack(spacing: 0) {
            HStack {
                Text("AI Settings")
                    .font(MCTheme.fontTitle)
                    .foregroundStyle(MCTheme.textPrimary)
                Spacer()
                Button {
                    state.showAISettings = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().background(MCTheme.panelBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providerSection(settings)
                    Divider().background(MCTheme.panelBorder)
                    apiKeysSection(settings)
                    Divider().background(MCTheme.panelBorder)
                    modelSection(settings)
                    Divider().background(MCTheme.panelBorder)
                    statusSection(settings)
                }
                .padding(24)
            }

            Spacer(minLength: 0)

            Divider().background(MCTheme.panelBorder)

            HStack {
                Spacer()
                Button("Done") {
                    state.showAISettings = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            if !didLoad {
                openAIKey = settings.openAIKey
                anthropicKey = settings.anthropicKey
                geminiKey = settings.geminiKey
                didLoad = true
            }
        }
    }

    // MARK: - Provider Selection

    private func providerSection(_ settings: AISettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Active Provider")

            HStack(spacing: 8) {
                ForEach(AIProvider.allCases) { provider in
                    providerButton(provider, settings: settings)
                }
            }
        }
    }

    private func providerButton(_ provider: AIProvider, settings: AISettings) -> some View {
        let isActive = settings.selectedProvider == provider
        return Button {
            settings.selectedProvider = provider
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? MCTheme.statusGreen : MCTheme.textTertiary.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(provider.rawValue)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(isActive ? MCTheme.textPrimary : MCTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.white.opacity(0.2) : MCTheme.inputBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - API Keys

    private func apiKeysSection(_ settings: AISettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("API Keys")

            apiKeyRow("OpenAI", key: $openAIKey) {
                settings.openAIKey = openAIKey
            }
            apiKeyRow("Anthropic", key: $anthropicKey) {
                settings.anthropicKey = anthropicKey
            }
            apiKeyRow("Gemini", key: $geminiKey) {
                settings.geminiKey = geminiKey
            }
        }
    }

    private func apiKeyRow(_ label: String, key: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .trailing)

            SecureField("Enter API key...", text: key)
                .textFieldStyle(.plain)
                .font(MCTheme.fontMono)
                .mcInputStyle()
                .onChange(of: key.wrappedValue) { _, _ in
                    onCommit()
                }

            Circle()
                .fill(key.wrappedValue.isEmpty ? MCTheme.textTertiary.opacity(0.3) : MCTheme.statusGreen)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Model Selection

    private func modelSection(_ settings: AISettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Models")

            modelPicker("OpenAI", provider: .openai, selection: Binding(
                get: { settings.openAIModel },
                set: { settings.openAIModel = $0 }
            ))
            modelPicker("Anthropic", provider: .anthropic, selection: Binding(
                get: { settings.anthropicModel },
                set: { settings.anthropicModel = $0 }
            ))
            modelPicker("Gemini", provider: .gemini, selection: Binding(
                get: { settings.geminiModel },
                set: { settings.geminiModel = $0 }
            ))
        }
    }

    private func modelPicker(_ label: String, provider: AIProvider, selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .trailing)

            Picker("", selection: selection) {
                ForEach(provider.availableModels, id: \.self) { model in
                    Text(provider.displayName(for: model))
                        .tag(model)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    // MARK: - Status

    private func statusSection(_ settings: AISettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Status")

            HStack(spacing: 8) {
                Circle()
                    .fill(settings.isConfigured ? MCTheme.statusGreen : MCTheme.statusRed)
                    .frame(width: 6, height: 6)

                if settings.isConfigured {
                    Text("Ready — using **\(settings.selectedProvider.rawValue)** with **\(settings.selectedProvider.displayName(for: settings.currentModel))**")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                } else {
                    Text("Not configured — enter an API key for **\(settings.selectedProvider.rawValue)** to enable AI features")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.statusRed)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MCTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}
