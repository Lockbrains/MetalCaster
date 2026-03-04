import Foundation
import Metal
import MetalKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage

public enum TextureError: Error, LocalizedError {
    case loadFailed(URL, Error)
    case loadFromBundleFailed(String, Error)
    case textureCreationFailed
    case formatNotSupported(MTLPixelFormat)
    case compressionRequiresFormatConversion
    case exportFailed(Error)
    case unsupportedExportFormat(String)

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let url, let underlying): return "Failed to load texture from \(url.path): \(underlying.localizedDescription)"
        case .loadFromBundleFailed(let name, let underlying): return "Failed to load texture '\(name)' from bundle: \(underlying.localizedDescription)"
        case .textureCreationFailed: return "Failed to create texture"
        case .formatNotSupported(let fmt): return "Pixel format \(fmt.rawValue) is not supported on this device"
        case .compressionRequiresFormatConversion: return "Metal blit encoder cannot convert between pixel formats; source and destination must match"
        case .exportFailed(let underlying): return "Failed to export texture: \(underlying.localizedDescription)"
        case .unsupportedExportFormat(let fmt): return "Unsupported export format: \(fmt)"
        }
    }
}

public struct TextureLoadOptions {
    public var sRGB: Bool = true
    public var generateMipmaps: Bool = true
    public var textureUsage: MTLTextureUsage = [.shaderRead]
    public var storageMode: MTLResourceOptions = []

    public init(sRGB: Bool = true, generateMipmaps: Bool = true, textureUsage: MTLTextureUsage = [.shaderRead], storageMode: MTLResourceOptions = []) {
        self.sRGB = sRGB
        self.generateMipmaps = generateMipmaps
        self.textureUsage = textureUsage
        self.storageMode = storageMode
    }
}

public enum CompressedFormat {
    case astc4x4
    case astc8x8
    case bc1
    case bc3
    case bc7

    public var mtlPixelFormat: MTLPixelFormat {
        switch self {
        case .astc4x4: return .astc_4x4_srgb
        case .astc8x8: return .astc_8x8_srgb
        case .bc1: return .bc1_rgba_srgb
        case .bc3: return .bc3_rgba_srgb
        case .bc7: return .bc7_rgbaUnorm_srgb
        }
    }
}

public enum CompressionQuality {
    case fast
    case normal
    case best
}

public enum ExportFormat {
    case png
    case jpeg(quality: Float)
}

public final class TextureLoader {

    private let device: MTLDevice
    private let loader: MTKTextureLoader
    private let commandQueue: MTLCommandQueue

    public init(device: MTLDevice) {
        self.device = device
        self.loader = MTKTextureLoader(device: device)
        self.commandQueue = device.makeCommandQueue()!
    }

    public func loadTexture(from url: URL, options: TextureLoadOptions = .init()) throws -> MTLTexture {
        let opts = makeLoaderOptions(options)
        do {
            return try loader.newTexture(URL: url, options: opts)
        } catch {
            throw TextureError.loadFailed(url, error)
        }
    }

    public func loadTexture(named name: String, bundle: Bundle = .main, options: TextureLoadOptions = .init()) throws -> MTLTexture {
        let opts = makeLoaderOptions(options)
        do {
            return try loader.newTexture(name: name, scaleFactor: 1.0, bundle: bundle, options: opts)
        } catch {
            throw TextureError.loadFromBundleFailed(name, error)
        }
    }

    public func createTexture(width: Int, height: Int, format: MTLPixelFormat = .bgra8Unorm, usage: MTLTextureUsage = [.shaderRead]) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)
    }

    /// Copies mip levels between textures of the same pixel format via blit encoder.
    /// For actual format conversion (e.g. RGBA8 -> ASTC), use `TextureCompressor`.
    public func blitCopy(source: MTLTexture, destination: MTLTexture) throws {
        guard source.pixelFormat == destination.pixelFormat else {
            throw TextureError.compressionRequiresFormatConversion
        }

        guard let buffer = commandQueue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else {
            throw TextureError.textureCreationFailed
        }

        let mipLevels = min(source.mipmapLevelCount, destination.mipmapLevelCount)
        for level in 0..<mipLevels {
            let w = max(1, source.width >> level)
            let h = max(1, source.height >> level)
            blit.copy(
                from: source,
                sourceSlice: 0,
                sourceLevel: level,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: w, height: h, depth: 1),
                to: destination,
                destinationSlice: 0,
                destinationLevel: level,
                destinationOrigin: .init(x: 0, y: 0, z: 0)
            )
        }
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        if let error = buffer.error {
            throw TextureError.exportFailed(error)
        }
    }

    /// Optimizes a texture for GPU access (driver-level compression/tiling).
    public func optimizeForGPU(texture: MTLTexture) throws {
        guard let buffer = commandQueue.makeCommandBuffer(),
              let blit = buffer.makeBlitCommandEncoder() else {
            throw TextureError.textureCreationFailed
        }
        blit.optimizeContentsForGPUAccess(texture: texture)
        blit.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
    }

    public func exportTexture(_ texture: MTLTexture, to url: URL, format: ExportFormat = .png) throws {
        let cgImage: CGImage
        if let ciImage = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) {
            let context = CIContext()
            guard let img = context.createCGImage(ciImage, from: ciImage.extent) else {
                throw TextureError.exportFailed(NSError(domain: "TextureLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from texture"]))
            }
            cgImage = img
        } else {
            let width = texture.width
            let height = texture.height
            let rowBytes = width * 4
            let length = rowBytes * height

            var data = Data(count: length)
            guard texture.storageMode != .private else {
                throw TextureError.exportFailed(NSError(domain: "TextureLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot read from private storage texture"]))
            }

            data.withUnsafeMutableBytes { ptr in
                texture.getBytes(
                    ptr.baseAddress!,
                    bytesPerRow: rowBytes,
                    from: MTLRegion(origin: .init(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1)),
                    mipmapLevel: 0
                )
            }

            guard let provider = CGDataProvider(data: data as CFData),
                  let img = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: rowBytes,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                  ) else {
                throw TextureError.exportFailed(NSError(domain: "TextureLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage from pixel data"]))
            }
            cgImage = img
        }

        let utType: String
        let options: CFDictionary
        switch format {
        case .png:
            utType = UTType.png.identifier
            options = [:] as CFDictionary
        case .jpeg(let quality):
            utType = UTType.jpeg.identifier
            options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, utType as CFString, 1, nil) else {
            throw TextureError.unsupportedExportFormat(utType)
        }
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            throw TextureError.exportFailed(NSError(domain: "TextureLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed"]))
        }
    }

    private func makeLoaderOptions(_ opts: TextureLoadOptions) -> [MTKTextureLoader.Option: Any] {
        let storage: MTLStorageMode
        if opts.storageMode.contains(.storageModePrivate) {
            storage = .private
        } else if opts.storageMode.contains(.storageModeShared) {
            storage = .shared
        } else {
            #if os(macOS)
            storage = opts.storageMode.contains(.storageModeManaged) ? .managed : .shared
            #else
            storage = .shared
            #endif
        }
        return [
            .SRGB: opts.sRGB,
            .generateMipmaps: opts.generateMipmaps,
            .textureUsage: NSNumber(value: opts.textureUsage.rawValue),
            .textureStorageMode: NSNumber(value: storage.rawValue),
        ]
    }
}
