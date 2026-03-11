import SwiftUI
import AppKit
import UniformTypeIdentifiers
import simd

// MARK: - SDF Canvas Pro View

struct SDFCanvasProView: View {
    @Environment(EditorState.self) private var editorState

    // MARK: - SDF State

    @State private var sdfTree: SDFNode = .defaultScene()
    @State private var selectedNodeID: UUID? = nil

    // MARK: - Camera State

    @State private var cameraYaw: Float = 0.5
    @State private var cameraPitch: Float = 0.3
    @State private var cameraDistance: Float = 5.0

    // MARK: - Render Settings

    @State private var maxSteps: Int = 128
    @State private var surfaceThreshold: Float = 0.001

    // MARK: - File State

    @State private var canvasName: String = "Untitled"
    @State private var currentFileURL: URL? = nil
    @State private var showingNewConfirm = false

    // MARK: - Export State

    @State private var showingExportPanel = false
    @State private var exportResolution: MeshResolution = .medium
    @State private var isExporting = false

    // MARK: - Undo

    @State private var undoStack: [SDFNode] = []
    @State private var redoStack: [SDFNode] = []
    @State private var copiedNode: SDFNode? = nil
    @State private var hoveredDropTargetID: UUID? = nil

    var body: some View {
        VStack(spacing: 8) {
            commandBar

            HSplitView {
                treePanel
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)

                viewportPanel

                propertiesPanel
                    .frame(minWidth: 240, idealWidth: 260, maxWidth: 360)
            }
        }
        .padding(8)
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasNew)) { _ in
            showingNewConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasSave)) { _ in
            saveCanvas()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasSaveAs)) { _ in
            saveCanvasAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasOpen)) { _ in
            openCanvas()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasExport)) { _ in
            showingExportPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasUndo)) { _ in
            performUndo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasRedo)) { _ in
            performRedo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasCopy)) { _ in
            copySelectedNode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdfCanvasPaste)) { _ in
            pasteNodeFromClipboard()
        }
        .alert("New Canvas", isPresented: $showingNewConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("New") { resetCanvas() }
        } message: {
            Text("Unsaved changes will be lost. Continue?")
        }
        .sheet(isPresented: $showingExportPanel) {
            exportSheet
        }
    }

    // MARK: - Command Bar

    private var commandBar: some View {
        HStack(spacing: 8) {
            Label("SDF Canvas Pro", systemImage: "cube.transparent")
                .font(MCTheme.fontBody.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            commandButton("New") { showingNewConfirm = true }
            commandButton("Open...") { openCanvas() }
            commandButton("Save") { saveCanvas() }
            commandButton("Save As...") { saveCanvasAs() }
            commandButton("Export Mesh...", accent: true) { showingExportPanel = true }
                .disabled(isExporting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func commandButton(_ title: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(accent ? .white : .white.opacity(0.75))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(accent ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tree Panel

    private var treePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(normal: "SDF", bold: "Tree")

            toolbar

            Divider().overlay(Color.white.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SDFTreeRow(
                        node: sdfTree,
                        selectedID: $selectedNodeID,
                        dropTargetID: $hoveredDropTargetID,
                        depth: 0,
                        onDropNode: moveNodeInHierarchy
                    )
                }
                .padding(8)
            }
        }
        .background(Color.black.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(PrimitiveTemplate.allCases, id: \.self) { prim in
                    Button(prim.label) { addPrimitive(prim) }
                }
            } label: {
                Label("Primitive", systemImage: "plus.circle")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)

            Menu {
                ForEach(OperationTemplate.allCases, id: \.self) { op in
                    Button(op.label) { wrapWithOperation(op) }
                }
            } label: {
                Label("Operation", systemImage: "circle.grid.cross")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)

            Menu {
                ForEach(ModifierTemplate.allCases, id: \.self) { mod in
                    Button(mod.label) { wrapWithModifier(mod) }
                }
            } label: {
                Label("Modifier", systemImage: "wand.and.stars")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)

            Spacer()

            Button {
                guard let sel = selectedNodeID else { return }
                pushUndo()
                if let newTree = sdfTree.removing(id: sel) {
                    sdfTree = newTree
                    selectedNodeID = nil
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(selectedNodeID == nil)
            .help("Delete selected node")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Viewport

    private var viewportPanel: some View {
        ZStack(alignment: .bottomLeading) {
            SDFMetalView(
                sdfTree: sdfTree,
                cameraYaw: cameraYaw,
                cameraPitch: cameraPitch,
                cameraDistance: cameraDistance,
                maxSteps: maxSteps,
                surfaceThreshold: surfaceThreshold,
                onOrbitDrag: { dx, dy in
                    let sensitivity: Float = 0.008
                    cameraYaw += dx * sensitivity
                    cameraPitch = Swift.max(
                        -Float.pi / 2 + 0.01,
                        Swift.min(Float.pi / 2 - 0.01, cameraPitch + dy * sensitivity)
                    )
                },
                onZoom: { delta in
                    cameraDistance -= delta * 0.03
                    cameraDistance = Swift.max(0.5, Swift.min(cameraDistance, 50))
                }
            )

            HStack(spacing: 8) {
                Text(canvasName)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                Text("RMB/Option+Drag Orbit  Scroll Zoom")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Properties Panel

    private var propertiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(normal: "Node", bold: "Properties")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selID = selectedNodeID,
                       let node = sdfTree.find(id: selID) {
                        nodePropertiesView(node: node)
                    } else {
                        Text("Select a node to edit")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }

                    Divider().overlay(Color.white.opacity(0.15))

                    sceneSettingsSection
                }
                .padding(12)
            }
        }
        .background(Color.black.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Node Properties

    @ViewBuilder
    private func nodePropertiesView(node: SDFNode) -> some View {
        HStack {
            Image(systemName: node.icon)
                .foregroundColor(.white.opacity(0.7))
            Text(node.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }

        switch node {
        case .sphere(let id, let radius):
            floatRow("Radius", value: radius) { newVal in
                updateNode(id: id, .sphere(id: id, radius: newVal))
            }

        case .box(let id, let size):
            vec3Row("Size", value: size) { newVal in
                updateNode(id: id, .box(id: id, size: newVal))
            }

        case .roundedBox(let id, let size, let radius):
            vec3Row("Size", value: size) { newVal in
                updateNode(id: id, .roundedBox(id: id, size: newVal, radius: radius))
            }
            floatRow("Radius", value: radius) { newVal in
                updateNode(id: id, .roundedBox(id: id, size: size, radius: newVal))
            }

        case .cylinder(let id, let radius, let height):
            floatRow("Radius", value: radius) { newVal in
                updateNode(id: id, .cylinder(id: id, radius: newVal, height: height))
            }
            floatRow("Height", value: height) { newVal in
                updateNode(id: id, .cylinder(id: id, radius: radius, height: newVal))
            }

        case .torus(let id, let major, let minor):
            floatRow("Major Radius", value: major) { newVal in
                updateNode(id: id, .torus(id: id, majorRadius: newVal, minorRadius: minor))
            }
            floatRow("Minor Radius", value: minor) { newVal in
                updateNode(id: id, .torus(id: id, majorRadius: major, minorRadius: newVal))
            }

        case .capsule(let id, let radius, let height):
            floatRow("Radius", value: radius) { newVal in
                updateNode(id: id, .capsule(id: id, radius: newVal, height: height))
            }
            floatRow("Height", value: height) { newVal in
                updateNode(id: id, .capsule(id: id, radius: radius, height: newVal))
            }

        case .cone(let id, let radius, let height):
            floatRow("Radius", value: radius) { newVal in
                updateNode(id: id, .cone(id: id, radius: newVal, height: height))
            }
            floatRow("Height", value: height) { newVal in
                updateNode(id: id, .cone(id: id, radius: radius, height: newVal))
            }

        case .smoothUnion(let id, let a, let b, let k):
            floatRow("Blend (k)", value: k, range: 0.01...2.0) { newVal in
                updateNode(id: id, .smoothUnion(id: id, a, b, k: newVal))
            }

        case .smoothSubtraction(let id, let a, let b, let k):
            floatRow("Blend (k)", value: k, range: 0.01...2.0) { newVal in
                updateNode(id: id, .smoothSubtraction(id: id, a, b, k: newVal))
            }

        case .smoothIntersection(let id, let a, let b, let k):
            floatRow("Blend (k)", value: k, range: 0.01...2.0) { newVal in
                updateNode(id: id, .smoothIntersection(id: id, a, b, k: newVal))
            }

        case .transform(let id, let child, let pos, let rot, let scl):
            vec3Row("Position", value: pos) { newVal in
                updateNode(id: id, .transform(id: id, child: child, position: newVal, rotation: rot, scale: scl))
            }
            vec3Row("Scale", value: scl) { newVal in
                updateNode(id: id, .transform(id: id, child: child, position: pos, rotation: rot, scale: newVal))
            }

        case .round(let id, let child, let radius):
            floatRow("Radius", value: radius) { newVal in
                updateNode(id: id, .round(id: id, child: child, radius: newVal))
            }

        case .onion(let id, let child, let thickness):
            floatRow("Thickness", value: thickness) { newVal in
                updateNode(id: id, .onion(id: id, child: child, thickness: newVal))
            }

        case .twist(let id, let child, let amount):
            floatRow("Amount", value: amount, range: -5...5) { newVal in
                updateNode(id: id, .twist(id: id, child: child, amount: newVal))
            }

        case .bend(let id, let child, let amount):
            floatRow("Amount", value: amount, range: -5...5) { newVal in
                updateNode(id: id, .bend(id: id, child: child, amount: newVal))
            }

        case .elongate(let id, let child, let h):
            vec3Row("Elongation", value: h) { newVal in
                updateNode(id: id, .elongate(id: id, child: child, h: newVal))
            }

        case .repeatSpace(let id, let child, let period):
            vec3Row("Period", value: period) { newVal in
                updateNode(id: id, .repeatSpace(id: id, child: child, period: newVal))
            }

        default:
            EmptyView()
        }
    }

    private var sceneSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scene Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)

            HStack {
                Text("Max Steps")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 80, alignment: .leading)
                TextField("", value: $maxSteps, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            HStack {
                Text("Threshold")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 80, alignment: .leading)
                TextField("", value: $surfaceThreshold, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
        }
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        VStack(spacing: 16) {
            Text("Export SDF as Mesh")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Picker("Resolution", selection: $exportResolution) {
                ForEach(MeshResolution.allCases, id: \.self) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .frame(width: 240)

            HStack {
                Button("Cancel") { showingExportPanel = false }
                    .keyboardShortcut(.cancelAction)

                Button("Export...") {
                    exportMesh()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }

            if isExporting {
                ProgressView("Generating mesh...")
                    .progressViewStyle(.linear)
            }
        }
        .padding(24)
        .frame(width: 320)
        .background(Color.black)
    }

    // MARK: - Property Edit Helpers

    private func floatRow(_ label: String, value: Float, range: ClosedRange<Float> = 0.01...10, onChange: @escaping (Float) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 90, alignment: .leading)
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range)
            Text(String(format: "%.3f", value))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 50)
        }
    }

    private func vec3Row(_ label: String, value: SIMD3<Float>, onChange: @escaping (SIMD3<Float>) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            HStack(spacing: 4) {
                floatField("X", value: value.x) { onChange(SIMD3($0, value.y, value.z)) }
                floatField("Y", value: value.y) { onChange(SIMD3(value.x, $0, value.z)) }
                floatField("Z", value: value.z) { onChange(SIMD3(value.x, value.y, $0)) }
            }
        }
    }

    private func floatField(_ label: String, value: Float, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
            TextField("", value: Binding(
                get: { value },
                set: { onChange($0) }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 55)
        }
    }

    // MARK: - Panel Header

    private func panelHeader(normal: String, bold: String) -> some View {
        HStack(spacing: 4) {
            Text(normal)
                .font(.system(size: 13))
                .foregroundColor(.white)
            Text(bold)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func updateNode(id: UUID, _ replacement: SDFNode) {
        pushUndo()
        sdfTree = sdfTree.replacing(id: id, with: replacement)
    }

    private func pushUndo() {
        undoStack.append(sdfTree)
        redoStack.removeAll()
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    private func addPrimitive(_ template: PrimitiveTemplate) {
        let newNode = template.create()
        pushUndo()
        if let selID = selectedNodeID, let _ = sdfTree.find(id: selID) {
            sdfTree = .smoothUnion(id: UUID(), sdfTree, newNode, k: 0.2)
        } else {
            sdfTree = .union(id: UUID(), sdfTree, newNode)
        }
        selectedNodeID = newNode.id
    }

    private func wrapWithOperation(_ op: OperationTemplate) {
        guard let selID = selectedNodeID,
              let _ = sdfTree.find(id: selID) else { return }
        pushUndo()
        let placeholder = SDFNode.sphere(id: UUID(), radius: 0.5)
        let wrapped = op.wrap(sdfTree, placeholder)
        sdfTree = wrapped
    }

    private func wrapWithModifier(_ mod: ModifierTemplate) {
        guard let selID = selectedNodeID,
              let selected = sdfTree.find(id: selID) else { return }
        pushUndo()
        let wrapped = mod.wrap(selected)
        sdfTree = sdfTree.replacing(id: selID, with: wrapped)
        selectedNodeID = wrapped.id
    }

    private func moveNodeInHierarchy(_ sourceID: UUID, _ targetID: UUID) {
        guard sourceID != targetID else { return }
        guard let movingNode = sdfTree.find(id: sourceID) else { return }
        guard movingNode.contains(id: targetID) == false else { return }

        // Remove source subtree first, then insert under target.
        guard let prunedTree = sdfTree.removing(id: sourceID) else { return }
        guard let updatedTree = prunedTree.insertingAsChild(movingNode, into: targetID) else { return }

        pushUndo()
        sdfTree = updatedTree
        selectedNodeID = sourceID
    }

    private func copySelectedNode() {
        guard let selectedNodeID,
              let node = sdfTree.find(id: selectedNodeID) else { return }
        copiedNode = node
    }

    private func pasteNodeFromClipboard() {
        guard let copiedNode else { return }
        let pasted = copiedNode.regeneratedIDs()
        pushUndo()

        if let targetID = selectedNodeID,
           let inserted = sdfTree.insertingAsChild(pasted, into: targetID) {
            sdfTree = inserted
        } else {
            sdfTree = .union(id: UUID(), sdfTree, pasted)
        }
        selectedNodeID = pasted.id
    }

    private func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(sdfTree)
        sdfTree = previous
        if let selectedNodeID, sdfTree.find(id: selectedNodeID) == nil {
            self.selectedNodeID = nil
        }
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(sdfTree)
        sdfTree = next
        if let selectedNodeID, sdfTree.find(id: selectedNodeID) == nil {
            self.selectedNodeID = nil
        }
    }

    // MARK: - File I/O

    private func resetCanvas() {
        sdfTree = .defaultScene()
        selectedNodeID = nil
        canvasName = "Untitled"
        currentFileURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func saveCanvas() {
        if let url = currentFileURL {
            writeCanvas(to: url)
        } else {
            saveCanvasAs()
        }
    }

    private func saveCanvasAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sdfCanvas]
        panel.nameFieldStringValue = canvasName + ".sdfcanvas"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            currentFileURL = url
            canvasName = url.deletingPathExtension().lastPathComponent
            writeCanvas(to: url)
        }
    }

    private func openCanvas() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sdfCanvas]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            readCanvas(from: url)
        }
    }

    private func writeCanvas(to url: URL) {
        let doc = SDFCanvasDocument(
            name: canvasName,
            tree: sdfTree,
            cameraYaw: cameraYaw,
            cameraPitch: cameraPitch,
            cameraDistance: cameraDistance,
            maxSteps: maxSteps,
            surfaceThreshold: surfaceThreshold
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(doc)
            try data.write(to: url)
        } catch {
            print("[SDFCanvas] Save failed: \(error)")
        }
    }

    private func readCanvas(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(SDFCanvasDocument.self, from: data)
            sdfTree = doc.tree
            canvasName = doc.name
            cameraYaw = doc.cameraYaw
            cameraPitch = doc.cameraPitch
            cameraDistance = doc.cameraDistance
            maxSteps = doc.maxSteps
            surfaceThreshold = doc.surfaceThreshold
            currentFileURL = url
            selectedNodeID = nil
            undoStack.removeAll()
            redoStack.removeAll()
        } catch {
            print("[SDFCanvas] Open failed: \(error)")
        }
    }

    // MARK: - Mesh Export

    private func exportMesh() {
        isExporting = true
        let tree = sdfTree
        let resolution = exportResolution.gridSize

        DispatchQueue.global(qos: .userInitiated).async {
            let mesh = MarchingCubes.extract(from: tree, gridSize: resolution)
            let usda = USDMeshExporter.export(mesh: mesh, name: canvasName)

            DispatchQueue.main.async {
                isExporting = false
                showingExportPanel = false
                exportUSDAIntoProjectMeshes(usda)
            }
        }
    }

    private func exportUSDAIntoProjectMeshes(_ usda: String) {
        guard let meshesRoot = editorState.projectManager.directoryURL(for: .meshes) else {
            print("[SDFCanvas] Meshes directory unavailable")
            return
        }

        let preferredDirectory: URL = {
            guard editorState.selectedAssetCategory == .meshes,
                  let sub = editorState.assetBrowserSubfolder,
                  !sub.isEmpty else {
                return meshesRoot
            }
            return meshesRoot.appendingPathComponent(sub, isDirectory: true)
        }()

        presentMeshesSavePanel(
            initialDirectory: preferredDirectory,
            meshesRoot: meshesRoot,
            defaultFilename: canvasName + ".usda"
        ) { url in
            guard let url else { return }
            do {
                try usda.write(to: url, atomically: true, encoding: .utf8)
                registerExportedMesh(url)
            } catch {
                print("[SDFCanvas] Export failed: \(error)")
            }
        }
    }

    private func registerExportedMesh(_ url: URL) {
        guard let root = editorState.projectManager.projectRoot,
              let relativePath = editorState.projectManager.relativePath(for: url, from: root) else {
            return
        }
        _ = editorState.projectManager.ensureMeta(for: relativePath, type: .meshes)
        editorState.selectedAssetCategory = .meshes
        editorState.refreshAssetBrowser()
    }

    private func presentMeshesSavePanel(
        initialDirectory: URL,
        meshesRoot: URL,
        defaultFilename: String,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = "Export Mesh to Project"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType(filenameExtension: "usda") ?? .plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = initialDirectory
        panel.nameFieldStringValue = defaultFilename

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            guard isInsideMeshesDirectory(url, meshesRoot: meshesRoot) else {
                showInvalidExportPathAlert(meshesRoot: meshesRoot)
                presentMeshesSavePanel(
                    initialDirectory: meshesRoot,
                    meshesRoot: meshesRoot,
                    defaultFilename: defaultFilename,
                    completion: completion
                )
                return
            }
            completion(url)
        }
    }

    private func isInsideMeshesDirectory(_ url: URL, meshesRoot: URL) -> Bool {
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        let root = meshesRoot.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : (root.path + "/")
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }

    private func showInvalidExportPathAlert(meshesRoot: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export location is restricted"
        alert.informativeText = "SDF meshes can only be exported into this project's Meshes folder:\n\(meshesRoot.path)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - SDF Tree Row

struct SDFTreeRow: View {
    let node: SDFNode
    @Binding var selectedID: UUID?
    @Binding var dropTargetID: UUID?
    let depth: Int
    let onDropNode: (UUID, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: node.icon)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .frame(width: 14)

                Text(node.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .padding(.leading, CGFloat(depth) * 16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDropTarget ? Color.blue.opacity(0.22)
                                       : isSelected ? Color.white.opacity(0.15)
                                       : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedID = node.id
            }
            .onDrag {
                selectedID = node.id
                return NSItemProvider(object: node.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: SDFTreeDropDelegate(
                    targetID: node.id,
                    currentDropTarget: $dropTargetID,
                    onDropNode: onDropNode
                )
            )

            ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
                SDFTreeRow(
                    node: child,
                    selectedID: $selectedID,
                    dropTargetID: $dropTargetID,
                    depth: depth + 1,
                    onDropNode: onDropNode
                )
            }
        }
    }

    private var isSelected: Bool { selectedID == node.id }
    private var isDropTarget: Bool { dropTargetID == node.id }
}

