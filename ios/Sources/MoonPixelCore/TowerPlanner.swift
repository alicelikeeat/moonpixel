import Foundation

// Cities build for themselves. Each city, now and then, looks at what it lacks, and if something is worth
// doing proposes a few ways of doing it, keeps the ones that pass every hard rule, picks the best by a
// score that weighs what it gives against what it costs, reserves the materials and builds it floor by
// floor. Every decision is written down with its reason. Nothing here is learned from a model: it is a
// grammar of floor plans, a set of checks and a score, the same every time for the same city and day.
//
// Order of a decision: needs -> site -> candidate blueprints -> hard checks -> score -> reserve -> build
// (structure, fit-out, inspection, in use) -> people move in -> the next look sees whether it helped.

public enum Blueprint {
    /// Floor plans by grammar: a core (stairs and lift shaft), a way round it, rooms off the way, columns
    /// on a grid, fittings by use. Three layouts (central core, side core, courtyard) and a seed vary it.
    public static func plan(use: RoomUse, w: Int, d: Int, layout: Int, seed: Int, columnsEvery: Int = 4) -> FloorPlan {
        var parts = [Part](repeating: .slab, count: w * d)
        func set(_ x: Int, _ y: Int, _ p: Part) { if x >= 0 && y >= 0 && x < w && y < d { parts[y * w + x] = p } }
        func get(_ x: Int, _ y: Int) -> Part { x >= 0 && y >= 0 && x < w && y < d ? parts[y * w + x] : .empty }
        // outer walls with windows
        for x in 0..<w { set(x, 0, x % 3 == 1 ? .window : .wall); set(x, d - 1, x % 3 == 1 ? .window : .wall) }
        for y in 0..<d { set(0, y, y % 3 == 1 ? .window : .wall); set(w - 1, y, y % 3 == 1 ? .window : .wall) }
        // the core
        let cx = layout == 1 ? 1 : w / 2 - 1, cy = layout == 2 ? 1 : d / 2 - 1
        set(cx, cy, .stair); set(cx + 1, cy, .shaft); set(cx, cy + 1, .stair); set(cx + 1, cy + 1, .shaft)
        // a courtyard: an open well in the middle (an atrium), the rooms around it
        if layout == 2 && w >= 10 && d >= 10 { for y in (d / 2 - 1)...(d / 2) { for x in (w / 2 - 1)...(w / 2) { set(x, y, .empty) } } }
        // the way round: a ring corridor two cells in from the walls (already slab); rooms are the bands between
        var rooms: [Room] = []
        let bands: [(Int, Int, Int, Int)] = [(1, 1, w - 2, 1), (1, d - 2, w - 2, d - 2)]       // north and south strips
        var rng = RNG(seed: seed &* 31 &+ w &* 7 &+ d)
        for (bi, b) in bands.enumerated() {
            // split the strip into rooms 3..5 wide, each with a door onto the corridor side
            var x = b.0
            while x + 2 < b.2 {
                let wid = 3 + rng.index(3)
                let x1 = min(b.2, x + wid - 1)
                var cells: [Int] = []
                for xx in x...x1 { let i = b.1 * w + xx; if parts[i] == .slab { cells.append(i) } }
                // a scrap of a room (beside the core) is left as floor to walk on
                guard cells.count >= 2 else { x = x1 + 1; continue }
                // walls between rooms
                if x1 + 1 < b.2 && parts[b.1 * w + x1 + 1] == .slab { set(x1 + 1, b.1, .wall) }
                // fittings
                var cap = 0
                // the door first (never a fitting on it), then fittings on every other cell after it
                let door = cells[0]
                for (k, i) in cells.enumerated() where k % 2 == 1 {
                    switch use {
                    case .home: parts[i] = .bed; cap += 1
                    case .farm: parts[i] = .field; cap += 1
                    case .store: parts[i] = .shelf; cap += 1
                    case .works, .pump: parts[i] = .machine; cap += 1
                    case .defence: parts[i] = .battlement; cap += 1
                    case .dock: parts[i] = .dock; cap += 1
                    case .lobby: break
                    }
                }
                rooms.append(Room(use: use, cells: cells, entrance: door, capacity: use == .lobby ? cells.count : cap))
                x = x1 + 2
            }
            _ = bi
        }
        // columns on a grid, on the walls (so they never block a way through)
        var cols = 0
        for y in stride(from: 0, to: d, by: columnsEvery) { for x in stride(from: 0, to: w, by: columnsEvery) {
            if get(x, y) == .wall || get(x, y) == .window { set(x, y, .column); cols += 1 }
        } }
        for (x, y) in [(0, 0), (w - 1, 0), (0, d - 1), (w - 1, d - 1)] { set(x, y, .column) }
        if use == .lobby { set(w / 2, d - 1, .door) }                // the street door
        let key = "\(use.rawValue)-\(w)x\(d)-L\(layout)-c\(columnsEvery)-s\(seed % 8)"
        return FloorPlan(key: key, w: w, d: d, height: 4, parts: parts, rooms: rooms, use: use)
    }

