import Metal
import Foundation

/// Compiles Metal Shading Language (MSL) source at runtime.
///
/// Supports both runtime compilation (for live editing) and
/// will support pre-compiled .metallib loading for shipping builds.
public final class ShaderCompiler {

    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    /// Compiles MSL source code into a Metal library.
    ///
    /// - Parameter source: Complete MSL source code string.
    /// - Returns: A compiled MTLLibrary on success, or throws on compilation error.
    public func compile(source: String) throws -> MTLLibrary {
        try device.makeLibrary(source: source, options: nil)
    }

    /// Compiles and creates a render pipeline state from vertex and fragment source.
    ///
    /// - Parameters:
    ///   - vertexSource: MSL source containing `vertex_main`.
    ///   - fragmentSource: MSL source containing `fragment_main`.
    ///   - colorFormat: The pixel format for the color attachment.
    ///   - depthFormat: The pixel format for the depth attachment (or .invalid).
    ///   - vertexDescriptor: Optional Metal vertex descriptor for mesh pipelines.
    /// - Returns: A compiled MTLRenderPipelineState.
    public func compilePipeline(
        vertexSource: String,
        fragmentSource: String,
        colorFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .invalid,
        vertexDescriptor: MTLVertexDescriptor? = nil
    ) throws -> MTLRenderPipelineState {
        let vLib = try compile(source: vertexSource)
        let fLib = try compile(source: fragmentSource)

        guard let vertexFunc = vLib.makeFunction(name: "vertex_main"),
              let fragFunc = fLib.makeFunction(name: "fragment_main") else {
            throw ShaderCompilationError.missingEntryPoint
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = colorFormat
        desc.depthAttachmentPixelFormat = depthFormat
        if let vd = vertexDescriptor {
            desc.vertexDescriptor = vd
        }

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    /// Compiles a unified MSL source (vertex + fragment in one string) with full render state control.
    ///
    /// - Parameters:
    ///   - source: Complete MSL source containing both `vertex_main` and `fragment_main`.
    ///   - renderState: The render state configuration for blend mode.
    ///   - colorFormat: The pixel format for the color attachment.
    ///   - depthFormat: The pixel format for the depth attachment (or .invalid).
    ///   - vertexDescriptor: Optional Metal vertex descriptor for mesh pipelines.
    ///   - vertexFunctionName: The vertex function name (default "vertex_main").
    ///   - fragmentFunctionName: The fragment function name (default "fragment_main").
    /// - Returns: A compiled MTLRenderPipelineState.
    public func compileUnifiedPipeline(
        source: String,
        renderState: MCRenderState = .opaque,
        colorFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .invalid,
        vertexDescriptor: MTLVertexDescriptor? = nil,
        vertexFunctionName: String = "vertex_main",
        fragmentFunctionName: String = "fragment_main"
    ) throws -> MTLRenderPipelineState {
        let lib = try compile(source: source)

        guard let vertexFunc = lib.makeFunction(name: vertexFunctionName),
              let fragFunc = lib.makeFunction(name: fragmentFunctionName) else {
            throw ShaderCompilationError.missingEntryPoint
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = colorFormat
        desc.depthAttachmentPixelFormat = depthFormat

        renderState.blendMode.apply(to: desc.colorAttachments[0])

        if let vd = vertexDescriptor {
            desc.vertexDescriptor = vd
        }

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    /// Compiles a self-contained fullscreen shader (both vertex and fragment in one source).
    public func compileFullscreenPipeline(
        source: String,
        colorFormat: MTLPixelFormat = .bgra8Unorm
    ) throws -> MTLRenderPipelineState {
        let lib = try compile(source: source)

        guard let vertexFunc = lib.makeFunction(name: "vertex_main"),
              let fragFunc = lib.makeFunction(name: "fragment_main") else {
            throw ShaderCompilationError.missingEntryPoint
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = colorFormat

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    /// Extracts concise MSL error lines from a Metal compilation error string.
    public static func extractMSLErrors(from fullError: String) -> String {
        fullError.components(separatedBy: "\n")
            .filter { $0.contains("error:") }
            .map { line in
                if let range = line.range(of: #"program_source:\d+:\d+: error: .+"#, options: .regularExpression) {
                    return String(line[range])
                }
                return line
            }
            .joined(separator: "\n")
    }
}

/// Errors that can occur during shader compilation.
public enum ShaderCompilationError: LocalizedError {
    case missingEntryPoint
    case compilationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingEntryPoint:
            return "Missing vertex_main or fragment_main entry point"
        case .compilationFailed(let msg):
            return "Shader compilation failed: \(msg)"
        }
    }
}
