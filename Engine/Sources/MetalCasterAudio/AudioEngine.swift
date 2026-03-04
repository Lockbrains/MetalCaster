import Foundation
import AVFoundation
import MetalCasterCore

// MARK: - Audio Source Component

public struct AudioSourceComponent: Component {
    public var audioFile: String
    public var volume: Float
    public var pitch: Float
    public var isLooping: Bool
    public var is3D: Bool
    public var maxDistance: Float
    public var referenceDistance: Float
    public var isPlaying: Bool
    public var bus: AudioBusType

    /// Internal tracking: the engine-assigned player ID for this source.
    public var _playerID: String?

    public init(
        audioFile: String = "",
        volume: Float = 1.0,
        pitch: Float = 1.0,
        isLooping: Bool = false,
        is3D: Bool = true,
        maxDistance: Float = 50.0,
        referenceDistance: Float = 1.0,
        isPlaying: Bool = false,
        bus: AudioBusType = .sfx
    ) {
        self.audioFile = audioFile
        self.volume = volume
        self.pitch = pitch
        self.isLooping = isLooping
        self.is3D = is3D
        self.maxDistance = maxDistance
        self.referenceDistance = referenceDistance
        self.isPlaying = isPlaying
        self.bus = bus
    }
}

// MARK: - Audio Listener Component

public struct AudioListenerComponent: Component {
    public var isActive: Bool

    public init(isActive: Bool = true) {
        self.isActive = isActive
    }
}

// MARK: - Audio Bus Type

public enum AudioBusType: String, Codable, Sendable, CaseIterable {
    case master
    case music
    case sfx
    case voice
    case ambient
}

// MARK: - Audio Events

public struct AudioPlayEvent: MCEvent {
    public let name: String
    public let bus: AudioBusType
    public let loop: Bool
    public init(name: String, bus: AudioBusType = .sfx, loop: Bool = false) {
        self.name = name; self.bus = bus; self.loop = loop
    }
}

public struct AudioStopEvent: MCEvent {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct AudioStopAllEvent: MCEvent {
    public init() {}
}

// MARK: - MCAudioEngine

/// Full-featured audio engine with 3D spatialization via AVAudioEnvironmentNode.
public final class MCAudioEngine {

    private let engine = AVAudioEngine()
    private let environmentNode = AVAudioEnvironmentNode()

    private var players: [String: AVAudioPlayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    /// Per-bus mixer nodes for independent volume control.
    private var busMixers: [AudioBusType: AVAudioMixerNode] = [:]
    private var busVolumes: [AudioBusType: Float] = [:]

    public var masterVolume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = masterVolume }
    }

    public init() {
        setupBusMixers()
    }

    // MARK: - Setup

    private func setupBusMixers() {
        engine.attach(environmentNode)

        for busType in AudioBusType.allCases {
            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            busMixers[busType] = mixer
            busVolumes[busType] = 1.0

            if busType == .master {
                engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            } else {
                engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            }
        }

        engine.connect(environmentNode, to: engine.mainMixerNode, format: nil)

        let distParams = environmentNode.distanceAttenuationParameters
        distParams.distanceAttenuationModel = .inverse
        distParams.referenceDistance = 1.0
        distParams.maximumDistance = 100.0
        distParams.rolloffFactor = 1.0
    }

    // MARK: - Lifecycle

    public func start() throws {
        try engine.start()
        MCLog.info(.audio, "Audio engine started")
    }

    public func stop() {
        stopAll()
        engine.stop()
        MCLog.info(.audio, "Audio engine stopped")
    }

    // MARK: - Bus Volume

    public func setVolume(_ volume: Float, forBus bus: AudioBusType) {
        busVolumes[bus] = volume
        busMixers[bus]?.outputVolume = volume
    }

    public func volume(forBus bus: AudioBusType) -> Float {
        busVolumes[bus] ?? 1.0
    }

    // MARK: - Resource Loading

