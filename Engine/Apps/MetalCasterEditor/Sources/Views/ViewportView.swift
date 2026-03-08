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
        ZStack {
            Color(white: 0.05)

            GeometryReader { geo in
                let targetAspect = CGFloat(state.renderTargetConfig.aspectRatio)
                let viewAspect = geo.size.width / max(geo.size.height, 1)
                let pillarbox = viewAspect > targetAspect
                let renderW = pillarbox ? geo.size.height * targetAspect : geo.size.width
                let renderH = pillarbox ? geo.size.height : geo.size.width / targetAspect

                EditorMetalView(viewportID: 1, state: state)
                    .frame(width: renderW, height: renderH)
                    .frame(width: geo.size.width, height: geo.size.height)
            }

            VStack {
                HStack {
                    renderTargetSelector
                    Spacer()
                    statsOverlay
                }
                Spacer()
            }
            .padding(8)
        }
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
    }

    private var renderTargetSelector: some View {
        @Bindable var s = state
        return HStack(spacing: 6) {
            Menu {
                ForEach(AppleDeviceCategory.allCases) { category in
                    Menu(category.rawValue) {
                        ForEach(AppleDevicePreset.presets(for: category)) { preset in
                            Button("\(preset.name)  (\(preset.displayString))") {
                                state.renderTargetConfig.mode = .devicePreset
                                state.renderTargetConfig.presetID = preset.id
                            }
                        }
                    }
                }
                Divider()
                Button("Custom...") {
                    state.renderTargetConfig.mode = .custom
                }
            } label: {
                HStack(spacing: 4) {
                    if let preset = state.renderTargetConfig.resolvedPreset {
                        Image(systemName: preset.category.icon)
                            .font(.system(size: 9))
                        Text(preset.name)
                            .font(MCTheme.fontSmall)
                    } else {
                        Image(systemName: "rectangle.dashed")
                            .font(.system(size: 9))
                        Text("Custom")
                            .font(MCTheme.fontSmall)
                    }
                }
                .foregroundStyle(MCTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text(state.renderTargetConfig.displayString)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)

            Button {
                state.renderTargetConfig.isLandscape.toggle()
            } label: {
                Image(systemName: state.renderTargetConfig.isLandscape ? "rectangle" : "rectangle.portrait")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(state.renderTargetConfig.isLandscape ? "Landscape" : "Portrait")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MCTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
    var debugOverlayRenderer: DebugOverlayRenderer?

    // Per-material rendering
    var materialPipelineCache: PipelineCache?
    var skyboxFallbackPipeline: MTLRenderPipelineState?
    var hdrSkyboxFallbackPipeline: MTLRenderPipelineState?
    var customSkyboxTexture: MTLTexture?
    var cachedSkyboxPath: String?
    var skyboxDepthStencilState: MTLDepthStencilState?

    // Post-processing (Game Viewport only)
    var postProcessStack: PostProcessStack?
    var hdrRenderedPipeline: MTLRenderPipelineState?

    // Object ID picking & outline (Scene Editor only)
    var objectIDTexture: MTLTexture?
    var objectIDDepthTexture: MTLTexture?
    var objectIDPipeline: MTLRenderPipelineState?
    var outlineCompositePipeline: MTLRenderPipelineState?
    var outlineNoDepthState: MTLDepthStencilState?

    var lastMouseLocation: NSPoint?
    var mouseDownPoint: NSPoint?
    var didDrag: Bool = false

    // Cached matrices (updated each draw, used for gizmo hit-testing)
    var cachedViewMatrix: simd_float4x4 = .init(1)
    var cachedProjMatrix: simd_float4x4 = .init(1)
    var cachedViewSize: CGSize = .zero

    // Gizmo interaction state
    var activeGizmoAxis: Int? = nil  // 0=X, 1=Y, 2=Z, 3=view-axis (rotate only)
    var gizmoDragStartPos: SIMD3<Float> = .zero
    var gizmoDragStartScale: SIMD3<Float> = .one
    var gizmoDragStartRotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    var gizmoDragStartLocalPoint: CGPoint = .zero
    var gizmoScreenAxisDir: SIMD2<Float> = .zero
    var gizmoPixelsPerUnit: Float = 1.0
    var gizmoEntityScreenCenter: SIMD2<Float> = .zero

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
        debugOverlayRenderer = DebugOverlayRenderer(device: device)

        if let compiler = shaderCompiler {
            materialPipelineCache = PipelineCache(compiler: compiler)
        }

        if let vd = MeshPool.metalVertexDescriptor {
            MaterialRegistry.shared.warmup(
                device: device,
                vertexDescriptor: vd,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float
            )
            skyboxFallbackPipeline = MaterialRegistry.shared.compileSkyboxFallback(
                device: device,
                vertexDescriptor: vd,
                colorFormat: .bgra8Unorm_srgb,
                depthFormat: .depth32Float
            )
            hdrSkyboxFallbackPipeline = MaterialRegistry.shared.compileSkyboxFallback(
                device: device,
                vertexDescriptor: vd,
                colorFormat: .rgba16Float,
                depthFormat: .depth32Float
            )
        }

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

            // Object ID pipeline (r32Uint render target for GPU picking)
            if let idLib = try? shaderCompiler?.compile(source: ShaderSnippets.entityIDShader),
               let idVert = idLib.makeFunction(name: "vertex_main"),
               let idFrag = idLib.makeFunction(name: "fragment_main") {
                let idDesc = MTLRenderPipelineDescriptor()
                idDesc.vertexFunction = idVert
                idDesc.fragmentFunction = idFrag
                idDesc.colorAttachments[0].pixelFormat = .r32Uint
                idDesc.depthAttachmentPixelFormat = .depth32Float
                if let vd = MeshPool.metalVertexDescriptor {
                    idDesc.vertexDescriptor = vd
                }
                objectIDPipeline = try? device.makeRenderPipelineState(descriptor: idDesc)
            }

            // Outline composite pipeline (fullscreen, alpha-blended)
            if let olLib = try? shaderCompiler?.compile(source: ShaderSnippets.outlineCompositeShader),
               let olVert = olLib.makeFunction(name: "vertex_main"),
               let olFrag = olLib.makeFunction(name: "fragment_main") {
                let olDesc = MTLRenderPipelineDescriptor()
                olDesc.vertexFunction = olVert
                olDesc.fragmentFunction = olFrag
                olDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
                olDesc.colorAttachments[0].isBlendingEnabled = true
                olDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                olDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                olDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
                olDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                olDesc.depthAttachmentPixelFormat = .depth32Float
                outlineCompositePipeline = try? device.makeRenderPipelineState(descriptor: olDesc)
            }

            // Depth state that disables depth for fullscreen passes
            let noDepthDesc = MTLDepthStencilDescriptor()
            noDepthDesc.depthCompareFunction = .always
            noDepthDesc.isDepthWriteEnabled = false
            outlineNoDepthState = device.makeDepthStencilState(descriptor: noDepthDesc)
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
            hdrRenderedPipeline = try? shaderCompiler?.compilePipeline(
                vertexSource: defaultVS,
                fragmentSource: header + ShaderSnippets.defaultFragment,
                colorFormat: .rgba16Float,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
            postProcessStack = PostProcessStack(device: device)
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
        gizmoDragStartRotation = tc.transform.rotation
        gizmoDragStartLocalPoint = localPoint

        let entityPos = SIMD3<Float>(tc.worldMatrix.columns.3.x, tc.worldMatrix.columns.3.y, tc.worldMatrix.columns.3.z)
        let vpMatrix = cachedProjMatrix * cachedViewMatrix
        let originScreen = worldToScreen(entityPos, vpMatrix: vpMatrix, viewSize: viewSize)
        gizmoEntityScreenCenter = originScreen

        if state.sceneToolMode == .rotate {
            gizmoPixelsPerUnit = 1.0
            gizmoScreenAxisDir = .zero
        } else if axis == 3 && state.sceneToolMode == .scale {
            gizmoPixelsPerUnit = 1.0
            gizmoScreenAxisDir = normalize(SIMD2<Float>(1, 1))
        } else {
            let axisDir = gizmoAxisDirection(axis)
            let unitScreen = worldToScreen(entityPos + axisDir, vpMatrix: vpMatrix, viewSize: viewSize)
            let screenDelta = unitScreen - originScreen
            let len = length(screenDelta)
            gizmoPixelsPerUnit = max(len, 0.01)
            gizmoScreenAxisDir = len > 0.001 ? screenDelta / len : SIMD2<Float>(1, 0)
        }
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

            if let selected = state.selectedEntity {
                let toolMode = state.sceneToolMode
                if toolMode == .translate {
                    let projectedPixels = dot(mouseDelta, gizmoScreenAxisDir)
                    let worldDelta = projectedPixels / gizmoPixelsPerUnit
                    let axisDir = gizmoAxisDirection(axis)
                    let newPos = gizmoDragStartPos + axisDir * worldDelta
                    state.updateComponent(TransformComponent.self, on: selected) { tc in
                        tc.transform.position = newPos
                    }
                } else if toolMode == .scale {
                    let projectedPixels = dot(mouseDelta, gizmoScreenAxisDir)
                    if axis == 3 {
                        let uniformFactor: Float = 1.0 + projectedPixels * 0.005
                        let clamped = max(0.01, uniformFactor)
                        let newScale = gizmoDragStartScale * clamped
                        state.updateComponent(TransformComponent.self, on: selected) { tc in
                            tc.transform.scale = newScale
                        }
                    } else {
                        let worldDelta = projectedPixels / gizmoPixelsPerUnit
                        let scaleFactor: Float = 1.0 + worldDelta * 0.5
                        var newScale = gizmoDragStartScale
                        newScale[axis] = gizmoDragStartScale[axis] * max(0.01, scaleFactor)
                        state.updateComponent(TransformComponent.self, on: selected) { tc in
                            tc.transform.scale = newScale
                        }
                    }
                } else if toolMode == .rotate {
                    let rotationAxis: SIMD3<Float>
                    if axis == 3 {
                        let yaw = state.cameraOrbitYaw
                        let pitch = state.cameraOrbitPitch
                        rotationAxis = SIMD3<Float>(
                            cos(pitch) * sin(yaw),
                            sin(pitch),
                            cos(pitch) * cos(yaw)
                        )
                    } else {
                        rotationAxis = gizmoAxisDirection(axis)
                    }
                    let currentPt = SIMD2<Float>(Float(localPoint.x), Float(localPoint.y))
                    let startPt = SIMD2<Float>(Float(gizmoDragStartLocalPoint.x), Float(gizmoDragStartLocalPoint.y))
                    let startVec = startPt - gizmoEntityScreenCenter
                    let curVec = currentPt - gizmoEntityScreenCenter
                    let startLen = length(startVec)
                    let curLen = length(curVec)
                    var angle: Float = 0
                    if startLen > 2 && curLen > 2 {
                        let cosA = dot(startVec, curVec) / (startLen * curLen)
                        let crossZ = startVec.x * curVec.y - startVec.y * curVec.x
                        angle = acos(min(1, max(-1, cosA))) * (crossZ >= 0 ? 1 : -1)
                    }
                    let deltaQuat = simd_quatf(angle: angle, axis: rotationAxis)
                    state.updateComponent(TransformComponent.self, on: selected) { tc in
                        tc.transform.rotation = deltaQuat * gizmoDragStartRotation
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
        let hasShift = event.modifierFlags.contains(.shift)

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "q":
            state.sceneToolMode = .pan
        case "w":
            if !hasCmd { state.sceneToolMode = .translate }
        case "e":
            state.sceneToolMode = .scale
        case "r":
            if !hasCmd { state.sceneToolMode = .rotate }
        case "f":
            if hasCmd && hasShift {
                state.alignSelectedEntityToView()
            } else if !hasCmd {
                state.focusOnSelectedEntity()
            }
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

    // MARK: - Object ID Texture Management

    private func ensureObjectIDTextures(width: Int, height: Int, device: MTLDevice) {
        guard width > 0 && height > 0 else { return }
        if objectIDTexture?.width == width && objectIDTexture?.height == height { return }

        let idDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Uint, width: width, height: height, mipmapped: false)
        idDesc.usage = [.renderTarget, .shaderRead]
        idDesc.storageMode = .managed
        objectIDTexture = device.makeTexture(descriptor: idDesc)
        objectIDTexture?.label = "ObjectID"

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDesc.usage = .renderTarget
        depthDesc.storageMode = .private
        objectIDDepthTexture = device.makeTexture(descriptor: depthDesc)
        objectIDDepthTexture?.label = "ObjectID Depth"
    }

    // MARK: - GPU Picking

    func performPick(at point: CGPoint, viewSize: CGSize) {
        guard viewportID == 0, let idTex = objectIDTexture else {
            state.selectedEntity = nil
            return
        }

        let scaleX = CGFloat(idTex.width) / viewSize.width
        let scaleY = CGFloat(idTex.height) / viewSize.height
        let px = Int(point.x * scaleX)
        let py = min(idTex.height - 1, max(0, idTex.height - 1 - Int(point.y * scaleY)))

        guard px >= 0 && px < idTex.width && py >= 0 && py < idTex.height else {
            state.selectedEntity = nil
            return
        }

        var pixelValue: UInt32 = 0
        idTex.getBytes(
            &pixelValue,
            bytesPerRow: MemoryLayout<UInt32>.stride * idTex.width,
            from: MTLRegion(
                origin: MTLOrigin(x: px, y: py, z: 0),
                size: MTLSize(width: 1, height: 1, depth: 1)),
            mipmapLevel: 0)

        if pixelValue > 0 {
            let entity = Entity(id: UInt64(pixelValue - 1))
            state.selectedEntity = state.engine.world.isAlive(entity) ? entity : nil
        } else {
            state.selectedEntity = nil
        }
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
        let camDist = state.cameraOrbitDistance
        let vpMatrix = cachedProjMatrix * cachedViewMatrix
        let clickPt = SIMD2<Float>(Float(screenPoint.x), Float(screenPoint.y))
        let threshold: Float = 20.0

        if state.sceneToolMode == .rotate {
            return hitTestRotateRings(entityPos: entityPos, camDist: camDist, vpMatrix: vpMatrix,
                                      clickPt: clickPt, viewSize: viewSize, threshold: threshold)
        }

        let gizmoLen = camDist * 0.18 * 1.18
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

        if state.sceneToolMode == .scale {
            let centerScreen = worldToScreen(entityPos, vpMatrix: vpMatrix, viewSize: viewSize)
            let centerDist = length(clickPt - centerScreen)
            if centerDist < 25 {
                bestAxis = 3
            }
        }

        return bestAxis
    }

    private func hitTestRotateRings(entityPos: SIMD3<Float>, camDist: Float, vpMatrix: simd_float4x4,
                                    clickPt: SIMD2<Float>, viewSize: CGSize, threshold: Float) -> Int? {
        let ringRadius = camDist * 0.18 * 0.9
        let segments = 48

        let axisNormals: [SIMD3<Float>] = [
            SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)
        ]
        let axisStarts: [SIMD3<Float>] = [
            SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 0)
        ]

        var bestAxis: Int? = nil
        var bestDist: Float = threshold

        for axisIdx in 0..<3 {
            let normal = axisNormals[axisIdx]
            let startVec = axisStarts[axisIdx]
            let bitangent = normalize(cross(normal, startVec))
            let d = distanceToScreenRing(center: entityPos, tangent: startVec, bitangent: bitangent,
                                         radius: ringRadius, segments: segments,
                                         vpMatrix: vpMatrix, viewSize: viewSize, clickPt: clickPt)
            if d < bestDist {
                bestDist = d
                bestAxis = axisIdx
            }
        }

        let yaw = state.cameraOrbitYaw
        let pitch = state.cameraOrbitPitch
        let viewNormal = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        var viewStart = cross(viewNormal, SIMD3<Float>(0, 1, 0))
        if length(viewStart) < 0.001 { viewStart = cross(viewNormal, SIMD3<Float>(1, 0, 0)) }
        viewStart = normalize(viewStart)
        let viewBitangent = normalize(cross(viewNormal, viewStart))
        let viewRingRadius = ringRadius * 1.15
        let dView = distanceToScreenRing(center: entityPos, tangent: viewStart, bitangent: viewBitangent,
                                         radius: viewRingRadius, segments: segments,
                                         vpMatrix: vpMatrix, viewSize: viewSize, clickPt: clickPt)
        if dView < bestDist {
            bestDist = dView
            bestAxis = 3
        }

        return bestAxis
    }

    private func distanceToScreenRing(center: SIMD3<Float>, tangent: SIMD3<Float>, bitangent: SIMD3<Float>,
                                      radius: Float, segments: Int,
                                      vpMatrix: simd_float4x4, viewSize: CGSize, clickPt: SIMD2<Float>) -> Float {
        var minDist: Float = .greatestFiniteMagnitude
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * Float.pi * 2
            let a1 = Float(i + 1) / Float(segments) * Float.pi * 2
            let p0 = center + (tangent * cos(a0) + bitangent * sin(a0)) * radius
            let p1 = center + (tangent * cos(a1) + bitangent * sin(a1)) * radius
            let s0 = worldToScreen(p0, vpMatrix: vpMatrix, viewSize: viewSize)
            let s1 = worldToScreen(p1, vpMatrix: vpMatrix, viewSize: viewSize)
            let d = distancePointToSegment(point: clickPt, a: s0, b: s1)
            if d < minDist { minDist = d }
        }
        return minDist
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
              let pool = meshPool else { return }

        // Determine whether Game Viewport uses post-processing
        let camSys = state.cameraSystem
        let hasVolumePostProcess = state.postProcessVolumeSystem.hasActiveVolume
        let usePostProcess = viewportID == 1
            && camSys.allowPostProcessing
            && (camSys.usePhysicalProperties || hasVolumePostProcess)
            && postProcessStack != nil
            && hdrRenderedPipeline != nil

        let viewMatrix: simd_float4x4
        let projMatrix: simd_float4x4
        let eye: SIMD3<Float>
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)

        if viewportID == 1,
           let camEntity = state.resolvedOutputCamera,
           let tc = state.engine.world.getComponent(TransformComponent.self, from: camEntity),
           let cam = state.engine.world.getComponent(CameraComponent.self, from: camEntity) {
            let wm = tc.worldMatrix
            eye = SIMD3<Float>(wm.columns.3.x, wm.columns.3.y, wm.columns.3.z)
            let forward = -SIMD3<Float>(wm.columns.2.x, wm.columns.2.y, wm.columns.2.z)
            let up = SIMD3<Float>(wm.columns.1.x, wm.columns.1.y, wm.columns.1.z)
            viewMatrix = matrix4x4LookAt(eye: eye, target: eye + forward, up: up)

            switch cam.projection {
            case .perspective:
                projMatrix = matrix4x4PerspectiveRightHand(
                    fovyRadians: cam.effectiveFOV,
                    aspectRatio: aspect,
                    nearZ: cam.nearZ,
                    farZ: cam.farZ
                )
            case .orthographic:
                let halfH = cam.orthoSize
                let halfW = halfH * aspect
                projMatrix = matrix4x4Orthographic(
                    left: -halfW, right: halfW,
                    bottom: -halfH, top: halfH,
                    nearZ: cam.nearZ, farZ: cam.farZ
                )
            }
        } else {
            let yaw: Float
            let pitch: Float
            let dist: Float
            let target: SIMD3<Float>
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

            eye = target + SIMD3<Float>(
                dist * cos(pitch) * sin(yaw),
                dist * sin(pitch),
                dist * cos(pitch) * cos(yaw)
            )
            viewMatrix = matrix4x4LookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))

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
            activePipeline = usePostProcess ? hdrRenderedPipeline : renderedPipeline
            useWireframe = false
        }

        guard let pipeline = activePipeline else { return }

        // Object ID pass (Scene Editor only — for GPU picking and post-process outline)
        if viewportID == 0, let idPSO = objectIDPipeline, let dev = metalDevice?.device {
            let w = Int(view.drawableSize.width)
            let h = Int(view.drawableSize.height)
            ensureObjectIDTextures(width: w, height: h, device: dev)

            if let idTex = objectIDTexture, let idDepth = objectIDDepthTexture {
                let idRPD = MTLRenderPassDescriptor()
                idRPD.colorAttachments[0].texture = idTex
                idRPD.colorAttachments[0].loadAction = .clear
                idRPD.colorAttachments[0].storeAction = .store
                idRPD.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                idRPD.depthAttachment.texture = idDepth
                idRPD.depthAttachment.loadAction = .clear
                idRPD.depthAttachment.storeAction = .dontCare
                idRPD.depthAttachment.clearDepth = 1.0

                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: idRPD) {
                    enc.setFrontFacing(.counterClockwise)
                    enc.setDepthStencilState(device.depthStencilState)
                    enc.setRenderPipelineState(idPSO)

                    for drawCall in state.meshRenderSystem.drawCalls {
                        let mvp = projMatrix * viewMatrix * drawCall.worldMatrix
                        var uniforms = Uniforms(
                            mvpMatrix: mvp,
                            modelMatrix: drawCall.worldMatrix,
                            normalMatrix: drawCall.normalMatrix,
                            cameraPosition: SIMD4<Float>(eye.x, eye.y, eye.z, 0),
                            time: state.engine.totalTime
                        )
                        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        var entityID = UInt32(truncatingIfNeeded: drawCall.entity.id &+ 1)
                        enc.setFragmentBytes(&entityID, length: MemoryLayout<UInt32>.stride, index: 6)
                        enc.setCullMode(drawCall.material.renderState.cullMode.metalCullMode)

                        if let mesh = pool.mesh(for: drawCall.meshType) {
                            MeshRenderer.draw(mesh: mesh, with: enc)
                        }
                    }
                    enc.endEncoding()
                }

                if let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.synchronize(resource: idTex)
                    blit.endEncoding()
                }
            }
        }

        // Build the render pass descriptor
        let rpd: MTLRenderPassDescriptor
        if usePostProcess, let ppStack = postProcessStack {
            let w = Int(view.drawableSize.width)
            let h = Int(view.drawableSize.height)
            ppStack.ensureTextures(width: w, height: h)
            let cc = camSys.clearColor
            let clearColor = MTLClearColor(red: Double(cc.x), green: Double(cc.y), blue: Double(cc.z), alpha: Double(cc.w))
            guard let offscreenRPD = ppStack.sceneRenderPassDescriptor(clearColor: clearColor) else { return }
            rpd = offscreenRPD
        } else {
            guard let viewRPD = view.currentRenderPassDescriptor else { return }
            rpd = viewRPD
        }

        // Scene rendering pass
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            encoder.setFrontFacing(.counterClockwise)
            encoder.setDepthStencilState(device.depthStencilState)

            if viewportID == 0 && state.showGrid {
                let vpMatrix = projMatrix * viewMatrix
                gridRenderer?.draw(encoder: encoder, viewProjectionMatrix: vpMatrix)
            }

            // Skybox pass (before opaque geometry)
            drawSkybox(encoder: encoder, device: device, pool: pool,
                       viewMatrix: viewMatrix, projMatrix: projMatrix,
                       useHDR: usePostProcess)

            encoder.setDepthStencilState(device.depthStencilState)

            let usePerMaterial = (viewportID == 0 && state.sceneRenderMode == .rendered) || viewportID == 1
            if !usePerMaterial {
                encoder.setRenderPipelineState(pipeline)
            }
            if useWireframe {
                encoder.setTriangleFillMode(.lines)
            }

            var lightsData = state.lightingSystem.lights
            var lightCount = state.lightingSystem.lightCount

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

                if usePerMaterial {
                    if let materialPSO = resolveMaterialPipeline(for: drawCall.material, device: device, useHDR: usePostProcess) {
                        encoder.setRenderPipelineState(materialPSO)

                        let rs = drawCall.material.renderState
                        encoder.setCullMode(rs.cullMode.metalCullMode)
                        if let dss = materialPipelineCache?.depthStencilState(for: rs, device: device.device) {
                            encoder.setDepthStencilState(dss)
                        }
                    } else {
                        encoder.setRenderPipelineState(pipeline)
                        encoder.setCullMode(.none)
                        encoder.setDepthStencilState(device.depthStencilState)
                    }

                    // Bind PBR material properties at fragment buffer 2
                    var gpuMat = GPUMaterialProperties(from: drawCall.material.surfaceProperties)
                    encoder.setFragmentBytes(&gpuMat, length: MemoryLayout<GPUMaterialProperties>.stride, index: 2)

                    // Bind textures (or 1x1 white placeholder)
                    let placeholder = MaterialRegistry.shared.placeholderWhiteTexture
                    let registry = MaterialRegistry.shared
                    let props = drawCall.material.surfaceProperties

                    if let path = props.albedoTexturePath,
                       let tex = registry.texture(forPath: path, device: device.device) {
                        encoder.setFragmentTexture(tex, index: 0)
                    } else if let ph = placeholder {
                        encoder.setFragmentTexture(ph, index: 0)
                    }

                    if let path = props.normalMapPath,
                       let tex = registry.texture(forPath: path, device: device.device) {
                        encoder.setFragmentTexture(tex, index: 1)
                    } else if let ph = placeholder {
                        encoder.setFragmentTexture(ph, index: 1)
                    }

                    if let path = props.metallicRoughnessMapPath,
                       let tex = registry.texture(forPath: path, device: device.device) {
                        encoder.setFragmentTexture(tex, index: 2)
                    } else if let ph = placeholder {
                        encoder.setFragmentTexture(ph, index: 2)
                    }

                    if drawCall.material.needsLighting && !lightsData.isEmpty {
                        encoder.setFragmentBytes(&lightsData,
                                                 length: MemoryLayout<GPULightData>.stride * lightsData.count,
                                                 index: 3)
                        encoder.setFragmentBytes(&lightCount,
                                                 length: MemoryLayout<UInt32>.stride,
                                                 index: 4)
                    }

                    // Bind custom shader parameters at buffer 5
                    let shaderSource = drawCall.material.unifiedShaderSource ?? drawCall.material.fragmentShaderSource
                    if !shaderSource.isEmpty {
                        let shaderParams = ShaderParameterParser.parse(source: shaderSource)
                        if !shaderParams.isEmpty {
                            var packed = ShaderParameterParser.packParameters(
                                params: shaderParams,
                                values: drawCall.material.parameters
                            )
                            if !packed.isEmpty {
                                encoder.setFragmentBytes(&packed,
                                                         length: MemoryLayout<Float>.stride * packed.count,
                                                         index: 5)
                            }
                        }
                    }
                }

                if let mesh = pool.mesh(for: drawCall.meshType) {
                    MeshRenderer.draw(mesh: mesh, with: encoder)
                }
            }

            if viewportID == 0, let selected = state.selectedEntity, let dev = metalDevice?.device {
                // Post-process outline from Object ID texture
                if let olPSO = outlineCompositePipeline,
                   let idTex = objectIDTexture,
                   let noDepth = outlineNoDepthState {
                    encoder.setRenderPipelineState(olPSO)
                    encoder.setDepthStencilState(noDepth)
                    encoder.setCullMode(.none)
                    encoder.setTriangleFillMode(.fill)
                    var selectedID = UInt32(truncatingIfNeeded: selected.id &+ 1)
                    encoder.setFragmentBytes(&selectedID, length: MemoryLayout<UInt32>.stride, index: 0)
                    encoder.setFragmentTexture(idTex, index: 0)
                    MeshRenderer.drawFullscreenTriangle(with: encoder)
                    encoder.setDepthStencilState(device.depthStencilState)
                    encoder.setCullMode(.back)
                }

                if let tc = state.engine.world.getComponent(TransformComponent.self, from: selected) {
                    let cam = state.engine.world.getComponent(CameraComponent.self, from: selected)
                    let light = state.engine.world.getComponent(LightComponent.self, from: selected)
                    if cam != nil || light != nil {
                        let vpMatrix = projMatrix * viewMatrix
                        debugOverlayRenderer?.drawForEntity(
                            encoder: encoder,
                            viewProjectionMatrix: vpMatrix,
                            camera: cam,
                            light: light,
                            entityWorldMatrix: tc.worldMatrix,
                            aspectRatio: aspect,
                            device: dev
                        )
                    }
                }

                if state.sceneToolMode != .pan,
                   let tc = state.engine.world.getComponent(TransformComponent.self, from: selected) {
                    let pos = SIMD3<Float>(
                        tc.worldMatrix.columns.3.x,
                        tc.worldMatrix.columns.3.y,
                        tc.worldMatrix.columns.3.z
                    )
                    let gizmoScale = state.cameraOrbitDistance * 0.18
                    let vpMatrix = projMatrix * viewMatrix
                    let gizmoMode: GizmoRenderer.Mode
                    switch state.sceneToolMode {
                    case .translate: gizmoMode = .translate
                    case .scale:     gizmoMode = .scale
                    case .rotate:    gizmoMode = .rotate
                    case .pan:       gizmoMode = .translate
                    }
                    gizmoRenderer?.draw(
                        encoder: encoder,
                        viewProjectionMatrix: vpMatrix,
                        worldPosition: pos,
                        scale: gizmoScale,
                        mode: gizmoMode,
                        device: dev
                    )
                }
            }

            encoder.endEncoding()
        }

        // Post-processing for Game Viewport
        if usePostProcess, let ppStack = postProcessStack {
            let screenW = Float(view.drawableSize.width)
            let screenH = Float(view.drawableSize.height)

            let ppVolSys = state.postProcessVolumeSystem
            if ppVolSys.hasActiveVolume {
                let vol = ppVolSys.resolvedSettings
                var settings = VolumePostProcessSettings()

                settings.enableBloom = vol.bloom.enabled
                if settings.enableBloom {
                    settings.bloomUniforms = BloomUniforms(
                        threshold: vol.bloom.threshold, intensity: vol.bloom.intensity,
                        scatter: vol.bloom.scatter,
                        tintR: vol.bloom.tint.x, tintG: vol.bloom.tint.y, tintB: vol.bloom.tint.z,
                        screenWidth: screenW, screenHeight: screenH)
                }

                settings.enableDoF = vol.depthOfField.enabled
                if settings.enableDoF {
                    settings.ppUniforms = PostProcessUniforms(
                        exposureMultiplier: camSys.exposureMultiplier,
                        focusDistance: vol.depthOfField.focusDistance,
                        aperture: vol.depthOfField.aperture,
                        focalLengthM: vol.depthOfField.focalLength * 0.001,
                        sensorHeightM: camSys.sensorHeightMM * 0.001,
                        shutterAngle: camSys.shutterAngleValue,
                        nearZ: camSys.nearZ, farZ: camSys.farZ,
                        screenWidth: screenW, screenHeight: screenH)
                }

                let vpMatrix = projMatrix * viewMatrix
                settings.enableMotionBlur = vol.motionBlur.enabled
                if settings.enableMotionBlur {
                    settings.mbUniforms = MotionBlurUniforms(
                        viewProjectionMatrix: vpMatrix,
                        previousViewProjectionMatrix: camSys.previousViewProjectionMatrix,
                        inverseViewProjectionMatrix: vpMatrix.inverse,
                        shutterAngle: camSys.shutterAngleValue * vol.motionBlur.intensity,
                        screenWidth: screenW, screenHeight: screenH)
                }

                settings.enablePanini = vol.paniniProjection.enabled
                if settings.enablePanini {
                    settings.paniniUniforms = PaniniUniforms(
                        distance: vol.paniniProjection.distance,
                        cropToFit: vol.paniniProjection.cropToFit,
                        screenWidth: screenW, screenHeight: screenH)
                }

                let needsColorGrading = vol.colorAdjustments.enabled || vol.whiteBalance.enabled
                    || vol.channelMixer.enabled || vol.liftGammaGain.enabled
                    || vol.splitToning.enabled || vol.shadowsMidtonesHighlights.enabled
                    || vol.tonemapping.enabled
                settings.enableColorGrading = needsColorGrading
                if needsColorGrading {
                    var cg = ColorGradingUniforms()
                    if vol.colorAdjustments.enabled {
                        cg.enableColorAdjustments = 1
                        cg.postExposure = vol.colorAdjustments.postExposure
                        cg.contrast = vol.colorAdjustments.contrast
                        cg.colorFilterR = vol.colorAdjustments.colorFilter.x
                        cg.colorFilterG = vol.colorAdjustments.colorFilter.y
                        cg.colorFilterB = vol.colorAdjustments.colorFilter.z
                        cg.hueShift = vol.colorAdjustments.hueShift
                        cg.saturation = vol.colorAdjustments.saturation
                    }
                    if vol.whiteBalance.enabled {
                        cg.enableWhiteBalance = 1
                        cg.temperature = vol.whiteBalance.temperature
                        cg.wbTint = vol.whiteBalance.tint
                    }
                    if vol.channelMixer.enabled {
                        cg.enableChannelMixer = 1
                        cg.mixerRedR = vol.channelMixer.redOutRed
                        cg.mixerRedG = vol.channelMixer.redOutGreen
                        cg.mixerRedB = vol.channelMixer.redOutBlue
                        cg.mixerGreenR = vol.channelMixer.greenOutRed
                        cg.mixerGreenG = vol.channelMixer.greenOutGreen
                        cg.mixerGreenB = vol.channelMixer.greenOutBlue
                        cg.mixerBlueR = vol.channelMixer.blueOutRed
                        cg.mixerBlueG = vol.channelMixer.blueOutGreen
                        cg.mixerBlueB = vol.channelMixer.blueOutBlue
                    }
                    if vol.liftGammaGain.enabled {
                        cg.enableLGG = 1
                        cg.lift = vol.liftGammaGain.lift
                        cg.gamma = vol.liftGammaGain.gamma
                        cg.gain = vol.liftGammaGain.gain
                    }
                    if vol.splitToning.enabled {
                        cg.enableSplitToning = 1
                        cg.splitShadowR = vol.splitToning.shadowsTint.x
                        cg.splitShadowG = vol.splitToning.shadowsTint.y
                        cg.splitShadowB = vol.splitToning.shadowsTint.z
                        cg.splitHighR = vol.splitToning.highlightsTint.x
                        cg.splitHighG = vol.splitToning.highlightsTint.y
                        cg.splitHighB = vol.splitToning.highlightsTint.z
                        cg.splitBalance = vol.splitToning.balance
                    }
                    if vol.shadowsMidtonesHighlights.enabled {
                        cg.enableSMH = 1
                        cg.smhShadows = vol.shadowsMidtonesHighlights.shadows
                        cg.smhMidtones = vol.shadowsMidtonesHighlights.midtones
                        cg.smhHighlights = vol.shadowsMidtonesHighlights.highlights
                        cg.smhShadowsStart = vol.shadowsMidtonesHighlights.shadowsStart
                        cg.smhShadowsEnd = vol.shadowsMidtonesHighlights.shadowsEnd
                        cg.smhHighlightsStart = vol.shadowsMidtonesHighlights.highlightsStart
                        cg.smhHighlightsEnd = vol.shadowsMidtonesHighlights.highlightsEnd
                    }
                    if vol.tonemapping.enabled {
                        switch vol.tonemapping.mode {
                        case .none: cg.tonemappingMode = 0
                        case .neutral: cg.tonemappingMode = 1
                        case .aces: cg.tonemappingMode = 2
                        }
                    }
                    settings.colorGradingUniforms = cg
                }

                settings.enableChromaticAberration = vol.chromaticAberration.enabled
                if settings.enableChromaticAberration {
                    settings.chromaticAberrationUniforms = ChromaticAberrationUniforms(
                        intensity: vol.chromaticAberration.intensity,
                        screenWidth: screenW, screenHeight: screenH)
                }

                settings.enableLensDistortion = vol.lensDistortion.enabled
                if settings.enableLensDistortion {
                    settings.lensDistortionUniforms = LensDistortionUniforms(
                        intensity: vol.lensDistortion.intensity,
                        xMultiplier: vol.lensDistortion.xMultiplier,
                        yMultiplier: vol.lensDistortion.yMultiplier,
                        scale: vol.lensDistortion.scale,
                        centerX: vol.lensDistortion.center.x,
                        centerY: vol.lensDistortion.center.y,
                        screenWidth: screenW, screenHeight: screenH)
                }

                settings.enableVignette = vol.vignette.enabled
                if settings.enableVignette {
                    var vu = VignetteUniforms()
                    vu.colorR = vol.vignette.color.x
                    vu.colorG = vol.vignette.color.y
                    vu.colorB = vol.vignette.color.z
                    vu.intensity = vol.vignette.intensity
                    vu.centerX = vol.vignette.center.x
                    vu.centerY = vol.vignette.center.y
                    vu.smoothness = vol.vignette.smoothness
                    vu.rounded = vol.vignette.rounded ? 1 : 0
                    vu.screenWidth = screenW
                    vu.screenHeight = screenH
                    settings.vignetteUniforms = vu
                }

                settings.enableFilmGrain = vol.filmGrain.enabled
                if settings.enableFilmGrain {
                    var fg = FilmGrainUniforms()
                    fg.intensity = vol.filmGrain.intensity
                    fg.response = vol.filmGrain.response
                    switch vol.filmGrain.type {
                    case .thin: fg.grainType = 0
                    case .medium: fg.grainType = 1
                    case .large: fg.grainType = 2
                    }
                    fg.time = state.engine.totalTime
                    fg.screenWidth = screenW
                    fg.screenHeight = screenH
                    settings.filmGrainUniforms = fg
                }

                settings.enableSSAO = vol.ambientOcclusion.enabled
                if settings.enableSSAO {
                    var su = SSAOUniforms()
                    su.intensity = vol.ambientOcclusion.intensity
                    su.radius = vol.ambientOcclusion.radius
                    su.sampleCount = Float(vol.ambientOcclusion.sampleCount)
                    su.screenWidth = screenW; su.screenHeight = screenH
                    su.nearZ = camSys.nearZ; su.farZ = camSys.farZ
                    settings.ssaoUniforms = su
                }

                settings.enableFXAA = vol.antiAliasing.enabled && vol.antiAliasing.mode == .fxaa
                if settings.enableFXAA {
                    settings.fxaaUniforms = FXAAUniforms(screenWidth: screenW, screenHeight: screenH)
                }

                settings.enableFullscreenBlur = vol.fullscreenBlur.enabled
                if settings.enableFullscreenBlur {
                    var bu = FullscreenBlurUniforms()
                    bu.intensity = vol.fullscreenBlur.intensity
                    bu.radius = vol.fullscreenBlur.radius
                    bu.blurMode = vol.fullscreenBlur.mode == .highQuality ? 0 : 1
                    bu.screenWidth = screenW; bu.screenHeight = screenH
                    settings.fullscreenBlurUniforms = bu
                }

                settings.enableFullscreenOutline = vol.fullscreenOutline.enabled
                if settings.enableFullscreenOutline {
                    var ou = FullscreenOutlineUniforms()
                    switch vol.fullscreenOutline.mode {
                    case .normalBased: ou.outlineMode = 0
                    case .colorBased: ou.outlineMode = 1
                    case .depthBased: ou.outlineMode = 2
                    }
                    ou.thickness = vol.fullscreenOutline.thickness
                    ou.threshold = vol.fullscreenOutline.threshold
                    ou.colorR = vol.fullscreenOutline.color.x
                    ou.colorG = vol.fullscreenOutline.color.y
                    ou.colorB = vol.fullscreenOutline.color.z
                    ou.screenWidth = screenW; ou.screenHeight = screenH
                    ou.nearZ = camSys.nearZ; ou.farZ = camSys.farZ
                    settings.fullscreenOutlineUniforms = ou
                }

                ppStack.executeVolume(
                    commandBuffer: commandBuffer,
                    drawableTexture: drawable.texture,
                    settings: settings
                )
            } else {
                let ppUniforms = PostProcessUniforms(
                    exposureMultiplier: camSys.exposureMultiplier,
                    focusDistance: camSys.focusDistance,
                    aperture: camSys.apertureValue,
                    focalLengthM: camSys.focalLengthMM * 0.001,
                    sensorHeightM: camSys.sensorHeightMM * 0.001,
                    shutterAngle: camSys.shutterAngleValue,
                    nearZ: camSys.nearZ,
                    farZ: camSys.farZ,
                    screenWidth: screenW,
                    screenHeight: screenH
                )

                let vpMatrix = projMatrix * viewMatrix
                let mbUniforms = MotionBlurUniforms(
                    viewProjectionMatrix: vpMatrix,
                    previousViewProjectionMatrix: camSys.previousViewProjectionMatrix,
                    inverseViewProjectionMatrix: vpMatrix.inverse,
                    shutterAngle: camSys.shutterAngleValue,
                    screenWidth: screenW,
                    screenHeight: screenH
                )

                ppStack.execute(
                    commandBuffer: commandBuffer,
                    drawableTexture: drawable.texture,
                    ppUniforms: ppUniforms,
                    mbUniforms: mbUniforms,
                    enableDoF: true,
                    enableExposure: true,
                    enableMotionBlur: true
                )
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Per-Material Pipeline Resolution

    private func resolveMaterialPipeline(
        for material: MCMaterial,
        device: MCMetalDevice,
        useHDR: Bool = false
    ) -> MTLRenderPipelineState? {
        let colorFormat: MTLPixelFormat = useHDR ? .rgba16Float : .bgra8Unorm_srgb
        let registry = MaterialRegistry.shared

        if registry.isBuiltin(material.id) {
            return useHDR ? registry.hdrPipelineState(for: material.id) : registry.pipelineState(for: material.id)
        }

        if let ref = material.shaderReference, ref.hasPrefix("builtin/") {
            let builtinID: UUID
            switch ref {
            case "builtin/unlit": builtinID = MaterialRegistry.unlitMaterialID
            case "builtin/toon":  builtinID = MaterialRegistry.toonMaterialID
            default:              builtinID = MaterialRegistry.litMaterialID
            }
            return useHDR ? registry.hdrPipelineState(for: builtinID) : registry.pipelineState(for: builtinID)
        }

        let cacheKey = material.pipelineCacheKey.withHDR(useHDR)

        if let unified = material.unifiedShaderSource {
            return try? materialPipelineCache?.getOrCompile(materialKey: cacheKey) {
                try shaderCompiler!.compileUnifiedPipeline(
                    source: unified,
                    renderState: material.renderState,
                    colorFormat: colorFormat,
                    depthFormat: .depth32Float,
                    vertexDescriptor: MeshPool.metalVertexDescriptor
                )
            }
        }

        guard !material.fragmentShaderSource.isEmpty else { return nil }

        let config = material.dataFlowConfig
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let vertexSource = header + (material.vertexShaderSource
            ?? ShaderSnippets.generateDefaultVertexShader(config: config))
        let fragmentSource = header + material.fragmentShaderSource

        return try? materialPipelineCache?.getOrCompile(materialKey: cacheKey) {
            try shaderCompiler!.compilePipeline(
                vertexSource: vertexSource,
                fragmentSource: fragmentSource,
                colorFormat: colorFormat,
                depthFormat: .depth32Float,
                vertexDescriptor: MeshPool.metalVertexDescriptor
            )
        }
    }

    // MARK: - Skybox Rendering

    private func drawSkybox(
        encoder: MTLRenderCommandEncoder,
        device: MCMetalDevice,
        pool: MeshPool,
        viewMatrix: simd_float4x4,
        projMatrix: simd_float4x4,
        useHDR: Bool = false
    ) {
        let skyboxSystem = state.skyboxSystem
        guard skyboxSystem.isActive else { return }

        skyboxSystem.computeUniforms(viewMatrix: viewMatrix, projectionMatrix: projMatrix)

        // Resolve HDRI texture: scene-specific override > engine default
        let hdriTexture: MTLTexture? = resolveHDRITexture(device: device)

        let registry = MaterialRegistry.shared
        let skyboxPSO: MTLRenderPipelineState
        if hdriTexture != nil {
            if useHDR, let hdrPSO = registry.hdrPipelineState(for: MaterialRegistry.skyboxMaterialID) {
                skyboxPSO = hdrPSO
            } else if let sdrPSO = registry.pipelineState(for: MaterialRegistry.skyboxMaterialID) {
                skyboxPSO = sdrPSO
            } else {
                return
            }
        } else if useHDR, let hdrFallback = hdrSkyboxFallbackPipeline {
            skyboxPSO = hdrFallback
        } else if let fallback = skyboxFallbackPipeline {
            skyboxPSO = fallback
        } else {
            return
        }

        if let dss = MaterialRegistry.shared.depthStencilState(for: MaterialRegistry.skyboxMaterialID) {
            encoder.setDepthStencilState(dss)
        } else {
            let desc = MTLDepthStencilDescriptor()
            desc.depthCompareFunction = .lessEqual
            desc.isDepthWriteEnabled = false
            if let fallbackDSS = device.device.makeDepthStencilState(descriptor: desc) {
                skyboxDepthStencilState = fallbackDSS
                encoder.setDepthStencilState(fallbackDSS)
            }
        }

        encoder.setRenderPipelineState(skyboxPSO)
        // Skybox is viewed from inside the cube. Outward faces are front-facing;
        // cull them so only inward-facing (back) triangles remain visible.
        encoder.setCullMode(.front)

        var skyUniforms = skyboxSystem.skyboxUniforms
        encoder.setVertexBytes(&skyUniforms, length: MemoryLayout<SkyboxUniforms>.stride, index: 1)

        if let tex = hdriTexture {
            encoder.setFragmentTexture(tex, index: 0)
        }

        if let cubeMesh = pool.mesh(for: .cube) {
            MeshRenderer.draw(mesh: cubeMesh, with: encoder)
        }

        encoder.setCullMode(.back)
    }

    /// Resolves the HDRI texture for the current skybox.
    /// Priority: scene SkyboxComponent path > engine default HDRI.
    private func resolveHDRITexture(device: MCMetalDevice) -> MTLTexture? {
        if let customPath = state.skyboxSystem.hdriTexturePath,
           !customPath.isEmpty {
            if let cached = customSkyboxTexture, cachedSkyboxPath == customPath {
                return cached
            }
            let url = URL(fileURLWithPath: customPath)
            let tex = MaterialRegistry.shared.loadSkyboxTexture(from: url, device: device.device)
            customSkyboxTexture = tex
            cachedSkyboxPath = customPath
            return tex
        }
        return MaterialRegistry.shared.defaultSkyboxTexture
    }
}
#endif
