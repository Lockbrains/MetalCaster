import SwiftUI
import simd
import UniformTypeIdentifiers
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAsset

#if canImport(AppKit)
import AppKit
#endif

struct InspectorView: View {
    @Environment(EditorState.self) private var state
    @State private var transformResetID = UUID()

    var body: some View {
        let _ = state.worldRevision
        if let entity = state.selectedEntity, state.engine.world.isAlive(entity) {
            entityInspector(entity)
        } else if let assetEntry = state.selectedAssetEntry,
                  assetEntry.fileExtension == "mcmat" {
            materialAssetInspector(entry: assetEntry)
        } else {
            ZStack {
                MCTheme.background
                Text("Select an entity or asset")
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func entityInspector(_ entity: Entity) -> some View {
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
                if state.engine.world.hasComponent(MaterialComponent.self, on: entity) {
                    materialSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(SkyboxComponent.self, on: entity) {
                    skyboxSection(entity)
                    sectionDivider()
                }
                addComponentSection(entity)
            }
            .padding(MCTheme.panelPadding)
        }
        .background(MCTheme.background)
    }

    // MARK: - Material Asset Inspector

    @ViewBuilder
    private func materialAssetInspector(entry: AssetEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let mat = state.editingMaterialAsset {
                    assetMaterialHeader(entry: entry, mat: mat)
                    sectionDivider()
                    assetMaterialShaderSection(mat: mat)
                    sectionDivider()
                    assetMaterialSurfaceSection(mat: mat)
                    sectionDivider()
                    assetMaterialTextureSection(mat: mat)

                    let shaderParams = parseShaderParamsFromSource(mat: mat)
                    if !shaderParams.isEmpty {
                        sectionDivider()
                        assetMaterialShaderParamsSection(mat: mat, params: shaderParams)
                    }
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        ProgressView()
                        Text("Loading material...")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(MCTheme.panelPadding)
        }
        .background(MCTheme.background)
    }

    @ViewBuilder
    private func assetMaterialHeader(entry: AssetEntry, mat: MCMaterial) -> some View {
        MCSection(title: "Material Asset") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: Binding(
                    get: { state.editingMaterialAsset?.name ?? "" },
                    set: { newName in
                        state.editingMaterialAsset?.name = newName
                        state.saveEditingMaterialAsset()
                    }
                ))
                .textFieldStyle(.plain)
                .mcInputStyle()

                HStack {
                    Text("File")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 50, alignment: .leading)
                    Text("\(entry.name).\(entry.fileExtension)")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func assetMaterialShaderSection(mat: MCMaterial) -> some View {
        MCSection(title: "Shader") {
            ShaderPicker(
                currentShaderName: resolveShaderDisplayName(for: mat),
                onSelect: { selection in
                    applyShaderToAsset(selection)
                },
                assetDatabase: state.assetDatabase
            )
        }
    }

    private func applyShaderToAsset(_ selection: ShaderSelection) {
        let preserved = state.editingMaterialAsset?.surfaceProperties ?? MCMaterialProperties()
        let preservedParams = state.editingMaterialAsset?.parameters ?? [:]
        let preservedName = state.editingMaterialAsset?.name ?? "Material"
        let preservedID = state.editingMaterialAsset?.id ?? UUID()

        switch selection {
        case .builtin(let tag):
            let shaderRef: String
            switch tag {
            case "unlit": shaderRef = "builtin/unlit"
            case "toon":  shaderRef = "builtin/toon"
            default:      shaderRef = "builtin/lit"
            }
            state.editingMaterialAsset = MCMaterial(
                id: preservedID,
                name: preservedName,
                materialType: .custom,
                surfaceProperties: preserved,
                shaderReference: shaderRef
            )
        case .projectAsset(let entry):
            guard let url = state.assetDatabase.resolveURL(for: entry.guid),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { return }
            state.editingMaterialAsset = MCMaterial(
                id: preservedID,
                name: preservedName,
                materialType: .custom,
                unifiedShaderSource: source,
                surfaceProperties: preserved,
                shaderReference: entry.relativePath
            )
        }
        state.editingMaterialAsset?.parameters = preservedParams
        state.saveEditingMaterialAsset()
    }

    @ViewBuilder
    private func assetMaterialSurfaceSection(mat: MCMaterial) -> some View {
        let tag = materialShaderTag(for: mat)

        MCSection(title: "Surface") {
            VStack(alignment: .leading, spacing: 8) {
                assetColorRow(label: "Base Color",
                    get: { state.editingMaterialAsset?.surfaceProperties.baseColor ?? SIMD3<Float>(0.8, 0.8, 0.8) },
                    set: { state.editingMaterialAsset?.surfaceProperties.baseColor = $0; state.saveEditingMaterialAsset() })

                if tag == "lit" {
                    assetSlider(label: "Metallic", range: 0...1,
                        get: { state.editingMaterialAsset?.surfaceProperties.metallic ?? 0 },
                        set: { state.editingMaterialAsset?.surfaceProperties.metallic = $0; state.saveEditingMaterialAsset() })

                    assetSlider(label: "Roughness", range: 0.04...1,
                        get: { state.editingMaterialAsset?.surfaceProperties.roughness ?? 0.5 },
                        set: { state.editingMaterialAsset?.surfaceProperties.roughness = $0; state.saveEditingMaterialAsset() })
                }

                assetColorRow(label: "Emissive",
                    get: { state.editingMaterialAsset?.surfaceProperties.emissiveColor ?? .zero },
                    set: { state.editingMaterialAsset?.surfaceProperties.emissiveColor = $0; state.saveEditingMaterialAsset() })

                assetSlider(label: "Emissive Int.", range: 0...10,
                    get: { state.editingMaterialAsset?.surfaceProperties.emissiveIntensity ?? 0 },
                    set: { state.editingMaterialAsset?.surfaceProperties.emissiveIntensity = $0; state.saveEditingMaterialAsset() })
            }
        }
    }

    @ViewBuilder
    private func assetMaterialTextureSection(mat: MCMaterial) -> some View {
        let tag = materialShaderTag(for: mat)

        MCSection(title: "Textures") {
            VStack(alignment: .leading, spacing: 8) {
                materialTextureRow(label: "Albedo Map", entity: Entity(id: 0),
                    get: { state.editingMaterialAsset?.surfaceProperties.albedoTexturePath },
                    set: { state.editingMaterialAsset?.surfaceProperties.albedoTexturePath = $0; state.saveEditingMaterialAsset() })

                if tag == "lit" {
                    materialTextureRow(label: "Normal Map", entity: Entity(id: 0),
                        get: { state.editingMaterialAsset?.surfaceProperties.normalMapPath },
                        set: { state.editingMaterialAsset?.surfaceProperties.normalMapPath = $0; state.saveEditingMaterialAsset() })

                    materialTextureRow(label: "Metallic/Roughness", entity: Entity(id: 0),
                        get: { state.editingMaterialAsset?.surfaceProperties.metallicRoughnessMapPath },
                        set: { state.editingMaterialAsset?.surfaceProperties.metallicRoughnessMapPath = $0; state.saveEditingMaterialAsset() })
                }
            }
        }
    }

    @ViewBuilder
    private func assetMaterialShaderParamsSection(mat: MCMaterial, params: [ShaderParameter]) -> some View {
        MCSection(title: "Shader Parameters") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(params) { param in
                    assetShaderParamRow(param: param)
                }
            }
        }
    }

