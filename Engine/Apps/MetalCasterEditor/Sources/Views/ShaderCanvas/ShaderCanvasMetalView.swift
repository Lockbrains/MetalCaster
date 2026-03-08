#if os(macOS)
import SwiftUI
import MetalKit
import MetalCasterRenderer

/// NSViewRepresentable bridge between SwiftUI and the engine's ShaderCanvasRenderer.
/// Wraps an MTKView and forwards state changes to the renderer each frame.
struct ShaderCanvasMetalView: NSViewRepresentable {

    var canvasState: ShaderCanvasState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else { return mtkView }

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        mtkView.preferredFramesPerSecond = 60

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

    func updateNSView(_ nsView: MTKView, context: Context) {
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
