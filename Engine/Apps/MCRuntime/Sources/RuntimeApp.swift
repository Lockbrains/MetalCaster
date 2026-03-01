import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

@main
struct MCRuntimeApp: App {
    @State private var runtime = MCRuntime()
    
    var body: some Scene {
        WindowGroup("Metal Caster Runtime") {
            RuntimeContentView()
                .environment(runtime)
        }
    }
}
