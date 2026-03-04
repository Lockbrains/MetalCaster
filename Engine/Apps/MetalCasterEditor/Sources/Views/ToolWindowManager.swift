#if os(macOS)
import SwiftUI
import AppKit

enum ToolWindowKind: String {
    case shaderCanvas = "Shader Canvas"
    case sdfCanvas = "SDF Canvas"

    var defaultSize: NSSize {
        switch self {
        case .shaderCanvas: NSSize(width: 1100, height: 720)
        case .sdfCanvas:    NSSize(width: 1100, height: 720)
        }
    }
}

/// Opens standalone tool windows (NSWindow + NSHostingView) outside the main editor frame.
enum ToolWindowManager {
    private static var windows: [ToolWindowKind: NSWindow] = [:]

    static func open(_ kind: ToolWindowKind, state: EditorState) {
        if let existing = windows[kind], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            resetFlag(kind, state: state)
            return
        }

        let content: AnyView
        switch kind {
        case .shaderCanvas: content = AnyView(ShaderCanvasToolView().environment(state))
        case .sdfCanvas:    content = AnyView(SDFCanvasToolView().environment(state))
        }

        let hosting = NSHostingView(rootView: content)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: kind.defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = kind.rawValue
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.isOpaque = true
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        windows[kind] = window
        resetFlag(kind, state: state)
    }

    private static func resetFlag(_ kind: ToolWindowKind, state: EditorState) {
        DispatchQueue.main.async {
            switch kind {
            case .shaderCanvas: state.showShaderCanvas = false
            case .sdfCanvas:    state.showSDFCanvas = false
            }
        }
    }
}

// MARK: - Shader Canvas Tool

struct ShaderCanvasToolView: View {
    @Environment(EditorState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "paintbrush.pointed")
                    .font(.system(size: 14))
                    .foregroundStyle(MCTheme.statusBlue)
                Text("Shader Canvas")
                    .font(MCTheme.fontTitle)
                    .foregroundStyle(MCTheme.textPrimary)
                Spacer()
                Text("Real-time shader authoring")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            Divider().background(MCTheme.panelBorder)

            ZStack {
                MCTheme.background
                VStack(spacing: 16) {
                    Image(systemName: "function")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(MCTheme.textTertiary)
                    Text("Shader Canvas is integrated with the engine.\nOpen a .metal shader from the Project Assets to begin editing.")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }
}

// MARK: - SDF Canvas Tool

struct SDFCanvasToolView: View {
    @Environment(EditorState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 14))
                    .foregroundStyle(MCTheme.statusOrange)
                Text("SDF Canvas")
                    .font(MCTheme.fontTitle)
                    .foregroundStyle(MCTheme.textPrimary)
                Spacer()
                Text("Signed distance field modeling")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))

            Divider().background(MCTheme.panelBorder)

            ZStack {
                MCTheme.background
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(MCTheme.textTertiary)
                    Text("SDF Canvas enables real-time SDF modeling\nwith marching cubes mesh export to USD.")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }
}
#endif
