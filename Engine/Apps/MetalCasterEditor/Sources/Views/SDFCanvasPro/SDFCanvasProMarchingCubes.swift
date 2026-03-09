import Foundation
import simd

/// CPU iso-surface extraction for SDF trees.
///
/// This keeps the same API name as the standalone tool (`MarchingCubes`) so
/// the export pipeline can be reused unchanged.
enum MarchingCubes {

    struct ExportMesh {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var indices: [UInt32]
    }

    /// Extract a triangle mesh from an SDF tree.
    ///
    /// Uses cube sampling with tetrahedra decomposition. The resulting mesh is
    /// watertight for most smooth fields and is sufficient for USD export.
    static func extract(from tree: SDFNode, gridSize: Int, padding: Float = 0.2) -> ExportMesh {
        let (bbMin, bbMax) = tree.boundingBox()
        let lo = bbMin - SIMD3(repeating: padding)
        let hi = bbMax + SIMD3(repeating: padding)
        let extent = hi - lo
        let step = extent / Float(gridSize)

        let nx = gridSize + 1
        let ny = gridSize + 1
        let nz = gridSize + 1

        var values = [Float](repeating: 0, count: nx * ny * nz)
        for iz in 0..<nz {
            for iy in 0..<ny {
                for ix in 0..<nx {
                    let p = lo + SIMD3(Float(ix), Float(iy), Float(iz)) * step
                    values[index(ix: ix, iy: iy, iz: iz, nx: nx, ny: ny)] = tree.evaluate(at: p)
                }
            }
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Simple deduplication to reduce duplicated seam vertices.
        var vertexMap: [SIMD3<Int32>: UInt32] = [:]
        let quantScale: Float = 1000.0

        func addVertex(_ pos: SIMD3<Float>) -> UInt32 {
            let key = SIMD3<Int32>(
                Int32(pos.x * quantScale),
                Int32(pos.y * quantScale),
                Int32(pos.z * quantScale)
            )
            if let existing = vertexMap[key] {
                return existing
            }
            let idx = UInt32(positions.count)
            positions.append(pos)
            normals.append(tree.normal(at: pos))
            vertexMap[key] = idx
            return idx
        }

        // Standard 6-tetrahedra decomposition of a cube (corner indices 0...7).
        let tetrahedra: [[Int]] = [
            [0, 5, 1, 6],
            [0, 1, 2, 6],
            [0, 2, 3, 6],
            [0, 3, 7, 6],
            [0, 7, 4, 6],
            [0, 4, 5, 6]
        ]

        for iz in 0..<gridSize {
            for iy in 0..<gridSize {
                for ix in 0..<gridSize {
                    let cubePos = cornerPositions(ix: ix, iy: iy, iz: iz, lo: lo, step: step)
                    let cubeVal = cornerValues(ix: ix, iy: iy, iz: iz, nx: nx, ny: ny, values: values)

                    for tet in tetrahedra {
                        let p = tet.map { cubePos[$0] }
                        let v = tet.map { cubeVal[$0] }
                        let tris = polygonizeTetra(positions: p, values: v)
                        for tri in tris {
                            let i0 = addVertex(tri.0)
                            let i1 = addVertex(tri.1)
                            let i2 = addVertex(tri.2)
                            indices.append(contentsOf: [i0, i1, i2])
                        }
                    }
                }
            }
        }

        return ExportMesh(positions: positions, normals: normals, indices: indices)
    }

    // MARK: - Tetra Polygonization

    private static func polygonizeTetra(
        positions p: [SIMD3<Float>],
        values v: [Float]
    ) -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        let inside = (0..<4).filter { v[$0] < 0 }
        let outside = (0..<4).filter { v[$0] >= 0 }

        if inside.isEmpty || inside.count == 4 {
            return []
        }

        // 1 inside / 3 outside => single triangle.
        if inside.count == 1 {
            let i = inside[0]
            let a = interpolate(p[i], p[outside[0]], v[i], v[outside[0]])
            let b = interpolate(p[i], p[outside[1]], v[i], v[outside[1]])
            let c = interpolate(p[i], p[outside[2]], v[i], v[outside[2]])
            return [(a, b, c)]
        }

        // 3 inside / 1 outside => single triangle (flipped winding).
        if inside.count == 3 {
            let o = outside[0]
            let a = interpolate(p[o], p[inside[0]], v[o], v[inside[0]])
            let b = interpolate(p[o], p[inside[1]], v[o], v[inside[1]])
            let c = interpolate(p[o], p[inside[2]], v[o], v[inside[2]])
            return [(a, c, b)]
        }

        // 2 inside / 2 outside => quad split into two triangles.
        let i0 = inside[0], i1 = inside[1]
        let o0 = outside[0], o1 = outside[1]

        let a = interpolate(p[i0], p[o0], v[i0], v[o0])
        let b = interpolate(p[i0], p[o1], v[i0], v[o1])
        let c = interpolate(p[i1], p[o0], v[i1], v[o0])
        let d = interpolate(p[i1], p[o1], v[i1], v[o1])

        return [(a, b, c), (b, d, c)]
    }

    // MARK: - Grid Helpers

    private static func index(ix: Int, iy: Int, iz: Int, nx: Int, ny: Int) -> Int {
        ix + iy * nx + iz * nx * ny
    }

    private static func cornerValues(
        ix: Int, iy: Int, iz: Int,
        nx: Int, ny: Int, values: [Float]
    ) -> [Float] {
        [
            values[index(ix: ix, iy: iy, iz: iz, nx: nx, ny: ny)],
            values[index(ix: ix + 1, iy: iy, iz: iz, nx: nx, ny: ny)],
            values[index(ix: ix + 1, iy: iy + 1, iz: iz, nx: nx, ny: ny)],
            values[index(ix: ix, iy: iy + 1, iz: iz, nx: nx, ny: ny)],
            values[index(ix: ix, iy: iy, iz: iz + 1, nx: nx, ny: ny)],
            values[index(ix: ix + 1, iy: iy, iz: iz + 1, nx: nx, ny: ny)],
            values[index(ix: ix + 1, iy: iy + 1, iz: iz + 1, nx: nx, ny: ny)],
            values[index(ix: ix, iy: iy + 1, iz: iz + 1, nx: nx, ny: ny)]
        ]
    }

    private static func cornerPositions(
        ix: Int, iy: Int, iz: Int,
        lo: SIMD3<Float>, step: SIMD3<Float>
    ) -> [SIMD3<Float>] {
        let base = lo + SIMD3(Float(ix), Float(iy), Float(iz)) * step
        return [
            base,
            base + SIMD3(step.x, 0, 0),
            base + SIMD3(step.x, step.y, 0),
            base + SIMD3(0, step.y, 0),
            base + SIMD3(0, 0, step.z),
            base + SIMD3(step.x, 0, step.z),
            base + step,
            base + SIMD3(0, step.y, step.z)
        ]
    }

    private static func interpolate(
        _ p1: SIMD3<Float>, _ p2: SIMD3<Float>,
        _ v1: Float, _ v2: Float
    ) -> SIMD3<Float> {
        if Swift.abs(v1) < 0.00001 { return p1 }
        if Swift.abs(v2) < 0.00001 { return p2 }
        if Swift.abs(v1 - v2) < 0.00001 { return p1 }
        let t = -v1 / (v2 - v1)
        return p1 + t * (p2 - p1)
    }
}
