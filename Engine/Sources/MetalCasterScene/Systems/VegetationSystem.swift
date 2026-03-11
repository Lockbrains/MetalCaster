import Foundation
import simd
import MetalCasterCore

/// Scatters vegetation instances on terrain based on biome rules, density maps, and terrain properties.
public final class VegetationScatterEngine: @unchecked Sendable {

    public init() {}

    /// Generates vegetation instances for a given biome on a terrain.
    /// Uses height, slope, spacing, and density constraints.
    public func scatter(
        biome: BiomeDefinition,
        terrainWorldSize: SIMD2<Float>,
        terrainMaxHeight: Float,
        heightmapSampler: (Float, Float) -> Float,
        slopeSampler: (Float, Float) -> Float,
        seed: UInt64 = 0
    ) -> [VegetationInstance] {
        var instances: [VegetationInstance] = []
        var rng = SeededRNG(seed: seed)

        for prototype in biome.prototypes {
            let gridStep = max(prototype.minSpacing, 0.5)
            let stepsX = Int(terrainWorldSize.x / gridStep)
            let stepsZ = Int(terrainWorldSize.y / gridStep)

            for gz in 0..<stepsZ {
                for gx in 0..<stepsX {
                    if Float.random(in: 0...1, using: &rng) > prototype.density { continue }

                    let jitterX = Float.random(in: -gridStep * 0.4...gridStep * 0.4, using: &rng)
                    let jitterZ = Float.random(in: -gridStep * 0.4...gridStep * 0.4, using: &rng)
                    let worldX = Float(gx) * gridStep + jitterX - terrainWorldSize.x * 0.5
                    let worldZ = Float(gz) * gridStep + jitterZ - terrainWorldSize.y * 0.5

                    let u = (worldX + terrainWorldSize.x * 0.5) / terrainWorldSize.x
                    let v = (worldZ + terrainWorldSize.y * 0.5) / terrainWorldSize.y
                    guard u >= 0 && u <= 1 && v >= 0 && v <= 1 else { continue }

                    let normalizedHeight = heightmapSampler(u, v)
                    guard prototype.heightRange.contains(normalizedHeight) else { continue }

                    let slopeDegrees = slopeSampler(u, v) * 90.0
                    guard slopeDegrees <= prototype.maxSlope else { continue }

                    let worldY = normalizedHeight * terrainMaxHeight
                    let scale = Float.random(in: prototype.minScale...prototype.maxScale, using: &rng)
                    let rotation = Float.random(in: 0...(2 * Float.pi), using: &rng)

                    instances.append(VegetationInstance(
                        position: SIMD3<Float>(worldX, worldY, worldZ),
                        rotation: rotation,
                        scale: scale
                    ))
                }
            }
        }

        return instances
    }

    /// Generates GPU-ready instance data for instanced rendering.
    public static func buildInstanceBuffer(
        instances: [VegetationInstance]
    ) -> [InstanceData] {
        instances.map { inst in
            let cosR = cos(inst.rotation)
            let sinR = sin(inst.rotation)
            let s = inst.scale

            var model = matrix_identity_float4x4
            model[0][0] = cosR * s; model[0][2] =  sinR * s
            model[2][0] = -sinR * s; model[2][2] = cosR * s
            model[1][1] = s
            model[3][0] = inst.position.x
            model[3][1] = inst.position.y
            model[3][2] = inst.position.z

            return InstanceData(modelMatrix: model)
        }
    }
}

/// Per-instance transform data for GPU instanced drawing.
public struct InstanceData: Sendable {
    public var modelMatrix: float4x4

    public init(modelMatrix: float4x4) {
        self.modelMatrix = modelMatrix
    }
}

/// Deterministic random number generator for reproducible scatter.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 42 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

/// Preset biome definitions.
public enum BiomePresets {

    public static func temperateForest() -> BiomeDefinition {
        BiomeDefinition(
            name: "Temperate Forest",
            temperatureRange: 0.3...0.7,
            moistureRange: 0.4...0.8,
            prototypes: [
                VegetationPrototype(name: "Oak Tree", density: 0.15, minScale: 0.8, maxScale: 1.5, heightRange: 0.1...0.6, maxSlope: 35, minSpacing: 8),
                VegetationPrototype(name: "Pine Tree", density: 0.2, minScale: 0.7, maxScale: 1.3, heightRange: 0.3...0.7, maxSlope: 40, minSpacing: 6),
                VegetationPrototype(name: "Bush", density: 0.4, minScale: 0.5, maxScale: 1.0, heightRange: 0.1...0.5, maxSlope: 30, minSpacing: 3),
                VegetationPrototype(name: "Grass Clump", density: 0.7, minScale: 0.3, maxScale: 0.8, heightRange: 0.05...0.5, maxSlope: 25, minSpacing: 1),
            ]
        )
    }

    public static func alpine() -> BiomeDefinition {
        BiomeDefinition(
            name: "Alpine",
            temperatureRange: 0.1...0.4,
            moistureRange: 0.3...0.7,
            prototypes: [
                VegetationPrototype(name: "Snow Pine", density: 0.12, minScale: 0.6, maxScale: 1.2, heightRange: 0.4...0.7, maxSlope: 35, minSpacing: 10),
                VegetationPrototype(name: "Alpine Shrub", density: 0.25, minScale: 0.3, maxScale: 0.7, heightRange: 0.3...0.65, maxSlope: 30, minSpacing: 4),
                VegetationPrototype(name: "Rock", density: 0.15, minScale: 0.5, maxScale: 2.0, heightRange: 0.5...0.85, maxSlope: 50, minSpacing: 5),
            ]
        )
    }

    public static func desert() -> BiomeDefinition {
        BiomeDefinition(
            name: "Desert",
            temperatureRange: 0.7...1.0,
            moistureRange: 0.0...0.2,
            prototypes: [
                VegetationPrototype(name: "Cactus", density: 0.05, minScale: 0.6, maxScale: 1.5, heightRange: 0.1...0.5, maxSlope: 20, minSpacing: 15),
                VegetationPrototype(name: "Desert Shrub", density: 0.08, minScale: 0.3, maxScale: 0.8, heightRange: 0.05...0.4, maxSlope: 25, minSpacing: 8),
                VegetationPrototype(name: "Desert Rock", density: 0.1, minScale: 0.5, maxScale: 3.0, heightRange: 0.05...0.6, maxSlope: 45, minSpacing: 10),
            ]
        )
    }

    public static func tropical() -> BiomeDefinition {
        BiomeDefinition(
            name: "Tropical",
            temperatureRange: 0.6...1.0,
            moistureRange: 0.6...1.0,
            prototypes: [
                VegetationPrototype(name: "Palm Tree", density: 0.18, minScale: 0.8, maxScale: 1.6, heightRange: 0.05...0.4, maxSlope: 25, minSpacing: 7),
                VegetationPrototype(name: "Banana Plant", density: 0.12, minScale: 0.6, maxScale: 1.0, heightRange: 0.05...0.3, maxSlope: 20, minSpacing: 5),
                VegetationPrototype(name: "Tropical Fern", density: 0.5, minScale: 0.3, maxScale: 0.7, heightRange: 0.05...0.35, maxSlope: 30, minSpacing: 2),
                VegetationPrototype(name: "Jungle Tree", density: 0.15, minScale: 1.0, maxScale: 2.0, heightRange: 0.08...0.5, maxSlope: 30, minSpacing: 10),
            ]
        )
    }

    public static var all: [BiomeDefinition] {
        [temperateForest(), alpine(), desert(), tropical()]
    }
}
