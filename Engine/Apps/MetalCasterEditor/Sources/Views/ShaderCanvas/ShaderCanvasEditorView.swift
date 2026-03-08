#if os(macOS)
import SwiftUI
import AppKit
import MetalCasterRenderer

// MARK: - Shader Editor Panel

/// Sliding panel for editing shader code with MSL syntax highlighting,
/// snippet insertion, and preset selection.
struct ShaderCanvasEditorView: View {
    @Binding var shader: ActiveShader
    var dataFlowConfig: DataFlowConfig
    var compilationError: String?
    var onClose: () -> Void
    var onDismissError: () -> Void

    @State private var isRenaming = false
    @State private var editedName = ""

    private let snippets = [
        "mix()", "smoothstep()", "normalize()", "dot()", "cross()",
        "length()", "distance()", "reflect()", "max()", "min()",
        "clamp()", "sin()", "cos()", "sample()"
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                headerBar
                snippetBar
                presetBar
                MSLCodeEditor(text: $shader.code)
            }

            if let error = compilationError {
                errorOverlay(error)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            if isRenaming {
                TextField("", text: $editedName, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    .frame(maxWidth: 250)

                Button(action: commitRename) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green.opacity(0.8))
                }.buttonStyle(.plain)
            } else {
                Text(verbatim: shader.name)
                    .font(.headline).foregroundColor(.white)
                Button(action: {
                    editedName = shader.name
                    isRenaming = true
                }) {
                    Image(systemName: "pencil")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }

            Spacer()

            Button(action: resetShader) {
                Image(systemName: "arrow.counterclockwise").foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help("Reset to Template")
            .padding(.trailing, 12)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain)
        }
        .padding().background(Color.black.opacity(0.7))
    }

    // MARK: - Snippets

    private var snippetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(snippets, id: \.self) { snippet in
                    Button {
                        NotificationCenter.default.post(name: .mslInsertSnippet, object: snippet)
                    } label: {
                        Text(snippet)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.15)).cornerRadius(4)
                            .foregroundColor(.white)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }.background(Color.black.opacity(0.6))
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetBar: some View {
        if shader.category == .fragment {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    Text("Presets")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    ForEach(ShaderSnippets.shadingModelNames, id: \.self) { name in
                        Button {
                            shader.code = ShaderSnippets.shadingModel(named: name) ?? shader.code
                        } label: {
                            Text(name)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.purple.opacity(0.3)).cornerRadius(4)
                                .foregroundColor(.white)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }.background(Color.black.opacity(0.55))
        }

        if shader.category == .fullscreen {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    Text("PP Presets")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    ForEach(ShaderSnippets.ppPresetNames, id: \.self) { name in
                        Button {
                            shader.code = ShaderSnippets.ppPreset(named: name) ?? shader.code
                        } label: {
                            Text(name)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.orange.opacity(0.3)).cornerRadius(4)
                                .foregroundColor(.white)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }.background(Color.black.opacity(0.55))
        }
    }

    // MARK: - Error Overlay

    private func errorOverlay(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                Text("Compile Error")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                Spacer()
                Button(action: onDismissError) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            Text(error)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.red.opacity(0.15))
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.4), lineWidth: 1))
        .padding(8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func commitRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { shader.name = trimmed }
        isRenaming = false
    }

    private func resetShader() {
        switch shader.category {
        case .helper:     shader.code = "// Define reusable MSL functions here.\n\n"
        case .vertex:     shader.code = ShaderSnippets.generateVertexTemplate(config: dataFlowConfig)
        case .fragment:   shader.code = ShaderSnippets.fragmentTemplate
        case .fullscreen: shader.code = ShaderSnippets.fullscreenTemplate
        }
    }
}

// MARK: - MSL Code Editor (NSViewRepresentable)

/// A Metal Shading Language code editor with syntax highlighting, auto-indent,
/// and snippet insertion. Wraps NSTextView via NSViewRepresentable.
struct MSLCodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true

        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.textColor = NSColor(white: 0.9, alpha: 1.0)
        textView.insertionPointColor = NSColor.white
        textView.selectedTextAttributes = [.backgroundColor: NSColor(white: 0.3, alpha: 1.0)]
        textView.textContainerInset = NSSize(width: 4, height: 8)

        context.coordinator.textView = textView
        textView.delegate = context.coordinator

        textView.string = text
        context.coordinator.applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            context.coordinator.isUpdating = false
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MSLCodeEditor
        var isUpdating = false
        weak var textView: NSTextView?

        init(_ parent: MSLCodeEditor) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleInsertSnippet(_:)),
                name: .mslInsertSnippet, object: nil
            )
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc func handleInsertSnippet(_ notification: Notification) {
            guard let tv = textView, let snippet = notification.object as? String else { return }
            tv.insertText(snippet, replacementRange: tv.selectedRange())
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, !isUpdating else { return }
            isUpdating = true
            parent.text = tv.string
            applyHighlighting(to: tv)
            isUpdating = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let s = textView.string as NSString
                let sel = textView.selectedRange()
                let lineRange = s.lineRange(for: NSRange(location: sel.location, length: 0))
                let line = s.substring(with: lineRange)
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                var ins = "\n" + indent
                if line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("{") { ins += "    " }
                textView.insertText(ins, replacementRange: sel)
                return true
            }
            return false
        }

        // MARK: - Syntax Highlighting

        private let highlightRules: [(String, NSColor, NSRegularExpression.Options)] = [
            ("\\b(include|using|namespace|struct|vertex|fragment|kernel|constant|device|thread|threadgroup|return|constexpr|sampler|address|filter)\\b",
             NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1.0), []),
            ("\\b(float|float2|float3|float4|float4x4|float3x3|half|half2|half3|half4|int|uint|uint2|uint3|uint4|texture2d|void|bool)\\b",
             NSColor(red: 0.3, green: 0.7, blue: 0.8, alpha: 1.0), []),
            ("\\b(sin|cos|tan|max|min|clamp|dot|cross|normalize|length|distance|reflect|refract|mix|smoothstep|step|sample|pow|abs|fract|floor|ceil|saturate|sign|mod|exp|log|sqrt|atan2)\\b",
             NSColor(red: 0.8, green: 0.8, blue: 0.5, alpha: 1.0), []),
            ("\\[\\[[^\\]]+\\]\\]",
             NSColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1.0), []),
            ("\\b\\d+(\\.\\d+)?\\b",
             NSColor(red: 0.6, green: 0.8, blue: 0.6, alpha: 1.0), []),
            ("^\\s*#.*",
             NSColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1.0), .anchorsMatchLines),
            ("//.*",
             NSColor(red: 0.5, green: 0.6, blue: 0.5, alpha: 1.0), []),
        ]

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            let content = storage.string
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor(white: 0.9, alpha: 1.0), range: range)
            storage.addAttribute(.font, value: font, range: range)

            for (pattern, color, opts) in highlightRules {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
                for match in regex.matches(in: content, range: range) {
                    storage.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
            storage.endEditing()
        }
    }
}

// MARK: - Notification

extension NSNotification.Name {
    static let mslInsertSnippet = NSNotification.Name("mslInsertSnippet")
}
#endif
