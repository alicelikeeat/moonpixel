import Foundation

// Nations of the civilisation layer: how they are born, grow, join, break apart, go into exile and pass
// into history; how they deal with each other; what they study; what they choose to build.
// There is no fixed number of them and no rule that brings back any particular number.

public struct CivPolity: Codable, Equatable {
    public enum Status: Int, Codable { case active = 0, exile = 1, history = 2 }
    public var id = 0
    public var nameEn = "", nameZh = "", short = "", color = "#ffffff"
    /// Emblem: shape 0...7 (shield, circle, diamond, banner, star, tower, wave, crescent) and a mark 0...11.
    public var shape = 0, mark = 0
    public var status = Status.active
    public var founded = 0.0, origin = ""                       // origin: first, city_state, colony, rebellion, refugees, player, restored, division
    public var exileSince: Double?, endedAt: Double?, mergedInto: Int?
    public var capital: Int?
    public var techs: [String] = ["farming"]
    public var progress: [String: Double] = [:]
    public var studying: String?
    public var leaning = "agri"                                 // the branch it favours
    public var treasury = 100.0, fatigue = 0.0
    public var researchToday = 0.0
    /// Figures of the day (for panels and choices).
    public var pop = 0, cityCount = 0, soldiers = 0, foodDays = 0.0, power = 0.0
    public var detailed = false                                 // also has towns at the detailed level (Society)
    public var detailPop = 0                                    // its people in those towns (counted there)
    /// Run by the computer (arms, war, peace). Cities still look after their own food and roofs either way.
    public var ai = true
    /// Its cities choose what to build themselves (off: only what they are given, as in some tests).
    public var builds = true
    public func knows(_ t: String) -> Bool { techs.contains(t) }
    public func name(zh: Bool) -> String { zh ? nameZh : nameEn }
}

public struct CivRelation: Codable, Equatable {
    public var a = 0, b = 0
    public var value = 0.0                    // -1 hostile ... 1 friendly
    public var state = 0                      // 0 peace, 1 war, 2 truce
    public var since = 0.0
    public var pact = false, pactSince = 0.0
    public var trade = 0.0                    // goods sent between them recently
    public var claim = false                  // an old quarrel over land that keeps the relation alive
    public var contact = 0.0                  // last time they touched
    public static func key(_ a: Int, _ b: Int) -> String { a < b ? "\(a)-\(b)" : "\(b)-\(a)" }
}

extension Civ {
    // MARK: - relations (only pairs that touch: neighbours, partners, enemies, old quarrels)

    public func relation(_ a: Int, _ b: Int) -> CivRelation? { relations[CivRelation.key(a, b)] }
    public func atWar(_ a: Int, _ b: Int) -> Bool { a != b && relations[CivRelation.key(a, b)]?.state == 1 }
    public func wars(of a: Int) -> [Int] { relations.values.filter { $0.state == 1 && ($0.a == a || $0.b == a) }.map { $0.a == a ? $0.b : $0.a }.sorted() }

    @discardableResult func touch(_ a: Int, _ b: Int) -> String {
        let k = CivRelation.key(a, b)
        if relations[k] == nil { var r = CivRelation(); r.a = min(a, b); r.b = max(a, b); r.since = time; relations[k] = r }
        relations[k]!.contact = time
        return k
    }

    public func declare(_ a: Int, on b: Int) {
        guard a != b, polities[a]?.status == .active, polities[b]?.status != .history else { return }
        let k = touch(a, b)
        guard relations[k]!.state != 1 else { return }
        relations[k]!.state = 1; relations[k]!.since = time; relations[k]!.pact = false
        relations[k]!.value = min(relations[k]!.value, -0.4)
        say("war", [polities[a]!.nameEn, polities[a]!.nameZh, polities[b]!.nameEn, polities[b]!.nameZh], [a, b])
    }

    public func makePeace(_ a: Int, _ b: Int) {
        let k = CivRelation.key(a, b)
        guard relations[k]?.state == 1 else { return }
        relations[k]!.state = 2; relations[k]!.since = time
        say("truce", [polities[a]?.nameEn ?? "", polities[a]?.nameZh ?? "", polities[b]?.nameEn ?? "", polities[b]?.nameZh ?? ""], [a, b])
    }

