import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct SceneHierarchyView: View {
    @Environment(EditorState.self) private var state
    @State private var camerasExpanded = true
    @State private var materialsExpanded = true
    @State private var sceneExpanded = true
    @State private var sceneRenderExpanded = true
    @State private var sceneAudioExpanded = true
    @State private var managersExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hierarchy")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
                Menu {
                    Button("Empty Entity") { state.addEmptyEntity() }
                    Button("Cube") { state.addMeshEntity(name: "Cube", meshType: .cube) }
                    Button("Sphere") { state.addMeshEntity(name: "Sphere", meshType: .sphere) }
                    Divider()
                    Button("Camera") { state.addCamera() }
                    Button("Directional Light") { state.addDirectionalLight() }
                    Button("Point Light") { state.addPointLight() }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(MCTheme.textSecondary)
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, MCTheme.panelPadding)
            .padding(.vertical, 8)

            Rectangle()
                .fill(MCTheme.panelBorder)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    let world = state.engine.world
                    let hierarchy = state.sceneGraph.flattenedHierarchy()

                    let cameraEntities = world.query(CameraComponent.self).map { $0.0 }
                    let cameraSet = Set(cameraEntities)
                    let materialEntities = Array(Set(world.entitiesWith(MaterialComponent.self)).subtracting(cameraSet)).sorted()
                    let sceneEntities = hierarchy.map(\.0).filter { entity in
                        !world.hasComponent(CameraComponent.self, on: entity) &&
                        !world.hasComponent(MaterialComponent.self, on: entity)
                    }
                    let renderEntities = sceneEntities.filter { world.hasComponent(MeshComponent.self, on: $0) }

                    GroupRow(
                        title: "Cameras",
                        dotColor: MCTheme.statusGreen,
                        isExpanded: $camerasExpanded,
                        indent: 0
                    ) {
                        ForEach(cameraEntities, id: \.id) { entity in
                            EntityRow(
                                entity: entity,
                                name: state.sceneGraph.name(of: entity),
                                dotColor: MCTheme.statusGreen,
                                indent: 1
                            )
                        }
                    }

                    GroupRow(
                        title: "Materials",
                        dotColor: MCTheme.statusBlue,
                        isExpanded: $materialsExpanded,
                        indent: 0
                    ) {
                        ForEach(materialEntities, id: \.id) { entity in
                            EntityRow(
                                entity: entity,
                                name: state.sceneGraph.name(of: entity),
                                dotColor: MCTheme.statusBlue,
                                indent: 1
                            )
                        }
                    }

                    GroupRow(
                        title: "Scene",
                        dotColor: MCTheme.statusGray,
                        isExpanded: $sceneExpanded,
                        indent: 0
                    ) {
                        GroupRow(
                            title: "Render",
                            dotColor: MCTheme.statusGray,
                            isExpanded: $sceneRenderExpanded,
                            indent: 1
                        ) {
                            ForEach(renderEntities, id: \.id) { entity in
                                EntityRow(
                                    entity: entity,
                                    name: state.sceneGraph.name(of: entity),
                                    dotColor: MCTheme.statusGray,
                                    indent: 2
                                )
                            }
                        }
                        GroupRow(
                            title: "Audio",
                            dotColor: MCTheme.statusGray,
                            isExpanded: $sceneAudioExpanded,
                            indent: 1
                        ) {
                            EmptyView()
                        }
                        ForEach(
                            sceneEntities.filter { !world.hasComponent(MeshComponent.self, on: $0) },
                            id: \.id
                        ) { entity in
                            EntityRow(
                                entity: entity,
                                name: state.sceneGraph.name(of: entity),
                                dotColor: MCTheme.statusGray,
                                indent: 1
                            )
                        }
                    }

                    GroupRow(
                        title: "Managers",
                        dotColor: MCTheme.statusGray,
                        isExpanded: $managersExpanded,
                        indent: 0
                    ) {
                        EmptyView()
                    }
                }
                .padding(.vertical, MCTheme.panelPadding)
            }
        }
        .background(MCTheme.background)
    }
}

private struct GroupRow<Content: View>: View {
    let title: String
    let dotColor: Color
    @Binding var isExpanded: Bool
    let indent: Int
    @ViewBuilder let content: Content

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                ForEach(0..<indent, id: \.self) { _ in
                    Color.clear.frame(width: MCTheme.indentWidth)
                }
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MCTheme.textTertiary)
                MCStatusDot(color: dotColor)
                Text(title)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, MCTheme.panelPadding)
            .frame(height: MCTheme.rowHeight)
        }
        .buttonStyle(.plain)
        if isExpanded {
            content
        }
    }
}

private struct EntityRow: View {
    @Environment(EditorState.self) private var state
    let entity: Entity
    let name: String
    let dotColor: Color
    let indent: Int

    var body: some View {
        let isSelected = state.selectedEntity == entity
        HStack(spacing: 6) {
            ForEach(0..<indent, id: \.self) { _ in
                Color.clear.frame(width: MCTheme.indentWidth)
            }
            MCStatusDot(color: dotColor)
            Text(name)
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, MCTheme.panelPadding)
        .frame(height: MCTheme.rowHeight)
        .background(isSelected ? MCTheme.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedEntity = entity
        }
        .contextMenu {
            Button("Duplicate") {
                state.selectedEntity = entity
                state.duplicateSelectedEntity()
            }
            Button("Delete", role: .destructive) {
                state.selectedEntity = entity
                state.deleteSelectedEntity()
            }
        }
    }
}
