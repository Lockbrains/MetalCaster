import Foundation

// MARK: - Profile Data Types

public struct ProfilePassTiming: Sendable {
    public let name: String
    public let cpuTimeMs: Double
    public let gpuTimeMs: Double?

    public init(name: String, cpuTimeMs: Double, gpuTimeMs: Double? = nil) {
        self.name = name
        self.cpuTimeMs = cpuTimeMs
        self.gpuTimeMs = gpuTimeMs
    }
}

public struct ProfileSystemTiming: Sendable {
    public let name: String
    public let timeMs: Double

    public init(name: String, timeMs: Double) {
        self.name = name
        self.timeMs = timeMs
    }
}

/// Snapshot of a single frame's profiling data.
public struct ProfileFrameData: Sendable {
    public let frameNumber: UInt64
    public let totalCpuTimeMs: Double
    public let totalGpuTimeMs: Double?
    public let deltaTimeMs: Double
    public let fps: Double

    public let systemTimings: [ProfileSystemTiming]
    public let passTimings: [ProfilePassTiming]

    public let drawCallCount: Int
    public let triangleCount: Int
    public let stateChangeCount: Int

    public let allocatedGPUMemoryBytes: UInt64

    public init(
        frameNumber: UInt64,
        totalCpuTimeMs: Double,
        totalGpuTimeMs: Double?,
        deltaTimeMs: Double,
        systemTimings: [ProfileSystemTiming],
        passTimings: [ProfilePassTiming],
        drawCallCount: Int,
        triangleCount: Int,
        stateChangeCount: Int,
        allocatedGPUMemoryBytes: UInt64
    ) {
        self.frameNumber = frameNumber
        self.totalCpuTimeMs = totalCpuTimeMs
        self.totalGpuTimeMs = totalGpuTimeMs
        self.deltaTimeMs = deltaTimeMs
        self.fps = deltaTimeMs > 0 ? 1000.0 / deltaTimeMs : 0
        self.systemTimings = systemTimings
        self.passTimings = passTimings
        self.drawCallCount = drawCallCount
        self.triangleCount = triangleCount
        self.stateChangeCount = stateChangeCount
        self.allocatedGPUMemoryBytes = allocatedGPUMemoryBytes
    }
}

/// Event broadcast via EventBus at the end of each profiled frame.
public struct ProfileFrameEvent: MCEvent {
    public let data: ProfileFrameData
}

// MARK: - MCProfiler

/// Engine-wide profiling singleton. Collects CPU system timings, GPU pass timings,
/// draw call statistics, and memory usage. Disabled by default — set `isEnabled = true`.
public final class MCProfiler: @unchecked Sendable {

    public static let shared = MCProfiler()

    public var isEnabled: Bool = false
    public weak var eventBus: EventBus?

    private let lock = NSLock()

    /// Ring buffer of recent frame data.
    private var frameHistory: [ProfileFrameData] = []
    private let maxHistorySize = 300

    // Per-frame accumulators (written by instrumented code, read at frame end)
    private var currentSystemTimings: [ProfileSystemTiming] = []
    private var currentPassTimings: [ProfilePassTiming] = []
    private var currentDrawCalls: Int = 0
    private var currentTriangles: Int = 0
    private var currentStateChanges: Int = 0

    private var frameStartTime: Double = 0
    private var currentFrameNumber: UInt64 = 0
    private var allocatedGPUMemory: UInt64 = 0

    private init() {
        frameHistory.reserveCapacity(maxHistorySize)
    }

    // MARK: - Frame Lifecycle

    /// Call at the start of each frame (before system updates).
    public func beginFrame(frameNumber: UInt64) {
        guard isEnabled else { return }
        lock.lock()
        currentFrameNumber = frameNumber
        frameStartTime = CFAbsoluteTimeGetCurrent()
        currentSystemTimings.removeAll(keepingCapacity: true)
        currentPassTimings.removeAll(keepingCapacity: true)
        currentDrawCalls = 0
        currentTriangles = 0
        currentStateChanges = 0
        lock.unlock()
    }

    /// Call at the end of each frame (after presenting).
    public func endFrame(deltaTime: Float) {
        guard isEnabled else { return }
        let cpuEnd = CFAbsoluteTimeGetCurrent()

        lock.lock()
        let cpuMs = (cpuEnd - frameStartTime) * 1000.0
        let totalGpu = currentPassTimings.compactMap(\.gpuTimeMs).reduce(0, +)

        let data = ProfileFrameData(
            frameNumber: currentFrameNumber,
            totalCpuTimeMs: cpuMs,
            totalGpuTimeMs: totalGpu > 0 ? totalGpu : nil,
            deltaTimeMs: Double(deltaTime) * 1000.0,
            systemTimings: currentSystemTimings,
            passTimings: currentPassTimings,
            drawCallCount: currentDrawCalls,
            triangleCount: currentTriangles,
            stateChangeCount: currentStateChanges,
            allocatedGPUMemoryBytes: allocatedGPUMemory
        )

        if frameHistory.count >= maxHistorySize {
            frameHistory.removeFirst(maxHistorySize / 4)
        }
        frameHistory.append(data)
        lock.unlock()

        eventBus?.publish(ProfileFrameEvent(data: data))
    }

    // MARK: - Recording API

    /// Records a system update timing. Call from the engine tick loop.
    public func recordSystem(name: String, timeMs: Double) {
        guard isEnabled else { return }
        lock.lock()
        currentSystemTimings.append(ProfileSystemTiming(name: name, timeMs: timeMs))
        lock.unlock()
    }

    /// Records a render/compute pass timing.
    public func recordPass(name: String, cpuTimeMs: Double, gpuTimeMs: Double? = nil) {
        guard isEnabled else { return }
        lock.lock()
        currentPassTimings.append(ProfilePassTiming(name: name, cpuTimeMs: cpuTimeMs, gpuTimeMs: gpuTimeMs))
        lock.unlock()
    }

    /// Increments the draw call counter. Call from mesh rendering code.
    public func recordDrawCall(triangles: Int = 0) {
        guard isEnabled else { return }
        lock.lock()
        currentDrawCalls += 1
        currentTriangles += triangles
        lock.unlock()
    }

    /// Increments the pipeline state change counter.
    public func recordStateChange() {
        guard isEnabled else { return }
        lock.lock()
        currentStateChanges += 1
        lock.unlock()
    }

    /// Updates the GPU memory allocation value (call once per frame).
    public func updateGPUMemory(bytes: UInt64) {
        guard isEnabled else { return }
        lock.lock()
        allocatedGPUMemory = bytes
        lock.unlock()
    }

    // MARK: - Read API

    /// Returns the most recent N frames of profiling data.
    public func recentFrames(count: Int = 120) -> [ProfileFrameData] {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, frameHistory.count - count)
        return Array(frameHistory[start...])
    }

    /// Returns the latest single-frame snapshot.
    public var latestFrame: ProfileFrameData? {
        lock.lock()
        defer { lock.unlock() }
        return frameHistory.last
    }

    /// Clears all recorded frame data.
    public func clearHistory() {
        lock.lock()
        frameHistory.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
