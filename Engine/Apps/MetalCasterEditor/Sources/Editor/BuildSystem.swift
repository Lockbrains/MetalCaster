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
    public var isPlaying: Bool = false
    public private(set) var previewProcess: Process?

    private let sceneSerializer = SceneSerializer()
    private let sceneBundler = SceneBundler()
    private let scriptScanner = GameplayScriptScanner()
    private let fileManager = FileManager.default

    @ObservationIgnored private var _previewBuildDir: URL?
    /// Reusable temp directory for preview builds (enables incremental compilation).
    private var previewBuildDir: URL {
        if let dir = _previewBuildDir { return dir }
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("MetalCaster_Preview", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        _previewBuildDir = dir
        return dir
    }

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
            log("Build failed: \(error.localizedDescription)", level: .error)
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

    public func runInEditor(
        scene: SceneGraph,
        world: World,
        gameplayDirectories: [URL],
        enginePackagePath: URL
    ) async {
        guard !isPlaying else {
            log("Already playing — stop before starting again", level: .warning)
            return
        }

        status = .building(stage: "Preparing", progress: 0)
        buildLog.removeAll()

        do {
            // 1) Save scene to temp USDA
            status = .building(stage: "Saving scene", progress: 0.05)
            let tempSceneURL = previewBuildDir.appendingPathComponent("preview_scene.usda")
            let exporter = USDExporter()
            try exporter.writeScene(sceneGraph: scene, world: world, to: tempSceneURL)
            log("Scene saved to \(tempSceneURL.lastPathComponent)")

            // 2) Collect gameplay .swift files
            status = .building(stage: "Collecting scripts", progress: 0.15)
            let swiftFiles = collectSwiftFiles(in: gameplayDirectories)
            log("Found \(swiftFiles.count) gameplay script(s)")

            // 3) Scan for System/Component class names
            status = .building(stage: "Scanning scripts", progress: 0.25)
            let entries = scriptScanner.scan(directories: gameplayDirectories)
            let systemEntries = entries.filter { !$0.className.isEmpty }
            log("Discovered \(systemEntries.count) system(s)")

            // 4) Generate preview SPM package
            status = .building(stage: "Generating preview package", progress: 0.35)
            let projectDir = previewBuildDir.appendingPathComponent("GamePreview", isDirectory: true)
            let sourcesDir = projectDir.appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("GamePreview", isDirectory: true)
            try fileManager.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

            // Copy gameplay .swift files
            for file in swiftFiles {
                let dest = sourcesDir.appendingPathComponent(file.lastPathComponent)
                try? fileManager.removeItem(at: dest)
                try fileManager.copyItem(at: file, to: dest)
            }

            // Generate Package.swift
            let packageSwift = generatePreviewPackageSwift(enginePackagePath: enginePackagePath)
            let packageURL = projectDir.appendingPathComponent("Package.swift")
            try packageSwift.write(to: packageURL, atomically: true, encoding: .utf8)

            // Generate app entry point (NOT main.swift — @main conflicts with main.swift)
            let mainSwift = generatePreviewMainSwift(
                systems: systemEntries,
                sceneURL: tempSceneURL
            )
            let mainURL = sourcesDir.appendingPathComponent("GamePreviewApp.swift")
            try mainSwift.write(to: mainURL, atomically: true, encoding: .utf8)
            // Remove stale main.swift from previous runs
            let staleMain = sourcesDir.appendingPathComponent("main.swift")
            try? fileManager.removeItem(at: staleMain)
            log("Preview package generated at \(projectDir.path)")

            // 5) swift build
            status = .building(stage: "Compiling", progress: 0.5)
            log("Running swift build...")
            let buildProcess = Process()
            buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            buildProcess.arguments = ["build", "--package-path", projectDir.path]
            buildProcess.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            buildProcess.standardOutput = pipe
            buildProcess.standardError = pipe
            try buildProcess.run()
            buildProcess.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            for line in output.components(separatedBy: .newlines) where !line.isEmpty {
                log(line)
            }

            guard buildProcess.terminationStatus == 0 else {
                throw BuildError.projectGenerationFailed(
                    "swift build failed (exit \(buildProcess.terminationStatus))"
                )
            }
            log("Build succeeded")

            // 6) Locate and launch executable
            status = .building(stage: "Launching", progress: 0.9)
            let executableURL = locateBuiltExecutable(in: projectDir)
            guard let executableURL else {
                throw BuildError.projectGenerationFailed("Could not find built executable")
            }

            let gameProcess = Process()
            gameProcess.executableURL = executableURL
            gameProcess.arguments = [tempSceneURL.path]

            let gamePipe = Pipe()
            gameProcess.standardOutput = gamePipe
            gameProcess.standardError = gamePipe
            gamePipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: .newlines)
                    .filter { !$0.isEmpty }
                DispatchQueue.main.async {
                    for line in lines {
                        self?.log("[Preview] \(line)")
                    }
                }
            }

            gameProcess.terminationHandler = { [weak self] proc in
                gamePipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    let code = proc.terminationStatus
                    if code != 0 {
                        self?.log("[Preview] Process exited with code \(code)")
                    }
                    self?.isPlaying = false
                    self?.previewProcess = nil
                    self?.status = .idle
                    self?.log("Preview process exited")
                }
            }
            try gameProcess.run()
            previewProcess = gameProcess
            isPlaying = true
            status = .idle
            log("Game preview launched (PID \(gameProcess.processIdentifier))")

        } catch {
            status = .failed(error: error.localizedDescription)
            log("Play mode failed: \(error.localizedDescription)", level: .error)
        }
    }

    public func stopPreview() {
        guard let process = previewProcess, process.isRunning else {
            isPlaying = false
            previewProcess = nil
            return
        }
        process.terminate()
        log("Stopped preview process (PID \(process.processIdentifier))")
        isPlaying = false
        previewProcess = nil
        status = .idle
    }

    private func collectSwiftFiles(in directories: [URL]) -> [URL] {
        var files: [URL] = []
        for dir in directories where fileManager.fileExists(atPath: dir.path) {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            while let obj = enumerator.nextObject() {
                guard let fileURL = obj as? URL, fileURL.pathExtension == "swift" else { continue }
                files.append(fileURL)
            }
        }
        return files
    }

    private func locateBuiltExecutable(in projectDir: URL) -> URL? {
        let debugPath = projectDir.appendingPathComponent(".build/debug/GamePreview")
        if fileManager.isExecutableFile(atPath: debugPath.path) { return debugPath }
        let releasePath = projectDir.appendingPathComponent(".build/release/GamePreview")
        if fileManager.isExecutableFile(atPath: releasePath.path) { return releasePath }
        return nil
    }

    private func generatePreviewPackageSwift(enginePackagePath: URL) -> String {
        let pkgIdentity = enginePackagePath.lastPathComponent
        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "GamePreview",
            platforms: [.macOS(.v15)],
            dependencies: [
                .package(path: "\(enginePackagePath.path)")
            ],
            targets: [
                .executableTarget(
                    name: "GamePreview",
                    dependencies: [
                        .product(name: "MetalCasterCore", package: "\(pkgIdentity)"),
                        .product(name: "MetalCasterRenderer", package: "\(pkgIdentity)"),
                        .product(name: "MetalCasterScene", package: "\(pkgIdentity)"),
                    ],
                    path: "Sources/GamePreview",
                    swiftSettings: [.swiftLanguageMode(.v5)]
                )
            ]
        )
        """
    }

    private func generatePreviewMainSwift(
        systems: [GameplayScriptEntry],
        sceneURL: URL
    ) -> String {
        let systemRegistrations = systems.map { entry in
            "        engine.addSystem(\(entry.className)())"
        }.joined(separator: "\n")

        let scriptRefMapping = systems.map { entry in
            let name = entry.displayName
            let compName = entry.componentName ?? "\(entry.className.replacingOccurrences(of: "System", with: ""))Component"
            return "            case \"\(name)\":\n                world.addComponent(\(compName)(), to: entity)"
        }.joined(separator: "\n")

        return """
        import SwiftUI
        import simd
        import MetalCasterCore
        import MetalCasterRenderer
        import MetalCasterScene

        @Observable
        final class PreviewRuntime {
            let engine = Engine()
            let sceneGraph: SceneGraph
            let usdImporter = USDImporter()
            let hierarchySystem = HierarchySystem()
            let transformSystem = TransformSystem()
            let cameraSystem = CameraSystem()
            let lightingSystem = LightingSystem()
            let meshRenderSystem = MeshRenderSystem()
            let skyboxSystem = SkyboxSystem()
            let postProcessVolumeSystem = PostProcessVolumeSystem()

            init() {
                sceneGraph = SceneGraph(world: engine.world)
                engine.addSystem(hierarchySystem)
                engine.addSystem(transformSystem)
                engine.addSystem(cameraSystem)
                engine.addSystem(lightingSystem)
                engine.addSystem(skyboxSystem)
                engine.addSystem(meshRenderSystem)
                engine.addSystem(postProcessVolumeSystem)

        \(systemRegistrations.isEmpty ? "        // No gameplay systems discovered" : systemRegistrations)
            }

            func loadScene(from url: URL) throws {
                try usdImporter.loadScene(from: url, into: engine.world, sceneGraph: sceneGraph)
                mapScriptRefs()
            }

            private func mapScriptRefs() {
                let world = engine.world
                for (entity, ref) in world.query(GameplayScriptRef.self) {
                    switch ref.scriptName {
        \(scriptRefMapping.isEmpty ? "            default: break" : scriptRefMapping + "\n            default: break")
                    }
                }
            }

            func start() {
                engine.start()
            }
        }

        #if canImport(AppKit)
        import AppKit

        final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
            func applicationDidFinishLaunching(_ notification: Notification) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }

            func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
                true
            }
        }
        #endif

        @main
        struct GamePreviewApp: App {
            #if canImport(AppKit)
            @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) var appDelegate
            #endif
            @State private var runtime = PreviewRuntime()

            var body: some Scene {
                WindowGroup("Metal Caster — Preview") {
                    PreviewContentView(runtime: runtime)
                }
            }
        }

        struct PreviewContentView: View {
            let runtime: PreviewRuntime

            var body: some View {
                #if canImport(AppKit)
                PreviewMetalView(runtime: runtime)
                    .onAppear { loadScene() }
                    .frame(minWidth: 960, minHeight: 640)
                #else
                Text("Preview viewport")
                #endif
            }

            private func loadScene() {
                let args = CommandLine.arguments
                guard args.count > 1 else { return }
                let sceneURL = URL(fileURLWithPath: args[1])
                guard FileManager.default.fileExists(atPath: sceneURL.path) else { return }
                do {
                    try runtime.loadScene(from: sceneURL)
                } catch {
                    print("[GamePreview] Scene load error: \\(error)")
                }
                runtime.start()
            }
        }

        #if canImport(AppKit)
        import MetalKit

        struct PreviewMetalView: NSViewRepresentable {
            let runtime: PreviewRuntime

            func makeNSView(context: Context) -> MTKView {
                let view = MTKView()
                view.device = MTLCreateSystemDefaultDevice()
                view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
                view.depthStencilPixelFormat = .depth32Float
                view.colorPixelFormat = .bgra8Unorm_srgb
                let renderer = GameViewRenderer(
                    engine: runtime.engine,
                    cameraSystem: runtime.cameraSystem,
                    lightingSystem: runtime.lightingSystem,
                    meshRenderSystem: runtime.meshRenderSystem,
                    skyboxSystem: runtime.skyboxSystem,
                    postProcessVolumeSystem: runtime.postProcessVolumeSystem
                )
                renderer.setup(device: view.device!)
                view.delegate = renderer
                context.coordinator.renderer = renderer
                return view
            }

            func updateNSView(_ nsView: MTKView, context: Context) {}

            func makeCoordinator() -> Coordinator { Coordinator() }

            class Coordinator {
                var renderer: GameViewRenderer?
            }
        }
        #endif
        """
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
            let hierarchySystem = HierarchySystem()
            let transformSystem = TransformSystem()
            let cameraSystem = CameraSystem()
            let lightingSystem = LightingSystem()
            let meshRenderSystem = MeshRenderSystem()
            var isRunning = false

            init() {
                sceneGraph = SceneGraph(world: engine.world)
                engine.addSystem(hierarchySystem)
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

    private func log(_ message: String, level: MCLogLevel = .info) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)"
        buildLog.append(line)

        switch level {
        case .warning:         MCLog.warning(.editor, message)
        case .error, .fatal:   MCLog.error(.editor, message)
        default:               MCLog.info(.editor, message)
        }
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
