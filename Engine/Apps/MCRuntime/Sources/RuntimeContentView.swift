import SwiftUI
import MetalKit
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct RuntimeContentView: View {
    @Environment(MCRuntime.self) private var runtime
    
    var body: some View {
        ZStack {
            #if canImport(AppKit)
            RuntimeMetalView_macOS(runtime: runtime)
            #else
            Text("Runtime viewport placeholder")
            #endif
            
            if !runtime.isRunning {
                VStack {
                    Text("Metal Caster Runtime")
                        .font(.title.bold())
                    Text(runtime.sceneName)
                        .foregroundStyle(.secondary)
                    
                    Button("Start") {
                        runtime.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

#if canImport(AppKit)
struct RuntimeMetalView_macOS: NSViewRepresentable {
    let runtime: MCRuntime
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.delegate = context.coordinator
        context.coordinator.setup(device: mtkView.device!)
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {}
    
    func makeCoordinator() -> RuntimeCoordinator {
        RuntimeCoordinator(runtime: runtime)
    }
}

class RuntimeCoordinator: NSObject, MTKViewDelegate {
    let runtime: MCRuntime
    var metalDevice: MCMetalDevice?
    var meshPool: MeshPool?
    var shaderCompiler: ShaderCompiler?
    var meshPipeline: MTLRenderPipelineState?
    
    init(runtime: MCRuntime) {
        self.runtime = runtime
        super.init()
    }
    
    func setup(device: MTLDevice) {
        self.metalDevice = MCMetalDevice(device: device)
        self.meshPool = MeshPool(device: device)
        self.shaderCompiler = ShaderCompiler(device: device)
        compilePipeline(viewColorFormat: .bgra8Unorm_srgb)
    }
    
    private func compilePipeline(viewColorFormat: MTLPixelFormat) {
        guard let compiler = shaderCompiler else { return }
        let vs = ShaderSnippets.generateSharedHeader(config: DataFlowConfig()) +
            ShaderSnippets.generateDefaultVertexShader(config: DataFlowConfig())
        let fs = ShaderSnippets.generateSharedHeader(config: DataFlowConfig()) +
            ShaderSnippets.defaultFragment
        meshPipeline = try? compiler.compilePipeline(
            vertexSource: vs,
            fragmentSource: fs,
            colorFormat: viewColorFormat,
            depthFormat: .depth32Float,
            vertexDescriptor: MeshPool.metalVertexDescriptor
        )
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        runtime.cameraSystem.aspectRatio = Float(size.width / size.height)
    }
    
    func draw(in view: MTKView) {
        runtime.tick(deltaTime: 1.0 / 60.0)
        
        guard let device = metalDevice,
              let commandBuffer = device.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }
        
        let cam = runtime.cameraSystem
        let viewMatrix = cam.viewMatrix
        let projMatrix = cam.projectionMatrix
        let eye = cam.cameraPosition
        
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            encoder.setDepthStencilState(device.depthStencilState)
            
            if let pipeline = meshPipeline, let pool = meshPool {
                encoder.setRenderPipelineState(pipeline)
                
                for drawCall in runtime.meshRenderSystem.drawCalls {
                    let mvp = projMatrix * viewMatrix * drawCall.worldMatrix
                    let normalMatrix = simd_transpose(simd_inverse(drawCall.worldMatrix))
                    var uniforms = Uniforms(
                        mvpMatrix: mvp,
                        modelMatrix: drawCall.worldMatrix,
                        normalMatrix: normalMatrix,
                        cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 0),
                        time: runtime.engine.totalTime
                    )
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    
                    if let mesh = pool.mesh(for: drawCall.meshType) {
                        MeshRenderer.draw(mesh: mesh, with: encoder)
                    }
                }
            }
            
            encoder.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#endif
