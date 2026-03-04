import SwiftUI
import simd
import UniformTypeIdentifiers
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAsset
import MetalCasterPhysics
import MetalCasterAudio

#if canImport(AppKit)
import AppKit
import ImageIO
import CoreGraphics
#endif

struct InspectorView: View {
    @Environment(EditorState.self) private var state
    @State private var transformResetID = UUID()
    @State private var showComponentPicker = false

    var body: some View {
        let _ = state.worldRevision
        if let entity = state.selectedEntity, state.engine.world.isAlive(entity) {
            entityInspector(entity)
        } else if let assetEntry = state.selectedAssetEntry,
                  assetEntry.fileExtension == "mcmat" {
            materialAssetInspector(entry: assetEntry)
        } else if let assetEntry = state.selectedAssetEntry,
                  Self.textureExtensions.contains(assetEntry.fileExtension.lowercased()) {
            textureAssetInspector(entry: assetEntry)
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
                if state.engine.world.hasComponent(LODComponent.self, on: entity) {
                    lodSection(entity)
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
                if state.engine.world.hasComponent(PostProcessVolumeComponent.self, on: entity) {
                    postProcessVolumeSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(PhysicsBodyComponent.self, on: entity) {
                    physicsBodySection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(ColliderComponent.self, on: entity) {
                    colliderSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(AudioSourceComponent.self, on: entity) {
                    audioSourceSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(AudioListenerComponent.self, on: entity) {
                    audioListenerSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(UICanvasComponent.self, on: entity) {
                    uiCanvasSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(UIElementComponent.self, on: entity) {
                    uiElementSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(UILabelComponent.self, on: entity) {
                    uiLabelSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(UIImageComponent.self, on: entity) {
                    uiImageSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(UIPanelComponent.self, on: entity) {
                    uiPanelSection(entity)
                    sectionDivider()
                }
                if state.engine.world.hasComponent(GameplayScriptRef.self, on: entity) {
                    gameplayScriptSection(entity)
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

    private static let textureExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "exr", "hdr", "bmp", "gif", "webp"]

    private func removeComponentButton<C: Component>(_ type: C.Type, from entity: Entity, label: String = "Remove") -> some View {
        Button {
            state.engine.world.removeComponent(type, from: entity)
            state.worldRevision += 1
            state.markDirty()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9))
                .foregroundStyle(MCTheme.textTertiary)
        }
        .buttonStyle(.plain)
        .help(label)
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
            removeComponentButton(CameraComponent.self, from: entity, label: "Remove Camera")
        } content: {
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

                HStack(spacing: 12) {
                    liveFloatRow(label: "Near", entity: entity,
                        get: { cam?.nearZ ?? 0.1 },
                        set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.nearZ = val } })
                    liveFloatRow(label: "Far", entity: entity,
                        get: { cam?.farZ ?? 1000 },
                        set: { val in state.updateComponent(CameraComponent.self, on: entity) { $0.farZ = val } })
                }

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
                HStack(spacing: 16) {
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
                }

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
            removeComponentButton(LightComponent.self, from: entity, label: "Remove Light")
        } content: {
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
                removeComponentButton(MeshComponent.self, from: entity, label: "Remove Mesh")
            } content: {
                Text(meshTypeDisplay(mc.meshType))
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func lodSection(_ entity: Entity) -> some View {
        if let lod = state.engine.world.getComponent(LODComponent.self, from: entity) {
            MCSection(title: "LOD") {
                removeComponentButton(LODComponent.self, from: entity, label: "Remove LOD")
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active Level")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textSecondary)
                        Spacer()
                        Text("\(lod.activeLevelIndex)")
                            .font(MCTheme.fontMono)
                            .foregroundStyle(MCTheme.textSecondary)
                    }

                    Toggle("Cull Beyond Max", isOn: Binding(
                        get: { lod.cullBeyondMaxDistance },
                        set: { newVal in
                            state.updateComponent(LODComponent.self, on: entity) { c in
                                c.cullBeyondMaxDistance = newVal
                            }
                        }
                    ))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    ForEach(lod.levels.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Level \(i)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(i == lod.activeLevelIndex ? MCTheme.statusGreen : MCTheme.textTertiary)

                            HStack {
                                Text("Mesh")
                                    .font(MCTheme.fontCaption)
                                    .foregroundStyle(MCTheme.textSecondary)
                                    .frame(width: 70, alignment: .leading)
                                Text(meshTypeDisplay(lod.levels[i].meshType))
                                    .font(MCTheme.fontCaption)
                                    .foregroundStyle(MCTheme.textSecondary)
                            }

                            MCDraggableField(
                                label: "Dist",
                                displayValue: lod.levels[i].maxDistance,
                                getValue: {
                                    guard let c = state.engine.world.getComponent(LODComponent.self, from: entity),
                                          i < c.levels.count else { return 0 }
                                    return c.levels[i].maxDistance
                                },
                                onChanged: { newVal in
                                    state.updateComponent(LODComponent.self, on: entity) { c in
                                        guard i < c.levels.count else { return }
                                        c.levels[i].maxDistance = newVal
                                    }
                                },
                                step: 1.0,
                                labelWidth: 70
                            )
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if lod.levels.isEmpty {
                        Text("No LOD levels defined")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textTertiary)
                    }

                    Button {
                        state.updateComponent(LODComponent.self, on: entity) { c in
                            let nextDist = (c.levels.last?.maxDistance ?? 0) + 20
                            let mesh = state.engine.world.getComponent(MeshComponent.self, from: entity)?.meshType ?? .sphere
                            c.levels.append(LODLevel(meshType: mesh, maxDistance: nextDist))
                        }
                    } label: {
                        Label("Add Level", systemImage: "plus.circle")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func materialSection(_ entity: Entity) -> some View {
        let mat = state.engine.world.getComponent(MaterialComponent.self, from: entity)?.material

        MCSection(title: "Material") {
            HStack(spacing: 4) {
                removeComponentButton(MaterialComponent.self, from: entity, label: "Remove Material")
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
            removeComponentButton(SkyboxComponent.self, from: entity, label: "Remove Skybox")
        } content: {
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

    // MARK: - Post Process Volume Section

    @ViewBuilder
    private func postProcessVolumeSection(_ entity: Entity) -> some View {
        let vol = state.engine.world.getComponent(PostProcessVolumeComponent.self, from: entity)

        MCSection(title: "Post Process Volume") {
            removeComponentButton(PostProcessVolumeComponent.self, from: entity, label: "Remove Post Process")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Global (Infinite)", isOn: Binding(
                    get: { vol?.isGlobal ?? true },
                    set: { val in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.isGlobal = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)

                if !(vol?.isGlobal ?? true) {
                    liveVec3Row(label: "Extents", entity: entity,
                        get: { vol?.volumeExtents ?? SIMD3<Float>(10, 10, 10) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.volumeExtents = v } },
                        step: 0.5)
                    ppSlider(label: "Blend Dist", entity: entity, range: 0...20,
                        get: { vol?.blendDistance ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.blendDistance = v } })
                }

                ppIntRow(label: "Priority", entity: entity,
                    get: { vol?.priority ?? 0 },
                    set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.priority = v } })
            }
        }

        ppEffectBloom(entity, vol: vol)
        ppEffectChromaticAberration(entity, vol: vol)
        ppEffectColorAdjustments(entity, vol: vol)
        ppEffectChannelMixer(entity, vol: vol)
        ppEffectDepthOfField(entity, vol: vol)
        ppEffectFilmGrain(entity, vol: vol)
        ppEffectLensDistortion(entity, vol: vol)
        ppEffectLiftGammaGain(entity, vol: vol)
        ppEffectMotionBlur(entity, vol: vol)
        ppEffectPaniniProjection(entity, vol: vol)
        ppEffectShadowsMidtonesHighlights(entity, vol: vol)
        ppEffectSplitToning(entity, vol: vol)
        ppEffectTonemapping(entity, vol: vol)
        ppEffectVignette(entity, vol: vol)
        ppEffectWhiteBalance(entity, vol: vol)
        ppEffectAmbientOcclusion(entity, vol: vol)
        ppEffectAntiAliasing(entity, vol: vol)
        ppEffectFullscreenBlur(entity, vol: vol)
        ppEffectFullscreenOutline(entity, vol: vol)
    }

    // MARK: - PP Effect Sections

    @ViewBuilder
    private func ppEffectBloom(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Bloom", trailing: {
            ppToggle(entity: entity, get: { vol?.bloom.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.bloom.enabled = v } })
        }) {
            if vol?.bloom.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Threshold", entity: entity, range: 0...5,
                        get: { vol?.bloom.threshold ?? 0.9 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.bloom.threshold = v } })
                    ppSlider(label: "Intensity", entity: entity, range: 0...10,
                        get: { vol?.bloom.intensity ?? 1.0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.bloom.intensity = v } })
                    ppSlider(label: "Scatter", entity: entity, range: 0...1,
                        get: { vol?.bloom.scatter ?? 0.7 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.bloom.scatter = v } })
                    ppColorRow(label: "Tint", entity: entity,
                        get: { vol?.bloom.tint ?? SIMD3<Float>(1, 1, 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.bloom.tint = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectChromaticAberration(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Chromatic Aberration", trailing: {
            ppToggle(entity: entity, get: { vol?.chromaticAberration.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.chromaticAberration.enabled = v } })
        }) {
            if vol?.chromaticAberration.enabled == true {
                ppSlider(label: "Intensity", entity: entity, range: 0...1,
                    get: { vol?.chromaticAberration.intensity ?? 0.1 },
                    set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.chromaticAberration.intensity = v } })
            }
        }
    }

    @ViewBuilder
    private func ppEffectColorAdjustments(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Color Adjustments", trailing: {
            ppToggle(entity: entity, get: { vol?.colorAdjustments.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.colorAdjustments.enabled = v } })
        }) {
            if vol?.colorAdjustments.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Post Exposure", entity: entity, range: -5...5,
                        get: { vol?.colorAdjustments.postExposure ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.colorAdjustments.postExposure = v } })
                    ppSlider(label: "Contrast", entity: entity, range: -100...100,
                        get: { vol?.colorAdjustments.contrast ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.colorAdjustments.contrast = v } })
                    ppColorRow(label: "Color Filter", entity: entity,
                        get: { vol?.colorAdjustments.colorFilter ?? SIMD3<Float>(1, 1, 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.colorAdjustments.colorFilter = v } })
                    ppSlider(label: "Hue Shift", entity: entity, range: -180...180,
                        get: { vol?.colorAdjustments.hueShift ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.colorAdjustments.hueShift = v } })
                    ppSlider(label: "Saturation", entity: entity, range: -100...100,
                        get: { vol?.colorAdjustments.saturation ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.colorAdjustments.saturation = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectChannelMixer(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Channel Mixer", trailing: {
            ppToggle(entity: entity, get: { vol?.channelMixer.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.enabled = v } })
        }) {
            if vol?.channelMixer.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Red Output").font(MCTheme.fontCaption).foregroundStyle(MCTheme.textSecondary)
                    ppSlider(label: "R", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.redOutRed ?? 100 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.redOutRed = v } })
                    ppSlider(label: "G", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.redOutGreen ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.redOutGreen = v } })
                    ppSlider(label: "B", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.redOutBlue ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.redOutBlue = v } })
                    Text("Green Output").font(MCTheme.fontCaption).foregroundStyle(MCTheme.textSecondary)
                    ppSlider(label: "R", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.greenOutRed ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.greenOutRed = v } })
                    ppSlider(label: "G", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.greenOutGreen ?? 100 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.greenOutGreen = v } })
                    ppSlider(label: "B", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.greenOutBlue ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.greenOutBlue = v } })
                    Text("Blue Output").font(MCTheme.fontCaption).foregroundStyle(MCTheme.textSecondary)
                    ppSlider(label: "R", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.blueOutRed ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.blueOutRed = v } })
                    ppSlider(label: "G", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.blueOutGreen ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.blueOutGreen = v } })
                    ppSlider(label: "B", entity: entity, range: -200...200,
                        get: { vol?.channelMixer.blueOutBlue ?? 100 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.channelMixer.blueOutBlue = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectDepthOfField(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Depth of Field", trailing: {
            ppToggle(entity: entity, get: { vol?.depthOfField.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.depthOfField.enabled = v } })
        }) {
            if vol?.depthOfField.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: Binding(
                        get: { vol?.depthOfField.mode ?? .gaussian },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.depthOfField.mode = v } }
                    )) {
                        ForEach(DoFMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)

                    ppSlider(label: "Focus Dist", entity: entity, range: 0.1...100,
                        get: { vol?.depthOfField.focusDistance ?? 10 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.depthOfField.focusDistance = v } })
                    ppSlider(label: "Aperture", entity: entity, range: 1...22,
                        get: { vol?.depthOfField.aperture ?? 5.6 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.depthOfField.aperture = v } })
                    ppSlider(label: "Focal Length", entity: entity, range: 10...300,
                        get: { vol?.depthOfField.focalLength ?? 50 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.depthOfField.focalLength = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectFilmGrain(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Film Grain", trailing: {
            ppToggle(entity: entity, get: { vol?.filmGrain.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.filmGrain.enabled = v } })
        }) {
            if vol?.filmGrain.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Type", selection: Binding(
                        get: { vol?.filmGrain.type ?? .medium },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.filmGrain.type = v } }
                    )) {
                        ForEach(FilmGrainType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)

                    ppSlider(label: "Intensity", entity: entity, range: 0...1,
                        get: { vol?.filmGrain.intensity ?? 0.5 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.filmGrain.intensity = v } })
                    ppSlider(label: "Response", entity: entity, range: 0...1,
                        get: { vol?.filmGrain.response ?? 0.8 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.filmGrain.response = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectLensDistortion(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Lens Distortion", trailing: {
            ppToggle(entity: entity, get: { vol?.lensDistortion.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.lensDistortion.enabled = v } })
        }) {
            if vol?.lensDistortion.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Intensity", entity: entity, range: -1...1,
                        get: { vol?.lensDistortion.intensity ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.lensDistortion.intensity = v } })
                    ppSlider(label: "X Multiply", entity: entity, range: 0...1,
                        get: { vol?.lensDistortion.xMultiplier ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.lensDistortion.xMultiplier = v } })
                    ppSlider(label: "Y Multiply", entity: entity, range: 0...1,
                        get: { vol?.lensDistortion.yMultiplier ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.lensDistortion.yMultiplier = v } })
                    ppSlider(label: "Scale", entity: entity, range: 0.01...5,
                        get: { vol?.lensDistortion.scale ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.lensDistortion.scale = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectLiftGammaGain(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Lift Gamma Gain", trailing: {
            ppToggle(entity: entity, get: { vol?.liftGammaGain.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.liftGammaGain.enabled = v } })
        }) {
            if vol?.liftGammaGain.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppColorRow(label: "Lift", entity: entity,
                        get: { SIMD3<Float>(vol?.liftGammaGain.lift.x ?? 1, vol?.liftGammaGain.lift.y ?? 1, vol?.liftGammaGain.lift.z ?? 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.liftGammaGain.lift = SIMD4<Float>(v.x, v.y, v.z, $0.liftGammaGain.lift.w) } })
                    ppColorRow(label: "Gamma", entity: entity,
                        get: { SIMD3<Float>(vol?.liftGammaGain.gamma.x ?? 1, vol?.liftGammaGain.gamma.y ?? 1, vol?.liftGammaGain.gamma.z ?? 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.liftGammaGain.gamma = SIMD4<Float>(v.x, v.y, v.z, $0.liftGammaGain.gamma.w) } })
                    ppColorRow(label: "Gain", entity: entity,
                        get: { SIMD3<Float>(vol?.liftGammaGain.gain.x ?? 1, vol?.liftGammaGain.gain.y ?? 1, vol?.liftGammaGain.gain.z ?? 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.liftGammaGain.gain = SIMD4<Float>(v.x, v.y, v.z, $0.liftGammaGain.gain.w) } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectMotionBlur(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Motion Blur", trailing: {
            ppToggle(entity: entity, get: { vol?.motionBlur.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.motionBlur.enabled = v } })
        }) {
            if vol?.motionBlur.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Intensity", entity: entity, range: 0...1,
                        get: { vol?.motionBlur.intensity ?? 0.5 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.motionBlur.intensity = v } })
                    ppIntRow(label: "Quality", entity: entity,
                        get: { vol?.motionBlur.quality ?? 16 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.motionBlur.quality = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectPaniniProjection(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Panini Projection", trailing: {
            ppToggle(entity: entity, get: { vol?.paniniProjection.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.paniniProjection.enabled = v } })
        }) {
            if vol?.paniniProjection.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Distance", entity: entity, range: 0...1,
                        get: { vol?.paniniProjection.distance ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.paniniProjection.distance = v } })
                    ppSlider(label: "Crop to Fit", entity: entity, range: 0...1,
                        get: { vol?.paniniProjection.cropToFit ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.paniniProjection.cropToFit = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectShadowsMidtonesHighlights(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Shadows Midtones Highlights", trailing: {
            ppToggle(entity: entity, get: { vol?.shadowsMidtonesHighlights.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.enabled = v } })
        }) {
            if vol?.shadowsMidtonesHighlights.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppColorRow(label: "Shadows", entity: entity,
                        get: { SIMD3<Float>(vol?.shadowsMidtonesHighlights.shadows.x ?? 1, vol?.shadowsMidtonesHighlights.shadows.y ?? 1, vol?.shadowsMidtonesHighlights.shadows.z ?? 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.shadows = SIMD4<Float>(v.x, v.y, v.z, $0.shadowsMidtonesHighlights.shadows.w) } })
                    ppColorRow(label: "Midtones", entity: entity,
                        get: { SIMD3<Float>(vol?.shadowsMidtonesHighlights.midtones.x ?? 1, vol?.shadowsMidtonesHighlights.midtones.y ?? 1, vol?.shadowsMidtonesHighlights.midtones.z ?? 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.midtones = SIMD4<Float>(v.x, v.y, v.z, $0.shadowsMidtonesHighlights.midtones.w) } })
                    ppColorRow(label: "Highlights", entity: entity,
                        get: { SIMD3<Float>(vol?.shadowsMidtonesHighlights.highlights.x ?? 1, vol?.shadowsMidtonesHighlights.highlights.y ?? 1, vol?.shadowsMidtonesHighlights.highlights.z ?? 1) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.highlights = SIMD4<Float>(v.x, v.y, v.z, $0.shadowsMidtonesHighlights.highlights.w) } })
                    ppSlider(label: "Shadow Start", entity: entity, range: 0...1,
                        get: { vol?.shadowsMidtonesHighlights.shadowsStart ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.shadowsStart = v } })
                    ppSlider(label: "Shadow End", entity: entity, range: 0...1,
                        get: { vol?.shadowsMidtonesHighlights.shadowsEnd ?? 0.3 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.shadowsEnd = v } })
                    ppSlider(label: "HL Start", entity: entity, range: 0...1,
                        get: { vol?.shadowsMidtonesHighlights.highlightsStart ?? 0.55 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.highlightsStart = v } })
                    ppSlider(label: "HL End", entity: entity, range: 0...1,
                        get: { vol?.shadowsMidtonesHighlights.highlightsEnd ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.shadowsMidtonesHighlights.highlightsEnd = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectSplitToning(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Split Toning", trailing: {
            ppToggle(entity: entity, get: { vol?.splitToning.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.splitToning.enabled = v } })
        }) {
            if vol?.splitToning.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppColorRow(label: "Shadows", entity: entity,
                        get: { vol?.splitToning.shadowsTint ?? SIMD3<Float>(0.5, 0.5, 0.5) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.splitToning.shadowsTint = v } })
                    ppColorRow(label: "Highlights", entity: entity,
                        get: { vol?.splitToning.highlightsTint ?? SIMD3<Float>(0.5, 0.5, 0.5) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.splitToning.highlightsTint = v } })
                    ppSlider(label: "Balance", entity: entity, range: -100...100,
                        get: { vol?.splitToning.balance ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.splitToning.balance = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectTonemapping(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Tonemapping", trailing: {
            ppToggle(entity: entity, get: { vol?.tonemapping.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.tonemapping.enabled = v } })
        }) {
            if vol?.tonemapping.enabled == true {
                Picker("Mode", selection: Binding(
                    get: { vol?.tonemapping.mode ?? .aces },
                    set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.tonemapping.mode = v } }
                )) {
                    ForEach(TonemappingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func ppEffectVignette(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Vignette", trailing: {
            ppToggle(entity: entity, get: { vol?.vignette.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.vignette.enabled = v } })
        }) {
            if vol?.vignette.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppColorRow(label: "Color", entity: entity,
                        get: { vol?.vignette.color ?? SIMD3<Float>(0, 0, 0) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.vignette.color = v } })
                    ppSlider(label: "Intensity", entity: entity, range: 0...1,
                        get: { vol?.vignette.intensity ?? 0.3 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.vignette.intensity = v } })
                    ppSlider(label: "Smoothness", entity: entity, range: 0.01...1,
                        get: { vol?.vignette.smoothness ?? 0.3 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.vignette.smoothness = v } })
                    Toggle("Rounded", isOn: Binding(
                        get: { vol?.vignette.rounded ?? false },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.vignette.rounded = v } }
                    ))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectWhiteBalance(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "White Balance", trailing: {
            ppToggle(entity: entity, get: { vol?.whiteBalance.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.whiteBalance.enabled = v } })
        }) {
            if vol?.whiteBalance.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Temperature", entity: entity, range: -100...100,
                        get: { vol?.whiteBalance.temperature ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.whiteBalance.temperature = v } })
                    ppSlider(label: "Tint", entity: entity, range: -100...100,
                        get: { vol?.whiteBalance.tint ?? 0 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.whiteBalance.tint = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectAmbientOcclusion(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Ambient Occlusion", trailing: {
            ppToggle(entity: entity, get: { vol?.ambientOcclusion.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.ambientOcclusion.enabled = v } })
        }) {
            if vol?.ambientOcclusion.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    ppSlider(label: "Intensity", entity: entity, range: 0...4,
                        get: { vol?.ambientOcclusion.intensity ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.ambientOcclusion.intensity = v } })
                    ppSlider(label: "Radius", entity: entity, range: 0.01...5,
                        get: { vol?.ambientOcclusion.radius ?? 0.5 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.ambientOcclusion.radius = v } })
                    ppIntRow(label: "Samples", entity: entity,
                        get: { vol?.ambientOcclusion.sampleCount ?? 16 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.ambientOcclusion.sampleCount = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectAntiAliasing(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Anti-Aliasing", trailing: {
            ppToggle(entity: entity, get: { vol?.antiAliasing.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.antiAliasing.enabled = v } })
        }) {
            if vol?.antiAliasing.enabled == true {
                Picker("Mode", selection: Binding(
                    get: { vol?.antiAliasing.mode ?? .fxaa },
                    set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.antiAliasing.mode = v } }
                )) {
                    ForEach(AntiAliasingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func ppEffectFullscreenBlur(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Fullscreen Blur", trailing: {
            ppToggle(entity: entity, get: { vol?.fullscreenBlur.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenBlur.enabled = v } })
        }) {
            if vol?.fullscreenBlur.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: Binding(
                        get: { vol?.fullscreenBlur.mode ?? .highQuality },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenBlur.mode = v } }
                    )) {
                        ForEach(FullscreenBlurMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)

                    ppSlider(label: "Intensity", entity: entity, range: 0...1,
                        get: { vol?.fullscreenBlur.intensity ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenBlur.intensity = v } })
                    ppSlider(label: "Radius", entity: entity, range: 0...20,
                        get: { vol?.fullscreenBlur.radius ?? 5 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenBlur.radius = v } })
                }
            }
        }
    }

    @ViewBuilder
    private func ppEffectFullscreenOutline(_ entity: Entity, vol: PostProcessVolumeComponent?) -> some View {
        MCSection(title: "Fullscreen Outline", trailing: {
            ppToggle(entity: entity, get: { vol?.fullscreenOutline.enabled ?? false },
                set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenOutline.enabled = v } })
        }) {
            if vol?.fullscreenOutline.enabled == true {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Mode", selection: Binding(
                        get: { vol?.fullscreenOutline.mode ?? .depthBased },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenOutline.mode = v } }
                    )) {
                        ForEach(FullscreenOutlineMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)

                    ppSlider(label: "Thickness", entity: entity, range: 0.1...5,
                        get: { vol?.fullscreenOutline.thickness ?? 1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenOutline.thickness = v } })
                    ppColorRow(label: "Color", entity: entity,
                        get: { vol?.fullscreenOutline.color ?? SIMD3<Float>(0, 0, 0) },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenOutline.color = v } })
                    ppSlider(label: "Threshold", entity: entity, range: 0...1,
                        get: { vol?.fullscreenOutline.threshold ?? 0.1 },
                        set: { v in state.updateComponent(PostProcessVolumeComponent.self, on: entity) { $0.fullscreenOutline.threshold = v } })
                }
            }
        }
    }

    // MARK: - PP Helper Views

    @ViewBuilder
    private func ppToggle(entity: Entity, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: get, set: set))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    @ViewBuilder
    private func ppSlider(label: String, entity: Entity, range: ClosedRange<Float>,
                          get: @escaping () -> Float, set: @escaping (Float) -> Void) -> some View {
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
    private func ppColorRow(label: String, entity: Entity,
                            get: @escaping () -> SIMD3<Float>, set: @escaping (SIMD3<Float>) -> Void) -> some View {
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
    private func ppIntRow(label: String, entity: Entity,
                          get: @escaping () -> Int, set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            TextField("", value: Binding(get: get, set: set), format: .number)
                .textFieldStyle(.plain)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)
                .frame(width: 60)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MCTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(MCTheme.inputBorder, lineWidth: 1))
        }
    }

    // MARK: - Physics Body Section

    @ViewBuilder
    private func physicsBodySection(_ entity: Entity) -> some View {
        let body = state.engine.world.getComponent(PhysicsBodyComponent.self, from: entity)

        MCSection(title: "Physics Body") {
            removeComponentButton(PhysicsBodyComponent.self, from: entity, label: "Remove Physics Body")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: Binding(
                    get: { body?.bodyType ?? .dynamicBody },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.bodyType = val } }
                )) {
                    Text("Static").tag(PhysicsBodyComponent.BodyType.staticBody)
                    Text("Dynamic").tag(PhysicsBodyComponent.BodyType.dynamicBody)
                    Text("Kinematic").tag(PhysicsBodyComponent.BodyType.kinematic)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                liveFloatRow(label: "Mass", entity: entity,
                    get: { body?.mass ?? 1.0 },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.mass = val } })

                liveFloatRow(label: "Restitution", entity: entity,
                    get: { body?.restitution ?? 0.3 },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.restitution = val } })

                liveFloatRow(label: "Friction", entity: entity,
                    get: { body?.friction ?? 0.5 },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.friction = val } })

                Toggle("Use Gravity", isOn: Binding(
                    get: { body?.useGravity ?? true },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.useGravity = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

                liveFloatRow(label: "Lin Damp", entity: entity,
                    get: { body?.linearDamping ?? 0.01 },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.linearDamping = val } })

                liveFloatRow(label: "Ang Damp", entity: entity,
                    get: { body?.angularDamping ?? 0.05 },
                    set: { val in state.updateComponent(PhysicsBodyComponent.self, on: entity) { $0.angularDamping = val } })
            }
        }
    }

    // MARK: - Collider Section

    @ViewBuilder
    private func colliderSection(_ entity: Entity) -> some View {
        let col = state.engine.world.getComponent(ColliderComponent.self, from: entity)

        MCSection(title: "Collider") {
            removeComponentButton(ColliderComponent.self, from: entity, label: "Remove Collider")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Shape", selection: Binding(
                    get: { col?.shape ?? .sphere },
                    set: { val in state.updateComponent(ColliderComponent.self, on: entity) { $0.shape = val } }
                )) {
                    Text("Sphere").tag(ColliderComponent.Shape.sphere)
                    Text("Box").tag(ColliderComponent.Shape.box)
                    Text("Capsule").tag(ColliderComponent.Shape.capsule)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                if col?.shape == .sphere || col?.shape == .capsule {
                    liveFloatRow(label: "Radius", entity: entity,
                        get: { col?.radius ?? 1.0 },
                        set: { val in state.updateComponent(ColliderComponent.self, on: entity) { $0.radius = val } })
                }
                if col?.shape == .box {
                    liveVec3Row(label: "Half Extents", entity: entity,
                        get: { col?.halfExtents ?? SIMD3<Float>(0.5, 0.5, 0.5) },
                        set: { val in state.updateComponent(ColliderComponent.self, on: entity) { $0.halfExtents = val } })
                }

                Toggle("Is Trigger", isOn: Binding(
                    get: { col?.isTrigger ?? false },
                    set: { val in state.updateComponent(ColliderComponent.self, on: entity) { $0.isTrigger = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

                liveVec3Row(label: "Offset", entity: entity,
                    get: { col?.offset ?? .zero },
                    set: { val in state.updateComponent(ColliderComponent.self, on: entity) { $0.offset = val } })
            }
        }
    }

    // MARK: - Audio Source Section

    @ViewBuilder
    private func audioSourceSection(_ entity: Entity) -> some View {
        let src = state.engine.world.getComponent(AudioSourceComponent.self, from: entity)

        MCSection(title: "Audio Source") {
            removeComponentButton(AudioSourceComponent.self, from: entity, label: "Remove Audio Source")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    MCAssetPicker(
                        label: "Audio File",
                        category: .audio,
                        extensions: ["wav", "mp3", "aac", "m4a", "ogg", "flac"],
                        selection: Binding(
                            get: { src?.audioFile ?? "" },
                            set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.audioFile = val } }
                        )
                    )

                    Button {
                        let playing = src?.isPlaying ?? false
                        state.updateComponent(AudioSourceComponent.self, on: entity) {
                            $0.isPlaying = !playing
                        }
                    } label: {
                        Image(systemName: (src?.isPlaying ?? false) ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle((src?.isPlaying ?? false) ? MCTheme.statusRed : MCTheme.statusGreen)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(src?.audioFile.isEmpty ?? true)
                }

                liveFloatRow(label: "Volume", entity: entity,
                    get: { src?.volume ?? 1.0 },
                    set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.volume = val } })

                liveFloatRow(label: "Pitch", entity: entity,
                    get: { src?.pitch ?? 1.0 },
                    set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.pitch = val } })

                Toggle("Looping", isOn: Binding(
                    get: { src?.isLooping ?? false },
                    set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.isLooping = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

                Toggle("3D Spatial", isOn: Binding(
                    get: { src?.is3D ?? true },
                    set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.is3D = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

                if src?.is3D == true {
                    liveFloatRow(label: "Max Dist", entity: entity,
                        get: { src?.maxDistance ?? 50.0 },
                        set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.maxDistance = val } })
                    liveFloatRow(label: "Ref Dist", entity: entity,
                        get: { src?.referenceDistance ?? 1.0 },
                        set: { val in state.updateComponent(AudioSourceComponent.self, on: entity) { $0.referenceDistance = val } })
                }
            }
        }
    }

    // MARK: - Audio Listener Section

    @ViewBuilder
    private func audioListenerSection(_ entity: Entity) -> some View {
        let listener = state.engine.world.getComponent(AudioListenerComponent.self, from: entity)

        MCSection(title: "Audio Listener") {
            removeComponentButton(AudioListenerComponent.self, from: entity, label: "Remove Audio Listener")
        } content: {
            Toggle("Active", isOn: Binding(
                get: { listener?.isActive ?? true },
                set: { val in state.updateComponent(AudioListenerComponent.self, on: entity) { $0.isActive = val } }
            ))
            .font(MCTheme.fontCaption)
            .foregroundStyle(MCTheme.textSecondary)
        }
    }

    // MARK: - UI Component Sections

    @ViewBuilder
    private func uiCanvasSection(_ entity: Entity) -> some View {
        let canvas = state.engine.world.getComponent(UICanvasComponent.self, from: entity)

        MCSection(title: "UI Canvas") {
            removeComponentButton(UICanvasComponent.self, from: entity, label: "Remove UI Canvas")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Render Space", selection: Binding(
                    get: { canvas?.renderSpace ?? .screen },
                    set: { val in state.updateComponent(UICanvasComponent.self, on: entity) { $0.renderSpace = val } }
                )) {
                    Text("Screen").tag(UICanvasComponent.RenderSpace.screen)
                    Text("World").tag(UICanvasComponent.RenderSpace.world)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                HStack {
                    Text("Sort Order")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    TextField("0", value: Binding(
                        get: { canvas?.sortOrder ?? 0 },
                        set: { val in state.updateComponent(UICanvasComponent.self, on: entity) { $0.sortOrder = val } }
                    ), formatter: NumberFormatter())
                    .textFieldStyle(.plain)
                    .font(MCTheme.fontCaption)
                }

                Toggle("Enabled", isOn: Binding(
                    get: { canvas?.isEnabled ?? true },
                    set: { val in state.updateComponent(UICanvasComponent.self, on: entity) { $0.isEnabled = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func uiElementSection(_ entity: Entity) -> some View {
        let el = state.engine.world.getComponent(UIElementComponent.self, from: entity)

        MCSection(title: "UI Element") {
            removeComponentButton(UIElementComponent.self, from: entity, label: "Remove UI Element")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: Binding(
                    get: { el?.elementType ?? .panel },
                    set: { val in state.updateComponent(UIElementComponent.self, on: entity) { $0.elementType = val } }
                )) {
                    Text("Label").tag(UIElementType.label)
                    Text("Image").tag(UIElementType.image)
                    Text("Panel").tag(UIElementType.panel)
                    Text("Button").tag(UIElementType.button)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                liveVec3Row(label: "Position", entity: entity,
                    get: { SIMD3<Float>(el?.offset.x ?? 0, el?.offset.y ?? 0, 0) },
                    set: { val in state.updateComponent(UIElementComponent.self, on: entity) { $0.offset = SIMD2<Float>(val.x, val.y) } })

                Toggle("Visible", isOn: Binding(
                    get: { el?.isVisible ?? true },
                    set: { val in state.updateComponent(UIElementComponent.self, on: entity) { $0.isVisible = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func uiLabelSection(_ entity: Entity) -> some View {
        let lbl = state.engine.world.getComponent(UILabelComponent.self, from: entity)

        MCSection(title: "UI Label") {
            removeComponentButton(UILabelComponent.self, from: entity, label: "Remove UI Label")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    TextField("Label", text: Binding(
                        get: { lbl?.text ?? "" },
                        set: { val in state.updateComponent(UILabelComponent.self, on: entity) { $0.text = val } }
                    ))
                    .textFieldStyle(.plain)
                    .font(MCTheme.fontCaption)
                }

                liveFloatRow(label: "Font Size", entity: entity,
                    get: { lbl?.fontSize ?? 16 },
                    set: { val in state.updateComponent(UILabelComponent.self, on: entity) { $0.fontSize = val } })

                Picker("Alignment", selection: Binding(
                    get: { lbl?.alignment ?? .left },
                    set: { val in state.updateComponent(UILabelComponent.self, on: entity) { $0.alignment = val } }
                )) {
                    Text("Left").tag(UILabelComponent.TextAlignment.left)
                    Text("Center").tag(UILabelComponent.TextAlignment.center)
                    Text("Right").tag(UILabelComponent.TextAlignment.right)
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func uiImageSection(_ entity: Entity) -> some View {
        let img = state.engine.world.getComponent(UIImageComponent.self, from: entity)

        MCSection(title: "UI Image") {
            removeComponentButton(UIImageComponent.self, from: entity, label: "Remove UI Image")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Texture")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    TextField("path/to/texture", text: Binding(
                        get: { img?.texturePath ?? "" },
                        set: { val in state.updateComponent(UIImageComponent.self, on: entity) { $0.texturePath = val } }
                    ))
                    .textFieldStyle(.plain)
                    .font(MCTheme.fontCaption)
                }

                Toggle("Preserve Aspect", isOn: Binding(
                    get: { img?.preserveAspect ?? true },
                    set: { val in state.updateComponent(UIImageComponent.self, on: entity) { $0.preserveAspect = val } }
                ))
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func uiPanelSection(_ entity: Entity) -> some View {
        MCSection(title: "UI Panel") {
            removeComponentButton(UIPanelComponent.self, from: entity, label: "Remove UI Panel")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                liveFloatRow(label: "Corner R.", entity: entity,
                    get: {
                        state.engine.world.getComponent(UIPanelComponent.self, from: entity)?.cornerRadius ?? 8
                    },
                    set: { val in state.updateComponent(UIPanelComponent.self, on: entity) { $0.cornerRadius = val } })

                liveFloatRow(label: "Border W.", entity: entity,
                    get: {
                        state.engine.world.getComponent(UIPanelComponent.self, from: entity)?.borderWidth ?? 1
                    },
                    set: { val in state.updateComponent(UIPanelComponent.self, on: entity) { $0.borderWidth = val } })
            }
        }
    }

    // MARK: - Texture Asset Inspector

    @ViewBuilder
    private func textureAssetInspector(entry: AssetEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                texturePreviewSection(entry: entry)
                sectionDivider()
                textureInfoSection(entry: entry)
                sectionDivider()
                textureImportSettingsSection(entry: entry)
            }
            .padding(MCTheme.panelPadding)
        }
        .background(MCTheme.background)
    }

    @ViewBuilder
    private func texturePreviewSection(entry: AssetEntry) -> some View {
        MCSection(title: "Preview") {
            VStack(spacing: 8) {
                if let url = state.assetDatabase.resolveURL(for: entry.guid),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(MCTheme.panelBorder, lineWidth: 1)
                        )
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(MCTheme.textTertiary)
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func textureInfoSection(entry: AssetEntry) -> some View {
        let info = loadTextureInfo(for: entry)

        MCSection(title: "Info") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Name", value: "\(entry.name).\(entry.fileExtension)")
                infoRow("Format", value: entry.fileExtension.uppercased())
                if let info = info {
                    infoRow("Dimensions", value: "\(info.width) × \(info.height)")
                    infoRow("Color Space", value: info.colorSpace)
                }
                infoRow("File Size", value: formatByteSize(entry.fileSize))
            }
        }
    }

    @ViewBuilder
    private func textureImportSettingsSection(entry: AssetEntry) -> some View {
        MCSection(title: "Import Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: .constant(TextureUsageType.diffuse)) {
                    ForEach(TextureUsageType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                Picker("Compression", selection: .constant(TextureCompression.astc6x6)) {
                    ForEach(TextureCompression.allCases, id: \.self) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(MCTheme.textPrimary)

                Toggle("Generate Mipmaps", isOn: .constant(true))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)

                Toggle("sRGB", isOn: .constant(true))
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
    }

    private struct TextureInfo {
        let width: Int
        let height: Int
        let colorSpace: String
    }

    private func loadTextureInfo(for entry: AssetEntry) -> TextureInfo? {
        guard let url = state.assetDatabase.resolveURL(for: entry.guid) else { return nil }
        #if canImport(CoreGraphics)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let cs = (props[kCGImagePropertyColorModel] as? String) ?? "Unknown"
        return TextureInfo(width: w, height: h, colorSpace: cs)
        #else
        return nil
        #endif
    }

    private func formatByteSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    // MARK: - Gameplay Script Section

    @ViewBuilder
    private func gameplayScriptSection(_ entity: Entity) -> some View {
        MCSection(title: "Gameplay Script") {
            Button {
                state.engine.world.removeComponent(GameplayScriptRef.self, from: entity)
                state.worldRevision += 1
                state.markDirty()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Remove Gameplay Script")
        } content: {
            let scriptNames = discoverScriptNames()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Script")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .frame(width: 70, alignment: .leading)
                    if scriptNames.isEmpty {
                        Text("No scripts found")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Picker("", selection: Binding(
                            get: {
                                state.engine.world.getComponent(GameplayScriptRef.self, from: entity)?.scriptName ?? ""
                            },
                            set: { newValue in
                                state.updateComponent(GameplayScriptRef.self, on: entity) { ref in
                                    ref.scriptName = newValue
                                    ref.properties = discoverDefaultProperties(for: newValue)
                                }
                            }
                        )) {
                            Text("-- None --").tag("")
                            ForEach(scriptNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                let discoveredProps = discoverProperties(
                    for: state.engine.world.getComponent(GameplayScriptRef.self, from: entity)?.scriptName ?? ""
                )

                if !discoveredProps.isEmpty {
                    ForEach(discoveredProps, id: \.name) { prop in
                        HStack(spacing: 6) {
                            Text(prop.name)
                                .font(MCTheme.fontCaption)
                                .foregroundStyle(MCTheme.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            TextField(prop.defaultValue, text: Binding(
                                get: {
                                    state.engine.world.getComponent(GameplayScriptRef.self, from: entity)?
                                        .properties[prop.name] ?? prop.defaultValue
                                },
                                set: { newValue in
                                    state.updateComponent(GameplayScriptRef.self, on: entity) { r in
                                        r.properties[prop.name] = newValue
                                    }
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(MCTheme.inputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MCTheme.inputBorder, lineWidth: 1))
                            Text(prop.type)
                                .font(.system(size: 9))
                                .foregroundStyle(MCTheme.textTertiary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func gameplayDirectories() -> [URL] {
        var dirs: [URL] = []
        if let gameplayDir = state.projectManager.directoryURL(for: .gameplay) {
            dirs.append(gameplayDir)
            let genDir = gameplayDir.appendingPathComponent(".generated")
            if FileManager.default.fileExists(atPath: genDir.path) {
                dirs.append(genDir)
            }
        }
        return dirs
    }

    private func discoverScriptNames() -> [String] {
        let dirs = gameplayDirectories()
        guard !dirs.isEmpty else { return [] }
        return GameplayScriptScanner().scriptNames(in: dirs)
    }

    private func discoverProperties(for scriptName: String) -> [ScriptProperty] {
        guard !scriptName.isEmpty else { return [] }
        let dirs = gameplayDirectories()
        guard !dirs.isEmpty else { return [] }
        return GameplayScriptScanner().properties(forScript: scriptName, in: dirs)
    }

    private func discoverDefaultProperties(for scriptName: String) -> [String: String] {
        let props = discoverProperties(for: scriptName)
        var dict: [String: String] = [:]
        for p in props {
            dict[p.name] = p.defaultValue
        }
        return dict
    }

    @ViewBuilder
    private func addComponentSection(_ entity: Entity) -> some View {
        HStack {
            Spacer()
            Button {
                showComponentPicker.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                    Text("Add Component")
                        .font(MCTheme.fontCaption)
                }
                .foregroundStyle(MCTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MCTheme.panelBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showComponentPicker, arrowEdge: .bottom) {
                ComponentPickerView(entity: entity) {
                    showComponentPicker = false
                }
                .environment(state)
            }
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
        MCDraggableField(label: label, displayValue: get(),
            getValue: get,
            onChanged: { v in set(v) },
            step: 0.1,
            labelWidth: 70)
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
                    .frame(maxWidth: .infinity)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Texture Import Enums

enum TextureUsageType: String, CaseIterable {
    case diffuse
    case normalMap
    case ui
    case lightmap
    case hdri
    case mask

    var displayName: String {
        switch self {
        case .diffuse:   return "Diffuse (Color)"
        case .normalMap: return "Normal Map"
        case .ui:        return "UI (Sprite)"
        case .lightmap:  return "Lightmap"
        case .hdri:      return "HDRI Environment"
        case .mask:      return "Mask / Alpha"
        }
    }
}

enum TextureCompression: String, CaseIterable {
    case none
    case astc4x4
    case astc6x6
    case astc8x8
    case bc7

    var displayName: String {
        switch self {
        case .none:    return "None (Uncompressed)"
        case .astc4x4: return "ASTC 4×4 (Best Quality)"
        case .astc6x6: return "ASTC 6×6 (Balanced)"
        case .astc8x8: return "ASTC 8×8 (Smallest)"
        case .bc7:     return "BC7 (Desktop)"
        }
    }
}
