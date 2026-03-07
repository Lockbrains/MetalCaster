import SwiftUI
import MetalCasterCore
import MetalCasterAsset
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
import ImageIO
import CoreGraphics
#endif

// MARK: - Project Assets Browser

struct ProjectAssetsView: View {
    @Environment(EditorState.self) private var state
    @State private var showNewScriptAlert = false
    @State private var newScriptName = ""
    @State private var showNewPromptAlert = false
    @State private var newPromptName = ""
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
        .alert("New Prompt Script", isPresented: $showNewPromptAlert) {
            TextField("Prompt name", text: $newPromptName)
            Button("Create") {
                let name = newPromptName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                state.createPromptScript(named: name)
                newPromptName = ""
            }
            Button("Cancel", role: .cancel) {
                newPromptName = ""
            }
        } message: {
            Text("Enter a name for the prompt script. Describe behavior in natural language — the engine generates Swift code via AI.")
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
                if state.assetViewMode == .grid {
                    assetGridView
                } else {
                    assetListView
                }
            }

            Spacer(minLength: 0)

            Divider().background(MCTheme.panelBorder)
            bottomStatusBar
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            if state.renamingAssetGUID == nil,
               let selected = state.selectedAssetEntry {
                state.renamingAssetGUID = selected.guid
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if state.renamingAssetGUID != nil {
                state.renamingAssetGUID = nil
                return .handled
            }
            return .ignored
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
                newPromptName = ""
                showNewPromptAlert = true
            } label: {
                Label("New Prompt Script", systemImage: "text.bubble")
            }

            Button {
                newScriptName = ""
                showNewScriptAlert = true
            } label: {
                Label("New Swift Script", systemImage: "chevron.left.forwardslash.chevron.right")
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

    // MARK: - Asset Grid

    private var assetGridView: some View {
        let _ = state.assetBrowserRevision
        let entries = state.assetDatabase.entries(
            in: state.selectedAssetCategory,
            subfolder: state.assetBrowserSubfolder
        ).filter { !Self.hiddenExtensions.contains($0.fileExtension.lowercased()) }

        let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)]

        return ScrollView {
            if entries.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(entries) { entry in
                        AssetGridCell(entry: entry)
                    }
                }
                .padding(8)
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
    @State private var renameText = ""
    @State private var lastClickTime: Date = .distantPast
    @State private var isDropTarget = false

