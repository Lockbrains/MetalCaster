import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

/// Generates and caches thumbnail images for project assets.
/// Thumbnails are stored in Library/Thumbnails/ as small PNG files.
public final class AssetThumbnailGenerator: @unchecked Sendable {

    private let projectManager: ProjectManager
    private var memoryCache: [UUID: CGImage] = [:]

    public static let thumbnailSize: Int = 64

    public init(projectManager: ProjectManager) {
        self.projectManager = projectManager
    }

    // MARK: - Public API

    /// Returns a cached thumbnail or generates one on demand.
    public func thumbnail(for guid: UUID, category: AssetCategory) -> CGImage? {
        if let cached = memoryCache[guid] {
            return cached
        }

        if let diskCached = loadFromDisk(guid: guid) {
            memoryCache[guid] = diskCached
            return diskCached
        }

        guard let fileURL = projectManager.resolveGUID(guid) else { return nil }
        let image = generateThumbnail(for: fileURL, category: category)
        if let image = image {
            memoryCache[guid] = image
            saveToDisk(image: image, guid: guid)
        }
        return image
    }

    /// Generates a thumbnail asynchronously and calls back on the main queue.
    public func thumbnailAsync(for guid: UUID, category: AssetCategory, completion: @escaping (CGImage?) -> Void) {
        if let cached = memoryCache[guid] {
            completion(cached)
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = self?.thumbnail(for: guid, category: category)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Invalidates the thumbnail for a specific asset.
    public func invalidate(guid: UUID) {
        memoryCache.removeValue(forKey: guid)
        if let thumbnailURL = thumbnailURL(for: guid) {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    /// Clears all cached thumbnails from memory.
    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    // MARK: - Generation

    private func generateThumbnail(for fileURL: URL, category: AssetCategory) -> CGImage? {
        switch category {
        case .textures:
            return generateImageThumbnail(at: fileURL)
        case .meshes:
            return generatePlaceholderIcon(systemName: "cube.fill")
        case .scenes:
            return generatePlaceholderIcon(systemName: "film.fill")
        case .materials:
            return generatePlaceholderIcon(systemName: "paintpalette.fill")
        case .shaders:
            return generatePlaceholderIcon(systemName: "function")
        case .audio:
            return generatePlaceholderIcon(systemName: "waveform")
        case .prefabs:
            return generatePlaceholderIcon(systemName: "square.on.square.fill")
        }
    }

    private func generateImageThumbnail(at url: URL) -> CGImage? {
        #if canImport(CoreGraphics)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        #else
        return nil
        #endif
    }

    private func generatePlaceholderIcon(systemName: String) -> CGImage? {
        #if canImport(AppKit)
        let size = CGFloat(Self.thumbnailSize)
        guard let nsImage = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return nil
        }

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep = rep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .light)
        let configured = nsImage.withSymbolConfiguration(symbolConfig) ?? nsImage
        let imageSize = configured.size
        let drawRect = NSRect(
            x: (size - imageSize.width) / 2,
            y: (size - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )

        NSColor.white.withAlphaComponent(0.6).setFill()
        configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 0.6)

        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
        #else
        return nil
        #endif
    }

    // MARK: - Disk Cache

    private func thumbnailURL(for guid: UUID) -> URL? {
        guard let library = projectManager.libraryDirectory() else { return nil }
        return library
            .appendingPathComponent("Thumbnails")
            .appendingPathComponent("\(guid.uuidString).png")
    }

    private func loadFromDisk(guid: UUID) -> CGImage? {
        #if canImport(CoreGraphics)
        guard let url = thumbnailURL(for: guid),
              FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
        #else
        return nil
        #endif
    }

    private func saveToDisk(image: CGImage, guid: UUID) {
        #if canImport(CoreGraphics)
        guard let url = thumbnailURL(for: guid) else { return }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        #endif
    }
}