private struct SDFTreeDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var currentDropTarget: UUID?
    let onDropNode: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        currentDropTarget = targetID
    }

    func dropExited(info: DropInfo) {
        if currentDropTarget == targetID {
            currentDropTarget = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        currentDropTarget = nil
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let rawString: String?
            if let data = item as? Data {
                rawString = String(data: data, encoding: .utf8)
            } else if let text = item as? String {
                rawString = text
            } else if let text = item as? NSString {
                rawString = text as String
            } else {
                rawString = nil
            }

            guard let raw = rawString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let sourceID = UUID(uuidString: raw) else { return }

            DispatchQueue.main.async {
                onDropNode(sourceID, targetID)
            }
        }
        return true
    }
}

// MARK: - Templates

enum PrimitiveTemplate: CaseIterable {
    case sphere, box, roundedBox, cylinder, torus, capsule, cone

    var label: String {
        switch self {
        case .sphere:     return "Sphere"
        case .box:        return "Box"
        case .roundedBox: return "Rounded Box"
        case .cylinder:   return "Cylinder"
        case .torus:      return "Torus"
        case .capsule:    return "Capsule"
        case .cone:       return "Cone"
        }
    }

    func create() -> SDFNode {
        switch self {
        case .sphere:     return .sphere(id: UUID(), radius: 0.5)
        case .box:        return .box(id: UUID(), size: SIMD3(repeating: 1.0))
        case .roundedBox: return .roundedBox(id: UUID(), size: SIMD3(repeating: 1.0), radius: 0.1)
        case .cylinder:   return .cylinder(id: UUID(), radius: 0.5, height: 1.0)
        case .torus:      return .torus(id: UUID(), majorRadius: 0.8, minorRadius: 0.2)
        case .capsule:    return .capsule(id: UUID(), radius: 0.3, height: 1.0)
        case .cone:       return .cone(id: UUID(), radius: 0.5, height: 1.0)
        }
    }
}

