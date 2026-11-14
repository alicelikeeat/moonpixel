import Foundation

/// Cities with a character of their own, landmarks that do something, one
/// capital per nation - and a chronicle that remembers it all by event number.
public struct Chron: Codable {
    public var id = 0
    public var t = 0.0
    public var kind = "", text = ""
    public var nations: [Int] = []
    public var city: Int?
    public var x = 0.0, y = 0.0
    public var cause = "", result = ""
    public var major = false
}

public struct CapitalMove: Codable, Equatable { public var to: Int; public var since: Double; public var paid: Bool }

extension Society {
    // MARK: chronicle
    static let majorKinds: Set<String> = ["war", "truce", "peace", "captured", "fell", "unified", "split", "revived", "submitted", "pact", "alliance_broken", "leader_died",
                                          "capital_lost", "capital_moved", "capital_restored", "capital_named", "city_founded", "siege", "repelled", "battle", "law", "restart", "resettled",
                                          "town_defect", "wedding_player", "breach", "palace_ruined"]

    /// Record an event. Ids only ever go up, so "what is new since id N" is always answerable.
    @discardableResult func chronicle(_ kind: String, _ text: String, _ pos: Vec2, nations: [Int] = [], city: Int? = nil, cause: String = "", result: String = "") -> Int {
        let id = (realm.nextEvent ?? 0) + 1
        realm.nextEvent = id
        var c = Chron()
        c.id = id; c.t = world.time; c.kind = kind; c.text = text; c.nations = nations; c.city = city; c.x = pos.x; c.y = pos.y
        c.cause = cause; c.result = result; c.major = Society.majorKinds.contains(kind)
        var list = realm.chron ?? []
        list.append(c)
        // ordinary news fades quickly; history is kept longer, in the same compact form
        let cfg = realm.cfg
        let minor = list.filter { !$0.major }.count
        if minor > cfg.maxNews { var drop = minor - cfg.maxNews; list.removeAll { e in if !e.major && drop > 0 { drop -= 1; return true }; return false } }
        let major = list.count - min(minor, cfg.maxNews)
        if major > cfg.maxHistory { var drop = major - cfg.maxHistory; list.removeAll { e in if e.major && drop > 0 { drop -= 1; return true }; return false } }
        realm.chron = list
        return id
    }

    public var lastEventID: Int { realm.nextEvent ?? 0 }
    public func events(after id: Int) -> [Chron] { (realm.chron ?? []).filter { $0.id > id } }

    public struct ChronView { public var entry: Chron; public var place: String; public var gone: Bool }
    /// History, newest first, with where it happened - or that the place is no more.
    public func chronicleView(majorOnly: Bool = false, limit: Int = 80) -> [ChronView] {
        (realm.chron ?? []).reversed().filter { !majorOnly || $0.major }.prefix(limit).map { e in
            var place = "", gone = false
            if let sid = e.city {
                if let s = settlements[sid], !s.abandoned { place = cityName(s) } else { gone = true; place = settlements[sid].map { cityName($0) } ?? "" }
            }
            return ChronView(entry: e, place: place, gone: gone)
        }
    }

    // MARK: city character
    public func cityName(_ s: Settlement) -> String { s.cityName ?? s.name(zh: zh) }
    public func isCapital(_ s: Settlement) -> Bool { realm.nations.contains { $0.capital == s.id } }

