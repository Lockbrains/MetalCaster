#if os(macOS)
import SwiftUI
import MetalKit
import MetalCasterRenderer

/// Custom MTKView subclass that handles right-mouse drag for arcball rotation.
final class InteractiveCanvasMTKView: MTKView {
    var canvasState: ShaderCanvasState?

    override var acceptsFirstResponder: Bool { true }

    override func rightMouseDragged(with event: NSEvent) {
        guard let state = canvasState else { return }
        let sensitivity: Float = 0.008
        state.modelYaw += Float(event.deltaX) * sensitivity
        state.modelPitch = max(-.pi / 2 + 0.01,
                               min(.pi / 2 - 0.01,
                                   state.modelPitch + Float(event.deltaY) * sensitivity))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// NSViewRepresentable bridge between SwiftUI and the engine's ShaderCanvasRenderer.
struct ShaderCanvasMetalView: NSViewRepresentable {

    var canvasState: ShaderCanvasState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> InteractiveCanvasMTKView {
        let mtkView = InteractiveCanvasMTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return mtkView }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        mtkView.preferredFramesPerSecond = 60
        mtkView.canvasState = canvasState

        let metalDevice = MCMetalDevice(device: device)
        let renderer = ShaderCanvasRenderer()
        if let md = metalDevice {
            renderer.setup(metalDevice: md)
        }

        let delegate = CanvasViewDelegate(renderer: renderer, canvasState: canvasState, metalDevice: metalDevice)
        mtkView.delegate = delegate
        context.coordinator.delegate = delegate

        return mtkView
    }

    func updateNSView(_ nsView: InteractiveCanvasMTKView, context: Context) {
        nsView.canvasState = canvasState
        context.coordinator.delegate?.canvasState = canvasState
    }

    class Coordinator {
        var delegate: CanvasViewDelegate?
    }
}

/// MTKViewDelegate that drives ShaderCanvasRenderer each frame.
final class CanvasViewDelegate: NSObject, MTKViewDelegate {
    let renderer: ShaderCanvasRenderer
    var canvasState: ShaderCanvasState
    private let metalDevice: MCMetalDevice?

    init(renderer: ShaderCanvasRenderer, canvasState: ShaderCanvasState, metalDevice: MCMetalDevice?) {
        self.renderer = renderer
        self.canvasState = canvasState
        self.metalDevice = metalDevice
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let commandBuffer = metalDevice?.makeCommandBuffer() else { return }
        renderer.render(state: canvasState, in: view, commandBuffer: commandBuffer)
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
#endif
