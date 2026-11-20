import Foundation

// Families, relatives, churches and weddings; and prisoners who stay with the side that took them.
//
// * Kin: everyone's family is read from who bore whom and who married whom: spouse, parents, children,
//   brothers and sisters, grandparents and grandchildren, uncles and aunts, nephews and nieces, cousins, and
//   the spouse's parents. Relatives get on better when they meet, mourn each other, come to each other's
//   weddings, and move together.
// * A church: every town of thirty people builds one (a nave of pews, an altar, lamps, a door to the square).
//   On the seventh day of every week, from nine to eleven, the townsfolk go to service: it eases grief and
//   brings them together.
// * Weddings: a couple who have courted are engaged, and marry the next day at ten in their town's church
//   (on its square if it has none). The bride wears white, the groom dark; their family and friends come as
//   guests, flowers are laid at the door, and at noon they are married (and move in together).
// * Prisoners: when the war is over, half of the prisoners stay with the nation that took them, and their
//   family and relatives come to join them there (the other half go home).

public struct Wedding: Codable, Equatable {
    public var a: Int, b: Int
    public var town: Int
    public var at: Double                  // the ceremony begins (it lasts two hours)
    /// What the two wore before (they are dressed for the day and changed back after).
    public var shirtA: String?, shirtB: String?
    public var dressed: Bool?
}

extension Society {
    static let familyText: [String: (String, String)] = [
        "engaged": ("%@ and %@ are engaged: the wedding is tomorrow at ten in %@", "%@ 和 %@ 订婚了：明天上午十点在%@举行婚礼"),
        "wedding": ("%@ and %@ were married in %@ before %@ guests", "%@ 和 %@ 在%@举行了婚礼，%@ 位亲友到场"),
        "church_built": ("%@ consecrated its church", "%@ 的教堂落成了"),
        "defected": ("%@ stayed with %@ after the war, and %@ of their family and relatives came to join them", "战后 %@ 留在了%@，并带着 %@ 位家人和亲属一同加入"),
        "t_wedding": ("I married %@ today!", "今天我和%@结婚了！"),
        "t_guest": ("We went to %@'s wedding.", "我们参加了%@的婚礼。"),
        "t_church": ("The service did me good.", "做完礼拜，心里踏实多了。"),
        "t_family": ("It was good to see %@ again.", "又见到%@了，真好。"),
        "t_defect": ("We will make our home here now.", "我们以后就在这里安家了。"),
        "church": ("church", "教堂"),
    ]

    // MARK: kin

    /// A person's family and relatives, each with what they are to them (nearest first).
    public func kin(of a: Agent) -> [(agent: Agent, relation: String)] {
        var out: [(Agent, String)] = []
        var seen: Set<Int> = [a.id]
        func add(_ id: Int, _ rel: (Agent) -> String) {
            guard id != 0, !seen.contains(id), let k = agents[id] else { return }
            seen.insert(id); out.append((k, rel(k)))
        }
        func g(_ k: Agent, _ m: String, _ f: String) -> String { k.female ? f : m }
        let z = zh
        add(a.partner) { g($0, z ? "丈夫" : "husband", z ? "妻子" : "wife") }
        add(a.father) { _ in z ? "父亲" : "father" }
        add(a.mother) { _ in z ? "母亲" : "mother" }
        for c in a.children { add(c) { g($0, z ? "儿子" : "son", z ? "女儿" : "daughter") } }
        let parents = [a.mother, a.father].compactMap { agents[$0] }
        for p in parents { for c in p.children { add(c) { g($0, z ? "兄弟" : "brother", z ? "姐妹" : "sister") } } }
        for p in parents { for gp in [p.mother, p.father] { add(gp) { g($0, z ? "祖父" : "grandfather", z ? "祖母" : "grandmother") } } }
        for c in a.children.compactMap({ agents[$0] }) { for gc in c.children { add(gc) { g($0, z ? "孙子" : "grandson", z ? "孙女" : "granddaughter") } } }
        // uncles and aunts (the parents' brothers and sisters), and their children, the cousins
        var piblings: [Agent] = []
        for p in parents { for gp in [p.mother, p.father].compactMap({ agents[$0] }) { for u in gp.children where u != p.id {
            if let x = agents[u], !seen.contains(u) { piblings.append(x) }
            add(u) { g($0, z ? "叔伯舅舅" : "uncle", z ? "姑姨" : "aunt") }
        } } }
        // nephews and nieces (brothers' and sisters' children)
        for p in parents { for sib in p.children where sib != a.id { for nn in agents[sib]?.children ?? [] { add(nn) { g($0, z ? "侄子外甥" : "nephew", z ? "侄女外甥女" : "niece") } } } }
        for u in piblings { for c in u.children { add(c) { g($0, z ? "堂表兄弟" : "cousin", z ? "堂表姐妹" : "cousin") } } }
        if let sp = agents[a.partner] { for pil in [sp.father, sp.mother] { add(pil) { g($0, z ? "岳父公公" : "father-in-law", z ? "岳母婆婆" : "mother-in-law") } } }
        return out.map { (agent: $0.0, relation: $0.1) }
    }

