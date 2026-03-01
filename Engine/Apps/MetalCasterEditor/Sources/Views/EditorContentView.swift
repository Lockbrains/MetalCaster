import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct EditorContentView: View {
    @Environment(EditorState.self) private var state

    var body: some View {
        VSplitView {
            HSplitView {
                MCPanel(titleNormal: "Scene", titleBold: "Editor") {
                    SceneEditorView()
                }
                .frame(minWidth: 300, minHeight: 200)

                MCPanel(titleNormal: "Entity", titleBold: "Hierarchy") {
                    SceneHierarchyView()
                }
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)

                MCPanel(titleNormal: "Inspector", titleBold: "Input") {
                    InspectorView()
                }
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 420)
            }

            HSplitView {
                MCPanel(titleNormal: "Output", titleBold: "Camera 01") {
                    GameViewportView()
                }
                .frame(minWidth: 300, minHeight: 140)

                MCPanel(titleNormal: "Project", titleBold: "Assets") {
                    ProjectAssetsView()
                }
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)

                MCPanel(titleNormal: "Component", titleBold: "Toolboxes") {
                    ComponentToolboxView()
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
                    state.loadScene(from: url)
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
