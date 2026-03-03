import simd

/// A planar polygon defined by an ordered list of coplanar vertices.
public struct MCPolygon: Sendable, Codable, Equatable {
    public var vertices: [SIMD3<Float>]

    public init(vertices: [SIMD3<Float>]) {
        self.vertices = vertices
    }

    /// The number of vertices.
    @inlinable
    public var vertexCount: Int { vertices.count }

    /// Computes the polygon normal using Newell's method (works for non-convex polygons).
    public var normal: SIMD3<Float> {
        guard vertices.count >= 3 else { return .zero }
        var n = SIMD3<Float>.zero
        for i in 0..<vertices.count {
            let curr = vertices[i]
            let next = vertices[(i + 1) % vertices.count]
            n.x += (curr.y - next.y) * (curr.z + next.z)
            n.y += (curr.z - next.z) * (curr.x + next.x)
            n.z += (curr.x - next.x) * (curr.y + next.y)
        }
        let len = simd_length(n)
        return len > mc_epsilon ? n / len : .zero
    }

    /// Signed area of the polygon (positive for CCW when viewed along the normal).
    public var area: Float {
        guard vertices.count >= 3 else { return 0 }
        var crossSum = SIMD3<Float>.zero
        let v0 = vertices[0]
        for i in 1..<(vertices.count - 1) {
            crossSum += simd_cross(vertices[i] - v0, vertices[i + 1] - v0)
        }
        return simd_length(crossSum) * 0.5
    }

    /// Centroid (average of vertices).
    public var centroid: SIMD3<Float> {
        guard !vertices.isEmpty else { return .zero }
        var sum = SIMD3<Float>.zero
        for v in vertices { sum += v }
        return sum / Float(vertices.count)
    }

    /// Returns the edges as segments.
    public var edges: [MCSegment] {
        guard vertices.count >= 2 else { return [] }
        return (0..<vertices.count).map { i in
            MCSegment(start: vertices[i], end: vertices[(i + 1) % vertices.count])
        }
    }

    /// Simple ear-clipping triangulation. Returns an array of index triples.
    /// Works correctly for convex polygons; approximate for non-convex ones.
    public func triangulate() -> [(Int, Int, Int)] {
        guard vertices.count >= 3 else { return [] }
        var indices = Array(0..<vertices.count)
        var result: [(Int, Int, Int)] = []
        result.reserveCapacity(vertices.count - 2)

        var remaining = indices.count
        var i = 0
        var guard_counter = remaining * 2

        while remaining > 2 && guard_counter > 0 {
            guard_counter -= 1
            let prev = indices[(i + remaining - 1) % remaining]
            let curr = indices[i % remaining]
            let next = indices[(i + 1) % remaining]

            let e1 = vertices[next] - vertices[curr]
            let e2 = vertices[prev] - vertices[curr]
            let n = normal
            if simd_dot(simd_cross(e1, e2), n) >= 0 {
                result.append((prev, curr, next))
                indices.remove(at: i % remaining)
                remaining -= 1
                if i >= remaining { i = 0 }
                continue
            }
            i = (i + 1) % remaining
        }
        return result
    }

    /// Returns true if the point (assumed on the polygon's plane) is inside the polygon.
    /// Uses the winding number method.
    public func contains(_ point: SIMD3<Float>) -> Bool {
        guard vertices.count >= 3 else { return false }
        let n = normal
        let absN = SIMD3<Float>(abs(n.x), abs(n.y), abs(n.z))

        let projAxis1: Int
        let projAxis2: Int
        if absN.x >= absN.y && absN.x >= absN.z {
            projAxis1 = 1; projAxis2 = 2
        } else if absN.y >= absN.z {
            projAxis1 = 0; projAxis2 = 2
        } else {
            projAxis1 = 0; projAxis2 = 1
        }

        func proj(_ v: SIMD3<Float>) -> SIMD2<Float> {
            SIMD2<Float>(v[projAxis1], v[projAxis2])
        }

        let p2d = proj(point)
        var winding = 0
        for i in 0..<vertices.count {
            let a = proj(vertices[i])
            let b = proj(vertices[(i + 1) % vertices.count])
            if a.y <= p2d.y {
                if b.y > p2d.y && cross2D(b - a, p2d - a) > 0 { winding += 1 }
            } else {
                if b.y <= p2d.y && cross2D(b - a, p2d - a) < 0 { winding -= 1 }
            }
        }
        return winding != 0
    }
}

@inlinable
func cross2D(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    a.x * b.y - a.y * b.x
}
