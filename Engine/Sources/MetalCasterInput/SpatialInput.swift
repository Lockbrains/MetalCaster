import Foundation
import simd

/// Spatial input data for visionOS hand tracking.
///
/// Provides abstracted hand joint data that can be consumed by
/// game systems. The actual hand tracking integration (ARKit/RealityKit)
/// happens in the platform-specific runtime layer.
public struct HandJointData: Sendable {
    public let position: SIMD3<Float>
    public let orientation: simd_quatf
    public let isTracked: Bool
    
    public init(position: SIMD3<Float> = .zero, orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), isTracked: Bool = false) {
        self.position = position
        self.orientation = orientation
        self.isTracked = isTracked
    }
}

/// Tracks spatial input for visionOS (hand tracking, eye gaze).
public final class SpatialInputManager: @unchecked Sendable {
    
    public enum Hand: Sendable {
        case left, right
    }
    
    public enum Joint: String, CaseIterable, Sendable {
        case wrist, thumbTip, indexTip, middleTip, ringTip, littleTip
    }
    
    private var jointData: [Hand: [Joint: HandJointData]] = [
        .left: [:],
        .right: [:]
    ]
    
    /// Eye gaze direction (if available).
    public var gazeDirection: SIMD3<Float>?
    
    /// Eye gaze origin (if available).
    public var gazeOrigin: SIMD3<Float>?
    
    public init() {}
    
    /// Updates joint data from the platform tracking system.
    public func updateJoint(_ joint: Joint, hand: Hand, data: HandJointData) {
        jointData[hand]?[joint] = data
    }
    
    /// Gets current joint data.
    public func getJoint(_ joint: Joint, hand: Hand) -> HandJointData {
        jointData[hand]?[joint] ?? HandJointData()
    }
    
    /// Returns true if a pinch gesture is detected (thumb tip close to index tip).
    public func isPinching(hand: Hand, threshold: Float = 0.02) -> Bool {
        let thumb = getJoint(.thumbTip, hand: hand)
        let index = getJoint(.indexTip, hand: hand)
        guard thumb.isTracked && index.isTracked else { return false }
        return simd_distance(thumb.position, index.position) < threshold
    }
    
    /// Resets all tracking data.
    public func reset() {
        jointData = [.left: [:], .right: [:]]
        gazeDirection = nil
        gazeOrigin = nil
    }
}
