import SwiftUI

struct MCPanel<Content: View>: View {
    let titleNormal: String
    let titleBold: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            panelTitle
        }
        .background(MCTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: MCTheme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MCTheme.panelCornerRadius)
                .stroke(MCTheme.panelBorder, lineWidth: MCTheme.panelBorderWidth)
        )
    }

    private var panelTitle: some View {
        HStack(spacing: 4) {
            Text(titleNormal)
                .font(MCTheme.fontPanelLabel)
                .foregroundStyle(MCTheme.textSecondary)
            Text(titleBold)
                .font(MCTheme.fontPanelLabelBold)
                .foregroundStyle(MCTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, MCTheme.panelPadding)
        .padding(.vertical, 6)
    }
}
