import Foundation
import Metal

// MARK: - Blend Mode

/// How the fragment output blends with the existing framebuffer contents.
public enum MCBlendMode: String, Codable, Sendable, CaseIterable {
    /// Fully opaque — no blending.
    case opaque
    /// Standard alpha blending (srcAlpha, oneMinusSrcAlpha).
    case alpha
    /// Additive blending (one, one).
    case additive
    /// Multiplicative blending (destColor, zero).
    case multiply
}

// MARK: - Depth Test

/// Depth comparison function.
public enum MCDepthTest: String, Codable, Sendable {
    case never
    case less
    case lessEqual
    case equal
    case greater
    case greaterEqual
    case always
}

// MARK: - Cull Mode

/// Triangle face culling mode.
public enum MCCullMode: String, Codable, Sendable {
    case none
    case front
    case back
}

// MARK: - Render Queue

/// Determines draw order. Lower values render first.
public enum MCRenderQueue: Int, Codable, Sendable, Comparable {
    case background  = 1000
    case opaque      = 2000
    case transparent = 3000
    case overlay     = 4000

    public static func < (lhs: MCRenderQueue, rhs: MCRenderQueue) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Render State

/// Complete render state configuration for a material pass.
public struct MCRenderState: Codable, Sendable, Hashable {
    public var blendMode: MCBlendMode
    public var depthWrite: Bool
    public var depthTest: MCDepthTest
    public var cullMode: MCCullMode
    public var renderQueue: MCRenderQueue

    public init(
        blendMode: MCBlendMode = .opaque,
        depthWrite: Bool = true,
        depthTest: MCDepthTest = .less,
        cullMode: MCCullMode = .back,
        renderQueue: MCRenderQueue = .opaque
    ) {
        self.blendMode = blendMode
        self.depthWrite = depthWrite
        self.depthTest = depthTest
        self.cullMode = cullMode
        self.renderQueue = renderQueue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blendMode = try c.decodeIfPresent(MCBlendMode.self, forKey: .blendMode) ?? .opaque
        depthWrite = try c.decodeIfPresent(Bool.self, forKey: .depthWrite) ?? true
        depthTest = try c.decodeIfPresent(MCDepthTest.self, forKey: .depthTest) ?? .less
        cullMode = try c.decodeIfPresent(MCCullMode.self, forKey: .cullMode) ?? .back
        renderQueue = try c.decodeIfPresent(MCRenderQueue.self, forKey: .renderQueue) ?? .opaque
    }

    /// Opaque default — depth write on, depth test less, cull back.
    public static let opaque = MCRenderState()

    /// Transparent default — alpha blending, depth write off, cull back.
    public static let transparent = MCRenderState(
        blendMode: .alpha,
        depthWrite: false,
        renderQueue: .transparent
    )

    /// Skybox — no depth write, depth test less-equal, cull front (view from inside).
    public static let skybox = MCRenderState(
        blendMode: .opaque,
        depthWrite: false,
        depthTest: .lessEqual,
        cullMode: .front,
        renderQueue: .background
    )
}

// MARK: - Material Type

/// Whether a material is engine-provided (immutable) or user-created.
public enum MCMaterialType: String, Codable, Sendable {
    /// Engine built-in material — cannot be edited by users.
    case builtin
    /// User-created material via ShaderCanvas.
    case custom
}

// MARK: - Metal Conversions

extension MCBlendMode {
    /// Configures a Metal color attachment for this blend mode.
    public func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .opaque:
            attachment.isBlendingEnabled = false
        case .alpha:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        case .multiply:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .destinationColor
            attachment.destinationRGBBlendFactor = .zero
            attachment.sourceAlphaBlendFactor = .destinationAlpha
            attachment.destinationAlphaBlendFactor = .zero
        }
    }
}

extension MCDepthTest {
    public var metalCompareFunction: MTLCompareFunction {
        switch self {
        case .never:        return .never
        case .less:         return .less
        case .lessEqual:    return .lessEqual
        case .equal:        return .equal
        case .greater:      return .greater
        case .greaterEqual: return .greaterEqual
        case .always:       return .always
        }
    }
}

extension MCCullMode {
    public var metalCullMode: MTLCullMode {
        switch self {
        case .none:  return .none
        case .front: return .front
        case .back:  return .back
        }
    }
}
