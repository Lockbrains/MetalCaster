import simd

/// A rectangle in 3D space defined by a center, two half-extent axes, and a normal.
public struct MCRect3D: Sendable, Codable, Equatable {
    public var center: SIMD3<Float>
    /// Half-size along the axisU direction.
    public var extentU: Float
    /// Half-size along the axisV direction.
    public var extentV: Float
    /// First axis direction (unit vector).
    public var axisU: SIMD3<Float>
    /// Second axis direction (unit vector, perpendicular to axisU).
    public var axisV: SIMD3<Float>

    public init(
        center: SIMD3<Float>,
        axisU: SIMD3<Float>,
        axisV: SIMD3<Float>,
        extentU: Float,
        extentV: Float
    ) {
        self.center = center
        self.axisU = simd_normalize(axisU)
        self.axisV = simd_normalize(axisV)
        self.extentU = extentU
        self.extentV = extentV
    }

    /// Creates an axis-aligned rectangle on the XZ plane.
    public init(center: SIMD3<Float>, width: Float, height: Float) {
        self.center = center
        self.axisU = SIMD3<Float>(1, 0, 0)
        self.axisV = SIMD3<Float>(0, 0, 1)
        self.extentU = width * 0.5
        self.extentV = height * 0.5
    }

    /// The face normal (axisU × axisV).
    @inlinable
    public var normal: SIMD3<Float> {
        simd_normalize(simd_cross(axisU, axisV))
    }

    /// Area of the rectangle.
    @inlinable
    public var area: Float {
        extentU * extentV * 4
    }

    /// Returns the four corners in CCW order.
    @inlinable
    public var corners: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let u = axisU * extentU
        let v = axisV * extentV
        return (
            center - u - v,
            center + u - v,
            center + u + v,
            center - u + v
        )
    }

    /// Returns true if the point (assumed to be on the rect's plane) lies inside.
    @inlinable
    public func contains(_ point: SIMD3<Float>) -> Bool {
        let d = point - center
        let projU = abs(simd_dot(d, axisU))
        let projV = abs(simd_dot(d, axisV))
        return projU <= extentU + mc_epsilon && projV <= extentV + mc_epsilon
    }

    /// The plane containing this rectangle.
    @inlinable
    public var plane: MCPlane {
        MCPlane(normal: normal, point: center)
    }
}
