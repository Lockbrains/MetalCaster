import SwiftUI
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct InspectorView: View {
    @Environment(EditorState.self) private var state
    @State private var transformResetID = UUID()

    var body: some View {
        let _ = state.worldRevision
        if let entity = state.selectedEntity, state.engine.world.isAlive(entity) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if state.engine.world.hasComponent(NameComponent.self, on: entity) {
                        nameSection(entity)
                        sectionDivider()
                    }
                    if state.engine.world.hasComponent(TransformComponent.self, on: entity) {
                        transformSection(entity)
                        sectionDivider()
                    }
                    if state.engine.world.hasComponent(CameraComponent.self, on: entity) {
                        cameraSection(entity)
                        sectionDivider()
                    }
                    if state.engine.world.hasComponent(LightComponent.self, on: entity) {
                        lightSection(entity)
                        sectionDivider()
                    }
                    if state.engine.world.hasComponent(MeshComponent.self, on: entity) {
                        meshSection(entity)
                        sectionDivider()
                    }
                    addComponentSection(entity)
                }
                .padding(MCTheme.panelPadding)
            }
            .background(MCTheme.background)
        } else {
            ZStack {
                MCTheme.background
                Text("Select an entity")
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
    }

    private func sectionDivider() -> some View {
        Rectangle()
            .fill(MCTheme.panelBorder)
            .frame(height: 1)
    }

    @ViewBuilder
    private func nameSection(_ entity: Entity) -> some View {
        MCSection(title: "Name") {
            TextField("Name", text: Binding(
                get: {
                    state.engine.world.getComponent(NameComponent.self, from: entity)?.name ?? ""
                },
                set: { newName in
                    state.updateComponent(NameComponent.self, on: entity) { nc in
                        nc.name = newName
                    }
                }
            ))
            .textFieldStyle(.plain)
            .mcInputStyle()
        }
    }

    @ViewBuilder
    private func transformSection(_ entity: Entity) -> some View {
        MCSection(title: "Transform") {
            Button {
                state.updateComponent(TransformComponent.self, on: entity) { tc in
                    tc.transform = .identity
                }
                transformResetID = UUID()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Reset Transform")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                liveVec3Row(label: "Position", entity: entity,
                    get: { state.engine.world.getComponent(TransformComponent.self, from: entity)?.transform.position ?? .zero },
                    set: { newVal in
                        state.updateComponent(TransformComponent.self, on: entity) { tc in
                            tc.transform.position = newVal
                        }
                    })
                liveVec3Row(label: "Rotation", entity: entity,
                    get: {
                        let q = state.engine.world.getComponent(TransformComponent.self, from: entity)?.transform.rotation ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                        let radians = eulerFromQuaternion(q)
                        return radians * (180.0 / .pi)
                    },
                    set: { degrees in
                        let radians = degrees * (.pi / 180.0)
                        state.updateComponent(TransformComponent.self, on: entity) { tc in
                            tc.transform.rotation = quaternionFromEuler(radians)
                        }
                    },
                    step: 1.0)
                ScaleRowView(
                    currentScale: state.engine.world.getComponent(TransformComponent.self, from: entity)?.transform.scale ?? .one,
                    getScale: { state.engine.world.getComponent(TransformComponent.self, from: entity)?.transform.scale ?? .one },
                    setScale: { newScale in
                        state.updateComponent(TransformComponent.self, on: entity) { tc in
                            tc.transform.scale = newScale
                        }
                    }
                )
            }
            .id(transformResetID)
        }
    }

    @ViewBuilder
    private func cameraSection(_ entity: Entity) -> some View {
        let cam = state.engine.world.getComponent(CameraComponent.self, from: entity)

        // MARK: Projection & Base
        MCSection(title: "Camera") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Projection", selection: Binding(
                    get: { cam?.projection ?? .perspective },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.projection = val } }
                )) {
                    Text("Perspective").tag(CameraComponent.Projection.perspective)
                    Text("Orthographic").tag(CameraComponent.Projection.orthographic)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                Toggle("Physical Camera", isOn: Binding(
                    get: { cam?.usePhysicalProperties ?? false },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.usePhysicalProperties = val } }
                ))
                .foregroundStyle(MCTheme.textSecondary)

                if cam?.usePhysicalProperties != true {
                    cameraFOVRow(entity)
                }

                liveFloatRow(label: "Near", entity: entity,
                    get: { cam?.nearZ ?? 0.1 },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.nearZ = val } })
                liveFloatRow(label: "Far", entity: entity,
                    get: { cam?.farZ ?? 1000 },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.farZ = val } })

                if cam?.projection == .orthographic {
                    liveFloatRow(label: "Ortho Size", entity: entity,
                        get: { cam?.orthoSize ?? 5 },
                        set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.orthoSize = val } })
                }

                Toggle("Active", isOn: Binding(
                    get: { cam?.isActive ?? false },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.isActive = val } }
                ))
                .foregroundStyle(MCTheme.textSecondary)
            }
        }

        // MARK: Lens (Physical)
        if cam?.usePhysicalProperties == true {
            MCSection(title: "Lens") {
                VStack(alignment: .leading, spacing: 8) {
                    cameraLensSection(entity, cam: cam)
                }
            }

            MCSection(title: "Exposure") {
                VStack(alignment: .leading, spacing: 8) {
                    cameraExposureSection(entity, cam: cam)
                }
            }

            MCSection(title: "Focus") {
                VStack(alignment: .leading, spacing: 8) {
                    liveFloatRow(label: "Distance", entity: entity,
                        get: { cam?.focusDistance ?? 10.0 },
                        set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.focusDistance = max(0.1, val) } })
                    liveFloatRow(label: "Shutter Angle", entity: entity,
                        get: { cam?.shutterAngle ?? 180.0 },
                        set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.shutterAngle = max(1, min(360, val)) } })
                }
            }
        }

        // MARK: Rendering
        MCSection(title: "Rendering") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Post Processing", isOn: Binding(
                    get: { cam?.allowPostProcessing ?? true },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.allowPostProcessing = val } }
                ))
                .foregroundStyle(MCTheme.textSecondary)

                Toggle("HDR", isOn: Binding(
                    get: { cam?.allowHDR ?? true },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.allowHDR = val } }
                ))
                .foregroundStyle(MCTheme.textSecondary)

                Picker("Background", selection: Binding(
                    get: { cam?.backgroundType ?? .solidColor },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.backgroundType = val } }
                )) {
                    ForEach(CameraBackgroundType.allCases, id: \.rawValue) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                Picker("Depth Mode", selection: Binding(
                    get: { cam?.depthTextureMode ?? .depth },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.depthTextureMode = val } }
                )) {
                    ForEach(DepthTextureMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                liveFloatRow(label: "Priority", entity: entity,
                    get: { Float(cam?.renderingPriority ?? 0) },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.renderingPriority = Int(val) } })
            }
        }
    }

    // MARK: - Camera Sub-Sections

    @ViewBuilder
    private func cameraFOVRow(_ entity: Entity) -> some View {
        HStack {
            Text("FOV")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Slider(value: Binding(
                get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.fov ?? 1.047 },
                set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.fov = val } }
            ), in: 0.1...Float.pi)
            Text(String(format: "%.0f\u{00B0}", (state.engine.world.getComponent(CameraComponent.self, from: entity)?.fov ?? 1.047) * 180.0 / .pi))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func cameraLensSection(_ entity: Entity, cam: CameraComponent?) -> some View {
        // Sensor Preset
        Picker("Sensor", selection: Binding(
            get: { cam?.sensorPreset ?? .fullFrame },
            set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.sensorPreset = val } }
        )) {
            ForEach(SensorPreset.allCases) { preset in
                Text(preset.rawValue).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .foregroundStyle(MCTheme.textPrimary)

        // Focal Length
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Focal Length")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Text(String(format: "%.0f mm", cam?.focalLength ?? 50))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            Slider(value: Binding(
                get: { cam?.focalLength ?? 50.0 },
                set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.focalLength = val } }
            ), in: 8...400)
            HStack(spacing: 4) {
                ForEach(CameraComponent.commonFocalLengths, id: \.self) { fl in
                    Button(String(format: "%.0f", fl)) {
                        state.updateComponent(CameraComponent.self, on: entity) { $0.focalLength = fl }
                    }
                    .buttonStyle(.plain)
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(cam?.focalLength == fl ? MCTheme.textPrimary : MCTheme.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(cam?.focalLength == fl ? MCTheme.surfaceSelected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }

        // Computed FOV (read-only)
        HStack {
            Text("Effective FOV")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
            Text(String(format: "%.1f\u{00B0}", (cam?.physicalFOV ?? 0) * 180.0 / .pi))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func cameraExposureSection(_ entity: Entity, cam: CameraComponent?) -> some View {
        // Aperture (f-stop)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Aperture")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Text(String(format: "f/%.1f", cam?.aperture ?? 2.8))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            HStack(spacing: 4) {
                ForEach(CameraComponent.commonApertures, id: \.self) { ap in
                    Button(String(format: "%.1f", ap)) {
                        state.updateComponent(CameraComponent.self, on: entity) { $0.aperture = ap }
                    }
                    .buttonStyle(.plain)
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(cam?.aperture == ap ? MCTheme.textPrimary : MCTheme.textTertiary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(cam?.aperture == ap ? MCTheme.surfaceSelected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }

        // ISO
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ISO")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Text(String(format: "%.0f", cam?.iso ?? 200))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            HStack(spacing: 4) {
                ForEach(CameraComponent.commonISOs, id: \.self) { isoVal in
                    Button(String(format: "%.0f", isoVal)) {
                        state.updateComponent(CameraComponent.self, on: entity) { $0.iso = isoVal }
                    }
                    .buttonStyle(.plain)
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(cam?.iso == isoVal ? MCTheme.textPrimary : MCTheme.textTertiary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(cam?.iso == isoVal ? MCTheme.surfaceSelected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }

        // Shutter Speed
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Shutter Speed")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Text(CameraComponent.shutterSpeedLabel(for: cam?.shutterSpeed ?? (1.0 / 125.0)))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(CameraComponent.commonShutterSpeeds, id: \.value) { item in
                        let isSelected = abs((cam?.shutterSpeed ?? 0) - item.value) / max(item.value, 1e-6) < 0.01
                        Button(item.label) {
                            state.updateComponent(CameraComponent.self, on: entity) { $0.shutterSpeed = item.value }
                        }
                        .buttonStyle(.plain)
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(isSelected ? MCTheme.textPrimary : MCTheme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isSelected ? MCTheme.surfaceSelected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }

        // EV100 (read-only)
        HStack {
            Text("EV100")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
            Text(String(format: "%.1f", cam?.ev100 ?? 0))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func lightSection(_ entity: Entity) -> some View {
        MCSection(title: "Light") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: Binding(
                    get: { state.engine.world.getComponent(LightComponent.self, from: entity)?.type ?? .directional },
                    set: { val in state.updateComponent(LightComponent.self, on: entity) { $0.type = val } }
                )) {
                    Text("Directional").tag(LightComponent.LightType.directional)
                    Text("Point").tag(LightComponent.LightType.point)
                    Text("Spot").tag(LightComponent.LightType.spot)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                liveVec3Row(label: "Color", entity: entity,
                    get: { state.engine.world.getComponent(LightComponent.self, from: entity)?.color ?? SIMD3<Float>(1,1,1) },
                    set: { val in state.updateComponent(LightComponent.self, on: entity) { $0.color = val } })

                HStack {
                    Text("Intensity")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: Binding(
                        get: { state.engine.world.getComponent(LightComponent.self, from: entity)?.intensity ?? 1 },
                        set: { val in state.updateComponent(LightComponent.self, on: entity) { $0.intensity = val } }
                    ), in: 0...10)
                    Text(String(format: "%.2f", state.engine.world.getComponent(LightComponent.self, from: entity)?.intensity ?? 0))
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("Range")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: Binding(
                        get: { state.engine.world.getComponent(LightComponent.self, from: entity)?.range ?? 10 },
                        set: { val in state.updateComponent(LightComponent.self, on: entity) { $0.range = val } }
                    ), in: 0...100)
                    Text(String(format: "%.2f", state.engine.world.getComponent(LightComponent.self, from: entity)?.range ?? 0))
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }

                Toggle("Casts Shadows", isOn: Binding(
                    get: { state.engine.world.getComponent(LightComponent.self, from: entity)?.castsShadows ?? false },
                    set: { val in state.updateComponent(LightComponent.self, on: entity) { $0.castsShadows = val } }
                ))
                .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func meshSection(_ entity: Entity) -> some View {
        if let mc = state.engine.world.getComponent(MeshComponent.self, from: entity) {
            MCSection(title: "Mesh") {
                Text(meshTypeDisplay(mc.meshType))
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func addComponentSection(_ entity: Entity) -> some View {
        let world = state.engine.world
        HStack {
            Spacer()
            Menu("Add Component") {
                if !world.hasComponent(MeshComponent.self, on: entity) {
                    Button("Mesh") {
                        world.addComponent(MeshComponent(), to: entity)
                        world.addComponent(MaterialComponent(), to: entity)
                        state.worldRevision += 1
                    }
                }
                if !world.hasComponent(CameraComponent.self, on: entity) {
                    Button("Camera") {
                        world.addComponent(CameraComponent(), to: entity)
                        state.worldRevision += 1
                    }
                }
                if !world.hasComponent(LightComponent.self, on: entity) {
                    Button("Light") {
                        world.addComponent(LightComponent(), to: entity)
                        state.worldRevision += 1
                    }
                }
            }
            .foregroundStyle(MCTheme.textPrimary)
            Spacer()
        }
        .padding(.vertical, MCTheme.panelPadding)
    }

    // MARK: - Live Binding Helpers

    private func liveVec3Row(label: String, entity: Entity,
                             get: @escaping () -> SIMD3<Float>,
                             set: @escaping (SIMD3<Float>) -> Void,
                             step: Float = 0.1) -> some View {
        let current = get()
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            HStack(spacing: 6) {
                MCDraggableField(label: "X", displayValue: current.x,
                    getValue: { get().x },
                    onChanged: { v in var cur = get(); cur.x = v; set(cur) },
                    step: step)
                MCDraggableField(label: "Y", displayValue: current.y,
                    getValue: { get().y },
                    onChanged: { v in var cur = get(); cur.y = v; set(cur) },
                    step: step)
                MCDraggableField(label: "Z", displayValue: current.z,
                    getValue: { get().z },
                    onChanged: { v in var cur = get(); cur.z = v; set(cur) },
                    step: step)
            }
        }
    }

    private func liveFloatRow(label: String, entity: Entity,
                              get: @escaping () -> Float,
                              set: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            MCDraggableField(label: label, displayValue: get(),
                getValue: get,
                onChanged: { v in set(v) },
                step: 0.1,
                labelWidth: 70)
                .frame(width: 130)
        }
    }

    private func meshTypeDisplay(_ type: MeshType) -> String {
        switch type {
        case .custom(let url): return "Custom: \(url.lastPathComponent)"
        case .asset(let guid): return "Asset: \(guid.uuidString.prefix(8))..."
        default: return type.displayName
        }
    }
}

struct MCSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MCTheme.textTertiary)
                        Text(title)
                            .font(MCTheme.fontCaption)
                            .fontWeight(.bold)
                            .foregroundStyle(MCTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                trailing()
            }

            if isExpanded {
                content()
                    .padding(.leading, MCTheme.indentWidth)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }
}

extension MCSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = { EmptyView() }
        self.content = content
    }
}

// MARK: - Scale Row (shared state for lock-uniform display)

private struct ScaleRowView: View {
    let currentScale: SIMD3<Float>
    let getScale: () -> SIMD3<Float>
    let setScale: (SIMD3<Float>) -> Void

    @State private var isLocked = true
    @State private var localScale: SIMD3<Float>? = nil
    @State private var dragging = false
    @State private var dragOrigin: SIMD3<Float> = .one
    @State private var dragAxisOrigin: Float = 0
    @State private var editingAxis: Int = -1
    @State private var editText = ""
    @FocusState private var isFocused: Bool

    private var shown: SIMD3<Float> { localScale ?? currentScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Scale")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Button { isLocked.toggle() } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 9))
                        .foregroundStyle(isLocked ? MCTheme.textPrimary : MCTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help(isLocked ? "Uniform scale (locked)" : "Per-axis scale (unlocked)")
            }
            HStack(spacing: 6) {
                axisField("X", axis: 0)
                axisField("Y", axis: 1)
                axisField("Z", axis: 2)
            }
        }
        .onChange(of: currentScale) { _, _ in
            if !dragging { localScale = nil }
        }
    }

    private func axisField(_ label: String, axis: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 14)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active:  NSCursor.resizeLeftRight.push()
                    case .ended:   NSCursor.pop()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if !dragging {
                                dragging = true
                                dragOrigin = getScale()
                                dragAxisOrigin = comp(dragOrigin, axis)
                            }
                            let px = Float(value.translation.width)
                            let newAxisVal = dragAxisOrigin + px * 0.1 * 0.1

                            var newScale: SIMD3<Float>
                            if isLocked {
                                guard abs(dragAxisOrigin) > 0.0001 else { return }
                                let ratio = newAxisVal / dragAxisOrigin
                                newScale = dragOrigin * ratio
                            } else {
                                newScale = withComp(shown, axis, newAxisVal)
                            }
                            localScale = newScale
                            setScale(newScale)
                        }
                        .onEnded { _ in
                            localScale = getScale()
                            dragging = false
                        }
                )

            if editingAxis == axis {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .mcInputStyle()
                    .frame(width: 50)
                    .focused($isFocused)
                    .onSubmit { commitEdit(axis) }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitEdit(axis) }
                    }
                    .onAppear {
                        editText = String(format: "%.2f", comp(shown, axis))
                        isFocused = true
                    }
            } else {
                Text(String(format: "%.2f", comp(shown, axis)))
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 50, alignment: .leading)
                    .background(MCTheme.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(MCTheme.inputBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingAxis = axis }
            }
        }
    }

    private func commitEdit(_ axis: Int) {
        guard let val = Float(editText) else { editingAxis = -1; return }
        let cur = getScale()
        var newScale: SIMD3<Float>
        if isLocked {
            let oldVal = comp(cur, axis)
            guard abs(oldVal) > 0.0001 else { editingAxis = -1; return }
            newScale = cur * (val / oldVal)
        } else {
            newScale = withComp(cur, axis, val)
        }
        setScale(newScale)
        editingAxis = -1
    }

    private func comp(_ v: SIMD3<Float>, _ axis: Int) -> Float {
        axis == 0 ? v.x : (axis == 1 ? v.y : v.z)
    }

    private func withComp(_ v: SIMD3<Float>, _ axis: Int, _ val: Float) -> SIMD3<Float> {
        var r = v
        if axis == 0 { r.x = val } else if axis == 1 { r.y = val } else { r.z = val }
        return r
    }
}