    static let landmarkSpecs: [String: RoomSpec] = [
        "palace": RoomSpec(w: 8, h: 7, wall: "wall_stone", floor: "brick_floor", items: [(3, 1, "throne"), (1, 1, "banner"), (6, 1, "banner"), (1, 4, "bookshelf"), (6, 4, "table")]),
        "fortress": RoomSpec(w: 8, h: 6, wall: "wall_stone", floor: "stone_floor", items: [(1, 1, "tower"), (6, 1, "tower"), (3, 2, "anvil"), (1, 3, "bed"), (6, 3, "bed"), (4, 1, "banner")]),
        "barracks": RoomSpec(w: 6, h: 5, wall: "wall_wood", floor: "wood_floor", items: [(1, 1, "bed"), (2, 1, "bed"), (4, 1, "bed"), (4, 2, "crate")]),
        "watchtower": RoomSpec(w: 4, h: 4, wall: "wall_stone", floor: "stone_floor", items: [(1, 1, "tower"), (2, 1, "banner")]),
        "granary": RoomSpec(w: 6, h: 5, wall: "wall_wood", floor: "wood_floor", items: [(1, 1, "barrel"), (2, 1, "barrel"), (4, 1, "barrel"), (1, 3, "crate"), (4, 3, "crate")]),
        "windmill": RoomSpec(w: 4, h: 4, wall: "wall_wood", floor: "wood_floor", items: [(1, 1, "mill")]),
        "market": RoomSpec(w: 7, h: 5, wall: "fence", floor: "stone_floor", items: [(1, 1, "market_stall"), (3, 1, "market_stall"), (5, 1, "market_stall"), (1, 3, "crate"), (5, 3, "banner")]),
    ]
    public static let landmarkNames: [String: (String, String)] = [
        "palace": ("Palace", "王宫"), "fortress": ("Fortress", "要塞"), "barracks": ("Barracks", "军营"), "watchtower": ("Watchtower", "瞭望塔"),
        "granary": ("Granary", "粮仓"), "windmill": ("Windmill", "风车"), "market": ("Market", "市场"), "workshop": ("Workshop", "工坊"), "mine": ("Mine", "矿井"),
        "factory": ("Factory", "工厂"), "school": ("School", "学校"), "lab": ("Laboratory", "实验室"), "ai_center": ("AI centre", "人工智能中心"), "tavern": ("Tavern", "酒馆"),
        "warehouse": ("Warehouse", "仓库"),
    ]
    public static let kindNames: [String: (String, String)] = [
        "military": ("Stronghold", "军事重镇"), "industrial": ("Industrial city", "工业城市"), "agricultural": ("Farming city", "农业城市"),
        "trade": ("Trading city", "商贸城市"), "town": ("Town", "城镇"),
    ]

    /// What a city is known for, from what actually stands in it.
    public func cityKind(_ s: Settlement) -> String {
        let scores: [(String, Int)] = [
            ("military", 3 * s.count("fortress", done: true) + 2 * s.count("barracks", done: true) + s.count("watchtower", done: true) + s.fixture("tower") + 2 * s.fixture("ballista")),
            ("industrial", 2 * s.count("workshop", done: true) + 2 * s.count("mine", done: true) + 3 * s.count("factory", done: true) + s.fixture("furnace") + s.fixture("anvil")),
            ("agricultural", s.count("farm", done: true) / 2 + 2 * s.count("granary", done: true) + 2 * s.count("windmill", done: true) + s.fixture("mill")),
            ("trade", 3 * s.count("market", done: true) + s.fixture("market_stall")),
        ]
        guard let best = scores.max(by: { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 > $1.0 }), best.1 >= 2 else { return "town" }
        return best.0
    }

    /// The direction a town's own builders take: frontier towns arm, mining towns forge, the rest farm or trade.
    func cityFocus(_ s: Settlement) -> String {
        if s.count("mine") > 0 || s.count("workshop") > 0 { if s.id % 3 == 0 { return "industrial" } }
        let enemies = settlements.values.filter { !$0.abandoned && $0.nation != s.nation }
        let mine = towns(of: s.nation ?? 0)
        if mine.count > 1, let near = enemies.map({ ($0.center - s.center).lengthSquared }).min() {
            let closest = mine.allSatisfy { m in m === s || (enemies.map { ($0.center - m.center).lengthSquared }.min() ?? Int.max) >= near }
            if closest { return "military" }
        }
        return ["agricultural", "trade", "industrial"][s.id % 3]
    }

