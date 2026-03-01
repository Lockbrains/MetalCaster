import Metal

/// A simple frame graph that manages the execution order of render passes.
///
/// Passes are executed sequentially in the order they were added.
/// Future enhancement: dependency-based DAG scheduling.
public final class RenderGraph {

    /// All registered render passes, in execution order.
    private var passes: [any RenderPass] = []

    public init() {}

    /// Adds a pass to the end of the render graph.
    public func addPass(_ pass: any RenderPass) {
        passes.append(pass)
    }

    /// Inserts a pass at a specific index.
    public func insertPass(_ pass: any RenderPass, at index: Int) {
        passes.insert(pass, at: min(index, passes.count))
    }

    /// Removes a pass by reference.
    public func removePass(_ pass: any RenderPass) {
        passes.removeAll { $0 === pass }
    }

    /// Returns all registered passes.
    public var allPasses: [any RenderPass] { passes }

    /// Executes all enabled passes in order.
    public func execute(
        commandBuffer: MTLCommandBuffer,
        device: MCMetalDevice,
        context: inout RenderContext
    ) {
        for pass in passes where pass.isEnabled {
            pass.encode(
                commandBuffer: commandBuffer,
                device: device,
                context: &context
            )
        }
    }
}
