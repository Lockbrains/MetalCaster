import SwiftUI
import MetalCasterAsset

struct VersionControlView: View {
    @Environment(EditorState.self) private var state
    @State private var selectedTab = 0
    @State private var commitMessage = ""
    @State private var files: [GitFileStatus] = []
    @State private var commits: [GitCommit] = []
    @State private var branches: [GitBranch] = []
    @State private var selectedFilePath: String?
    @State private var diffText: String = ""
    @State private var showNewBranchField = false
    @State private var newBranchName = ""

    private var gitClient: MCGitClient? { state.gitClient }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().background(MCTheme.panelBorder)

            if let client = gitClient, client.isRepository {
                switch selectedTab {
                case 0: changesView(client)
                case 1: historyView
                case 2: branchesView(client)
                default: changesView(client)
                }
            } else {
                notARepoView
            }
        }
        .background(MCTheme.background)
        .onAppear { refresh() }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 12) {
            tabButton("Changes", index: 0, badge: files.count)
            tabButton("History", index: 1)
            tabButton("Branches", index: 2)
            Spacer()
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func tabButton(_ title: String, index: Int, badge: Int = 0) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(selectedTab == index ? MCTheme.fontPanelLabelBold : MCTheme.fontPanelLabel)
                    .foregroundStyle(selectedTab == index ? MCTheme.textPrimary : MCTheme.textTertiary)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(MCTheme.statusRed.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Changes View

    private func changesView(_ client: MCGitClient) -> some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                Spacer()
                Text("No changes")
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textTertiary)
                Spacer()
            } else {
                HStack(spacing: 0) {
                    fileListView(client)
                        .frame(minWidth: 180)

                    Divider().background(MCTheme.panelBorder)

                    diffView
                        .frame(minWidth: 200)
                }
            }

            Divider().background(MCTheme.panelBorder)
            commitBar(client)
        }
    }

    private func fileListView(_ client: MCGitClient) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(files) { file in
                    fileRow(file, client: client)
                }
            }
            .padding(4)
        }
    }

    private func fileRow(_ file: GitFileStatus, client: MCGitClient) -> some View {
        HStack(spacing: 6) {
            Button {
                if file.isStaged {
                    client.unstage(file.path)
                } else {
                    client.add(file.path)
                }
                refresh()
            } label: {
                Image(systemName: file.isStaged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(file.isStaged ? MCTheme.statusGreen : MCTheme.textTertiary)
            }
            .buttonStyle(.plain)

            statusBadge(file.status)

            Text(file.path)
                .font(MCTheme.fontMono)
                .foregroundStyle(selectedFilePath == file.path ? MCTheme.textPrimary : MCTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(selectedFilePath == file.path ? Color.white.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFilePath = file.path
            if let client = gitClient {
                diffText = file.isStaged ? client.diffStaged(for: file.path) : client.diff(for: file.path)
            }
        }
    }

    private func statusBadge(_ status: GitFileStatusKind) -> some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(statusColor(status))
            .frame(width: 14, height: 14)
    }

    private func statusColor(_ status: GitFileStatusKind) -> Color {
        switch status {
        case .modified:  return .orange
        case .added:     return MCTheme.statusGreen
        case .deleted:   return MCTheme.statusRed
        case .untracked: return .gray
        case .renamed:   return .blue
        default:         return MCTheme.textTertiary
        }
    }

    private var diffView: some View {
        ScrollView {
            if diffText.isEmpty {
                Text("Select a file to view changes")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffText.components(separatedBy: .newlines).indices, id: \.self) { i in
                        let line = diffText.components(separatedBy: .newlines)[i]
                        Text(line)
                            .font(MCTheme.fontMono)
                            .foregroundStyle(diffLineColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(diffLineBackground(line))
                    }
                }
                .padding(8)
            }
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return MCTheme.statusGreen }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return MCTheme.statusRed }
        if line.hasPrefix("@@") { return .cyan }
        return MCTheme.textSecondary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return MCTheme.statusGreen.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return MCTheme.statusRed.opacity(0.08) }
        return .clear
    }

    private func commitBar(_ client: MCGitClient) -> some View {
        HStack(spacing: 8) {
            TextField("Commit message...", text: $commitMessage)
                .textFieldStyle(.plain)
                .font(MCTheme.fontCaption)
                .mcInputStyle()

            Button("Commit") {
                let staged = files.filter(\.isStaged)
                guard !staged.isEmpty, !commitMessage.isEmpty else { return }
                client.commit(message: commitMessage)
                commitMessage = ""
                refresh()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(commitMessage.isEmpty || files.filter(\.isStaged).isEmpty)
        }
        .padding(8)
    }

    // MARK: - History View

    private var historyView: some View {
        ScrollView {
            if commits.isEmpty {
                Text("No commits yet")
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(commits) { commit in
                        commitRow(commit)
                    }
                }
                .padding(4)
            }
        }
    }

    private func commitRow(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(commit.shortHash)
                    .font(MCTheme.fontMono)
                    .foregroundStyle(MCTheme.statusGreen)
                Text(commit.message)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textPrimary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(commit.author)
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
                Text(commit.date.prefix(10))
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Branches View

    private func branchesView(_ client: MCGitClient) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    let localBranches = branches.filter { !$0.isRemote }
                    let remoteBranches = branches.filter(\.isRemote)

                    if !localBranches.isEmpty {
                        sectionHeader("Local")
                        ForEach(localBranches) { branch in
                            branchRow(branch, client: client)
                        }
                    }

                    if !remoteBranches.isEmpty {
                        sectionHeader("Remote")
                        ForEach(remoteBranches) { branch in
                            branchRow(branch, client: client)
                        }
                    }
                }
                .padding(4)
            }

            Divider().background(MCTheme.panelBorder)

            HStack(spacing: 8) {
                if showNewBranchField {
                    TextField("Branch name", text: $newBranchName)
                        .textFieldStyle(.plain)
                        .font(MCTheme.fontCaption)
                        .mcInputStyle()

                    Button("Create") {
                        guard !newBranchName.isEmpty else { return }
                        client.createBranch(newBranchName)
                        newBranchName = ""
                        showNewBranchField = false
                        refresh()
                    }
                    .controlSize(.small)

                    Button("Cancel") {
                        showNewBranchField = false
                        newBranchName = ""
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        showNewBranchField = true
                    } label: {
                        Label("New Branch", systemImage: "plus")
                            .font(MCTheme.fontCaption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MCTheme.textSecondary)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private func branchRow(_ branch: GitBranch, client: MCGitClient) -> some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(branch.isCurrent ? MCTheme.statusGreen : MCTheme.textTertiary)

            Text(branch.name)
                .font(MCTheme.fontCaption)
                .foregroundStyle(branch.isCurrent ? MCTheme.textPrimary : MCTheme.textSecondary)

            Spacer()

            if !branch.isCurrent && !branch.isRemote {
                Button("Switch") {
                    client.checkout(branch.name)
                    refresh()
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundStyle(MCTheme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(MCTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: - Not a Repo

    private var notARepoView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 28))
                .foregroundStyle(MCTheme.textTertiary)
            Text("No Git Repository")
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textSecondary)
            Text("Initialize a repository to track changes")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)

            if let client = gitClient, client.isGitAvailable {
                Button("Initialize Repository") {
                    client.initRepository()
                    refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("git is not available on this system")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.statusRed)
            }
            Spacer()
        }
    }

    // MARK: - Refresh

    private func refresh() {
        guard let client = gitClient, client.isRepository else { return }
        files = client.status()
        commits = client.log(limit: 50)
        branches = client.branches()
    }
}
