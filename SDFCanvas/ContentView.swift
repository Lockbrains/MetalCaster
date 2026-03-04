import SwiftUI
import UniformTypeIdentifiers
import simd

// MARK: - ContentView

struct ContentView: View {

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

    var body: some View {
        HSplitView {
            treePanel
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)

            viewportPanel

            propertiesPanel
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 360)
        }
        .background(Color.black)
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

    // MARK: - Tree Panel

    private var treePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(normal: "SDF", bold: "Tree")

            toolbar

            Divider().overlay(Color.white.opacity(0.15))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SDFTreeRow(node: sdfTree, selectedID: $selectedNodeID, depth: 0)
                }
                .padding(8)
            }
        }
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
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
                surfaceThreshold: surfaceThreshold
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        cameraYaw += Float(value.translation.width) * 0.005
                        cameraPitch += Float(value.translation.height) * 0.005
                        cameraPitch = Swift.min(Swift.max(cameraPitch, -Float.pi / 2 + 0.1), Float.pi / 2 - 0.1)
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        cameraDistance /= Float(value.magnification)
                        cameraDistance = Swift.max(0.5, Swift.min(cameraDistance, 50))
                    }
            )
            .onScrollGesture { delta in
                cameraDistance -= delta * 0.02
                cameraDistance = Swift.max(0.5, Swift.min(cameraDistance, 50))
            }

            Text(canvasName)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
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
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
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

                let panel = NSSavePanel()
                panel.allowedContentTypes = [UTType(filenameExtension: "usda")!]
                panel.nameFieldStringValue = canvasName + ".usda"
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    do {
                        try usda.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        print("[SDFCanvas] Export failed: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - SDF Tree Row

struct SDFTreeRow: View {
    let node: SDFNode
    @Binding var selectedID: UUID?
    let depth: Int

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
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedID = node.id
            }

            ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
                SDFTreeRow(node: child, selectedID: $selectedID, depth: depth + 1)
            }
        }
    }

    private var isSelected: Bool { selectedID == node.id }
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

// MARK: - Scroll Gesture Helper

extension View {
    func onScrollGesture(action: @escaping (Float) -> Void) -> some View {
        self.onContinuousHover { _ in }
            .background(ScrollGestureView(action: action))
    }
}

struct ScrollGestureView: NSViewRepresentable {
    let action: (Float) -> Void

    func makeNSView(context: Context) -> ScrollCaptureView {
        let view = ScrollCaptureView()
        view.onScroll = action
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
        nsView.onScroll = action
    }
}

class ScrollCaptureView: NSView {
    var onScroll: ((Float) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(Float(event.deltaY))
    }
}
