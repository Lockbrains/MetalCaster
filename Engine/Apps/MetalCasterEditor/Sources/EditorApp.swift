import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAI
import MetalCasterAsset

@main
struct MetalCasterEditorApp: App {
    @State private var editorState: EditorState?
    @State private var openedProjectURL: URL? = nil

    var body: some Scene {
        WindowGroup("Metal Caster") {
            Group {
                if let state = editorState {
                    EditorContentView()
                        .environment(state)
                        .background(WindowConfigurator())
                } else {
                    WelcomeView(openedProjectURL: $openedProjectURL)
                        .background(WelcomeWindowConfigurator())
                }
            }
            .onChange(of: openedProjectURL) { _, newURL in
                guard let url = newURL else { return }
                openProject(at: url)
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Scene") {
                    editorState?.requestNewScene()
                }
                .keyboardShortcut("n")
                .disabled(editorState == nil)

                Divider()

                Button("Open Scene...") {
                    editorState?.showOpenPanel = true
                }
                .keyboardShortcut("o")
                .disabled(editorState == nil)

                Divider()

                Button("Close Project") {
                    closeProject()
                }
                .disabled(editorState == nil)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    editorState?.undoLast()
                }
                .keyboardShortcut("z")
                .disabled(editorState?.undoStack.isEmpty ?? true)

                Button("Redo") {
                    editorState?.redoLast()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editorState?.redoStack.isEmpty ?? true)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    editorState?.copySelectedEntity()
                }
                .keyboardShortcut("c")
                .disabled(editorState?.selectedEntity == nil)

                Button("Paste") {
                    editorState?.pasteEntity()
                }
                .keyboardShortcut("v")
                .disabled(editorState?.entityClipboard == nil)

                Divider()

                Button("Duplicate") {
                    editorState?.duplicateSelectedEntity()
                }
                .keyboardShortcut("d")
                .disabled(editorState?.selectedEntity == nil)

                Button("Delete") {
                    editorState?.deleteSelectedEntity()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(editorState?.selectedEntity == nil)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Scene") {
                    editorState?.saveScene()
                }
                .keyboardShortcut("s")
                .disabled(editorState == nil)

                Button("Save Scene As...") {
                    editorState?.saveSceneAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(editorState == nil)
            }

            CommandMenu("Scene") {
                Button("Empty Entity") {
                    editorState?.addEmptyEntity()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editorState == nil)

                Button("New Collection") {
                    editorState?.createCollectionOrEntityInCollection()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(editorState == nil)

                Divider()

                Menu("Prefab") {
                    Menu("Mesh") {
                        ForEach(MeshType.builtinPrimitives, id: \.displayName) { meshType in
                            Button(meshType.displayName) {
                                editorState?.addMeshEntity(name: meshType.displayName, meshType: meshType)
                            }
                        }
                    }
                    Button("Camera") { editorState?.addCamera() }
                    Button("Directional Light") { editorState?.addDirectionalLight() }
                    Button("Point Light") { editorState?.addPointLight() }
                    Button("Spot Light") { editorState?.addSpotLight() }
                }
                .disabled(editorState == nil)

                Divider()

                Button("Import USD...") {
                    editorState?.showImportPanel = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(editorState == nil)
            }

            CommandMenu("Build") {
                Button(editorState?.buildSystem.isPlaying == true ? "Stop" : "Play in Editor") {
                    editorState?.playInEditor()
                }
                .keyboardShortcut("r")
                .disabled(editorState == nil)

                Divider()

                Menu("Target Platform") {
                    ForEach(TargetPlatform.allCases, id: \.rawValue) { platform in
                        Button(platform.displayName) {
                            editorState?.buildTargetPlatform = platform
                        }
                    }
                }

                Button("Build Project...") {
                    editorState?.showBuildPanel = true
                }
                .keyboardShortcut("b")
                .disabled(editorState == nil)
            }

            CommandMenu("Tool") {
                Button("Shader Canvas") {
                    editorState?.showShaderCanvas = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(editorState == nil)

                Button("SDF Canvas") {
                    editorState?.showSDFCanvas = true
                }
                .disabled(editorState == nil)

                Divider()

                Section("Analyze") {
                    Button("Frame Debugger") {
                        editorState?.showFrameDebugger = true
                    }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(editorState == nil)

                    Button("Profiler") {
                        editorState?.showProfiler = true
                    }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(editorState == nil)
                }
            }

            CommandMenu("AI") {
                Button("AI Chat") {
                    editorState?.showAIChat.toggle()
                }
                .keyboardShortcut("l")
                .disabled(editorState == nil)

                Button("AI Settings...") {
                    editorState?.showAISettings = true
                }
                .keyboardShortcut(",", modifiers: [.command, .option])
                .disabled(editorState == nil)
            }
        }
    }

    private func openProject(at url: URL) {
        let state = EditorState(projectURL: url)
        self.editorState = state

        let name = url.deletingPathExtension().lastPathComponent
        RecentProjectsStore.add(name: name, url: url)
    }

    private func closeProject() {
        editorState?.saveEditorSnapshot()
        editorState?.saveScene()
        editorState = nil
        openedProjectURL = nil
    }
}

#if os(macOS)
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.isOpaque = true
            window.styleMask.insert(.fullSizeContentView)
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct WelcomeWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.isOpaque = true
            window.styleMask.insert(.fullSizeContentView)
            window.setContentSize(NSSize(width: 800, height: 480))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
