import SwiftUI

struct SceneComposerProToolPanel: View {
    @Binding var selectedTool: ComposerToolMode
    @Binding var brushSettings: ComposerBrushSettings

    var body: some View {
        VStack(spacing: 0) {
            toolButtons
            Divider().background(MCTheme.panelBorder)
            brushPanel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tool Buttons

    private var toolButtons: some View {
        VStack(spacing: 2) {
            ForEach(ComposerToolMode.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(tool.rawValue)
                            .font(MCTheme.fontCaption)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedTool == tool ? Color.white.opacity(0.08) : Color.clear)
                    .foregroundStyle(selectedTool == tool ? MCTheme.textPrimary : MCTheme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    // MARK: - Brush Settings

    @ViewBuilder
    private var brushPanel: some View {
        if selectedTool == .brush || selectedTool == .terrain {
            VStack(alignment: .leading, spacing: 8) {
                Text("BRUSH")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MCTheme.textTertiary)
                    .tracking(0.8)

                HStack(spacing: 4) {
                    ForEach(ComposerBrushMode.allCases) { mode in
                        Button {
                            brushSettings.mode = mode
                        } label: {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11))
                                .frame(width: 24, height: 24)
                                .background(brushSettings.mode == mode ? Color.white.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(brushSettings.mode == mode ? MCTheme.textPrimary : MCTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help(mode.rawValue)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    labeledSlider("Radius", value: $brushSettings.radius, range: 1...200)
                    labeledSlider("Strength", value: $brushSettings.strength, range: 0...1)
                    labeledSlider("Falloff", value: $brushSettings.falloff, range: 0...1)
                }
            }
            .padding(8)
        }
    }

    private func labeledSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(MCTheme.fontMono)
                    .foregroundStyle(MCTheme.textTertiary)
            }
            Slider(value: value, in: range)
                .controlSize(.mini)
        }
    }
}
