import SwiftUI
import MetalCasterCore
import MetalCasterAsset
import UniformTypeIdentifiers

// MARK: - Project Assets Browser

struct ProjectAssetsView: View {
    @Environment(EditorState.self) private var state
    @State private var showNewScriptAlert = false
    @State private var newScriptName = ""
    @State private var showNewMaterialAlert = false
    @State private var newMaterialName = ""
    @State private var newMaterialShader = "lit"
    @State private var showNewShaderAlert = false
    @State private var newShaderName = ""

    var body: some View {
        VStack(spacing: 0) {
            assetSearchBar
            Divider().background(MCTheme.panelBorder)

            HStack(spacing: 0) {
                categorySidebar
                    .frame(width: 120)
                Divider().background(MCTheme.panelBorder)
                contentArea
            }
        }
        .background(MCTheme.background)
        .alert("New Script", isPresented: $showNewScriptAlert) {
            TextField("Script name", text: $newScriptName)
            Button("Create") {
                let name = newScriptName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                state.createGameplayScript(named: name)
                newScriptName = ""
            }
            Button("Cancel", role: .cancel) {
                newScriptName = ""
            }
        } message: {
            Text("Enter a name for the new gameplay script.")
        }
        .alert("New Material", isPresented: $showNewMaterialAlert) {
            TextField("Material name", text: $newMaterialName)
            Picker("Base Shader", selection: $newMaterialShader) {
                Text("Lit").tag("lit")
                Text("Unlit").tag("unlit")
                Text("Toon").tag("toon")
            }
            Button("Create") {
                let name = newMaterialName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                state.createMaterialAsset(named: name, baseShader: newMaterialShader)
                newMaterialName = ""
            }
            Button("Cancel", role: .cancel) {
                newMaterialName = ""
            }
        } message: {
            Text("Enter a name for the new material.")
        }
        .alert("New Shader", isPresented: $showNewShaderAlert) {
            TextField("Shader name", text: $newShaderName)
            Button("Create") {
                let name = newShaderName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                state.createShaderAsset(named: name)
                newShaderName = ""
            }
            Button("Cancel", role: .cancel) {
                newShaderName = ""
            }
        } message: {
            Text("Enter a name for the new shader.")
        }
    }

    // MARK: - Search Bar

