import SwiftUI
import simd
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct InspectorView: View {
    @Environment(EditorState.self) private var state

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
            VStack(alignment: .leading, spacing: 8) {
                liveVec3Row(label: "Position", entity: entity,
                    get: { state.engine.world.getComponent(TransformComponent.self, from: entity)?.transform.position ?? .zero },
                    set: { newVal in
                        state.updateComponent(TransformComponent.self, on: entity) { tc in
                            tc.transform.position = newVal
                        }
                    })
                liveVec3Row(label: "Scale", entity: entity,
                    get: { state.engine.world.getComponent(TransformComponent.self, from: entity)?.transform.scale ?? .one },
                    set: { newVal in
                        state.updateComponent(TransformComponent.self, on: entity) { tc in
                            tc.transform.scale = newVal
                        }
                    })
            }
        }
    }

    @ViewBuilder
    private func cameraSection(_ entity: Entity) -> some View {
        MCSection(title: "Camera") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Projection", selection: Binding(
                    get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.projection ?? .perspective },
                    set: { val in
                        state.updateComponent(CameraComponent.self, on: entity) { cam in
                            cam.projection = val
                        }
                    }
                )) {
                    Text("Perspective").tag(CameraComponent.Projection.perspective)
                    Text("Orthographic").tag(CameraComponent.Projection.orthographic)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                HStack {
                    Text("FOV")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: Binding(
                        get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.fov ?? 1.047 },
                        set: { val in
                            state.updateComponent(CameraComponent.self, on: entity) { cam in
                                cam.fov = val
                            }
                        }
                    ), in: 0.1...Float.pi)
                    Text(String(format: "%.2f", state.engine.world.getComponent(CameraComponent.self, from: entity)?.fov ?? 0))
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }

                liveFloatRow(label: "Near", entity: entity,
                    get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.nearZ ?? 0.1 },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.nearZ = val } })
                liveFloatRow(label: "Far", entity: entity,
                    get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.farZ ?? 1000 },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.farZ = val } })
                liveFloatRow(label: "Ortho Size", entity: entity,
                    get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.orthoSize ?? 5 },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.orthoSize = val } })

                Toggle("Active", isOn: Binding(
                    get: { state.engine.world.getComponent(CameraComponent.self, from: entity)?.isActive ?? false },
                    set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.isActive = val } }
                ))
                .foregroundStyle(MCTheme.textSecondary)
            }
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
                             set: @escaping (SIMD3<Float>) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            HStack(spacing: 6) {
                liveAxisInput("X", get: { get().x }, set: { v in var cur = get(); cur.x = v; set(cur) })
                liveAxisInput("Y", get: { get().y }, set: { v in var cur = get(); cur.y = v; set(cur) })
                liveAxisInput("Z", get: { get().z }, set: { v in var cur = get(); cur.z = v; set(cur) })
            }
        }
    }

    private func liveAxisInput(_ axis: String,
                               get: @escaping () -> Float,
                               set: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(axis)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 14)
            TextField("", value: Binding(get: get, set: set),
                      format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.plain)
                .mcInputStyle()
                .frame(width: 50)
        }
    }

    private func liveFloatRow(label: String, entity: Entity,
                              get: @escaping () -> Float,
                              set: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            TextField("", value: Binding(get: get, set: set),
                      format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.plain)
                .mcInputStyle()
                .frame(width: 60)
        }
    }

    private func meshTypeDisplay(_ type: MeshType) -> String {
        switch type {
        case .sphere: return "Sphere"
        case .cube: return "Cube"
        case .custom(let url): return "Custom: \(url.lastPathComponent)"
        }
    }
}

struct MCSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            if isExpanded {
                content()
                    .padding(.leading, MCTheme.indentWidth)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }
}
