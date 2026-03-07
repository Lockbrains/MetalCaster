import SwiftUI
import UniformTypeIdentifiers
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterAsset
import MetalCasterScene
import MetalCasterAudio

struct ECSEntityBrowserView: View {
    @Environment(EditorState.self) private var state
    @State private var searchText = ""
    @State private var activeFilters: Set<String> = []
    @State private var collapsedEntities: Set<Entity> = []
    @State private var collapsedCollections: Set<UUID> = []
    @State private var selectedCollectionID: UUID? = nil
    @State private var dropTargetEntity: Entity? = nil

    var body: some View {
        let _ = state.worldRevision
        let world = state.engine.world

        VStack(spacing: 0) {
            componentFilterBar(world: world)
            Rectangle().fill(MCTheme.panelBorder).frame(height: 1)
            hierarchyList(world: world)
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

    // MARK: - Hierarchy List

    private enum HierarchyItem: Identifiable {
        case entity(entity: Entity, depth: Int, hasChildren: Bool)
        case collection(SceneCollection)

        var id: String {
            switch self {
            case .entity(let e, _, _): return "e-\(e.id)"
            case .collection(let c): return "c-\(c.id.uuidString)"
            }
        }
    }

    @ViewBuilder
    private func hierarchyList(world: World) -> some View {
        let items = buildHierarchyItems(world: world)
        if items.isEmpty {
            Spacer()
            Text("No matching entities")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .entity(let entity, let depth, let hasChildren):
                            EntityRowView(
                                entity: entity,
                                depth: depth,
                                hasChildren: hasChildren,
                                isCollapsed: collapsedEntities.contains(entity),
                                onToggleCollapse: { toggleCollapse(entity) },
                                onSelect: { selectedCollectionID = nil },
                                world: world
                            )
                        case .collection(let collection):
                            CollectionRowView(
                                collection: collection,
                                isCollapsed: collapsedCollections.contains(collection.id),
                                isSelected: selectedCollectionID == collection.id,
                                onSelect: { selectCollection(collection.id) },
                                onToggle: { toggleCollapseCollection(collection.id) }
                            )
                        }
                    }
                }
                .padding(.vertical, MCTheme.panelPadding)
            }
            .onDrop(of: [.utf8PlainText], delegate: HierarchyBackgroundDropDelegate(
                state: state,
                dropTarget: $dropTargetEntity
            ))
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) {
                guard state.renameManager.target == nil else { return .ignored }
                if let cid = selectedCollectionID {
                    state.renamingCollectionID = cid
                    return .handled
                }
                if let entity = state.selectedEntity {
                    state.renamingEntityID = entity
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                if state.renameManager.target != nil {
                    state.renameManager.endRename()
                    return .handled
                }
                return .ignored
            }
        }
    }

    private func toggleCollapse(_ entity: Entity) {
        if collapsedEntities.contains(entity) {
            collapsedEntities.remove(entity)
        } else {
            collapsedEntities.insert(entity)
        }
    }

    private func toggleCollapseCollection(_ id: UUID) {
        if collapsedCollections.contains(id) {
            collapsedCollections.remove(id)
        } else {
            collapsedCollections.insert(id)
        }
    }

    private func selectCollection(_ id: UUID) {
        selectedCollectionID = id
        state.selectedEntity = nil
        state.selectedAssetEntry = nil
    }

    // MARK: - Hierarchy Building

    private func buildHierarchyItems(world: World) -> [HierarchyItem] {
        let sceneGraph = state.sceneGraph
        let isFiltering = !activeFilters.isEmpty

        if isFiltering {
            let all = Array(world.entities).sorted()
            return all
                .filter { activeFilters.isSubset(of: world.archetypeSignature(of: $0)) }
                .map { .entity(entity: $0, depth: 0, hasChildren: false) }
        }

        let collectedEntityIDs: Set<UInt64> = {
            var s = Set<UInt64>()
            for c in state.collections {
                for id in c.memberEntityIDs { s.insert(id) }
            }
            return s
        }()

        var items: [HierarchyItem] = []

        // Root entities NOT in any collection
        let roots = sceneGraph.rootEntities().sorted()
        for root in roots {
            if !collectedEntityIDs.contains(root.id) {
                buildEntityTree(entity: root, depth: 0, sceneGraph: sceneGraph, into: &items)
            }
        }

        // Orphan entities (no TransformComponent, no parent) NOT in any collection
        let treeEntitySet = Set(items.compactMap { item -> Entity? in
            if case .entity(let e, _, _) = item { return e }
            return nil
        })
        for entity in world.entities.sorted() {
            if !treeEntitySet.contains(entity)
                && !world.hasComponent(ParentComponent.self, on: entity)
                && !collectedEntityIDs.contains(entity.id) {
                items.append(.entity(entity: entity, depth: 0, hasChildren: false))
            }
        }

        // Collections with their members
        for collection in state.collections {
            items.append(.collection(collection))

            guard !collapsedCollections.contains(collection.id) else { continue }
            let members = collection.liveMembers(in: world)
            for member in members {
                buildEntityTree(entity: member, depth: 1, sceneGraph: sceneGraph, into: &items)
            }
        }

        return items
    }

    private func buildEntityTree(entity: Entity, depth: Int, sceneGraph: SceneGraph, into result: inout [HierarchyItem]) {
        let kids = sceneGraph.children(of: entity)
        result.append(.entity(entity: entity, depth: depth, hasChildren: !kids.isEmpty))

        guard !collapsedEntities.contains(entity) else { return }
        for child in kids {
            buildEntityTree(entity: child, depth: depth + 1, sceneGraph: sceneGraph, into: &result)
        }
    }

    // MARK: - Helpers

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "Component", with: "")
    }

    private func componentColor(_ name: String) -> Color {
        EntityRowView.componentColor(name)
    }
}

