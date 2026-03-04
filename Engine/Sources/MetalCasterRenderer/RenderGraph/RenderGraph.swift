import Metal

/// A frame graph that manages the execution order of render and compute passes.
///
/// Passes are executed sequentially in the order they were added.
/// Supports mixed render/compute pass ordering — encoder transitions
/// are handled implicitly by Metal's command buffer.
public final class RenderGraph {

    private var passes: [GraphPass] = []

    public init() {}

    // MARK: - Pass Management

    public func addPass(_ pass: any RenderPass) {
        passes.append(.render(pass))
    }

    public func addComputePass(_ pass: any ComputePass) {
        passes.append(.compute(pass))
    }

    public func addGraphPass(_ pass: GraphPass) {
        passes.append(pass)
    }

    public func insertPass(_ pass: any RenderPass, at index: Int) {
        passes.insert(.render(pass), at: min(index, passes.count))
    }

    public func insertComputePass(_ pass: any ComputePass, at index: Int) {
        passes.insert(.compute(pass), at: min(index, passes.count))
    }

    public func removePass(named name: String) {
        passes.removeAll { $0.name == name }
    }

    public func removePass(_ pass: any RenderPass) {
        passes.removeAll {
            if case .render(let p) = $0 { return p === pass }
            return false
        }
    }

    public func removeComputePass(_ pass: any ComputePass) {
        passes.removeAll {
            if case .compute(let p) = $0 { return p === pass }
            return false
        }
    }

    public var allPasses: [GraphPass] { passes }

    public var allRenderPasses: [any RenderPass] {
        passes.compactMap {
            if case .render(let p) = $0 { return p }
            return nil
        }
    }

    public var allComputePasses: [any ComputePass] {
        passes.compactMap {
            if case .compute(let p) = $0 { return p }
            return nil
        }
    }

    // MARK: - Execution

    /// Executes all enabled passes in order.
    /// Render and compute passes are encoded sequentially — Metal handles
    /// the implicit barrier between different encoder types on the same command buffer.
    public func execute(
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        context: inout RenderContext
    ) {
        for pass in passes where pass.isEnabled {
            switch pass {
            case .render(let renderPass):
                renderPass.encode(
                    commandBuffer: commandBuffer,
                    device: device,
                    context: &context
                )
            case .compute(let computePass):
                computePass.encode(
                    commandBuffer: commandBuffer,
                    device: device,
                    context: &context
                )
            }
        }
    }
}
