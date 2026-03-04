import Foundation
import simd
import MetalCasterCore
import MetalCasterRenderer

/// ECS System that collects UI elements each frame and prepares draw data
/// for the renderer. Handles layout computation for screen-space UI.
public final class UIRenderSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { 95 }

    /// Collected UI draw calls for the current frame. Read by the renderer.
    public nonisolated(unsafe) var uiDrawCalls: [UIDrawCall] = []

    /// Current screen size, must be set by the renderer each frame.
    public nonisolated(unsafe) var screenSize: SIMD2<Float> = SIMD2<Float>(1920, 1080)

    public init() {}

    public func update(context: UpdateContext) {
        uiDrawCalls.removeAll(keepingCapacity: true)
        let world = context.world

        let canvases = world.query(UICanvasComponent.self)
        let sortedCanvases = canvases.sorted { $0.1.sortOrder < $1.1.sortOrder }

        for (canvasEntity, canvas) in sortedCanvases {
            guard canvas.isEnabled else { continue }
            collectElements(world: world, canvas: canvas, canvasEntity: canvasEntity)
        }
    }

    private func collectElements(world: World, canvas: UICanvasComponent, canvasEntity: Entity) {
        let elements = world.query(UIElementComponent.self)

        for (entity, element) in elements {
            guard element.isVisible else { continue }

            let screenPos = computeScreenPosition(element: element, canvas: canvas)
            let screenSize = element.size

            var drawCall = UIDrawCall(
                entity: entity,
                elementType: element.elementType,
                screenPosition: screenPos,
                screenSize: screenSize,
                tint: element.tint,
                renderSpace: canvas.renderSpace
            )

            if let label = world.getComponent(UILabelComponent.self, from: entity) {
                drawCall.text = label.text
                drawCall.fontSize = label.fontSize
                drawCall.textColor = label.color
                drawCall.textAlignment = label.alignment
            }

            if let image = world.getComponent(UIImageComponent.self, from: entity) {
                drawCall.texturePath = image.texturePath
                drawCall.uvRect = image.uvRect
            }

            if let panel = world.getComponent(UIPanelComponent.self, from: entity) {
                drawCall.backgroundColor = panel.backgroundColor
                drawCall.cornerRadius = panel.cornerRadius
                drawCall.borderWidth = panel.borderWidth
                drawCall.borderColor = panel.borderColor
            }

            uiDrawCalls.append(drawCall)
        }
    }

    private func computeScreenPosition(element: UIElementComponent, canvas: UICanvasComponent) -> SIMD2<Float> {
        let ref = canvas.renderSpace == .screen ? screenSize : canvas.referenceResolution
        let anchorPos = element.anchor * ref
        let pivotOffset = element.pivot * element.size
        return anchorPos + element.offset - pivotOffset
    }
}

// MARK: - UI Draw Call

/// A single UI element ready for rendering.
public struct UIDrawCall {
    public var entity: Entity
    public var elementType: UIElementType
    public var screenPosition: SIMD2<Float>
    public var screenSize: SIMD2<Float>
    public var tint: SIMD4<Float>
    public var renderSpace: UICanvasComponent.RenderSpace

    // Label
    public var text: String?
    public var fontSize: Float = 16
    public var textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    public var textAlignment: UILabelComponent.TextAlignment = .left

    // Image
    public var texturePath: String?
    public var uvRect: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)

    // Panel
    public var backgroundColor: SIMD4<Float>?
    public var cornerRadius: Float = 0
    public var borderWidth: Float = 0
    public var borderColor: SIMD4<Float>?
}
