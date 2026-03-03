import simd

/// A view frustum defined by six planes, used for culling.
/// Plane normals point inward.
public struct MCFrustum: Sendable, Equatable {
    public var left: MCPlane
    public var right: MCPlane
    public var bottom: MCPlane
    public var top: MCPlane
    public var near: MCPlane
    public var far: MCPlane

    public init(
        left: MCPlane,
        right: MCPlane,
        bottom: MCPlane,
        top: MCPlane,
        near: MCPlane,
        far: MCPlane
    ) {
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
        self.near = near
        self.far = far
    }

    /// Extracts frustum planes from a view-projection matrix.
    /// The resulting plane normals point inward.
    public init(viewProjection vp: simd_float4x4) {
        let row0 = SIMD4<Float>(vp.columns.0.x, vp.columns.1.x, vp.columns.2.x, vp.columns.3.x)
        let row1 = SIMD4<Float>(vp.columns.0.y, vp.columns.1.y, vp.columns.2.y, vp.columns.3.y)
        let row2 = SIMD4<Float>(vp.columns.0.z, vp.columns.1.z, vp.columns.2.z, vp.columns.3.z)
        let row3 = SIMD4<Float>(vp.columns.0.w, vp.columns.1.w, vp.columns.2.w, vp.columns.3.w)

        self.left   = MCFrustum.normalizePlane(row3 + row0)
        self.right  = MCFrustum.normalizePlane(row3 - row0)
        self.bottom = MCFrustum.normalizePlane(row3 + row1)
        self.top    = MCFrustum.normalizePlane(row3 - row1)
        self.near   = MCFrustum.normalizePlane(row2)
        self.far    = MCFrustum.normalizePlane(row3 - row2)
    }

    private static func normalizePlane(_ v: SIMD4<Float>) -> MCPlane {
        let n = SIMD3<Float>(v.x, v.y, v.z)
        let len = simd_length(n)
        guard len > mc_epsilon else {
            return MCPlane(normal: SIMD3<Float>(0, 1, 0), distance: 0)
        }
        return MCPlane(normal: n / len, distance: v.w / len)
    }

    /// All six planes as an array.
    @inlinable
    public var planes: [MCPlane] {
        [left, right, bottom, top, near, far]
    }

    /// Returns true if the point is inside all six planes.
    public func contains(_ point: SIMD3<Float>) -> Bool {
        for plane in planes {
            if plane.signedDistance(to: point) < -mc_epsilon {
                return false
            }
        }
        return true
    }

    /// Returns true if the AABB is at least partially inside the frustum.
    public func intersects(_ aabb: MCAABB) -> Bool {
        for plane in planes {
            let px = SIMD3<Float>(
                plane.normal.x >= 0 ? aabb.max.x : aabb.min.x,
                plane.normal.y >= 0 ? aabb.max.y : aabb.min.y,
                plane.normal.z >= 0 ? aabb.max.z : aabb.min.z
            )
            if plane.signedDistance(to: px) < 0 {
                return false
            }
        }
        return true
    }

    /// Returns true if the sphere is at least partially inside the frustum.
    public func intersects(_ sphere: MCSphere) -> Bool {
        for plane in planes {
            if plane.signedDistance(to: sphere.center) < -sphere.radius {
                return false
            }
        }
        return true
    }
}
