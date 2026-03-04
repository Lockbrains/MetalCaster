import SwiftUI
import UniformTypeIdentifiers
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterAsset
import MetalCasterScene

struct ECSEntityBrowserView: View {
    @Environment(EditorState.self) private var state
    @State private var searchText = ""
    @State private var activeFilters: Set<String> = []

    var body: some View {
        let _ = state.worldRevision
        let world = state.engine.world

        VStack(spacing: 0) {
            componentFilterBar(world: world)
            Rectangle().fill(MCTheme.panelBorder).frame(height: 1)
            entityList(world: world)
        }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private func componentFilterBar(world: World) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
                TextField("Filter components…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                if !searchText.isEmpty || !activeFilters.isEmpty {
                    Button {
                        searchText = ""
                        activeFilters.removeAll()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MCTheme.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(MCTheme.inputBorder, lineWidth: 1))
            .padding(.horizontal, MCTheme.panelPadding)

            let types = world.registeredComponentTypes
                .sorted { $0.name < $1.name }
                .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(types, id: \.name) { key in
                        componentPill(key)
                    }
                }
                .padding(.horizontal, MCTheme.panelPadding)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func componentPill(_ key: ComponentTypeKey) -> some View {
        let on = activeFilters.contains(key.name)
        let color = componentColor(key.name)
        Button {
            if on { activeFilters.remove(key.name) } else { activeFilters.insert(key.name) }
        } label: {
            Text(displayName(key.name))
                .font(MCTheme.fontSmall)
                .foregroundStyle(on ? MCTheme.textPrimary : MCTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(on ? color.opacity(0.2) : MCTheme.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? color.opacity(0.5) : MCTheme.inputBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entity List

    @ViewBuilder
    private func entityList(world: World) -> some View {
        let entities = filteredEntities(world: world)
        if entities.isEmpty {
            Spacer()
            Text("No matching entities")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entities, id: \.id) { entity in
                        entityRow(entity, world: world)
                    }
                }
                .padding(.vertical, MCTheme.panelPadding)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) {
                if state.renamingEntityID == nil,
                   let selected = state.selectedEntity {
                    state.renamingEntityID = selected
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                if state.renamingEntityID != nil {
                    state.renamingEntityID = nil
                    return .handled
                }
                return .ignored
            }
        }
    }

    @ViewBuilder
    private func entityRow(_ entity: Entity, world: World) -> some View {
        EntityRowView(entity: entity, world: world)
    }

    private func handleMaterialDrop(_ providers: [NSItemProvider], onto entity: Entity, world: World) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let str = item as? NSString,
                          let guid = UUID(uuidString: str as String),
                          let url = state.assetDatabase.resolveURL(for: guid),
                          url.pathExtension == "mcmat" else { return }
                    DispatchQueue.main.async {
                        state.assignMaterialAsset(from: url, to: entity)
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Logic

    private func filteredEntities(world: World) -> [Entity] {
        let all = Array(world.entities).sorted()
        guard !activeFilters.isEmpty else { return all }
        return all.filter { activeFilters.isSubset(of: world.archetypeSignature(of: $0)) }
    }

    // MARK: - Helpers

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "Component", with: "")
    }

    private func abbreviation(_ name: String) -> String {
        let short = displayName(name)
        if short.count <= 4 { return short }
        let upper = short.filter(\.isUppercase)
        return upper.isEmpty ? String(short.prefix(3)).uppercased() : String(upper.prefix(3))
    }

    private func componentColor(_ name: String) -> Color {
        EntityRowView.componentColor(name)
    }
}

// MARK: - Entity Row (supports inline rename)

struct EntityRowView: View {
    let entity: Entity
    let world: World
    @Environment(EditorState.self) private var state
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private var isRenaming: Bool { state.renamingEntityID == entity }
    private var selected: Bool { state.selectedEntity == entity }

    var body: some View {
        let name = state.sceneGraph.name(of: entity)
        let keys = world.componentTypeKeys(of: entity).sorted { $0.name < $1.name }

        HStack(spacing: 6) {
            MCStatusDot(color: MCTheme.textPrimary)

            if isRenaming {
                #if canImport(AppKit)
                RenameField(text: $renameText, isFocused: $renameFieldFocused) {
                    commitRename()
                }
                .onChange(of: renameFieldFocused) { _, focused in
                    if !focused { commitRename() }
                }
                #endif
            } else {
                Text(name)
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()
            HStack(spacing: 2) {
                ForEach(Array(keys.prefix(3)), id: \.name) { k in
                    Text(abbreviation(k.name))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Self.componentColor(k.name))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Self.componentColor(k.name).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                if keys.count > 3 {
                    Text("+\(keys.count - 3)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(MCTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, MCTheme.panelPadding)
        .frame(height: MCTheme.rowHeight)
        .background(selected ? MCTheme.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedAssetEntry = nil
            state.selectedEntity = entity
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            handleMaterialDrop(providers)
        }
        .contextMenu {
            Button("Rename") {
                state.renamingEntityID = entity
            }
            Divider()
            Button("Duplicate") {
                state.selectedEntity = entity
                state.duplicateSelectedEntity()
            }
            Button("Delete", role: .destructive) {
                state.selectedEntity = entity
                state.deleteSelectedEntity()
            }
        }
        .onChange(of: state.renamingEntityID) { _, newVal in
            if newVal == entity {
                renameText = state.sceneGraph.name(of: entity)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    renameFieldFocused = true
                }
            }
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        state.renamingEntityID = nil
        renameFieldFocused = false
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != state.sceneGraph.name(of: entity) else { return }
        state.updateComponent(NameComponent.self, on: entity) { $0.name = trimmed }
    }

    private func handleMaterialDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let str = item as? NSString,
                          let guid = UUID(uuidString: str as String),
                          let url = state.assetDatabase.resolveURL(for: guid),
                          url.pathExtension == "mcmat" else { return }
                    DispatchQueue.main.async {
                        state.assignMaterialAsset(from: url, to: entity)
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    private func abbreviation(_ name: String) -> String {
        let short = name.replacingOccurrences(of: "Component", with: "")
        if short.count <= 4 { return short }
        let upper = short.filter(\.isUppercase)
        return upper.isEmpty ? String(short.prefix(3)).uppercased() : String(upper.prefix(3))
    }

    static func componentColor(_ name: String) -> Color {
        let palette: [Color] = [
            MCTheme.statusGreen, MCTheme.statusBlue, MCTheme.statusOrange,
            MCTheme.statusYellow, MCTheme.statusRed,
            Color(red: 0.7, green: 0.4, blue: 0.9),
        ]
        let hash = name.utf8.reduce(0) { $0 &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}