    /// Next landmark this town should raise, if any (called from the town planner).
    func wantedLandmark(_ s: Settlement, pop: Int) -> String? {
        if isCapital(s) && s.count("palace") == 0 && has("masonry") && pop >= 12 { return "palace" }
        if pop < 14 { return nil }
        let order: [String]
        switch cityFocus(s) {
        case "military": order = ["barracks", "watchtower", "fortress"]
        case "agricultural": order = ["granary", "windmill"]
        case "trade": order = ["market", "granary"]
        default: order = ["warehouse", "barracks"]
        }
        if !has("masonry") { return nil }
        return order.first { s.count($0) == 0 }
    }

    func styledWall(_ s: Settlement, _ wall: String) -> String {
        // each nation builds its own way: Azure in grey stone, Crimson in red brick, Golden keeps to timber longest
        guard wall != "fence", has("masonry") else { return wall }
        switch s.nation ?? 0 {
        case 2: return "wall_brick"
        case 3: return has("metalwork") ? "wall_stone" : "wall_wood"
        default: return "wall_stone"
        }
    }

    /// Flags follow the owner: after a change of hands every banner in town is re-dyed.
    func reflag(_ s: Settlement) {
        s.flagOf = s.nation
        guard let n = s.nation, n >= 1, n <= 3 else { return }
        let want = content.tid("banner_\(n)")
        let ids = Set((1...3).map { content.tid("banner_\($0)") })
        let r = realm.cfg.cityRadius
        for dy in -r...r { for dx in -r...r {
            let x = s.center.x + dx, y = s.center.y + dy
            let o = world.tile(2, x, y)
            if ids.contains(o) && o != want { world.setTile(2, x, y, want) }
        } }
    }

    /// A capital shows it: a wide square, a main street, and the nation's banner on a tall pole.
    func dressCapital(_ s: Settlement) {
        let c = s.center
        for dy in -4...4 { for dx in -4...4 where dx * dx + dy * dy <= 18 {
            let x = c.x + dx, y = c.y + dy
            if world.isLand(x, y) && world.tile(1, x, y) == 0 && world.tile(2, x, y) == 0 { world.setTile(1, x, y, T["cobble_road"]!) }
        } }
        for k in 5...12 { for x in [c.x - 1, c.x, c.x + 1] where world.isLand(x, c.y + k) && world.tile(1, x, c.y + k) == 0 && world.tile(2, x, c.y + k) == 0 { world.setTile(1, x, c.y + k, T["cobble_road"]!) } }
        let pole = c + TilePos(0, -3)
        if world.tile(2, pole.x, pole.y) == 0, let n = s.nation, n >= 1, n <= 3 { world.setTile(2, pole.x, pole.y, content.tid("banner_\(n)")) }
    }

    // MARK: capitals
    /// A capital is valid when the nation holds the city. A palace makes it fully effective.
    public func capital(of nation: Int) -> Settlement? {
        guard let id = realm.nation(nation)?.capital, let s = settlements[id], !s.abandoned, s.nation == nation else { return nil }
        return s
    }
    public func hasPalace(_ s: Settlement) -> Bool { s.count("palace", done: true) > 0 || s.fixture("throne") > 0 }

    /// Governance: 1 with a working palace in a held capital, less while the court is on the road or its hall lies in ruins.
    public func governance(_ nation: Int) -> Double {
        guard let n = realm.nation(nation), n.exileSince == nil else { return 0 }
        guard let c = capital(of: nation) else { return realm.cfg.govNoCapital }
        if n.moving != nil { return realm.cfg.govMoving }
        if c.siege != nil { return realm.cfg.govSiege }
        return hasPalace(c) ? 1 : realm.cfg.govNoPalace
    }

    func setCapital(_ nation: Int, _ s: Settlement, kind: String, cause: String) {
        guard let k = realm.ni(nation) else { return }
        if let old = realm.nations[k].capital, old != s.id, let o = settlements[old] { o.formerCapital = nation }
        realm.nations[k].capital = s.id
        realm.nations[k].moving = nil
        s.formerCapital = nil
        dressCapital(s)
        s.planT = 0
        emit(kind, [realm.nations[k].name(zh: zh), cityName(s)], s.center.center, nations: [nation], city: s.id, cause: cause, result: "capital=\(s.id)")
    }

