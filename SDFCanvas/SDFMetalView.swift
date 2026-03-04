import SwiftUI
import MetalKit

/// SwiftUI ↔ Metal bridge for SDF Canvas.
///
/// Thin stateless wrapper: receives SDF tree and camera state from SwiftUI,
/// pushes them into `SDFRenderer` on every update cycle.
struct SDFMetalView: NSViewRepresentable {

    var sdfTree: SDFNode
    var cameraYaw: Float
    var cameraPitch: Float
    var cameraDistance: Float
    var maxSteps: Int
    var surfaceThreshold: Float

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.layer?.isOpaque = true

        if let renderer = SDFRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
        }
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.sdfTree = sdfTree
        renderer.cameraYaw = cameraYaw
        renderer.cameraPitch = cameraPitch
        renderer.cameraDistance = cameraDistance
        renderer.maxSteps = maxSteps
        renderer.surfaceThreshold = surfaceThreshold
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: SDFRenderer?
    }
}