    /// Cells people walk on.
    static func walkable(_ p: Part) -> Bool { [.slab, .door, .stair, .shaft, .field].contains(p) }

    /// Hard checks on one plan: every room is reached from the stairs; every fitting can be stood at;
    /// there is a stair. Returns what is wrong (empty: it passes).
    public static func check(_ p: FloorPlan) -> [String] {
        var out: [String] = []
        let stairs = p.parts.indices.filter { p.parts[$0] == .stair }
        if stairs.isEmpty { out.append("no stair") }
        var seen = Set<Int>(stairs), q = stairs, h = 0
        while h < q.count {
            let i = q[h]; h += 1
            let x = i % p.w, y = i / p.w
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < p.w, ny < p.d else { continue }
                let j = ny * p.w + nx
                if !seen.contains(j) && walkable(p.parts[j]) { seen.insert(j); q.append(j) }
            }
        }
        for (k, r) in p.rooms.enumerated() {
            if !seen.contains(r.entrance) { out.append("room \(k) (\(r.use.rawValue)) cannot be reached from the stairs") }
            for i in r.cells where [.bed, .machine, .shelf, .battlement, .dock].contains(p.parts[i]) {
                let x = i % p.w, y = i / p.w
                let standing = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { (dx, dy) in let nx = x + dx, ny = y + dy; return nx >= 0 && ny >= 0 && nx < p.w && ny < p.d && seen.contains(ny * p.w + nx) }
                if !standing { out.append("a fitting in room \(k) has no room to work at it"); break }
            }
        }
        return out
    }
}

public struct TowerProposal: Equatable {
    public var reasonEn: String, reasonZh: String
    public var kind: String                     // new_tower, add_floors, lift, sky_lobby, farm_floors, defence, pump
    public var score: Double
}

extension Civ {
    /// The material a nation can build towers in (the best it knows).
    /// The best material the nation knows and the city can pay for a few floors of now (else the next one down).
    func bestMaterial(_ n: Int, city c: CivCity? = nil) -> Int {
        let sample = Blueprint.plan(use: .home, w: 12, d: 10, layout: 0, seed: 0)
        for m in stride(from: TowerRules.materialTech.count - 1, through: 0, by: -1) {
            guard TowerRules.materialTech[m].map({ knows(n, $0) }) ?? true else { continue }
            guard let c = c else { return m }
            let cost = TowerRules.cost(sample, material: m)
            if cost.allSatisfy({ c.free($0.key) >= $0.value * 3 }) { return m }
        }
        return 0
    }