enum OperationTemplate: CaseIterable {
    case union, subtraction, intersection, smoothUnion, smoothSubtraction, smoothIntersection

    var label: String {
        switch self {
        case .union:               return "Union"
        case .subtraction:         return "Subtraction"
        case .intersection:        return "Intersection"
        case .smoothUnion:         return "Smooth Union"
        case .smoothSubtraction:   return "Smooth Subtraction"
        case .smoothIntersection:  return "Smooth Intersection"
        }
    }

    func wrap(_ a: SDFNode, _ b: SDFNode) -> SDFNode {
        switch self {
        case .union:               return .union(id: UUID(), a, b)
        case .subtraction:         return .subtraction(id: UUID(), a, b)
        case .intersection:        return .intersection(id: UUID(), a, b)
        case .smoothUnion:         return .smoothUnion(id: UUID(), a, b, k: 0.2)
        case .smoothSubtraction:   return .smoothSubtraction(id: UUID(), a, b, k: 0.2)
        case .smoothIntersection:  return .smoothIntersection(id: UUID(), a, b, k: 0.2)
        }
    }
}

enum ModifierTemplate: CaseIterable {
    case transform, round, onion, twist, bend, elongate, repeatSpace

    var label: String {
        switch self {
        case .transform:   return "Transform"
        case .round:       return "Round"
        case .onion:       return "Onion"
        case .twist:       return "Twist"
        case .bend:        return "Bend"
        case .elongate:    return "Elongate"
        case .repeatSpace: return "Repeat"
        }
    }

    func wrap(_ child: SDFNode) -> SDFNode {
        switch self {
        case .transform:
            return .transform(id: UUID(), child: child,
                              position: .zero, rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), scale: SIMD3(repeating: 1))
        case .round:       return .round(id: UUID(), child: child, radius: 0.05)
        case .onion:       return .onion(id: UUID(), child: child, thickness: 0.05)
        case .twist:       return .twist(id: UUID(), child: child, amount: 1.0)
        case .bend:        return .bend(id: UUID(), child: child, amount: 1.0)
        case .elongate:    return .elongate(id: UUID(), child: child, h: SIMD3(0.2, 0, 0))
        case .repeatSpace: return .repeatSpace(id: UUID(), child: child, period: SIMD3(repeating: 3))
        }
    }
}
