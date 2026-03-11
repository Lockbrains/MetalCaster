import SwiftUI
import MetalCasterCore
import MetalCasterRenderer
import MetalCasterScene
import MetalCasterAsset
import MetalCasterPhysics
import MetalCasterAudio

// MARK: - Data Model

struct ComponentEntry: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let isAvailable: (World, Entity) -> Bool
    let add: (World, Entity) -> Void
}

struct ComponentCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let entries: [ComponentEntry]
}

// MARK: - Registry

enum ComponentRegistry {

    static func categories() -> [ComponentCategory] {
        [
            ComponentCategory(name: "Rendering", icon: "paintbrush", entries: [
                ComponentEntry(
                    name: "Mesh",
                    icon: "cube",
                    isAvailable: { w, e in !w.hasComponent(MeshComponent.self, on: e) },
                    add: { w, e in
                        w.addComponent(MeshComponent(), to: e)
                        if !w.hasComponent(MaterialComponent.self, on: e) {
                            w.addComponent(MaterialComponent(material: MaterialRegistry.litMaterial), to: e)
                        }
                    }
                ),
                ComponentEntry(
                    name: "Material",
                    icon: "circle.lefthalf.filled",
                    isAvailable: { w, e in !w.hasComponent(MaterialComponent.self, on: e) },
                    add: { w, e in
                        w.addComponent(MaterialComponent(material: MaterialRegistry.litMaterial), to: e)
                    }
                ),
                ComponentEntry(
                    name: "LOD",
                    icon: "square.3.layers.3d.down.left",
                    isAvailable: { w, e in
                        !w.hasComponent(LODComponent.self, on: e) &&
                        w.hasComponent(MeshComponent.self, on: e)
                    },
                    add: { w, e in w.addComponent(LODComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Skybox",
                    icon: "globe",
                    isAvailable: { w, e in !w.hasComponent(SkyboxComponent.self, on: e) },
                    add: { w, e in w.addComponent(SkyboxComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Post Process Volume",
                    icon: "camera.filters",
                    isAvailable: { w, e in !w.hasComponent(PostProcessVolumeComponent.self, on: e) },
                    add: { w, e in w.addComponent(PostProcessVolumeComponent(), to: e) }
                ),
            ]),

            ComponentCategory(name: "Lighting", icon: "lightbulb", entries: [
                ComponentEntry(
                    name: "Light",
                    icon: "light.max",
                    isAvailable: { w, e in !w.hasComponent(LightComponent.self, on: e) },
                    add: { w, e in w.addComponent(LightComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Camera",
                    icon: "camera",
                    isAvailable: { w, e in !w.hasComponent(CameraComponent.self, on: e) },
                    add: { w, e in w.addComponent(CameraComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Light Probe",
                    icon: "circle.grid.3x3",
                    isAvailable: { w, e in !w.hasComponent(LightProbeComponent.self, on: e) },
                    add: { w, e in w.addComponent(LightProbeComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Reflection Probe",
                    icon: "sparkles",
                    isAvailable: { w, e in !w.hasComponent(ReflectionProbeComponent.self, on: e) },
                    add: { w, e in w.addComponent(ReflectionProbeComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Lightmap",
                    icon: "sun.max.trianglebadge.exclamationmark",
                    isAvailable: { w, e in
                        !w.hasComponent(LightmapComponent.self, on: e) &&
                        w.hasComponent(MeshComponent.self, on: e)
                    },
                    add: { w, e in w.addComponent(LightmapComponent(), to: e) }
                ),
            ]),

            ComponentCategory(name: "Environment", icon: "cloud.sun", entries: [
                ComponentEntry(
                    name: "Height Fog",
                    icon: "cloud.fog",
                    isAvailable: { w, e in !w.hasComponent(HeightFogComponent.self, on: e) },
                    add: { w, e in w.addComponent(HeightFogComponent(), to: e) }
                ),
            ]),

            ComponentCategory(name: "Physics", icon: "arrow.triangle.branch", entries: [
                ComponentEntry(
                    name: "Physics Body",
                    icon: "scalemass",
                    isAvailable: { w, e in !w.hasComponent(PhysicsBodyComponent.self, on: e) },
                    add: { w, e in w.addComponent(PhysicsBodyComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Collider",
                    icon: "shield",
                    isAvailable: { w, e in !w.hasComponent(ColliderComponent.self, on: e) },
                    add: { w, e in w.addComponent(ColliderComponent(), to: e) }
                ),
            ]),

            ComponentCategory(name: "Audio", icon: "speaker.wave.3", entries: [
                ComponentEntry(
                    name: "Audio Source",
                    icon: "speaker.wave.2",
                    isAvailable: { w, e in !w.hasComponent(AudioSourceComponent.self, on: e) },
                    add: { w, e in w.addComponent(AudioSourceComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "Audio Listener",
                    icon: "ear",
                    isAvailable: { w, e in !w.hasComponent(AudioListenerComponent.self, on: e) },
                    add: { w, e in w.addComponent(AudioListenerComponent(), to: e) }
                ),
            ]),

            ComponentCategory(name: "UI", icon: "rectangle.on.rectangle", entries: [
                ComponentEntry(
                    name: "UI Canvas",
                    icon: "rectangle.dashed",
                    isAvailable: { w, e in !w.hasComponent(UICanvasComponent.self, on: e) },
                    add: { w, e in w.addComponent(UICanvasComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "UI Element",
                    icon: "square",
                    isAvailable: { w, e in !w.hasComponent(UIElementComponent.self, on: e) },
                    add: { w, e in w.addComponent(UIElementComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "UI Label",
                    icon: "textformat",
                    isAvailable: { w, e in !w.hasComponent(UILabelComponent.self, on: e) },
                    add: { w, e in w.addComponent(UILabelComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "UI Image",
                    icon: "photo",
                    isAvailable: { w, e in !w.hasComponent(UIImageComponent.self, on: e) },
                    add: { w, e in w.addComponent(UIImageComponent(), to: e) }
                ),
                ComponentEntry(
                    name: "UI Panel",
                    icon: "rectangle",
                    isAvailable: { w, e in !w.hasComponent(UIPanelComponent.self, on: e) },
                    add: { w, e in w.addComponent(UIPanelComponent(), to: e) }
                ),
            ]),
        ]
    }
}

// MARK: - Component Picker View

struct ComponentPickerView: View {
    @Environment(EditorState.self) private var state
    let entity: Entity
    let onDismiss: () -> Void

    @State private var search = ""
    @State private var expandedCategories: Set<String> = []

    private var world: World { state.engine.world }

    private var filteredCategories: [(ComponentCategory, [ComponentEntry])] {
        let cats = ComponentRegistry.categories()
        let query = search.lowercased()

        return cats.compactMap { cat in
            let available = cat.entries.filter { $0.isAvailable(world, entity) }
            guard !available.isEmpty else { return nil }

            if query.isEmpty { return (cat, available) }

            let matched = available.filter { $0.name.lowercased().contains(query) }
            return matched.isEmpty ? nil : (cat, matched)
        }
    }

    private var filteredScripts: [String] {
        let names = discoverScriptNames()
        let query = search.lowercased()
        if query.isEmpty { return names }
        return names.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().background(MCTheme.panelBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    componentCategories
                    scriptSection
                    if filteredCategories.isEmpty && filteredScripts.isEmpty {
                        emptyState
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 260, height: min(CGFloat(totalRows) * 28 + 80, 420))
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MCTheme.panelBorder, lineWidth: 1)
        )
    }

    // MARK: - Search

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(MCTheme.textTertiary)
            TextField("Search components…", text: $search)
                .textFieldStyle(.plain)
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Categories

    @ViewBuilder
    private var componentCategories: some View {
        ForEach(filteredCategories, id: \.0.id) { cat, entries in
            categoryHeader(cat)
            if isExpanded(cat) || !search.isEmpty {
                ForEach(entries) { entry in
                    componentRow(entry)
                }
            }
        }
    }

    private func categoryHeader(_ cat: ComponentCategory) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if expandedCategories.contains(cat.name) {
                    expandedCategories.remove(cat.name)
                } else {
                    expandedCategories.insert(cat.name)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded(cat) || !search.isEmpty ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MCTheme.textTertiary)
                    .frame(width: 10)
                Image(systemName: cat.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(MCTheme.textSecondary)
                    .frame(width: 16)
                Text(cat.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MCTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func componentRow(_ entry: ComponentEntry) -> some View {
        Button {
            entry.add(world, entity)
            state.worldRevision += 1
            state.markDirty()
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(MCTheme.statusBlue)
                    .frame(width: 16)
                Text(entry.name)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.leading, 20)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ComponentRowButtonStyle())
    }

    // MARK: - Scripts

    @ViewBuilder
    private var scriptSection: some View {
        let scripts = filteredScripts
        let hasScriptRef = world.hasComponent(GameplayScriptRef.self, on: entity)

        if !scripts.isEmpty && !hasScriptRef {
            categoryHeaderStatic(name: "Scripts", icon: "scroll")
            ForEach(scripts, id: \.self) { scriptName in
                Button {
                    var ref = GameplayScriptRef()
                    ref.scriptName = scriptName
                    world.addComponent(ref, to: entity)
                    state.worldRevision += 1
                    state.markDirty()
                    onDismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(MCTheme.statusGreen)
                            .frame(width: 16)
                        Text(scriptName)
                            .font(MCTheme.fontCaption)
                            .foregroundStyle(MCTheme.textPrimary)
                        Spacer()
                        Text("Script")
                            .font(.system(size: 9))
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.leading, 20)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ComponentRowButtonStyle())
            }
        }
    }

    private func categoryHeaderStatic(name: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 10)
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(MCTheme.textSecondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MCTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .thin))
                .foregroundStyle(MCTheme.textTertiary)
            Text("No matching components")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Helpers

    private func isExpanded(_ cat: ComponentCategory) -> Bool {
        expandedCategories.contains(cat.name)
    }

    private var totalRows: Int {
        var count = filteredCategories.count
        for (_, entries) in filteredCategories {
            count += entries.count
        }
        count += filteredScripts.isEmpty ? 0 : 1 + filteredScripts.count
        return max(count, 3)
    }

    private func discoverScriptNames() -> [String] {
        var dirs: [URL] = []
        if let gameplayDir = state.projectManager.directoryURL(for: .gameplay) {
            dirs.append(gameplayDir)
            let genDir = gameplayDir.appendingPathComponent(".generated")
            if FileManager.default.fileExists(atPath: genDir.path) {
                dirs.append(genDir)
            }
        }
        guard !dirs.isEmpty else { return [] }
        return GameplayScriptScanner().scriptNames(in: dirs)
    }
}

// MARK: - Row Button Style

struct ComponentRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            )
    }
}
