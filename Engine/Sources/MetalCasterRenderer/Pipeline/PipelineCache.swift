import Metal
import Foundation

/// Caches compiled render pipeline states to avoid redundant GPU compilation.
///
/// Supports both simple string keys (legacy) and composite `PipelineCacheKey` (material-based).
/// When a shader's source code and render state haven't changed, the cached pipeline is reused.
public final class PipelineCache {

    private var cache: [String: MTLRenderPipelineState] = [:]
    private var materialCache: [PipelineCacheKey: MTLRenderPipelineState] = [:]
    private var depthStencilCache: [String: MTLDepthStencilState] = [:]
    private let compiler: ShaderCompiler

    public init(compiler: ShaderCompiler) {
        self.compiler = compiler
    }

    // MARK: - String-Keyed (Legacy)

    /// Gets a cached pipeline or compiles a new one.
    public func getOrCompile(
        key: String,
        compile: () throws -> MTLRenderPipelineState
    ) rethrows -> MTLRenderPipelineState {
        if let cached = cache[key] {
            return cached
        }
        let pipeline = try compile()
        cache[key] = pipeline
        return pipeline
    }

    /// Invalidates a specific cached pipeline.
    public func invalidate(key: String) {
        cache.removeValue(forKey: key)
    }

    // MARK: - Material-Keyed

    /// Gets a cached pipeline for a material or compiles a new one.
    public func getOrCompile(
        materialKey: PipelineCacheKey,
        compile: () throws -> MTLRenderPipelineState
    ) rethrows -> MTLRenderPipelineState {
        if let cached = materialCache[materialKey] {
            return cached
        }
        let pipeline = try compile()
        materialCache[materialKey] = pipeline
        return pipeline
    }

    /// Invalidates a material-keyed pipeline.
    public func invalidate(materialKey: PipelineCacheKey) {
        materialCache.removeValue(forKey: materialKey)
    }

    // MARK: - Depth Stencil Cache

    /// Gets or creates a depth stencil state for the given render state.
    public func depthStencilState(
        for renderState: MCRenderState,
        device: MTLDevice
    ) -> MTLDepthStencilState? {
        let key = "\(renderState.depthTest.rawValue)_\(renderState.depthWrite)"
        if let cached = depthStencilCache[key] {
            return cached
        }
        let desc = MTLDepthStencilDescriptor()
        desc.depthCompareFunction = renderState.depthTest.metalCompareFunction
        desc.isDepthWriteEnabled = renderState.depthWrite
        let state = device.makeDepthStencilState(descriptor: desc)
        if let state { depthStencilCache[key] = state }
        return state
    }

    // MARK: - Bulk Operations

    /// Invalidates all cached pipelines.
    public func invalidateAll() {
        cache.removeAll()
        materialCache.removeAll()
        depthStencilCache.removeAll()
    }

    /// The total number of cached pipelines.
    public var count: Int { cache.count + materialCache.count }
}