    public func loadAudio(name: String, url: URL) throws {
        guard buffers[name] == nil else { return }
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            MCLog.error(.audio, "Failed to create buffer for \(name)")
            return
        }
        try file.read(into: buffer)
        buffers[name] = buffer
        MCLog.debug(.audio, "Loaded audio: \(name)")
    }

    public func unloadAudio(name: String) {
        stop(name: name)
        buffers.removeValue(forKey: name)
    }

    public func isLoaded(_ name: String) -> Bool {
        buffers[name] != nil
    }

    // MARK: - 2D Playback

    public func play(name: String, bus: AudioBusType = .sfx, loop: Bool = false, volume: Float = 1.0, pitch: Float = 1.0) {
        guard let buffer = buffers[name] else {
            MCLog.warning(.audio, "Audio not loaded: \(name)")
            return
        }

        stop(name: name)

        if !engine.isRunning {
            MCLog.warning(.audio, "AVAudioEngine not running, attempting restart")
            try? engine.start()
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)

        if let mixer = busMixers[bus] {
            engine.connect(player, to: mixer, format: buffer.format)
        } else {
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        }

        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: loop ? .loops : [])
        player.play()
        players[name] = player
        MCLog.info(.audio, "Playing '\(name)' on bus \(bus.rawValue), volume=\(volume), loop=\(loop)")
    }

    // MARK: - 3D Spatialized Playback

    public func play3D(name: String, position: AVAudio3DPoint, bus: AudioBusType = .sfx,
                       loop: Bool = false, volume: Float = 1.0, pitch: Float = 1.0) {
        guard let buffer = buffers[name] else {
            MCLog.warning(.audio, "Audio not loaded: \(name)")
            return
        }

        stop(name: name)

        if !engine.isRunning {
            MCLog.warning(.audio, "AVAudioEngine not running, attempting restart")
            try? engine.start()
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: environmentNode, format: buffer.format)

        player.volume = volume * (busVolumes[bus] ?? 1.0)
        player.position = position
        player.scheduleBuffer(buffer, at: nil, options: loop ? .loops : [])
        player.play()
        players[name] = player
        MCLog.info(.audio, "Playing 3D '\(name)' at (\(position.x),\(position.y),\(position.z))")
    }

    /// Updates the 3D position of an active spatialized player.
    public func updatePosition(name: String, position: AVAudio3DPoint) {
        players[name]?.position = position
    }

    /// Updates the listener orientation for 3D audio spatialization.
    public func updateListener(position: AVAudio3DPoint, forward: AVAudio3DVector, up: AVAudio3DVector) {
        environmentNode.listenerPosition = position
        environmentNode.listenerAngularOrientation = AVAudioEnvironmentNode.angularOrientation(
            forward: forward, up: up
        )
    }

    // MARK: - Playback Control

    public func stop(name: String) {
        guard let player = players[name] else { return }
        player.stop()
        engine.detach(player)
        players.removeValue(forKey: name)
    }

    public func pause(name: String) {
        players[name]?.pause()
    }

    public func resume(name: String) {
        players[name]?.play()
    }

    public func isPlayerActive(_ name: String) -> Bool {
        players[name]?.isPlaying ?? false
    }

    public func stopAll() {
        for (name, player) in players {
            player.stop()
            engine.detach(player)
            players.removeValue(forKey: name)
        }
    }

    /// Number of currently active audio players.
    public var activePlayerCount: Int { players.count }

    /// Names of all loaded audio buffers.
    public var loadedAudioNames: [String] { Array(buffers.keys) }
}

// MARK: - AVAudioEnvironmentNode Helper

private extension AVAudioEnvironmentNode {
    static func angularOrientation(forward: AVAudio3DVector, up: AVAudio3DVector) -> AVAudio3DAngularOrientation {
        let yaw = atan2(forward.x, forward.z) * (180.0 / .pi)
        let pitch = asin(-forward.y) * (180.0 / .pi)
        let roll: Float = 0
        return AVAudio3DAngularOrientation(yaw: yaw, pitch: pitch, roll: roll)
    }
}