    private static let doubleClickInterval: TimeInterval = 0.3
    private static let inspectableExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "exr", "hdr", "bmp", "gif", "webp"]

    private var isRenaming: Bool { state.renamingAssetGUID == entry.guid }

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
                    let ext = entry.fileExtension.lowercased()
                    if ext == "mcmat" || Self.inspectableExtensions.contains(ext) {
                        state.selectedEntity = nil
                    }
                    state.selectedAssetEntry = entry
                }
            }
            .contextMenu {
                assetContextMenu
            }
            .conditionalDropTarget(isFolder: entry.isDirectory, isDropTarget: $isDropTarget) { guids in
                handleAssetDrop(guids)
            }
            .onChange(of: state.renamingAssetGUID) { _, newVal in
                if newVal == entry.guid {
                    renameText = entry.name
                }
            }
    }

    private var isPromptFile: Bool {
        entry.fileExtension.lowercased() == "prompt"
    }

    private func rowContent(isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isDirectory ? MCTheme.statusBlue : iconColor)
                    .frame(width: 16)

                if isRenaming {
                    RenameField(text: $renameText) {
                        commitRename()
                    }
                } else {
                    Text(entry.isDirectory ? entry.name : "\(entry.name).\(entry.fileExtension)")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                if isPromptFile {
                    promptStatusIndicator
                } else if !entry.isDirectory && entry.fileSize > 0 {
                    Text(formatFileSize(entry.fileSize))
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(MCTheme.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: MCTheme.rowHeight)

            if isPromptFile && isSelected {
                promptSubordinateRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isDropTarget ? MCTheme.statusBlue.opacity(0.25) : (isSelected ? MCTheme.surfaceSelected : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isDropTarget ? MCTheme.statusBlue : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .draggable(entry.guid.uuidString)
    }

    private var iconColor: Color {
        isPromptFile ? Color.purple : MCTheme.textSecondary
    }

    @ViewBuilder
    private var promptStatusIndicator: some View {
        let key = "\(entry.name).\(entry.fileExtension)"
        let status = state.promptCompileStatuses[key]
        let hasGenerated = state.hasGeneratedScript(for: entry)

        switch status {
        case .compiling:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(MCTheme.statusRed)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(MCTheme.statusGreen)
        default:
            if hasGenerated {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.statusGreen.opacity(0.5))
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var promptSubordinateRow: some View {
        let hasGenerated = state.hasGeneratedScript(for: entry)

        HStack(spacing: 6) {
            Color.clear.frame(width: 16)
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 8))
                .foregroundStyle(MCTheme.textTertiary)
            Image(systemName: "swift")
                .font(.system(size: 9))
                .foregroundStyle(hasGenerated ? MCTheme.textSecondary : MCTheme.textTertiary)
            Text("\(entry.name).swift")
                .font(MCTheme.fontSmall)
                .foregroundStyle(hasGenerated ? MCTheme.textSecondary : MCTheme.textTertiary)
                .italic(!hasGenerated)
            if !hasGenerated {
                Text("(not generated)")
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(MCTheme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 18)
        .onTapGesture {
            if hasGenerated {
                openGeneratedScript()
            }
        }
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

        if isPromptFile {
            Divider()

            Button {
                compilePrompt()
            } label: {
                Label("Compile Prompt", systemImage: "sparkles")
            }

            if state.hasGeneratedScript(for: entry) {
                Button {
                    openGeneratedScript()
                } label: {
                    Label("View Generated Swift", systemImage: "swift")
                }
            }
        }

        Divider()

        Button {
            beginRename()
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
            case .gameplay:
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    if entry.fileExtension.lowercased() == "prompt" {
                        state.editingPromptURL = url
                    } else {
                        #if os(macOS)
                        openWithTextEditor(url)
                        #endif
                    }
                }
            default:
                #if os(macOS)
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    openWithTextEditor(url)
                }
                #endif
            }
        }
    }

    #if os(macOS)
    private func openWithTextEditor(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let textEditable: Set<String> = ["prompt", "swift", "metal", "json", "txt", "usda"]

        if textEditable.contains(ext) {
            let xcodeBundleID = "com.apple.dt.Xcode"
            if let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: xcodeBundleID) {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: xcodeURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } else {
                NSWorkspace.shared.open(url)
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    private func beginRename() {
        state.renamingAssetGUID = entry.guid
    }

    private func commitRename() {
        guard isRenaming else { return }
        state.renamingAssetGUID = nil
        guard !renameText.isEmpty, renameText != entry.name else { return }
        _ = try? state.assetDatabase.renameAsset(entry: entry, newName: renameText)
        state.refreshAssetBrowser()
    }

    private func handleAssetDrop(_ guidStrings: [String]) {
        let allEntries = state.assetDatabase.entries(
            in: state.selectedAssetCategory,
            subfolder: state.assetBrowserSubfolder
        )
        for guidStr in guidStrings {
            guard let guid = UUID(uuidString: guidStr) else { continue }
            guard guid != entry.guid else { continue }
            if let movingEntry = allEntries.first(where: { $0.guid == guid }),
               !movingEntry.isDirectory {
                try? state.assetDatabase.moveAsset(
                    entry: movingEntry,
                    toFolderRelativePath: entry.relativePath
                )
            }
        }
        state.refreshAssetBrowser()
    }

    private func deleteAsset() {
        try? state.assetDatabase.deleteAsset(entry: entry)
        if state.selectedAssetEntry?.guid == entry.guid {
            state.selectedAssetEntry = nil
        }
        state.refreshAssetBrowser()
    }

    private func compilePrompt() {
        guard let url = state.assetDatabase.resolveURL(for: entry.guid) else { return }
        Task {
            await state.compilePromptScript(at: url)
        }
    }

    private func openGeneratedScript() {
        #if os(macOS)
        guard let genURL = state.generatedScriptURL(for: entry),
              FileManager.default.fileExists(atPath: genURL.path) else { return }
        NSWorkspace.shared.open(genURL)
        #endif
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
        case "prompt": return "text.bubble"
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

// MARK: - Asset Grid Cell

struct AssetGridCell: View {
    let entry: AssetEntry
    @Environment(EditorState.self) private var state
    @State private var thumbnail: NSImage?
    @State private var lastClickTime: Date = .distantPast
    @State private var renameText = ""
    @State private var isDropTarget = false

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "exr", "hdr", "bmp", "gif", "webp"]
    private static let doubleClickInterval: TimeInterval = 0.3
    private static let inspectableExtensions: Set<String> = ["jpg", "jpeg", "png", "tiff", "tif", "exr", "hdr", "bmp", "gif", "webp"]

    private var isRenaming: Bool { state.renamingAssetGUID == entry.guid }

    var body: some View {
        let isSelected = state.selectedAssetEntry?.guid == entry.guid

        VStack(spacing: 4) {
            thumbnailView
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? MCTheme.statusBlue : Color.clear, lineWidth: 2)
                )

            if isRenaming {
                RenameField(text: $renameText) {
                    commitRename()
                }
                .frame(width: 80, height: 14)
            } else {
                Text(entry.isDirectory ? entry.name : "\(entry.name).\(entry.fileExtension)")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTarget ? MCTheme.statusBlue.opacity(0.25) : (isSelected ? MCTheme.surfaceSelected : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTarget ? MCTheme.statusBlue : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .draggable(entry.guid.uuidString)
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < Self.doubleClickInterval {
                lastClickTime = .distantPast
                if entry.isDirectory {
                    state.assetBrowserSubfolder = (state.assetBrowserSubfolder ?? "")
                        .appending(entry.name + "/")
                }
            } else {
                lastClickTime = now
                let ext = entry.fileExtension.lowercased()
                if ext == "mcmat" || Self.inspectableExtensions.contains(ext) {
                    state.selectedEntity = nil
                }
                state.selectedAssetEntry = entry
            }
        }
        .contextMenu {
            gridContextMenu
        }
        .conditionalDropTarget(isFolder: entry.isDirectory, isDropTarget: $isDropTarget) { guids in
            handleAssetDrop(guids)
        }
        .onChange(of: state.renamingAssetGUID) { _, newVal in
            if newVal == entry.guid {
                renameText = entry.name
            }
        }
        .onAppear { loadThumbnail() }
    }

    @ViewBuilder
    private var gridContextMenu: some View {
        if entry.isDirectory {
            Button {
                state.enterAssetSubfolder(entry.name)
            } label: {
                Label("Open", systemImage: "folder")
            }
        }

        Divider()

        Button {
            beginRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Button(role: .destructive) {
            try? state.assetDatabase.deleteAsset(entry: entry)
            if state.selectedAssetEntry?.guid == entry.guid {
                state.selectedAssetEntry = nil
            }
            state.refreshAssetBrowser()
        } label: {
            Label("Delete", systemImage: "trash")
        }

        if !entry.isDirectory {
            Divider()
            Button {
                #if os(macOS)
                if let url = state.assetDatabase.resolveURL(for: entry.guid) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                #endif
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private func beginRename() {
        state.renamingAssetGUID = entry.guid
    }

    private func commitRename() {
        guard isRenaming else { return }
        state.renamingAssetGUID = nil
        guard !renameText.isEmpty, renameText != entry.name else { return }
        _ = try? state.assetDatabase.renameAsset(entry: entry, newName: renameText)
        state.refreshAssetBrowser()
    }

    private func handleAssetDrop(_ guidStrings: [String]) {
        let allEntries = state.assetDatabase.entries(
            in: state.selectedAssetCategory,
            subfolder: state.assetBrowserSubfolder
        )
        for guidStr in guidStrings {
            guard let guid = UUID(uuidString: guidStr) else { continue }
            guard guid != entry.guid else { continue }
            if let movingEntry = allEntries.first(where: { $0.guid == guid }),
               !movingEntry.isDirectory {
                try? state.assetDatabase.moveAsset(
                    entry: movingEntry,
                    toFolderRelativePath: entry.relativePath
                )
            }
        }
        state.refreshAssetBrowser()
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if entry.isDirectory {
            ZStack {
                Color.white.opacity(0.04)
                Image(systemName: "folder.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(MCTheme.statusBlue)
            }
        } else if let thumb = thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.04)
                Image(systemName: iconForExtension)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
    }

    private var iconForExtension: String {
        switch entry.fileExtension.lowercased() {
        case "mcscene", "usda", "usdz", "usd", "usdc": return "film"
        case "obj": return "cube"
        case "png", "jpg", "jpeg", "tiff", "exr", "hdr": return "photo"
        case "mcmat": return "paintpalette"
        case "metal": return "function"
        case "wav", "mp3", "aac", "m4a", "ogg": return "speaker.wave.2"
        case "mcprefab": return "square.on.square"
        case "swift": return "swift"
        case "prompt": return "text.bubble"
        default: return "doc"
        }
    }

    private func loadThumbnail() {
        guard !entry.isDirectory else { return }
        let ext = entry.fileExtension.lowercased()
        guard Self.imageExtensions.contains(ext) else { return }
        guard let url = state.assetDatabase.resolveURL(for: entry.guid) else { return }

        DispatchQueue.global(qos: .utility).async {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            let nsImg = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                self.thumbnail = nsImg
            }
        }
    }
}

// RenameField is defined in RenameManager.swift

// MARK: - Conditional Drop Target

extension View {
    @ViewBuilder
    func conditionalDropTarget(
        isFolder: Bool,
        isDropTarget: Binding<Bool>,
        onDrop: @escaping ([String]) -> Void
    ) -> some View {
        if isFolder {
            self.dropDestination(for: String.self) { items, _ in
                let validGuids = items.filter { UUID(uuidString: $0) != nil }
                guard !validGuids.isEmpty else { return false }
                onDrop(validGuids)
                return true
            } isTargeted: { targeted in
                isDropTarget.wrappedValue = targeted
            }
        } else {
            self
        }
    }
}
