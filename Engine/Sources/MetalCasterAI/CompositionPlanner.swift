import Foundation

// MARK: - Composition Plan (AI Module Types)

/// A structured multi-step plan for composing a complex scene.
public struct AICompositionPlan: Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var description: String
    public var stages: [Stage]
    public var status: Status

    public enum Status: String, Codable, Sendable {
        case draft     = "Draft"
        case confirmed = "Confirmed"
        case executing = "Executing"
        case completed = "Completed"
        case failed    = "Failed"
    }

    public struct Stage: Codable, Sendable, Identifiable {
        public let id: UUID
        public var order: Int
        public var name: String
        public var description: String
        public var toolCalls: [PlannedToolCall]
        public var requiredAssets: [AssetRequirement]
        public var status: StageStatus

        public enum StageStatus: String, Codable, Sendable {
            case pending   = "Pending"
            case running   = "Running"
            case completed = "Completed"
            case failed    = "Failed"
        }

        public init(order: Int, name: String, description: String,
                    toolCalls: [PlannedToolCall] = [], requiredAssets: [AssetRequirement] = []) {
            self.id = UUID()
            self.order = order
            self.name = name
            self.description = description
            self.toolCalls = toolCalls
            self.requiredAssets = requiredAssets
            self.status = .pending
        }
    }

    public struct PlannedToolCall: Codable, Sendable {
        public var toolName: String
        public var arguments: [String: String]

        public init(toolName: String, arguments: [String: String] = [:]) {
            self.toolName = toolName
            self.arguments = arguments
        }
    }

    public struct AssetRequirement: Codable, Sendable, Identifiable {
        public let id: UUID
        public var name: String
        public var assetType: AssetType
        public var source: AssetSource
        public var referencePrompt: String?

        public enum AssetType: String, Codable, Sendable { case mesh, texture, material }
        public enum AssetSource: String, Codable, Sendable { case userProvided, aiGenerated, library }

        public init(name: String, assetType: AssetType, source: AssetSource, referencePrompt: String? = nil) {
            self.id = UUID()
            self.name = name
            self.assetType = assetType
            self.source = source
            self.referencePrompt = referencePrompt
        }
    }

    public init(title: String, description: String, stages: [Stage] = []) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.stages = stages
        self.status = .draft
    }
}

// MARK: - Plan Builder

/// Builds scene composition plans from AI analysis.
public struct CompositionPlanBuilder: Sendable {

    public init() {}

    /// Generates a plan for a snow mountain scene.
    public func snowMountainPlan() -> AICompositionPlan {
        AICompositionPlan(
            title: "Snow Mountain Scene",
            description: "A high-altitude mountain landscape with snow peaks, alpine vegetation, and atmospheric fog.",
            stages: [
                .init(order: 1, name: "Terrain Generation",
                      description: "Generate high-altitude mountainous terrain with ridged noise and glacial erosion.",
                      toolCalls: [
                          PlannedToolCall(toolName: "generateTerrain", arguments: [
                              "noiseType": "Ridged", "frequency": "3.0", "amplitude": "1.5",
                              "octaves": "8", "maxHeight": "200", "worldSize": "[500, 500]"
                          ]),
                          PlannedToolCall(toolName: "applyErosion", arguments: [
                              "type": "Glacial", "strength": "0.8"
                          ]),
                      ]),
                .init(order: 2, name: "Material Setup",
                      description: "Apply snow-covered rock materials with height and slope-based blending.",
                      toolCalls: [
                          PlannedToolCall(toolName: "paintMaterial", arguments: [
                              "materialName": "Snow", "position": "[0, 0]", "radius": "500"
                          ]),
                      ]),
                .init(order: 3, name: "Vegetation",
                      description: "Scatter alpine vegetation below the snow line.",
                      toolCalls: [
                          PlannedToolCall(toolName: "scatterVegetation", arguments: [
                              "biomeName": "Alpine", "density": "0.3"
                          ]),
                      ],
                      requiredAssets: [
                          .init(name: "Snow Pine", assetType: .mesh, source: .aiGenerated, referencePrompt: "Realistic snow-covered pine tree, alpine environment"),
                          .init(name: "Alpine Rock", assetType: .mesh, source: .aiGenerated, referencePrompt: "Weathered alpine rock with snow patches"),
                      ]),
                .init(order: 4, name: "Atmosphere",
                      description: "Configure snowy atmosphere with height fog and overcast lighting.",
                      toolCalls: [
                          PlannedToolCall(toolName: "adjustAtmosphere", arguments: [
                              "preset": "snowy", "fogDensity": "0.3"
                          ]),
                      ]),
                .init(order: 5, name: "Optimization",
                      description: "Auto-generate LODs and enable instancing for vegetation.",
                      toolCalls: [
                          PlannedToolCall(toolName: "optimizeScene", arguments: [
                              "enableLOD": "true", "enableInstancing": "true", "targetFPS": "60"
                          ]),
                      ]),
            ]
        )
    }

    /// Alias
    private typealias PlannedToolCall = AICompositionPlan.PlannedToolCall
}