    @ViewBuilder
    private func assetShaderParamRow(param: ShaderParameter) -> some View {
        let values = state.editingMaterialAsset?.parameters[param.name] ?? param.defaultValue

        switch param.type {
        case .float:
            assetSlider(label: param.name, range: (param.minValue ?? 0)...(param.maxValue ?? 10),
                get: { values.first ?? param.defaultValue.first ?? 0 },
                set: { state.editingMaterialAsset?.parameters[param.name] = [$0]; state.saveEditingMaterialAsset() })
        case .color3, .color4:
            assetColorRow(label: param.name,
                get: { SIMD3<Float>(values.count > 0 ? values[0] : 1, values.count > 1 ? values[1] : 1, values.count > 2 ? values[2] : 1) },
                set: {
                    state.editingMaterialAsset?.parameters[param.name] = param.type == .color4 ? [$0.x, $0.y, $0.z, 1] : [$0.x, $0.y, $0.z]
                    state.saveEditingMaterialAsset()
                })
        default:
            EmptyView()
        }
    }

    private func parseShaderParamsFromSource(mat: MCMaterial) -> [ShaderParameter] {
        let source: String?
        if let unified = mat.unifiedShaderSource {
            source = unified
        } else if !mat.fragmentShaderSource.isEmpty {
            source = mat.fragmentShaderSource
        } else {
            source = nil
        }
        guard let src = source else { return [] }
        return ShaderParameterParser.parse(source: src)
    }

