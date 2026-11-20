import XCTest
@testable import MoonPixelCore

/// Families and relatives, churches and Sunday service, weddings, and prisoners who stay with their family.
final class FamilyTests: XCTestCase {
    /// A family of three generations in one town: grandparents, two children (one with a spouse and a child),
    /// and a cousin.
    func family(_ s: Society) -> (Settlement, [String: Agent]) {
        let t = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }[0]
        let ppl = t.members.compactMap { s.agents[$0] }.sorted { $0.id < $1.id }
        var f: [String: Agent] = [:]
        for (k, a) in zip(["gpa", "gma", "dad", "aunt", "mum", "me", "sis", "cousin", "uncle"], ppl) { f[k] = a; a.partner = 0; a.mother = 0; a.father = 0; a.children = [] }
        func parents(_ c: Agent, _ m: Agent, _ p: Agent) { c.mother = m.id; c.father = p.id; m.children.append(c.id); p.children.append(c.id) }
        parents(f["dad"]!, f["gma"]!, f["gpa"]!); parents(f["aunt"]!, f["gma"]!, f["gpa"]!)
        f["dad"]!.partner = f["mum"]!.id; f["mum"]!.partner = f["dad"]!.id
        parents(f["me"]!, f["mum"]!, f["dad"]!); parents(f["sis"]!, f["mum"]!, f["dad"]!)
        f["aunt"]!.partner = f["uncle"]!.id; f["uncle"]!.partner = f["aunt"]!.id
        parents(f["cousin"]!, f["aunt"]!, f["uncle"]!)
        return (t, f)
    }

    func testEveryoneKnowsTheirFamilyAndRelatives() {
        let s = makeSociety(61, villages: 2, per: 24)
        s.zh = true
        let (_, f) = family(s)
        let k = Dictionary(uniqueKeysWithValues: s.kin(of: f["me"]!).map { ($0.agent.id, $0.relation) })
        XCTAssertEqual(k[f["dad"]!.id], "父亲"); XCTAssertEqual(k[f["mum"]!.id], "母亲")
        XCTAssertTrue(["兄弟", "姐妹"].contains(k[f["sis"]!.id] ?? ""))
        XCTAssertTrue(["祖父", "祖母"].contains(k[f["gpa"]!.id] ?? ""))
        XCTAssertTrue(["叔伯舅舅", "姑姨"].contains(k[f["aunt"]!.id] ?? ""))
        XCTAssertTrue(["堂表兄弟", "堂表姐妹"].contains(k[f["cousin"]!.id] ?? ""))
        let gk = Dictionary(uniqueKeysWithValues: s.kin(of: f["gpa"]!).map { ($0.agent.id, $0.relation) })
        XCTAssertTrue(["孙子", "孙女"].contains(gk[f["me"]!.id] ?? ""))
        XCTAssertTrue(s.talk(f["me"]!.id, speak: false)!.family.count >= 6, "the person card lists them")
    }

    func testACoupleIsEngagedAndMarriedAtAWeddingWithTheirFamilyThere() {
        let s = makeSociety(62, villages: 2, per: 24)
        let (t, f) = family(s)
        let bride = f["sis"]!, groom = f["cousin"]!.female ? f["uncle"]! : f["cousin"]!
        bride.female = true; groom.female = false; bride.partner = 0; groom.partner = 0
        let shirt = bride.look.shirt
        s.engage(bride, groom)
        guard let w = s.realm.weddings?.first else { return XCTFail("engaged") }
        XCTAssertEqual(w.town, t.id)
        XCTAssertGreaterThan(w.at, s.world.time, "the wedding is to come")
        XCTAssertTrue(s.talk(bride.id, speak: false)!.family[0].contains("💍"))
        // the hour before: dressed in white; family among the guests
        s.world.time = w.at - 1800
        s.weddingsHourly()
        XCTAssertEqual(bride.look.shirt, "#fbfaf6", "the bride in white")
        XCTAssertNotNil(s.weddingNow(for: f["mum"]!), "her mother is a guest")
        XCTAssertTrue(s.weddingNow(for: bride)!.couple)
        // two hours on: married
        s.world.time = w.at + 7300
        s.weddingsHourly()
        XCTAssertEqual(bride.partner, groom.id); XCTAssertEqual(groom.partner, bride.id)
        XCTAssertNotNil(bride.spouseSince)
        XCTAssertEqual(bride.look.shirt, shirt, "changed back after")
        XCTAssertTrue(s.realm.weddings?.isEmpty ?? true)
        XCTAssertEqual(s.stats.weddings, 1)
    }

    func testTownsBuildChurchesAndGoToServiceOnTheSeventhDay() {
        XCTAssertNotNil(Society.roomSpecs["church"])
        let s = makeSociety(63, villages: 2, per: 40)
        let t = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }[0]
        XCTAssertTrue(s.queue(t, "church"), "room for a church")
        let c = t.buildings.first { $0.type == "church" }!
        c.done = true
        s.world.time = 6 * MP.daySeconds + 9.5 * MP.daySeconds / 24
        XCTAssertTrue(s.serviceTime)
        let a = t.members.compactMap { s.agents[$0] }.first { $0.stage(s.world.time) == "adult" && $0.legion == nil }!
        a.task = nil; a.hunger = 0.1; a.grief = 0.8
        XCTAssertTrue(s.ceremony(a, t))
        XCTAssertEqual(a.task?.act, "worship")
        s.worshipped(a)
        XCTAssertLessThan(a.grief, 0.8, "the service eases grief")
    }

    func testAPrisonerWhoStaysBringsTheirFamily() {
        let s = makeSociety(64, villages: 4, per: 24)
        let towns = s.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        guard let ta = towns.first, let tb = towns.first(where: { ($0.nation ?? 0) != (ta.nation ?? 0) }), let nb = tb.nation else { return XCTFail("two nations") }
        let (_, f) = family(s)
        let me = f["me"]!
        s.move(me, from: ta, to: tb); me.captiveOf = nb; me.captiveHome = ta.id
        let came = s.defect(me, to: nb, in: tb)
        XCTAssertEqual(me.nation, nb)
        XCTAssertGreaterThanOrEqual(came, 5, "parents, sister, grandparents and more came")
        for k in ["dad", "mum", "sis", "gpa"] { XCTAssertEqual(f[k]!.sid, tb.id, k); XCTAssertEqual(f[k]!.nation, nb, k) }
    }
}
