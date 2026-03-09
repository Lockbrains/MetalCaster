#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterCore
import MetalCasterAsset

// MARK: - Main Shader Canvas View

struct ShaderCanvasView: View {
    @Environment(EditorState.self) private var editorState

    // MARK: - State

    @State private var activeShaders: [ActiveShader]
    @State private var editingShaderID: UUID?
    @State private var meshType: MeshType = .sphere
    @State private var dataFlowConfig: DataFlowConfig
    @State private var paramValues: [String: [Float]] = [:]
    @State private var lastCodeDefaults: [String: [Float]] = [:]
    @State private var textureSlots: [TextureSlot] = []
    @State private var sourceImagePath: String?
    @State private var canvasName: String = "Untitled Canvas"
    @State private var currentFileURL: URL?
    @State private var compilationError: String?
    @State private var isSidebarVisible = true
    @State private var showExportMaterialSheet = false
    @State private var exportMaterialName = ""

    @State private var lastDeletedShader: ActiveShader?
    @State private var lastDeletedIndex: Int = 0
    @State private var showUndoToast = false
    @State private var undoToken = UUID()

    @State private var ppEnabled = false
    @State private var selectedPPVolumeID: UInt64?
    @State private var studioLightingEnabled = true

    @State private var canvasState = ShaderCanvasState()

    /// Source URL when editing an existing .mcmat material.
    @State private var sourceMaterialURL: URL?

    init(template: ShaderCanvasTemplate) {
        let shaders = template.initialShaders()
        _activeShaders = State(initialValue: shaders)
        _dataFlowConfig = State(initialValue: template.dataFlowConfig)
        _canvasName = State(initialValue: template.rawValue)
    }

    init(material: MCMaterial, fileURL: URL) {
        let doc = material.toCanvasDocument()
        _activeShaders = State(initialValue: doc.shaders)
        _dataFlowConfig = State(initialValue: doc.dataFlow)
        _canvasName = State(initialValue: doc.name)
        _paramValues = State(initialValue: doc.paramValues)
        _meshType = State(initialValue: doc.meshType)
        _sourceMaterialURL = State(initialValue: fileURL)
    }

    // MARK: - Scene PP Volumes

    private var availablePPVolumes: [PPVolumeInfo] {
        let world = editorState.engine.world
        let entities = world.entitiesWith(PostProcessVolumeComponent.self)
        return entities.compactMap { entity in
            let name = world.getComponent(NameComponent.self, from: entity)?.name ?? "Volume"
            return PPVolumeInfo(id: entity.id, name: name)
        }
    }

    // MARK: - Derived Mode

    private var hasMeshShaders: Bool {
        activeShaders.contains { $0.category == .vertex || $0.category == .fragment }
    }

