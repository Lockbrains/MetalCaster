import Metal
import Foundation

/// Caches compiled render pipeline states to avoid redundant GPU compilation.
///
/// Pipelines are keyed by a hash of their configuration.
/// When a shader's source code hasn't changed, the cached pipeline is reused.
public final class PipelineCache {

    private var cache: [String: MTLRenderPipelineState] = [:]
    private let compiler: ShaderCompiler

    public init(compiler: ShaderCompiler) {
        self.compiler = compiler
    }

    /// Gets a cached pipeline or compiles a new one.
    ///
    /// - Parameters:
    ///   - key: A unique string key for this pipeline configuration.
    ///   - compile: A closure that produces the pipeline state if not cached.
    /// - Returns: The cached or newly compiled pipeline state.
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

    /// Invalidates all cached pipelines.
    public func invalidateAll() {
        cache.removeAll()
    }

    /// The number of currently cached pipelines.
    public var count: Int { cache.count }
}
