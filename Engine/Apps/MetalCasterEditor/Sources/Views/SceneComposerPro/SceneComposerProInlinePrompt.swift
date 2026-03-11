import SwiftUI

/// The Space-key triggered floating AI dialog that anchors near selected entities in the viewport.
struct SceneComposerProInlinePrompt: View {
    let anchorPoint: CGPoint
    let context: InlinePromptContext
    let spatialMode: SpatialCoordinateMode
    let viewportSize: CGSize
    var onSpatialModeChanged: (SpatialCoordinateMode) -> Void
    var onSubmit: (String) -> Void
    var onDismiss: () -> Void

    @State private var inputText: String = ""
    @State private var responseText: String? = nil
    @State private var isExecuting: Bool = false
    @FocusState private var isFocused: Bool

    private let promptWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            contextHeader
            Divider().background(Color.white.opacity(0.15))
            inputRow
            if let response = responseText {
                Divider().background(Color.white.opacity(0.15))
                responseRow(response)
            }
        }
        .frame(width: promptWidth)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .position(anchoredPosition)
        .onAppear { isFocused = true }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(context.isEntity ? MCTheme.statusGreen : context.isTerrainPoint ? MCTheme.statusOrange : MCTheme.statusBlue)
                .frame(width: 6, height: 6)

            Text(context.displayLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Menu {
                ForEach(SpatialCoordinateMode.allCases) { mode in
                    Button {
                        onSpatialModeChanged(mode)
                    } label: {
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: spatialMode.icon)
                        .font(.system(size: 9))
                    Text(spatialMode.rawValue)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 6) {
            Text(">")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            TextField("", text: $inputText, prompt: Text("Type a command...").foregroundStyle(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isFocused)
                .onSubmit {
                    guard !inputText.isEmpty else { return }
                    isExecuting = true
                    onSubmit(inputText)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Response

    private func responseRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack {
                Spacer()
                Button("Undo") {
                    // TODO: Hook into undo system
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)

                Button("OK") {
                    onDismiss()
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Positioning

    /// Anchors the prompt to the right-above of the anchor point, flipping if near edges.
    private var anchoredPosition: CGPoint {
        let offsetX: CGFloat = 20
        let offsetY: CGFloat = -20
        let estimatedHeight: CGFloat = responseText != nil ? 140 : 80

        var x = anchorPoint.x + promptWidth / 2 + offsetX
        var y = anchorPoint.y - estimatedHeight / 2 + offsetY

        if x + promptWidth / 2 > viewportSize.width {
            x = anchorPoint.x - promptWidth / 2 - offsetX
        }
        if y - estimatedHeight / 2 < 0 {
            y = anchorPoint.y + estimatedHeight / 2 - offsetY
        }

        return CGPoint(x: x, y: y)
    }

    /// Updates the response text from external state.
    func withResponse(_ text: String?) -> SceneComposerProInlinePrompt {
        var copy = self
        copy._responseText = State(initialValue: text)
        return copy
    }
}
