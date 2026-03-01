import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct ComponentToolboxView: View {
    @Environment(EditorState.self) private var state

    private let componentTypes: [(name: String, icon: String, color: Color)] = [
        ("Transform", "move.3d", MCTheme.statusGray),
        ("Camera", "camera", MCTheme.statusGreen),
        ("Light", "light.max", MCTheme.statusGray),
        ("Mesh", "cube", MCTheme.statusGray),
        ("Material", "paintpalette", MCTheme.statusBlue),
        ("Physics Body", "atom", MCTheme.statusGray),
        ("Collider", "shield", MCTheme.statusGray),
        ("Audio Source", "speaker.wave.2", MCTheme.statusGray),
        ("Name", "tag", MCTheme.statusGray),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(componentTypes, id: \.name) { comp in
                    componentRow(comp)
                }
            }
            .padding(.horizontal, MCTheme.panelPadding)
            .padding(.vertical, 8)
        }
        .background(MCTheme.background)
    }

    private func componentRow(_ comp: (name: String, icon: String, color: Color)) -> some View {
        Button {
            addComponent(comp.name)
        } label: {
            HStack(spacing: 8) {
                MCStatusDot(color: comp.color)
                Image(systemName: comp.icon)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                    .frame(width: 14)
                Text(comp.name)
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textPrimary)
                Spacer()
            }
            .frame(height: MCTheme.rowHeight)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.selectedEntity == nil)
        .opacity(state.selectedEntity == nil ? 0.4 : 1.0)
    }

    private func addComponent(_ name: String) {
        guard let entity = state.selectedEntity else { return }
        let world = state.engine.world

        switch name {
        case "Camera":
            if world.getComponent(CameraComponent.self, from: entity) == nil {
                world.addComponent(CameraComponent(), to: entity)
            }
        case "Light":
            if world.getComponent(LightComponent.self, from: entity) == nil {
                world.addComponent(LightComponent(), to: entity)
            }
        case "Mesh":
            if world.getComponent(MeshComponent.self, from: entity) == nil {
                world.addComponent(MeshComponent(meshType: .cube), to: entity)
            }
        case "Material":
            if world.getComponent(MaterialComponent.self, from: entity) == nil {
                world.addComponent(
                    MaterialComponent(material: MCMaterial(name: "New Material")),
                    to: entity
                )
            }
        default:
            break
        }
    }
}
