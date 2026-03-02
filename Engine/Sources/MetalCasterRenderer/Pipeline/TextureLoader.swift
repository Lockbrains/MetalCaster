import Metal
import MetalKit
import Foundation

/// Loads textures from disk or from the engine's bundled resources.
///
/// Supports HDR (Radiance .hdr), EXR, PNG, JPEG, and other formats
/// that `MTKTextureLoader` can handle. HDRI textures are loaded as
/// 2D float textures suitable for equirectangular skybox sampling.
public final class TextureLoader {

    private let textureLoader: MTKTextureLoader

    public init(device: MTLDevice) {
        self.textureLoader = MTKTextureLoader(device: device)
    }

    /// Loads a texture from the engine's bundled resources (Bundle.module).
    ///
    /// - Parameters:
    ///   - name: The resource file name without extension (e.g. "default_skybox").
    ///   - ext: The file extension (e.g. "hdr", "exr", "png").
    ///   - sRGB: Whether to interpret as sRGB. Use `false` for HDR/linear data.
    public func loadBundledTexture(
        name: String,
        extension ext: String,
        sRGB: Bool = false
    ) -> MTLTexture? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            print("[TextureLoader] Bundled resource not found: \(name).\(ext)")
            return nil
        }
        return loadTexture(from: url, sRGB: sRGB)
    }

    /// Loads a texture from an arbitrary file URL.
    public func loadTexture(from url: URL, sRGB: Bool = false) -> MTLTexture? {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: sRGB,
            .generateMipmaps: true,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]

        do {
            return try textureLoader.newTexture(URL: url, options: options)
        } catch {
            print("[TextureLoader] Failed to load texture at \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Loads the engine's default skybox HDRI texture from Bundle.module.
    /// Searches for known default filenames with common HDR extensions.
    public func loadDefaultSkyboxHDRI() -> MTLTexture? {
        let names = ["default_skybox", "citrus_orchard_puresky_4k"]
        let extensions = ["exr", "hdr", "png", "jpg"]
        for name in names {
            for ext in extensions {
                if let tex = loadBundledTexture(name: name, extension: ext, sRGB: false) {
                    return tex
                }
            }
        }
        print("[TextureLoader] No default skybox HDRI resource found in bundle")
        return nil
    }
}