    // Asset-editing slider/color helpers (not bound to entity)

    @ViewBuilder
    private func assetSlider(label: String, range: ClosedRange<Float>,
                             get: @escaping () -> Float,
                             set: @escaping (Float) -> Void) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: get, set: set), in: range)
            Text(String(format: "%.2f", get()))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func assetColorRow(label: String,
                               get: @escaping () -> SIMD3<Float>,
                               set: @escaping (SIMD3<Float>) -> Void) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: {
                    let c = get()
                    return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
                },
                set: { newColor in
                    if let components = newColor.cgColor?.components, components.count >= 3 {
                        set(SIMD3<Float>(Float(components[0]), Float(components[1]), Float(components[2])))
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
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
    private func materialSection(_ entity: Entity) -> some View {
        let mat = state.engine.world.getComponent(MaterialComponent.self, from: entity)?.material

        MCSection(title: "Material") {
            HStack(spacing: 4) {
                Menu {
                    Section("New") {
                        Button("Lit Material") {
                            createMaterial(on: entity, basedOn: MaterialRegistry.litMaterialID, name: "Custom Lit")
                        }
                        Button("Unlit Material") {
                            createMaterial(on: entity, basedOn: MaterialRegistry.unlitMaterialID, name: "Custom Unlit")
                        }
                        Button("Toon Material") {
                            createMaterial(on: entity, basedOn: MaterialRegistry.toonMaterialID, name: "Custom Toon")
                        }
                    }

                    Divider()

                    Section("Project Materials") {
                        let entries = state.assetDatabase.entries(in: .materials, subfolder: nil)
                            .filter { $0.fileExtension == "mcmat" }
                        if entries.isEmpty {
                            Text("No materials in project")
                        } else {
                            ForEach(entries) { entry in
                                Button(entry.name) {
                                    if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                                        state.assignMaterialAsset(from: url)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Load from File...") {
                        pickMaterialFile(entity: entity)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if mat?.materialType == .custom || mat != nil {
                    Button {
                        saveMaterialToProject(mat: mat)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Save Material to Project")
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                // Material name (editable for custom)
                if mat?.materialType == .custom {
                    TextField("Name", text: Binding(
                        get: { mat?.name ?? "" },
                        set: { newName in
                            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                                mc.material.name = newName
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .mcInputStyle()
                } else {
                    HStack {
                        Text("Name")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textSecondary)
                            .frame(width: 70, alignment: .leading)
                        Text(mat?.name ?? "—")
                            .font(MCTheme.fontBody)
                            .foregroundStyle(MCTheme.textPrimary)
                    }
                }

                // Shader selector (Unity-style dropdown with full path)
                ShaderPicker(
                    currentShaderName: resolveShaderDisplayName(for: mat),
                    onSelect: { selection in
                        applyShaderSelection(selection, on: entity)
                    },
                    assetDatabase: state.assetDatabase
                )

                sectionDivider()

                // Base Color
                materialColorRow(label: "Base Color", entity: entity,
                    get: { mat?.surfaceProperties.baseColor ?? SIMD3<Float>(0.8, 0.8, 0.8) },
                    set: { color in
                        state.updateComponent(MaterialComponent.self, on: entity) { mc in
                            mc.material.surfaceProperties.baseColor = color
                        }
                    })

                // PBR sliders (Lit and Toon only)
                if materialShaderTag(for: mat) == "lit" {
                    materialSlider(label: "Metallic", entity: entity, range: 0...1,
                        get: { mat?.surfaceProperties.metallic ?? 0 },
                        set: { val in
                            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                                mc.material.surfaceProperties.metallic = val
                            }
                        })

                    materialSlider(label: "Roughness", entity: entity, range: 0.04...1,
                        get: { mat?.surfaceProperties.roughness ?? 0.5 },
                        set: { val in
                            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                                mc.material.surfaceProperties.roughness = val
                            }
                        })
                }

                // Emissive
                materialColorRow(label: "Emissive", entity: entity,
                    get: { mat?.surfaceProperties.emissiveColor ?? .zero },
                    set: { color in
                        state.updateComponent(MaterialComponent.self, on: entity) { mc in
                            mc.material.surfaceProperties.emissiveColor = color
                        }
                    })

                materialSlider(label: "Emissive Intensity", entity: entity, range: 0...10,
                    get: { mat?.surfaceProperties.emissiveIntensity ?? 0 },
                    set: { val in
                        state.updateComponent(MaterialComponent.self, on: entity) { mc in
                            mc.material.surfaceProperties.emissiveIntensity = val
                        }
                    })

                sectionDivider()

                // Texture slots
                materialTextureRow(label: "Albedo Map", entity: entity,
                    get: { mat?.surfaceProperties.albedoTexturePath },
                    set: { path in
                        state.updateComponent(MaterialComponent.self, on: entity) { mc in
                            mc.material.surfaceProperties.albedoTexturePath = path
                        }
                    })

                if materialShaderTag(for: mat) == "lit" {
                    materialTextureRow(label: "Normal Map", entity: entity,
                        get: { mat?.surfaceProperties.normalMapPath },
                        set: { path in
                            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                                mc.material.surfaceProperties.normalMapPath = path
                            }
                        })

                    materialTextureRow(label: "Metallic/Roughness", entity: entity,
                        get: { mat?.surfaceProperties.metallicRoughnessMapPath },
                        set: { path in
                            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                                mc.material.surfaceProperties.metallicRoughnessMapPath = path
                            }
                        })
                }

                // Custom shader parameters (parsed from @param annotations)
                if let shaderParams = parseShaderParams(from: mat),
                   !shaderParams.isEmpty {
                    sectionDivider()

                    Text("Shader Parameters")
                        .font(MCTheme.fontCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(MCTheme.textSecondary)

                    ForEach(shaderParams) { param in
                        shaderParameterRow(param: param, entity: entity, mat: mat)
                    }
                }

                sectionDivider()

                // Render state info
                HStack {
                    Text("Blend")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Text(mat?.renderState.blendMode.rawValue.capitalized ?? "Opaque")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textTertiary)
                }
            }
        }
    }

    private func parseShaderParams(from mat: MCMaterial?) -> [ShaderParameter]? {
        let source: String?
        if let unified = mat?.unifiedShaderSource {
            source = unified
        } else if let frag = mat?.fragmentShaderSource, !frag.isEmpty {
            source = frag
        } else {
            source = nil
        }
        guard let src = source else { return nil }
        return ShaderParameterParser.parse(source: src)
    }

    @ViewBuilder
    private func shaderParameterRow(param: ShaderParameter, entity: Entity, mat: MCMaterial?) -> some View {
        let values = mat?.parameters[param.name] ?? param.defaultValue

        switch param.type {
        case .float:
            materialSlider(
                label: param.name, entity: entity,
                range: (param.minValue ?? 0)...(param.maxValue ?? 10),
                get: { values.first ?? param.defaultValue.first ?? 0 },
                set: { val in
                    state.updateComponent(MaterialComponent.self, on: entity) { mc in
                        mc.material.parameters[param.name] = [val]
                    }
                })

        case .float2:
            liveVec3Row(label: param.name, entity: entity,
                get: {
                    let v = mat?.parameters[param.name] ?? param.defaultValue
                    return SIMD3<Float>(v.count > 0 ? v[0] : 0, v.count > 1 ? v[1] : 0, 0)
                },
                set: { newVal in
                    state.updateComponent(MaterialComponent.self, on: entity) { mc in
                        mc.material.parameters[param.name] = [newVal.x, newVal.y]
                    }
                })

        case .color3, .color4:
            materialColorRow(label: param.name, entity: entity,
                get: {
                    let v = mat?.parameters[param.name] ?? param.defaultValue
                    return SIMD3<Float>(v.count > 0 ? v[0] : 1, v.count > 1 ? v[1] : 1, v.count > 2 ? v[2] : 1)
                },
                set: { color in
                    state.updateComponent(MaterialComponent.self, on: entity) { mc in
                        if param.type == .color4 {
                            mc.material.parameters[param.name] = [color.x, color.y, color.z, 1.0]
                        } else {
                            mc.material.parameters[param.name] = [color.x, color.y, color.z]
                        }
                    }
                })

        case .float3:
            liveVec3Row(label: param.name, entity: entity,
                get: {
                    let v = mat?.parameters[param.name] ?? param.defaultValue
                    return SIMD3<Float>(v.count > 0 ? v[0] : 0, v.count > 1 ? v[1] : 0, v.count > 2 ? v[2] : 0)
                },
                set: { newVal in
                    state.updateComponent(MaterialComponent.self, on: entity) { mc in
                        mc.material.parameters[param.name] = [newVal.x, newVal.y, newVal.z]
                    }
                })

        case .float4:
            liveVec3Row(label: "\(param.name) (xyz)", entity: entity,
                get: {
                    let v = mat?.parameters[param.name] ?? param.defaultValue
                    return SIMD3<Float>(v.count > 0 ? v[0] : 0, v.count > 1 ? v[1] : 0, v.count > 2 ? v[2] : 0)
                },
                set: { newVal in
                    state.updateComponent(MaterialComponent.self, on: entity) { mc in
                        var v = mc.material.parameters[param.name] ?? param.defaultValue
                        while v.count < 4 { v.append(0) }
                        v[0] = newVal.x; v[1] = newVal.y; v[2] = newVal.z
                        mc.material.parameters[param.name] = v
                    }
                })
        }
    }

    // MARK: - Material Helpers

    private func resolveShaderDisplayName(for mat: MCMaterial?) -> String {
        guard let mat else { return "Built-in/Lit" }

        if let ref = mat.shaderReference, !ref.isEmpty {
            switch ref {
            case "builtin/lit":   return "Built-in/Lit"
            case "builtin/unlit": return "Built-in/Unlit"
            case "builtin/toon":  return "Built-in/Toon"
            default:
                let filename = URL(fileURLWithPath: ref).deletingPathExtension().lastPathComponent
                return "Custom/\(filename)"
            }
        }

        if MaterialRegistry.shared.isBuiltin(mat.id) {
            if mat.id == MaterialRegistry.unlitMaterialID { return "Built-in/Unlit" }
            if mat.id == MaterialRegistry.toonMaterialID { return "Built-in/Toon" }
            return "Built-in/Lit"
        }

        if mat.unifiedShaderSource != nil || !mat.fragmentShaderSource.isEmpty {
            return "Custom Shader"
        }

        return "Built-in/Lit"
    }

    private func applyShaderSelection(_ selection: ShaderSelection, on entity: Entity) {
        switch selection {
        case .builtin(let tag):
            switchShader(on: entity, to: tag)
        case .projectAsset(let entry):
            guard let url = state.assetDatabase.resolveURL(for: entry.guid),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { return }
            state.updateComponent(MaterialComponent.self, on: entity) { mc in
                let preserved = mc.material.surfaceProperties
                let preservedParams = mc.material.parameters
                let preservedName = mc.material.name
                mc.material = MCMaterial(
                    name: preservedName,
                    materialType: .custom,
                    unifiedShaderSource: source,
                    surfaceProperties: preserved,
                    shaderReference: entry.relativePath
                )
                mc.material.parameters = preservedParams
            }
        }
    }

    private func shaderDisplayPath(for entry: AssetEntry) -> String {
        let rel = entry.relativePath
        // Strip "Shaders/" prefix and ".metal" extension
        var path = rel
        if path.hasPrefix("Shaders/") {
            path = String(path.dropFirst("Shaders/".count))
        }
        if path.hasSuffix(".metal") {
            path = String(path.dropLast(".metal".count))
        }
        return path
    }

    private func materialShaderTag(for mat: MCMaterial?) -> String {
        guard let mat else { return "lit" }

        if let ref = mat.shaderReference, !ref.isEmpty {
            switch ref {
            case "builtin/lit":   return "lit"
            case "builtin/unlit": return "unlit"
            case "builtin/toon":  return "toon"
            default:              return "custom"
            }
        }

        if MaterialRegistry.shared.isBuiltin(mat.id) {
            if mat.id == MaterialRegistry.unlitMaterialID { return "unlit" }
            if mat.id == MaterialRegistry.toonMaterialID { return "toon" }
            return "lit"
        }

        if mat.unifiedShaderSource != nil || !mat.fragmentShaderSource.isEmpty { return "custom" }
        return "lit"
    }

    private func switchShader(on entity: Entity, to tag: String) {
        let builtinID: UUID
        let shaderRef: String
        switch tag {
        case "unlit": builtinID = MaterialRegistry.unlitMaterialID; shaderRef = "builtin/unlit"
        case "toon":  builtinID = MaterialRegistry.toonMaterialID;  shaderRef = "builtin/toon"
        default:      builtinID = MaterialRegistry.litMaterialID;   shaderRef = "builtin/lit"
        }
        guard let builtin = MaterialRegistry.shared.builtinMaterial(builtinID) else { return }
        state.updateComponent(MaterialComponent.self, on: entity) { mc in
            let preserved = mc.material.surfaceProperties
            let preservedName = mc.material.name
            mc.material = builtin
            mc.material.surfaceProperties = preserved
            mc.material.shaderReference = shaderRef
            mc.material.name = preservedName
        }
    }

    private func createMaterial(on entity: Entity, basedOn builtinID: UUID, name: String) {
        let shaderRef: String
        if builtinID == MaterialRegistry.unlitMaterialID { shaderRef = "builtin/unlit" }
        else if builtinID == MaterialRegistry.toonMaterialID { shaderRef = "builtin/toon" }
        else { shaderRef = "builtin/lit" }

        let custom = MCMaterial(
            name: name,
            materialType: .custom,
            surfaceProperties: MCMaterialProperties(),
            shaderReference: shaderRef
        )
        state.updateComponent(MaterialComponent.self, on: entity) { mc in
            mc.material = custom
        }
    }

    @ViewBuilder
    private func materialColorRow(label: String, entity: Entity,
                                  get: @escaping () -> SIMD3<Float>,
                                  set: @escaping (SIMD3<Float>) -> Void) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: {
                    let c = get()
                    return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
                },
                set: { newColor in
                    if let components = newColor.cgColor?.components, components.count >= 3 {
                        set(SIMD3<Float>(Float(components[0]), Float(components[1]), Float(components[2])))
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func materialSlider(label: String, entity: Entity, range: ClosedRange<Float>,
                                get: @escaping () -> Float,
                                set: @escaping (Float) -> Void) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Slider(value: Binding(
                get: get,
                set: set
            ), in: range)
            Text(String(format: "%.2f", get()))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func materialTextureRow(label: String, entity: Entity,
                                    get: @escaping () -> String?,
                                    set: @escaping (String?) -> Void) -> some View {
        let currentPath = get()
        let displayName: String = {
            guard let p = currentPath else { return "None" }
            return URL(fileURLWithPath: p).lastPathComponent
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                if currentPath != nil {
                    Button {
                        set(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Menu {
                let texEntries = state.assetDatabase.entries(in: .textures, subfolder: nil)
                    .filter { !$0.isDirectory }

                if texEntries.isEmpty {
                    Text("No textures in project")
                } else {
                    ForEach(texEntries) { entry in
                        Button {
                            if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                                set(url.path)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "photo")
                                Text("\(entry.name).\(entry.fileExtension)")
                            }
                        }
                    }
                }

                Divider()

                Button("Import Texture...") {
                    importTextureToProject { relativePath in
                        if let path = relativePath {
                            set(path)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: currentPath != nil ? "photo.fill" : "photo")
                        .font(.system(size: 10))
                        .foregroundStyle(currentPath != nil ? MCTheme.statusGreen : MCTheme.textTertiary)
                    Text(displayName)
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(MCTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MCTheme.inputBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func importTextureToProject(completion: @escaping (String?) -> Void) {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .png, .jpeg,
            .init(filenameExtension: "exr")!,
            .init(filenameExtension: "hdr")!,
            .tiff
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a texture to import into the project"
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else {
                    completion(nil)
                    return
                }
                do {
                    let entry = try state.assetDatabase.importAsset(from: url, toCategory: .textures)
                    if let resolvedURL = state.assetDatabase.resolveURL(for: entry.guid) {
                        state.refreshAssetBrowser()
                        completion(resolvedURL.path)
                    } else {
                        completion(nil)
                    }
                } catch {
                    print("[MetalCaster] Failed to import texture: \(error)")
                    completion(nil)
                }
            }
        }
        #endif
    }

    private func pickMaterialFile(entity: Entity) {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "mcmat")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a material file (.mcmat)"
        panel.begin { response in
            DispatchQueue.main.async {
                if response == .OK, let url = panel.url {
                    state.assignMaterialAsset(from: url)
                }
            }
        }
        #endif
    }

    private func loadCustomShader(on entity: Entity, from url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("[MetalCaster] Failed to read shader file: \(url.path)")
            return
        }
        let relativePath: String? = {
            guard let root = state.projectManager.projectRoot else { return nil }
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            if url.path.hasPrefix(rootPath) {
                return String(url.path.dropFirst(rootPath.count))
            }
            return nil
        }()
        state.updateComponent(MaterialComponent.self, on: entity) { mc in
            let preserved = mc.material.surfaceProperties
            let preservedParams = mc.material.parameters
            let preservedName = mc.material.name
            mc.material = MCMaterial(
                name: preservedName,
                materialType: .custom,
                unifiedShaderSource: source,
                surfaceProperties: preserved,
                shaderReference: relativePath
            )
            mc.material.parameters = preservedParams
        }
    }

    private func saveMaterialToProject(mat: MCMaterial?) {
        guard let mat else { return }
        guard let dir = state.projectManager.directoryURL(for: .materials) else { return }
        let sanitized = mat.name.replacingOccurrences(of: " ", with: "_")
        let fileURL = dir.appendingPathComponent("\(sanitized).mcmat")
        do {
            try mat.save(to: fileURL)
            let relPath = "Materials/\(sanitized).mcmat"
            _ = state.projectManager.ensureMeta(for: relPath, type: .materials)
            state.refreshAssetBrowser()
        } catch {
            print("[MetalCaster] Failed to save material: \(error)")
        }
    }

    @ViewBuilder
    private func skyboxSection(_ entity: Entity) -> some View {
        let sky = state.engine.world.getComponent(SkyboxComponent.self, from: entity)

        MCSection(title: "Skybox") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("HDRI")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Text(sky?.hdriTexturePath ?? "None (gradient)")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Exposure")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: Binding(
                        get: { sky?.exposure ?? 1.0 },
                        set: { val in state.updateComponent(SkyboxComponent.self, on: entity) { $0.exposure = val } }
                    ), in: 0.1...5.0)
                    Text(String(format: "%.2f", sky?.exposure ?? 1.0))
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text("Rotation")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: Binding(
                        get: { (sky?.rotation ?? 0) * 180 / .pi },
                        set: { deg in state.updateComponent(SkyboxComponent.self, on: entity) { $0.rotation = deg * .pi / 180 } }
                    ), in: 0...360)
                    Text(String(format: "%.0f°", (sky?.rotation ?? 0) * 180 / .pi))
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
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
                        if !world.hasComponent(MaterialComponent.self, on: entity) {
                            world.addComponent(
                                MaterialComponent(material: MaterialRegistry.litMaterial),
                                to: entity
                            )
                        }
                        state.worldRevision += 1
                    }
                }
                if !world.hasComponent(MaterialComponent.self, on: entity) {
                    Button("Material") {
                        world.addComponent(
                            MaterialComponent(material: MaterialRegistry.litMaterial),
                            to: entity
                        )
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
                if !world.hasComponent(SkyboxComponent.self, on: entity) {
                    Button("Skybox") {
                        world.addComponent(SkyboxComponent(), to: entity)
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

// MARK: - Shader Selection

enum ShaderSelection {
    case builtin(String)
    case projectAsset(AssetEntry)
}

/// Unity-style shader picker: shows current shader path, click to open searchable list.
struct ShaderPicker: View {
    let currentShaderName: String
    let onSelect: (ShaderSelection) -> Void
    let assetDatabase: AssetDatabase

    @State private var showPopover = false
    @State private var searchText = ""

    private var builtinShaders: [(name: String, path: String, tag: String)] {
        [
            ("Lit",   "Built-in/Lit",   "lit"),
            ("Unlit", "Built-in/Unlit", "unlit"),
            ("Toon",  "Built-in/Toon",  "toon"),
        ]
    }

    private var projectShaders: [AssetEntry] {
        let _ = 0  // Force re-evaluation
        return assetDatabase.allEntries(in: .shaders)
            .filter { $0.fileExtension == "metal" }
    }

    private func shaderPath(for entry: AssetEntry) -> String {
        var path = entry.relativePath
        if path.hasPrefix("Shaders/") { path = String(path.dropFirst("Shaders/".count)) }
        if path.hasSuffix(".metal") { path = String(path.dropLast(".metal".count)) }
        return path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shader")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "function")
                        .font(.system(size: 10))
                        .foregroundStyle(MCTheme.textTertiary)
                    Text(currentShaderName)
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(MCTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MCTheme.inputBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                shaderListPopover
            }
        }
    }

    private var shaderListPopover: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
                TextField("Search shaders...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Built-in section
                    let filteredBuiltins = builtinShaders.filter {
                        searchText.isEmpty || $0.path.localizedCaseInsensitiveContains(searchText)
                    }
                    if !filteredBuiltins.isEmpty {
                        sectionHeader("Built-in")
                        ForEach(filteredBuiltins, id: \.tag) { shader in
                            shaderRow(
                                path: shader.path,
                                isSelected: currentShaderName == shader.path
                            ) {
                                onSelect(.builtin(shader.tag))
                                showPopover = false
                            }
                        }
                    }

                    // Project shaders
                    let filteredProject = projectShaders.filter {
                        searchText.isEmpty || shaderPath(for: $0).localizedCaseInsensitiveContains(searchText)
                    }
                    if !filteredProject.isEmpty {
                        sectionHeader("Project")
                        ForEach(filteredProject) { entry in
                            let path = shaderPath(for: entry)
                            shaderRow(
                                path: path,
                                isSelected: currentShaderName == path
                            ) {
                                onSelect(.projectAsset(entry))
                                showPopover = false
                            }
                        }
                    }

                    if filteredBuiltins.isEmpty && filteredProject.isEmpty {
                        Text("No matching shaders")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 240)
        .background(MCTheme.background)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(MCTheme.fontSmall)
            .fontWeight(.semibold)
            .foregroundStyle(MCTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func shaderRow(path: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "function")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? MCTheme.statusBlue : MCTheme.textTertiary)
                    .frame(width: 14)
                Text(path)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(isSelected ? MCTheme.textPrimary : MCTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? MCTheme.surfaceSelected : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
