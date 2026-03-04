import Metal

/// Utility for dispatching compute work with optimal thread group sizes.
public struct ComputeDispatcher {

    /// Dispatches a 2D compute grid covering `width x height` elements.
    /// Automatically selects the optimal thread group size for the pipeline.
    public static func dispatch2D(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int
    ) {
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Dispatches a 1D compute grid covering `count` elements.
    public static func dispatch1D(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        count: Int
    ) {
        let w = min(pipeline.maxTotalThreadsPerThreadgroup, count)
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Dispatches a 3D compute grid.
    public static func dispatch3D(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int,
        depth: Int
    ) {
        let execWidth = pipeline.threadExecutionWidth
        let maxThreads = pipeline.maxTotalThreadsPerThreadgroup
        let h = max(1, maxThreads / execWidth)
        let d = max(1, maxThreads / (execWidth * h))
        let threadsPerGroup = MTLSize(width: execWidth, height: h, depth: d)
        let gridSize = MTLSize(width: width, height: height, depth: depth)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Dispatches using thread group count (for devices that don't support non-uniform grids).
    public static func dispatchThreadgroups2D(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        width: Int,
        height: Int
    ) {
        let w = pipeline.threadExecutionWidth
        let h = pipeline.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
        let threadgroupCount = MTLSize(
            width: (width + w - 1) / w,
            height: (height + h - 1) / h,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerGroup)
    }

    /// Dispatches using an indirect buffer containing thread group counts.
    public static func dispatchIndirect(
        encoder: MTLComputeCommandEncoder,
        pipeline: MTLComputePipelineState,
        indirectBuffer: MTLBuffer,
        offset: Int = 0,
        threadsPerGroup: MTLSize
    ) {
        encoder.dispatchThreadgroups(
            indirectBuffer: indirectBuffer,
            indirectBufferOffset: offset,
            threadsPerThreadgroup: threadsPerGroup
        )
    }
}