    /// What a city lacks that a building could give, with the reason in words.
    public func towerNeeds(_ c: CivCity) -> [TowerProposal] {
        var out: [TowerProposal] = []
        let ts = towers(of: c.id)
        let beds = Int(Double(c.has("house")) * cfg.housePeople + 18) + c.towerBeds
        let short = c.pop - beds
        if short >= 24 {
            let canGrow = ts.contains { t in growth(t) > 0 && !t.protected }
            out.append(TowerProposal(reasonEn: "\(short) people have no bed" + (canGrow ? "; a tower can take more floors" : "; a new tower is needed"),
                                     reasonZh: "缺 \(short) 个床位" + (canGrow ? "，现有塔楼可以加建" : "，需要新建塔楼"),
                                     kind: canGrow ? "add_floors" : "new_tower", score: Double(short)))
        }
        // short of food up the towers while the stores are full: carrying, not growing, is the problem
        let hungryUp = ts.flatMap { $0.floors }.contains { $0.people.total > 0 && $0.coverage < 0.95 }
        if hungryUp && c.foodDays > 8 {
            let tall = ts.max { $0.floors.count < $1.floors.count }
            let lobby = (tall?.floors.count ?? 0) > 60 && (tall?.skyLobbyEvery ?? 0) == 0
            out.append(TowerProposal(reasonEn: "food is in the stores but does not get up the towers: " + (lobby ? "add sky lobbies" : "add a bank of lifts"),
                                     reasonZh: "仓库有粮但运不上楼：" + (lobby ? "增设空中转换层" : "加装一组电梯"), kind: lobby ? "sky_lobby" : "lift", score: 80))
        } else if c.foodDays < 10 && c.coverage < 1 && knows(c.nation, "greenhouse") && !ts.isEmpty {
            out.append(TowerProposal(reasonEn: "the city grows too little food: vertical farm floors", reasonZh: "粮食产量不足：加建垂直农场层", kind: "farm_floors", score: 60))
        }
        // dry floors: a pump room
        if ts.contains(where: { t in t.floors.contains { $0.stage == .inUse && $0.water < 1 } }) {
            out.append(TowerProposal(reasonEn: "upper floors have no water: a pump room", reasonZh: "高层缺水：加建水泵层", kind: "pump", score: 70))
        }
        if !wars(of: c.nation).isEmpty && !ts.isEmpty && !ts.contains(where: { t in t.floors.contains { plan($0)?.use == .defence } }) {
            out.append(TowerProposal(reasonEn: "at war: a defence platform on the tallest tower", reasonZh: "处于战争：在最高塔楼顶建防御平台", kind: "defence", score: 40))
        }
        return out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.kind < $1.kind }
    }

    /// How many more floors a tower's lowest floor could carry at its weakest point (0 if none).
    func growth(_ t: Tower) -> Int {
        restructure(t)
        guard let p = t.floors.last.flatMap({ plan($0) }) else { return 0 }
        let per = p.weight + Double(p.capacity(.home)) * TowerRules.personLoad
        var room = Double.infinity
        for i in t.floors.indices where t.strength[i] != .infinity { room = min(room, (t.strength[i] / TowerRules.failure * 0.9 - t.load[i]) / per) }
        return room == .infinity ? 50 : max(0, Int(room))
    }

    /// Look, decide, start. At most one decision a city every few days, and only for a real need.
    func planTowers(_ c: CivCity) {
        guard let p = polities[c.nation], p.builds, c.detail == nil else { return }
        advanceConstruction(c)
        if let last = c.lastPlanBox, day - last < 4 { return }
        guard let need = towerNeeds(c).first, need.score >= 20 else { return }
        if propose(need, in: c) { c.lastPlanBox = day }
    }

    /// Carry out a decision: blueprints are generated, checked and scored; the best one is started.
    @discardableResult public func propose(_ need: TowerProposal, in c: CivCity) -> Bool {
        let m = bestMaterial(c.nation, city: c)
        let reg = regions[c.regionKey]
        switch need.kind {
        case "new_tower":
            // a few sites, a few layouts: keep what passes, score what is left
            var best: (Tower, Double)?
            let lots = towers(of: c.id).count
            guard lots < 16 else { return false }                         // the city's ground is built out
            for layout in 0..<3 {
                for (w, d) in [(12, 10), (14, 12), (10, 10)] {
                    let lobby = Blueprint.plan(use: .lobby, w: w, d: d, layout: layout, seed: day)
                    let home = Blueprint.plan(use: .home, w: w, d: d, layout: layout, seed: day &+ c.id, columnsEvery: m >= 2 ? 4 : 3)
                    guard Blueprint.check(home).isEmpty, Blueprint.check(lobby).isEmpty else { continue }
                    // terrain: river towns favour courtyards, steep ground narrow footprints
                    var score = Double(home.capacity(.home)) / Double(w * d)
                    if reg?.river == true && layout == 2 { score += 0.15 }
                    if (reg?.mountain ?? 0) > 0.3 && w * d <= 100 { score += 0.15 }
                    let t = Tower(base: Cell3(Int64(c.rx * cfg.regionTiles + 16 + (lots % 4) * 20), Int64(c.ry * cfg.regionTiles + 16 + (lots / 4) * 20), 0))
                    t.w = w; t.d = d; t.material = m; t.style = ["central", "side", "courtyard"][layout]
                    towerIndex.plans[lobby.key] = lobby; towerIndex.plans[home.key] = home
                    t.floors = [TowerFloor(z: 0, plan: lobby.key)]
                    let n = min(8, max(2, need.score >= 24 ? Int(need.score) / max(1, home.capacity(.home)) + 1 : 2))
                    for k in 1...n { t.floors.append(TowerFloor(z: Int64(k * 4), plan: home.key)) }
                    if best == nil || score > best!.1 { best = (t, score) }
                }
            }
            guard let (t, _) = best else { c.planNote = "no layout passed the checks"; return false }
            t.id = towerIndex.nextTower; towerIndex.nextTower += 1
            t.city = c.id; t.nation = c.nation; t.founded = day
            t.nameEn = c.nameEn + " Tower \(t.id)"; t.nameZh = c.nameZh + "塔楼\(t.id)"
            t.history.append("d\(day): planned (\(t.style), \(TowerRules.materialNames[t.material].0)): " + need.reasonEn)
            towerIndex.towers[t.id] = t; towerIndex.index(t)
            say("tower_planned", [t.nameEn, t.nameZh, need.reasonEn, need.reasonZh], [c.nation], region: c.regionKey)
            return true
        case "add_floors", "farm_floors", "pump", "defence":
            guard let t = towers(of: c.id).filter({ !$0.protected }).max(by: { growth($0) != growth($1) ? growth($0) < growth($1) : $0.id > $1.id }) else { return false }
            let room = growth(t)
            guard room > 0, let top = t.floors.last, let base = plan(top) else { c.planNote = "no tower can carry more"; return false }
            let use: RoomUse = need.kind == "farm_floors" ? .farm : (need.kind == "pump" ? .pump : (need.kind == "defence" ? .defence : .home))
            let p = Blueprint.plan(use: use, w: t.w, d: t.d, layout: ["central", "side", "courtyard"].firstIndex(of: t.style) ?? 0, seed: day &+ t.id)
            guard Blueprint.check(p).isEmpty else { c.planNote = "the new floors failed their checks"; return false }
            towerIndex.plans[p.key] = p
            let want = use == .home ? min(room, max(1, Int(need.score) / max(1, p.capacity(.home)) + 1), 10) : 1
            for k in 0..<want { t.floors.append(TowerFloor(z: top.z + Int64(base.height) * Int64(k + 1), plan: p.key)) }
            t.history.append("d\(day): \(want) floor(s) of \(use.rawValue) added: " + need.reasonEn)
            say("tower_grows", [t.nameEn, t.nameZh, "\(want)", need.reasonEn, need.reasonZh], [c.nation], region: c.regionKey)
            return true
        case "lift", "sky_lobby":
            guard let t = towers(of: c.id).filter({ !$0.protected }).max(by: { $0.liftLoad < $1.liftLoad }) else { return false }
            if need.kind == "sky_lobby" { t.skyLobbyEvery = 30; t.history.append("d\(day): sky lobbies every 30 floors: " + need.reasonEn); return true }
            guard Goods.take(TowerRules.liftCost, from: c.holding) == nil else { c.planNote = "a bank of lifts needs steel, parts and electronics"; return false }
            for (k, v) in TowerRules.liftCost { c.today.add(\.used, k, v); c.ledger.add(\.used, k, v) }
            t.lifts += 1
            t.history.append("d\(day): a bank of lifts added (\(t.lifts) now): " + need.reasonEn)
            return true
        default: return false
        }
    }

    /// Building goes floor by floor from the bottom: a floor takes its materials when it starts (all or
    /// none: short of them it waits), then structure, fit-out and inspection take days. A floor is used
    /// only once it passes its checks and the floor below stands.
    func advanceConstruction(_ c: CivCity) {
        for t in towers(of: c.id) {
            var active = 0
            for i in t.floors.indices {
                let f = t.floors[i]
                if f.stage >= .inUse { continue }
                if i > 0 && t.floors[i - 1].stage < .fitout { break }          // nothing hangs in the air
                guard active < 3 else { break }
                active += 1
                guard let p = plan(f) else { continue }
                switch f.stage {
                case .planned:
                    let cost = TowerRules.cost(p, material: t.material)
                    if Goods.take(cost, from: c.holding) == nil {
                        for (k, v) in cost { c.today.add(\.used, k, v); c.ledger.add(\.used, k, v) }
                        t.floors[i].stage = .reserved; t.floors[i].work = 1
                    } else { c.planNote = "waiting for materials for \(t.nameEn) floor \(i + 1)" }
                case .reserved, .structure, .fitout, .inspection:
                    t.floors[i].work -= 1
                    if t.floors[i].work <= 0 {
                        let next: TowerFloor.Stage = f.stage == .reserved ? .structure : (f.stage == .structure ? .fitout : (f.stage == .fitout ? .inspection : .inUse))
                        if next == .inUse {
                            // the inspection: the plan's checks, and the tower still holds with this floor in it
                            restructure(t, from: i)
                            let ok = Blueprint.check(p).isEmpty && t.load[i] <= t.strength[i] / TowerRules.failure
                            if !ok { t.history.append("d\(day): floor \(i + 1) failed inspection"); t.floors[i].stage = .planned; continue }
                            t.floors[i].builtDay = day
                        }
                        t.floors[i].stage = next; t.floors[i].work = next == .structure ? 2 : 1
                        if next == .structure { restructure(t, from: i) }
                    }
                default: break
                }
            }
        }
    }
}
