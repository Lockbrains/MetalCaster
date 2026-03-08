#if os(macOS)
import SwiftUI
import MetalCasterRenderer

// MARK: - Template Definition

enum ShaderCanvasTemplate: String, CaseIterable, Identifiable {
    case fullscreenMaterial = "Fullscreen Material"
    case litMaterial = "Lit Material"
    case unlitMaterial = "Unlit Material"
    case empty = "Empty"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fullscreenMaterial: return "rectangle.fill.on.rectangle.fill"
        case .litMaterial:        return "light.max"
        case .unlitMaterial:      return "circle.lefthalf.filled"
        case .empty:              return "doc"
        }
    }

    var subtitle: String {
        switch self {
        case .fullscreenMaterial: return "Screen-space post-processing"
        case .litMaterial:        return "PBR surface with lighting"
        case .unlitMaterial:      return "Unlit surface shader"
        case .empty:              return "Blank workspace"
        }
    }

    var description: String {
        switch self {
        case .fullscreenMaterial:
            return "Creates a screen-space material with a fullscreen triangle pass. Ideal for post-processing effects, procedural backgrounds, image filters, and any effect that operates in screen UV space.\n\nThe template includes a single Fullscreen shader layer with access to the previous pass texture and time uniform."
        case .litMaterial:
            return "Creates a physically-based lit material with Vertex and Fragment shader layers. The fragment shader receives world-space normals, positions, and view direction for computing lighting.\n\nIncludes a default Blinn-Phong shading model that you can customize into any lighting response — Lambert, PBR, toon, or your own."
        case .unlitMaterial:
            return "Creates an unlit surface material with Vertex and Fragment shader layers. The fragment shader receives object-space normals and UV coordinates but no lighting data.\n\nPerfect for UI elements, particles, stylized effects, or any surface where you want full control over the final color without a lighting model."
        case .empty:
            return "An empty workspace with no shader layers. Start from scratch by adding Vertex, Fragment, or Fullscreen layers manually using the toolbar.\n\nChoose this when you want complete freedom over the shader architecture."
        }
    }

    var layerSummary: String {
        switch self {
        case .fullscreenMaterial: return "1x Fullscreen"
        case .litMaterial:        return "1x Vertex + 1x Fragment"
        case .unlitMaterial:      return "1x Vertex + 1x Fragment"
        case .empty:              return "None"
        }
    }

    var dataFlowSummary: String {
        switch self {
        case .fullscreenMaterial: return "Time"
        case .litMaterial:        return "Normal, UV, Time, World Position, World Normal, View Direction"
        case .unlitMaterial:      return "Normal, UV, Time"
        case .empty:              return "Normal, UV, Time (default)"
        }
    }

    var dataFlowConfig: DataFlowConfig {
        switch self {
        case .fullscreenMaterial:
            return DataFlowConfig(normalEnabled: true, uvEnabled: true, timeEnabled: true)
        case .litMaterial:
            return DataFlowConfig(
                normalEnabled: true, uvEnabled: true, timeEnabled: true,
                worldPositionEnabled: true, worldNormalEnabled: true, viewDirectionEnabled: true
            )
        case .unlitMaterial:
            return DataFlowConfig(normalEnabled: true, uvEnabled: true, timeEnabled: true)
        case .empty:
            return DataFlowConfig()
        }
    }

    func initialShaders() -> [ActiveShader] {
        let config = dataFlowConfig
        switch self {
        case .fullscreenMaterial:
            return [
                ActiveShader(category: .fullscreen, name: "Fullscreen 1", code: ShaderSnippets.fullscreenDemo)
            ]
        case .litMaterial:
            return [
                ActiveShader(category: .vertex, name: "Vertex 1", code: ShaderSnippets.generateDefaultVertexShader(config: config)),
                ActiveShader(category: .fragment, name: "Fragment 1", code: ShaderSnippets.litMaterialFragment)
            ]
        case .unlitMaterial:
            return [
                ActiveShader(category: .vertex, name: "Vertex 1", code: ShaderSnippets.generateDefaultVertexShader(config: config)),
                ActiveShader(category: .fragment, name: "Fragment 1", code: ShaderSnippets.fragmentTemplate)
            ]
        case .empty:
            return []
        }
    }
}

// MARK: - Template Picker View

struct ShaderCanvasTemplatePicker: View {
    @State private var selectedTemplate: ShaderCanvasTemplate = .litMaterial
    var onCancel: () -> Void
    var onCreate: (ShaderCanvasTemplate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider().background(MCTheme.panelBorder)

            HStack(spacing: 0) {
                templateList
                Divider().background(MCTheme.panelBorder)
                detailPanel
            }

            Divider().background(MCTheme.panelBorder)

            footerBar
        }
        .frame(width: 680, height: 460)
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 14))
                .foregroundStyle(MCTheme.statusBlue)
            Text("Choose a template for your new shader:")
                .font(MCTheme.fontTitle)
                .foregroundStyle(MCTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Template List (Left)

    private var templateList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ShaderCanvasTemplate.allCases) { template in
                templateRow(template)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 220)
        .background(Color.white.opacity(0.02))
    }

    private func templateRow(_ template: ShaderCanvasTemplate) -> some View {
        let isSelected = selectedTemplate == template
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTemplate = template
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? MCTheme.statusBlue : MCTheme.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(template.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(MCTheme.textPrimary)
                    Text(template.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? MCTheme.statusBlue.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Panel (Right)

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: selectedTemplate.icon)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(MCTheme.statusBlue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTemplate.rawValue)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(MCTheme.textPrimary)
                            Text(selectedTemplate.subtitle)
                                .font(MCTheme.fontCaption)
                                .foregroundStyle(MCTheme.textSecondary)
                        }
                    }

                    Text(selectedTemplate.description)
                        .font(.system(size: 12))
                        .foregroundStyle(MCTheme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().background(MCTheme.panelBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(label: "Layers", value: selectedTemplate.layerSummary)
                        infoRow(label: "Data Flow", value: selectedTemplate.dataFlowSummary)
                    }
                }
                .padding(24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(MCTheme.textPrimary)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Create") { onCreate(selectedTemplate) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(MCTheme.statusBlue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
    }
}
#endif
