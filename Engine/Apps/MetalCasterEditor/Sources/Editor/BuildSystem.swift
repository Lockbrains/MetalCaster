import Foundation
import Metal
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAsset

public enum TargetPlatform: String, CaseIterable {
    case macOS
    case iOS
    case tvOS
    case visionOS

    public var displayName: String {
        switch self {
        case .macOS: return "macOS"
        case .iOS: return "iOS"
        case .tvOS: return "tvOS"
        case .visionOS: return "visionOS"
        }
    }

    public var sdkName: String {
        switch self {
        case .macOS: return "macosx"
        case .iOS: return "iphoneos"
        case .tvOS: return "appletvos"
        case .visionOS: return "xros"
        }
    }
}

public struct BuildConfiguration {
    public var targetPlatform: TargetPlatform
    public var outputDirectory: URL
    public var projectName: String
    public var bundleIdentifier: String
    public var precompileShaders: Bool = true

    public init(
        targetPlatform: TargetPlatform,
        outputDirectory: URL,
        projectName: String,
        bundleIdentifier: String,
        precompileShaders: Bool = true
    ) {
        self.targetPlatform = targetPlatform
        self.outputDirectory = outputDirectory
        self.projectName = projectName
        self.bundleIdentifier = bundleIdentifier
        self.precompileShaders = precompileShaders
    }
}

public enum BuildStatus: Equatable {
    case idle
    case building(stage: String, progress: Float)
    case succeeded(outputURL: URL)
    case failed(error: String)
}

@Observable
public final class BuildSystem {
    public var status: BuildStatus = .idle
    public var buildLog: [String] = []

    private let sceneSerializer = SceneSerializer()
    private let sceneBundler = SceneBundler()
    private let fileManager = FileManager.default

    public init() {}