    private var hasFullscreenShaders: Bool {
        activeShaders.contains { $0.category == .fullscreen }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            metalViewport
            uiOverlay

            if let editingID = editingShaderID,
               let index = activeShaders.firstIndex(where: { $0.id == editingID }) {
                editorPanel(index: index, editingID: editingID)
            }

            if showUndoToast, let deleted = lastDeletedShader {
                undoToast(deleted)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
        .onChange(of: activeShaders) { _ in syncParamValuesFromCode(); syncToCanvasState() }
        .onChange(of: dataFlowConfig) { _ in syncToCanvasState() }
        .onChange(of: paramValues) { _ in syncToCanvasState() }
        .onChange(of: meshType) { _ in syncToCanvasState() }
        .onChange(of: sourceImagePath) { _ in syncToCanvasState() }
        .onChange(of: ppEnabled) { _ in syncToCanvasState() }
        .onChange(of: selectedPPVolumeID) { _ in syncToCanvasState() }
        .onChange(of: studioLightingEnabled) { _ in syncToCanvasState() }
        .onAppear { syncToCanvasState() }
        .onReceive(NotificationCenter.default.publisher(for: .shaderCompilationResult)) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                compilationError = notification.object as? String
            }
        }
        .sheet(isPresented: $showExportMaterialSheet) {
            exportMaterialSheet
        }
    }

    // MARK: - Metal Viewport

    private var metalViewport: some View {
        ZStack(alignment: .bottomTrailing) {
            ShaderCanvasMetalView(canvasState: canvasState)
                .ignoresSafeArea()
            CanvasFPSOverlay(canvasState: canvasState)
                .padding(8)
        }
    }

    // MARK: - UI Overlay

    private var uiOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    topBar
                    if isSidebarVisible {
                        ShaderCanvasSidebar(
                            activeShaders: $activeShaders,
                            editingShaderID: $editingShaderID,
                            dataFlowConfig: $dataFlowConfig,
                            paramValues: $paramValues,
                            textureSlots: $textureSlots,
                            ppEnabled: $ppEnabled,
                            selectedPPVolumeID: $selectedPPVolumeID,
                            availablePPVolumes: availablePPVolumes,
                            studioLightingEnabled: $studioLightingEnabled,
                            onRemoveShader: removeShader,
                            onImportTexture: importTexture
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .padding()
                Spacer()
            }
            Spacer()
            bottomToolbar
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation { isSidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title2).foregroundColor(.white)
            }.buttonStyle(.plain)

            Text(verbatim: canvasName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            toolbarActions
        }
    }

    private var isEditingMaterial: Bool { sourceMaterialURL != nil }

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            if isEditingMaterial {
                Button { performSave() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Save Material")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Save changes to .mcmat (Cmd+S)")
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    exportMaterialName = canvasName + "_Copy"
                    showExportMaterialSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("Save as New")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Save as a new .mcmat material")
            } else {
                Button { performSave() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                        Text("Save")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Save Canvas (Cmd+S)")
                .keyboardShortcut("s", modifiers: .command)

                Button { performOpen() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                        Text("Open")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Open Canvas (Cmd+O)")
                .keyboardShortcut("o", modifiers: .command)

                Divider().frame(height: 16).background(Color.white.opacity(0.2))

                Button {
                    exportMaterialName = canvasName.replacingOccurrences(of: " ", with: "_")
                    showExportMaterialSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(MCTheme.statusGreen)
                        Text("Save as Material")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Export as .mcmat material to the project")
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(alignment: .bottom) {
            shaderButtons
            Spacer()
            if hasFullscreenShaders {
                imageSelector
            } else {
                meshSelector
            }
        }
    }

    private var shaderButtons: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.headline).foregroundColor(.white)
                .padding(.trailing, 4)

            shaderButton("VS", color: .blue, category: .vertex, defaultName: "Vertex",
                         disabled: hasFullscreenShaders, help: "Vertex Shader")

            shaderButton("FS", color: .purple, category: .fragment, defaultName: "Fragment",
                         disabled: hasFullscreenShaders, help: "Fragment Shader")

            shaderButton("PP", color: .orange, category: .fullscreen, defaultName: "Fullscreen",
                         disabled: hasMeshShaders, help: "Post Processing")

            shaderButton("HF", color: .cyan, category: .helper, defaultName: "Helper",
                         disabled: false, help: "Helper Functions")
        }
        .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()
    }

    private func shaderButton(_ label: String, color: Color, category: ShaderCategory,
                              defaultName: String, disabled: Bool, help: String) -> some View {
        Button { addShader(category: category, name: defaultName) } label: {
            Text(label).fontWeight(.bold)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(disabled ? Color.gray.opacity(0.3) : color.opacity(0.8))
        .cornerRadius(8)
        .foregroundColor(disabled ? .white.opacity(0.4) : .white)
        .disabled(disabled)
        .help(help)
    }

    private var meshSelector: some View {
        HStack(spacing: 12) {
            ForEach(MeshType.builtinPrimitives, id: \.displayName) { mesh in
                Button { meshType = mesh } label: {
                    Text(mesh.displayName)
                        .font(.system(size: 11, weight: meshType == mesh ? .semibold : .regular))
                        .foregroundColor(meshType == mesh ? .blue : .white)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 14).background(Color.white.opacity(0.2))

            Button { importCustomMesh() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10))
                    Text(customMeshName ?? "Custom...")
                        .font(.system(size: 11, weight: customMeshName != nil ? .semibold : .regular))
                }
                .foregroundColor(customMeshName != nil ? .green : .white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()
    }

    @State private var customMeshName: String?

    private func importCustomMesh() {
        let panel = NSOpenPanel()
        panel.title = "Import Mesh"
        panel.allowedContentTypes = AssetCategory.meshes.acceptedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let (destURL, _) = try? editorState.projectManager.importFile(from: url, to: .meshes) {
            meshType = .custom(destURL)
            customMeshName = destURL.deletingPathExtension().lastPathComponent
            editorState.refreshAssetBrowser()
        }
    }

    private var imageSelector: some View {
        HStack(spacing: 8) {
            Image(systemName: sourceImagePath != nil ? "photo.fill" : "photo")
                .foregroundColor(sourceImagePath != nil ? .green : .white.opacity(0.5))

            Text(sourceImagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose Source Image...")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            if sourceImagePath != nil {
                Button {
                    sourceImagePath = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.7))
                }.buttonStyle(.plain)
            }
        }
        .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()
        .onTapGesture { pickSourceImage() }
    }

    private func pickSourceImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Source Image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            sourceImagePath = url.path
        }
    }

    // MARK: - Editor Panel

    private func editorPanel(index: Int, editingID: UUID) -> some View {
        HStack(spacing: 0) {
            Spacer()
            ShaderCanvasEditorView(
                shader: $activeShaders[index],
                dataFlowConfig: dataFlowConfig,
                compilationError: compilationError,
                onClose: { withAnimation { editingShaderID = nil } },
                onDismissError: { compilationError = nil }
            )
            .id(editingID)
            .frame(width: 500)
            .transition(.move(edge: .trailing))
        }
        .zIndex(1)
    }

    // MARK: - Undo Toast

    private func undoToast(_ deleted: ActiveShader) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "trash").foregroundColor(.white.opacity(0.7))
                Text("Deleted \"\(deleted.name)\"")
                    .font(.system(size: 13)).foregroundColor(.white)

                Button { undoDelete() } label: {
                    Text("Undo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.yellow)
                }.buttonStyle(.plain)

                Button {
                    withAnimation { showUndoToast = false }
                    lastDeletedShader = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .padding(.bottom, 80)
        }
        .zIndex(4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Export Material Sheet

    private var exportMaterialSheet: some View {
        VStack(spacing: 16) {
            Text("Export as Material")
                .font(.headline)
                .foregroundColor(MCTheme.textPrimary)

            TextField("Material name", text: $exportMaterialName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") { showExportMaterialSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Export") {
                    exportAsMaterial()
                    showExportMaterialSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(exportMaterialName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Shader Management

    private func addShader(category: ShaderCategory, name: String) {
        let code: String
        switch category {
        case .vertex:     code = ShaderSnippets.generateVertexDemo(config: dataFlowConfig)
        case .fragment:   code = ShaderSnippets.fragmentDemo
        case .fullscreen: code = ShaderSnippets.fullscreenDemo
        case .helper:     code = "// Define reusable MSL functions here.\n// They are injected before all shader code.\n\n"
        }
        let count = activeShaders.filter { $0.category == category }.count + 1
        let shader = ActiveShader(category: category, name: "\(name) \(count)", code: code)
        activeShaders.append(shader)
        sortShaders()
    }

    private func removeShader(_ shader: ActiveShader) {
        guard let index = activeShaders.firstIndex(where: { $0.id == shader.id }) else { return }
        lastDeletedShader = activeShaders[index]
        lastDeletedIndex = index
        if editingShaderID == shader.id { editingShaderID = nil }
        activeShaders.remove(at: index)

        let token = UUID()
        undoToken = token
        withAnimation { showUndoToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if undoToken == token {
                withAnimation { showUndoToast = false }
                lastDeletedShader = nil
            }
        }
    }

    private func undoDelete() {
        guard let shader = lastDeletedShader else { return }
        activeShaders.insert(shader, at: min(lastDeletedIndex, activeShaders.count))
        sortShaders()
        lastDeletedShader = nil
        withAnimation { showUndoToast = false }
    }

    private func sortShaders() {
        activeShaders.sort { s1, s2 in
            let order: [ShaderCategory: Int] = [.helper: 0, .vertex: 1, .fragment: 2, .fullscreen: 3]
            return (order[s1.category] ?? 0) < (order[s2.category] ?? 0)
        }
    }

    // MARK: - State Sync

    /// Re-parses `// @param` annotations from shader code and syncs `paramValues`.
    /// - New params: initialized to their code default.
    /// - Code default edited: sidebar value updated to the new default.
    /// - Sidebar-only change (code default unchanged): preserved.
    /// - Removed params: cleaned up.
    private func syncParamValuesFromCode() {
        var codeDefaults: [String: [Float]] = [:]
        for shader in activeShaders where shader.category == .fragment || shader.category == .vertex {
            for param in ShaderSnippets.parseParams(from: shader.code) {
                codeDefaults[param.name] = param.defaultValue
            }
        }

        var updated: [String: [Float]] = [:]
        for (name, newDef) in codeDefaults {
            let oldDef = lastCodeDefaults[name]
            if oldDef == nil {
                updated[name] = paramValues[name] ?? newDef
            } else if oldDef != newDef {
                updated[name] = newDef
            } else {
                updated[name] = paramValues[name] ?? newDef
            }
        }

        if updated != paramValues {
            paramValues = updated
        }
        lastCodeDefaults = codeDefaults
    }

    private func syncToCanvasState() {
        canvasState.activeShaders = activeShaders.filter { $0.category != .helper }
        canvasState.meshType = meshType
        canvasState.dataFlowConfig = dataFlowConfig
        canvasState.paramValues = paramValues
        canvasState.textureSlots = textureSlots
        canvasState.helperFunctions = activeShaders
            .filter { $0.category == .helper }
            .map(\.code)
            .joined(separator: "\n\n")
        canvasState.sourceImagePath = sourceImagePath
        canvasState.editingShaderID = editingShaderID
        canvasState.studioLightingEnabled = studioLightingEnabled
        canvasState.postProcessEnabled = ppEnabled
        canvasState.postProcessSettings = ppEnabled ? resolveCurrentPPSettings() : nil
    }

    private func resolveCurrentPPSettings() -> VolumePostProcessSettings? {
        let world = editorState.engine.world
        let entities = world.entitiesWith(PostProcessVolumeComponent.self)

        let target: Entity?
        if let selectedID = selectedPPVolumeID {
            target = entities.first { $0.id == selectedID }
        } else {
            target = entities.first
        }

        guard let entity = target,
              let vol = world.getComponent(PostProcessVolumeComponent.self, from: entity) else {
            return nil
        }

        let screenW: Float = 1920
        let screenH: Float = 1080

        var s = VolumePostProcessSettings()

        s.enableBloom = vol.bloom.enabled
        if s.enableBloom {
            s.bloomUniforms = BloomUniforms(
                threshold: vol.bloom.threshold, intensity: vol.bloom.intensity,
                scatter: vol.bloom.scatter,
                tintR: vol.bloom.tint.x, tintG: vol.bloom.tint.y, tintB: vol.bloom.tint.z,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        let needsColorGrading = vol.colorAdjustments.enabled || vol.whiteBalance.enabled
            || vol.channelMixer.enabled || vol.liftGammaGain.enabled
            || vol.splitToning.enabled || vol.shadowsMidtonesHighlights.enabled
            || vol.tonemapping.enabled
        s.enableColorGrading = needsColorGrading
        if needsColorGrading {
            var cg = ColorGradingUniforms()
            let ca = vol.colorAdjustments
            cg.postExposure = ca.postExposure; cg.contrast = ca.contrast
            cg.colorFilterR = ca.colorFilter.x; cg.colorFilterG = ca.colorFilter.y; cg.colorFilterB = ca.colorFilter.z
            cg.hueShift = ca.hueShift; cg.saturation = ca.saturation
            cg.enableColorAdjustments = ca.enabled ? 1 : 0

            let wb = vol.whiteBalance
            cg.temperature = wb.temperature; cg.wbTint = wb.tint
            cg.enableWhiteBalance = wb.enabled ? 1 : 0

            let cm = vol.channelMixer
            cg.mixerRedR = cm.redOutRed / 100; cg.mixerRedG = cm.redOutGreen / 100; cg.mixerRedB = cm.redOutBlue / 100
            cg.mixerGreenR = cm.greenOutRed / 100; cg.mixerGreenG = cm.greenOutGreen / 100; cg.mixerGreenB = cm.greenOutBlue / 100
            cg.mixerBlueR = cm.blueOutRed / 100; cg.mixerBlueG = cm.blueOutGreen / 100; cg.mixerBlueB = cm.blueOutBlue / 100
            cg.enableChannelMixer = cm.enabled ? 1 : 0

            let lgg = vol.liftGammaGain
            cg.lift = lgg.lift; cg.gamma = lgg.gamma; cg.gain = lgg.gain
            cg.enableLGG = lgg.enabled ? 1 : 0

            let st = vol.splitToning
            cg.splitShadowR = st.shadowsTint.x; cg.splitShadowG = st.shadowsTint.y; cg.splitShadowB = st.shadowsTint.z
            cg.splitHighR = st.highlightsTint.x; cg.splitHighG = st.highlightsTint.y; cg.splitHighB = st.highlightsTint.z
            cg.splitBalance = st.balance
            cg.enableSplitToning = st.enabled ? 1 : 0

            let smh = vol.shadowsMidtonesHighlights
            cg.smhShadows = smh.shadows; cg.smhMidtones = smh.midtones; cg.smhHighlights = smh.highlights
            cg.smhShadowsStart = smh.shadowsStart; cg.smhShadowsEnd = smh.shadowsEnd
            cg.smhHighlightsStart = smh.highlightsStart; cg.smhHighlightsEnd = smh.highlightsEnd
            cg.enableSMH = smh.enabled ? 1 : 0

            let tmIndex: Float = {
                switch vol.tonemapping.mode {
                case .none: return 0
                case .neutral: return 1
                case .aces: return 2
                }
            }()
            cg.tonemappingMode = vol.tonemapping.enabled ? tmIndex : 0

            s.colorGradingUniforms = cg
        }

        s.enableVignette = vol.vignette.enabled
        if s.enableVignette {
            let v = vol.vignette
            s.vignetteUniforms = VignetteUniforms()
            s.vignetteUniforms.colorR = v.color.x; s.vignetteUniforms.colorG = v.color.y; s.vignetteUniforms.colorB = v.color.z
            s.vignetteUniforms.intensity = v.intensity; s.vignetteUniforms.smoothness = v.smoothness
            s.vignetteUniforms.rounded = v.rounded ? 1 : 0
            s.vignetteUniforms.centerX = 0.5; s.vignetteUniforms.centerY = 0.5
            s.vignetteUniforms.screenWidth = screenW; s.vignetteUniforms.screenHeight = screenH
        }

        s.enableChromaticAberration = vol.chromaticAberration.enabled
        if s.enableChromaticAberration {
            s.chromaticAberrationUniforms = ChromaticAberrationUniforms(
                intensity: vol.chromaticAberration.intensity,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        s.enableFilmGrain = vol.filmGrain.enabled
        if s.enableFilmGrain {
            s.filmGrainUniforms = FilmGrainUniforms()
            s.filmGrainUniforms.intensity = vol.filmGrain.intensity
            s.filmGrainUniforms.response = vol.filmGrain.response
            let grainIndex: Float = {
                switch vol.filmGrain.type {
                case .thin: return 0
                case .medium: return 1
                case .large: return 2
                }
            }()
            s.filmGrainUniforms.grainType = grainIndex
            s.filmGrainUniforms.screenWidth = screenW; s.filmGrainUniforms.screenHeight = screenH
        }

        s.enableLensDistortion = vol.lensDistortion.enabled
        if s.enableLensDistortion {
            let ld = vol.lensDistortion
            s.lensDistortionUniforms = LensDistortionUniforms(
                intensity: ld.intensity, xMultiplier: ld.xMultiplier,
                yMultiplier: ld.yMultiplier, scale: ld.scale,
                centerX: ld.center.x, centerY: ld.center.y,
                screenWidth: screenW, screenHeight: screenH
            )
        }

        s.enableFXAA = vol.antiAliasing.enabled
        if s.enableFXAA {
            s.fxaaUniforms = FXAAUniforms(screenWidth: screenW, screenHeight: screenH)
        }

        return s
    }

    // MARK: - File IO

    private func performSave() {
        if let matURL = sourceMaterialURL {
            quickSaveMaterial(to: matURL)
        } else if let url = currentFileURL {
            saveCanvas(to: url)
        } else {
            performSaveAs()
        }
    }

    private func quickSaveMaterial(to url: URL) {
        let doc = CanvasDocument(
            name: canvasName, meshType: meshType,
            shaders: activeShaders, dataFlow: dataFlowConfig, paramValues: paramValues
        )
        let material = MCMaterial(from: doc)
        do {
            try material.save(to: url)
            editorState.reloadMaterialOnEntities(from: url, material: material)
            editorState.refreshAssetBrowser()
            print("[ShaderCanvasPro] Quick-saved material: \(url.lastPathComponent)")
        } catch {
            print("[ShaderCanvasPro] Failed to quick-save: \(error)")
        }
    }

    private func performSaveAs() {
        let panel = NSSavePanel()
        panel.title = "Save Canvas"
        panel.nameFieldStringValue = canvasName + ".shadercanvas"
        panel.allowedContentTypes = [UTType(filenameExtension: "shadercanvas") ?? .json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            saveCanvas(to: url)
        }
    }

    private func saveCanvas(to url: URL) {
        let doc = CanvasDocument(
            name: canvasName, meshType: meshType,
            shaders: activeShaders, dataFlow: dataFlowConfig, paramValues: paramValues
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(doc)
            try data.write(to: url, options: .atomic)
            currentFileURL = url
        } catch {
            print("[ShaderCanvasPro] Failed to save: \(error)")
        }
    }

    private func performOpen() {
        let panel = NSOpenPanel()
        panel.title = "Open Canvas"
        panel.allowedContentTypes = [UTType(filenameExtension: "shadercanvas") ?? .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            openCanvas(from: url)
        }
    }

    private func openCanvas(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(CanvasDocument.self, from: data)
            canvasName = doc.name
            meshType = doc.meshType
            activeShaders = doc.shaders
            dataFlowConfig = doc.dataFlow
            paramValues = doc.paramValues
            currentFileURL = url
            editingShaderID = nil
        } catch {
            print("[ShaderCanvasPro] Failed to open: \(error)")
        }
    }

    // MARK: - Asset Import

    private func importTexture(from sourceURL: URL) -> String? {
        guard let (destURL, _) = try? editorState.projectManager.importFile(from: sourceURL, to: .textures) else {
            return nil
        }
        editorState.refreshAssetBrowser()
        return destURL.path
    }

    // MARK: - Material Export

    private func exportAsMaterial() {
        let name = exportMaterialName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let doc = CanvasDocument(
            name: name, meshType: meshType,
            shaders: activeShaders, dataFlow: dataFlowConfig, paramValues: paramValues
        )
        let material = MCMaterial(from: doc)

        guard let dir = editorState.projectManager.directoryURL(for: .materials) else {
            print("[ShaderCanvasPro] Materials directory not available")
            return
        }

        let filename = name.replacingOccurrences(of: " ", with: "_") + ".mcmat"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            try material.save(to: fileURL)
            let relPath = "Materials/\(filename)"
            _ = editorState.projectManager.ensureMeta(for: relPath, type: .materials)
            sourceMaterialURL = fileURL
            editorState.reloadMaterialOnEntities(from: fileURL, material: material)
            editorState.selectedAssetCategory = .materials
            editorState.refreshAssetBrowser()
            print("[ShaderCanvasPro] Material saved: \(fileURL.lastPathComponent)")
        } catch {
            print("[ShaderCanvasPro] Failed to export material: \(error)")
        }
    }
}

// MARK: - Shader Canvas FPS Overlay

private struct CanvasFPSOverlay: View {
    let canvasState: ShaderCanvasState

    @State private var fps: Int = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("\(fps) FPS")
            .font(MCTheme.fontSmall)
            .foregroundStyle(fps >= 50 ? .green : fps >= 30 ? .yellow : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MCTheme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onReceive(timer) { _ in
                fps = canvasState.currentFPS
            }
    }
}
#endif
