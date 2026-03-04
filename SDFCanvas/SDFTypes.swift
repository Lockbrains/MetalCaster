import Foundation
import simd
import UniformTypeIdentifiers

// MARK: - simd_quatf Codable / Equatable

extension simd_quatf: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let x = try c.decode(Float.self)
        let y = try c.decode(Float.self)
        let z = try c.decode(Float.self)
        let w = try c.decode(Float.self)
        self.init(ix: x, iy: y, iz: z, r: w)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(vector.x)
        try c.encode(vector.y)
        try c.encode(vector.z)
        try c.encode(vector.w)
    }
}

extension simd_quatf: @retroactive Equatable {
    public static func == (lhs: simd_quatf, rhs: simd_quatf) -> Bool {
        lhs.vector == rhs.vector
    }
}

// MARK: - Custom File Type

extension UTType {
    static let sdfCanvas = UTType(exportedAs: "com.linghent.sdfcanvas")
}

// MARK: - SDF Node

/// Recursive tree representing an SDF scene.
///
/// Each node carries a UUID for tree editor selection, drag-and-drop, and undo.
/// The recursive `indirect enum` maps directly to the tree hierarchy displayed
/// in the editor sidebar and compiles 1:1 into MSL via `SDFShaderGenerator`.
public indirect enum SDFNode: Codable, Sendable, Equatable {

    // MARK: Primitives

    case sphere(id: UUID, radius: Float)
    case box(id: UUID, size: SIMD3<Float>)
    case roundedBox(id: UUID, size: SIMD3<Float>, radius: Float)
    case cylinder(id: UUID, radius: Float, height: Float)
    case torus(id: UUID, majorRadius: Float, minorRadius: Float)
    case capsule(id: UUID, radius: Float, height: Float)
    case cone(id: UUID, radius: Float, height: Float)

    // MARK: Boolean Operations

    case union(id: UUID, SDFNode, SDFNode)
    case subtraction(id: UUID, SDFNode, SDFNode)
    case intersection(id: UUID, SDFNode, SDFNode)
    case smoothUnion(id: UUID, SDFNode, SDFNode, k: Float)
    case smoothSubtraction(id: UUID, SDFNode, SDFNode, k: Float)
    case smoothIntersection(id: UUID, SDFNode, SDFNode, k: Float)

    // MARK: Transform

    case transform(id: UUID, child: SDFNode,
                   position: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>)

    // MARK: Modifiers

    case round(id: UUID, child: SDFNode, radius: Float)
    case onion(id: UUID, child: SDFNode, thickness: Float)
    case twist(id: UUID, child: SDFNode, amount: Float)
    case bend(id: UUID, child: SDFNode, amount: Float)
    case elongate(id: UUID, child: SDFNode, h: SIMD3<Float>)
    case repeatSpace(id: UUID, child: SDFNode, period: SIMD3<Float>)

    // MARK: - Identity

    public var id: UUID {
        switch self {
        case .sphere(let id, _),
             .box(let id, _),
             .roundedBox(let id, _, _),
             .cylinder(let id, _, _),
             .torus(let id, _, _),
             .capsule(let id, _, _),
             .cone(let id, _, _),
             .union(let id, _, _),
             .subtraction(let id, _, _),
             .intersection(let id, _, _),
             .smoothUnion(let id, _, _, _),
             .smoothSubtraction(let id, _, _, _),
             .smoothIntersection(let id, _, _, _),
             .transform(let id, _, _, _, _),
             .round(let id, _, _),
             .onion(let id, _, _),
             .twist(let id, _, _),
             .bend(let id, _, _),
             .elongate(let id, _, _),
             .repeatSpace(let id, _, _):
            return id
        }
    }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .sphere:              return "Sphere"
        case .box:                 return "Box"
        case .roundedBox:          return "Rounded Box"
        case .cylinder:            return "Cylinder"
        case .torus:               return "Torus"
        case .capsule:             return "Capsule"
        case .cone:                return "Cone"
        case .union:               return "Union"
        case .subtraction:         return "Subtraction"
        case .intersection:        return "Intersection"
        case .smoothUnion:         return "Smooth Union"
        case .smoothSubtraction:   return "Smooth Subtraction"
        case .smoothIntersection:  return "Smooth Intersection"
        case .transform:           return "Transform"
        case .round:               return "Round"
        case .onion:               return "Onion"
        case .twist:               return "Twist"
        case .bend:                return "Bend"
        case .elongate:            return "Elongate"
        case .repeatSpace:         return "Repeat"
        }
    }

    public var icon: String {
        switch self {
        case .sphere:              return "circle"
        case .box:                 return "square"
        case .roundedBox:          return "square.on.square"
        case .cylinder:            return "cylinder"
        case .torus:               return "circle.circle"
        case .capsule:             return "capsule"
        case .cone:                return "triangle"
        case .union:               return "plus.circle"
        case .subtraction:         return "minus.circle"
        case .intersection:        return "circle.grid.cross"
        case .smoothUnion:         return "plus.circle.fill"
        case .smoothSubtraction:   return "minus.circle.fill"
        case .smoothIntersection:  return "circle.grid.cross.fill"
        case .transform:           return "move.3d"
        case .round:               return "circle.dashed"
        case .onion:               return "circle.and.line.horizontal"
        case .twist:               return "arrow.triangle.2.circlepath"
        case .bend:                return "arrow.uturn.right"
        case .elongate:            return "arrow.left.and.right"
        case .repeatSpace:         return "square.grid.3x3"
        }
    }

    /// Whether this node is a leaf (primitive) with no children.
    public var isPrimitive: Bool {
        switch self {
        case .sphere, .box, .roundedBox, .cylinder, .torus, .capsule, .cone:
            return true
        default:
            return false
        }
    }

    /// Whether this is a boolean operation with two children.
    public var isBooleanOp: Bool {
        switch self {
        case .union, .subtraction, .intersection,
             .smoothUnion, .smoothSubtraction, .smoothIntersection:
            return true
        default:
            return false
        }
    }

    // MARK: - Children

    /// Direct children of this node (0 for primitives, 1 for modifiers, 2 for booleans).
    public var children: [SDFNode] {
        switch self {
        case .sphere, .box, .roundedBox, .cylinder, .torus, .capsule, .cone:
            return []
        case .union(_, let a, let b),
             .subtraction(_, let a, let b),
             .intersection(_, let a, let b),
             .smoothUnion(_, let a, let b, _),
             .smoothSubtraction(_, let a, let b, _),
             .smoothIntersection(_, let a, let b, _):
            return [a, b]
        case .transform(_, let c, _, _, _),
             .round(_, let c, _),
             .onion(_, let c, _),
             .twist(_, let c, _),
             .bend(_, let c, _),
             .elongate(_, let c, _),
             .repeatSpace(_, let c, _):
            return [c]
        }
    }

    // MARK: - Tree Traversal

    /// Find a node by its UUID anywhere in the tree.
    public func find(id target: UUID) -> SDFNode? {
        if self.id == target { return self }
        for child in children {
            if let found = child.find(id: target) { return found }
        }
        return nil
    }

    /// Replace a node identified by UUID, returning a new tree.
    public func replacing(id target: UUID, with replacement: SDFNode) -> SDFNode {
        if self.id == target { return replacement }

        switch self {
        case .sphere, .box, .roundedBox, .cylinder, .torus, .capsule, .cone:
            return self

        case .union(let id, let a, let b):
            return .union(id: id,
                          a.replacing(id: target, with: replacement),
                          b.replacing(id: target, with: replacement))
        case .subtraction(let id, let a, let b):
            return .subtraction(id: id,
                                a.replacing(id: target, with: replacement),
                                b.replacing(id: target, with: replacement))
        case .intersection(let id, let a, let b):
            return .intersection(id: id,
                                 a.replacing(id: target, with: replacement),
                                 b.replacing(id: target, with: replacement))
        case .smoothUnion(let id, let a, let b, let k):
            return .smoothUnion(id: id,
                                a.replacing(id: target, with: replacement),
                                b.replacing(id: target, with: replacement), k: k)
        case .smoothSubtraction(let id, let a, let b, let k):
            return .smoothSubtraction(id: id,
                                      a.replacing(id: target, with: replacement),
                                      b.replacing(id: target, with: replacement), k: k)
        case .smoothIntersection(let id, let a, let b, let k):
            return .smoothIntersection(id: id,
                                       a.replacing(id: target, with: replacement),
                                       b.replacing(id: target, with: replacement), k: k)

        case .transform(let id, let c, let p, let r, let s):
            return .transform(id: id, child: c.replacing(id: target, with: replacement),
                              position: p, rotation: r, scale: s)
        case .round(let id, let c, let r):
            return .round(id: id, child: c.replacing(id: target, with: replacement), radius: r)
        case .onion(let id, let c, let t):
            return .onion(id: id, child: c.replacing(id: target, with: replacement), thickness: t)
        case .twist(let id, let c, let a):
            return .twist(id: id, child: c.replacing(id: target, with: replacement), amount: a)
        case .bend(let id, let c, let a):
            return .bend(id: id, child: c.replacing(id: target, with: replacement), amount: a)
        case .elongate(let id, let c, let h):
            return .elongate(id: id, child: c.replacing(id: target, with: replacement), h: h)
        case .repeatSpace(let id, let c, let p):
            return .repeatSpace(id: id, child: c.replacing(id: target, with: replacement), period: p)
        }
    }

    /// Remove a node by UUID, returning nil if the root itself is removed.
    public func removing(id target: UUID) -> SDFNode? {
        if self.id == target { return nil }

        switch self {
        case .sphere, .box, .roundedBox, .cylinder, .torus, .capsule, .cone:
            return self

        case .union(let id, let a, let b):
            let ra = a.removing(id: target)
            let rb = b.removing(id: target)
            if let ra, let rb { return .union(id: id, ra, rb) }
            return ra ?? rb

        case .subtraction(let id, let a, let b):
            let ra = a.removing(id: target)
            let rb = b.removing(id: target)
            if let ra, let rb { return .subtraction(id: id, ra, rb) }
            return ra ?? rb

        case .intersection(let id, let a, let b):
            let ra = a.removing(id: target)
            let rb = b.removing(id: target)
            if let ra, let rb { return .intersection(id: id, ra, rb) }
            return ra ?? rb

        case .smoothUnion(let id, let a, let b, let k):
            let ra = a.removing(id: target)
            let rb = b.removing(id: target)
            if let ra, let rb { return .smoothUnion(id: id, ra, rb, k: k) }
            return ra ?? rb

        case .smoothSubtraction(let id, let a, let b, let k):
            let ra = a.removing(id: target)
            let rb = b.removing(id: target)
            if let ra, let rb { return .smoothSubtraction(id: id, ra, rb, k: k) }
            return ra ?? rb

        case .smoothIntersection(let id, let a, let b, let k):
            let ra = a.removing(id: target)
            let rb = b.removing(id: target)
            if let ra, let rb { return .smoothIntersection(id: id, ra, rb, k: k) }
            return ra ?? rb

        case .transform(let id, let c, let p, let r, let s):
            guard let rc = c.removing(id: target) else { return nil }
            return .transform(id: id, child: rc, position: p, rotation: r, scale: s)
        case .round(let id, let c, let r):
            guard let rc = c.removing(id: target) else { return nil }
            return .round(id: id, child: rc, radius: r)
        case .onion(let id, let c, let t):
            guard let rc = c.removing(id: target) else { return nil }
            return .onion(id: id, child: rc, thickness: t)
        case .twist(let id, let c, let a):
            guard let rc = c.removing(id: target) else { return nil }
            return .twist(id: id, child: rc, amount: a)
        case .bend(let id, let c, let a):
            guard let rc = c.removing(id: target) else { return nil }
            return .bend(id: id, child: rc, amount: a)
        case .elongate(let id, let c, let h):
            guard let rc = c.removing(id: target) else { return nil }
            return .elongate(id: id, child: rc, h: h)
        case .repeatSpace(let id, let c, let p):
            guard let rc = c.removing(id: target) else { return nil }
            return .repeatSpace(id: id, child: rc, period: p)
        }
    }

    // MARK: - CPU Evaluation (for Marching Cubes)

    /// Evaluate the signed distance at a point in local space.
    public func evaluate(at p: SIMD3<Float>) -> Float {
        switch self {
        case .sphere(_, let r):
            return length(p) - r

        case .box(_, let s):
            let q = abs(p) - s * 0.5
            return length(max(q, SIMD3<Float>.zero)) + min(max(q.x, max(q.y, q.z)), 0)

        case .roundedBox(_, let s, let r):
            let q = abs(p) - s * 0.5 + SIMD3<Float>(repeating: r)
            return length(max(q, SIMD3<Float>.zero)) + min(max(q.x, max(q.y, q.z)), 0) - r

        case .cylinder(_, let r, let h):
            let d = SIMD2<Float>(length(SIMD2<Float>(p.x, p.z)) - r, abs(p.y) - h * 0.5)
            return min(max(d.x, d.y), 0) + length(max(d, SIMD2<Float>.zero))

        case .torus(_, let major, let minor):
            let q = SIMD2<Float>(length(SIMD2<Float>(p.x, p.z)) - major, p.y)
            return length(q) - minor

        case .capsule(_, let r, let h):
            var q = p
            q.y -= clamp(q.y, -h * 0.5, h * 0.5)
            return length(q) - r

        case .cone(_, let r, let h):
            let q = SIMD2<Float>(length(SIMD2<Float>(p.x, p.z)), p.y)
            let tip = SIMD2<Float>(0, h)
            let cb = SIMD2<Float>(r, 0)
            let ba = cb - tip
            let pa = q - tip
            let x = pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0, 1)
            let y = pa - SIMD2<Float>(cb.x * clamp(pa.x / cb.x, 0, 1), cb.y)
            let d = min(dot(x, x), dot(y, y))
            let s: Float = max(-pa.y, (pa.x * ba.y - pa.y * ba.x)) > 0 ? 1 : -1
            return s * sqrt(d)

        // Boolean operations
        case .union(_, let a, let b):
            return min(a.evaluate(at: p), b.evaluate(at: p))
        case .subtraction(_, let a, let b):
            return max(a.evaluate(at: p), -b.evaluate(at: p))
        case .intersection(_, let a, let b):
            return max(a.evaluate(at: p), b.evaluate(at: p))

        case .smoothUnion(_, let a, let b, let k):
            let da = a.evaluate(at: p), db = b.evaluate(at: p)
            let h = clamp(0.5 + 0.5 * (db - da) / k, 0, 1)
            return mix(db, da, h) - k * h * (1 - h)

        case .smoothSubtraction(_, let a, let b, let k):
            let da = a.evaluate(at: p), db = b.evaluate(at: p)
            let h = clamp(0.5 - 0.5 * (db + da) / k, 0, 1)
            return mix(da, -db, h) + k * h * (1 - h)

        case .smoothIntersection(_, let a, let b, let k):
            let da = a.evaluate(at: p), db = b.evaluate(at: p)
            let h = clamp(0.5 - 0.5 * (db - da) / k, 0, 1)
            return mix(db, da, h) + k * h * (1 - h)

        // Transform
        case .transform(_, let child, let pos, let rot, let scl):
            let invRot = rot.inverse
            var local = p - pos
            local = invRot.act(local)
            local /= scl
            return child.evaluate(at: local) * min(scl.x, min(scl.y, scl.z))

        // Modifiers
        case .round(_, let child, let r):
            return child.evaluate(at: p) - r

        case .onion(_, let child, let t):
            return abs(child.evaluate(at: p)) - t

        case .twist(_, let child, let amount):
            let c = cos(amount * p.y)
            let s = sin(amount * p.y)
            let q = SIMD3<Float>(c * p.x - s * p.z, p.y, s * p.x + c * p.z)
            return child.evaluate(at: q)

        case .bend(_, let child, let amount):
            let c = cos(amount * p.x)
            let s = sin(amount * p.x)
            let q = SIMD3<Float>(c * p.x - s * p.y, s * p.x + c * p.y, p.z)
            return child.evaluate(at: q)

        case .elongate(_, let child, let h):
            let q = p - clamp(p, -h, h)
            return child.evaluate(at: q)

        case .repeatSpace(_, let child, let period):
            let q = SIMD3<Float>(
                p.x - period.x * Foundation.round(p.x / period.x),
                p.y - period.y * Foundation.round(p.y / period.y),
                p.z - period.z * Foundation.round(p.z / period.z)
            )
            return child.evaluate(at: q)
        }
    }

    /// Compute a normal via central differences on the SDF.
    public func normal(at p: SIMD3<Float>, eps: Float = 0.001) -> SIMD3<Float> {
        let n = SIMD3<Float>(
            evaluate(at: p + SIMD3(eps, 0, 0)) - evaluate(at: p - SIMD3(eps, 0, 0)),
            evaluate(at: p + SIMD3(0, eps, 0)) - evaluate(at: p - SIMD3(0, eps, 0)),
            evaluate(at: p + SIMD3(0, 0, eps)) - evaluate(at: p - SIMD3(0, 0, eps))
        )
        let len = length(n)
        return len > 0 ? n / len : SIMD3(0, 1, 0)
    }
}

