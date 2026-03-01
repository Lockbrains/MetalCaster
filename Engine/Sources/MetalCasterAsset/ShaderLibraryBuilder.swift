import Foundation
import Metal
import MetalCasterRenderer

// MARK: - ShaderSource

public struct ShaderSource {
    public let name: String
    public let mslSource: String

    public init(name: String, mslSource: String) {
        self.name = name
        self.mslSource = mslSource
    }
}

// MARK: - ShaderBuildError

public enum ShaderBuildError: LocalizedError {
    case compilationFailed(String)
    case metalToolNotFound
    case outputFailed(String)
    case platformNotSupported

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let message):
            return "Shader compilation failed: \(message)"
        case .metalToolNotFound:
            return "Metal command-line tools (xcrun metal/metallib) not found"
        case .outputFailed(let message):
            return "Failed to write output: \(message)"
        case .platformNotSupported:
            return "Shader precompilation to .metallib is only supported on macOS"
        }
    }
}

// MARK: - ShaderLibraryBuilder

/// Compiles Metal Shading Language sources into MTLLibrary instances
/// and supports offline precompilation to .metallib on macOS.
public final class ShaderLibraryBuilder {
    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    /// Compiles multiple MSL source strings into a single MTLLibrary by concatenating them.
    public func compileToLibrary(sources: [ShaderSource]) throws -> MTLLibrary {
        let combinedSource = sources.map(\.mslSource).joined(separator: "\n\n")
        guard let library = try? device.makeLibrary(source: combinedSource, options: nil) else {
            throw ShaderBuildError.compilationFailed("makeLibrary returned nil")
        }
        return library
    }

    /// Compiles MSL sources to a .metallib file on disk using command-line tools.
    /// Only supported on macOS; throws on other platforms.
    public func compileToMetalLib(sources: [ShaderSource], outputURL: URL) throws {
        #if os(macOS)
        for source in sources {
            _ = try compileToLibrary(sources: [source])
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var airURLs: [URL] = []
        for (index, source) in sources.enumerated() {
            let metalURL = tempDir.appendingPathComponent("\(source.name)_\(index).metal")
            let airURL = tempDir.appendingPathComponent("\(source.name)_\(index).air")
            try source.mslSource.write(to: metalURL, atomically: true, encoding: .utf8)

            let (status, stderr) = try runMetalCompile(input: metalURL, output: airURL)
            guard status == 0 else {
                throw ShaderBuildError.compilationFailed(
                    stderr.isEmpty ? "Metal compiler exited with code \(status)" : stderr
                )
            }
            airURLs.append(airURL)
        }

        let tempMetallibURL = tempDir.appendingPathComponent("output.metallib")
        let metallibStatus = try runMetallib(inputs: airURLs, output: tempMetallibURL)
        guard metallibStatus == 0 else {
            throw ShaderBuildError.metalToolNotFound
        }

        let parentDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        do {
            try FileManager.default.copyItem(at: tempMetallibURL, to: outputURL)
        } catch {
            throw ShaderBuildError.outputFailed(error.localizedDescription)
        }
        #else
        throw ShaderBuildError.platformNotSupported
        #endif
    }

    #if os(macOS)
    private func runMetalCompile(input: URL, output: URL) throws -> (Int32, String) {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-sdk", "macosx", "metal", "-c", input.path, "-o", output.path]
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw ShaderBuildError.metalToolNotFound
        }
        process.waitUntilExit()
        let stderrData = pipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stderr)
    }

    private func runMetallib(inputs: [URL], output: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-sdk", "macosx", "metallib"] + inputs.map(\.path) + ["-o", output.path]
        do {
            try process.run()
        } catch {
            throw ShaderBuildError.metalToolNotFound
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
    #endif

    /// Loads a precompiled .metallib file from disk.
    public func loadPrecompiledLibrary(url: URL) throws -> MTLLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ShaderBuildError.outputFailed("File not found: \(url.path)")
        }
        guard let library = try? device.makeLibrary(URL: url) else {
            throw ShaderBuildError.compilationFailed("Failed to load library from \(url.path)")
        }
        return library
    }

    /// Produces the default vertex and fragment shader sources with shared headers.
    public static func generateDefaultShaderSources() -> [ShaderSource] {
        let config = DataFlowConfig()
        let header = ShaderSnippets.generateSharedHeader(config: config)
        let vertex = ShaderSnippets.generateDefaultVertexShader(config: config)
        let fragment = ShaderSnippets.defaultFragment
        let defaultMeshSource = header + "\n" + vertex + "\n" + fragment

        return [
            ShaderSource(name: "DefaultMesh", mslSource: defaultMeshSource),
            ShaderSource(name: "Blit", mslSource: ShaderSnippets.blitShader)
        ]
    }
}
