import SwiftUI
import MetalCasterScene

struct SceneComposerProInspector: View {
    @Binding var terrain: TerrainComponent?
    @Binding var needsRegeneration: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if var t = terrain {
                    terrainSection(terrain: Binding(
                        get: { t },
                        set: { t = $0; terrain = $0 }
                    ))
                } else {
                    emptyState
                }
            }
            .padding(10)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mountain.2")
                .font(.system(size: 28))
                .foregroundStyle(MCTheme.textTertiary)
            Text("No terrain selected")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Terrain Section

    private func terrainSection(terrain: Binding<TerrainComponent>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("TERRAIN")

            Group {
                paramRow("Resolution") {
                    Picker("", selection: terrain.heightmapResolution) {
                        Text("512").tag(512)
                        Text("1024").tag(1024)
                        Text("2048").tag(2048)
                        Text("4096").tag(4096)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }

                paramRow("World Size") {
                    HStack(spacing: 4) {
                        floatField(value: Binding(
                            get: { terrain.wrappedValue.worldSize.x },
                            set: { terrain.wrappedValue.worldSize.x = $0 }
                        ))
                        Text("x")
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textTertiary)
                        floatField(value: Binding(
                            get: { terrain.wrappedValue.worldSize.y },
                            set: { terrain.wrappedValue.worldSize.y = $0 }
                        ))
                    }
                }

                paramRow("Max Height") {
                    floatField(value: terrain.maxHeight)
                }

                paramRow("LOD Levels") {
                    Stepper(value: terrain.lodLevels, in: 1...10) {
                        Text("\(terrain.wrappedValue.lodLevels)")
                            .font(MCTheme.fontMono)
                            .foregroundStyle(MCTheme.textPrimary)
                    }
                    .controlSize(.mini)
                }
            }

            Divider().background(MCTheme.panelBorder)
            noiseSection(terrain: terrain)

            Divider().background(MCTheme.panelBorder)
            erosionSection(terrain: terrain)

            Divider().background(MCTheme.panelBorder)

            Button("Regenerate Terrain") {
                terrain.wrappedValue.isDirty = true
                needsRegeneration = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Noise Section

    private func noiseSection(terrain: Binding<TerrainComponent>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("NOISE LAYERS")

            ForEach(terrain.noiseLayers) { $layer in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Picker("", selection: $layer.noiseType) {
                            ForEach(TerrainNoiseType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 100)

                        Spacer()

                        Toggle("", isOn: $layer.isEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    if layer.isEnabled {
                        labeledSlider("Frequency", value: $layer.frequency, range: 0.1...20)
                        labeledSlider("Amplitude", value: $layer.amplitude, range: 0...2)

                        paramRow("Octaves") {
                            Stepper(value: $layer.octaves, in: 1...12) {
                                Text("\(layer.octaves)")
                                    .font(MCTheme.fontMono)
                                    .foregroundStyle(MCTheme.textPrimary)
                            }
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
                terrain.wrappedValue.noiseLayers.append(TerrainNoiseLayer())
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Noise Layer")
                }
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Erosion Section

    private func erosionSection(terrain: Binding<TerrainComponent>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("EROSION")

            ForEach(terrain.erosionConfigs.indices, id: \.self) { idx in
                HStack {
                    Picker("", selection: terrain.erosionConfigs[idx].type) {
                        ForEach(ErosionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)

                    Spacer()

                    Toggle("", isOn: terrain.erosionConfigs[idx].isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MCTheme.textTertiary)
            .tracking(0.8)
    }

    private func paramRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }

    private func labeledSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 70, alignment: .trailing)
            Slider(value: value, in: range)
                .controlSize(.mini)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(MCTheme.fontMono)
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 40)
        }
    }

    private func floatField(value: Binding<Float>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.plain)
            .font(MCTheme.fontMono)
            .frame(width: 60)
            .mcInputStyle()
    }
}
