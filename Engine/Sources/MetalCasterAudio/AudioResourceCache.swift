import Foundation
import MetalCasterCore

/// LRU cache for audio resources. Manages loading, eviction, and memory budgets.
public final class AudioResourceCache {

    private let audioEngine: MCAudioEngine
    private var accessOrder: [String] = []
    private var loadedSet: Set<String> = []
    private let lock = NSLock()

    /// Maximum number of cached audio buffers before eviction.
    public var maxCachedItems: Int = 128

    public init(audioEngine: MCAudioEngine) {
        self.audioEngine = audioEngine
    }

    /// Loads an audio file, evicting least-recently-used entries if over budget.
    public func load(name: String, url: URL) {
        lock.lock()
        defer { lock.unlock() }

        if loadedSet.contains(name) {
            touchUnlocked(name)
            return
        }

        do {
            try audioEngine.loadAudio(name: name, url: url)
            loadedSet.insert(name)
            accessOrder.append(name)
            evictIfNeeded()
        } catch {
            MCLog.error(.audio, "Failed to load audio '\(name)': \(error.localizedDescription)")
        }
    }

    /// Marks a resource as recently used.
    public func touch(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        touchUnlocked(name)
    }

    /// Unloads a specific audio resource.
    public func unload(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        audioEngine.unloadAudio(name: name)
        loadedSet.remove(name)
        accessOrder.removeAll { $0 == name }
    }

    /// Unloads all cached resources.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        for name in loadedSet {
            audioEngine.unloadAudio(name: name)
        }
        loadedSet.removeAll()
        accessOrder.removeAll()
    }

    public var cachedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadedSet.count
    }

    // MARK: - Internal

    private func touchUnlocked(_ name: String) {
        accessOrder.removeAll { $0 == name }
        accessOrder.append(name)
    }

    private func evictIfNeeded() {
        while accessOrder.count > maxCachedItems, let oldest = accessOrder.first {
            audioEngine.unloadAudio(name: oldest)
            loadedSet.remove(oldest)
            accessOrder.removeFirst()
            MCLog.debug(.audio, "Evicted audio: \(oldest)")
        }
    }
}
