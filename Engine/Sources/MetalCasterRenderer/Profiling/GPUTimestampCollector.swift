import Metal
import MetalCasterCore

/// Collects per-pass GPU timestamps using `MTLCounterSampleBuffer` when available.
/// Falls back to CPU-side estimation on unsupported devices.
public final class GPUTimestampCollector {

    private let device: MTLDevice
    private let supportsTimestamps: Bool
    private var counterSampleBuffer: MTLCounterSampleBuffer?
    private var sampleIndex: Int = 0
    private let maxSamples = 64

    public init(device: MTLDevice) {
        self.device = device
        self.supportsTimestamps = device.supportsCounterSampling(.atStageBoundary)
        if supportsTimestamps {
            setupCounterBuffer()
        }
    }

    private func setupCounterBuffer() {
        guard let counterSets = device.counterSets else { return }
        var timestampSet: MTLCounterSet?
        for set in counterSets {
            if set.name == MTLCommonCounterSet.timestamp.rawValue {
                timestampSet = set
                break
            }
        }
        guard let set = timestampSet else { return }

        let desc = MTLCounterSampleBufferDescriptor()
        desc.counterSet = set
        desc.storageMode = .shared
        desc.sampleCount = maxSamples
        desc.label = "MCProfiler GPU Timestamps"

        counterSampleBuffer = try? device.makeCounterSampleBuffer(descriptor: desc)
    }

    // MARK: - Per-Pass Timing

    /// Resets the sample index at the beginning of a frame.
    public func beginFrame() {
        sampleIndex = 0
    }

    /// Returns the current sample index pair (begin, end) for a pass and advances.
    /// Returns nil if out of sample slots.
    public func allocateTimestampSlots() -> (begin: Int, end: Int)? {
        guard supportsTimestamps, counterSampleBuffer != nil else { return nil }
        let begin = sampleIndex
        let end = sampleIndex + 1
        guard end < maxSamples else { return nil }
        sampleIndex = end + 1
        return (begin, end)
    }

    /// Resolves all recorded timestamps into pass timings (in milliseconds).
    /// Call after the command buffer has completed.
    public func resolveTimings(passNames: [(String, Int, Int)]) -> [ProfilePassTiming] {
        guard let buffer = counterSampleBuffer else { return [] }

        let data: Data
        do {
            guard let resolved = try buffer.resolveCounterRange(0..<sampleIndex) else { return [] }
            data = resolved
        } catch {
            return []
        }

        return data.withUnsafeBytes { rawPtr -> [ProfilePassTiming] in
            let bound = rawPtr.bindMemory(to: MTLCounterResultTimestamp.self)
            return passNames.compactMap { (name, beginIdx, endIdx) in
                guard beginIdx < bound.count, endIdx < bound.count else { return nil }
                let beginTs = bound[beginIdx].timestamp
                let endTs = bound[endIdx].timestamp
                guard endTs > beginTs else { return nil }
                let gpuMs = Double(endTs - beginTs) / 1_000_000.0
                return ProfilePassTiming(name: name, cpuTimeMs: 0, gpuTimeMs: gpuMs)
            }
        }
    }

    public var isHardwareSupported: Bool { supportsTimestamps }
}
