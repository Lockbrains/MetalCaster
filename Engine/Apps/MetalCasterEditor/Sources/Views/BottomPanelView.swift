import SwiftUI
import MetalCasterCore
import MetalCasterAsset

struct ProjectAssetsView: View {
    @Environment(EditorState.self) private var state

    private let categories: [(name: String, color: Color, icon: String)] = [
        ("Devices", MCTheme.statusRed, "desktopcomputer"),
        ("Resources", MCTheme.statusGray, "folder"),
        ("Meshes", MCTheme.statusGray, "cube"),
        ("Scripts", MCTheme.statusGray, "doc.text"),
        ("Audios", MCTheme.statusGray, "speaker.wave.2"),
        ("Visuals", MCTheme.statusGray, "paintbrush"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(categories, id: \.name) { cat in
                    assetCategoryRow(name: cat.name, color: cat.color, icon: cat.icon)
                }
            }
            .padding(.horizontal, MCTheme.panelPadding)
            .padding(.vertical, 8)
        }
        .background(MCTheme.background)
    }

    private func assetCategoryRow(name: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            MCStatusDot(color: color)
            Image(systemName: icon)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 14)
            Text(name)
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)
            Spacer()
        }
        .frame(height: MCTheme.rowHeight)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
