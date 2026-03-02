import SwiftUI
import MetalCasterCore
import MetalCasterScene

struct ECSArchetypeBrowserView: View {
    @Environment(EditorState.self) private var state
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        let _ = state.worldRevision
        let world = state.engine.world
        let archetypes = computeArchetypes(world: world)
        let ubiquitous = computeUbiquitous(archetypes)

        if archetypes.isEmpty {
            Spacer()
            Text("No entities in world")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(archetypes) { arch in
                        archetypeCard(arch, ubiquitous: ubiquitous, world: world, totalEntityCount: world.entityCount)
                    }
                }
                .padding(.vertical, MCTheme.panelPadding)
            }
        }
    }

    // MARK: - Archetype Card

    @ViewBuilder
    private func archetypeCard(_ arch: ArchetypeGroup, ubiquitous: Set<String>, world: World, totalEntityCount: Int) -> some View {
        let isExpanded = expandedIDs.contains(arch.id)
        let name = archetypeName(arch, ubiquitous: ubiquitous)
        let sizes = arch.components.map { comp in
            ComponentSizeEntry(name: comp, size: world.estimatedComponentSize(for: ComponentTypeKey(name: comp)) ?? 0)
        }
        let perEntity = sizes.reduce(0) { $0 + $1.size }
        let total = perEntity * arch.entities.count

        VStack(spacing: 0) {
            Button { toggle(arch.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MCTheme.textTertiary)

                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MCTheme.textPrimary)

                        Spacer()

                        Text("\(arch.entities.count)")
                            .font(MCTheme.fontMono)
                            .foregroundStyle(MCTheme.textTertiary)

                        Button {
                            state.addEntityFromArchetype(componentNames: arch.signature)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(MCTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("New entity with this archetype")
                    }

                    componentSignature(arch.components)
                        .padding(.leading, 20)

                    HStack(spacing: 4) {
                        Text("~\(formatBytes(perEntity))/entity")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MCTheme.textTertiary)
                        Text("·")
                            .foregroundStyle(MCTheme.textTertiary)
                        Text(formatBytes(total))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(MCTheme.textSecondary)
                        Spacer()
                        densityBadge(count: arch.entities.count, total: totalEntityCount)
                    }
                    .padding(.leading, 20)

                    memoryBar(sizes: sizes)
                        .padding(.leading, 20)
                }
                .padding(.horizontal, MCTheme.panelPadding)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedDetail(sizes: sizes, archetype: arch)
            }

            Rectangle()
                .fill(MCTheme.panelBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Component Signature

    @ViewBuilder
    private func componentSignature(_ components: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(components, id: \.self) { name in
                Text(displayName(name))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(componentColor(name).opacity(0.7))
            }
        }
    }

    // MARK: - Memory Bar

    @ViewBuilder
    private func memoryBar(sizes: [ComponentSizeEntry]) -> some View {
        let totalSize = sizes.reduce(0) { $0 + $1.size }
        if totalSize > 0 {
            GeometryReader { proxy in
                let available = proxy.size.width - CGFloat(max(sizes.count - 1, 0))
                HStack(spacing: 1) {
                    ForEach(sizes) { entry in
                        let fraction = CGFloat(entry.size) / CGFloat(totalSize)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(componentColor(entry.name).opacity(0.55))
                            .frame(width: max(3, available * fraction))
                    }
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Density Badge

    @ViewBuilder
    private func densityBadge(count: Int, total: Int) -> some View {
        let pct = total > 0 ? Double(count) / Double(total) * 100 : 0
        Text(String(format: "%.0f%%", pct))
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(MCTheme.textTertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(MCTheme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private func expandedDetail(sizes: [ComponentSizeEntry], archetype: ArchetypeGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sizes) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(componentColor(entry.name))
                        .frame(width: 5, height: 5)
                    Text(displayName(entry.name))
                        .font(MCTheme.fontMono)
                        .foregroundStyle(MCTheme.textSecondary)
                    Spacer()
                    Text("\(entry.size) B")
                        .font(MCTheme.fontMono)
                        .foregroundStyle(MCTheme.textTertiary)
                }
            }

            Rectangle().fill(MCTheme.panelBorder).frame(height: 1)

            ForEach(archetype.entities, id: \.id) { entity in
                entityMiniRow(entity)
            }
        }
        .padding(.horizontal, MCTheme.panelPadding)
        .padding(.leading, 20)
        .padding(.vertical, 6)
        .background(MCTheme.surfaceHover)
    }

    @ViewBuilder
    private func entityMiniRow(_ entity: Entity) -> some View {
        let selected = state.selectedEntity == entity
        let name = state.sceneGraph.name(of: entity)

        HStack(spacing: 6) {
            MCStatusDot(color: MCTheme.textTertiary)
            Text(name)
                .font(MCTheme.fontCaption)
                .foregroundStyle(selected ? MCTheme.textPrimary : MCTheme.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .frame(height: 20)
        .background(selected ? MCTheme.surfaceSelected : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { state.selectedEntity = entity }
    }

    // MARK: - Logic

    private func toggle(_ id: String) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
    }

    private func computeArchetypes(world: World) -> [ArchetypeGroup] {
        var groups: [Set<String>: [Entity]] = [:]
        for entity in world.entities {
            let sig = world.archetypeSignature(of: entity)
            groups[sig, default: []].append(entity)
        }
        return groups.map { sig, entities in
            ArchetypeGroup(
                signature: sig,
                entities: entities.sorted()
            )
        }
        .sorted {
            if $0.entities.count != $1.entities.count {
                return $0.entities.count > $1.entities.count
            }
            return $0.id < $1.id
        }
    }

    /// Components shared by every archetype — these are "ubiquitous" and stripped from display names.
    private func computeUbiquitous(_ archetypes: [ArchetypeGroup]) -> Set<String> {
        guard archetypes.count >= 2, let first = archetypes.first else { return [] }
        var common = first.signature
        for arch in archetypes.dropFirst() {
            common.formIntersection(arch.signature)
        }
        return common
    }

    private func archetypeName(_ arch: ArchetypeGroup, ubiquitous: Set<String>) -> String {
        let unique = arch.components.filter { !ubiquitous.contains($0) }
        if unique.isEmpty { return "Base" }
        return unique.map { displayName($0) }.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "Component", with: "")
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }

    private func componentColor(_ name: String) -> Color {
        let palette: [Color] = [
            MCTheme.statusGreen, MCTheme.statusBlue, MCTheme.statusOrange,
            MCTheme.statusYellow, MCTheme.statusRed,
            Color(red: 0.7, green: 0.4, blue: 0.9),
        ]
        let hash = name.utf8.reduce(0) { $0 &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}

// MARK: - Supporting Types

private struct ArchetypeGroup: Identifiable {
    let signature: Set<String>
    let entities: [Entity]

    var id: String { components.joined(separator: ",") }
    var components: [String] { signature.sorted() }
}

private struct ComponentSizeEntry: Identifiable {
    let name: String
    let size: Int
    var id: String { name }
}
