import XCTest
@testable import MoonPixelCore

/// A villager's facts for the on-device language model: true to the simulation, in the player's language,
/// with the written line to fall back on.
final class VillagerVoiceTests: XCTestCase {
    func testAVillagersFactsAreTheSimulationsAndTheWrittenLineStays() {
        let s = makeSociety(7, villages: 2, per: 12)
        s.zh = true
        let a = s.agents.values.sorted { $0.id < $1.id }.first { $0.stage(s.world.time) == "adult" }!
        let info = s.talk(a.id, speak: false)!
        let p = s.persona(a.id)!
        XCTAssertEqual(p.name, info.name)
        XCTAssertEqual(p.age, info.age)
        XCTAssertEqual(p.town, info.settlement)
        XCTAssertEqual(p.fallback, info.line, "the written line, for a phone without the model")
        XCTAssertGreaterThan(p.townPeople, 0)
        let prompt = p.prompt(topic: "family")
        XCTAssertTrue(prompt.contains(p.name) && prompt.contains(p.town))
        XCTAssertTrue(prompt.contains("家人"))
        XCTAssertTrue(p.instructions.contains("不要编造"), "the model is told to say nothing beyond the facts")
        // talking again moves the conversation on; the same facts and topic make the same key (written once)
        XCTAssertEqual(Set(VillagerPersona.topics.map { p.prompt(topic: $0) }).count, VillagerPersona.topics.count)
        XCTAssertEqual(p.key(topic: "work"), s.persona(a.id)!.key(topic: "work"))
        XCTAssertNotEqual(p.key(topic: "work"), p.key(topic: "town"))
        // asking does not change the villager (unlike talking)
        let rel = a.rel[0]
        _ = s.persona(a.id)
        XCTAssertEqual(a.rel[0], rel)
        // in English for an English player
        s.zh = false
        let e = s.persona(a.id)!
        XCTAssertTrue(e.instructions.contains("English"))
        XCTAssertTrue(e.prompt(topic: "greeting").contains("Facts:"))
        XCTAssertNil(s.persona(-5))
    }

    func testAHungryVillagerSaysSo() {
        let s = makeSociety(8, villages: 1, per: 10)
        s.zh = true
        let a = s.agents.values.sorted { $0.id < $1.id }.first { $0.stage(s.world.time) == "adult" }!
        a.hunger = 0.95
        XCTAssertTrue(s.persona(a.id)!.feeling.contains("很饿"))
    }
}
