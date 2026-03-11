import Foundation
import simd
import MetalCasterCore

// MARK: - Optimization Report

/// Summary of optimization results applied to a scene.
public struct OptimizationReport: Sendable {
    public var originalTriangleCount: Int
    public var optimizedTriangleCount: Int
    public var originalDrawCalls: Int
    public var optimizedDrawCalls: Int
    public var lodLevelsGenerated: Int
    public var instancedGroups: Int
    public var estimatedMemorySaved: Int
    public var estimatedFPS: Int
    public var suggestions: [String]

    public init() {
        self.originalTriangleCount = 0
        self.optimizedTriangleCount = 0
        self.originalDrawCalls = 0
        self.optimizedDrawCalls = 0
        self.lodLevelsGenerated = 0
        self.instancedGroups = 0
        self.estimatedMemorySaved = 0
        self.estimatedFPS = 60
        self.suggestions = []
    }

    /// Human-readable summary.
    public var summary: String {
        var lines: [String] = []
        lines.append("--- Scene Optimization Report ---")
        lines.append("Triangles: \(originalTriangleCount) -> \(optimizedTriangleCount) (\(triangleReductionPercent)% reduction)")
        lines.append("Draw Calls: \(originalDrawCalls) -> \(optimizedDrawCalls)")
        lines.append("LOD Levels Generated: \(lodLevelsGenerated)")
        lines.append("Instanced Groups: \(instancedGroups)")
        lines.append("Estimated Memory Saved: \(estimatedMemorySaved / 1024) KB")
        lines.append("Estimated FPS: \(estimatedFPS)")
        if !suggestions.isEmpty {
            lines.append("Suggestions:")
            for s in suggestions {
                lines.append("  - \(s)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var triangleReductionPercent: Int {
        guard originalTriangleCount > 0 else { return 0 }
        return Int(Float(originalTriangleCount - optimizedTriangleCount) / Float(originalTriangleCount) * 100)
    }
}

// MARK: - Scene Optimizer

/// Automatic scene optimization: LOD generation, instancing, culling analysis.
public final class SceneOptimizer: @unchecked Sendable {

    public struct Options: Sendable {
        public var targetFPS: Int
        public var enableAutoLOD: Bool
        public var enableInstancing: Bool
        public var enableOcclusionCulling: Bool
        public var lodDistances: [Float]
        public var maxTrianglesPerLOD: [Float]

        public init(
            targetFPS: Int = 60,
            enableAutoLOD: Bool = true,
            enableInstancing: Bool = true,
            enableOcclusionCulling: Bool = true
        ) {
            self.targetFPS = targetFPS
            self.enableAutoLOD = enableAutoLOD
            self.enableInstancing = enableInstancing
            self.enableOcclusionCulling = enableOcclusionCulling
            self.lodDistances = [50, 150, 400, 1000]
            self.maxTrianglesPerLOD = [1.0, 0.5, 0.25, 0.1]
        }
    }

    public init() {}

    /// Analyzes the scene and produces an optimization plan.
    public func analyze(
        entityCount: Int,
        totalTriangles: Int,
        drawCalls: Int,
        uniqueMeshCount: Int,
        duplicateMeshGroups: Int,
        options: Options = Options()
    ) -> OptimizationReport {
        var report = OptimizationReport()
        report.originalTriangleCount = totalTriangles
        report.originalDrawCalls = drawCalls

        // LOD estimation
        if options.enableAutoLOD {
            let lodLevels = options.lodDistances.count
            report.lodLevelsGenerated = lodLevels * uniqueMeshCount
            let avgReduction = options.maxTrianglesPerLOD.reduce(0, +) / Float(options.maxTrianglesPerLOD.count)
            report.optimizedTriangleCount = Int(Float(totalTriangles) * avgReduction)
        } else {
            report.optimizedTriangleCount = totalTriangles
        }

        // Instancing estimation
        if options.enableInstancing && duplicateMeshGroups > 0 {
            report.instancedGroups = duplicateMeshGroups
            let savedDrawCalls = max(drawCalls - uniqueMeshCount, 0)
            report.optimizedDrawCalls = drawCalls - savedDrawCalls
        } else {
            report.optimizedDrawCalls = drawCalls
        }

        // Memory estimation (rough: 32 bytes per vertex)
        let savedTriangles = report.originalTriangleCount - report.optimizedTriangleCount
        report.estimatedMemorySaved = savedTriangles * 32

        // FPS estimation
        let drawCallOverhead = Float(report.optimizedDrawCalls) * 0.05
        let triangleOverhead = Float(report.optimizedTriangleCount) / 1_000_000.0 * 2.0
        let totalFrameTime = drawCallOverhead + triangleOverhead
        report.estimatedFPS = min(options.targetFPS, max(15, Int(1000.0 / max(totalFrameTime, 1.0))))

        // Suggestions
        if report.optimizedDrawCalls > 100 {
            report.suggestions.append("Consider merging static meshes to reduce draw calls below 100.")
        }
        if report.optimizedTriangleCount > 2_000_000 {
            report.suggestions.append("Scene exceeds 2M triangles. Aggressive LOD or mesh decimation recommended.")
        }
        if !options.enableOcclusionCulling && entityCount > 500 {
            report.suggestions.append("Enable occlusion culling for scenes with 500+ entities.")
        }
        if duplicateMeshGroups > 10 && !options.enableInstancing {
            report.suggestions.append("Enable GPU instancing — \(duplicateMeshGroups) mesh groups can be batched.")
        }

        return report
    }

    /// Generates LOD distance thresholds based on scene bounds.
    public func autoLODDistances(sceneBoundsRadius: Float, levels: Int = 4) -> [Float] {
        guard levels > 0 else { return [] }
        return (0..<levels).map { i in
            let t = Float(i + 1) / Float(levels)
            return sceneBoundsRadius * t * t * 2.0
        }
    }
}

// MARK: - Terrain LOD Calculator

/// Calculates adaptive quadtree LOD for terrain patches.
public struct TerrainLODCalculator: Sendable {

    public init() {}

    /// Determines the LOD level for a terrain patch based on camera distance.
    public func lodLevel(
        patchCenter: SIMD3<Float>,
        cameraPosition: SIMD3<Float>,
        lodDistances: [Float]
    ) -> Int {
        let dist = length(patchCenter - cameraPosition)
        for (i, threshold) in lodDistances.enumerated() {
            if dist < threshold { return i }
        }
        return lodDistances.count
    }

    /// Generates an adaptive grid resolution map for terrain.
    /// Returns resolution (power of 2) per grid cell.
    public func adaptiveGrid(
        gridCells: Int,
        terrainWorldSize: SIMD2<Float>,
        cameraPosition: SIMD3<Float>,
        maxResolution: Int = 64,
        lodDistances: [Float] = [100, 300, 800, 2000]
    ) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 4, count: gridCells), count: gridCells)

        let cellSize = SIMD2<Float>(terrainWorldSize.x / Float(gridCells),
                                     terrainWorldSize.y / Float(gridCells))
        let halfTerrain = terrainWorldSize * 0.5

        for z in 0..<gridCells {
            for x in 0..<gridCells {
                let centerX = Float(x) * cellSize.x + cellSize.x * 0.5 - halfTerrain.x
                let centerZ = Float(z) * cellSize.y + cellSize.y * 0.5 - halfTerrain.y
                let center = SIMD3<Float>(centerX, 0, centerZ)

                let level = lodLevel(patchCenter: center, cameraPosition: cameraPosition, lodDistances: lodDistances)
                let resolution = max(4, maxResolution >> level)
                grid[z][x] = resolution
            }
        }

        return grid
    }
}
