import Foundation

/// A convenience protocol for the most common gameplay pattern:
/// read a custom Component, then mutate a Target component each frame.
///
/// Conformers only implement `process(entity:_:_:context:)`.
/// The engine handles entity iteration and component writeback automatically.
///
/// For more complex query patterns, conform to `System` directly.
public protocol GameplayScript: System {
    associatedtype Data: Component
    associatedtype Target: Component

    /// Called once per matching entity per frame.
    ///
    /// - Parameters:
    ///   - entity: The entity being processed.
    ///   - data: The read-only data component that drives this behavior.
    ///   - target: The mutable target component to modify.
    ///   - context: Full engine context (time, input, events, etc.).
    func process(entity: Entity, _ data: Data, _ target: inout Target, context: UpdateContext)
}

extension GameplayScript {
    public func update(context: UpdateContext) {
        context.world.forEach(Data.self, Target.self) { entity, data, _ in
            context.world.update(Target.self, on: entity) { target in
                self.process(entity: entity, data, &target, context: context)
            }
        }
    }
}