// MARK: - Collection Row

struct CollectionRowView: View {
    let collection: SceneCollection
    var isCollapsed: Bool
    var isSelected: Bool = false
    var onSelect: () -> Void
    var onToggle: () -> Void

    @Environment(EditorState.self) private var state
    @State private var renameText = ""
    @State private var isDropTargeted = false

    private var isRenaming: Bool { state.renamingCollectionID == collection.id }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 14, height: 14)
                .padding(.leading, MCTheme.panelPadding)

            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(MCTheme.textSecondary)
                .padding(.leading, 4)

            separatorLine

            if isRenaming {
                #if canImport(AppKit)
                RenameField(text: $renameText) {
                    commitRename()
                }
                .frame(maxWidth: 140)
                #endif
            } else {
                Text(collection.name)
                    .font(MCTheme.fontCaption.bold())
                    .foregroundStyle(isSelected ? MCTheme.textPrimary : MCTheme.textSecondary)
                    .lineLimit(1)
            }

            separatorLine
        }
        .frame(height: MCTheme.rowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            onToggle()
        }
        .onDrop(of: [.utf8PlainText], delegate: CollectionDropDelegate(
            collectionID: collection.id,
            state: state,
            isTargeted: $isDropTargeted
        ))
        .contextMenu {
            Button("Rename") { beginRename() }
            Divider()
            Button("Delete Collection", role: .destructive) {
                state.deleteCollection(id: collection.id)
            }
        }
        .onChange(of: state.renamingCollectionID) { _, newVal in
            if newVal == collection.id {
                renameText = collection.name
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isDropTargeted {
            MCTheme.statusBlue.opacity(0.12)
        } else if isSelected {
            MCTheme.surfaceSelected
        } else {
            Color.clear
        }
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(MCTheme.panelBorder)
            .frame(height: 1)
            .padding(.horizontal, 6)
    }

    private func beginRename() {
        state.renamingCollectionID = collection.id
    }

    private func commitRename() {
        guard isRenaming else { return }
        state.renamingCollectionID = nil
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != collection.name else { return }
        state.renameCollection(id: collection.id, to: trimmed)
    }
}

// MARK: - Entity Row

struct EntityRowView: View {
    let entity: Entity
    var depth: Int = 0
    var hasChildren: Bool = false
    var isCollapsed: Bool = false
    var isDropTarget: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil
    let world: World

    @Environment(EditorState.self) private var state
    @State private var renameText = ""
    @State private var isTargeted = false

    private var isRenaming: Bool { state.renamingEntityID == entity }
    private var selected: Bool { state.selectedEntity == entity }

