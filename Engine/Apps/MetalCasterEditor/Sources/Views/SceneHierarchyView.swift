import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene

struct SceneHierarchyView: View {
    @Environment(EditorState.self) private var state
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Hierarchy")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                Text(state.sceneName)
                    .font(MCTheme.fontCaption.bold())
                    .foregroundStyle(MCTheme.textPrimary)
                    .lineLimit(1)
                if state.isSceneDirty {
                    Circle()
                        .fill(MCTheme.statusRed)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                addEntityMenu
            }
            .padding(.horizontal, MCTheme.panelPadding)
            .padding(.vertical, 8)

            Rectangle()
                .fill(MCTheme.panelBorder)
                .frame(height: 1)

            if selectedTab == 0 {
                ECSEntityBrowserView()
            } else {
                ECSArchetypeBrowserView()
            }
        }
        .background(MCTheme.background)
    }

    // MARK: - Add Entity Menu

    private var addEntityMenu: some View {
        Menu {
            Menu("Primitives") {
                ForEach(MeshType.builtinPrimitives, id: \.displayName) { meshType in
                    Button(meshType.displayName) {
                        state.addMeshEntity(name: meshType.displayName, meshType: meshType)
                    }
                }
            }
            Menu("Lights") {
                Button("Directional Light") { state.addDirectionalLight() }
                Button("Point Light") { state.addPointLight() }
                Button("Spot Light") { state.addSpotLight() }
            }
            Button("Camera") { state.addCamera() }
            Button("Empty Entity") { state.addEmptyEntity() }
            Divider()
            managersSubmenu
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(MCTheme.textSecondary)
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var managersSubmenu: some View {
        let world = state.engine.world
        let existingManagers = Set(
            world.query(ManagerComponent.self).map { $0.1.managerType }
        )
        Menu("Managers") {
            ForEach(ManagerComponent.ManagerType.allCases, id: \.rawValue) { type in
                let exists = existingManagers.contains(type)
                Button {
                    if exists {
                        state.removeManager(type)
                    } else {
                        state.addManager(type)
                    }
                } label: {
                    HStack {
                        Text(type.rawValue)
                        if exists {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}