// MARK: - Default Scenes

extension SDFNode {
    /// A simple default scene: smooth union of a sphere and a box.
    public static func defaultScene() -> SDFNode {
        .smoothUnion(
            id: UUID(),
            .sphere(id: UUID(), radius: 0.8),
            .transform(
                id: UUID(),
                child: .box(id: UUID(), size: SIMD3(1.0, 1.0, 1.0)),
                position: SIMD3(1.2, 0, 0),
                rotation: simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0)),
                scale: SIMD3(repeating: 1)
            ),
            k: 0.3
        )
    }
}

// MARK: - Bounding Box

extension SDFNode {
    /// Conservative AABB for the SDF scene, used for Marching Cubes sampling volume.
    public func boundingBox() -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        switch self {
        case .sphere(_, let r):
            return (SIMD3(repeating: -r), SIMD3(repeating: r))

        case .box(_, let s), .roundedBox(_, let s, _):
            return (-s * 0.5, s * 0.5)

        case .cylinder(_, let r, let h):
            return (SIMD3(-r, -h * 0.5, -r), SIMD3(r, h * 0.5, r))

        case .torus(_, let major, let minor):
            let ext = major + minor
            return (SIMD3(-ext, -minor, -ext), SIMD3(ext, minor, ext))

        case .capsule(_, let r, let h):
            return (SIMD3(-r, -h * 0.5 - r, -r), SIMD3(r, h * 0.5 + r, r))

        case .cone(_, let r, let h):
            return (SIMD3(-r, 0, -r), SIMD3(r, h, r))

        case .union(_, let a, let b),
             .smoothUnion(_, let a, let b, _):
            let (aMin, aMax) = a.boundingBox()
            let (bMin, bMax) = b.boundingBox()
            return (min(aMin, bMin), max(aMax, bMax))

        case .subtraction(_, let a, _),
             .smoothSubtraction(_, let a, _, _):
            return a.boundingBox()

        case .intersection(_, let a, let b),
             .smoothIntersection(_, let a, let b, _):
            let (aMin, aMax) = a.boundingBox()
            let (bMin, bMax) = b.boundingBox()
            return (max(aMin, bMin), min(aMax, bMax))

        case .transform(_, let c, let pos, _, let scl):
            let (cMin, cMax) = c.boundingBox()
            let scaledMin = cMin * scl + pos
            let scaledMax = cMax * scl + pos
            return (min(scaledMin, scaledMax), max(scaledMin, scaledMax))

        case .round(_, let c, let r):
            let (cMin, cMax) = c.boundingBox()
            return (cMin - SIMD3(repeating: r), cMax + SIMD3(repeating: r))

        case .onion(_, let c, let t):
            let (cMin, cMax) = c.boundingBox()
            return (cMin - SIMD3(repeating: t), cMax + SIMD3(repeating: t))

        case .twist(_, let c, _), .bend(_, let c, _):
            let (cMin, cMax) = c.boundingBox()
            let ext = max(abs(cMin), abs(cMax))
            let maxExt = max(ext.x, max(ext.y, ext.z))
            return (SIMD3(repeating: -maxExt), SIMD3(repeating: maxExt))

        case .elongate(_, let c, let h):
            let (cMin, cMax) = c.boundingBox()
            return (cMin - h, cMax + h)

        case .repeatSpace(_, let c, let period):
            let (cMin, cMax) = c.boundingBox()
            let extent = max(abs(cMin), abs(cMax))
            let reps: Float = 3
            return (-period * reps - extent, period * reps + extent)
        }
    }
}

