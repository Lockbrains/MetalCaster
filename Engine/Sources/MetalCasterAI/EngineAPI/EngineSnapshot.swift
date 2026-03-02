import Foundation

/// Read-only snapshot of the entire engine state, serializable to text for LLM context.
public struct EngineSnapshot: Codable, Sendable {
    public let entityCount: Int
    public let entities: [EntityInfo]
    public let hierarchy: [HierarchyNode]
    public let selectedEntityID: UInt64?
    public let renderInfo: RenderInfo
    public let metrics: MetricsInfo
    public let systems: [SystemInfo]

    public init(
        entityCount: Int,
        entities: [EntityInfo],
        hierarchy: [HierarchyNode],
        selectedEntityID: UInt64?,
        renderInfo: RenderInfo,
        metrics: MetricsInfo,
        systems: [SystemInfo] = []
    ) {
        self.entityCount = entityCount
        self.entities = entities
        self.hierarchy = hierarchy
        self.selectedEntityID = selectedEntityID
        self.renderInfo = renderInfo
        self.metrics = metrics
        self.systems = systems
    }

    /// Human-readable text representation for inclusion in LLM system prompts.
    public var textDescription: String {
        var lines: [String] = []
        lines.append("Entity count: \(entityCount)")
        if let sel = selectedEntityID {
            if let entity = entities.first(where: { $0.id == sel }) {
                lines.append("Selected entity: \(entity.name) (id:\(sel))")
            } else {
                lines.append("Selected entity id: \(sel)")
            }
        }
        lines.append("")
        lines.append("Scene hierarchy:")
        for node in hierarchy {
            appendHierarchy(node, indent: "  ", to: &lines)
        }
        lines.append("")
        lines.append("Entities detail:")
        for entity in entities {
            var desc = "  [\(entity.id)] \(entity.name) — components: \(entity.components.joined(separator: ", "))"
            if let pos = entity.position {
                desc += " pos:(\(pos.x),\(pos.y),\(pos.z))"
            }
            lines.append(desc)
        }
        if !systems.isEmpty {
            lines.append("")
            lines.append("Registered systems (by priority):")
            for sys in systems {
                let status = sys.isEnabled ? "ON" : "OFF"
                lines.append("  [\(sys.priority)] \(sys.name) (\(status))")
            }
        }
        lines.append("")
        lines.append("Render state: \(renderInfo.drawCallCount) draw calls, \(renderInfo.lightCount) lights, mode=\(renderInfo.renderMode)")
        lines.append("Metrics: \(String(format: "%.1f", metrics.fps)) fps, frame time \(String(format: "%.2f", metrics.frameTime))ms")
        return lines.joined(separator: "\n")
    }

    private func appendHierarchy(_ node: HierarchyNode, indent: String, to lines: inout [String]) {
        lines.append("\(indent)- \(node.name) (id:\(node.entityID))")
        for child in node.children {
            appendHierarchy(child, indent: indent + "  ", to: &lines)
        }
    }

    public static let empty = EngineSnapshot(
        entityCount: 0,
        entities: [],
        hierarchy: [],
        selectedEntityID: nil,
        renderInfo: .empty,
        metrics: .empty,
        systems: []
    )
}

// MARK: - Sub-types

public struct EntityInfo: Codable, Sendable, Identifiable {
    public let id: UInt64
    public let name: String
    public let components: [String]
    public let position: Vec3Storage?
    public let rotation: Vec3Storage?
    public let scale: Vec3Storage?

    public init(id: UInt64, name: String, components: [String],
                position: Vec3Storage? = nil, rotation: Vec3Storage? = nil, scale: Vec3Storage? = nil) {
        self.id = id
        self.name = name
        self.components = components
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

public struct Vec3Storage: Codable, Sendable {
    public let x: Float, y: Float, z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x; self.y = y; self.z = z
    }
}

public struct HierarchyNode: Codable, Sendable {
    public let entityID: UInt64
    public let name: String
    public let children: [HierarchyNode]

    public init(entityID: UInt64, name: String, children: [HierarchyNode] = []) {
        self.entityID = entityID
        self.name = name
        self.children = children
    }
}

public struct RenderInfo: Codable, Sendable {
    public let drawCallCount: Int
    public let lightCount: Int
    public let renderMode: String

    public init(drawCallCount: Int, lightCount: Int, renderMode: String) {
        self.drawCallCount = drawCallCount
        self.lightCount = lightCount
        self.renderMode = renderMode
    }

    public static let empty = RenderInfo(drawCallCount: 0, lightCount: 0, renderMode: "rendered")
}

public struct MetricsInfo: Codable, Sendable {
    public let fps: Float
    public let frameTime: Float
    public let totalTime: Float

    public init(fps: Float, frameTime: Float, totalTime: Float) {
        self.fps = fps
        self.frameTime = frameTime
        self.totalTime = totalTime
    }

    public static let empty = MetricsInfo(fps: 0, frameTime: 0, totalTime: 0)
}

public struct SystemInfo: Codable, Sendable {
    public let name: String
    public let priority: Int
    public let isEnabled: Bool

    public init(name: String, priority: Int, isEnabled: Bool) {
        self.name = name
        self.priority = priority
        self.isEnabled = isEnabled
    }
}
