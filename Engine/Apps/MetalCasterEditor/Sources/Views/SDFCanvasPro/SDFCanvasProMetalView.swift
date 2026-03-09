import SwiftUI
import MetalKit

/// SwiftUI to Metal bridge for SDF Canvas Pro.
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
    var onOrbitDrag: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?

    func makeNSView(context: Context) -> InteractiveSDFMTKView {
        let mtkView = InteractiveSDFMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.layer?.isOpaque = true
        mtkView.onOrbitDrag = onOrbitDrag
        mtkView.onZoom = onZoom

        if let renderer = SDFRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
        }
        return mtkView
    }

    func updateNSView(_ nsView: InteractiveSDFMTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        nsView.onOrbitDrag = onOrbitDrag
        nsView.onZoom = onZoom
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

/// MTKView with direct mouse controls matching Shader Canvas Pro behavior.
final class InteractiveSDFMTKView: MTKView {
    var onOrbitDrag: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDragged(with event: NSEvent) {
        onOrbitDrag?(Float(event.deltaX), Float(event.deltaY))
    }

    override func otherMouseDragged(with event: NSEvent) {
        onOrbitDrag?(Float(event.deltaX), Float(event.deltaY))
    }

    override func mouseDragged(with event: NSEvent) {
        // Option + left drag mirrors right-drag for trackpad-heavy workflows.
        if event.modifierFlags.contains(.option) {
            onOrbitDrag?(Float(event.deltaX), Float(event.deltaY))
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onZoom?(Float(event.deltaY))
    }
}
