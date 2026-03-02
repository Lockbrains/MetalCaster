import Testing
@testable import MetalCasterCore

struct NameComponent: Component {
    var name: String
}

struct HealthComponent: Component {
    var hp: Int
    var maxHP: Int
}

struct PositionComponent: Component {
    var x: Float
    var y: Float
}

@Test func testEntityCreation() {
    let world = World()
    let e1 = world.createEntity()
    let e2 = world.createEntity()
    #expect(e1.id != e2.id)
    #expect(world.entityCount == 2)
}

@Test func testEntityDestruction() {
    let world = World()
    let e = world.createEntity()
    world.addComponent(NameComponent(name: "Test"), to: e)
    #expect(world.isAlive(e))
    world.destroyEntity(e)
    #expect(!world.isAlive(e))
    #expect(world.getComponent(NameComponent.self, from: e) == nil)
}

@Test func testComponentAddAndGet() {
    let world = World()
    let e = world.createEntity()
    world.addComponent(NameComponent(name: "Player"), to: e)
    world.addComponent(HealthComponent(hp: 100, maxHP: 100), to: e)

    let name = world.getComponent(NameComponent.self, from: e)
    #expect(name?.name == "Player")

    let health = world.getComponent(HealthComponent.self, from: e)
    #expect(health?.hp == 100)
}

@Test func testComponentRemoval() {
    let world = World()
    let e = world.createEntity()
    world.addComponent(NameComponent(name: "Test"), to: e)
    #expect(world.hasComponent(NameComponent.self, on: e))

    let removed = world.removeComponent(NameComponent.self, from: e)
    #expect(removed?.name == "Test")
    #expect(!world.hasComponent(NameComponent.self, on: e))
}

@Test func testSingleComponentQuery() {
    let world = World()
    let e1 = world.createEntity()
    let e2 = world.createEntity()
    let e3 = world.createEntity()

    world.addComponent(NameComponent(name: "A"), to: e1)
    world.addComponent(NameComponent(name: "B"), to: e2)
    world.addComponent(HealthComponent(hp: 50, maxHP: 100), to: e3)

    let results = world.query(NameComponent.self)
    #expect(results.count == 2)
}

@Test func testTwoComponentQuery() {
    let world = World()
    let e1 = world.createEntity()
    let e2 = world.createEntity()

    world.addComponent(NameComponent(name: "Player"), to: e1)
    world.addComponent(HealthComponent(hp: 100, maxHP: 100), to: e1)
    world.addComponent(NameComponent(name: "NPC"), to: e2)

    let results = world.query(NameComponent.self, HealthComponent.self)
    #expect(results.count == 1)
    #expect(results[0].1.name == "Player")
    #expect(results[0].2.hp == 100)
}

@Test func testThreeComponentQuery() {
    let world = World()
    let e1 = world.createEntity()
    world.addComponent(NameComponent(name: "P"), to: e1)
    world.addComponent(HealthComponent(hp: 100, maxHP: 100), to: e1)
    world.addComponent(PositionComponent(x: 1, y: 2), to: e1)

    let e2 = world.createEntity()
    world.addComponent(NameComponent(name: "Q"), to: e2)
    world.addComponent(HealthComponent(hp: 50, maxHP: 50), to: e2)

    let results = world.query(NameComponent.self, HealthComponent.self, PositionComponent.self)
    #expect(results.count == 1)
    #expect(results[0].1.name == "P")
}

@Test func testSpawn() {
    let world = World()
    let e = world.spawn(
        NameComponent(name: "Spawned"),
        HealthComponent(hp: 42, maxHP: 100)
    )
    #expect(world.getComponent(NameComponent.self, from: e)?.name == "Spawned")
    #expect(world.getComponent(HealthComponent.self, from: e)?.hp == 42)
}

@Test func testWorldClear() {
    let world = World()
    world.spawn(NameComponent(name: "A"))
    world.spawn(NameComponent(name: "B"))
    #expect(world.entityCount == 2)

    world.clear()
    #expect(world.entityCount == 0)
}

@Test func testEngineTickCallsSystems() {
    final class CountSystem: System, @unchecked Sendable {
        var isEnabled: Bool = true
        var tickCount = 0
        func update(context: UpdateContext) {
            tickCount += 1
        }
    }

    let engine = Engine()
    let system = CountSystem()
    engine.addSystem(system)
    engine.tick(deltaTime: 1.0 / 60.0)
    engine.tick(deltaTime: 1.0 / 60.0)
    #expect(system.tickCount == 2)
}

@Test func testEventBus() {
    struct DamageEvent: MCEvent {
        let amount: Int
    }

    let bus = EventBus()
    var received = 0
    bus.subscribe(DamageEvent.self) { event in
        received = event.amount
    }
    bus.publish(DamageEvent(amount: 25))
    #expect(received == 0) // Not yet flushed
    bus.flush()
    #expect(received == 25)
}
