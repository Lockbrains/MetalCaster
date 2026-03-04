import Metal
import MetalCasterCore

/// Represents a single draw call recorded during frame capture.
public struct CapturedDrawCall: Sendable {
    public let passName: String
    public let pipelineLabel: String?
    public let primitiveType: String
    public let vertexCount: Int
    public let indexCount: Int
    public let instanceCount: Int
    public let boundTextures: [String]

    public init(
        passName: String,
        pipelineLabel: String? = nil,
        primitiveType: String = "triangle",
        vertexCount: Int = 0,
        indexCount: Int = 0,
        instanceCount: Int = 1,
        boundTextures: [String] = []
    ) {
        self.passName = passName
        self.pipelineLabel = pipelineLabel
        self.primitiveType = primitiveType
        self.vertexCount = vertexCount
        self.indexCount = indexCount
        self.instanceCount = instanceCount
        self.boundTextures = boundTextures
    }

    public var estimatedTriangles: Int {
        let count = indexCount > 0 ? indexCount : vertexCount
        return (count / 3) * instanceCount
    }
}

/// A snapshot of an entire captured frame.
public struct FrameCaptureSnapshot: Sendable {
    public let frameNumber: UInt64
    public let timestamp: Date
    public let drawCalls: [CapturedDrawCall]
    public let totalTriangles: Int
    public let totalStateChanges: Int

    public init(
        frameNumber: UInt64,
        drawCalls: [CapturedDrawCall],
        totalStateChanges: Int = 0
    ) {
        self.frameNumber = frameNumber
        self.timestamp = Date()
        self.drawCalls = drawCalls
        self.totalTriangles = drawCalls.reduce(0) { $0 + $1.estimatedTriangles }
        self.totalStateChanges = totalStateChanges
    }
}

/// Records draw call data for a single frame when capture mode is active.
/// Not a singleton — create one per capture request.
public final class FrameCaptureRecorder {

    public private(set) var isCapturing = false
    private var drawCalls: [CapturedDrawCall] = []
    private var stateChanges = 0
    private var frameNumber: UInt64 = 0

    public init() {}

    public func beginCapture(frameNumber: UInt64) {
        self.frameNumber = frameNumber
        isCapturing = true
        drawCalls.removeAll(keepingCapacity: true)
        stateChanges = 0
    }

    public func recordDrawCall(_ call: CapturedDrawCall) {
        guard isCapturing else { return }
        drawCalls.append(call)
    }

    public func recordStateChange() {
        guard isCapturing else { return }
        stateChanges += 1
    }

    public func endCapture() -> FrameCaptureSnapshot {
        isCapturing = false
        return FrameCaptureSnapshot(
            frameNumber: frameNumber,
            drawCalls: drawCalls,
            totalStateChanges: stateChanges
        )
    }

    /// Triggers Xcode's Metal GPU Debugger capture.
    public static func triggerXcodeCapture(device: MTLDevice) {
        let manager = MTLCaptureManager.shared()
        guard manager.supportsDestination(.gpuTraceDocument) else {
            MCLog.warning(.renderer, "GPU trace capture not supported")
            return
        }

        let desc = MTLCaptureDescriptor()
        desc.captureObject = device
        desc.destination = .developerTools

        do {
            try manager.startCapture(with: desc)
            MCLog.info(.renderer, "Metal GPU capture started")
        } catch {
            MCLog.error(.renderer, "Failed to start GPU capture: \(error)")
        }
    }

    /// Stops the active Xcode GPU capture.
    public static func stopXcodeCapture() {
        let manager = MTLCaptureManager.shared()
        if manager.isCapturing {
            manager.stopCapture()
            MCLog.info(.renderer, "Metal GPU capture stopped")
        }
    }
}
