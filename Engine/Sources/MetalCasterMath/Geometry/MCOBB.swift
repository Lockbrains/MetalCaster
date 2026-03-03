import simd

/// An oriented bounding box defined by a center, half-extents, and a rotation.
public struct MCOBB: Sendable, Equatable {
    public var center: SIMD3<Float>
    public var halfExtents: SIMD3<Float>
    public var rotation: simd_quatf

    public init(
        center: SIMD3<Float>,
        halfExtents: SIMD3<Float>,
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    ) {
        self.center = center
        self.halfExtents = halfExtents
        self.rotation = rotation
    }

    /// Creates an OBB from a transform and local half-extents.
    public init(transform: MCTransform, halfExtents: SIMD3<Float>) {
        self.center = transform.position
        self.halfExtents = halfExtents * transform.scale
        self.rotation = transform.rotation
    }

    public static func == (lhs: MCOBB, rhs: MCOBB) -> Bool {
        lhs.center == rhs.center &&
        lhs.halfExtents == rhs.halfExtents &&
        lhs.rotation.real == rhs.rotation.real &&
        lhs.rotation.imag == rhs.rotation.imag
    }

    /// The three local axes as unit vectors.
    @inlinable
    public var axes: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (rotation.act(SIMD3<Float>(1, 0, 0)),
         rotation.act(SIMD3<Float>(0, 1, 0)),
         rotation.act(SIMD3<Float>(0, 0, 1)))
    }

    /// Returns true if the point is inside or on the OBB.
    @inlinable
    public func contains(_ point: SIMD3<Float>) -> Bool {
        let d = point - center
        let (ax, ay, az) = axes
        return abs(simd_dot(d, ax)) <= halfExtents.x + mc_epsilon &&
               abs(simd_dot(d, ay)) <= halfExtents.y + mc_epsilon &&
               abs(simd_dot(d, az)) <= halfExtents.z + mc_epsilon
    }

    /// Returns the closest point on or inside the OBB to the given point.
    public func closestPoint(to point: SIMD3<Float>) -> SIMD3<Float> {
        let d = point - center
        let (ax, ay, az) = axes
        var result = center

        let distX = simd_dot(d, ax).clamped(to: -halfExtents.x...halfExtents.x)
        result += ax * distX

        let distY = simd_dot(d, ay).clamped(to: -halfExtents.y...halfExtents.y)
        result += ay * distY

        let distZ = simd_dot(d, az).clamped(to: -halfExtents.z...halfExtents.z)
        result += az * distZ

        return result
    }

    /// Returns the eight corners of the OBB.
    public var corners: [SIMD3<Float>] {
        let (ax, ay, az) = axes
        let ex = ax * halfExtents.x
        let ey = ay * halfExtents.y
        let ez = az * halfExtents.z
        return [
            center - ex - ey - ez,
            center + ex - ey - ez,
            center - ex + ey - ez,
            center + ex + ey - ez,
            center - ex - ey + ez,
            center + ex - ey + ez,
            center - ex + ey + ez,
            center + ex + ey + ez,
        ]
    }

    /// Converts to an axis-aligned bounding box enclosing this OBB.
    public func toAABB() -> MCAABB {
        MCAABB(enclosing: corners)
    }

    /// Volume of the OBB.
    @inlinable
    public var volume: Float {
        8 * halfExtents.x * halfExtents.y * halfExtents.z
    }
}

// Manual Codable because simd_quatf doesn't conform to Codable.
extension MCOBB: Codable {
    enum CodingKeys: String, CodingKey {
        case cx, cy, cz, hx, hy, hz, rx, ry, rz, rw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.center = SIMD3<Float>(
            try c.decode(Float.self, forKey: .cx),
            try c.decode(Float.self, forKey: .cy),
            try c.decode(Float.self, forKey: .cz)
        )
        self.halfExtents = SIMD3<Float>(
            try c.decode(Float.self, forKey: .hx),
            try c.decode(Float.self, forKey: .hy),
            try c.decode(Float.self, forKey: .hz)
        )
        self.rotation = simd_quatf(
            ix: try c.decode(Float.self, forKey: .rx),
            iy: try c.decode(Float.self, forKey: .ry),
            iz: try c.decode(Float.self, forKey: .rz),
            r: try c.decode(Float.self, forKey: .rw)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(center.x, forKey: .cx)
        try c.encode(center.y, forKey: .cy)
        try c.encode(center.z, forKey: .cz)
        try c.encode(halfExtents.x, forKey: .hx)
        try c.encode(halfExtents.y, forKey: .hy)
        try c.encode(halfExtents.z, forKey: .hz)
        try c.encode(rotation.imag.x, forKey: .rx)
        try c.encode(rotation.imag.y, forKey: .ry)
        try c.encode(rotation.imag.z, forKey: .rz)
        try c.encode(rotation.real, forKey: .rw)
    }
}
