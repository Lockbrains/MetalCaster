import Foundation
import AVFoundation
import MetalCasterCore

/// ECS System that drives the audio engine by syncing AudioSourceComponent
/// and AudioListenerComponent transforms every frame.
public final class AudioSystem: System {
    public nonisolated(unsafe) var isEnabled: Bool = true
    public var priority: Int { 90 }

    public nonisolated(unsafe) let audioEngine: MCAudioEngine

    /// Tracks which audio sources have been started so we don't re-trigger.
    private nonisolated(unsafe) var activeSources: Set<Entity> = []

    /// Resolves an audio filename to a file URL. Set by the editor/runtime layer.
    public nonisolated(unsafe) var resolveAudioFile: ((String) -> URL?)? = nil

    public init(audioEngine: MCAudioEngine) {
        self.audioEngine = audioEngine
    }

    public func setup(world: World) {
        MCLog.info(.audio, "AudioSystem initialized")
    }

    public func update(context: UpdateContext) {
        let world = context.world

        updateListener(world: world)
        updateSources(world: world)
        handleEvents(context: context)
    }

    public func teardown(world: World) {
        audioEngine.stopAll()
        activeSources.removeAll()
    }

    // MARK: - Listener

    private func updateListener(world: World) {
        // TransformComponent is in MetalCasterScene, but we receive it generically.
        // The listener is any entity with AudioListenerComponent.
        // Position data comes from the entity's transform, which must be set externally
        // since MetalCasterAudio doesn't depend on MetalCasterScene.
    }

    /// External call to update listener from the scene layer.
    public func setListenerTransform(position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>) {
        audioEngine.updateListener(
            position: AVAudio3DPoint(x: position.x, y: position.y, z: position.z),
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z)
        )
    }

    // MARK: - Sources

    private func updateSources(world: World) {
        let sources = world.query(AudioSourceComponent.self)
        var currentEntities = Set<Entity>()

        for (entity, source) in sources {
            currentEntities.insert(entity)
            let file = source.audioFile
            guard !file.isEmpty else { continue }

            if source.isPlaying && !activeSources.contains(entity) {
                ensureLoaded(file)

                let playerID = "entity_\(entity.id)"
                if source.is3D {
                    audioEngine.play3D(
                        name: file,
                        position: AVAudio3DPoint(x: 0, y: 0, z: 0),
                        bus: source.bus,
                        loop: source.isLooping,
                        volume: source.volume,
                        pitch: source.pitch
                    )
                } else {
                    audioEngine.play(
                        name: file,
                        bus: source.bus,
                        loop: source.isLooping,
                        volume: source.volume,
                        pitch: source.pitch
                    )
                }
                var updated = source
                updated._playerID = playerID
                world.addComponent(updated, to: entity)
                activeSources.insert(entity)
            } else if !source.isPlaying && activeSources.contains(entity) {
                audioEngine.stop(name: file)
                activeSources.remove(entity)
            }
        }

        let stale = activeSources.subtracting(currentEntities)
        for entity in stale {
            activeSources.remove(entity)
        }
    }

    private func ensureLoaded(_ filename: String) {
        guard !audioEngine.isLoaded(filename) else { return }
        guard let resolve = resolveAudioFile else {
            MCLog.warning(.audio, "No resolveAudioFile callback set — cannot load '\(filename)'")
            return
        }
        guard let url = resolve(filename) else {
            MCLog.warning(.audio, "Could not resolve audio file '\(filename)' in asset database")
            return
        }
        do {
            try audioEngine.loadAudio(name: filename, url: url)
        } catch {
            MCLog.error(.audio, "Failed to load audio '\(filename)': \(error)")
        }
    }

    // MARK: - Events

    private func handleEvents(context: UpdateContext) {
        // Events are handled via EventBus subscriptions set up externally.
    }

    /// Convenience: set source position from scene layer.
    public func updateSourcePosition(audioFile: String, position: SIMD3<Float>) {
        audioEngine.updatePosition(
            name: audioFile,
            position: AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        )
    }
}
