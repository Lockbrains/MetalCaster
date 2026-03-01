import SwiftUI

enum MCTheme {

    // MARK: - Colors

    static let background = Color.black
    static let panelBorder = Color.white.opacity(0.15)
    static let panelBackground = Color.black
    static let surfaceHover = Color.white.opacity(0.06)
    static let surfaceSelected = Color.white.opacity(0.1)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.3)

    static let statusGreen = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let statusRed = Color(red: 0.95, green: 0.3, blue: 0.3)
    static let statusGray = Color.white.opacity(0.35)
    static let statusBlue = Color(red: 0.3, green: 0.55, blue: 1.0)

    static let inputBorder = Color.white.opacity(0.12)
    static let inputBackground = Color.white.opacity(0.04)

    // MARK: - Typography

    static let fontBody = Font.system(size: 13)
    static let fontCaption = Font.system(size: 11)
    static let fontSmall = Font.system(size: 10)
    static let fontMono = Font.system(size: 12, design: .monospaced)
    static let fontTitle = Font.system(size: 13, weight: .semibold)
    static let fontPanelLabel = Font.system(size: 11)
    static let fontPanelLabelBold = Font.system(size: 11, weight: .bold)

    // MARK: - Dimensions

    static let panelCornerRadius: CGFloat = 8
    static let panelBorderWidth: CGFloat = 1
    static let panelGap: CGFloat = 4
    static let panelPadding: CGFloat = 10
    static let statusDotSize: CGFloat = 7
    static let rowHeight: CGFloat = 24
    static let indentWidth: CGFloat = 16
}

// MARK: - View Modifiers

struct MCInputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(MCTheme.fontBody)
            .foregroundStyle(MCTheme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MCTheme.inputBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(MCTheme.inputBorder, lineWidth: 1)
            )
    }
}

extension View {
    func mcInputStyle() -> some View {
        modifier(MCInputFieldStyle())
    }
}

// MARK: - Status Dot

struct MCStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: MCTheme.statusDotSize, height: MCTheme.statusDotSize)
    }
}
