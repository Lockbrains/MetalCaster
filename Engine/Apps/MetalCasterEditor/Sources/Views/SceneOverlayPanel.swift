import SwiftUI

struct SceneOverlayPanel: View {
    @Environment(EditorState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolSection
            displaySection
            viewSection
        }
        .padding(10)
        .frame(width: 156)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: MCTheme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MCTheme.panelCornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(8)
    }

    // MARK: - Tool Mode (QWER)

    private var toolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tool")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            HStack(spacing: 4) {
                ForEach(EditorState.SceneToolMode.allCases, id: \.rawValue) { mode in
                    toolButton(mode)
                }
            }
        }
    }

    private func toolButton(_ mode: EditorState.SceneToolMode) -> some View {
        Button {
            state.sceneToolMode = mode
        } label: {
            VStack(spacing: 2) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11))
                Text(mode.shortcut)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .frame(width: 30, height: 32)
            .foregroundStyle(state.sceneToolMode == mode ? MCTheme.textPrimary : MCTheme.textTertiary)
            .background(
                state.sceneToolMode == mode
                    ? Color.white.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Display

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            VStack(spacing: 2) {
                ForEach(EditorState.SceneRenderMode.allCases, id: \.rawValue) { mode in
                    renderModeRow(mode)
                }
            }

            Toggle(isOn: Binding(
                get: { state.showGrid },
                set: { state.showGrid = $0 }
            )) {
                Text("Grid")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: Binding(
                get: { state.invertPan },
                set: { state.invertPan = $0 }
            )) {
                Text("Invert Pan")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private func renderModeRow(_ mode: EditorState.SceneRenderMode) -> some View {
        Button {
            state.sceneRenderMode = mode
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.sceneRenderMode == mode ? MCTheme.textPrimary : MCTheme.textTertiary)
                    .frame(width: 5, height: 5)
                Text(mode.rawValue)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(
                        state.sceneRenderMode == mode
                            ? MCTheme.textPrimary
                            : MCTheme.textSecondary
                    )
                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                state.sceneRenderMode == mode
                    ? Color.white.opacity(0.06)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    // MARK: - View (Ortho/Perspective)

    private var viewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("View")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            Text(state.orthoPreset.rawValue)
                .font(MCTheme.fontCaption)
                .foregroundStyle(
                    state.isOrthographic ? MCTheme.statusBlue : MCTheme.textPrimary
                )

            if state.isOrthographic {
                Text("Orthographic")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
    }
}
