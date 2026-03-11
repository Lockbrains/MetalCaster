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
                    routeToSDFCanvas(notification: .sdfCanvasUndo) {
                        editorState?.undoLast()
                    }
                }
                .keyboardShortcut("z")
                .disabled(editorState == nil)

                Button("Redo") {
                    routeToSDFCanvas(notification: .sdfCanvasRedo) {
                        editorState?.redoLast()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editorState == nil)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    routeToSDFCanvas(notification: .sdfCanvasCopy) {
                        editorState?.copySelectedEntity()
                    }
                }
                .keyboardShortcut("c")
                .disabled(editorState == nil)

                Button("Paste") {
                    routeToSDFCanvas(notification: .sdfCanvasPaste) {
                        editorState?.pasteEntity()
                    }
                }
                .keyboardShortcut("v")
                .disabled(editorState == nil)

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
                Button("Shader Canvas Pro") {
                    editorState?.showShaderCanvas = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(editorState == nil)

                Button("SDF Canvas Pro") {
                    editorState?.showSDFCanvas = true
                }
                .disabled(editorState == nil)

                Button("Scene Composer Pro") {
                    editorState?.showSceneComposer = true
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(editorState == nil)

                Divider()

                Section("Scene Composer Pro") {
                    Button("New Terrain") {
                        NotificationCenter.default.post(name: .sceneComposerNew, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Open Terrain...") {
                        NotificationCenter.default.post(name: .sceneComposerOpen, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Save Terrain") {
                        NotificationCenter.default.post(name: .sceneComposerSave, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Save Terrain As...") {
                        NotificationCenter.default.post(name: .sceneComposerSaveAs, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Export as USDA...") {
                        NotificationCenter.default.post(name: .sceneComposerExportUSDA, object: nil)
                    }
                    .disabled(editorState == nil)
                }

                Divider()

                Section("SDF Canvas Pro") {
                    Button("New Canvas") {
                        NotificationCenter.default.post(name: .sdfCanvasNew, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Open Canvas...") {
                        NotificationCenter.default.post(name: .sdfCanvasOpen, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Save Canvas") {
                        NotificationCenter.default.post(name: .sdfCanvasSave, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Save Canvas As...") {
                        NotificationCenter.default.post(name: .sdfCanvasSaveAs, object: nil)
                    }
                    .disabled(editorState == nil)

                    Button("Export SDF Mesh...") {
                        NotificationCenter.default.post(name: .sdfCanvasExport, object: nil)
                    }
                    .disabled(editorState == nil)
                }

                Divider()

                Section("Convert") {
                    Button("Import & Convert Model...") {
                        editorState?.showModelConverterPanel = true
                    }
                    .disabled(editorState == nil)
                }

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

    private func routeToSDFCanvas(notification: NSNotification.Name, fallback: () -> Void) {
        if isSDFCanvasWindowFocused {
            NotificationCenter.default.post(name: notification, object: nil)
        } else {
            fallback()
        }
    }

    private var isSDFCanvasWindowFocused: Bool {
        #if os(macOS)
        NSApp.keyWindow?.title == ToolWindowKind.sdfCanvas.rawValue
        #else
        false
        #endif
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
