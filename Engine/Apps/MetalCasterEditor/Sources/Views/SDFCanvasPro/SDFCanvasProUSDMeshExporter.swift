import Foundation
import simd

/// Exports a Marching Cubes mesh as a USDA text file compatible with
/// MetalCaster's USD import pipeline and Apple's ModelIO/RealityKit.
enum USDMeshExporter {

    /// Generate a USDA string from an extracted mesh.
    ///
    /// The output is a valid USDA file with a single `Mesh` prim containing
    /// `points`, `normals`, `faceVertexCounts`, and `faceVertexIndices`.
    /// MetalCaster's `USDImporter` can load this directly as a mesh asset.
    static func export(mesh: MarchingCubes.ExportMesh, name: String = "SDFMesh") -> String {
        guard !mesh.positions.isEmpty, !mesh.indices.isEmpty else {
            return emptyScene(name: name)
        }

        let sanitizedName = name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        var lines: [String] = []
        lines.append("#usda 1.0")
        lines.append("(")
        lines.append("    defaultPrim = \"\(sanitizedName)\"")
        lines.append("    metersPerUnit = 1")
        lines.append("    upAxis = \"Y\"")
        lines.append(")")
        lines.append("")
        lines.append("def Mesh \"\(sanitizedName)\"")
        lines.append("{")

        // Points
        lines.append("    point3f[] points = [")
        let pointStrs = mesh.positions.map { p in
            "        (\(fmt(p.x)), \(fmt(p.y)), \(fmt(p.z)))"
        }
        lines.append(pointStrs.joined(separator: ",\n"))
        lines.append("    ]")

        // Normals
        lines.append("    normal3f[] normals = [")
        let normalStrs = mesh.normals.map { n in
            "        (\(fmt(n.x)), \(fmt(n.y)), \(fmt(n.z)))"
        }
        lines.append(normalStrs.joined(separator: ",\n"))
        lines.append("    ]")
        lines.append("    uniform token normals:interpolation = \"vertex\"")

        // Face vertex counts (all triangles)
        let triCount = mesh.indices.count / 3
        let faceCountsStr = [String](repeating: "3", count: triCount).joined(separator: ", ")
        lines.append("    int[] faceVertexCounts = [\(faceCountsStr)]")

        // Face vertex indices
        let indexStrs = mesh.indices.map { String($0) }
        lines.append("    int[] faceVertexIndices = [")
        let batchSize = 24
        for start in stride(from: 0, to: indexStrs.count, by: batchSize) {
            let end = min(start + batchSize, indexStrs.count)
            let batch = indexStrs[start..<end].joined(separator: ", ")
            let trailing = end < indexStrs.count ? "," : ""
            lines.append("        \(batch)\(trailing)")
        }
        lines.append("    ]")

        // Subdivision scheme
        lines.append("    uniform token subdivisionScheme = \"none\"")

        // Extent (bounding box)
        if let extent = computeExtent(positions: mesh.positions) {
            lines.append("    float3[] extent = [(\(fmt(extent.0.x)), \(fmt(extent.0.y)), \(fmt(extent.0.z))), (\(fmt(extent.1.x)), \(fmt(extent.1.y)), \(fmt(extent.1.z)))]")
        }

        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func fmt(_ v: Float) -> String {
        String(format: "%.6f", v)
    }

    private static func emptyScene(name: String) -> String {
        """
        #usda 1.0
        (
            defaultPrim = "\(name)"
            metersPerUnit = 1
            upAxis = "Y"
        )

        def Xform "\(name)"
        {
        }
        """
    }

    private static func computeExtent(
        positions: [SIMD3<Float>]
    ) -> (SIMD3<Float>, SIMD3<Float>)? {
        guard let first = positions.first else { return nil }
        var lo = first
        var hi = first
        for p in positions {
            lo = min(lo, p)
            hi = max(hi, p)
        }
        return (lo, hi)
    }
}
