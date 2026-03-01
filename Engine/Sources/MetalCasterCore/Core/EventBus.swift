import Foundation

/// A typed event for inter-system communication.
public protocol MCEvent: Sendable {}

/// A simple publish-subscribe event bus for decoupled communication between systems.
///
/// Events are queued during the frame and flushed at the end of each tick.
/// Subscribers receive events in the order they were published.
public final class EventBus: @unchecked Sendable {

    private var subscribers: [String: [(any MCEvent) -> Void]] = [:]
    private var pendingEvents: [(String, any MCEvent)] = []

    public init() {}

    /// Subscribes to events of a specific type.
    public func subscribe<E: MCEvent>(_ type: E.Type, handler: @escaping (E) -> Void) {
        let key = String(describing: type)
        if subscribers[key] == nil {
            subscribers[key] = []
        }
        subscribers[key]!.append { event in
            if let typed = event as? E {
                handler(typed)
            }
        }
    }

    /// Publishes an event. It will be delivered to subscribers during flush().
    public func publish<E: MCEvent>(_ event: E) {
        let key = String(describing: type(of: event))
        pendingEvents.append((key, event))
    }

    /// Publishes an event and delivers it immediately (bypasses the queue).
    public func publishImmediate<E: MCEvent>(_ event: E) {
        let key = String(describing: type(of: event))
        guard let handlers = subscribers[key] else { return }
        for handler in handlers {
            handler(event)
        }
    }

    /// Delivers all queued events to their subscribers, then clears the queue.
    public func flush() {
        let events = pendingEvents
        pendingEvents.removeAll()

        for (key, event) in events {
            guard let handlers = subscribers[key] else { continue }
            for handler in handlers {
                handler(event)
            }
        }
    }

    /// Removes all subscribers and pending events.
    public func clear() {
        subscribers.removeAll()
        pendingEvents.removeAll()
    }
}
