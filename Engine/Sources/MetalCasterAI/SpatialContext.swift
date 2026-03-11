import Foundation
import simd
import MetalCasterCore

// MARK: - Spatial Coordinate Mode

public enum SpatialCoordinateMode: String, Codable, Sendable, CaseIterable {
    case screenSpace  = "Screen"
    case worldSpace   = "World"
    case objectSpace  = "Object"
}

// MARK: - Spatial Context

/// Provides the full spatial context needed for AI direction-to-transform mapping.
public struct SpatialContext: Sendable {
    public let cameraPosition: SIMD3<Float>
    public let cameraForward: SIMD3<Float>
    public let cameraRight: SIMD3<Float>
    public let cameraUp: SIMD3<Float>
    public let selectedEntityID: UInt64?
    public let selectedEntityPosition: SIMD3<Float>?
    public let selectedEntityBoundsSize: SIMD3<Float>?
    public let coordinateMode: SpatialCoordinateMode

    public init(
        cameraPosition: SIMD3<Float>,
        cameraForward: SIMD3<Float>,
        cameraRight: SIMD3<Float>,
        cameraUp: SIMD3<Float>,
        selectedEntityID: UInt64? = nil,
        selectedEntityPosition: SIMD3<Float>? = nil,
        selectedEntityBoundsSize: SIMD3<Float>? = nil,
        coordinateMode: SpatialCoordinateMode = .screenSpace
    ) {
        self.cameraPosition = cameraPosition
        self.cameraForward = cameraForward
        self.cameraRight = cameraRight
        self.cameraUp = cameraUp
        self.selectedEntityID = selectedEntityID
        self.selectedEntityPosition = selectedEntityPosition
        self.selectedEntityBoundsSize = selectedEntityBoundsSize
        self.coordinateMode = coordinateMode
    }
}

// MARK: - Spatial Direction Engine

/// Translates natural language directions and distances into world-space deltas.
public struct SpatialDirectionEngine: Sendable {

    public init() {}

    /// Resolves a semantic direction string to a normalized world-space direction vector.
    public func resolveDirection(
        _ directionName: String,
        context: SpatialContext
    ) -> SIMD3<Float> {
        let dir = directionName.lowercased().trimmingCharacters(in: .whitespaces)

        switch context.coordinateMode {
        case .screenSpace:
            return resolveScreenSpace(dir, context: context)
        case .worldSpace:
            return resolveWorldSpace(dir)
        case .objectSpace:
            return resolveWorldSpace(dir)
        }
    }

    /// Resolves a semantic distance string to a scalar distance in world units.
    public func resolveDistance(
        _ distanceName: String,
        context: SpatialContext
    ) -> Float {
        let name = distanceName.lowercased().trimmingCharacters(in: .whitespaces)

        if let numeric = Float(name) {
            return numeric
        }

        let bboxDiagonal = boundingBoxDiagonal(context)

        switch name {
        case "a bit", "a little", "slightly", "一点", "一些", "稍微":
            return bboxDiagonal * 0.1
        case "some", "moderate", "moderately", "一段", "适量":
            return bboxDiagonal * 0.5
        case "a lot", "far", "much", "很远", "大量", "很多":
            return bboxDiagonal * 2.0
        case "very far", "极远":
            return bboxDiagonal * 5.0
        default:
            return bboxDiagonal * 0.1
        }
    }

    /// Computes a full world-space translation delta from a direction name and distance name.
    public func computeTranslation(
        direction: String,
        distance: String,
        context: SpatialContext
    ) -> SIMD3<Float> {
        let dir = resolveDirection(direction, context: context)
        let dist = resolveDistance(distance, context: context)
        return dir * dist
    }

    // MARK: - Private

    private func resolveScreenSpace(_ dir: String, context: SpatialContext) -> SIMD3<Float> {
        let right = normalize(SIMD3<Float>(context.cameraRight.x, 0, context.cameraRight.z))
        let forward: SIMD3<Float> = {
            let f = SIMD3<Float>(context.cameraForward.x, 0, context.cameraForward.z)
            let len = length(f)
            return len > 0.001 ? f / len : SIMD3<Float>(0, 0, -1)
        }()
        let up = SIMD3<Float>(0, 1, 0)

        switch dir {
        case "right", "右", "右边", "右方":
            return right
        case "left", "左", "左边", "左方":
            return -right
        case "forward", "front", "前", "前面", "前方":
            return forward
        case "backward", "back", "后", "后面", "后方":
            return -forward
        case "up", "上", "上面", "上方":
            return up
        case "down", "下", "下面", "下方":
            return -up
        default:
            return right
        }
    }

    private func resolveWorldSpace(_ dir: String) -> SIMD3<Float> {
        switch dir {
        case "right", "右", "右边", "右方":
            return SIMD3<Float>(1, 0, 0)
        case "left", "左", "左边", "左方":
            return SIMD3<Float>(-1, 0, 0)
        case "forward", "front", "前", "前面", "前方":
            return SIMD3<Float>(0, 0, -1)
        case "backward", "back", "后", "后面", "后方":
            return SIMD3<Float>(0, 0, 1)
        case "up", "上", "上面", "上方":
            return SIMD3<Float>(0, 1, 0)
        case "down", "下", "下面", "下方":
            return SIMD3<Float>(0, -1, 0)
        default:
            return SIMD3<Float>(1, 0, 0)
        }
    }

    private func boundingBoxDiagonal(_ context: SpatialContext) -> Float {
        if let size = context.selectedEntityBoundsSize {
            return length(size)
        }
        return 5.0
    }
}

// MARK: - Spatial Context Text Description

extension SpatialContext {
    /// Produces a text description suitable for including in LLM prompts.
    public var textDescription: String {
        var lines: [String] = []
        lines.append("Camera position: (\(cameraPosition.x), \(cameraPosition.y), \(cameraPosition.z))")
        lines.append("Camera forward: (\(cameraForward.x), \(cameraForward.y), \(cameraForward.z))")
        lines.append("Camera right: (\(cameraRight.x), \(cameraRight.y), \(cameraRight.z))")
        lines.append("Coordinate mode: \(coordinateMode.rawValue)")

        if let eid = selectedEntityID {
            lines.append("Selected entity ID: \(eid)")
        }
        if let pos = selectedEntityPosition {
            lines.append("Selected entity position: (\(pos.x), \(pos.y), \(pos.z))")
        }
        if let bounds = selectedEntityBoundsSize {
            lines.append("Selected entity bounds: (\(bounds.x), \(bounds.y), \(bounds.z))")
        }

        return lines.joined(separator: "\n")
    }
}