    func bestSeat(_ nation: Int, except: Int = 0) -> Settlement? {
        towns(of: nation).filter { $0.id != except }.max { a, b in
            let sa = a.members.count + (hasPalace(a) ? 20 : 0) + (a.formerCapital == nation ? 30 : 0)
            let sb = b.members.count + (hasPalace(b) ? 20 : 0) + (b.formerCapital == nation ? 30 : 0)
            return sa != sb ? sa < sb : a.id > b.id }
    }

    /// Keep every landed nation with exactly one capital; run moves; notice ruined palaces.
    func capitalsHourly() {
        let cfg = realm.cfg
        let now = world.time
        for k in realm.nations.indices {
            let id = realm.nations[k].id
            let ts = towns(of: id)
            if ts.isEmpty {
                // in exile: no capital, but the memory of one
                if let old = realm.nations[k].capital, let o = settlements[old] { o.formerCapital = id }
                realm.nations[k].capital = nil; realm.nations[k].moving = nil
                continue
            }
            if let move = realm.nations[k].moving {
                guard let dest = settlements[move.to], !dest.abandoned, dest.nation == id else { realm.nations[k].moving = nil; continue }
                // the court moves when the cost is found and the time has passed
                if !move.paid, dest.wood >= cfg.capitalMoveWood, dest.food >= cfg.capitalMoveFood {
                    dest.wood -= cfg.capitalMoveWood; dest.food -= cfg.capitalMoveFood
                    realm.nations[k].moving!.paid = true
                }
                if realm.nations[k].moving!.paid && now - move.since >= cfg.capitalMoveYears * MP.year {
                    setCapital(id, dest, kind: "capital_moved", cause: "relocation")
                }
                continue
            }
            if capital(of: id) == nil {
                let had = realm.nations[k].capital
                let lost = had.flatMap { settlements[$0] }
                if let l = lost, !l.abandoned, l.nation != id {
                    // the capital fell while the nation lives on
                    l.formerCapital = id
                    addFatigue(id, cfg.capitalLostFatigue)
                    emit("capital_lost", [realm.nations[k].name(zh: zh), cityName(l)], l.center.center, nations: [id, l.nation ?? 0], city: l.id, cause: "captured", result: "relocating")
                }
                guard let seat = bestSeat(id) else { continue }
                if had == nil || lost == nil || lost?.abandoned == true {
                    // first capital, a capital wiped from the map, or land regained after exile
                    setCapital(id, seat, kind: had == nil && realm.nations[k].everCapital != true ? "capital_named" : "capital_restored", cause: had == nil ? "founding" : "rebuilding")
                    realm.nations[k].everCapital = true
                } else {
                    realm.nations[k].capital = nil
                    realm.nations[k].moving = CapitalMove(to: seat.id, since: now, paid: false)      // a temporary command centre until the move completes
                }
                continue
            }
            // a palace in ruins is its own misfortune, apart from losing the city
            if let c = capital(of: id), c.count("palace") > 0, !hasPalace(c), world.time >= (realm.cool["palace_ruined:\(id)"] ?? 0) {
                realm.cool["palace_ruined:\(id)"] = world.time + 2 * MP.year          // reported once, not every hour while it is rebuilt
                emit("palace_ruined", [cityName(c)], c.center.center, nations: [id], city: c.id, cause: "damage", result: "governance reduced")
            }
            // a nation may move its seat to a clearly greater city in peacetime
            if let c = capital(of: id), !realm.atWar(id), now - (realm.cool["capmove:\(id)"] ?? -1e12) >= cfg.capitalMoveCooldown * MP.year,
               let better = bestSeat(id, except: c.id), Double(better.members.count) >= Double(c.members.count) * cfg.capitalMoveRatio, better.members.count >= cfg.capitalPop {
                realm.cool["capmove:\(id)"] = now
                realm.nations[k].moving = CapitalMove(to: better.id, since: now, paid: false)
            }
        }
    }

