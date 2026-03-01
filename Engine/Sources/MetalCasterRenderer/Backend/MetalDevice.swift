import Metal
import MetalKit

/// Wrapper around MTLDevice and MTLCommandQueue.
/// Provides the entry point to all Metal GPU operations.
public final class MCMetalDevice: @unchecked Sendable {

    /// The GPU device handle.
    public let device: MTLDevice

    /// Serializes GPU command buffers.
    public let commandQueue: MTLCommandQueue

    /// Depth testing configuration: less-than comparison with depth writes enabled.
    public let depthStencilState: MTLDepthStencilState

    /// The texture loader for importing images.
    public let textureLoader: MTKTextureLoader

    /// Creates a device wrapper from an existing MTLDevice, or discovers the system default.
    public init?(device: MTLDevice? = nil) {
        guard let dev = device ?? MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = dev.makeCommandQueue() else { return nil }

        self.device = dev
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: dev)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let dss = dev.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.depthStencilState = dss
    }

    /// Creates a command buffer from the command queue.
    public func makeCommandBuffer() -> MTLCommandBuffer? {
        commandQueue.makeCommandBuffer()
    }
}
