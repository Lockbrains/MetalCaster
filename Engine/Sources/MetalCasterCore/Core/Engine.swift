import Foundation

/// The main engine coordinator. Manages the World and all registered Systems.
///
/// The Engine runs the game loop by ticking all systems each frame.
/// Systems are executed in priority order (lower priority values first).
public final class Engine: @unchecked Sendable {

    /// The ECS world containing all entities and components.
    public let world: World

    /// The event bus for inter-system communication.
    public let events: EventBus

    /// All registered systems, sorted by priority.
    private var systems: [any System] = []

    /// Whether the engine is currently running its update loop.
    public private(set) var isRunning: Bool = false

    /// Total elapsed time since the engine started, in seconds.
    public private(set) var totalTime: Float = 0

    /// Time of the last frame, in seconds.
    public private(set) var deltaTime: Float = 0

    /// The fixed timestep for physics updates (default 1/60).
    public var fixedDeltaTime: Float = 1.0 / 60.0

    public init() {
        self.world = World()
        self.events = EventBus()
    }

    // MARK: - System Management

    /// Registers a system with the engine. Systems are sorted by priority after insertion.
    public func addSystem(_ system: any System) {
        systems.append(system)
        systems.sort { $0.priority < $1.priority }
        system.setup(world: world)
    }

    /// Removes a system from the engine.
    public func removeSystem(_ system: any System) {
        system.teardown(world: world)
        systems.removeAll { $0 === system }
    }

    /// Returns a system of the given type, if registered.
    public func getSystem<S: System>(_ type: S.Type) -> S? {
        systems.first { $0 is S } as? S
    }

    /// All currently registered systems.
    public var registeredSystems: [any System] { systems }

    // MARK: - Update Loop

    /// Performs one engine tick. Call this every frame from the render loop.
    public func tick(deltaTime dt: Float) {
        self.deltaTime = dt
        self.totalTime += dt

        for system in systems where system.isEnabled {
            system.update(world: world, deltaTime: dt)
        }

        events.flush()
    }

    /// Starts the engine. Call before the first tick.
    public func start() {
        isRunning = true
        totalTime = 0
    }

    /// Stops the engine and tears down all systems.
    public func stop() {
        isRunning = false
        for system in systems {
            system.teardown(world: world)
        }
    }

    /// Resets the engine: clears the world and re-sets up all systems.
    public func reset() {
        world.clear()
        totalTime = 0
        deltaTime = 0
        for system in systems {
            system.setup(world: world)
        }
    }
}