    var body: some View {
        let name = state.sceneGraph.name(of: entity)
        let keys = world.componentTypeKeys(of: entity)
            .filter { $0.name != "ParentComponent" && $0.name != "ChildrenComponent" }
            .sorted { $0.name < $1.name }

        HStack(spacing: 0) {
            Spacer()
                .frame(width: CGFloat(depth) * MCTheme.indentWidth)

            if hasChildren {
                Button {
                    onToggleCollapse?()
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MCTheme.textTertiary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

            HStack(spacing: 6) {
                entityIcon

                if isRenaming {
                    #if canImport(AppKit)
                    RenameField(text: $renameText) {
                        commitRename()
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
            .padding(.trailing, MCTheme.panelPadding)
        }
        .padding(.leading, MCTheme.panelPadding)
        .frame(height: MCTheme.rowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedAssetEntry = nil
            state.selectedEntity = entity
            onSelect?()
        }
        .draggable(entityTransferString) {
            Text(name)
                .font(MCTheme.fontCaption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MCTheme.surfaceSelected)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .onDrop(of: [.utf8PlainText], delegate: EntityRowDropDelegate(
            targetEntity: entity,
            state: state,
            isTargeted: $isTargeted
        ))
        .contextMenu { contextMenuContent }
        .onChange(of: state.renamingEntityID) { _, newVal in
            if newVal == entity {
                renameText = state.sceneGraph.name(of: entity)
            }
        }
    }

    private var entityTransferString: String {
        "mc-entity:\(entity.id)"
    }

    @ViewBuilder
    private var rowBackground: some View {
        if selected {
            MCTheme.surfaceSelected
        } else if isTargeted || isDropTarget {
            MCTheme.statusBlue.opacity(0.15)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var entityIcon: some View {
        let iconName: String = {
            if world.hasComponent(CameraComponent.self, on: entity) { return "camera.fill" }
            if world.hasComponent(LightComponent.self, on: entity) { return "light.max" }
            if world.hasComponent(MeshComponent.self, on: entity) { return "cube.fill" }
            if world.hasComponent(ManagerComponent.self, on: entity) { return "gearshape.fill" }
            if world.hasComponent(SkyboxComponent.self, on: entity) { return "cloud.fill" }
            if world.hasComponent(UICanvasComponent.self, on: entity) { return "rectangle.on.rectangle" }
            if world.hasComponent(AudioSourceComponent.self, on: entity) { return "speaker.wave.2.fill" }
            if hasChildren { return "folder.fill" }
            return "circle.fill"
        }()

        Image(systemName: iconName)
            .font(.system(size: 10))
            .foregroundStyle(MCTheme.textSecondary)
            .frame(width: 14)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("Rename") {
            state.renamingEntityID = entity
        }
        Divider()
        Button("Create Child") {
            state.addChildEntity(parent: entity)
        }
        if state.sceneGraph.parent(of: entity) != nil {
            Button("Unparent") {
                state.reparentEntity(entity, to: nil)
            }
        }

        if !state.collections.isEmpty {
            Divider()
            Menu("Move to Collection") {
                ForEach(state.collections) { collection in
                    Button(collection.name) {
                        state.addEntityToCollection(entity, collectionID: collection.id)
                    }
                }
                if state.collectionContaining(entity) != nil {
                    Divider()
                    Button("Remove from Collection") {
                        state.removeEntityFromAllCollections(entity)
                    }
                }
            }
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

    private func commitRename() {
        guard isRenaming else { return }
        state.renamingEntityID = nil
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != state.sceneGraph.name(of: entity) else { return }
        state.updateComponent(NameComponent.self, on: entity) { $0.name = trimmed }
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

// MARK: - Drag & Drop Delegates

private struct EntityRowDropDelegate: DropDelegate {
    let targetEntity: Entity
    let state: EditorState
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func validateDrop(info: DropInfo) -> Bool { true }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let itemProvider = info.itemProviders(for: [.utf8PlainText]).first else { return false }

        itemProvider.loadObject(ofClass: NSString.self) { item, _ in
            guard let str = item as? NSString else { return }
            let string = str as String

            if string.hasPrefix("mc-entity:") {
                let idStr = String(string.dropFirst("mc-entity:".count))
                guard let entityID = UInt64(idStr) else { return }
                let dragged = Entity(id: entityID)
                guard dragged != targetEntity else { return }
                if isDescendant(of: dragged, entity: targetEntity) { return }

                DispatchQueue.main.async {
                    state.reparentEntity(dragged, to: targetEntity)
                }
            } else if let guid = UUID(uuidString: string),
                      let url = state.assetDatabase.resolveURL(for: guid),
                      url.pathExtension == "mcmat" {
                DispatchQueue.main.async {
                    state.assignMaterialAsset(from: url, to: targetEntity)
                }
            }
        }
        return true
    }

    private func isDescendant(of ancestor: Entity, entity: Entity) -> Bool {
        var current: Entity? = entity
        while let c = current {
            if c == ancestor { return true }
            current = state.sceneGraph.parent(of: c)
        }
        return false
    }
}

private struct CollectionDropDelegate: DropDelegate {
    let collectionID: UUID
    let state: EditorState
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func validateDrop(info: DropInfo) -> Bool { true }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let itemProvider = info.itemProviders(for: [.utf8PlainText]).first else { return false }

        itemProvider.loadObject(ofClass: NSString.self) { item, _ in
            guard let str = item as? NSString else { return }
            let string = str as String
            guard string.hasPrefix("mc-entity:") else { return }
            let idStr = String(string.dropFirst("mc-entity:".count))
            guard let entityID = UInt64(idStr) else { return }
            let entity = Entity(id: entityID)

            DispatchQueue.main.async {
                state.addEntityToCollection(entity, collectionID: collectionID)
            }
        }
        return true
    }
}

/// Drop on the scroll view background = unparent / remove from collection.
private struct HierarchyBackgroundDropDelegate: DropDelegate {
    let state: EditorState
    @Binding var dropTarget: Entity?

    func performDrop(info: DropInfo) -> Bool {
        dropTarget = nil
        guard let itemProvider = info.itemProviders(for: [.utf8PlainText]).first else { return false }
        itemProvider.loadObject(ofClass: NSString.self) { item, _ in
            guard let str = item as? NSString else { return }
            let string = str as String
            guard string.hasPrefix("mc-entity:") else { return }
            let idStr = String(string.dropFirst("mc-entity:".count))
            guard let entityID = UInt64(idStr) else { return }
            let dragged = Entity(id: entityID)

            DispatchQueue.main.async {
                state.removeEntityFromAllCollections(dragged)
                if state.sceneGraph.parent(of: dragged) != nil {
                    state.reparentEntity(dragged, to: nil)
                }
            }
        }
        return true
    }
}