    /// The player's petition: make this city of their nation the capital.
    public func petitionCapital(_ sid: Int) -> String? {
        let cfg = realm.cfg
        guard let s = settlements[sid], !s.abandoned else { return "nobody" }
        guard let n = s.nation, n == realm.player.nation, n != 0, let k = realm.ni(n) else { return "nation" }
        if realm.nations[k].capital == sid { return "already" }
        if realm.nations[k].moving != nil { return "moving" }
        if s.siege != nil { return "siege" }
        if now(s.cityT) { surveyTown(s) }
        if !hasPalace(s) { return "palace" }
        if s.members.count < cfg.capitalPop { return "people" }
        if s.food < Double(s.members.count) * cfg.capitalFoodPerHead { return "food" }
        realm.nations[k].moving = CapitalMove(to: sid, since: world.time, paid: false)
        realm.cool["capmove:\(n)"] = world.time
        return nil
    }
    func now(_ t: Double) -> Bool { world.time >= t }

    // MARK: cities founded by the player
    /// Turn what the player has built into a city: needs a nation, beds on floors, a store and food to start with.
    public func registerCity(at center: TilePos, name: String) -> String? {
        let cfg = realm.cfg
        let n = realm.player.nation
        if n == 0 { return "nation" }
        if world.gen.isMaze(center.x >> 5, center.y >> 5) { return "maze" }
        if settlements.values.contains(where: { !$0.abandoned && ($0.center - center).lengthSquared < cfg.cityMinGap * cfg.cityMinGap }) { return "close" }
        if livingSettlements >= world.budget.maxSettlements { return "limit" }
        var beds = 0, stores = 0
        let floors: Set<UInt8> = [content.tid("wood_floor"), content.tid("stone_floor"), content.tid("brick_floor")]
        for dy in -14...14 { for dx in -14...14 {
            let o = world.tile(2, center.x + dx, center.y + dy)
            if o == content.tid("bed") && floors.contains(world.tile(0, center.x + dx, center.y + dy)) { beds += 1 }
            if o == T["chest"] { stores += 1 }
        } }
        if beds < cfg.cityBeds { return "beds" }
        if stores < 1 { return "store" }
        if realm.player.food < cfg.cityFood { return "food" }
        realm.player.food -= cfg.cityFood
        let s = Settlement()
        s.id = nextSID; nextSID += 1
        let ni = (s.id - 1) % Society.townEn.count
        s.nameEn = Society.townEn[ni]; s.nameZh = Society.townZh[ni]
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { s.cityName = String(clean.prefix(20)) }
        s.center = center
        s.founded = world.time; s.lastFound = world.time
        s.nation = n
        s.byPlayer = true
        s.food = cfg.cityFood
        settlements[s.id] = s
        attach(s)
        surveyTown(s)
        stats.founded += 1
        emit("city_founded", [cityName(s), realm.nation(n)?.name(zh: zh) ?? ""], center.center, nations: [n], city: s.id, cause: "player", result: "beds=\(beds)")
        settle(s)
        landCheck()
        return nil
    }

    /// Households from the most crowded town of the same nation move into free housing. Nobody is invented.
    @discardableResult func settle(_ s: Settlement) -> Int {
        guard let n = s.nation else { return 0 }
        let nowT = world.time
        var room = s.freeBeds.count + s.buildings.filter { $0.type == "house" && $0.done && $0.owner == nil }.count * 3 - s.members.filter { agents[$0]?.home == -1 }.count
        if room <= 0 || s.food < 4 || s.siege != nil { return 0 }
        guard let src = towns(of: n).filter({ $0 !== s && $0.members.count >= 12 }).max(by: { a, b in
            let ha = a.members.filter { agents[$0]?.home == -1 }.count, hb = b.members.filter { agents[$0]?.home == -1 }.count
            return ha != hb ? ha < hb : a.id > b.id }) else { return 0 }
        var houses: [Int: [Agent]] = [:]
        for a in src.members.compactMap({ agents[$0] }) where a.legion == nil && a.refugee == nil && !a.travelling { houses[household(a, nowT), default: []].append(a) }
        // those without a roof go first
        let order = houses.keys.sorted { a, b in
            let ha = houses[a]!.contains { $0.home == -1 }, hb = houses[b]!.contains { $0.home == -1 }
            return ha != hb ? ha : a < b }
        var moved = 0
        for h in order {
            let fam = houses[h]!
            if fam.count > room || moved >= realm.cfg.settleBatch { continue }
            if src.members.count - fam.count < 10 { break }
            for a in fam {
                move(a, to: s)
                a.travelling = true
                a.travelTo = world.findFree(near: s.center + TilePos(a.id % 7 - 3, 2 + a.id % 3), maxR: 8).center
                moved += 1
            }
            room -= fam.count
        }
        if moved > 0 { s.planT = 0; src.planT = 0 }
        return moved
    }

