import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAsset

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
                } else if state.autoSaveStatus == .saved {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(MCTheme.statusGreen)
                            .frame(width: 5, height: 5)
                        Text("Saved")
                            .font(.system(size: 9))
                            .foregroundStyle(MCTheme.statusGreen)
                    }
                    .transition(.opacity)
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
            Button("Empty Entity") { state.addEmptyEntity() }
            Divider()
            Menu("Prefab") {
                Menu("Mesh") {
                    ForEach(MeshType.builtinPrimitives, id: \.displayName) { meshType in
                        Button(meshType.displayName) {
                            state.addMeshEntity(name: meshType.displayName, meshType: meshType)
                        }
                    }
                    let meshAssets = state.meshAssetEntries()
                    if !meshAssets.isEmpty {
                        Divider()
                        Menu("From Project") {
                            ForEach(meshAssets) { entry in
                                Button(entry.name) {
                                    state.addMeshAssetToScene(guid: entry.guid, name: entry.name)
                                }
                            }
                        }
                    }
                }
                Button("Camera") { state.addCamera() }
                Button("Directional Light") { state.addDirectionalLight() }
                Button("Point Light") { state.addPointLight() }
                Button("Spot Light") { state.addSpotLight() }
                let hasSkybox = !state.engine.world.query(SkyboxComponent.self).isEmpty
                Button("Skybox") { state.addSkybox() }
                    .disabled(hasSkybox)
                Button("Post Process Volume") { state.addPostProcessVolume() }
                Divider()
                Button("Light Probe") { state.addLightProbe() }
                Button("Reflection Probe") { state.addReflectionProbe() }
                let hasHeightFog = !state.engine.world.query(HeightFogComponent.self).isEmpty
                Button("Height Atmospheric Fog") { state.addHeightFog() }
                    .disabled(hasHeightFog)
            }
            Divider()
            Button("New Collection") { state.createCollection() }
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
