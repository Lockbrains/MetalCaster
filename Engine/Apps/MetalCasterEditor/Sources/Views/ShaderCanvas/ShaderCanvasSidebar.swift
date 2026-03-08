#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MetalCasterRenderer
import MetalCasterAsset

// MARK: - Sidebar Container

/// Represents a PP volume available in the scene.
struct PPVolumeInfo: Identifiable, Equatable {
    let id: UInt64
    let name: String
}

/// The left sidebar of Shader Canvas: Layers + Data Flow + Parameters + Textures + Helpers.
struct ShaderCanvasSidebar: View {
    @Binding var activeShaders: [ActiveShader]
    @Binding var editingShaderID: UUID?
    @Binding var dataFlowConfig: DataFlowConfig
    @Binding var paramValues: [String: [Float]]
    @Binding var textureSlots: [TextureSlot]
    @Binding var ppEnabled: Bool
    @Binding var selectedPPVolumeID: UInt64?
    var availablePPVolumes: [PPVolumeInfo]
    @Binding var studioLightingEnabled: Bool
    var onRemoveShader: (ActiveShader) -> Void
    var onImportTexture: (URL) -> String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                layersPanel
                dataFlowPanel
                texturesPanel
                parametersPanel
            }
        }
        .frame(width: 220)
    }

    // MARK: - Layers Panel

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Layers")
                    .font(.headline).foregroundColor(.white)
                Spacer()
                studioLightToggle
                ppToggle
            }
            .padding(.bottom, 4)

            if activeShaders.isEmpty {
                Text("No Active Shaders")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            } else {
                ForEach(activeShaders) { shader in
                    HStack {
                        Image(systemName: shader.category.icon)
                            .foregroundColor(layerColor(for: shader.category))
                        Text(verbatim: shader.name)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            withAnimation { editingShaderID = shader.id }
                        } label: {
                            Image(systemName: "pencil.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.7))

                        Button { onRemoveShader(shader) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red.opacity(0.8))
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(editingShaderID == shader.id
                                  ? Color.white.opacity(0.1)
                                  : Color.black.opacity(0.4))
                    )
                }
            }
        }
        .sidebarSection()
    }

    // MARK: - Studio Lighting Toggle

    private var studioLightToggle: some View {
        Button { studioLightingEnabled.toggle() } label: {
            Image(systemName: studioLightingEnabled ? "light.recessed.3.fill" : "light.recessed.3")
                .font(.system(size: 12))
                .foregroundColor(studioLightingEnabled ? .yellow : .white.opacity(0.4))
        }
        .buttonStyle(.plain)
        .help(studioLightingEnabled ? "Studio Lighting On" : "Studio Lighting Off")
    }

    // MARK: - Post Processing Toggle

    @ViewBuilder
    private var ppToggle: some View {
        if availablePPVolumes.isEmpty {
            Button {} label: {
                Image(systemName: "camera.filters")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help("No Post Processing Volume in scene")
        } else if availablePPVolumes.count == 1 {
            Button { ppEnabled.toggle() } label: {
                Image(systemName: "camera.filters")
                    .font(.system(size: 12))
                    .foregroundColor(ppEnabled ? .yellow : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(ppEnabled ? "Disable Post Processing" : "Enable Post Processing")
        } else {
            Menu {
                Button {
                    ppEnabled = false
                    selectedPPVolumeID = nil
                } label: {
                    Label("Off", systemImage: ppEnabled ? "" : "checkmark")
                }
                Divider()
                ForEach(availablePPVolumes) { vol in
                    Button {
                        selectedPPVolumeID = vol.id
                        ppEnabled = true
                    } label: {
                        HStack {
                            Text(vol.name)
                            if ppEnabled && selectedPPVolumeID == vol.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "camera.filters")
                    .font(.system(size: 12))
                    .foregroundColor(ppEnabled ? .yellow : .white.opacity(0.4))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("Post Processing Volume")
        }
    }

    private func layerColor(for category: ShaderCategory) -> Color {
        switch category {
        case .helper: return .cyan
        case .vertex: return .blue
        case .fragment: return .purple
        case .fullscreen: return .orange
        }
    }

    @State private var isStructPreviewExpanded = false

    // MARK: - Data Flow Panel

    private var dataFlowPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Data Flow")
                .font(.headline).foregroundColor(.white)
                .padding(.bottom, 2)

            Text("Vertex fields shared across all mesh shaders")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 4)

            Group {
                dataFlowToggle(label: "Normal", icon: "arrow.up.right", binding: $dataFlowConfig.normalEnabled, locked: false)
                dataFlowToggle(label: "UV", icon: "squareshape.split.2x2", binding: $dataFlowConfig.uvEnabled, locked: false)
                dataFlowToggle(label: "Time", icon: "clock", binding: $dataFlowConfig.timeEnabled, locked: false)
            }

            Divider().background(Color.white.opacity(0.2))

            Text("Extended")
                .font(.caption).foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)

            Group {
                dataFlowToggle(label: "World Position", icon: "globe", binding: $dataFlowConfig.worldPositionEnabled, locked: false)
                dataFlowToggle(label: "World Normal", icon: "arrow.up.forward.circle", binding: $dataFlowConfig.worldNormalEnabled, locked: !dataFlowConfig.normalEnabled)
                dataFlowToggle(label: "View Direction", icon: "eye", binding: $dataFlowConfig.viewDirectionEnabled, locked: !dataFlowConfig.worldPositionEnabled)
            }

            Divider().background(Color.white.opacity(0.2))

            Text("TBN (Tangent Space)")
                .font(.caption).foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)

            Group {
                dataFlowToggle(label: "Tangent", icon: "arrow.right", binding: $dataFlowConfig.tangentEnabled, locked: false)
                dataFlowToggle(label: "Bitangent", icon: "arrow.up.right.and.arrow.down.left", binding: $dataFlowConfig.bitangentEnabled, locked: !dataFlowConfig.tangentEnabled)
            }

            Divider().background(Color.white.opacity(0.2))

            structPreview
        }
        .sidebarSection()
        .onChange(of: dataFlowConfig) { _ in
            dataFlowConfig.resolveDependencies()
        }
    }

    private func dataFlowToggle(label: String, icon: String, binding: Binding<Bool>, locked: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(locked ? .gray : .blue)
                .frame(width: 16)
            Text(label)
                .font(.caption).foregroundColor(locked ? .gray : .white)
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(locked)
        }
        .padding(.vertical, 1)
    }

    private var structPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isStructPreviewExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isStructPreviewExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Generated Structs")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isStructPreviewExpanded {
                ScrollView {
                    Text(ShaderSnippets.generateStructPreview(config: dataFlowConfig))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }

    // MARK: - Parameters Panel

    private var allParsedParams: [ShaderParam] {
        guard let editingID = editingShaderID,
              let shader = activeShaders.first(where: { $0.id == editingID }) else { return [] }
        return ShaderSnippets.parseParams(from: shader.code)
    }

    private var parametersPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Parameters")
                    .font(.headline).foregroundColor(.white)
                Spacer()

                if editingShaderID != nil {
                    Menu {
                        Button("Float Slider") { addParam(type: .float, withRange: true) }
                        Button("Float Input") { addParam(type: .float, withRange: false) }
                        Divider()
                        Button("Color") { addParam(type: .color, withRange: false) }
                        Divider()
                        Button("Float2") { addParam(type: .float2, withRange: false) }
                        Button("Float3") { addParam(type: .float3, withRange: false) }
                        Button("Float4") { addParam(type: .float4, withRange: false) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                    .help("Add parameter to current shader")
                }
            }

            if allParsedParams.isEmpty {
                Text(editingShaderID != nil
                     ? "Use + to add parameters, or write\n// @param _name type default ..."
                     : "Select a layer to see parameters")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.vertical, 4)
            } else {
                ForEach(allParsedParams, id: \.name) { param in
                    paramControl(for: param)
                }
            }
        }
        .sidebarSection()
    }

    // MARK: - Parameter Controls

    @ViewBuilder
    private func paramControl(for param: ShaderParam) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(paramDisplayName(param.name))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))

            switch param.type {
            case .float:
                if let minVal = param.minValue, let maxVal = param.maxValue {
                    HStack(spacing: 4) {
                        Slider(
                            value: paramBinding(name: param.name, index: 0, defaultValue: param.defaultValue),
                            in: minVal...maxVal
                        )
                        .controlSize(.mini)
                        Text(String(format: "%.2f", currentParamValue(param.name, 0, param.defaultValue)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 36, alignment: .trailing)
                    }
                } else {
                    floatInputField(name: param.name, index: 0, defaultValue: param.defaultValue)
                }
            case .color:
                colorControl(name: param.name, defaultValue: param.defaultValue)
            case .float2:
                HStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { i in
                        floatInputField(name: param.name, index: i, defaultValue: param.defaultValue)
                    }
                }
            case .float3:
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        floatInputField(name: param.name, index: i, defaultValue: param.defaultValue)
                    }
                }
            case .float4:
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        floatInputField(name: param.name, index: i, defaultValue: param.defaultValue)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func floatInputField(name: String, index: Int, defaultValue: [Float]) -> some View {
        let labels = ["X", "Y", "Z", "W"]
        return HStack(spacing: 2) {
            if defaultValue.count > 1 {
                Text(labels[min(index, 3)])
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 10)
            }
            TextField("", value: paramBinding(name: name, index: index, defaultValue: defaultValue), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(3)
        }
    }

    private func colorControl(name: String, defaultValue: [Float]) -> some View {
        let colorBinding = Binding<Color>(
            get: {
                Color(
                    red: Double(currentParamValue(name, 0, defaultValue)),
                    green: Double(currentParamValue(name, 1, defaultValue)),
                    blue: Double(currentParamValue(name, 2, defaultValue))
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                paramValues[name] = [Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent)]
            }
        )
        return ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden()
    }

    // MARK: - Parameter Helpers

    private func paramDisplayName(_ internalName: String) -> String {
        internalName.hasPrefix("_") ? String(internalName.dropFirst()) : internalName
    }

    private func currentParamValue(_ name: String, _ index: Int, _ defaultValue: [Float]) -> Float {
        let vals = paramValues[name] ?? defaultValue
        return index < vals.count ? vals[index] : (index < defaultValue.count ? defaultValue[index] : 0)
    }

    private func paramBinding(name: String, index: Int, defaultValue: [Float]) -> Binding<Float> {
        Binding<Float>(
            get: { currentParamValue(name, index, defaultValue) },
            set: { newVal in
                var vals = paramValues[name] ?? defaultValue
                while vals.count <= index { vals.append(0) }
                vals[index] = newVal
                paramValues[name] = vals
            }
        )
    }

    // MARK: - Textures Panel

    private static let acceptedImageTypes: [UTType] = [.png, .jpeg, .tiff]

    private var texturesPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Textures")
                    .font(.headline).foregroundColor(.white)
                Spacer()
                Button { addTextureSlot() } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }.buttonStyle(.plain).help("Add texture slot")
            }

            Text("Bound to fragment_main via [[texture(N)]]")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
                .padding(.bottom, 2)

            if textureSlots.isEmpty {
                Text("No textures bound.\nDrag an image here or add a slot.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.vertical, 4)
            } else {
                ForEach($textureSlots) { $slot in
                    textureSlotRow(slot: $slot)
                }
            }
        }
        .sidebarSection()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleTextureDrop(providers: providers, intoSlot: nil)
        }
    }

    private func textureSlotRow(slot: Binding<TextureSlot>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("[\(slot.wrappedValue.bindingIndex)]")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.7))
                TextField("name", text: slot.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Button { removeTextureSlot(slot.wrappedValue) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.7))
                }.buttonStyle(.plain)
            }

            Button {
                pickTextureFile { path in slot.wrappedValue.filePath = path }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: slot.wrappedValue.filePath != nil ? "photo.fill" : "photo")
                        .font(.system(size: 10))
                        .foregroundColor(slot.wrappedValue.filePath != nil ? .green : .white.opacity(0.5))
                    Text(slot.wrappedValue.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose or drag image...")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
            }.buttonStyle(.plain)
        }
        .padding(6)
        .background(Color.black.opacity(0.3))
        .cornerRadius(6)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleTextureDrop(providers: providers, intoSlot: slot)
        }
    }

    private func pickTextureFile(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Import Texture"
        panel.allowedContentTypes = Self.acceptedImageTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let path = onImportTexture(url) {
                completion(path)
            }
        }
    }

    private func handleTextureDrop(providers: [NSItemProvider], intoSlot slot: Binding<TextureSlot>?) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let ext = url.pathExtension.lowercased()
            guard AssetCategory.textures.acceptedExtensions.contains(ext) else { return }
            DispatchQueue.main.async {
                if let path = onImportTexture(url) {
                    if let slot {
                        slot.wrappedValue.filePath = path
                    } else {
                        let usedIndices = Set(textureSlots.map(\.bindingIndex))
                        var nextIndex = 0
                        while usedIndices.contains(nextIndex) { nextIndex += 1 }
                        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                        textureSlots.append(TextureSlot(name: name, bindingIndex: nextIndex))
                        if let idx = textureSlots.indices.last {
                            textureSlots[idx].filePath = path
                        }
                    }
                }
            }
        }
        return true
    }

    private func addTextureSlot() {
        let usedIndices = Set(textureSlots.map(\.bindingIndex))
        var nextIndex = 0
        while usedIndices.contains(nextIndex) { nextIndex += 1 }
        textureSlots.append(TextureSlot(name: "texture\(nextIndex)", bindingIndex: nextIndex))
    }

    private func removeTextureSlot(_ slot: TextureSlot) {
        textureSlots.removeAll { $0.id == slot.id }
    }

    // MARK: - Parameter Helpers

    private func addParam(type: ParamType, withRange: Bool) {
        guard let editingID = editingShaderID,
              let index = activeShaders.firstIndex(where: { $0.id == editingID }) else { return }

        let existingNames = Set(allParsedParams.map(\.name))
        let base: String
        switch type {
        case .float: base = "value"; case .float2: base = "offset"
        case .float3: base = "direction"; case .float4: base = "vector"; case .color: base = "tint"
        }
        var name = "_\(base)"
        if existingNames.contains(name) {
            for i in 2...99 {
                let c = "_\(base)\(i)"
                if !existingNames.contains(c) { name = c; break }
            }
        }

        let directive: String
        switch type {
        case .float:  directive = withRange ? "// @param \(name) float 0.5 0.0 1.0" : "// @param \(name) float 0.0"
        case .float2: directive = "// @param \(name) float2 0.0 0.0"
        case .float3: directive = "// @param \(name) float3 0.0 0.0 0.0"
        case .float4: directive = "// @param \(name) float4 0.0 0.0 0.0 0.0"
        case .color:  directive = "// @param \(name) color 1.0 1.0 1.0"
        }

        activeShaders[index].code = directive + "\n" + activeShaders[index].code
    }
}

// MARK: - Sidebar Section Modifier

private struct SidebarSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
    }
}

private extension View {
    func sidebarSection() -> some View {
        modifier(SidebarSectionModifier())
    }
}
#endif
