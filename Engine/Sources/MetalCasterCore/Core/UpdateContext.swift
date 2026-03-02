import Foundation
import MetalCasterInput

/// Snapshot of time-related state for the current frame.
public struct TimeState: Sendable {
    public let deltaTime: Float
    public let fixedDeltaTime: Float
    public let totalTime: Float
    public let frameCount: UInt64

    public init(deltaTime: Float, fixedDeltaTime: Float, totalTime: Float, frameCount: UInt64) {
        self.deltaTime = deltaTime
        self.fixedDeltaTime = fixedDeltaTime
        self.totalTime = totalTime
        self.frameCount = frameCount
    }
}

/// The unified context passed to every System on each frame.
///
/// Provides convenient access to the ECS world, timing, input, events,
/// and the engine itself. Systems should use this as their primary
/// interface rather than holding direct references to subsystems.
public struct UpdateContext: Sendable {
    public let world: World
    public let time: TimeState
    public let input: InputManager
    public let events: EventBus
    public let engine: Engine

    public init(world: World, time: TimeState, input: InputManager, events: EventBus, engine: Engine) {
        self.world = world
        self.time = time
        self.input = input
        self.events = events
        self.engine = engine
    }
}