    /// Are these two relatives (anything `kin` names)?
    public func isKin(_ a: Agent, _ b: Agent) -> Bool { related(a, b) || kin(of: a).contains { $0.agent.id == b.id } }

    // MARK: church

    /// The town's church, if it has one finished.
    func church(_ s: Settlement) -> Building? { s.buildings.first { $0.type == "church" && $0.done } }

    /// Is it time for service (the seventh day of the week, nine to eleven)?
    var serviceTime: Bool {
        let day = Int(world.time / MP.daySeconds), h = world.hour
        return day % 7 == 6 && h >= 9 && h < 11
    }

    /// A seat in the church for someone (a pew in the nave, by their number).
    func pew(_ c: Building, for a: Agent) -> TilePos {
        let row = a.id % 5, side = a.id % 2
        return TilePos(c.x + (side == 0 ? 2 : c.w - 3), c.y + 4 + row * 2)
    }

    // MARK: weddings

    /// A couple who have courted are engaged: their wedding is the next day at ten, in their town.
    func engage(_ a: Agent, _ b: Agent) {
        var list = realm.weddings ?? []
        guard !list.contains(where: { [$0.a, $0.b].contains(a.id) || [$0.a, $0.b].contains(b.id) }), let s = settlements[a.sid] else { return }
        let day = (world.time / MP.daySeconds).rounded(.down) + 1
        list.append(Wedding(a: a.id, b: b.id, town: s.id, at: day * MP.daySeconds + 10 * MP.daySeconds / 24))
        realm.weddings = list
        emit("engaged", [a.name(zh: zh), b.name(zh: zh), venueName(s)], a.pos)
    }

    func venueName(_ s: Settlement) -> String { church(s) != nil ? s.name(zh: zh) + (zh ? "教堂" : " church") : s.name(zh: zh) + (zh ? "广场" : " square") }

    /// Where the wedding is held: before the altar, or on the square.
    func venue(_ s: Settlement) -> TilePos {
        if let c = church(s) { return TilePos(c.x + c.w / 2, c.y + 2) }
        return s.center + TilePos(0, 1)
    }

    /// The wedding someone has a part in now (the couple, or a guest: kin, or a friend), if it is under way.
    func weddingNow(for a: Agent) -> (Wedding, couple: Bool)? {
        for w in realm.weddings ?? [] where world.time >= w.at - Society.hour / 2 && world.time < w.at + 2 * Society.hour && a.sid == w.town {
            if a.id == w.a || a.id == w.b { return (w, true) }
            guard let x = agents[w.a], let y = agents[w.b] else { continue }
            if isKin(a, x) || isKin(a, y) || (a.rel[x.id] ?? 0) > 0.3 || (a.rel[y.id] ?? 0) > 0.3 { return (w, false) }
        }
        return nil
    }

