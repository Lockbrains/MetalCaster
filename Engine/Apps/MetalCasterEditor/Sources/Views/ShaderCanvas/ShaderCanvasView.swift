#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import MetalCasterRenderer
import MetalCasterAsset

// MARK: - Main Shader Canvas View

/// The root view of the integrated Shader Canvas tool.
/// Combines a Metal viewport, layer sidebar, code editor, and material export.
struct ShaderCanvasView: View {
    @Environment(EditorState.self) private var editorState

    // MARK: - State

    @State private var activeShaders: [ActiveShader]
    @State private var editingShaderID: UUID?
    @State private var meshType: MeshType = .sphere
    @State private var dataFlowConfig: DataFlowConfig
    @State private var paramValues: [String: [Float]] = [:]
    @State private var textureSlots: [TextureSlot] = []
    @State private var helperFunctions: String = ""
    @State private var canvasName: String = "Untitled Canvas"
    @State private var currentFileURL: URL?
    @State private var compilationError: String?
    @State private var isSidebarVisible = true
    @State private var showSaveAsSheet = false
    @State private var showExportMaterialSheet = false
    @State private var exportMaterialName = ""

    @State private var lastDeletedShader: ActiveShader?
    @State private var lastDeletedIndex: Int = 0
    @State private var showUndoToast = false
    @State private var undoToken = UUID()

    @State private var canvasState = ShaderCanvasState()

    init(template: ShaderCanvasTemplate) {
        let shaders = template.initialShaders()
        _activeShaders = State(initialValue: shaders)
        _dataFlowConfig = State(initialValue: template.dataFlowConfig)
        _canvasName = State(initialValue: template.rawValue)
    }

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
        .onChange(of: activeShaders) { _ in syncToCanvasState() }
        .onChange(of: dataFlowConfig) { _ in syncToCanvasState() }
        .onChange(of: paramValues) { _ in syncToCanvasState() }
        .onChange(of: meshType) { _ in syncToCanvasState() }
        .onChange(of: helperFunctions) { _ in syncToCanvasState() }
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
        ShaderCanvasMetalView(canvasState: canvasState)
            .ignoresSafeArea()
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
                            helperFunctions: $helperFunctions,
                            onRemoveShader: removeShader
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

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Button {
                performSave()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Save Canvas (Cmd+S)")
            .keyboardShortcut("s", modifiers: .command)

            Button {
                performOpen()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Open Canvas (Cmd+O)")
            .keyboardShortcut("o", modifiers: .command)

            Divider().frame(height: 16).background(Color.white.opacity(0.2))

            Button {
                exportMaterialName = canvasName
                    .replacingOccurrences(of: " ", with: "_")
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

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.headline).foregroundColor(.white)
                    .padding(.trailing, 4)

                Button { addShader(category: .vertex, name: "Vertex Layer") } label: {
                    Text("VS").fontWeight(.bold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(8).foregroundColor(.white)
                .help("Vertex Shader")

                Button { addShader(category: .fragment, name: "Fragment Layer") } label: {
                    Text("FS").fontWeight(.bold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.purple.opacity(0.8))
                .cornerRadius(8).foregroundColor(.white)
                .help("Fragment Shader")

                Button { addShader(category: .fullscreen, name: "Fullscreen Layer") } label: {
                    Text("PP").fontWeight(.bold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.orange.opacity(0.8))
                .cornerRadius(8).foregroundColor(.white)
                .help("Post Processing")
            }
            .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()

            Spacer()

            meshSelector
        }
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
        }
        .padding(10).background(Color.black.opacity(0.6)).cornerRadius(12).padding()
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
            let order: [ShaderCategory: Int] = [.vertex: 0, .fragment: 1, .fullscreen: 2]
            return (order[s1.category] ?? 0) < (order[s2.category] ?? 0)
        }
    }

    // MARK: - State Sync

    private func syncToCanvasState() {
        canvasState.activeShaders = activeShaders
        canvasState.meshType = meshType
        canvasState.dataFlowConfig = dataFlowConfig
        canvasState.paramValues = paramValues
        canvasState.textureSlots = textureSlots
        canvasState.helperFunctions = helperFunctions
        canvasState.editingShaderID = editingShaderID
    }

    // MARK: - File IO

    private func performSave() {
        if let url = currentFileURL {
            saveCanvas(to: url)
        } else {
            performSaveAs()
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
            print("[ShaderCanvas] Failed to save: \(error)")
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
            print("[ShaderCanvas] Failed to open: \(error)")
        }
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
            print("[ShaderCanvas] Materials directory not available")
            return
        }

        let filename = name.replacingOccurrences(of: " ", with: "_") + ".mcmat"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            try material.save(to: fileURL)
            let relPath = "Materials/\(filename)"
            _ = editorState.projectManager.ensureMeta(for: relPath, type: .materials)
            editorState.selectedAssetCategory = .materials
            editorState.refreshAssetBrowser()
        } catch {
            print("[ShaderCanvas] Failed to export material: \(error)")
        }
    }
}
#endif
