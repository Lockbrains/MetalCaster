import MetalKit
import simd

/// Metal rendering backend for SDF Canvas.
///
/// Renders a fullscreen triangle whose fragment shader performs ray marching
/// against the SDF scene. The shader source is regenerated whenever the
/// SDF tree changes, compiled at runtime, and cached until the next change.
final class SDFRenderer: NSObject, MTKViewDelegate {

    // MARK: - GPU Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?

    // MARK: - Shader State

    private var currentShaderSource: String = ""
    private var compilationError: String?
    private var needsRecompile = true

    // MARK: - Scene State (set by SDFMetalView bridge)

    var sdfTree: SDFNode = .defaultScene() {
        didSet { needsRecompile = true }
    }

    var maxSteps: Int = 128 {
        didSet { needsRecompile = true }
    }

    var surfaceThreshold: Float = 0.001 {
        didSet { needsRecompile = true }
    }

    // MARK: - Camera

    var cameraYaw: Float = 0.5
    var cameraPitch: Float = 0.3
    var cameraDistance: Float = 5.0

    // MARK: - Timing

    private var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    // MARK: - Init

    init?(metalView: MTKView) {
        guard let device = metalView.device,
              let queue = device.makeCommandQueue() else { return nil }

        self.device = device
        self.commandQueue = queue
        super.init()

        metalView.delegate = self
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.preferredFramesPerSecond = 60
    }

    // MARK: - Shader Compilation

    private func recompileIfNeeded() {
        guard needsRecompile else { return }
        needsRecompile = false

        let source = SDFShaderGenerator.generate(
            tree: sdfTree,
            maxSteps: maxSteps,
            threshold: surfaceThreshold
        )

        guard source != currentShaderSource else { return }
        currentShaderSource = source

        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let vertexFn = library.makeFunction(name: "vertex_main"),
                  let fragmentFn = library.makeFunction(name: "fragment_main") else {
                compilationError = "Missing vertex_main or fragment_main"
                return
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = fragmentFn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            compilationError = nil
        } catch {
            compilationError = error.localizedDescription
            print("[SDFRenderer] Shader compilation failed: \(error)")
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        recompileIfNeeded()

        guard let pipeline = pipelineState,
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let size = view.drawableSize
        let aspect = Float(size.width / size.height)
        let time = Float(CFAbsoluteTimeGetCurrent() - startTime)

        let camX = cameraDistance * cos(cameraPitch) * sin(cameraYaw)
        let camY = cameraDistance * sin(cameraPitch)
        let camZ = cameraDistance * cos(cameraPitch) * cos(cameraYaw)
        let eye = SIMD3<Float>(camX, camY, camZ)

        let view4 = lookAt(eye: eye, center: .zero, up: SIMD3(0, 1, 0))
        let proj = perspectiveProjection(fovY: Float.pi / 4, aspect: aspect, near: 0.1, far: 200)
        let vp = proj * view4

        guard let vpInv = vp.inverse else { return }

        var uniforms = SDFUniforms(
            inverseViewProjection: vpInv,
            cameraPosition: eye,
            time: time,
            resolution: SIMD2(Float(size.width), Float(size.height)),
            maxSteps: Int32(maxSteps),
            surfaceThreshold: surfaceThreshold
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SDFUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    // MARK: - Math Helpers

    private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        ))
    }

    private func perspectiveProjection(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1.0 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)

        return simd_float4x4(columns: (
            SIMD4(x, 0, 0,  0),
            SIMD4(0, y, 0,  0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }
}

// MARK: - Matrix Inverse Helper

private extension simd_float4x4 {
    var inverse: simd_float4x4? {
        let inv = simd_inverse(self)
        if simd_determinant(self) == 0 { return nil }
        return inv
    }
}
