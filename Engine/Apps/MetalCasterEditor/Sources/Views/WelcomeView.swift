import SwiftUI
import MetalCasterAsset
#if canImport(AppKit)
import AppKit
#endif

struct WelcomeView: View {
    @Binding var openedProjectURL: URL?
    @State private var recentProjects: [RecentProject] = RecentProjectsStore.load()
    @State private var hoveredProject: URL? = nil
    @State private var showNewProjectSheet = false
    @State private var newProjectName = "My Game"

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider().background(MCTheme.panelBorder)
            rightPanel
        }
        .frame(width: 800, height: 480)
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showNewProjectSheet) {
            newProjectSheet
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MCTheme.statusBlue, MCTheme.statusBlue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 4) {
                    Text("Metal Caster")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundStyle(MCTheme.textPrimary)

                    Text("Version 0.1.0")
                        .font(.system(size: 13))
                        .foregroundStyle(MCTheme.textTertiary)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                welcomeButton(
                    icon: "plus.rectangle.fill",
                    title: "Create New Project...",
                    action: { showNewProjectSheet = true }
                )

                welcomeButton(
                    icon: "folder.fill",
                    title: "Open Existing Project...",
                    action: openExistingProject
                )
            }
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 40)
        }
        .frame(width: 340)
    }

    private func welcomeButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(MCTheme.statusBlue)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MCTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(MCTheme.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MCTheme.panelBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Panel (Recent Projects)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
            }
            .frame(height: 36)

            if recentProjects.isEmpty {
                emptyRecentState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(recentProjects) { project in
                            recentProjectRow(project)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.02))
    }

    private var emptyRecentState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(MCTheme.textTertiary)
            Text("No Recent Projects")
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textTertiary)
            Text("Create a new project or open an existing one")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func recentProjectRow(_ project: RecentProject) -> some View {
        let isHovered = hoveredProject == project.url
        let exists = FileManager.default.fileExists(
            atPath: project.url.appendingPathComponent("project.json").path
        )

        return Button {
            if exists {
                openedProjectURL = project.url
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(exists ? MCTheme.statusBlue : MCTheme.textTertiary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(exists ? MCTheme.textPrimary : MCTheme.textTertiary)
                        .lineLimit(1)

                    Text(project.displayPath)
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if !exists {
                    Text("Missing")
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(MCTheme.statusRed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isHovered ? MCTheme.surfaceHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredProject = hovering ? project.url : nil
        }
    }

    // MARK: - New Project Sheet

    private var newProjectSheet: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MCTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Project Name")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)

                TextField("", text: $newProjectName)
                    .textFieldStyle(.plain)
                    .mcInputStyle()
            }
            .padding(.horizontal, 24)

            HStack {
                Button("Cancel") {
                    showNewProjectSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    showNewProjectSheet = false
                    createNewProject()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 20)
        .frame(width: 400)
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func createNewProject() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose Location for New Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Here"

        panel.begin { response in
            guard response == .OK, let parentURL = panel.url else { return }
            let safeName = newProjectName.trimmingCharacters(in: .whitespaces)
            guard !safeName.isEmpty else { return }

            let projectURL = parentURL.appendingPathComponent("\(safeName).mcproject")

            let pm = ProjectManager()
            do {
                try pm.createProject(at: projectURL, name: safeName)
                RecentProjectsStore.add(name: safeName, url: projectURL)
                recentProjects = RecentProjectsStore.load()
                openedProjectURL = projectURL
            } catch {
                print("[MetalCaster] Failed to create project: \(error)")
            }
        }
        #endif
    }

    private func openExistingProject() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Open MetalCaster Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.message = "Select a .mcproject folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let configURL = url.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                print("[MetalCaster] Not a valid project: \(url.path)")
                return
            }

            let name = url.deletingPathExtension().lastPathComponent
            RecentProjectsStore.add(name: name, url: url)
            recentProjects = RecentProjectsStore.load()
            openedProjectURL = url
        }
        #endif
    }
}

// MARK: - Recent Projects Persistence

struct RecentProject: Identifiable, Codable {
    let name: String
    let path: String
    let lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    var displayPath: String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

enum RecentProjectsStore {
    private static let key = "MetalCaster.recentProjects"
    private static let maxRecent = 10

    static func load() -> [RecentProject] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let projects = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return []
        }
        return projects
    }

    static func save(_ projects: [RecentProject]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func add(name: String, url: URL) {
        var projects = load()
        projects.removeAll { $0.path == url.path }
        projects.insert(
            RecentProject(name: name, path: url.path, lastOpened: Date()),
            at: 0
        )
        if projects.count > maxRecent {
            projects = Array(projects.prefix(maxRecent))
        }
        save(projects)
    }
}
