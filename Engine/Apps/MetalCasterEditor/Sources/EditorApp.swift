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
                    editorState?.newScene()
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
                Button("Add Empty Entity") {
                    editorState?.addEmptyEntity()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editorState == nil)

                Button("Add Camera") {
                    editorState?.addCamera()
                }
                .disabled(editorState == nil)

                Button("Add Directional Light") {
                    editorState?.addDirectionalLight()
                }
                .disabled(editorState == nil)

                Button("Add Point Light") {
                    editorState?.addPointLight()
                }
                .disabled(editorState == nil)

                Divider()

                Button("Add Cube") {
                    editorState?.addMeshEntity(name: "Cube", meshType: .cube)
                }
                .disabled(editorState == nil)

                Button("Add Sphere") {
                    editorState?.addMeshEntity(name: "Sphere", meshType: .sphere)
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
                Button("Play in Editor") {
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

            CommandMenu("AI") {
                Button("AI Chat") {
                    editorState?.showAIChat.toggle()
                }
                .keyboardShortcut("l")
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
