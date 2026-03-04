import SwiftUI
import Combine
import MetalCasterCore
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Collapsed Log Group

private struct CollapsedLogGroup: Identifiable {
    let id: UUID
    let entry: MCLogEntry
    var count: Int
}

// MARK: - Console View

struct ConsoleView: View {
    @Environment(EditorState.self) private var state
    @State private var searchQuery = ""
    @State private var showInfo = true
    @State private var showWarnings = true
    @State private var showErrors = true
    @State private var collapseEnabled = false
    @State private var logEntries: [MCLogEntry] = []
    @State private var lastRevision: Int = -1
    @State private var expandedEntries: Set<UUID> = []

    private let refreshTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    // MARK: - Derived Data

    private var filteredEntries: [MCLogEntry] {
        logEntries.filter { entry in
            switch entry.level {
            case .debug, .info:
                guard showInfo else { return false }
            case .warning:
                guard showWarnings else { return false }
            case .error, .fatal:
                guard showErrors else { return false }
            }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                return entry.message.lowercased().contains(q)
                    || entry.subsystem.rawValue.lowercased().contains(q)
            }
            return true
        }
    }

    private var displayGroups: [CollapsedLogGroup] {
        let entries = filteredEntries
        guard collapseEnabled else {
            return entries.map { CollapsedLogGroup(id: $0.id, entry: $0, count: 1) }
        }
        var groups: [CollapsedLogGroup] = []
        for entry in entries {
            if let last = groups.last, last.entry.collapseKey == entry.collapseKey {
                groups[groups.count - 1].count += 1
            } else {
                groups.append(CollapsedLogGroup(id: entry.id, entry: entry, count: 1))
            }
        }
        return groups
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            consoleToolbar
            Rectangle().fill(MCTheme.panelBorder).frame(height: 1)
            logListView
        }
        .background(MCTheme.background)
        .onReceive(refreshTimer) { _ in
            let rev = MCLog.shared.revision
            if rev != lastRevision {
                logEntries = MCLog.shared.recentEntries(count: 2048)
                lastRevision = rev
            }
        }
        .onAppear {
            logEntries = MCLog.shared.recentEntries(count: 2048)
            lastRevision = MCLog.shared.revision
        }
    }

    // MARK: - Toolbar

    private var consoleToolbar: some View {
        HStack(spacing: 6) {
            searchField

            Spacer(minLength: 4)

            buildStatusBadge

            levelFilterButton(
                icon: "info.circle", count: logEntries.count(where: { $0.level <= .info }),
                isOn: $showInfo, activeColor: MCTheme.textSecondary
            )
            levelFilterButton(
                icon: "exclamationmark.triangle.fill",
                count: logEntries.count(where: { $0.level == .warning }),
                isOn: $showWarnings, activeColor: MCTheme.statusYellow
            )
            levelFilterButton(
                icon: "xmark.circle.fill",
                count: logEntries.count(where: { $0.level >= .error }),
                isOn: $showErrors, activeColor: MCTheme.statusRed
            )

            Divider().frame(height: 14)

            Button {
                collapseEnabled.toggle()
            } label: {
                Image(systemName: collapseEnabled
                      ? "rectangle.compress.vertical"
                      : "rectangle.expand.vertical")
                    .font(.system(size: 10))
                    .foregroundStyle(collapseEnabled ? MCTheme.textPrimary : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Collapse Identical")

            Button { copyAllToClipboard() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Copy All")

            Button {
                MCLog.shared.clearBuffer()
                logEntries.removeAll()
                expandedEntries.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Clear Console")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(MCTheme.textTertiary)
            TextField("Filter...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textPrimary)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MCTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(MCTheme.inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(MCTheme.inputBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var buildStatusBadge: some View {
        switch state.buildSystem.status {
        case .idle:
            EmptyView()
        case .building(let stage, _):
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(stage)
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textSecondary)
            }
        case .succeeded:
            HStack(spacing: 3) {
                Circle().fill(MCTheme.statusGreen).frame(width: 6, height: 6)
                Text("Build OK")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.statusGreen)
            }
        case .failed:
            HStack(spacing: 3) {
                Circle().fill(MCTheme.statusRed).frame(width: 6, height: 6)
                Text("Build Failed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MCTheme.statusRed)
            }
        }
    }

    private func levelFilterButton(icon: String, count: Int,
                                    isOn: Binding<Bool>, activeColor: Color) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(isOn.wrappedValue ? activeColor : MCTheme.textTertiary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(isOn.wrappedValue ? activeColor : MCTheme.textTertiary)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isOn.wrappedValue ? activeColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log List

    private var logListView: some View {
        let groups = displayGroups

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        ConsoleEntryRow(
                            entry: group.entry,
                            count: group.count,
                            isExpanded: expandedEntries.contains(group.entry.id),
                            onToggleExpand: {
                                if expandedEntries.contains(group.entry.id) {
                                    expandedEntries.remove(group.entry.id)
                                } else {
                                    expandedEntries.insert(group.entry.id)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: logEntries.count) { _, _ in
                if let last = groups.last, searchQuery.isEmpty {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Clipboard

    private func copyAllToClipboard() {
        let text = filteredEntries.map(\.formattedMessage).joined(separator: "\n")
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Console Entry Row

private struct ConsoleEntryRow: View {
    let entry: MCLogEntry
    let count: Int
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var levelColor: Color {
        switch entry.level {
        case .debug:           return MCTheme.textTertiary
        case .info:            return MCTheme.textSecondary
        case .warning:         return MCTheme.statusYellow
        case .error, .fatal:   return MCTheme.statusRed
        }
    }

    private var hasCallStack: Bool {
        !(entry.callStack ?? []).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow

            if isExpanded, let stack = entry.callStack, !stack.isEmpty {
                callStackView(stack)
            }
        }
        .background(rowBackground)
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(entry.compactTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MCTheme.textTertiary)
                .frame(width: 52, alignment: .leading)

            Image(systemName: entry.level.icon)
                .font(.system(size: 9))
                .foregroundStyle(levelColor)
                .frame(width: 16)

            Text(entry.subsystem.rawValue)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MCTheme.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 62, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.level >= .error ? levelColor : MCTheme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(MCTheme.textTertiary)
                    .clipShape(Capsule())
            }

            if hasCallStack {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MCTheme.textTertiary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    // MARK: - Call Stack

    private func callStackView(_ stack: [String]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(stack.prefix(15).enumerated()), id: \.offset) { idx, frame in
                HStack(spacing: 4) {
                    Text("\(idx)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(MCTheme.textTertiary.opacity(0.6))
                        .frame(width: 18, alignment: .trailing)

                    Text(frame.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MCTheme.textTertiary)
                        .textSelection(.enabled)
                }
            }
            if stack.count > 15 {
                Text("    ... +\(stack.count - 15) frames")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MCTheme.textTertiary.opacity(0.5))
            }
        }
        .padding(.leading, 82)
        .padding(.trailing, 10)
        .padding(.bottom, 4)
        .background(Color.white.opacity(0.02))
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        Group {
            if entry.level >= .error {
                MCTheme.statusRed.opacity(0.06)
            } else if entry.level == .warning {
                MCTheme.statusYellow.opacity(0.04)
            } else {
                Color.clear
            }
        }
    }
}
