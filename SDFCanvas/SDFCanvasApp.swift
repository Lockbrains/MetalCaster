import SwiftUI

@main
struct SDFCanvasApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Canvas") {
                    NotificationCenter.default.post(name: .sdfCanvasNew, object: nil)
                }
                .keyboardShortcut("n")

                Divider()

                Button("Open...") {
                    NotificationCenter.default.post(name: .sdfCanvasOpen, object: nil)
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .sdfCanvasSave, object: nil)
                }
                .keyboardShortcut("s")

                Button("Save As...") {
                    NotificationCenter.default.post(name: .sdfCanvasSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandMenu("Export") {
                Button("Export Mesh...") {
                    NotificationCenter.default.post(name: .sdfCanvasExport, object: nil)
                }
                .keyboardShortcut("e")
            }
        }
    }
}
