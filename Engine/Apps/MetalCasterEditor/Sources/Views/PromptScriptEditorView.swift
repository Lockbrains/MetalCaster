import SwiftUI
import MetalCasterAsset
#if os(macOS)
import AppKit
#endif

struct PromptScriptEditorView: View {
    @Environment(EditorState.self) private var state
    let fileURL: URL

    @State private var promptData: PromptScriptData = .init()
    @State private var didLoad = false
    @State private var saveTimer: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MCTheme.panelBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nameField
                    coreField(
                        title: "Initial State",
                        hint: "Describe the data this component holds when first created.\nThink: what variables does this behavior need?",
                        placeholder: "e.g. It has a speed of 2.0, a list of waypoint positions, and a current index starting at 0.",
                        text: $promptData.initialState
                    )
                    coreField(
                        title: "Per-Frame Behavior",
                        hint: "Describe what happens every frame (every tick of the game loop).\nThis becomes the System's process() function.",
                        placeholder: "e.g. Move toward the current waypoint. When within 0.1m, advance to the next. Loop back to the first.",
                        text: $promptData.perFrameBehavior
                    )
                    coreField(
                        title: "Public Interface",
                        hint: "Describe what other components should be able to read from this one.\nThese become public properties on the Component struct.",
                        placeholder: "e.g. Whether it is moving or paused, the current waypoint index, and the speed.",
                        text: $promptData.publicInterface
                    )

                    customFieldsSection
                }
                .padding(24)
            }

            Divider().background(MCTheme.panelBorder)
            bottomBar
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadData)
        .onChange(of: promptData) { _, _ in scheduleSave() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 14))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 1) {
                Text("Prompt Script")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MCTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text(fileURL.deletingPathExtension().lastPathComponent)
                    .font(MCTheme.fontTitle)
                    .foregroundStyle(MCTheme.textPrimary)
            }

            Spacer()

            compileStatusBadge

            Button {
                state.editingPromptURL = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var compileStatusBadge: some View {
        let key = fileURL.lastPathComponent
        let status = state.promptCompileStatuses[key]

        switch status {
        case .compiling:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
                Text("Compiling...")
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(MCTheme.textSecondary)
            }
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.statusGreen)
                Text("Generated")
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(MCTheme.statusGreen)
            }
        case .failed(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MCTheme.statusRed)
                Text(msg)
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(MCTheme.statusRed)
                    .lineLimit(2)
                    .help(msg)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Name")

            Text("The Component and System name to be generated. Use PascalCase.")
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)

            TextField("e.g. PatrolGuard, FloatingCrystal", text: $promptData.name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(MCTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MCTheme.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MCTheme.inputBorder, lineWidth: 1)
                )

            if !promptData.name.isEmpty {
                Text("Will generate: **\(promptData.swiftIdentifier)Component** + **\(promptData.swiftIdentifier)System**")
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(.purple.opacity(0.7))
            }
        }
    }

    // MARK: - Core Field

    private func coreField(
        title: String,
        hint: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title)

            Text(hint)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)

            promptTextEditor(placeholder: placeholder, text: text)
        }
    }

    private func promptTextEditor(placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }

            TextEditor(text: text)
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .frame(minHeight: 72)
        .fixedSize(horizontal: false, vertical: true)
        .background(MCTheme.inputBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MCTheme.inputBorder, lineWidth: 1)
        )
    }

    // MARK: - Custom Fields

    private var customFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                fieldLabel("Additional Context")
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        promptData.customFields.append(.init())
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Add Field")
                            .font(MCTheme.fontSmall)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            Text("Give the AI more context about this component. Each field becomes part of the generation prompt.")
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)

            if promptData.customFields.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 20))
                            .foregroundStyle(MCTheme.textTertiary)
                        Text("No additional fields")
                            .font(MCTheme.fontSmall)
                            .foregroundStyle(MCTheme.textTertiary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ForEach(Array(promptData.customFields.enumerated()), id: \.element.id) { index, field in
                    customFieldRow(index: index, field: field)
                }
            }
        }
    }

    private func customFieldRow(index: Int, field: PromptScriptData.CustomField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Field label (e.g. Dependencies, Physics Rules...)",
                          text: Binding(
                            get: { promptData.customFields[safe: index]?.label ?? "" },
                            set: { if promptData.customFields.indices.contains(index) { promptData.customFields[index].label = $0 } }
                          ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MCTheme.textPrimary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        promptData.customFields.removeAll { $0.id == field.id }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MCTheme.statusRed.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            promptTextEditor(
                placeholder: "Describe anything the AI should know...",
                text: Binding(
                    get: { promptData.customFields[safe: index]?.content ?? "" },
                    set: { if promptData.customFields.indices.contains(index) { promptData.customFields[index].content = $0 } }
                )
            )
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MCTheme.inputBorder, lineWidth: 1)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            let errors = PromptScriptValidator.validate(promptData)
            if !errors.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(MCTheme.statusOrange)
                    Text(errors.first ?? "")
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(MCTheme.statusOrange)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                openGeneratedScript()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "swift")
                        .font(.system(size: 10))
                    Text("View Generated")
                        .font(MCTheme.fontSmall)
                }
                .foregroundStyle(MCTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(MCTheme.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MCTheme.inputBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasGeneratedScript)

            Button {
                compilePrompt()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("Generate Swift")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    promptData.isComplete
                        ? LinearGradient(colors: [.purple, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(!promptData.isComplete || isCompiling)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var isCompiling: Bool {
        let key = fileURL.lastPathComponent
        if case .compiling = state.promptCompileStatuses[key] { return true }
        return false
    }

    private var hasGeneratedScript: Bool {
        guard let genURL = state.projectManager.generatedScriptURL(for: fileURL) else { return false }
        return FileManager.default.fileExists(atPath: genURL.path)
    }

    // MARK: - Actions

    private func loadData() {
        guard !didLoad else { return }
        didLoad = true
        if let data = try? PromptScriptTemplate.load(from: fileURL) {
            promptData = data
        }
    }

    private func scheduleSave() {
        saveTimer?.cancel()
        let task = DispatchWorkItem { [promptData] in
            try? PromptScriptTemplate.save(promptData, to: fileURL)
        }
        saveTimer = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    private func openGeneratedScript() {
        #if os(macOS)
        guard let genURL = state.projectManager.generatedScriptURL(for: fileURL),
              FileManager.default.fileExists(atPath: genURL.path) else { return }
        NSWorkspace.shared.open(genURL)
        #endif
    }

    private func compilePrompt() {
        try? PromptScriptTemplate.save(promptData, to: fileURL)
        Task {
            await state.compilePromptScript(at: fileURL)
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MCTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
