#if os(macOS)
import SwiftUI
import AppKit
import MetalKit

struct SceneComposerProMetalView: NSViewRepresentable {
    @Binding var cameraYaw: Float
    @Binding var cameraPitch: Float
    @Binding var cameraDistance: Float
    @Binding var worldSize: SIMD2<Float>
    @Binding var maxHeight: Float
    @Binding var noiseFrequency: Float
    @Binding var noiseOctaves: Int
    @Binding var noiseSeed: UInt32
    @Binding var needsRegeneration: Bool
    @Binding var erosionEnabled: Bool
    @Binding var erosionStrength: Float
    @Binding var needsErosion: Bool
    @Binding var selectedWorldPosition: SIMD3<Float>?

    var selectedTool: ComposerToolMode
    var brushSettings: ComposerBrushSettings
    var waterLevel: Float
    var showWater: Bool
    var waterDeepColor: SIMD3<Float>
    var waterShallowColor: SIMD3<Float>
    var waterOpacity: Float
    var waterWaveScale: Float
    var waterWaveSpeed: Float
    var sunAltitude: Float
    var sunAzimuth: Float
    var fogDensity: Float

    var onSpacePressed: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> InteractiveComposerMTKView {
        let mtkView = InteractiveComposerMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60

        if let renderer = SceneComposerProRenderer(mtkView: mtkView) {
            context.coordinator.renderer = renderer
            mtkView.delegate = renderer
            syncRenderer(renderer)
        }
        context.coordinator.view = mtkView
        mtkView.coordinator = context.coordinator
        return mtkView
    }

    func updateNSView(_ nsView: InteractiveComposerMTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        syncRenderer(renderer)
        if needsRegeneration {
            renderer.needsHeightmapRegeneration = true
            DispatchQueue.main.async { needsRegeneration = false }
        }
        if needsErosion {
            renderer.needsErosion = true
            DispatchQueue.main.async { needsErosion = false }
        }
    }

    private func syncRenderer(_ renderer: SceneComposerProRenderer) {
        renderer.cameraYaw = cameraYaw
        renderer.cameraPitch = cameraPitch
        renderer.cameraDistance = cameraDistance
        renderer.cameraTarget = SIMD3<Float>(0, maxHeight * 0.25, 0)
        renderer.worldSize = worldSize
        renderer.maxHeight = maxHeight
        renderer.noiseFrequency = noiseFrequency
        renderer.noiseOctaves = noiseOctaves
        renderer.noiseSeed = noiseSeed
        renderer.erosionEnabled = erosionEnabled
        renderer.erosionStrength = erosionStrength
        renderer.selectedPosition = selectedWorldPosition
        renderer.waterLevel = waterLevel
        renderer.showWater = showWater
        renderer.waterDeepColor = waterDeepColor
        renderer.waterShallowColor = waterShallowColor
        renderer.waterOpacity = waterOpacity
        renderer.waterWaveScale = waterWaveScale
        renderer.waterWaveSpeed = waterWaveSpeed
        renderer.sunAltitude = sunAltitude
        renderer.sunAzimuth = sunAzimuth
        renderer.fogDensity = fogDensity
    }

    final class Coordinator {
        let parent: SceneComposerProMetalView
        var renderer: SceneComposerProRenderer?
        weak var view: InteractiveComposerMTKView?
        private var isPainting = false

        init(parent: SceneComposerProMetalView) {
            self.parent = parent
        }

        var isBrushMode: Bool {
            parent.selectedTool == .terrain || parent.selectedTool == .brush
        }

        func handleScrollWheel(_ event: NSEvent) {
            let delta = Float(event.scrollingDeltaY) * 2.0
            parent.cameraDistance = max(20, min(1000, parent.cameraDistance - delta))
        }

        func handleRightDrag(_ event: NSEvent) {
            parent.cameraYaw += Float(event.deltaX) * 0.008
            parent.cameraPitch = max(0.05, min(Float.pi / 2 - 0.05, parent.cameraPitch + Float(event.deltaY) * 0.008))
        }

        func handleMouseDown(_ event: NSEvent) {
            if isBrushMode {
                isPainting = true
                applyBrush(event)
            } else {
                guard let mtkView = view, let renderer = renderer else { return }
                let loc = mtkView.convert(event.locationInWindow, from: nil)
                parent.selectedWorldPosition = renderer.hitTest(screenPoint: loc, viewSize: mtkView.bounds.size)
            }
        }

        func handleMouseDragged(_ event: NSEvent) {
            if event.modifierFlags.contains(.command) {
                handleRightDrag(event)
            } else if isPainting && isBrushMode {
                applyBrush(event)
            }
        }

        func handleMouseUp(_ event: NSEvent) {
            isPainting = false
        }

        private func applyBrush(_ event: NSEvent) {
            guard let mtkView = view, let renderer = renderer else { return }
            let loc = mtkView.convert(event.locationInWindow, from: nil)
            guard let worldPos = renderer.hitTest(screenPoint: loc, viewSize: mtkView.bounds.size) else { return }
            let bs = parent.brushSettings
            renderer.queueBrushStroke(worldPos: worldPos, radius: bs.radius, strength: bs.strength, mode: bs.mode, falloff: bs.falloff)
        }

        func handleSpaceKey() { parent.onSpacePressed?() }
    }
}

final class InteractiveComposerMTKView: MTKView {
    weak var coordinator: SceneComposerProMetalView.Coordinator?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        coordinator?.handleMouseDown(event)
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator?.handleMouseDragged(event)
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.handleMouseUp(event)
    }

    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScrollWheel(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        coordinator?.handleRightDrag(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { coordinator?.handleSpaceKey() }
    }
}
#endif