    /// Regions an enemy army stands in (trips and settlers go round them).
    public func hostileRegions(of nation: Int) -> Set<Int64> {
        var out = Set<Int64>()
        for f in forces.values where f.nation != nation && atWar(f.nation, nation) && f.layer == .ground { out.insert(f.region) }
        return out
    }

    // MARK: - nations

    static let nameA = ["Ar", "Bel", "Cor", "Dra", "Eth", "Fal", "Gal", "Hes", "Ist", "Jor", "Kal", "Lys", "Mor", "Nar", "Or", "Pyr", "Ruv", "Sar", "Tal", "Ul", "Vel", "Xan", "Yr", "Zeph"]
    static let nameB = ["adia", "enor", "imar", "ovia", "esse", "andor", "ith", "urne", "avel", "ethra", "onia", "aris"]
    static let nameAz = ["亚", "贝", "珂", "德", "艾", "法", "伽", "赫", "伊", "乔", "卡", "莱", "墨", "纳", "奥", "皮", "鲁", "萨", "塔", "乌", "维", "赞", "伊尔", "泽"]
    static let nameBz = ["迪亚", "诺尔", "玛", "维亚", "瑟", "多尔", "斯", "恩", "维尔", "瑟拉", "尼亚", "里斯"]

    /// A new nation with an id never used before, a name, a colour and an emblem of its own.
    @discardableResult public func newPolity(origin: String, near: Int64?, id: Int? = nil) -> Int {
        let nid = id ?? nextNation
        nextNation = max(nextNation, nid + 1)
        var p = CivPolity()
        p.id = nid; p.founded = time; p.origin = origin
        var h = RNG(seed: seed &* 131 &+ nid &* 7349)
        let i = h.index(Civ.nameA.count), j = h.index(Civ.nameB.count)
        p.nameEn = Civ.nameA[i] + Civ.nameB[j]; p.nameZh = Civ.nameAz[i] + Civ.nameBz[j]
        p.short = String(p.nameEn.prefix(2)).uppercased()
        // colours spread round the wheel; the emblem keeps nations apart where colours come close
        let hue = (Double(nid) * 0.618033988749895).truncatingRemainder(dividingBy: 1)
        p.color = Civ.hex(hue: hue, sat: 0.55 + 0.3 * h.unit(), val: 0.75 + 0.2 * h.unit())
        p.shape = nid % 8; p.mark = h.index(12)
        p.leaning = ["agri", "industry", "naval", "air", "mecha", "land", "info"][h.index(7)]
        polities[nid] = p
        born.append(nid)
        return nid
    }

