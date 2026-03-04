import Metal

/// Protocol for a GPU compute pass in the render graph.
///
/// Compute passes encode dispatch commands via `MTLComputeCommandEncoder`.
/// They share the same `RenderContext` as render passes for resource access.
public protocol ComputePass: AnyObject {
    var name: String { get }
    var isEnabled: Bool { get set }

    /// Encodes compute dispatch commands into the given command buffer.
    func encode(
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        context: inout RenderContext
    )
}

/// Type-erasing wrapper so RenderGraph can store both render and compute passes.
public enum GraphPass {
    case render(any RenderPass)
    case compute(any ComputePass)

    public var name: String {
        switch self {
        case .render(let p): return p.name
        case .compute(let p): return p.name
        }
    }

    public var isEnabled: Bool {
        get {
            switch self {
            case .render(let p): return p.isEnabled
            case .compute(let p): return p.isEnabled
            }
        }
        set {
            switch self {
            case .render(let p): p.isEnabled = newValue
            case .compute(let p): p.isEnabled = newValue
            }
        }
    }
}
