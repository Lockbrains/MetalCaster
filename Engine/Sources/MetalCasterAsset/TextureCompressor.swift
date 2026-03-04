import Foundation
import Metal
import MetalKit

/// Handles offline texture compression and compressed format detection/loading.
///
/// V1 Strategy: Metal GPUs can *decode* ASTC/BC but not *encode* at runtime.
/// This class provides:
/// - Detection of device-supported compressed formats
/// - Loading of pre-compressed textures (KTX headers or raw ASTC blocks)
/// - A CLI bridge to Apple's `texturetool` for offline compression
/// - Mipmap generation for uncompressed textures
public final class TextureCompressor {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    public init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }

    // MARK: - Format Support Detection

    public struct FormatSupport: Sendable {
        public let astc: Bool
        public let bc: Bool
        public let etc2: Bool

        public var preferredCompressed: CompressedFormat? {
            if astc { return .astc4x4 }
            if bc { return .bc7 }
            return nil
        }
    }

    /// Queries which compressed texture formats the current device supports.
    public func queryFormatSupport() -> FormatSupport {
        let astc = device.supportsFamily(.apple2)
        let bc = device.supportsFamily(.mac2) || device.supportsFamily(.macCatalyst2)
        let etc2 = device.supportsFamily(.apple1)
        return FormatSupport(astc: astc, bc: bc, etc2: etc2)
    }

    // MARK: - Mipmap Generation

    /// Generates mipmaps for a texture in-place using a blit encoder.
    public func generateMipmaps(for texture: MTLTexture) {
        guard texture.mipmapLevelCount > 1 else { return }
        guard let buffer = commandQueue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else { return }
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
    }

    // MARK: - Compressed Texture Creation

    /// Creates an empty compressed texture descriptor for a given format and size.
    public func makeCompressedTexture(
        width: Int,
        height: Int,
        format: CompressedFormat,
        mipmapped: Bool = true
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format.mtlPixelFormat,
            width: width,
            height: height,
            mipmapped: mipmapped
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    /// Loads pre-compressed texture data (raw block bytes) into a Metal texture.
    /// The data must match the format's block layout exactly.
    public func loadCompressedData(
        _ data: Data,
        width: Int,
        height: Int,
        format: CompressedFormat,
        bytesPerRow: Int
    ) -> MTLTexture? {
        guard let texture = makeCompressedTexture(width: width, height: height, format: format, mipmapped: false) else {
            return nil
        }

        data.withUnsafeBytes { ptr in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        return texture
    }

    // MARK: - Offline Compression via CLI

    /// Attempts to compress a texture file using Apple's `texturetool` CLI.
    /// Returns the URL of the compressed output file, or nil if the tool is unavailable.
    public func compressOffline(
        inputURL: URL,
        outputURL: URL,
        format: CompressedFormat
    ) -> Bool {
        let toolPath = "/usr/bin/xcrun"
        let formatArg: String
        switch format {
        case .astc4x4: formatArg = "astc_4x4"
        case .astc8x8: formatArg = "astc_8x8"
        case .bc1: formatArg = "bc1"
        case .bc3: formatArg = "bc3"
        case .bc7: formatArg = "bc7"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = [
            "texturetool",
            "-e", formatArg,
            "-o", outputURL.path,
            inputURL.path
        ]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Texture Info

    /// Returns the estimated memory size in bytes for a compressed texture.
    public static func compressedMemorySize(
        width: Int,
        height: Int,
        format: CompressedFormat,
        mipmapped: Bool = true
    ) -> Int {
        let bitsPerPixel: Int
        switch format {
        case .astc4x4: bitsPerPixel = 8
        case .astc8x8: bitsPerPixel = 2
        case .bc1: bitsPerPixel = 4
        case .bc3, .bc7: bitsPerPixel = 8
        }

        var total = (width * height * bitsPerPixel) / 8
        if mipmapped {
            total = total * 4 / 3
        }
        return total
    }
}
