#if os(macOS)
import SwiftUI
import AppKit
import MetalCasterRenderer

enum ToolWindowKind: String {
    case shaderCanvas = "Shader Canvas Pro"
    case sdfCanvas = "SDF Canvas Pro"
    case profiler = "Profiler"
    case frameDebugger = "Frame Debugger"

    var defaultSize: NSSize {
        switch self {
        case .shaderCanvas:  NSSize(width: 1280, height: 800)
        case .sdfCanvas:     NSSize(width: 1100, height: 720)
        case .profiler:      NSSize(width: 680, height: 520)
        case .frameDebugger: NSSize(width: 780, height: 560)
        }
    }
}

/// Opens standalone tool windows (NSWindow + NSHostingView) outside the main editor frame.
enum ToolWindowManager {
    private static var windows: [ToolWindowKind: NSWindow] = [:]
    private static var templatePickerWindow: NSWindow?

    static func open(_ kind: ToolWindowKind, state: EditorState) {
        if kind == .shaderCanvas {
            openShaderCanvasFlow(state: state)
            return
        }

        if let existing = windows[kind], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            resetFlag(kind, state: state)
            return
        }

        let content: AnyView
        switch kind {
        case .shaderCanvas:  return
        case .sdfCanvas:     content = AnyView(SDFCanvasProView().environment(state))
        case .profiler:      content = AnyView(ProfilerView().environment(state))
        case .frameDebugger: content = AnyView(FrameDebuggerView().environment(state))
        }

        openWindow(kind: kind, content: content)
        resetFlag(kind, state: state)
    }

    // MARK: - Shader Canvas Flow (Template Picker -> Canvas)

    private static func openShaderCanvasFlow(state: EditorState) {
        resetFlag(.shaderCanvas, state: state)

        if let existing = templatePickerWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let picker = ShaderCanvasTemplatePicker(
            onCancel: {
                templatePickerWindow?.close()
                templatePickerWindow = nil
            },
            onCreate: { template in
                templatePickerWindow?.close()
                templatePickerWindow = nil
                openShaderCanvas(template: template, state: state)
            }
        )

        let hosting = NSHostingView(rootView: picker)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 680, height: 460)),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.title = "New Shader"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.isReleasedWhenClosed = false

        templatePickerWindow = panel
    }

    private static func openShaderCanvas(template: ShaderCanvasTemplate, state: EditorState) {
        if let existing = windows[.shaderCanvas], existing.isVisible {
            existing.close()
            windows[.shaderCanvas] = nil
        }

        let canvasView = ShaderCanvasView(template: template)
            .environment(state)
        openWindow(kind: .shaderCanvas, content: AnyView(canvasView))
    }

    /// Opens Shader Canvas Pro with an existing material for editing.
    static func openShaderCanvas(material: MCMaterial, fileURL: URL, state: EditorState) {
        if let existing = windows[.shaderCanvas], existing.isVisible {
            existing.close()
            windows[.shaderCanvas] = nil
        }

        let canvasView = ShaderCanvasView(material: material, fileURL: fileURL)
            .environment(state)
        openWindow(kind: .shaderCanvas, content: AnyView(canvasView))
    }

    // MARK: - Generic Window Helper

    private static func openWindow(kind: ToolWindowKind, content: AnyView) {
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
        // SDF canvas uses in-canvas drag/drop heavily; avoid stealing drags as window moves.
        window.isMovableByWindowBackground = (kind != .sdfCanvas)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        windows[kind] = window
    }

    private static func resetFlag(_ kind: ToolWindowKind, state: EditorState) {
        DispatchQueue.main.async {
            switch kind {
            case .shaderCanvas:  state.showShaderCanvas = false
            case .sdfCanvas:     state.showSDFCanvas = false
            case .profiler:      state.showProfiler = false
            case .frameDebugger: state.showFrameDebugger = false
            }
        }
    }
}
#endif