    /// Landmarks at work, once an hour.
    func citiesHourly() {
        let cfg = realm.cfg
        let dty = Society.hour / MP.year
        for s in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) {
            // whatever way a town changed hands (conquest, defection, submission, division), its banners follow
            if s.flagOf != s.nation { reflag(s); s.flagOf = s.nation }
            let farms = Double(s.count("farm", done: true))
            if s.count("windmill", done: true) + s.fixture("mill") > 0 { s.food += cfg.millFood * farms }
            // markets move surplus towards same-nation towns that have less (never through a siege)
            if s.count("market", done: true) + s.fixture("market_stall") > 0, s.siege == nil {
                for o in towns(of: s.nation ?? 0) where o !== s && o.siege == nil {
                    for g in ["food", "wood", "stone"] {
                        let a = s.good(g) / Double(max(1, s.members.count)), b = o.good(g) / Double(max(1, o.members.count))
                        if a > b * 1.5 { let q = (s.good(g) - o.good(g)) * cfg.marketFlow; s.addGood(g, -q); o.addGood(g, q) }
                    }
                }
            }
            // player-founded cities keep drawing people while they have room
            if s.byPlayer == true && world.time >= (realm.cool["settle:\(s.id)"] ?? 0) {
                realm.cool["settle:\(s.id)"] = world.time + cfg.settleEvery * MP.year
                if world.time >= s.cityT { surveyTown(s) }
                settle(s)
            }
            if isCapital(s) && hasPalace(s) { s.unrest = max(0, (s.unrest ?? 0) - 0.3 * dty) }
        }
        capitalsHourly()
    }

    func fortBonus(_ s: Settlement) -> Double {
        let cfg = realm.cfg
        return 1 + cfg.fortFortress * Double(min(1, s.count("fortress", done: true))) + cfg.fortTower * Double(min(4, s.fixture("tower"))) + cfg.fortBallista * Double(min(3, s.fixture("ballista")))
            + cfg.fortWall * min(1, Double(s.walls.count) / 60)
    }

    // MARK: what the interface shows
    public struct LandmarkInfo { public var type = "", name = "", function = "", state = ""; public var pos = Vec2.zero; public var damaged = false }
    public struct CityInfo {
        public var id = 0, name = "", nation = "", color = "", kind = "", kindName = ""
        public var capital = false, former = "", byPlayer = false, siege = false
        public var pop = 0, soldiers = 0, homeless = 0, beds = 0
        public var stocks: [(String, Int)] = [], landmarks: [LandmarkInfo] = [], stations: [String] = [], history: [String] = []
        public var pos = Vec2.zero
        public var governance = 0.0, unrest = 0.0, wallCount = 0, gateCount = 0
    }

    public func cityInfo(_ sid: Int) -> CityInfo? {
        guard let s = settlements[sid] else { return nil }
        if world.time >= s.cityT && !s.abandoned { surveyTown(s) }
        var c = CityInfo()
        let nat = realm.nation(s.nation ?? 0)
        c.id = s.id; c.name = cityName(s); c.nation = nat?.name(zh: zh) ?? ""; c.color = nat?.color ?? "#ffffff"
        c.kind = cityKind(s); c.kindName = Society.kindNames[c.kind].map { zh ? $0.1 : $0.0 } ?? c.kind
        c.capital = isCapital(s); c.byPlayer = s.byPlayer == true; c.siege = s.siege != nil
        if let f = s.formerCapital, let fn = realm.nation(f) { c.former = fn.name(zh: zh) }
        c.pop = s.members.count
        c.soldiers = s.members.filter { agents[$0]?.legion != nil }.count
        c.homeless = s.members.filter { agents[$0]?.home == -1 }.count
        c.beds = s.freeBeds.count
        c.pos = s.center.center
        c.governance = governance(s.nation ?? 0); c.unrest = s.unrest ?? 0
        c.wallCount = s.walls.count; c.gateCount = s.gates.count
        for g in Recipe.goods { let v = s.good(g.0); if v >= 1 { c.stocks.append((zh ? g.2 : g.1, Int(v))) } }
        let functions: [String: (String, String)] = [
            "palace": ("governs the nation, seat of the leader", "治理全国、领袖驻地"), "fortress": ("stronger walls, larger garrison", "加固城防、扩大驻军"),
            "barracks": ("trains more soldiers", "训练更多士兵"), "watchtower": ("helps the defence", "协助防守"), "granary": ("stores far more food", "大幅增加粮食储量"),
            "windmill": ("raises farm output", "提高农田产量"), "market": ("trades surplus with other towns", "与其他城镇互通有无"), "workshop": ("makes tools, arms and engines", "制造工具、武器与器械"),
            "mine": ("brings up ore; a way underground", "出产矿石，可通往地下"), "factory": ("produces wood and stone", "产出木石"), "warehouse": ("more storage", "扩大仓储"),
            "tavern": ("cooks meals, cures boredom", "制作口粮、消遣解闷"), "school": ("research", "研究"), "lab": ("research", "研究"), "ai_center": ("research, automatic farms", "研究、自动化农田"),
        ]
        for b in s.buildings.sorted(by: { $0.id < $1.id }) {
            guard let nm = Society.landmarkNames[b.type] else { continue }
            var l = LandmarkInfo()
            l.type = b.type; l.name = zh ? nm.1 : nm.0
            l.function = functions[b.type].map { zh ? $0.1 : $0.0 } ?? ""
            l.damaged = !b.done && b.placed > 0 && !b.retry.isEmpty
            l.state = b.done ? (zh ? "完好" : "intact") : (l.damaged ? (zh ? "受损，修复中" : "damaged, under repair") : (zh ? "建造中" : "under construction"))
            l.pos = TilePos(b.x + b.w / 2, b.y + b.h / 2).center
            c.landmarks.append(l)
        }
        for (slot, why) in (s.pause ?? [:]).sorted(by: { $0.key < $1.key }) {
            let station = String(slot.split(separator: "#")[0])
            let reason: String
            if why.hasPrefix("input:") { reason = (zh ? "缺 " : "lacks ") + Recipe.goodName(String(why.dropFirst(6)), zh: zh) }
            else { reason = ["full": (zh ? "仓库已满" : "store full"), "worker": (zh ? "缺人手" : "no worker"), "idle": (zh ? "暂无需求" : "nothing wanted")][why] ?? why }
            c.stations.append((content.tile(content.tid(station)).map { zh ? $0.nameZh : $0.nameEn } ?? station) + "：" + reason)
        }
        c.history = (realm.chron ?? []).filter { $0.city == sid }.suffix(6).reversed().map { "\(Int($0.t / MP.year) + 1): " + $0.text }
        return c
    }

    /// Cities to label: from far away only capitals and big cities, close up all of them.
    public func cityLabels(far: Bool) -> [(id: Int, name: String, nation: Int, capital: Bool, kind: String, pos: Vec2, siege: Bool)] {
        settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }.compactMap { s in
            let cap = isCapital(s)
            if far && !cap && s.members.count < 30 { return nil }
            return (s.id, cityName(s), s.nation ?? 0, cap, cityKind(s), s.center.center, s.siege != nil)
        }
    }
}
