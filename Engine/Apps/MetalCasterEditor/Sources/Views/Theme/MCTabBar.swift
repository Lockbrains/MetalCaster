import SwiftUI

struct MCTabBar: View {
    let tabs: [String]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    selected = index
                } label: {
                    Text(tabs[index])
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(
                            index == selected
                                ? MCTheme.textPrimary
                                : MCTheme.textTertiary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if index < tabs.count - 1 {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, MCTheme.panelPadding)
    }
}