    /// Weddings move on with the hours: the couple dressed, the flowers laid; at noon they are married.
    func weddingsHourly() {
        guard var list = realm.weddings, !list.isEmpty else { return }
        let now = world.time
        var keep: [Wedding] = []
        for var w in list {
            guard let a = agents[w.a], let b = agents[w.b], let s = settlements[w.town], !s.abandoned else { continue }   // called off
            if now >= w.at - Society.hour && w.dressed != true {
                // dressed for the day: the bride in white, the groom in dark; flowers at the door
                w.shirtA = a.look.shirt; w.shirtB = b.look.shirt
                a.look.shirt = a.female ? "#fbfaf6" : "#2a2a34"; b.look.shirt = b.female ? "#fbfaf6" : "#2a2a34"
                w.dressed = true
                let v = venue(s)
                for (dx, dy) in [(-2, 1), (2, 1), (-2, 3), (2, 3)] {
                    let t = v + TilePos(dx, dy)
                    if world.tile(2, t.x, t.y) == 0 && world.tile(3, t.x, t.y) == 0 { world.setTile(3, t.x, t.y, content.tid(dx < 0 ? "flower_red" : "flower_yellow")) }
                }
            }
            if now >= w.at + 2 * Society.hour {                 // (game hours: a day is 1200 s)
                // married
                let guests = s.members.compactMap { agents[$0] }.filter { $0.id != a.id && $0.id != b.id && $0.task?.act == "wedding" }
                if a.partner == 0 && b.partner == 0 { pair(a, b, announce: true) }
                a.spouseSince = now; b.spouseSince = now
                if let sa = w.shirtA { a.look.shirt = sa }; if let sb = w.shirtB { b.look.shirt = sb }
                a.think(now, "t_wedding", [b.name(zh: zh)]); b.think(now, "t_wedding", [a.name(zh: zh)])
                a.grief = 0; b.grief = 0; a.fun = 0; b.fun = 0
                for g in guests { g.think(now, "t_guest", [a.name(zh: zh)]); g.social = 0; g.fun = 0; g.task = nil }
                stats.weddings = (stats.weddings ?? 0) + 1
                emit("wedding", [a.name(zh: zh), b.name(zh: zh), venueName(s), "\(guests.count)"], a.pos)
                continue
            }
            keep.append(w)
        }
        list = keep
        realm.weddings = list
    }

    /// What someone does at a wedding or a service, if one calls them now (from `decide`).
    func ceremony(_ a: Agent, _ s: Settlement) -> Bool {
        if let (w, couple) = weddingNow(for: a) {
            let v = venue(s)
            let spot: TilePos
            if couple { spot = v + TilePos(a.id == w.a ? -1 : 1, 0) }
            else { spot = church(s).map { pew($0, for: a) } ?? v + TilePos(a.id % 7 - 3, 3 + a.id % 3) }
            return go(a, s, spot, "wedding", 2.5)
        }
        if serviceTime, a.stage(world.time) != "child" || a.mother != 0, let c = church(s), a.legion == nil, a.hunger < 0.7 {
            return go(a, s, pew(c, for: a), "worship", 2.5)
        }
        return false
    }

    /// After the service: grief eased, people brought together.
    func worshipped(_ a: Agent) {
        a.grief = max(0, a.grief - 0.35)
        a.social = max(0, a.social - 0.4)
        if realm.rng.unit() < 0.3 { a.think(world.time, "t_church") }
    }

    // MARK: prisoners who stay

    /// A prisoner who stays with the nation that took them: they become its own, and their family and
    /// relatives come from home to join them. Returns how many came.
    @discardableResult func defect(_ a: Agent, to captor: Int, in s: Settlement) -> Int {
        a.nation = captor
        a.captiveOf = nil; a.captiveHome = nil
        a.think(world.time, "t_defect")
        var came = 0
        for k in kin(of: a) {
            let r = k.agent
            guard r.alive, r.legion == nil, r.captiveOf == nil, r.nation != captor, let from = settlements[r.sid] else { continue }
            r.nation = captor
            if from.id != s.id { move(r, from: from, to: s) }
            r.think(world.time, "t_defect")
            came += 1
        }
        stats.defected = (stats.defected ?? 0) + 1 + came
        emit("defected", [a.name(zh: zh), realm.nation(captor)?.name(zh: zh) ?? "", "\(came)"], a.pos)
        return came
    }
}