// MARK: - Mesh Export Resolution

public enum MeshResolution: String, CaseIterable {
    case low = "Low (64)"
    case medium = "Medium (128)"
    case high = "High (256)"
    case ultra = "Ultra (512)"

    public var gridSize: Int {
        switch self {
        case .low: return 64
        case .medium: return 128
        case .high: return 256
        case .ultra: return 512
        }
    }
}

// MARK: - Canvas Document

struct SDFCanvasDocument: Codable {
    var name: String
    var tree: SDFNode
    var cameraYaw: Float
    var cameraPitch: Float
    var cameraDistance: Float
    var maxSteps: Int
    var surfaceThreshold: Float

    init(
        name: String = "Untitled",
        tree: SDFNode = .defaultScene(),
        cameraYaw: Float = 0.5,
        cameraPitch: Float = 0.3,
        cameraDistance: Float = 5.0,
        maxSteps: Int = 128,
        surfaceThreshold: Float = 0.001
    ) {
        self.name = name
        self.tree = tree
        self.cameraYaw = cameraYaw
        self.cameraPitch = cameraPitch
        self.cameraDistance = cameraDistance
        self.maxSteps = maxSteps
        self.surfaceThreshold = surfaceThreshold
    }
}

// MARK: - GPU Uniforms

struct SDFUniforms {
    var inverseViewProjection: simd_float4x4
    var cameraPosition: SIMD3<Float>
    var time: Float
    var resolution: SIMD2<Float>
    var maxSteps: Int32
    var surfaceThreshold: Float
}

// MARK: - Notification Names

extension NSNotification.Name {
    static let sdfCanvasNew      = NSNotification.Name("sdfCanvasNew")
    static let sdfCanvasSave     = NSNotification.Name("sdfCanvasSave")
    static let sdfCanvasSaveAs   = NSNotification.Name("sdfCanvasSaveAs")
    static let sdfCanvasOpen     = NSNotification.Name("sdfCanvasOpen")
    static let sdfCanvasExport   = NSNotification.Name("sdfCanvasExport")
}

// MARK: - Float Helpers

func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a * (1 - t) + b * t
}

func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
    min(max(x, lo), hi)
}

func clamp(_ v: SIMD3<Float>, _ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> SIMD3<Float> {
    min(max(v, lo), hi)
}

func abs(_ v: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(Swift.abs(v.x), Swift.abs(v.y), Swift.abs(v.z))
}
