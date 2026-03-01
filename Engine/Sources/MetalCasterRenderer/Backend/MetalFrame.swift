import Metal
import MetalKit

/// Per-frame rendering context. Encapsulates the command buffer and
/// drawable for a single frame's worth of GPU work.
public final class MetalFrame {

    /// The command buffer for this frame.
    public let commandBuffer: MTLCommandBuffer

    /// The drawable to present at the end of the frame.
    public let drawable: CAMetalDrawable?

    /// The render pass descriptor for the final blit to screen.
    public let renderPassDescriptor: MTLRenderPassDescriptor?

    /// The drawable size in pixels.
    public let drawableSize: CGSize

    public init(
        commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable?,
        renderPassDescriptor: MTLRenderPassDescriptor?,
        drawableSize: CGSize
    ) {
        self.commandBuffer = commandBuffer
        self.drawable = drawable
        self.renderPassDescriptor = renderPassDescriptor
        self.drawableSize = drawableSize
    }

    /// Presents the drawable and commits the command buffer.
    public func present() {
        if let drawable = drawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
