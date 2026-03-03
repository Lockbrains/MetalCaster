import SwiftUI
import AppKit

/// A numeric input field that supports two interaction modes:
/// 1. Direct keyboard text entry (double-click to edit)
/// 2. Horizontal drag on the axis label to scrub the value
///
/// Uses an optional localValue: non-nil only during active drag for instant feedback.
/// When nil, falls back to displayValue from parent — always fresh, no sync needed.
struct MCDraggableField: View {
    let label: String
    let displayValue: Float
    let getValue: () -> Float
    let onChanged: (Float) -> Void
    var step: Float = 0.1
    var labelWidth: CGFloat = 14

    @State private var isEditing = false
    @State private var editText = ""
    @State private var dragOrigin: Float = 0
    @State private var dragging = false
    @State private var localValue: Float? = nil
    @FocusState private var isFocused: Bool

    private var shownValue: Float { localValue ?? displayValue }

    var body: some View {
        HStack(spacing: 4) {
            dragLabel
            valueDisplay
        }
        .onChange(of: displayValue) { _, _ in
            if !dragging { localValue = nil }
        }
    }

    // MARK: - Draggable Label

    private var dragLabel: some View {
        Text(label)
            .font(MCTheme.fontSmall)
            .foregroundStyle(MCTheme.textTertiary)
            .frame(width: labelWidth, alignment: labelWidth > 20 ? .leading : .center)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:  NSCursor.resizeLeftRight.push()
                case .ended:   NSCursor.pop()
                }
            }
            .simultaneousGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    dragOrigin = getValue()
                }
                let newVal = dragOrigin + Float(value.translation.width) * step * 0.1
                localValue = newVal
                onChanged(newVal)
            }
            .onEnded { _ in
                localValue = getValue()
                dragging = false
            }
    }

    // MARK: - Value Display / Edit

    @ViewBuilder
    private var valueDisplay: some View {
        if isEditing {
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .mcInputStyle()
                .frame(maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit { commitEdit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitEdit() }
                }
                .onAppear {
                    editText = String(format: "%.2f", shownValue)
                    isFocused = true
                }
        } else {
            Text(String(format: "%.2f", shownValue))
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MCTheme.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MCTheme.inputBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    isEditing = true
                }
        }
    }

    private func commitEdit() {
        if let val = Float(editText) {
            onChanged(val)
        }
        isEditing = false
    }
}
