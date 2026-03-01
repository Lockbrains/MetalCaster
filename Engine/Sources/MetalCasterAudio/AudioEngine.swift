import Foundation
import AVFoundation
import MetalCasterCore

/// Audio source component for entities.
public struct AudioSourceComponent: Component {
    public var audioFile: String
    public var volume: Float
    public var pitch: Float
    public var isLooping: Bool
    public var is3D: Bool
    public var maxDistance: Float
    public var isPlaying: Bool
    
    public init(
        audioFile: String = "",
        volume: Float = 1.0,
        pitch: Float = 1.0,
        isLooping: Bool = false,
        is3D: Bool = true,
        maxDistance: Float = 50.0,
        isPlaying: Bool = false
    ) {
        self.audioFile = audioFile
        self.volume = volume
        self.pitch = pitch
        self.isLooping = isLooping
        self.is3D = is3D
        self.maxDistance = maxDistance
        self.isPlaying = isPlaying
    }
}

/// Audio engine wrapping AVAudioEngine for 3D spatial audio.
public final class MCAudioEngine {
    
    private let engine = AVAudioEngine()
    private var players: [String: AVAudioPlayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    
    public var masterVolume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = masterVolume }
    }
    
    public init() {}
    
    /// Starts the audio engine.
    public func start() throws {
        try engine.start()
    }
    
    /// Stops the audio engine.
    public func stop() {
        engine.stop()
    }
    
    /// Loads an audio file into memory for playback.
    public func loadAudio(name: String, url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else { return }
        try file.read(into: buffer)
        buffers[name] = buffer
    }
    
    /// Plays a loaded audio buffer.
    public func play(name: String, loop: Bool = false) {
        guard let buffer = buffers[name] else { return }
        
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        
        player.scheduleBuffer(buffer, at: nil, options: loop ? .loops : [])
        player.play()
        players[name] = player
    }
    
    /// Stops playback of a specific audio.
    public func stop(name: String) {
        guard let player = players[name] else { return }
        player.stop()
        engine.detach(player)
        players.removeValue(forKey: name)
    }
    
    /// Stops all audio playback.
    public func stopAll() {
        for (name, player) in players {
            player.stop()
            engine.detach(player)
            players.removeValue(forKey: name)
        }
    }
}
