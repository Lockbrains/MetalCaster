import SwiftUI

struct SceneComposerProLayerPanel: View {
    @Binding var layers: [ComposerLayer]
    @Binding var selectedLayerID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MCTheme.panelBorder)
            layerList
        }
    }

    private var header: some View {
        HStack {
            Text("LAYERS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MCTheme.textTertiary)
                .tracking(0.8)
            Spacer()
            Menu {
                ForEach(ComposerLayer.LayerKind.allCases, id: \.rawValue) { kind in
                    Button(kind.rawValue) {
                        let layer = ComposerLayer(name: kind.rawValue, kind: kind)
                        layers.append(layer)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(MCTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var layerList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach($layers) { $layer in
                    layerRow(layer: $layer)
                }
            }
            .padding(4)
        }
    }

    private func layerRow(layer: Binding<ComposerLayer>) -> some View {
        let isSelected = layer.wrappedValue.id == selectedLayerID
        return HStack(spacing: 6) {
            Button {
                layer.wrappedValue.isVisible.toggle()
            } label: {
                Image(systemName: layer.wrappedValue.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(layer.wrappedValue.isVisible ? MCTheme.textSecondary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            kindIcon(layer.wrappedValue.kind)
                .font(.system(size: 10))
                .foregroundStyle(MCTheme.textTertiary)

            Text(layer.wrappedValue.name)
                .font(MCTheme.fontCaption)
                .foregroundStyle(isSelected ? MCTheme.textPrimary : MCTheme.textSecondary)
                .lineLimit(1)

            Spacer()

            if layer.wrappedValue.isLocked {
                Image(systemName: "lock")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture {
            selectedLayerID = layer.wrappedValue.id
        }
    }

    private func kindIcon(_ kind: ComposerLayer.LayerKind) -> Image {
        switch kind {
        case .terrain:    return Image(systemName: "mountain.2")
        case .vegetation: return Image(systemName: "leaf")
        case .water:      return Image(systemName: "drop")
        case .atmosphere: return Image(systemName: "cloud.sun")
        case .objects:    return Image(systemName: "cube")
        }
    }
}
