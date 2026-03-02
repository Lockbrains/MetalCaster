import Foundation

/// Protocol for all ECS systems. Systems contain logic that operates on components.
///
/// Systems are stateless processors that query the World for entities with
/// specific component combinations, then update those components each frame.
public protocol System: AnyObject, Sendable {
    /// Human-readable name for debugging and profiling.
    var name: String { get }

    /// Priority for execution ordering. Lower values run first.
    var priority: Int { get }

    /// Whether this system is currently enabled.
    var isEnabled: Bool { get set }

    /// Called once when the system is first registered with the engine.
    func setup(world: World)

    /// Called every frame with the full engine context.
    func update(context: UpdateContext)

    /// Called when the system is removed from the engine.
    func teardown(world: World)
}

extension System {
    public var name: String { String(describing: type(of: self)) }
    public var priority: Int { 0 }
    public func setup(world: World) {}
    public func teardown(world: World) {}
}
