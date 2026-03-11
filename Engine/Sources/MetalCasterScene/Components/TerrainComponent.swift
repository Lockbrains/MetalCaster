import Foundation
import simd
import MetalCasterCore

// MARK: - Terrain Material Layer

public struct TerrainMaterialLayer: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var albedoTexturePath: String?
    public var normalTexturePath: String?
    public var roughnessTexturePath: String?
    public var aoTexturePath: String?
    public var tiling: SIMD2<Float>

    /// Height range where this layer is active (normalized 0–1).
    public var heightRange: ClosedRange<Float>

    /// Slope range in degrees where this layer appears.
    public var slopeRange: ClosedRange<Float>

    /// Blend sharpness at layer boundaries. Higher = sharper transitions.
    public var blendSharpness: Float

    public init(
        name: String,
        heightRange: ClosedRange<Float> = 0...1,
        slopeRange: ClosedRange<Float> = 0...90,
        blendSharpness: Float = 2.0,
        tiling: SIMD2<Float> = SIMD2<Float>(10, 10)
    ) {
        self.id = UUID()
        self.name = name
        self.heightRange = heightRange
        self.slopeRange = slopeRange
        self.blendSharpness = blendSharpness
        self.tiling = tiling
    }
}

// MARK: - Erosion Model

public enum ErosionType: String, CaseIterable, Codable, Sendable {
    case hydraulic     = "Hydraulic"
    case thermal       = "Thermal"
    case wind          = "Wind"
    case coastal       = "Coastal"
    case glacial       = "Glacial"
    case sediment      = "Sediment"
    case arid          = "Arid"
    case fluvial       = "Fluvial"
}

// MARK: - Noise Type

public enum TerrainNoiseType: String, CaseIterable, Codable, Sendable {
    case perlin        = "Perlin"
    case simplex       = "Simplex"
    case voronoi       = "Voronoi"
    case ridged        = "Ridged"
    case billow        = "Billow"
    case fbm           = "FBM"
    case warp          = "Domain Warp"
    case cellular      = "Cellular"
}

// MARK: - Noise Layer

public struct TerrainNoiseLayer: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var noiseType: TerrainNoiseType
    public var frequency: Float
    public var amplitude: Float
    public var octaves: Int
    public var lacunarity: Float
    public var persistence: Float
    public var seed: UInt32
    public var offset: SIMD2<Float>
    public var isEnabled: Bool

    public init(
        noiseType: TerrainNoiseType = .perlin,
        frequency: Float = 1.0,
        amplitude: Float = 1.0,
        octaves: Int = 6,
        lacunarity: Float = 2.0,
        persistence: Float = 0.5,
        seed: UInt32 = 0,
        offset: SIMD2<Float> = .zero
    ) {
        self.id = UUID()
        self.noiseType = noiseType
        self.frequency = frequency
        self.amplitude = amplitude
        self.octaves = octaves
        self.lacunarity = lacunarity
        self.persistence = persistence
        self.seed = seed
        self.offset = offset
        self.isEnabled = true
    }
}

// MARK: - Erosion Config

public struct ErosionConfig: Codable, Sendable, Equatable {
    public var type: ErosionType
    public var iterations: Int
    public var strength: Float
    public var isEnabled: Bool

    public init(type: ErosionType = .hydraulic, iterations: Int = 50000, strength: Float = 1.0) {
        self.type = type
        self.iterations = iterations
        self.strength = strength
        self.isEnabled = true
    }
}

// MARK: - Terrain Component

/// Defines a GPU-generated terrain entity with procedural heightmap, erosion, and material layering.
public struct TerrainComponent: Component, Equatable {

    /// Resolution of the heightmap texture (power of two recommended).
    public var heightmapResolution: Int

    /// World-space footprint of the terrain (width, depth).
    public var worldSize: SIMD2<Float>

    /// Maximum displacement height from the base plane.
    public var maxHeight: Float

    /// Noise layers composited to produce the base heightmap.
    public var noiseLayers: [TerrainNoiseLayer]

    /// Erosion passes applied after noise generation.
    public var erosionConfigs: [ErosionConfig]

    /// Material layers painted onto the terrain surface.
    public var materialLayers: [TerrainMaterialLayer]

    /// Number of LOD subdivision levels for the terrain mesh.
    public var lodLevels: Int

    /// Whether the terrain mesh needs regeneration.
    public var isDirty: Bool

    public init(
        heightmapResolution: Int = 2048,
        worldSize: SIMD2<Float> = SIMD2<Float>(1000, 1000),
        maxHeight: Float = 500,
        lodLevels: Int = 6
    ) {
        self.heightmapResolution = heightmapResolution
        self.worldSize = worldSize
        self.maxHeight = maxHeight
        self.noiseLayers = [TerrainNoiseLayer()]
        self.erosionConfigs = [ErosionConfig()]
        self.materialLayers = [
            TerrainMaterialLayer(name: "Rock", heightRange: 0...1, slopeRange: 40...90),
            TerrainMaterialLayer(name: "Grass", heightRange: 0...0.5, slopeRange: 0...35),
            TerrainMaterialLayer(name: "Snow", heightRange: 0.7...1, slopeRange: 0...45),
            TerrainMaterialLayer(name: "Sand", heightRange: 0...0.15, slopeRange: 0...20),
        ]
        self.lodLevels = lodLevels
        self.isDirty = true
    }
}
