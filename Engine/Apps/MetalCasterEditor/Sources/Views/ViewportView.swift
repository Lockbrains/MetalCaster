import SwiftUI
import MetalKit
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Scene Editor View (Top — Interactive)

struct SceneEditorView: View {
    @Environment(EditorState.self) private var state

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topTrailing) {
                EditorMetalView(viewportID: 0, state: state)
                statsOverlay
            }
            SceneOverlayPanel()
        }
        .background(Color.black)
    }

    private var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Entities: \(state.engine.world.entityCount)")
            Text("Draw Calls: \(state.meshRenderSystem.drawCalls.count)")
            Text("Lights: \(state.lightingSystem.lights.count)")
        }
        .font(MCTheme.fontSmall)
        .foregroundStyle(MCTheme.textSecondary)
        .padding(8)
        .background(MCTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}

// MARK: - Game Viewport View (Bottom — Camera Output)

struct GameViewportView: View {
    @Environment(EditorState.self) private var state

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EditorMetalView(viewportID: 1, state: state)
            statsOverlay
        }
        .background(Color.black)
    }

    private var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Entities: \(state.engine.world.entityCount)")
            Text("Draw Calls: \(state.meshRenderSystem.drawCalls.count)")
        }
        .font(MCTheme.fontSmall)
        .foregroundStyle(MCTheme.textSecondary)
        .padding(8)
        .background(MCTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}

// MARK: - Metal View Bridge

#if canImport(AppKit)
struct EditorMetalView: NSViewRepresentable {
    let viewportID: Int
    let state: EditorState

    func makeNSView(context: Context) -> EditorMTKView {
        let mtkView = EditorMTKView(viewportID: viewportID)
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.delegate = context.coordinator
        context.coordinator.setup(device: mtkView.device!)
        context.coordinator.viewportView = mtkView
        return mtkView
    }

    func updateNSView(_ nsView: EditorMTKView, context: Context) {
        context.coordinator.state = state
    }

    func makeCoordinator() -> ViewportCoordinator {
        ViewportCoordinator(viewportID: viewportID, state: state)
    }
}

// MARK: - EditorMTKView (NSEvent handling)

final class EditorMTKView: MTKView {
    let viewportID: Int

    init(viewportID: Int) {
        self.viewportID = viewportID
        super.init(frame: .zero, device: nil)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }

    private func claimFocus() {
        window?.makeFirstResponder(self)
    }

    private var coordinator: ViewportCoordinator? {
        delegate as? ViewportCoordinator
    }

    // MARK: Scroll

    override func scrollWheel(with event: NSEvent) {
        guard viewportID == 0 else { return }
        claimFocus()
        coordinator?.handleScroll(delta: Float(event.scrollingDeltaY))
    }

    // MARK: Right Mouse (Orbit)

    override func rightMouseDown(with event: NSEvent) {
        guard viewportID == 0 else { return }
        claimFocus()
        coordinator?.handleRightMouseDown(at: event.locationInWindow)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleRightMouseDragged(to: event.locationInWindow)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleMouseUp()
    }

    // MARK: Left Mouse (Cmd+drag = orbit, Cmd+Opt+drag = zoom)

    override func mouseDown(with event: NSEvent) {
        guard viewportID == 0 else { return }
        claimFocus()
        coordinator?.handleLeftMouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleLeftMouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleLeftMouseUp(with: event, in: self)
    }

    // MARK: Middle Mouse (Pan)

    override func otherMouseDown(with event: NSEvent) {
        guard viewportID == 0 else { return }
        claimFocus()
        coordinator?.handleMiddleMouseDown(at: event.locationInWindow)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleMiddleMouseDragged(to: event.locationInWindow)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleMouseUp()
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard viewportID == 0 else { return }
        coordinator?.handleKeyDown(event: event)
    }
}

// MARK: - ViewportCoordinator

class ViewportCoordinator: NSObject, MTKViewDelegate {
    let viewportID: Int
    var state: EditorState
    weak var viewportView: MTKView?
    var metalDevice: MCMetalDevice?
    var meshPool: MeshPool?
    var shaderCompiler: ShaderCompiler?

    var renderedPipeline: MTLRenderPipelineState?
    var shadingPipeline: MTLRenderPipelineState?
    var wireframePipeline: MTLRenderPipelineState?
    var outlinePipeline: MTLRenderPipelineState?
    var gridRenderer: GridRenderer?
    var gizmoRenderer: GizmoRenderer?

