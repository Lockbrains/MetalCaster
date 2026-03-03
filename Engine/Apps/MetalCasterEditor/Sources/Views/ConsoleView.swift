import SwiftUI
import MetalCasterCore

struct ConsoleView: View {
    @Environment(EditorState.self) private var state
    @State private var searchQuery = ""

    private var filteredLog: [(Int, String)] {
        let log = state.buildSystem.buildLog
        if searchQuery.isEmpty {
            return Array(log.enumerated())
        }
        return log.enumerated().filter { $0.element.localizedCaseInsensitiveContains(searchQuery) }
            .map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            consoleToolbar
            Rectangle()
                .fill(MCTheme.panelBorder)
                .frame(height: 1)
            logList
        }
        .background(MCTheme.background)
    }

    private var consoleToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
                TextField("Filter logs...", text: $searchQuery)
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

            buildStatusBadge
            Button {
                state.buildSystem.buildLog.removeAll()
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

    @ViewBuilder
    private var buildStatusBadge: some View {
        switch state.buildSystem.status {
        case .idle:
            EmptyView()
        case .building(let stage, _):
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text(stage)
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textSecondary)
            }
        case .succeeded:
            HStack(spacing: 3) {
                Circle()
                    .fill(MCTheme.statusGreen)
                    .frame(width: 6, height: 6)
                Text("Build Succeeded")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.statusGreen)
            }
        case .failed:
            HStack(spacing: 3) {
                Circle()
                    .fill(MCTheme.statusRed)
                    .frame(width: 6, height: 6)
                Text("Build Failed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MCTheme.statusRed)
            }
        }
    }

    private var logList: some View {
        let entries = filteredLog
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries, id: \.0) { index, line in
                        logRow(line, index: index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .onChange(of: state.buildSystem.buildLog.count) { _, newCount in
                if newCount > 0, searchQuery.isEmpty {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ line: String, index: Int) -> some View {
        let isError = line.localizedCaseInsensitiveContains("error") ||
                      line.localizedCaseInsensitiveContains("failed")
        let isWarning = line.localizedCaseInsensitiveContains("warning")

        return HStack(alignment: .top, spacing: 6) {
            if isError {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.statusRed)
                    .frame(width: 12)
            } else if isWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .frame(width: 12)
            } else {
                Text("\(index + 1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MCTheme.textTertiary)
                    .frame(width: 12, alignment: .trailing)
            }

            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isError ? MCTheme.statusRed : MCTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            index % 2 == 0
                ? Color.clear
                : Color.white.opacity(0.02)
        )
        .id(index)
    }
}
