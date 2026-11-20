import XCTest
@testable import MoonPixelCore

/// Nobody is killed in war: the beaten are taken prisoner, and sent home when the war is over.
final class CaptivesTests: XCTestCase {
    func war(_ s: Society, _ a: Int, _ b: Int, _ on: Bool) {
        let k = s.realm.meet(a, b, at: s.world.time)
        s.realm.relations[k].state = on ? 1 : 0
    }

    func testSoldiersBeatenInTheFieldAreTakenPrisonerNotKilled() {
        let s = makeSociety(51, villages: 4, per: 20)
        let towns = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        guard let ta = towns.first, let tb = towns.first(where: { ($0.nation ?? 0) != (ta.nation ?? 0) }), let na = ta.nation, let nb = tb.nation else { return XCTFail("two nations") }
        war(s, na, nb, true)
        let soldiers = ta.members.compactMap { s.agents[$0] }.prefix(5)
        let lg = Legion(); lg.id = 901; lg.nation = na; lg.home = ta.id; lg.state = 4; lg.members = soldiers.map { $0.id }; lg.pos = ta.center.center
        let foe = Legion(); foe.id = 902; foe.nation = nb; foe.home = tb.id; foe.state = 4; foe.pos = tb.center.center
        lg.foe = foe.id; foe.foe = lg.id
        for a in soldiers { a.legion = lg.id }
        s.realm.legions += [lg, foe]
        let deaths = s.stats.deaths, alive = s.agents.count
        s.kill(from: lg, 3)
        XCTAssertEqual(s.stats.deaths, deaths, "nobody died")
        XCTAssertEqual(s.agents.count, alive, "everyone is still alive")
        let taken = soldiers.filter { $0.captiveOf == nb }
        XCTAssertEqual(taken.count, 3, "three taken prisoner by the other side")
        XCTAssertTrue(taken.allSatisfy { $0.legion == nil && $0.sid == tb.id && $0.nation == na }, "disarmed, held in a town of the captor's, still of their own nation")
        XCTAssertEqual(lg.members.count, 2)
        XCTAssertEqual(s.realm.ledger.fallen(na), 3, "the battle's losses are recorded (as prisoners)")
        XCTAssertEqual(s.prisoners()[nb], 3)
        // held while the war goes on; home when it is over
        s.releasePrisoners()
        XCTAssertEqual(soldiers.filter { $0.captiveOf != nil }.count, 3)
        war(s, na, nb, false)
        s.releasePrisoners()
        XCTAssertTrue(taken.allSatisfy { $0.captiveOf == nil }, "nobody is held after the war")
        // half stay with the side that took them (now of its nation), the rest go home
        let stayed = taken.filter { $0.nation == nb }, home = taken.filter { $0.nation == na }
        XCTAssertEqual(stayed.count + home.count, 3)
        XCTAssertTrue(stayed.allSatisfy { $0.sid == tb.id }); XCTAssertTrue(home.allSatisfy { $0.sid == ta.id })
        XCTAssertEqual(s.stats.freed ?? 0, home.count)
    }

    func testTheTravellerBeatenBySoldiersIsTakenPrisoner() {
        let s = makeSociety(52)
        var t = Society.Threat(); t.damage = 1e6; t.attackers = 3; t.captor = s.realm.nations.first!.id
        let deaths = s.realm.player.deaths
        XCTAssertTrue(s.harmPlayer(t).died)
        XCTAssertEqual(s.realm.player.deaths, deaths, "not counted as a death")
        s.realm.player.body = Body()
        XCTAssertNotNil(s.takeTravellerCaptor(), "carried to a town of the captor's")
        XCTAssertNil(s.takeTravellerCaptor(), "once")
    }

    func testRegionalWarsTakePrisonersAndSendThemHome() {
        let c = Civ(seed: 3)
        for x in 0...1 { var r = CivRegion(); r.rx = x; r.ry = 0; r.land = 1; r.fertility = 0.6; c.regions[r.key] = r }
        let a = c.newPolity(origin: "first", near: nil), b = c.newPolity(origin: "first", near: nil)
        let ca = c.newCity(at: MP.chunkKey(0, 0), nation: a, people: CivPeople(adults: 300), firstCount: true)
        let cb = c.newCity(at: MP.chunkKey(1, 0), nation: b, people: CivPeople(adults: 300), firstCount: true)
        c.polities[a]!.capital = ca.id; c.polities[b]!.capital = cb.id
        c.declare(a, on: b)
        XCTAssertTrue(c.atWar(a, b))
        let people = c.people
        let crew = ca.people.takeAdults(20)
        c.takePrisoners(crew, of: a, by: b, near: MP.chunkKey(1, 0))
        XCTAssertEqual(c.people, people, "nobody died: the crew are counted where they are held")
        XCTAssertEqual(c.prisonersHeld()[b], 20)
        XCTAssertEqual(cb.pop, 320)
        c.releasePrisoners()
        XCTAssertEqual(c.prisonersHeld()[b], 20, "held while at war")
        c.relations[CivRelation.key(a, b)]!.state = 0
        c.releasePrisoners()
        XCTAssertNil(c.prisonersHeld()[b])
        // ten go home, ten stay, and two of family each come to join those who stay
        XCTAssertEqual(ca.pop, 280 + 10 - 20, "half home again; families leave to join the rest")
        XCTAssertEqual(cb.pop, 320 - 10 + 20)
        XCTAssertEqual(c.people, people, "everyone still counted")
        XCTAssertEqual(c.totals.deaths["battle"] ?? 0, 0)
    }
}