    public func build(scene: SceneGraph, world: World, config: BuildConfiguration, device: MTLDevice? = nil) async {
        status = .building(stage: "Initializing", progress: 0)
        buildLog.removeAll()

        do {
            log("Starting build for \(config.projectName) (\(config.targetPlatform.displayName))")

            status = .building(stage: "Serializing scene", progress: 0.1)
            let sceneData = try sceneSerializer.serialize(sceneGraph: scene, world: world)
            log("Scene serialized (\(sceneData.count) bytes)")

            status = .building(stage: "Collecting shaders", progress: 0.2)
            let shaderSources = collectShaderSources(from: world)
            log("Collected \(shaderSources.count) shader source(s)")

            var shaderLibraryURL: URL?
            if config.precompileShaders {
                #if os(macOS)
                status = .building(stage: "Precompiling shaders", progress: 0.35)
                let metalDevice = device ?? MTLCreateSystemDefaultDevice()
                guard let mtlDevice = metalDevice else {
                    throw BuildError.shaderPrecompilationFailed("No Metal device available")
                }
                let builder = ShaderLibraryBuilder(device: mtlDevice)
                let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? fileManager.removeItem(at: tempDir) }
                shaderLibraryURL = tempDir.appendingPathComponent("DefaultShaders.metallib", isDirectory: false)
                try builder.compileToMetalLib(sources: shaderSources, outputURL: shaderLibraryURL!)
                log("Shaders precompiled to \(shaderLibraryURL!.lastPathComponent)")
                #else
                log("Shader precompilation skipped (not on macOS)")
                #endif
            }

            status = .building(stage: "Bundling assets", progress: 0.5)
            let sceneName = config.projectName
            let metadata = BundleMetadata(
                engineVersion: "1.0",
                targetPlatform: config.targetPlatform.sdkName,
                createdAt: Date(),
                bundleFormatVersion: 1
            )
            let bundleConfig = BundleConfig(
                sceneName: sceneName,
                sceneData: sceneData,
                shaderLibraryURL: shaderLibraryURL,
                textureURLs: [:],
                meshURLs: [:],
                metadata: metadata
            )
            let tempBundleDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: tempBundleDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempBundleDir) }
            let tempBundleURL = tempBundleDir.appendingPathComponent("\(sceneName).mcbundle", isDirectory: true)
            try sceneBundler.bundle(config: bundleConfig, to: tempBundleURL)
            log("Bundle created")

            status = .building(stage: "Generating SPM project", progress: 0.8)
            let projectURL = try generateSPMProject(config: config, bundleURL: tempBundleURL, sceneName: sceneName)
            log("SPM project generated at \(projectURL.path)")

            status = .succeeded(outputURL: projectURL)
            log("Build succeeded")
        } catch {
            status = .failed(error: error.localizedDescription)
            log("Build failed: \(error.localizedDescription)")
        }
    }

    public func generateSPMProject(config: BuildConfiguration, bundleURL: URL, sceneName: String? = nil) throws -> URL {
        let name = config.projectName
        let projectDir = config.outputDirectory.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let sourcesDir = projectDir.appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let resourcesDir = projectDir.appendingPathComponent("Resources", isDirectory: true)
        if !fileManager.fileExists(atPath: resourcesDir.path) {
            try fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        }

        let effectiveSceneName = sceneName ?? name
        let bundleName = "\(effectiveSceneName).mcbundle"
        let bundleDest = resourcesDir.appendingPathComponent(bundleName, isDirectory: true)
        if fileManager.fileExists(atPath: bundleDest.path) {
            try fileManager.removeItem(at: bundleDest)
        }
        try fileManager.copyItem(at: bundleURL, to: bundleDest)

        let packageSwift = generatePackageSwift(config: config)
        let packageURL = projectDir.appendingPathComponent("Package.swift", isDirectory: false)
        try packageSwift.write(to: packageURL, atomically: true, encoding: .utf8)

        let mainSwift = generateMainSwift(projectName: name, sceneName: effectiveSceneName)
        let mainURL = sourcesDir.appendingPathComponent("main.swift", isDirectory: false)
        try mainSwift.write(to: mainURL, atomically: true, encoding: .utf8)

        return projectDir
    }

    public func runInEditor(scene: SceneGraph, world: World) async {
        status = .building(stage: "Preparing", progress: 0)
        buildLog.removeAll()

        do {
            _ = try sceneSerializer.serialize(sceneGraph: scene, world: world)
            log("Play mode started")
            status = .idle
        } catch {
            status = .failed(error: error.localizedDescription)
            log("Play mode failed: \(error.localizedDescription)")
        }
    }

    #if os(macOS)
    public func openInXcode(projectURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Xcode", projectURL.path]
        try? process.run()
        process.waitUntilExit()
    }
    #endif

    private func collectShaderSources(from world: World) -> [ShaderSource] {
        var seen = Set<UUID>()
        var sources: [ShaderSource] = []

        for (_, mc) in world.query(MaterialComponent.self) {
            let mat = mc.material
            if seen.contains(mat.id) { continue }
            seen.insert(mat.id)

            let header = ShaderSnippets.generateSharedHeader(config: mat.dataFlowConfig)
            let vertex = mat.vertexShaderSource ?? ShaderSnippets.generateDefaultVertexShader(config: mat.dataFlowConfig)
            let fragment = mat.fragmentShaderSource.isEmpty ? ShaderSnippets.defaultFragment : mat.fragmentShaderSource
            let msl = header + "\n" + vertex + "\n" + fragment
            sources.append(ShaderSource(name: "Material_\(mat.name.replacingOccurrences(of: " ", with: "_"))", mslSource: msl))
        }

        if sources.isEmpty {
            return ShaderLibraryBuilder.generateDefaultShaderSources()
        }

        let defaults = ShaderLibraryBuilder.generateDefaultShaderSources()
        for def in defaults {
            if !sources.contains(where: { $0.name == def.name }) {
                sources.append(def)
            }
        }
        return sources
    }

    private func generatePackageSwift(config: BuildConfiguration) -> String {
        let platform: String
        switch config.targetPlatform {
        case .macOS: platform = ".macOS(.v15)"
        case .iOS: platform = ".iOS(.v18)"
        case .tvOS: platform = ".tvOS(.v18)"
        case .visionOS: platform = ".visionOS(.v2)"
        }
        return """
        // swift-tools-version: 6.0

        import PackageDescription

        let package = Package(
            name: "\(config.projectName)",
            platforms: [\(platform)],
            dependencies: [
                .package(path: "../Engine")
            ],
            targets: [
                .executableTarget(
                    name: "\(config.projectName)",
                    dependencies: [
                        .product(name: "MetalCasterCore", package: "MetalCaster"),
                        .product(name: "MetalCasterRenderer", package: "MetalCaster"),
                        .product(name: "MetalCasterScene", package: "MetalCaster")
                    ],
                    path: "Sources/\(config.projectName)",
                    resources: [.process("Resources")],
                    swiftSettings: [.swiftLanguageMode(.v5)]
                )
            ]
        )
        """
    }

    private func generateMainSwift(projectName: String, sceneName: String) -> String {
        let safeName = projectName.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        return """
        import SwiftUI
        import simd
        import MetalCasterCore
        import MetalCasterRenderer
        import MetalCasterScene

        @Observable
        final class GameRuntime {
            let engine = Engine()
            let sceneGraph: SceneGraph
            let sceneSerializer = SceneSerializer()
            let transformSystem = TransformSystem()
            let cameraSystem = CameraSystem()
            let lightingSystem = LightingSystem()
            let meshRenderSystem = MeshRenderSystem()
            var isRunning = false

            init() {
                sceneGraph = SceneGraph(world: engine.world)
                engine.addSystem(transformSystem)
                engine.addSystem(cameraSystem)
                engine.addSystem(lightingSystem)
                engine.addSystem(meshRenderSystem)
            }

            func loadScene(from url: URL) throws {
                let data = try Data(contentsOf: url)
                try sceneSerializer.deserialize(data: data, into: engine.world, sceneGraph: sceneGraph)
            }

            func start() {
                engine.start()
                isRunning = true
            }

            func tick(deltaTime: Float) {
                guard isRunning else { return }
                engine.tick(deltaTime: deltaTime)
            }
        }

        @main
        struct \(safeName)App: App {
            @State private var runtime = GameRuntime()

            var body: some Scene {
                WindowGroup("\(projectName)") {
                    GameContentView(runtime: runtime)
                }
            }
        }

        struct GameContentView: View {
            @State var runtime: GameRuntime

            var body: some View {
                ZStack {
                    #if canImport(AppKit)
                    GameMetalView(runtime: runtime)
                    #else
                    Text("Runtime viewport")
                    #endif
                    if !runtime.isRunning {
                        VStack {
                            Text("\(projectName)")
                                .font(.title.bold())
                            Button("Start") { runtime.start() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .onAppear { loadScene() }
                .frame(minWidth: 640, minHeight: 480)
            }

            private func loadScene() {
                guard let resourceURL = Bundle.main.resourceURL else { return }
                let bundleURL = resourceURL.appendingPathComponent("\(sceneName).mcbundle", isDirectory: true)
                let sceneURL = bundleURL.appendingPathComponent("scene.mcscene", isDirectory: false)
                guard FileManager.default.fileExists(atPath: sceneURL.path) else { return }
                try? runtime.loadScene(from: sceneURL)
                runtime.start()
            }
        }

        #if canImport(AppKit)
        import MetalKit
        import Metal

        struct GameMetalView: NSViewRepresentable {
            let runtime: GameRuntime

            func makeNSView(context: Context) -> MTKView {
                let view = MTKView()
                view.device = MTLCreateSystemDefaultDevice()
                view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
                view.depthStencilPixelFormat = .depth32Float
                view.colorPixelFormat = .bgra8Unorm_srgb
                view.delegate = context.coordinator
                context.coordinator.setup(device: view.device!)
                return view
            }

            func updateNSView(_ nsView: MTKView, context: Context) {}

            func makeCoordinator() -> GameCoordinator {
                GameCoordinator(runtime: runtime)
            }
        }

        class GameCoordinator: NSObject, MTKViewDelegate {
            let runtime: GameRuntime
            var metalDevice: MCMetalDevice?
            var meshPool: MeshPool?
            var shaderCompiler: ShaderCompiler?
            var pipeline: MTLRenderPipelineState?

            init(runtime: GameRuntime) {
                self.runtime = runtime
                super.init()
            }

            func setup(device: MTLDevice) {
                metalDevice = MCMetalDevice(device: device)
                meshPool = MeshPool(device: device)
                shaderCompiler = ShaderCompiler(device: device)
                let vs = ShaderSnippets.generateSharedHeader(config: DataFlowConfig()) +
                    ShaderSnippets.generateDefaultVertexShader(config: DataFlowConfig())
                let fs = ShaderSnippets.generateSharedHeader(config: DataFlowConfig()) +
                    ShaderSnippets.defaultFragment
                pipeline = try? shaderCompiler?.compilePipeline(
                    vertexSource: vs,
                    fragmentSource: fs,
                    colorFormat: .bgra8Unorm_srgb,
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
                      let buffer = device.makeCommandBuffer(),
                      let drawable = view.currentDrawable,
                      let rpd = view.currentRenderPassDescriptor else { return }
                let cam = runtime.cameraSystem
                if let enc = buffer.makeRenderCommandEncoder(descriptor: rpd), let p = pipeline, let pool = meshPool {
                    enc.setDepthStencilState(device.depthStencilState)
                    enc.setRenderPipelineState(p)
                    for dc in runtime.meshRenderSystem.drawCalls {
                        let mvp = cam.projectionMatrix * cam.viewMatrix * dc.worldMatrix
                        let nm = simd_transpose(simd_inverse(dc.worldMatrix))
                        var u = Uniforms(
                            mvpMatrix: mvp,
                            modelMatrix: dc.worldMatrix,
                            normalMatrix: nm,
                            cameraPosition: SIMD4<Float>(cam.cameraPosition.x, cam.cameraPosition.y, cam.cameraPosition.z, 0),
                            time: runtime.engine.totalTime
                        )
                        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                        if let mesh = pool.mesh(for: dc.meshType) {
                            MeshRenderer.draw(mesh: mesh, with: enc)
                        }
                    }
                    enc.endEncoding()
                }
                buffer.present(drawable)
                buffer.commit()
            }
        }
        #endif
        """
    }

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)"
        buildLog.append(line)
    }
}

enum BuildError: LocalizedError {
    case shaderPrecompilationFailed(String)
    case projectGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .shaderPrecompilationFailed(let msg): return msg
        case .projectGenerationFailed(let msg): return msg
        }
    }
}