    var lastMouseLocation: NSPoint?
    var mouseDownPoint: NSPoint?
    var didDrag: Bool = false

    // Cached matrices (updated each draw, used for gizmo hit-testing)
    var cachedViewMatrix: simd_float4x4 = .init(1)
    var cachedProjMatrix: simd_float4x4 = .init(1)
    var cachedViewSize: CGSize = .zero

    // Gizmo interaction state
    var activeGizmoAxis: Int? = nil  // 0=X, 1=Y, 2=Z
    var gizmoDragStartPos: SIMD3<Float> = .zero
    var gizmoDragStartScale: SIMD3<Float> = .one
    var gizmoDragStartLocalPoint: CGPoint = .zero
    var gizmoScreenAxisDir: SIMD2<Float> = .zero
    var gizmoPixelsPerUnit: Float = 1.0

    init(viewportID: Int, state: EditorState) {
        self.viewportID = viewportID
        self.state = state
        super.init()
    }

    func setup(device: MTLDevice) {
        metalDevice = MCMetalDevice(device: device)
        meshPool = MeshPool(device: device)
        shaderCompiler = ShaderCompiler(device: device)
        gridRenderer = GridRenderer(device: device)
        gizmoRenderer = GizmoRenderer(device: device)

        if viewportID == 0 {
            var wsConfig = DataFlowConfig()
            wsConfig.worldNormalEnabled = true
            let wsHeader = ShaderSnippets.generateSharedHeader(config: wsConfig)
            let wsVS = wsHeader + ShaderSnippets.generateDefaultVertexShader(config: wsConfig)

            renderedPipeline = try? shaderCompiler?.compilePipeline(
                vertexSource: wsVS,
                fragmentSource: wsHeader + ShaderSnippets.editorRenderedFragment,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
            shadingPipeline = try? shaderCompiler?.compilePipeline(
                vertexSource: wsVS,
                fragmentSource: wsHeader + ShaderSnippets.editorShadingFragment,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
            wireframePipeline = shadingPipeline
            outlinePipeline = try? shaderCompiler?.compilePipeline(
                vertexSource: wsVS,
                fragmentSource: wsHeader + ShaderSnippets.outlineFragment,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
        } else {
            let config = DataFlowConfig()
            let header = ShaderSnippets.generateSharedHeader(config: config)
            let defaultVS = header + ShaderSnippets.generateDefaultVertexShader(config: config)
            renderedPipeline = try? shaderCompiler?.compilePipeline(
                vertexSource: defaultVS,
                fragmentSource: header + ShaderSnippets.defaultFragment,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
        }
    }

    // MARK: - Input Handlers (Scene Editor only — viewport 0)

    func handleScroll(delta: Float) {
        let zoomSpeed: Float = 0.15
        if state.isOrthographic {
            state.orthoSize = max(1, state.orthoSize - delta * zoomSpeed)
        } else {
            state.cameraOrbitDistance = max(1, state.cameraOrbitDistance - delta * zoomSpeed)
        }
    }

    func handleRightMouseDown(at point: NSPoint) {
        lastMouseLocation = point
    }

    func handleRightMouseDragged(to point: NSPoint) {
        guard let last = lastMouseLocation else { return }
        let dx = Float(point.x - last.x)
        let dy = Float(point.y - last.y)
        lastMouseLocation = point
        applyOrbit(dx: dx, dy: dy, sensitivity: 0.005)
    }

    func handleLeftMouseDown(with event: NSEvent) {
        lastMouseLocation = event.locationInWindow
        mouseDownPoint = event.locationInWindow
        didDrag = false
        activeGizmoAxis = nil

        if state.selectedEntity != nil {
            if let view = viewportView {
                let localPoint = view.convert(event.locationInWindow, from: nil)
                let toolMode = state.sceneToolMode

                if toolMode != .pan {
                    if let axis = hitTestGizmoAxis(screenPoint: localPoint, viewSize: view.bounds.size) {
                        startGizmoDrag(axis: axis, localPoint: localPoint, viewSize: view.bounds.size)
                    }
                }
            }
        }
    }

    private func startGizmoDrag(axis: Int, localPoint: CGPoint, viewSize: CGSize) {
        guard let selected = state.selectedEntity,
              let tc = state.engine.world.getComponent(TransformComponent.self, from: selected) else { return }

        activeGizmoAxis = axis
        didDrag = true
        gizmoDragStartPos = tc.transform.position
        gizmoDragStartScale = tc.transform.scale
        gizmoDragStartLocalPoint = localPoint

        let axisDir = gizmoAxisDirection(axis)
        let entityPos = SIMD3<Float>(tc.worldMatrix.columns.3.x, tc.worldMatrix.columns.3.y, tc.worldMatrix.columns.3.z)
        let vpMatrix = cachedProjMatrix * cachedViewMatrix
        let originScreen = worldToScreen(entityPos, vpMatrix: vpMatrix, viewSize: viewSize)
        let unitScreen = worldToScreen(entityPos + axisDir, vpMatrix: vpMatrix, viewSize: viewSize)
        let screenDelta = unitScreen - originScreen
        let len = length(screenDelta)
        gizmoPixelsPerUnit = max(len, 0.01)
        gizmoScreenAxisDir = len > 0.001 ? screenDelta / len : SIMD2<Float>(1, 0)
    }

    func handleLeftMouseDragged(with event: NSEvent) {
        guard let last = lastMouseLocation else { return }
        let point = event.locationInWindow
        let dx = Float(point.x - last.x)
        let dy = Float(point.y - last.y)
        lastMouseLocation = point

        if let down = mouseDownPoint {
            let totalDx = abs(point.x - down.x)
            let totalDy = abs(point.y - down.y)
            if totalDx > 3 || totalDy > 3 { didDrag = true }
        }

        if let axis = activeGizmoAxis, let view = viewportView {
            let localPoint = view.convert(point, from: nil)
            let mouseDelta = SIMD2<Float>(
                Float(localPoint.x - gizmoDragStartLocalPoint.x),
                Float(localPoint.y - gizmoDragStartLocalPoint.y)
            )
            let projectedPixels = dot(mouseDelta, gizmoScreenAxisDir)
            let worldDelta = projectedPixels / gizmoPixelsPerUnit
            let axisDir = gizmoAxisDirection(axis)

            if let selected = state.selectedEntity {
                let toolMode = state.sceneToolMode
                if toolMode == .translate {
                    let newPos = gizmoDragStartPos + axisDir * worldDelta
                    state.updateComponent(TransformComponent.self, on: selected) { tc in
                        tc.transform.position = newPos
                    }
                } else if toolMode == .scale {
                    let scaleFactor: Float = 1.0 + worldDelta * 0.5
                    var newScale = gizmoDragStartScale
                    newScale[axis] = gizmoDragStartScale[axis] * max(0.01, scaleFactor)
                    state.updateComponent(TransformComponent.self, on: selected) { tc in
                        tc.transform.scale = newScale
                    }
                }
            }
            return
        }

        let hasCmd = event.modifierFlags.contains(.command)
        let hasOpt = event.modifierFlags.contains(.option)

        if hasCmd && hasOpt {
            let zoomDelta = dy * 0.05
            state.cameraOrbitDistance = max(1, state.cameraOrbitDistance - zoomDelta)
        } else if hasCmd {
            applyOrbit(dx: dx, dy: dy, sensitivity: 0.005)
        }
    }

    func handleMiddleMouseDown(at point: NSPoint) {
        lastMouseLocation = point
    }

    func handleMiddleMouseDragged(to point: NSPoint) {
        guard let last = lastMouseLocation else { return }
        let dx = Float(point.x - last.x)
        let dy = Float(point.y - last.y)
        lastMouseLocation = point
        applyPan(dx: dx, dy: dy)
    }

    func handleLeftMouseUp(with event: NSEvent, in view: NSView) {
        let wasGizmoDrag = activeGizmoAxis != nil
        activeGizmoAxis = nil

        let hasModifiers = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        if !didDrag && !hasModifiers && !wasGizmoDrag {
            let localPoint = view.convert(event.locationInWindow, from: nil)
            performPick(at: localPoint, viewSize: view.bounds.size)
        }
        lastMouseLocation = nil
        mouseDownPoint = nil
        didDrag = false
    }

    func handleMouseUp() {
        lastMouseLocation = nil
    }

    func handleKeyDown(event: NSEvent) {
        let hasCmd = event.modifierFlags.contains(.command)

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "q":
            state.sceneToolMode = .pan
        case "w":
            if !hasCmd { state.sceneToolMode = .translate }
        case "e":
            state.sceneToolMode = .scale
        case "r":
            if !hasCmd { state.sceneToolMode = .rotate }
        case "1":
            state.applyOrthoPreset(hasCmd ? .back : .front)
        case "3":
            state.applyOrthoPreset(hasCmd ? .left : .right)
        case "7":
            state.applyOrthoPreset(hasCmd ? .bottom : .top)
        case "5":
            if state.isOrthographic {
                state.isOrthographic = false
                state.orthoPreset = .free
            } else {
                state.isOrthographic = true
            }
        default:
            break
        }
    }

    // MARK: - Picking

    func performPick(at point: CGPoint, viewSize: CGSize) {
        guard viewportID == 0 else { return }

        let yaw = state.cameraOrbitYaw
        let pitch = state.cameraOrbitPitch
        let dist = state.cameraOrbitDistance
        let target = state.cameraOrbitTarget
        let eye = target + SIMD3<Float>(
            dist * cos(pitch) * sin(yaw),
            dist * sin(pitch),
            dist * cos(pitch) * cos(yaw)
        )
        let viewMatrix = matrix4x4LookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        let aspect = Float(viewSize.width / viewSize.height)

        let projMatrix: simd_float4x4
        if state.isOrthographic {
            let halfH = state.orthoSize * 0.5
            let halfW = halfH * aspect
            projMatrix = matrix4x4Orthographic(
                left: -halfW, right: halfW,
                bottom: -halfH, top: halfH,
                nearZ: 0.1, farZ: 1000.0
            )
        } else {
            projMatrix = matrix4x4PerspectiveRightHand(
                fovyRadians: Float.pi / 3.0,
                aspectRatio: aspect,
                nearZ: 0.1,
                farZ: 1000.0
            )
        }

        let ndcX = Float(point.x / viewSize.width) * 2.0 - 1.0
        let ndcY = Float(point.y / viewSize.height) * 2.0 - 1.0

        let invVP = (projMatrix * viewMatrix).inverse
        var nearClip = invVP * SIMD4<Float>(ndcX, ndcY, 0, 1)
        nearClip /= nearClip.w
        var farClip = invVP * SIMD4<Float>(ndcX, ndcY, 1, 1)
        farClip /= farClip.w

        let rayOrigin = SIMD3<Float>(nearClip.x, nearClip.y, nearClip.z)
        let rayDir = normalize(SIMD3<Float>(farClip.x, farClip.y, farClip.z) - rayOrigin)

        var closestT: Float = .infinity
        var closestEntity: Entity?

        for drawCall in state.meshRenderSystem.drawCalls {
            let worldMatrix = drawCall.worldMatrix
            let center = SIMD3<Float>(worldMatrix.columns.3.x, worldMatrix.columns.3.y, worldMatrix.columns.3.z)
            let scaleX = length(SIMD3<Float>(worldMatrix.columns.0.x, worldMatrix.columns.0.y, worldMatrix.columns.0.z))
            let scaleY = length(SIMD3<Float>(worldMatrix.columns.1.x, worldMatrix.columns.1.y, worldMatrix.columns.1.z))
            let scaleZ = length(SIMD3<Float>(worldMatrix.columns.2.x, worldMatrix.columns.2.y, worldMatrix.columns.2.z))
            let radius = max(scaleX, max(scaleY, scaleZ))

            if let t = raySphereIntersect(origin: rayOrigin, direction: rayDir, center: center, radius: radius), t < closestT {
                closestT = t
                closestEntity = drawCall.entity
            }
        }

        state.selectedEntity = closestEntity
    }

    private func raySphereIntersect(origin: SIMD3<Float>, direction: SIMD3<Float>, center: SIMD3<Float>, radius: Float) -> Float? {
        let oc = origin - center
        let a = dot(direction, direction)
        let b = 2.0 * dot(oc, direction)
        let c = dot(oc, oc) - radius * radius
        let disc = b * b - 4.0 * a * c
        guard disc >= 0 else { return nil }
        let t = (-b - sqrt(disc)) / (2.0 * a)
        return t > 0 ? t : nil
    }

    // MARK: - Camera Math Helpers

    private func applyOrbit(dx: Float, dy: Float, sensitivity: Float) {
        if state.isOrthographic {
            state.isOrthographic = false
            state.orthoPreset = .free
        }
        state.cameraOrbitYaw -= dx * sensitivity
        state.cameraOrbitPitch = max(
            -Float.pi / 2 + 0.01,
            min(Float.pi / 2 - 0.01, state.cameraOrbitPitch - dy * sensitivity)
        )
    }

    private func applyPan(dx: Float, dy: Float) {
        let sensitivity: Float = 0.01
        let invert: Float = state.invertPan ? -1.0 : 1.0
        let yaw = state.cameraOrbitYaw
        let pitch = state.cameraOrbitPitch

        let forward = SIMD3<Float>(
            cos(pitch) * sin(yaw),
            sin(pitch),
            cos(pitch) * cos(yaw)
        )
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = normalize(cross(forward, worldUp))
        let up = normalize(cross(right, forward))

        let panOffset = (-right * dx + up * dy) * sensitivity * invert
        let dist = state.isOrthographic ? state.orthoSize : state.cameraOrbitDistance
        state.cameraOrbitTarget += panOffset * dist * 0.1
    }

    // MARK: - Gizmo Hit-Test & Axis Projection

    private func gizmoAxisDirection(_ axis: Int) -> SIMD3<Float> {
        switch axis {
        case 0: return SIMD3<Float>(1, 0, 0)
        case 1: return SIMD3<Float>(0, 1, 0)
        case 2: return SIMD3<Float>(0, 0, 1)
        default: return .zero
        }
    }

    private func worldToScreen(_ worldPos: SIMD3<Float>, vpMatrix: simd_float4x4, viewSize: CGSize) -> SIMD2<Float> {
        var clip = vpMatrix * SIMD4<Float>(worldPos.x, worldPos.y, worldPos.z, 1)
        clip /= clip.w
        let sx = (clip.x * 0.5 + 0.5) * Float(viewSize.width)
        let sy = (clip.y * 0.5 + 0.5) * Float(viewSize.height)
        return SIMD2<Float>(sx, sy)
    }

    private func distancePointToSegment(point: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> Float {
        let ab = b - a
        let ap = point - a
        let lenSq = dot(ab, ab)
        guard lenSq > 0.0001 else { return length(ap) }
        let t = max(0, min(1, dot(ap, ab) / lenSq))
        let proj = a + ab * t
        return length(point - proj)
    }

    func hitTestGizmoAxis(screenPoint: CGPoint, viewSize: CGSize) -> Int? {
        guard let selected = state.selectedEntity,
              let tc = state.engine.world.getComponent(TransformComponent.self, from: selected) else { return nil }

        let entityPos = SIMD3<Float>(tc.worldMatrix.columns.3.x, tc.worldMatrix.columns.3.y, tc.worldMatrix.columns.3.z)
        let dist = state.cameraOrbitDistance
        let gizmoLen = dist * 0.18 * 1.18  // shaft + arrowhead
        let vpMatrix = cachedProjMatrix * cachedViewMatrix
        let threshold: Float = 20.0

        let clickPt = SIMD2<Float>(Float(screenPoint.x), Float(screenPoint.y))
        var bestAxis: Int? = nil
        var bestDist: Float = threshold

        for i in 0..<3 {
            let axisDir = gizmoAxisDirection(i)
            let tip = entityPos + axisDir * gizmoLen
            let originScreen = worldToScreen(entityPos, vpMatrix: vpMatrix, viewSize: viewSize)
            let tipScreen = worldToScreen(tip, vpMatrix: vpMatrix, viewSize: viewSize)
            let d = distancePointToSegment(point: clickPt, a: originScreen, b: tipScreen)
            if d < bestDist {
                bestDist = d
                bestAxis = i
            }
        }
        return bestAxis
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if viewportID == 0 {
            state.cameraSystem.aspectRatio = Float(size.width / size.height)
        }
    }

    func draw(in view: MTKView) {
        if viewportID == 0 {
            state.tick(deltaTime: 1.0 / 60.0)
        }

        guard let device = metalDevice,
              let commandBuffer = device.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let pool = meshPool else { return }

        let (yaw, pitch, dist, target): (Float, Float, Float, SIMD3<Float>)
        if viewportID == 0 {
            yaw = state.cameraOrbitYaw
            pitch = state.cameraOrbitPitch
            dist = state.cameraOrbitDistance
            target = state.cameraOrbitTarget
        } else {
            yaw = state.camera2OrbitYaw
            pitch = state.camera2OrbitPitch
            dist = state.camera2OrbitDistance
            target = state.camera2OrbitTarget
        }

        let eye = target + SIMD3<Float>(
            dist * cos(pitch) * sin(yaw),
            dist * sin(pitch),
            dist * cos(pitch) * cos(yaw)
        )
        let viewMatrix = matrix4x4LookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)

        let projMatrix: simd_float4x4
        if viewportID == 0 && state.isOrthographic {
            let halfH = state.orthoSize * 0.5
            let halfW = halfH * aspect
            projMatrix = matrix4x4Orthographic(
                left: -halfW, right: halfW,
                bottom: -halfH, top: halfH,
                nearZ: 0.1, farZ: 1000.0
            )
        } else {
            projMatrix = matrix4x4PerspectiveRightHand(
                fovyRadians: Float.pi / 3.0,
                aspectRatio: aspect,
                nearZ: 0.1,
                farZ: 1000.0
            )
        }

        if viewportID == 0 {
            cachedViewMatrix = viewMatrix
            cachedProjMatrix = projMatrix
            cachedViewSize = CGSize(width: view.bounds.width, height: view.bounds.height)
        }

        let activePipeline: MTLRenderPipelineState?
        let useWireframe: Bool
        if viewportID == 0 {
            switch state.sceneRenderMode {
            case .shading:
                activePipeline = shadingPipeline
                useWireframe = false
            case .wireframe:
                activePipeline = wireframePipeline
                useWireframe = true
            case .rendered:
                activePipeline = renderedPipeline
                useWireframe = false
            }
        } else {
            activePipeline = renderedPipeline
            useWireframe = false
        }

        guard let pipeline = activePipeline else { return }

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            encoder.setDepthStencilState(device.depthStencilState)

            if viewportID == 0 && state.showGrid {
                let vpMatrix = projMatrix * viewMatrix
                gridRenderer?.draw(encoder: encoder, viewProjectionMatrix: vpMatrix)
            }

            // Restore depth state after grid (grid disables depth writes)
            encoder.setDepthStencilState(device.depthStencilState)
            encoder.setRenderPipelineState(pipeline)
            if useWireframe {
                encoder.setTriangleFillMode(.lines)
            }

            for drawCall in state.meshRenderSystem.drawCalls {
                let mvp = projMatrix * viewMatrix * drawCall.worldMatrix
                var uniforms = Uniforms(
                    mvpMatrix: mvp,
                    modelMatrix: drawCall.worldMatrix,
                    normalMatrix: drawCall.normalMatrix,
                    cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 0),
                    time: state.engine.totalTime
                )
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                if let mesh = pool.mesh(for: drawCall.meshType) {
                    MeshRenderer.draw(mesh: mesh, with: encoder)
                }
            }

            if viewportID == 0, let selected = state.selectedEntity, let dev = metalDevice?.device {
                if let mc = state.engine.world.getComponent(MeshComponent.self, from: selected),
                   let tc = state.engine.world.getComponent(TransformComponent.self, from: selected),
                   let outlinePSO = outlinePipeline {
                    let outlineScale: Float = 1.03
                    let scaleMatrix = matrix4x4Scale(SIMD3<Float>(repeating: outlineScale))
                    let outlineWorld = tc.worldMatrix * scaleMatrix
                    let outlineMVP = projMatrix * viewMatrix * outlineWorld
                    let outlineNormal = simd_transpose(simd_inverse(outlineWorld))
                    var outlineUniforms = Uniforms(
                        mvpMatrix: outlineMVP,
                        modelMatrix: outlineWorld,
                        normalMatrix: outlineNormal,
                        cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 0),
                        time: state.engine.totalTime
                    )
                    encoder.setRenderPipelineState(outlinePSO)
                    encoder.setTriangleFillMode(.fill)
                    encoder.setCullMode(.back)
                    encoder.setVertexBytes(&outlineUniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    if let mesh = pool.mesh(for: mc.meshType) {
                        MeshRenderer.draw(mesh: mesh, with: encoder)
                    }
                    encoder.setCullMode(.none)
                }

                if let tc = state.engine.world.getComponent(TransformComponent.self, from: selected) {
                    let pos = SIMD3<Float>(
                        tc.worldMatrix.columns.3.x,
                        tc.worldMatrix.columns.3.y,
                        tc.worldMatrix.columns.3.z
                    )
                    let gizmoScale = dist * 0.18
                    let vpMatrix = projMatrix * viewMatrix
                    gizmoRenderer?.draw(
                        encoder: encoder,
                        viewProjectionMatrix: vpMatrix,
                        worldPosition: pos,
                        scale: gizmoScale,
                        device: dev
                    )
                }
            }

            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#endif
