import Foundation
import simd
import MetalCasterCore

// MARK: - UI Canvas Component

/// Defines a UI canvas that holds UI elements. Attached to an entity to create a UI hierarchy.
public struct UICanvasComponent: Component {
    public enum RenderSpace: String, Codable, Sendable {
        case screen
        case world
    }

    public var renderSpace: RenderSpace
    public var sortOrder: Int
    public var referenceResolution: SIMD2<Float>
    public var isEnabled: Bool

    public init(
        renderSpace: RenderSpace = .screen,
        sortOrder: Int = 0,
        referenceResolution: SIMD2<Float> = SIMD2<Float>(1920, 1080),
        isEnabled: Bool = true
    ) {
        self.renderSpace = renderSpace
        self.sortOrder = sortOrder
        self.referenceResolution = referenceResolution
        self.isEnabled = isEnabled
    }
}

// MARK: - UI Element Types

public enum UIElementType: String, Codable, Sendable {
    case label
    case image
    case panel
    case button
}

// MARK: - UI Element Component

/// A single UI element that can be rendered. Attach to child entities of a UICanvas entity.
public struct UIElementComponent: Component {
    public var elementType: UIElementType
    public var anchor: SIMD2<Float>
    public var pivot: SIMD2<Float>
    public var size: SIMD2<Float>
    public var offset: SIMD2<Float>
    public var tint: SIMD4<Float>
    public var isVisible: Bool

    public init(
        elementType: UIElementType = .panel,
        anchor: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        pivot: SIMD2<Float> = SIMD2<Float>(0.5, 0.5),
        size: SIMD2<Float> = SIMD2<Float>(100, 50),
        offset: SIMD2<Float> = .zero,
        tint: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        isVisible: Bool = true
    ) {
        self.elementType = elementType
        self.anchor = anchor
        self.pivot = pivot
        self.size = size
        self.offset = offset
        self.tint = tint
        self.isVisible = isVisible
    }
}

// MARK: - UI Label Component

/// Text content for a UI label element.
public struct UILabelComponent: Component {
    public var text: String
    public var fontSize: Float
    public var fontName: String
    public var color: SIMD4<Float>
    public var alignment: TextAlignment

    public enum TextAlignment: String, Codable, Sendable {
        case left, center, right
    }

    public init(
        text: String = "",
        fontSize: Float = 16,
        fontName: String = "Helvetica",
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        alignment: TextAlignment = .left
    ) {
        self.text = text
        self.fontSize = fontSize
        self.fontName = fontName
        self.color = color
        self.alignment = alignment
    }
}

// MARK: - UI Image Component

/// Image content for a UI image element.
public struct UIImageComponent: Component {
    public var texturePath: String
    public var preserveAspect: Bool
    public var uvRect: SIMD4<Float>

    public init(
        texturePath: String = "",
        preserveAspect: Bool = true,
        uvRect: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)
    ) {
        self.texturePath = texturePath
        self.preserveAspect = preserveAspect
        self.uvRect = uvRect
    }
}

// MARK: - UI Panel Component

/// Background panel for UI grouping.
public struct UIPanelComponent: Component {
    public var backgroundColor: SIMD4<Float>
    public var cornerRadius: Float
    public var borderWidth: Float
    public var borderColor: SIMD4<Float>

    public init(
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0.8),
        cornerRadius: Float = 8,
        borderWidth: Float = 1,
        borderColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 0.15)
    ) {
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
    }
}
