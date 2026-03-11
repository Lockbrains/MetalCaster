import SwiftUI
import SceneKit

#if canImport(AppKit)
import AppKit

// MARK: - 3D Scene Preview (SCNView Wrapper)

/// Renders a 3D preview of USD/USDZ/OBJ files using SceneKit.
struct MCScenePreviewView: NSViewRepresentable {
    let url: URL?
    var allowsCameraControl: Bool = true

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = allowsCameraControl
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        context.coordinator.scnView = scnView
        if let url {
            context.coordinator.loadScene(from: url)
        }
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if context.coordinator.currentURL != url {
            if let url {
                context.coordinator.loadScene(from: url)
            } else {
                nsView.scene = nil
                context.coordinator.currentURL = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var scnView: SCNView?
        var currentURL: URL?

        func loadScene(from url: URL) {
            currentURL = url
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let scene = try? SCNScene(url: url) else { return }

                Self.setupLighting(in: scene)
                Self.frameCameraToFit(scene: scene)

                DispatchQueue.main.async {
                    self?.scnView?.scene = scene
                }
            }
        }

        private static func setupLighting(in scene: SCNScene) {
            let ambientNode = SCNNode()
            ambientNode.light = SCNLight()
            ambientNode.light!.type = .ambient
            ambientNode.light!.intensity = 300
            ambientNode.light!.color = NSColor(white: 0.6, alpha: 1)
            scene.rootNode.addChildNode(ambientNode)

            let keyNode = SCNNode()
            keyNode.light = SCNLight()
            keyNode.light!.type = .directional
            keyNode.light!.intensity = 800
            keyNode.light!.castsShadow = true
            keyNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
            scene.rootNode.addChildNode(keyNode)
        }

        private static func frameCameraToFit(scene: SCNScene) {
            let (minBound, maxBound) = scene.rootNode.boundingBox
            let center = SCNVector3(
                (minBound.x + maxBound.x) / 2,
                (minBound.y + maxBound.y) / 2,
                (minBound.z + maxBound.z) / 2
            )
            let size = SCNVector3(
                maxBound.x - minBound.x,
                maxBound.y - minBound.y,
                maxBound.z - minBound.z
            )
            let maxDim = max(size.x, max(size.y, size.z))
            let distance = maxDim * 2.0

            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.camera!.automaticallyAdjustsZRange = true
            cameraNode.position = SCNVector3(
                center.x + distance * 0.5,
                center.y + distance * 0.4,
                center.z + distance * 0.7
            )
            cameraNode.look(at: center)
            scene.rootNode.addChildNode(cameraNode)
        }
    }
}

// MARK: - Thumbnail Generator

/// Generates static thumbnails of 3D models using SCNRenderer for use in asset grids.
final class MeshThumbnailCache {
    static let shared = MeshThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var inFlightURLs = Set<URL>()
    private let lock = NSLock()

    func thumbnail(for url: URL, size: CGSize = CGSize(width: 128, height: 128), completion: @escaping (NSImage?) -> Void) {
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }

        lock.lock()
        guard !inFlightURLs.contains(url) else {
            lock.unlock()
            return
        }
        inFlightURLs.insert(url)
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer {
                self?.lock.lock()
                self?.inFlightURLs.remove(url)
                self?.lock.unlock()
            }

            guard let scene = try? SCNScene(url: url) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene
            renderer.autoenablesDefaultLighting = true

            MeshThumbnailCache.setupThumbnailCamera(in: scene)

            let nsImage = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)

            self?.cache.setObject(nsImage, forKey: url as NSURL)
            DispatchQueue.main.async { completion(nsImage) }
        }
    }

    private static func setupThumbnailCamera(in scene: SCNScene) {
        let (minBound, maxBound) = scene.rootNode.boundingBox
        let center = SCNVector3(
            (minBound.x + maxBound.x) / 2,
            (minBound.y + maxBound.y) / 2,
            (minBound.z + maxBound.z) / 2
        )
        let size = SCNVector3(
            maxBound.x - minBound.x,
            maxBound.y - minBound.y,
            maxBound.z - minBound.z
        )
        let maxDim = max(size.x, max(size.y, size.z))
        guard maxDim > 0 else { return }
        let distance = maxDim * 2.0

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera!.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(
            center.x + distance * 0.5,
            center.y + distance * 0.4,
            center.z + distance * 0.7
        )
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light!.type = .ambient
        ambientNode.light!.intensity = 400
        scene.rootNode.addChildNode(ambientNode)

        let keyNode = SCNNode()
        keyNode.light = SCNLight()
        keyNode.light!.type = .directional
        keyNode.light!.intensity = 800
        keyNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyNode)
    }

    func invalidate(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}

#endif
