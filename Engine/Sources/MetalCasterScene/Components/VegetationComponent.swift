import Foundation
import simd
import MetalCasterCore

// MARK: - Vegetation Instance

public struct VegetationInstance: Codable, Sendable, Equatable {
    public var position: SIMD3<Float>
    public var rotation: Float
    public var scale: Float

    public init(position: SIMD3<Float>, rotation: Float = 0, scale: Float = 1) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}

// MARK: - Vegetation Prototype

public struct VegetationPrototype: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var meshPath: String?
    public var density: Float
    public var minScale: Float
    public var maxScale: Float
    /// Height range (normalized 0–1 of terrain height) where this prototype can spawn.
    public var heightRange: ClosedRange<Float>
    /// Maximum terrain slope (degrees) where this prototype can spawn.
    public var maxSlope: Float
    /// Minimum distance between instances of this prototype.
    public var minSpacing: Float

    public init(
        name: String,
        density: Float = 0.5,
        minScale: Float = 0.8,
        maxScale: Float = 1.2,
        heightRange: ClosedRange<Float> = 0...1,
        maxSlope: Float = 45,
        minSpacing: Float = 2.0
    ) {
        self.id = UUID()
        self.name = name
        self.density = density
        self.minScale = minScale
        self.maxScale = maxScale
        self.heightRange = heightRange
        self.maxSlope = maxSlope
        self.minSpacing = minSpacing
    }
}

// MARK: - Biome Definition

public struct BiomeDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var prototypes: [VegetationPrototype]
    /// Temperature range (abstract 0–1 scale).
    public var temperatureRange: ClosedRange<Float>
    /// Moisture range (abstract 0–1 scale).
    public var moistureRange: ClosedRange<Float>

    public init(
        name: String,
        temperatureRange: ClosedRange<Float> = 0...1,
        moistureRange: ClosedRange<Float> = 0...1,
        prototypes: [VegetationPrototype] = []
    ) {
        self.id = UUID()
        self.name = name
        self.temperatureRange = temperatureRange
        self.moistureRange = moistureRange
        self.prototypes = prototypes
    }
}

// MARK: - Vegetation Component

/// Manages instanced vegetation scatter on a terrain surface.
public struct VegetationComponent: Component {
    public var biome: BiomeDefinition
    public var densityMapPath: String?
    public var instances: [VegetationInstance]
    public var lodDistances: [Float]
    public var isDirty: Bool

    public init(
        biome: BiomeDefinition = BiomeDefinition(name: "Default"),
        lodDistances: [Float] = [50, 150, 500]
    ) {
        self.biome = biome
        self.densityMapPath = nil
        self.instances = []
        self.lodDistances = lodDistances
        self.isDirty = true
    }
}
