import Foundation
import simd
import MetalCasterCore
import MetalCasterMath

/// Sort-and-Sweep broadphase collision detection.
/// Projects AABBs onto a single axis and finds overlapping pairs efficiently.
public final class Broadphase {

    /// A broadphase entry: entity + its world-space AABB.
    public struct Entry {
        public let entity: Entity
        public var aabb: MCAABB
    }

    private var entries: [Entry] = []
    private var sortedIndices: [Int] = []

    public init() {}

    /// Clears all entries for the current frame.
    public func clear() {
        entries.removeAll(keepingCapacity: true)
        sortedIndices.removeAll(keepingCapacity: true)
    }

    /// Adds a body's world-space AABB for broadphase testing.
    public func insert(entity: Entity, aabb: MCAABB) {
        entries.append(Entry(entity: entity, aabb: aabb))
    }

    /// Performs Sort-and-Sweep on the X axis and returns potentially overlapping pairs.
    public func findPairs() -> [CollisionPairKey] {
        let count = entries.count
        guard count > 1 else { return [] }

        sortedIndices = Array(0..<count)
        sortedIndices.sort { entries[$0].aabb.min.x < entries[$1].aabb.min.x }

        var pairs: [CollisionPairKey] = []
        pairs.reserveCapacity(count)

        for i in 0..<count {
            let idxA = sortedIndices[i]
            let aabbA = entries[idxA].aabb

            for j in (i + 1)..<count {
                let idxB = sortedIndices[j]
                let aabbB = entries[idxB].aabb

                if aabbB.min.x > aabbA.max.x { break }

                if aabbA.min.y <= aabbB.max.y && aabbA.max.y >= aabbB.min.y &&
                   aabbA.min.z <= aabbB.max.z && aabbA.max.z >= aabbB.min.z {
                    pairs.append(CollisionPairKey(entries[idxA].entity, entries[idxB].entity))
                }
            }
        }

        return pairs
    }

    /// Direct lookup for an entity's AABB.
    public func aabb(for entity: Entity) -> MCAABB? {
        entries.first { $0.entity == entity }?.aabb
    }
}