    static func hex(hue: Double, sat: Double, val: Double) -> String {
        let h6 = hue * 6, i = Int(h6) % 6, f = h6 - Double(Int(h6))
        let p = val * (1 - sat), q = val * (1 - sat * f), t = val * (1 - sat * (1 - f))
        let (r, g, b) = [(val, t, p), (q, val, p), (p, val, t), (p, q, val), (t, p, val), (val, p, q)][i]
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    public func activePolities() -> [CivPolity] { polities.values.filter { $0.status == .active }.sorted { $0.id < $1.id } }
    public func cities(of n: Int) -> [CivCity] { cities.values.filter { $0.nation == n }.sorted { $0.id < $1.id } }
    func identityPeople(_ n: Int) -> Double { cities.keys.sorted().reduce(0.0) { $0 + Double(cities[$1]!.pop) * (cities[$1]!.culture[n] ?? 0) } }

    // MARK: - finding the world

    /// Learn a region for the first time. Done once per region, from the world seed and the region's
    /// place alone: looking again never makes new people. A fertile, empty region may hold a city-state.
    @discardableResult public func discover(_ rx: Int, _ ry: Int, gen: Generator, occupied: Bool = false) -> Bool {
        let key = MP.chunkKey(rx, ry)
        guard regions[key] == nil else { return false }
        var r = Civ.survey(gen, rx, ry, size: cfg.regionTiles)
        r.foundAt = time
        regions[key] = r
        var h = RNG(seed: gen.seed &* 977 &+ rx &* 2654435761 &+ ry &* 40503 &+ cfg.rulesVersion)
        let roll = h.unit()
        guard !occupied, r.land >= 0.5, r.fertility > 0.25, roll < cfg.cityStateChance * (0.5 + r.fertility) else { return true }
        // a city-state that was always here: its people are counted now, for the first time
        let n = newPolity(origin: "city_state", near: key)
        let adults = 20 + Int(h.unit() * 90 * r.fertility), kids = adults / 3, old = adults / 6
        let c = newCity(at: key, nation: n, people: CivPeople(adults: adults, children: kids, elders: old), firstCount: true)
        c.facilities = ["farm": max(2, adults / 3), "house": (adults + kids + old) / 6 + 1, "well": 1]
        if adults > 60 { c.facilities["granary"] = 1; c.facilities["bakery"] = 1 }
        c.stock = ["grain": Double(adults) * 15, "vegetable": Double(adults) * 2, "timber": 60, "stone": 30]
        for (k, v) in c.stock where CivFood.isFood(k) { totals.add(\.found, k, v) }
        c.cropDue = Double(day) + 3; c.cropPlots = c.has("farm")
        polities[n]!.capital = c.id
        say("city_state", [polities[n]!.nameEn, polities[n]!.nameZh, c.nameEn, c.nameZh], [n], region: key)
        return true
    }

    /// Learn every region within `radius` of a tile (the player exploring, a nation scouting).
    @discardableResult public func discover(around t: TilePos, radius: Int, gen: Generator, detailed: Set<Int64> = []) -> Int {
        let (rx, ry) = Civ.regionOf(tile: t, size: cfg.regionTiles)
        var n = 0
        for dy in -radius...radius { for dx in -radius...radius {
            let k = MP.chunkKey(rx + dx, ry + dy)
            if discover(rx + dx, ry + dy, gen: gen, occupied: detailed.contains(k)) { n += 1 }
        } }
        return n
    }

    /// A player (or anyone) founds a nation with people who are already counted somewhere: they move.
    @discardableResult public func foundNation(from city: Int, people k: Int, at key: Int64) -> Int? {
        guard let c = cities[city], regions[key]?.city == nil, regions[key].map({ $0.land >= 0.3 }) == true,
              let path = route(from: c.regionKey, to: key) else { return nil }
        let n = newPolity(origin: "player", near: key)
        var group = c.people.take(k, from: Array(6..<12))
        group.add(c.people.take(k / 3, from: Array(0..<6)))
        guard group.total >= 5 else { c.people.add(group); polities[n]!.status = .history; return nil }
        var t = CivTrip(); t.id = nextTrip; nextTrip += 1
        t.nation = n; t.from = c.id; t.to = c.id; t.route = path; t.people = group; t.settle = key
        t.cargo = takeFood(from: c, nutrition: Double(group.total) * 20)
        c.ledger.migOut += group.total; c.today.migOut += group.total; totals.migOut += group.total
        trips[t.id] = t
        return n
    }

    // MARK: - the day of nations

    func politicsDaily() {
        let cfg = self.cfg
        // what each nation is today
        for id in polities.keys.sorted() {
            guard var p = polities[id], p.status != .history else { continue }
            let mine = cities(of: id)
            p.cityCount = mine.count
            p.pop = mine.reduce(0) { $0 + ($1.detail == nil ? $1.pop : 0) }
            p.soldiers = forces.values.filter { $0.nation == id }.reduce(0) { $0 + $1.crew.total }
            let need = mine.reduce(0.0) { $0 + $1.dailyNeed }
            p.foodDays = need > 0 ? mine.reduce(0.0) { $0 + $1.foodNutrition } / need : 99
            p.power = forces.keys.sorted().reduce(0.0) { forces[$1]!.nation == id ? $0 + forcePower(forces[$1]!) : $0 } + Double(p.pop) * 0.05
            if p.capital == nil || cities[p.capital!]?.nation != id { p.capital = mine.max { $0.pop != $1.pop ? $0.pop < $1.pop : $0.id > $1.id }?.id }
            // money: work taxed, soldiers and machines paid
            let workers = mine.reduce(0) { $0 + ($1.detail == nil ? $1.people.band(1) : 0) }
            let upkeep = units.keys.sorted().reduce(0.0) { acc, k in units[k]!.nation == id && units[k]!.force != nil ? acc + units[k]!.def.upkeep : acc }
            p.treasury += Double(workers) * cfg.taxPerWorker - upkeep
            p.fatigue = max(0, p.fatigue + (wars(of: id).isEmpty ? -0.02 : 0.01))
            // landless: exile while people still hold to the name; history once they no longer do
            if mine.isEmpty && !p.detailed && p.status == .active { p.status = .exile; p.exileSince = time; say("exile", [p.nameEn, p.nameZh], [id]) }
            if !mine.isEmpty && p.status == .exile { p.status = .active; p.exileSince = nil }
            if p.status == .exile, let since = p.exileSince, (time - since) / MP.daySeconds > cfg.exileToHistoryYears * yearDays, identityPeople(id) < Double(cfg.exileMinIdentity) {
                p.status = .history; p.endedAt = time
                say("history", [p.nameEn, p.nameZh], [id])
            }
            polities[id] = p
        }
        // neighbours touch: relations exist only between nations that meet
        for c in cities.values.sorted(by: { $0.id < $1.id }) {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)] {
                guard let o = regions[MP.chunkKey(c.rx + dx, c.ry + dy)]?.city, let oc = cities[o], oc.nation != c.nation else { continue }
                touch(c.nation, oc.nation)
            }
        }
        for k in relations.keys.sorted() {
            guard var r = relations[k] else { continue }
            if r.state == 2 && (time - r.since) / MP.daySeconds > yearDays * 0.5 { r.state = 0; r.since = time }
            r.trade *= 0.95
            r.value += (r.trade > 1 ? 0.004 : 0) - (r.state == 1 ? 0.004 : 0)
            // two growing peoples pressing on the same land, with nothing to trade, come to resent each other
            let pressA = cities(of: r.a).contains { $0.crowding > 0.8 }, pressB = cities(of: r.b).contains { $0.crowding > 0.8 }
            if pressA && pressB && r.trade < 1 && !r.pact { r.value -= cfg.rivalry }
            r.value = max(-1, min(1, r.value * 0.998))
            // a pair that no longer meets, trades or quarrels is forgotten (the record stays in the news)
            let idle = (time - r.contact) / MP.daySeconds > yearDays * 2 && r.state == 0 && !r.pact && !r.claim && abs(r.value) < 0.05
            let gone = polities[r.a]?.status == .history || polities[r.b]?.status == .history
            relations[k] = (idle || gone) && r.state != 1 ? nil : r
        }
        research()
        unrestAndSecession()
        unions()
        for p in activePolities() { decide(p.id) }
    }

    // MARK: - research

    func research() {
        let cfg = self.cfg
        for id in polities.keys.sorted() {
            guard var p = polities[id], p.status == .active else { continue }
            var points = 0.0
            for c in cities(of: id) where c.detail == nil {
                let lab = c.has("laboratory") > 0 ? 3 : (c.has("institute") > 0 ? 2 : (c.has("school") > 0 ? 1 : 0))
                let staff = Double(c.has("school") * 2 + c.has("institute") * 6 + c.has("laboratory") * 8)
                let fed = 1 - c.people.hungerIndex
                points += (Double(c.people.band(1)) * 0.02 + staff) * cfg.researchPerResearcher * 10 * Double(1 + lab) * fed
            }
            p.researchToday = points
            let lab = cities(of: id).map { $0.has("laboratory") > 0 ? 3 : ($0.has("institute") > 0 ? 2 : ($0.has("school") > 0 ? 1 : 0)) }.max() ?? 0
            if p.studying == nil || p.knows(p.studying!) {
                let open = CivTech.all.filter { !p.knows($0.key) && $0.lab <= lab && $0.needs.allSatisfy(p.knows) }
                p.studying = open.min { a, b in
                    let ca = a.cost * (a.branch == p.leaning ? 0.6 : 1) * (a.branch == "agri" && p.foodDays < 20 ? 0.5 : 1)
                    let cb = b.cost * (b.branch == p.leaning ? 0.6 : 1) * (b.branch == "agri" && p.foodDays < 20 ? 0.5 : 1)
                    return ca != cb ? ca < cb : a.key < b.key }?.key
            }
            if let t = p.studying, let def = CivTech.byKey[t] {
                // what a partner or neighbour already knows is learned faster; nothing is simply handed over
                let known = relations.values.contains { r in (r.a == id || r.b == id) && r.state != 1 && (polities[r.a == id ? r.b : r.a]?.knows(t) ?? false) }
                let cost = def.cost * (known ? 1 - cfg.diffusion : 1)
                p.progress[t, default: 0] += points
                if p.progress[t]! >= cost {
                    p.techs.append(t); p.progress[t] = nil; p.studying = nil
                    say("tech", [p.nameEn, p.nameZh, def.en, def.zh], [id])
                }
            }
            polities[id] = p
        }
    }

    /// Studying a captured machine gives a head start on what made it, never the whole of it.
    func studyCaptured(_ nation: Int, _ kind: String) {
        guard var p = polities[nation], let def = CivUnitDef.byKey[kind] else { return }
        for t in def.tech where !p.knows(t) {
            let cost = CivTech.byKey[t]?.cost ?? 100
            p.progress[t] = min(cost * cfg.capturedCap, (p.progress[t] ?? 0) + cost * cfg.capturedKnowledge)
        }
        polities[nation] = p
    }

    // MARK: - loyalty, breaking away, coming together

    func unrestAndSecession() {
        let cfg = self.cfg
        for c in cities.values.sorted(by: { $0.id < $1.id }) where c.detail == nil {
            guard let p = polities[c.nation] else { continue }
            let own = c.culture[c.nation] ?? 0
            var d = 0.0
            d += cfg.unrestIdentity * (1 - own)
            d += cfg.unrestHunger * c.people.hungerIndex * 2
            if let cap = p.capital.flatMap({ cities[$0] }) { d += cfg.unrestDistance * Double(abs(cap.rx - c.rx) + abs(cap.ry - c.ry)) / 3 }
            if p.treasury < 0 { d += cfg.unrestDebt }
            d -= cfg.unrestCalm
            c.unrest = max(0, min(1.5, c.unrest + d / yearDays))
            // people slowly come to feel they belong where they are well governed
            if c.unrest < 0.3 { mixCulture(c, [c.nation: 1], 0.01) }
        }
        // cities that will not be ruled any more go their own way: one new nation per group of
        // neighbouring rebel cities of one nation, or back to an older name their people still hold to
        let rebels = cities.values.filter { $0.detail == nil && $0.unrest >= cfg.secedeUnrest && $0.pop >= cfg.rebelMinPeople && $0.id != polities[$0.nation]?.capital }.sorted { $0.id < $1.id }
        var used = Set<Int>()
        for r in rebels where !used.contains(r.id) {
            var group = [r]; used.insert(r.id)
            var i = 0
            while i < group.count {
                let g = group[i]; i += 1
                for o in rebels where !used.contains(o.id) && o.nation == g.nation && abs(o.rx - g.rx) + abs(o.ry - g.ry) <= 2 { group.append(o); used.insert(o.id) }
            }
            let old = r.nation
            var culture: [Int: Double] = [:]
            for g in group { for (k, v) in g.culture { culture[k, default: 0] += v * Double(g.pop) } }
            let lead = culture.filter { $0.key != old }.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
            let new: Int
            if let l = lead, let lp = polities[l], lp.status != .active || cities(of: l).isEmpty {
                new = l; polities[l]!.status = .active; polities[l]!.exileSince = nil; polities[l]!.endedAt = nil
                say("restored", [lp.nameEn, lp.nameZh, r.nameEn, r.nameZh], [l, old], region: r.regionKey)
            } else {
                new = newPolity(origin: "rebellion", near: r.regionKey)
                say("seceded", [polities[new]!.nameEn, polities[new]!.nameZh, polities[old]?.nameEn ?? "", polities[old]?.nameZh ?? ""], [new, old], region: r.regionKey)
            }
            for g in group { transfer(g, to: new); g.unrest = 0.3 }
            // what the cities knew and kept stays with them: the new state learns from its own schools and works
            if var np = polities[new], let op = polities[old] {
                let lab = group.contains { $0.has("institute") + $0.has("laboratory") > 0 }
                np.techs = Array(Set(np.techs + op.techs.filter { lab || (CivTech.byKey[$0]?.era ?? 0) <= 2 })).sorted()
                polities[new] = np
            }
            let k = touch(old, new); relations[k]!.value = -0.5; relations[k]!.claim = true
        }
    }

    /// A city changes hands. Its people keep their loyalties; armies inside go with whoever they serve.
    func transfer(_ c: CivCity, to n: Int) {
        let old = c.nation
        c.nation = n
        c.occupier = nil; c.occupyHours = 0
        for b in c.builds.indices { _ = b }
        if polities[n]?.capital == nil { polities[n]?.capital = c.id }
        if polities[old]?.capital == c.id { polities[old]?.capital = nil }
    }

    /// Nations that have long stood together may become one; a beaten nation with one city may submit.
    func unions() {
        let cfg = self.cfg
        for k in relations.keys.sorted() {
            guard let r = relations[k], r.pact, r.state == 0, r.value >= cfg.federateRelation,
                  (time - r.pactSince) / MP.daySeconds > cfg.federateYears * yearDays,
                  let a = polities[r.a], let b = polities[r.b], a.status == .active, b.status == .active, !a.detailed || !b.detailed else { continue }
            let (big, small) = a.pop >= b.pop ? (a.id, b.id) : (b.id, a.id)
            for c in cities(of: small) { transfer(c, to: big) }
            for f in forces.values where f.nation == small { f.nation = big }
            polities[small]!.status = .history; polities[small]!.mergedInto = big; polities[small]!.endedAt = time
            polities[big]!.techs = Array(Set(polities[big]!.techs + polities[small]!.techs)).sorted()
            relations[k] = nil
            say("federated", [polities[small]!.nameEn, polities[small]!.nameZh, polities[big]!.nameEn, polities[big]!.nameZh], [big, small])
            return
        }
        for p in activePolities() where p.cityCount == 1 && p.fatigue >= cfg.submitFatigue && !p.detailed {
            guard let foe = wars(of: p.id).compactMap({ polities[$0] }).filter({ $0.power > p.power * 3 }).max(by: { $0.power < $1.power }) else { continue }
            for c in cities(of: p.id) { transfer(c, to: foe.id) }
            for f in forces.values where f.nation == p.id { f.nation = foe.id }
            relations[CivRelation.key(p.id, foe.id)] = nil
            polities[p.id]!.status = .exile; polities[p.id]!.exileSince = time
            say("submitted", [p.nameEn, p.nameZh, foe.nameEn, foe.nameZh], [p.id, foe.id])
            return
        }
    }

    // MARK: - choices (every one costs something real)

    func decide(_ id: Int) {
        guard let p = polities[id] else { return }
        for c in cities(of: id) where c.detail == nil {
            // food first: rations, help from the nation's other cities, more fields
            if c.foodDays < 5 && c.ration == .normal && c.rationNext == nil { setRation(c, .emergency) }
            if c.foodDays > 12 && c.ration == .emergency && c.rationNext == nil { setRation(c, .normal) }
            if c.foodDays < 8, let giver = cities(of: id).filter({ $0.id != c.id && $0.detail == nil && $0.foodDays > 30 && !$0.besieged })
                .min(by: { abs($0.rx - c.rx) + abs($0.ry - c.ry) < abs($1.rx - c.rx) + abs($1.ry - c.ry) }) {
                let want = c.dailyNeed * 10
                let pending = trips.values.contains { $0.to == c.id && !$0.cargo.isEmpty }
                if !pending { ship(foodFor(giver, nutrition: want), from: giver.id, to: c.id) }
            }
            // none of our own to help: buy from a friendly neighbour that has plenty (paid, and remembered)
            if c.foodDays < 6, p.treasury > 0, !trips.values.contains(where: { $0.to == c.id && !$0.cargo.isEmpty }),
               !cities(of: id).contains(where: { $0.id != c.id && $0.foodDays > 30 }),
               let seller = cities.values.filter({ $0.nation != id && $0.detail == nil && $0.foodDays > 30 && !atWar($0.nation, id) && (relation($0.nation, id)?.value ?? 0) >= -0.1 && dist($0.regionKey, c.regionKey) <= 3 })
                   .min(by: { dist($0.regionKey, c.regionKey) != dist($1.regionKey, c.regionKey) ? dist($0.regionKey, c.regionKey) < dist($1.regionKey, c.regionKey) : $0.id < $1.id }) {
                let want = min(c.dailyNeed * 8, p.treasury / cfg.foodPrice)
                let goods = foodFor(seller, nutrition: want)
                let n = goods.keys.sorted().reduce(0.0) { $0 + goods[$1]! * (CivFood.byKey[$1]?.nutrition ?? 0) }
                if n > 0, ship(goods, from: seller.id, to: c.id) != nil {
                    polities[id]!.treasury -= n * cfg.foodPrice; polities[seller.nation]?.treasury += n * cfg.foodPrice
                    let k = touch(id, seller.nation); relations[k]!.trade += n; relations[k]!.value = min(1, relations[k]!.value + 0.02)
                }
            }
            let adults = c.people.band(1)
            let building = Set(c.builds.map { $0.facility })
            func want(_ f: String, _ cond: Bool) { if p.builds && cond && !building.contains(f) { _ = build(f, in: c) } }
            // the capital's schools come before anything that can wait: they are what the future is made of
            let big = c.id == p.capital
            want("school", p.knows("writing") && c.has("school") == 0 && c.pop > 30)
            want("institute", big && p.knows("metallurgy") && c.has("institute") == 0)
            want("laboratory", big && p.knows("electricity") && c.has("laboratory") == 0)
            want("farm", c.foodDays < 30 && Double(adults) > c.jobs + cfg.plotWorkers)
            want("house", c.crowding > 0.9)
            want("well", c.thirst > 0.05)
            want("granary", c.pop > 60 && c.has("granary") == 0)
            want("bakery", c.pop > 80 && c.has("bakery") == 0)
            want("pasture", p.knows("husbandry") && c.has("pasture") < c.pop / 80)
            want("fishery", p.knows("fishing") && (regions[c.regionKey]?.coast ?? false) && c.has("fishery") < 1 + c.pop / 150)
            want("clinic", p.knows("medicine") && c.has("clinic") < c.pop / 150)
            want("school", p.knows("writing") && c.has("school") == 0 && c.pop > 40)

            want("mine", p.knows("metallurgy") && c.has("mine") < 2 && (regions[c.regionKey]?.ore ?? 0) > 0.2)
            want("steelworks", p.knows("steel") && c.has("steelworks") == 0 && c.has("mine") > 0)
            want("factory", p.knows("machining") && c.has("factory") == 0 && c.pop > 100)
            want("plant", p.knows("electricity") && c.energyUsed > c.energyMade)
            want("oilwell", p.knows("oil") && (regions[c.regionKey]?.oil ?? 0) > 0.3 && c.has("oilwell") == 0)
            want("refinery", p.knows("oil") && c.has("oilwell") > 0 && c.has("refinery") == 0)
            want("greenhouse", p.knows("greenhouse") && c.foodDays < 20)
            want("ration_works", p.knows("preserving") && big && c.has("ration_works") == 0)
            want("barracks", big && c.has("barracks") == 0 && c.pop > 60)
            // a crowded, settled city sends people to found another where the land is free
            // (a choice weighed against building more houses: open land nearby and a full town tip it)
            if c.crowding > 0.85 && c.pop > 100 && c.foodDays > 15 && rng.unit() < 0.1 && !trips.values.contains(where: { $0.from == c.id && $0.settle != nil }) {
                if let site = freeSite(near: c) { _ = settle(from: c, at: site) }
            }
        }
        if p.ai { warChoices(id) }
    }

    func foodFor(_ c: CivCity, nutrition want: Double) -> [String: Double] {
        var out: [String: Double] = [:], left = want
        for k in CivFood.eatOrder.reversed() where left > 0 {
            guard let f = CivFood.byKey[k] else { continue }
            let u = min(c.free(k), left / f.nutrition); if u > 0 { out[k] = u; left -= u * f.nutrition }
        }
        return out
    }

    /// A new ration takes a day to reach every kitchen (so it cannot flicker).
    public func setRation(_ c: CivCity, _ r: CivRation) {
        guard c.ration != r else { c.rationNext = nil; return }
        c.rationNext = r; c.rationAt = time + cfg.policyDelayDays * MP.daySeconds
    }

    /// Start a facility: all its materials are taken at once, or nothing is.
    @discardableResult public func build(_ f: String, in c: CivCity) -> Bool {
        guard let def = CivFacility.byKey[f], def.tech == nil || knows(c.nation, def.tech!) else { return false }
        if def.needs == "coast" && !(regions[c.regionKey]?.coast ?? false) { return false }
        if def.needs == "deep" && (regions[c.regionKey]?.deep ?? 0) < 0.3 { return false }
        guard def.cost.allSatisfy({ c.free($0.key) >= $0.value }) else { return false }
        for (k, v) in def.cost { c.stock[k, default: 0] -= v; c.today.add(\.used, k, v); c.ledger.add(\.used, k, v) }
        c.builds.append(CivBuild(facility: f, daysLeft: 2 + Double(def.workers) / 4))
        return true
    }

    func freeSite(near c: CivCity) -> Int64? {
        var best: (Int64, Double)?
        for dy in -2...2 { for dx in -2...2 where abs(dx) + abs(dy) >= 1 {
            let k = MP.chunkKey(c.rx + dx, c.ry + dy)
            guard let r = regions[k], r.city == nil, r.land >= 0.5 else { continue }
            let score = r.fertility - 0.1 * Double(abs(dx) + abs(dy)) + (r.river ? 0.2 : 0)
            if best == nil || score > best!.1 || (score == best!.1 && k < best!.0) { best = (k, score) }
        } }
        return best?.0
    }

    @discardableResult func settle(from c: CivCity, at key: Int64) -> Int? {
        guard let path = route(from: c.regionKey, to: key, avoid: hostileRegions(of: c.nation)) else { return nil }
        var group = c.people.take(24, from: Array(6..<12))
        group.add(c.people.take(8, from: Array(0..<6)))
        guard group.total >= 10 else { c.people.add(group); return nil }
        var t = CivTrip(); t.id = nextTrip; nextTrip += 1
        t.nation = c.nation; t.from = c.id; t.to = c.id; t.route = path; t.people = group; t.settle = key
        var cargo = takeFood(from: c, nutrition: Double(group.total) * 25)
        for k in ["timber", "stone"] { let u = min(c.free(k), 40); if u > 0 { c.stock[k, default: 0] -= u; cargo[k] = u } }
        t.cargo = cargo
        c.ledger.migOut += group.total; c.today.migOut += group.total; totals.migOut += group.total
        c.sick = min(c.sick, c.pop)
        trips[t.id] = t
        return t.id
    }

    /// Facilities going up get a day's work; what is done opens.
    func finishBuilds(_ c: CivCity) {
        for i in c.builds.indices { c.builds[i].daysLeft -= 1 }
        for b in c.builds where b.daysLeft <= 0 { c.facilities[b.facility, default: 0] += 1 }
        c.builds.removeAll { $0.daysLeft <= 0 }
    }
}
