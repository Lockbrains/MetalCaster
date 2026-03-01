import Foundation
import simd
import MetalCasterCore
import MetalCasterScene

/// Manages entity selection and transform gizmo operations.
public final class SelectionManager {

    public enum GizmoMode: String, CaseIterable, Sendable {
        case translate
        case rotate
        case scale
    }

    public enum GizmoAxis: Sendable {
        case none
        case x, y, z
        case xy, xz, yz
    }

    public var gizmoMode: GizmoMode = .translate
    public var activeAxis: GizmoAxis = .none
    public var isDragging: Bool = false

    private var dragStartPosition: SIMD3<Float> = .zero
    private var dragStartTransform: MCTransform = .identity

    public init() {}

    /// Begins a gizmo drag operation on the selected entity.
    public func beginDrag(entity: Entity, world: World, axis: GizmoAxis) {
        guard let tc = world.getComponent(TransformComponent.self, from: entity) else { return }
        isDragging = true
        activeAxis = axis
        dragStartTransform = tc.transform
        dragStartPosition = tc.transform.position
    }

    /// Updates the drag operation with a delta in screen space.
    public func updateDrag(entity: Entity, world: World, delta: SIMD3<Float>) {
        guard isDragging, var tc = world.getComponent(TransformComponent.self, from: entity) else { return }

        switch gizmoMode {
        case .translate:
            let maskedDelta = maskDelta(delta, axis: activeAxis)
            tc.transform.position = dragStartPosition + maskedDelta
        case .scale:
            let maskedDelta = maskDelta(delta, axis: activeAxis)
            tc.transform.scale = dragStartTransform.scale + maskedDelta * 0.5
            tc.transform.scale = max(tc.transform.scale, SIMD3<Float>(0.01, 0.01, 0.01))
        case .rotate:
            let angle = delta.x * 0.02
            switch activeAxis {
            case .x:
                tc.transform.rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0)) * dragStartTransform.rotation
            case .y:
                tc.transform.rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)) * dragStartTransform.rotation
            case .z:
                tc.transform.rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1)) * dragStartTransform.rotation
            default:
                break
            }
        }

        world.addComponent(tc, to: entity)
    }

    /// Ends the current drag operation.
    public func endDrag() -> (oldTransform: MCTransform, newTransform: MCTransform)? {
        guard isDragging else { return nil }
        isDragging = false
        activeAxis = .none
        return (dragStartTransform, dragStartTransform)
    }

    private func maskDelta(_ delta: SIMD3<Float>, axis: GizmoAxis) -> SIMD3<Float> {
        switch axis {
        case .x:  return SIMD3<Float>(delta.x, 0, 0)
        case .y:  return SIMD3<Float>(0, delta.y, 0)
        case .z:  return SIMD3<Float>(0, 0, delta.z)
        case .xy: return SIMD3<Float>(delta.x, delta.y, 0)
        case .xz: return SIMD3<Float>(delta.x, 0, delta.z)
        case .yz: return SIMD3<Float>(0, delta.y, delta.z)
        case .none: return delta
        }
    }
}

private func max(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(Swift.max(a.x, b.x), Swift.max(a.y, b.y), Swift.max(a.z, b.z))
}