    private var assetSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)

            TextField("Search assets...", text: Binding(
                get: { state.assetBrowserSearchQuery },
                set: { state.assetBrowserSearchQuery = $0 }
            ))
            .textFieldStyle(.plain)
            .font(MCTheme.fontCaption)
            .foregroundStyle(MCTheme.textPrimary)

            if !state.assetBrowserSearchQuery.isEmpty {
                Button {
                    state.assetBrowserSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(MCTheme.inputBackground)
    }

    // MARK: - Category Sidebar

    private var categorySidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(AssetCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .padding(.vertical, 4)
        }
        .background(MCTheme.background)
    }

    private func categoryRow(_ category: AssetCategory) -> some View {
        let _ = state.assetBrowserRevision
        let isSelected = state.selectedAssetCategory == category
        let count = state.assetDatabase.assetCount(in: category)

        return Button {
            state.selectedAssetCategory = category
            state.assetBrowserSubfolder = nil
            state.selectedAssetEntry = nil
        } label: {
            HStack(spacing: 6) {
                MCStatusDot(color: isSelected ? MCTheme.statusBlue : MCTheme.statusGray)

                Image(systemName: category.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? MCTheme.textPrimary : MCTheme.textSecondary)
                    .frame(width: 14)

                Text(category.directoryName)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(isSelected ? MCTheme.textPrimary : MCTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(MCTheme.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: MCTheme.rowHeight)
            .background(isSelected ? MCTheme.surfaceSelected : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            if !state.assetBrowserSearchQuery.isEmpty {
                searchResultsView
            } else {
                breadcrumbBar
                Divider().background(MCTheme.panelBorder)
                assetListView
            }

            Spacer(minLength: 0)

            Divider().background(MCTheme.panelBorder)
            bottomStatusBar
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .contextMenu {
            assetAreaContextMenu
        }
    }

    @ViewBuilder
    private var assetAreaContextMenu: some View {
        if state.selectedAssetCategory == .scenes {
            Button {
                state.requestNewScene()
                state.refreshAssetBrowser()
            } label: {
                Label("New Scene", systemImage: "film.fill")
            }

            Divider()
        }

        if state.selectedAssetCategory == .materials {
            Button {
                newMaterialName = ""
                newMaterialShader = "lit"
                showNewMaterialAlert = true
            } label: {
                Label("New Material", systemImage: "paintpalette.fill")
            }

            Divider()
        }

        if state.selectedAssetCategory == .shaders {
            Button {
                newShaderName = ""
                showNewShaderAlert = true
            } label: {
                Label("New Shader", systemImage: "function")
            }

            Divider()
        }

        if state.selectedAssetCategory == .gameplay {
            Button {
                newScriptName = ""
                showNewScriptAlert = true
            } label: {
                Label("New Script", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Divider()
        }

        Button {
            state.showImportPanel = true
        } label: {
            Label("Import...", systemImage: "square.and.arrow.down")
        }

        Divider()

        Button {
            createNewSubfolder()
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }

        Divider()

        Button {
            showInFinder()
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    state.importAssetFile(from: url)
                }
            }
        }
    }

    private func createNewSubfolder() {
        let folderName = "New Folder"
        try? state.assetDatabase.createSubfolder(
            named: folderName,
            in: state.selectedAssetCategory,
            parentSubpath: state.assetBrowserSubfolder
        )
        state.refreshAssetBrowser()
    }

    private func showInFinder() {
        #if os(macOS)
        if let dir = state.assetDatabase.projectManager.directoryURL(for: state.selectedAssetCategory) {
            var target = dir
            if let sub = state.assetBrowserSubfolder {
                target = target.appendingPathComponent(sub)
            }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: target.path)
        }
        #endif
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 2) {
            if state.assetBrowserSubfolder != nil {
                Button {
                    state.exitAssetSubfolder()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MCTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
            }

            ForEach(Array(state.assetBreadcrumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                Text(crumb)
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(
                        index == state.assetBreadcrumbs.count - 1
                            ? MCTheme.textPrimary
                            : MCTheme.textSecondary
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Asset List

    private static let hiddenExtensions: Set<String> = ["mcmeta", "meta"]

    private var assetListView: some View {
        let _ = state.assetBrowserRevision
        let entries = state.assetDatabase.entries(
            in: state.selectedAssetCategory,
            subfolder: state.assetBrowserSubfolder
        ).filter { entry in
            !Self.hiddenExtensions.contains(entry.fileExtension.lowercased())
        }

        return ScrollView {
            if entries.isEmpty {
                emptyStateView
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        AssetListRow(entry: entry)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: state.selectedAssetCategory.icon)
                .font(.system(size: 24))
                .foregroundStyle(MCTheme.textTertiary)
            Text("No \(state.selectedAssetCategory.directoryName)")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Text("Drag files here or right-click to import")
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        let results = state.assetDatabase.search(query: state.assetBrowserSearchQuery)
            .filter { !Self.hiddenExtensions.contains($0.fileExtension.lowercased()) }

        return ScrollView {
            if results.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(MCTheme.textTertiary)
                    Text("No results for \"\(state.assetBrowserSearchQuery)\"")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(results) { entry in
                        AssetListRow(entry: entry)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Bottom Status Bar

    private var bottomStatusBar: some View {
        let _ = state.assetBrowserRevision
        return HStack(spacing: 8) {
            let entries = state.assetDatabase.entries(
                in: state.selectedAssetCategory,
                subfolder: state.assetBrowserSubfolder
            ).filter { !Self.hiddenExtensions.contains($0.fileExtension.lowercased()) }
            let fileCount = entries.filter { !$0.isDirectory }.count
            Text("\(fileCount) item\(fileCount == 1 ? "" : "s")")
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)

            Spacer()

            HStack(spacing: 2) {
                Button {
                    state.assetViewMode = .list
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            state.assetViewMode == .list ? MCTheme.textPrimary : MCTheme.textTertiary
                        )
                }
                .buttonStyle(.plain)

                Button {
                    state.assetViewMode = .grid
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            state.assetViewMode == .grid ? MCTheme.textPrimary : MCTheme.textTertiary
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Asset List Row

struct AssetListRow: View {
    let entry: AssetEntry
    @Environment(EditorState.self) private var state
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var lastClickTime: Date = .distantPast

    private static let doubleClickInterval: TimeInterval = 0.3

    var body: some View {
        let isSelected = state.selectedAssetEntry?.guid == entry.guid

        rowContent(isSelected: isSelected)
            .onTapGesture {
                let now = Date()
                if now.timeIntervalSince(lastClickTime) < Self.doubleClickInterval {
                    lastClickTime = .distantPast
                    handleDoubleClick()
                } else {
                    lastClickTime = now
                    if entry.fileExtension == "mcmat" {
                        state.selectedEntity = nil
                    }
                    state.selectedAssetEntry = entry
                }
            }
            .contextMenu {
                assetContextMenu
            }
    }

    private func rowContent(isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon)
                .font(.system(size: 11))
                .foregroundStyle(entry.isDirectory ? MCTheme.statusBlue : MCTheme.textSecondary)
                .frame(width: 16)

            if isRenaming {
                TextField("", text: $renameText, onCommit: {
                    commitRename()
                })
                .textFieldStyle(.plain)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)
            } else {
                Text(entry.isDirectory ? entry.name : "\(entry.name).\(entry.fileExtension)")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            if !entry.isDirectory && entry.fileSize > 0 {
                Text(formatFileSize(entry.fileSize))
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(MCTheme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: MCTheme.rowHeight)
        .background(isSelected ? MCTheme.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
        .draggable(entry.guid.uuidString)
    }

    @ViewBuilder
    private var assetContextMenu: some View {
        if entry.isDirectory {
            Button {
                state.enterAssetSubfolder(entry.name)
            } label: {
                Label("Open", systemImage: "folder")
            }
        } else {
            Button {
                handleDoubleClick()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }
        }

        Divider()

        Button {
            isRenaming = true
            renameText = entry.name
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            deleteAsset()
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Divider()

        if !entry.isDirectory {
            Button {
                #if os(macOS)
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }

            Button {
                #if os(macOS)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(entry.guid.uuidString, forType: .string)
                #endif
            } label: {
                Label("Copy GUID", systemImage: "doc.on.doc")
            }
        }
    }

    private func handleDoubleClick() {
        if entry.isDirectory {
            state.enterAssetSubfolder(entry.name)
        } else {
            switch entry.category {
            case .scenes:
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    state.requestLoadScene(from: url)
                }
            case .materials:
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    state.assignMaterialAsset(from: url)
                }
            default:
                #if os(macOS)
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }
        }
    }

    private func commitRename() {
        isRenaming = false
        guard !renameText.isEmpty, renameText != entry.name else { return }
        _ = try? state.assetDatabase.renameAsset(entry: entry, newName: renameText)
        state.refreshAssetBrowser()
    }

    private func deleteAsset() {
        try? state.assetDatabase.deleteAsset(entry: entry)
        if state.selectedAssetEntry?.guid == entry.guid {
            state.selectedAssetEntry = nil
        }
        state.refreshAssetBrowser()
    }

    private var fileIcon: String {
        if entry.category == .scenes && entry.fileExtension == "usda" {
            return "film"
        }
        switch entry.fileExtension {
        case "mcscene": return "film"
        case "usdz", "usd", "usda", "usdc", "obj": return "cube"
        case "png", "jpg", "jpeg", "tiff", "exr", "hdr": return "photo"
        case "mcmat": return "paintpalette"
        case "metal": return "function"
        case "wav", "mp3", "aac", "m4a", "ogg": return "speaker.wave.2"
        case "mcprefab": return "square.on.square"
        case "swift": return "swift"
        default: return "doc"
        }
    }

    private func formatFileSize(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}
