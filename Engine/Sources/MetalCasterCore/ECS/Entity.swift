import Foundation

/// A lightweight entity identifier. Entities are just IDs — all data lives in Components.
public struct Entity: Hashable, Equatable, Codable, Sendable, CustomStringConvertible {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }

    public var description: String { "Entity(\(id))" }
}

extension Entity: Comparable {
    public static func < (lhs: Entity, rhs: Entity) -> Bool {
        lhs.id < rhs.id
    }
}
