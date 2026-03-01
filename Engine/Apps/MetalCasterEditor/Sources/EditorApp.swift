import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAI

@main
struct MetalCasterEditorApp: App {
    @State private var editorState = EditorState()

    var body: some Scene {
        WindowGroup("Metal Caster") {
            EditorContentView()
                .environment(editorState)
                .background(WindowConfigurator())
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Scene") {
                    editorState.newScene()
                }
                .keyboardShortcut("n")

                Divider()

                Button("Open...") {
                    editorState.showOpenPanel = true
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Scene") {
                    editorState.saveScene()
                }
                .keyboardShortcut("s")

                Button("Save Scene As...") {
                    editorState.saveSceneAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandMenu("Scene") {
                Button("Add Empty Entity") {
                    editorState.addEmptyEntity()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Add Camera") {
                    editorState.addCamera()
                }

                Button("Add Directional Light") {
                    editorState.addDirectionalLight()
                }

                Button("Add Point Light") {
                    editorState.addPointLight()
                }

                Divider()

                Button("Add Cube") {
                    editorState.addMeshEntity(name: "Cube", meshType: .cube)
                }

                Button("Add Sphere") {
                    editorState.addMeshEntity(name: "Sphere", meshType: .sphere)
                }

                Divider()

                Button("Import USD...") {
                    editorState.showImportPanel = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandMenu("Build") {
                Button("Play in Editor") {
                    editorState.playInEditor()
                }
                .keyboardShortcut("r")

                Divider()

                Menu("Target Platform") {
                    ForEach(TargetPlatform.allCases, id: \.rawValue) { platform in
                        Button(platform.displayName) {
                            editorState.buildTargetPlatform = platform
                        }
                    }
                }

                Button("Build Project...") {
                    editorState.showBuildPanel = true
                }
                .keyboardShortcut("b")
            }

            CommandMenu("AI") {
                Button("AI Chat") {
                    editorState.showAIChat.toggle()
                }
                .keyboardShortcut("l")
            }
        }
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
#endif
