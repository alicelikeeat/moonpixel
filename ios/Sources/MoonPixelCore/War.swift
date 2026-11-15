import Foundation

/// Campaigns: muster -> march -> meet -> field battle or siege -> rout or
/// occupation -> truce and rebuilding. Everything is decided per legion from
/// numbers, unit mix, morale, supply and walls - the same whether or not anyone
/// is looking. Soldiers are real villagers; who falls is taken from them.
public enum Unit { public static let infantry = 0, archer = 1, cavalry = 2, siege = 3, supply = 4
    public static let names: [(String, String)] = [("Infantry", "步兵"), ("Archers", "远程兵"), ("Cavalry", "骑兵"), ("Siege crew", "攻城单位"), ("Supply train", "补给单位")] }

extension Society {
    // MARK: composition
    public func units(_ lg: Legion) -> [Int] {
        var c = [0, 0, 0, 0, 0]
        for id in lg.members { if let a = agents[id] { c[min(4, a.unit ?? (id % 3 == 0 ? Unit.archer : Unit.infantry))] += 1 } }
        return c
    }

    /// Give a mustered army its shape: a supply train, crews for the engines it could bring, horse, bow and foot.
    func assignUnits(_ lg: Legion, home: Settlement) {
        let ids = lg.members.sorted()
        let n = ids.count
        let carriers = max(1, n / 8)
        let engines = min(Int(home.good("engines")), max(0, n / 5))
        home.addGood("engines", -Double(engines))
        lg.engines = engines
        let tech = realm.nation(lg.nation)?.techCount ?? 0
        let fighting = n - carriers - engines
        let cav = tech >= 1 ? fighting / 5 : 0
        let arch = fighting * 3 / 10
        for (i, id) in ids.enumerated() {
            guard let a = agents[id] else { continue }
            if i < engines { a.unit = Unit.siege }
            else if i < engines + cav { a.unit = Unit.cavalry }
            else if i < engines + cav + arch { a.unit = Unit.archer }
            else if i >= n - carriers { a.unit = Unit.supply }
            else { a.unit = Unit.infantry }
        }
        lg.leader = ids.first { agents[$0]?.unit == Unit.infantry } ?? ids.first
    }

    func openGround(_ p: Vec2) -> Bool {
        let k = biomeKey(p.tile)
        return k != "forest" && k != "wetland" && k != "taiga"
    }

    /// Fighting strength. `mode`: 0 field, 1 storming walls, 2 fighting in the streets, 3 defending a city.
    func legionPower(_ lg: Legion, mode: Int, enemyCavalry: Bool = false, breached: Bool = true) -> Double {
        let cfg = realm.cfg
        guard let n = realm.nation(lg.nation) else { return 0 }
        let u = units(lg)
        var p = 0.0
        switch mode {
        case 0:
            let screened = u[0] * 2 >= u[1]
            p = Double(u[0]) + Double(u[1]) * (screened ? 1.25 : (enemyCavalry ? 0.6 : 1.0)) + Double(u[2]) * (openGround(lg.pos) ? 1.6 : 0.7) + Double(u[3] + u[4]) * 0.2
        case 1: p = Double(u[0]) + Double(u[1]) * 0.7 + Double(u[2]) * 0.3 + Double(u[4]) * 0.1
        case 2: p = Double(u[0]) + Double(u[1]) * 0.8 + Double(u[2]) * 0.6 + Double(u[3] + u[4]) * 0.2
        default: p = Double(u[0]) + Double(u[1]) * (breached ? 1.1 : 1.5) + Double(u[2]) * 0.6 + Double(u[3] + u[4]) * 0.3
        }
        p *= (1 + cfg.techPower * Double(n.techCount)) * (1 - 0.3 * min(1, n.fatigue))
        if realm.active("general", lg.nation, world.time) { p *= cfg.generalPower }
        p *= arsenalBonus(lg.nation) * gearBonus(lg.nation)
        p *= 0.5 + 0.5 * (lg.morale ?? cfg.moraleStart)
        if mode == 3 {
            let fort = settlements[lg.home].map { fortBonus($0) } ?? 1
            p *= breached ? 1 + (cfg.fortify * fort - 1) / 3 : cfg.fortify * fort
        } else { p *= lg.supply }
        return p
    }

    /// Kept for callers that only know "attacking or defending".
    func legionPower(_ lg: Legion, defending: Bool) -> Double { legionPower(lg, mode: defending ? 3 : 2, breached: false) }

    func addFatigue(_ nation: Int, _ v: Double) {
        if let k = realm.ni(nation) { realm.nations[k].fatigue = min(1.5, max(0, realm.nations[k].fatigue + v)) }
    }

    func kill(from lg: Legion, _ count: Int) {
        for _ in 0..<count {
            guard !lg.members.isEmpty else { return }
            let id = lg.members[realm.rng.index(lg.members.count)]
            if let a = agents[id] {
                let wasLeader = lg.leader == id
                die(a, "battle")
                if wasLeader { lg.morale = max(0, (lg.morale ?? realm.cfg.moraleStart) - realm.cfg.moraleLeader); lg.leader = lg.members.sorted().first }
            } else { lg.members.removeAll { $0 == id } }
        }
        // weapons are lost with the fallen
        if count > 0, let h = settlements[lg.home] { h.addGood("weapons", -Double(count) * 0.5) }
    }

    // MARK: roads to war
    /// A march route over legal ground: land, roads and bridges. Water without a
    /// bridge, cliffs and walls are closed. If no such way exists the army fords
    /// (a straight, slow line) and the route says so.
    /// How a march route came out.
    public enum RouteStatus: Int, Codable {
        case complete       // all the way, over legal ground (shallow fords included)
        case partial        // the search ran out of budget: a legal route towards the goal, to be continued
        case needsSiege     // legal up to the walls / closed gates of the target; the rest is a siege
        case needsBridge    // only deep water stands in the way: legal up to the shore
        case unreachable    // no legal way, and not even across water or walls
    }

    public struct MarchPlan {
        public var points: [Vec2]
        public var status: RouteStatus
        public var wades: Int                    // shallow-water tiles crossed on foot
        public var deps: [Int64: Int]            // chunk -> change stamp the route was planned against
        public var expanded: Int
    }

    /// What a tile is to a marching army.
    enum Ground { case road, open, woods, shallow, deep, cliff, wall }

    func ground(_ x: Int, _ y: Int) -> Ground {
        if !world.touched(x >> 5, y >> 5) {
            // country nobody has touched is judged from the generator alone, so planning never loads chunks
            let c = world.gen.climate(x, y)
            if c.0 > Biome.mountainLevel { return .cliff }
            if c.0 < Biome.sea || world.gen.isRiver(x, y, c.0) { return .deep }
            return .open
        }
        let st = world.tile(1, x, y)
        if content.bridge[Int(st)] || st == T["cobble_road"] || st == T["path"] { return .road }
        if content.solid[Int(st)] { return .cliff }
        let g = world.tile(0, x, y)
        if content.water[Int(g)] { return content.solid[Int(g)] ? .deep : .shallow }
        if let o = content.tile(world.tile(2, x, y)), o.solid {
            return o.built && !o.natural ? .wall : .woods            // walls and closed gates; trees and rocks are only slow
        }
        return .open
    }

    static func stepCost(_ g: Ground) -> Float? {
        switch g {
        case .road: return 0.6
        case .open: return 1
        case .woods: return 1.4
        case .shallow: return 2.5
        default: return nil
        }
    }
    /// The cheapest step there is, so the heuristic never overestimates (roads cost 0.6).
    static let minStep: Float = 0.6

    /// Plan a march. Budget-limited A* over legal ground; when the goal cannot be reached legally,
    /// a second look tells whether walls (a siege) or deep water (a bridge) is what stands in the way.
    /// The result is simplified only where a straight line is clear tile by tile.
    public func planMarch(from a: TilePos, to b: TilePos, budget: Int = 30_000, margin: Int = 40) -> MarchPlan {
        let minX = min(a.x, b.x) - margin, minY = min(a.y, b.y) - margin
        let w = abs(a.x - b.x) + 2 * margin + 1, h = abs(a.y - b.y) + 2 * margin + 1
        var memo = [UInt8](repeating: 255, count: w * h)
        let kinds: [Ground] = [.road, .open, .woods, .shallow, .deep, .cliff, .wall]
        func g(_ x: Int, _ y: Int) -> Ground {
            let k = (y - minY) * w + (x - minX)
            if memo[k] == 255 { memo[k] = UInt8(kinds.firstIndex(of: ground(x, y))!) }
            return kinds[Int(memo[k])]
        }
        func inside(_ x: Int, _ y: Int) -> Bool { x >= minX && y >= minY && x < minX + w && y < minY + h }
        /// A* with the given extra passable grounds (at a heavy cost) for the "what blocks it" searches.
        func search(extra: Set<Ground>, limit: Int) -> (path: [Int], found: Bool, best: Int, exhausted: Bool, expanded: Int) {
            var cost = [Float](repeating: .infinity, count: w * h)
            var from = [Int32](repeating: -1, count: w * h)
            var heap: [(Float, Int32)] = []
            func push(_ e: (Float, Int32)) {
                heap.append(e); var c = heap.count - 1
                while c > 0 { let p = (c - 1) / 2; if heap[p].0 <= heap[c].0 { break }; heap.swapAt(p, c); c = p }
            }
            func pop() -> (Float, Int32) {
                let top = heap[0]; let last = heap.removeLast()
                if !heap.isEmpty {
                    heap[0] = last; var c = 0
                    while true {
                        let l = 2 * c + 1, r = l + 1; var m = c
                        if l < heap.count && heap[l].0 < heap[m].0 { m = l }
                        if r < heap.count && heap[r].0 < heap[m].0 { m = r }
                        if m == c { break }; heap.swapAt(m, c); c = m
                    }
                }
                return top
            }
            func hd(_ x: Int, _ y: Int) -> Float {
                let dx = Float(abs(x - b.x)), dy = Float(abs(y - b.y))
                return (max(dx, dy) + 0.414 * min(dx, dy)) * Society.minStep                // admissible: never above the true cost
            }
            func price(_ gr: Ground) -> Float? { Society.stepCost(gr) ?? (extra.contains(gr) ? 25 : nil) }
            let s0 = (a.y - minY) * w + (a.x - minX), g0 = (b.y - minY) * w + (b.x - minX)
            cost[s0] = 0; push((hd(a.x, a.y), Int32(s0)))
            var best = s0, bestH = hd(a.x, a.y), n = 0, found = false
            while !heap.isEmpty && n < limit {
                let (f, ci) = pop()
                let c = Int(ci)
                let cx = c % w + minX, cy = c / w + minY
                if f > cost[c] + hd(cx, cy) + 0.001 { continue }               // stale entry
                n += 1
                if c == g0 { found = true; break }
                let hc = hd(cx, cy)
                if hc < bestH { bestH = hc; best = c }
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                    let nx = cx + dx, ny = cy + dy
                    if !inside(nx, ny) { continue }
                    let k = (ny - minY) * w + (nx - minX)
                    guard let sc = k == g0 ? 1 : price(g(nx, ny)) else { continue }
                    // no squeezing diagonally between two closed tiles
                    if dx != 0 && dy != 0 && (price(g(cx + dx, cy)) == nil || price(g(cx, cy + dy)) == nil) { continue }
                    let nc = cost[c] + sc * (dx != 0 && dy != 0 ? 1.414 : 1)
                    if nc < cost[k] { cost[k] = nc; from[k] = Int32(c); push((nc + hd(nx, ny), Int32(k))) }
                }
            }
            let end = found ? g0 : best
            var path: [Int] = []
            var k = end
            while k >= 0 { path.append(k); k = Int(from[k]) }
            return (path.reversed(), found, best, !found && !heap.isEmpty, n)
        }
        func tile(_ k: Int) -> TilePos { TilePos(k % w + minX, k / w + minY) }
        /// Every tile a straight line from p to q passes through, including both neighbours at diagonal steps.
        func clear(_ p: TilePos, _ q: TilePos, allowShallow: Bool) -> Bool {
            var x = p.x, y = p.y
            let dx = abs(q.x - p.x), dy = abs(q.y - p.y), sx = q.x > p.x ? 1 : -1, sy = q.y > p.y ? 1 : -1
            var err = dx - dy
            while true {
                guard inside(x, y), let c = Society.stepCost(g(x, y)) else { return false }
                if !allowShallow && c > 2 { return false }
                if x == q.x && y == q.y { return true }
                let e2 = 2 * err
                if e2 > -dy && e2 < dx {
                    // a diagonal step: the line touches both side tiles
                    guard inside(x + sx, y), inside(x, y + sy), Society.stepCost(g(x + sx, y)) != nil, Society.stepCost(g(x, y + sy)) != nil else { return false }
                }
                if e2 > -dy { err -= dy; x += sx }
                if e2 < dx { err += dx; y += sy }
            }
        }
        var status = RouteStatus.complete
        var r = search(extra: [], limit: budget)
        let expanded = r.expanded
        if !r.found {
            if r.exhausted { status = .partial }
            else if search(extra: [.wall], limit: budget).found { status = .needsSiege }
            else if search(extra: [.deep], limit: budget).found { status = .needsBridge }
            else if search(extra: [.wall, .deep], limit: budget).found { status = .needsBridge }
            else { status = .unreachable }
            if status == .unreachable && r.path.count <= 1 { r.path = [r.path.first ?? 0] }
        }
        // straighten only where the straight line is clear tile by tile (and does not add wading)
        let tiles = r.path.map(tile)
        var pts: [TilePos] = tiles.isEmpty ? [a] : [tiles[0]]
        var i = 0
        while i < tiles.count - 1 {
            var j = min(tiles.count - 1, i + 24)
            let wadesHere = tiles[i...].prefix(25).contains { g($0.x, $0.y) == .shallow }
            while j > i + 1 && !clear(tiles[i], tiles[j], allowShallow: wadesHere) { j -= 1 }
            pts.append(tiles[j]); i = j
        }
        var out = pts.map { $0.center }
        if status == .complete { out[out.count - 1] = b.center }
        out[0] = a.center
        var deps: [Int64: Int] = [:]
        for t in tiles { let k = MP.chunkKey(t.x >> 5, t.y >> 5); if deps[k] == nil { deps[k] = world.stamp(t.x >> 5, t.y >> 5) } }
        // the ring around the route matters too: a bridge built next to it can open a shorter way
        let wades = tiles.filter { g($0.x, $0.y) == .shallow }.count
        return MarchPlan(points: out, status: status, wades: wades, deps: deps, expanded: expanded)
    }

    /// Compatibility: points, and whether the route is not a full legal one.
    public func marchRoute(from a: TilePos, to b: TilePos) -> (points: [Vec2], forded: Bool) {
        let p = planMarch(from: a, to: b)
        return (p.points, p.status != .complete)
    }

    /// Give a legion a fresh plan towards `goal`.
    func replan(_ lg: Legion, to goal: TilePos) {
        let p = planMarch(from: lg.pos.tile, to: goal)
        lg.route = p.points; lg.routeI = 0
        lg.forded = p.wades > 0
        lg.routeStatus = p.status.rawValue
        lg.routeDeps = Dictionary(uniqueKeysWithValues: p.deps.map { ("\($0.key)", $0.value) })
        lg.routeGoal = [goal.x, goal.y]
        lg.routeT = world.time
        if p.status == .complete || p.status == .needsSiege { lg.routeFails = 0 }      // a way was found again
    }

    /// Something along the way changed (a bridge, a gate, a wall, a law): the route has to be planned again.
    func routeStale(_ lg: Legion) -> Bool {
        guard lg.route != nil else { return true }
        for (k, v) in lg.routeDeps ?? [:] {
            guard let key = Int64(k) else { continue }
            if world.stamp(MP.keyCX(key), MP.keyCY(key)) != v { return true }
        }
        return false
    }

    func routeLength(_ r: [Vec2]) -> Double { zip(r, r.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
    func point(on r: [Vec2], at f: Double) -> Vec2 {
        guard r.count > 1 else { return r.first ?? .zero }
        var left = routeLength(r) * max(0, min(1, f))
        for (p, q) in zip(r, r.dropFirst()) {
            let d = p.distance(to: q)
            if left <= d { return p + (q - p) * (d > 0 ? left / d : 0) }
            left -= d
        }
        return r[r.count - 1]
    }

    // MARK: muster
    func muster(_ nid: Int, against enemy: Int) {
        let cfg = realm.cfg
        if realm.legions.contains(where: { $0.nation == nid && $0.state != 0 }) { return }
        let mine = towns(of: nid), theirs = towns(of: enemy)
        guard !mine.isEmpty, !theirs.isEmpty else { return }
        var best: (Settlement, Settlement, Int)?
        for h in mine {
            guard let g = garrison(h, create: false), g.members.count >= 2 else { continue }
            for t in theirs {
                let d = (h.center - t.center).lengthSquared
                if best == nil || d < best!.2 { best = (h, t, d) }
            }
        }
        guard let (home, target, _) = best else { return }
        // every garrison sends its share; the army gathers at the town nearest the enemy
        var moving: [Int] = []
        for h in mine {
            guard let g = garrison(h, create: false), g.members.count >= 2 else { continue }
            let take = min(g.members.count - 1, Int((Double(g.members.count) * cfg.attackShare).rounded()))
            let ids = Array(g.members.sorted().prefix(take))
            g.members.removeAll { ids.contains($0) }
            moving += ids
        }
        if moving.count < cfg.minAttack {
            for id in moving { if let a = agents[id], let h = settlements[a.sid], let g = garrison(h, create: true) { g.members.append(id) } }
            return
        }
        let lg = Legion()
        lg.id = realm.nextLegion; realm.nextLegion += 1
        lg.nation = nid; lg.home = home.id; lg.target = target.id; lg.state = 1; lg.pos = home.center.center
        for id in moving { if let a = agents[id] { if let s = settlements[a.sid] { abort(a, s) }; a.legion = lg.id; lg.members.append(id) } }
        lg.startN = lg.members.count
        assignUnits(lg, home: home)
        lg.morale = cfg.moraleStart
        // rations come out of the home town's real stores (cooked meals first)
        let want = Double(lg.members.count) * cfg.rationStart
        let meals = min(home.good("meal"), want / 1.5)
        home.addGood("meal", -meals)
        let grain = min(max(0, home.food - Double(home.members.count) * 2), want - meals * 1.5)
        home.food -= grain
        lg.food = meals * 1.5 + grain
        replan(lg, to: target.center)
        lg.supply = supply(from: home.center, to: target.center, nation: nid) * (lg.forded == true ? 0.8 : 1)
        lg.supplyT = world.time + cfg.supplyInterval
        lg.convoyT = world.time + cfg.convoyEvery
        realm.legions.append(lg)
    }

    func sendHome(_ lg: Legion) {
        guard lg.state == 1 || lg.state == 2 || lg.state == 4 else { return }
        if let t = settlements[lg.target], t.siege == lg.id { endSiege(t) }
        lg.state = 3; lg.target = 0; lg.foe = nil; lg.phase = nil; lg.hold = nil
        lg.route = nil
    }

    func endSiege(_ s: Settlement) {
        s.siege = nil
        for g in s.gates where world.tile(2, g.x, g.y) == content.tid("gate") { world.setTile(2, g.x, g.y, content.tid("gate_open")) }
    }

    func disband(_ lg: Legion, into s: Settlement) {
        let g = garrison(s, create: true)!
        if g === lg { return }
        g.nation = s.nation ?? g.nation
        // engines that came back go into the store again
        if let e = lg.engines, e > 0 { s.addGood("engines", Double(e)) }
        if let f = lg.food, f > 0 { s.food += f }
        for id in lg.members { if let a = agents[id] { move(a, to: s); a.legion = g.id; a.unit = nil; if !g.members.contains(id) { g.members.append(id) } } }
        lg.members = []
        realm.legions.removeAll { $0 === lg }
    }

    public func realmTick(_ dt: Double) {
        guard !realm.nations.isEmpty else { return }
        realm.acc += dt
        let cfg = realm.cfg
        while realm.acc >= cfg.step {
            realm.acc -= cfg.step
            craftTick()
            meetInTheField()
            for lg in realm.legions.sorted(by: { $0.id < $1.id }) where lg.state != 0 { stepLegion(lg, cfg.step) }
        }
    }

    /// Armies of nations at war that come within reach of each other on the road give battle.
    func meetInTheField() {
        let field = realm.legions.filter { $0.state == 1 || $0.state == 3 }.sorted { $0.id < $1.id }
        for (i, a) in field.enumerated() where a.foe == nil {
            for b in field[(i + 1)...] where b.foe == nil && realm.atWar(a.nation, b.nation) && a.pos.distance(to: b.pos) <= realm.cfg.meetRange {
                a.foe = b.id; b.foe = a.id; a.state = 4; b.state = 4
                let near = town(near: a.pos, radius: 6000)
                emit("battle", [realm.nation(a.nation)?.name(zh: zh) ?? "", realm.nation(b.nation)?.name(zh: zh) ?? "", near.map { cityName($0) } ?? ""], a.pos,
                     nations: [a.nation, b.nation], city: near?.id, cause: "armies met", result: "\(a.members.count) vs \(b.members.count)")
                pushFX("charge", a.pos, to: b.pos, nation: a.nation)
                break
            }
        }
    }

    func pushFX(_ kind: String, _ pos: Vec2, to: Vec2, nation: Int) {
        if pendingFX.count < realm.cfg.maxEffects { pendingFX.append(WorldFX(kind: kind, pos: pos, to: to, nation: nation)) }
    }

    func lose(_ lg: Legion, _ n: Int) {
        if n <= 0 { return }
        let before = max(1, lg.members.count)
        kill(from: lg, n)
        lg.morale = max(0, (lg.morale ?? realm.cfg.moraleStart) - realm.cfg.moraleLoss * Double(n) / Double(before))
    }

    func stepLegion(_ lg: Legion, _ dt: Double) {
        let cfg = realm.cfg
        lg.members.removeAll { agents[$0] == nil }
        if lg.members.isEmpty {
            if let t = settlements[lg.target], t.siege == lg.id { endSiege(t) }
            if let f = lg.foe, let o = realm.legion(f) { o.foe = nil; if o.state == 4 { o.state = settlements[o.target] != nil && o.target != 0 ? 1 : 3 } }
            realm.legions.removeAll { $0 === lg }
            return
        }
        // where is home now?
        var home = settlements[lg.home]
        if home == nil || home!.abandoned || home!.nation != lg.nation {
            home = towns(of: lg.nation).min { ($0.center.center - lg.pos).length < ($1.center.center - lg.pos).length }
            if let h = home { lg.home = h.id; lg.route = nil }
        }
        guard let hm = home else {
            // a landless army lays down its arms where it stands
            if let t = settlements[lg.target], t.siege == lg.id { endSiege(t) }
            if let near = settlements.values.filter({ !$0.abandoned }).min(by: { ($0.center.center - lg.pos).length < ($1.center.center - lg.pos).length }) {
                for id in lg.members { if let a = agents[id] { move(a, to: near); discharge(a); a.refugee = world.time + cfg.refugeeIntegrate * MP.year } }
            }
            realm.legions.removeAll { $0 === lg }
            return
        }
        // --- supply: rations carried, and convoys from home along the real road
        let n = Double(lg.members.count)
        var food = lg.food ?? 0
        food -= n * cfg.ration * dt
        let carriers = units(lg)[Unit.supply]
        if let at = lg.convoyAt {
            let road = lg.route ?? [hm.center.center, lg.pos]
            let len = max(1, routeLength(road))
            let next = at + cfg.marchSpeed * 1.5 * (lg.forded == true ? 0.4 : 1) * dt / len
            if carriers == 0 { lg.convoyAt = nil; lg.convoyLoad = nil }                     // the train was cut down: its load is lost
            else if next >= 1 { food += lg.convoyLoad ?? 0; lg.convoyAt = nil; lg.convoyLoad = nil }
            else { lg.convoyAt = next }
        } else if world.time >= (lg.convoyT ?? 0), carriers > 0, food < n * cfg.rationStart / 2, lg.state != 3 {
            lg.convoyT = world.time + cfg.convoyEvery
            let spare = max(0, hm.food - Double(hm.members.count) * 2)
            let load = min(spare, Double(carriers) * cfg.convoyCarry)
            if load >= 1 && hm.siege == nil { hm.food -= load; lg.convoyAt = 0; lg.convoyLoad = load }
        }
        let fed = food > 0
        lg.food = max(0, food)
        var morale = lg.morale ?? cfg.moraleStart
        if !fed {
            morale -= cfg.moraleHunger * dt / 60
            lg.lossAcc += n * cfg.starveLoss * dt
            addFatigue(lg.nation, cfg.fatigueHunger * dt / MP.year)
        } else if lg.state == 1 || lg.state == 3 { morale = min(1, morale + cfg.moraleRally * dt / 60) }
        lg.morale = max(0, morale)
        if world.time >= lg.supplyT {
            let goal = settlements[lg.target]?.center ?? lg.pos.tile
            lg.supply = supply(from: hm.center, to: goal, nation: lg.nation) * (lg.forded == true ? 0.8 : 1) * (fed ? 1 : 0.4)
            lg.supplyT = world.time + cfg.supplyInterval
        }
        let starved = Int(lg.lossAcc)
        if starved > 0 && !fed { lose(lg, starved); lg.lossAcc -= Double(starved) }

        // --- going home
        if lg.state == 3 {
            if needsRoute(lg, to: hm.center) { replan(lg, to: hm.center) }
            if advance(lg, dt, speed: cfg.marchSpeed * (morale < cfg.rout ? 1.4 : 1) * (lg.forded == true ? 0.7 : 1)) {
                if lg.routeStatus == RouteStatus.complete.rawValue || lg.pos.distance(to: hm.center.center) < 64 { disband(lg, into: hm) }
                else { blocked(lg, home: hm) }
            }
            return
        }
        // --- a battle in the open
        if lg.state == 4 {
            guard let fid = lg.foe, let foe = realm.legion(fid), foe.state == 4, !foe.members.isEmpty, realm.atWar(lg.nation, foe.nation) else {
                lg.foe = nil; lg.state = lg.target != 0 ? 1 : 3; lg.route = nil
                return
            }
            if lg.id < foe.id {                       // the pair is resolved once per step, by the lower id
                let ua = units(lg), ub = units(foe)
                let pa = legionPower(lg, mode: 0, enemyCavalry: ub[2] > 0), pb = legionPower(foe, mode: 0, enemyCavalry: ua[2] > 0)
                lg.lossAcc += cfg.lethality * pb * dt
                foe.lossAcc += cfg.lethality * pa * dt
                if ua[1] + ub[1] > 0 { pushFX("volley", ua[1] >= ub[1] ? lg.pos : foe.pos, to: ua[1] >= ub[1] ? foe.pos : lg.pos, nation: ua[1] >= ub[1] ? lg.nation : foe.nation) }
                for (x, power, other) in [(lg, pa, pb), (foe, pb, pa)] {
                    let l = Int(x.lossAcc)
                    if l > 0 { lose(x, l); x.lossAcc -= Double(l) }
                    let m = x.morale ?? cfg.moraleStart
                    if x.members.isEmpty { continue }
                    if m < cfg.rout || (m < cfg.waver && power < other) || Double(x.members.count) < max(1, Double(x.startN) * cfg.retreatShare) {
                        // broken: the beaten side runs, and loses stragglers to the pursuit (worse if the victor has horse)
                        let horse = units(x === lg ? foe : lg)[2] > 0
                        if m < cfg.rout { lose(x, Int((Double(x.members.count) * cfg.routLoss * (horse ? 2 : 1)).rounded(.up))) }
                        pushFX("rout", x.pos, to: settlements[x.home]?.center.center ?? x.pos, nation: x.nation)
                        addFatigue(x.nation, 0.1)
                        let victor = x === lg ? foe : lg
                        victor.foe = nil; victor.state = 1; victor.route = nil
                        victor.morale = min(1, (victor.morale ?? cfg.moraleStart) + 0.1)
                        x.foe = nil; x.state = 3; x.target = 0; x.route = nil
                        break
                    }
                }
            }
            return
        }
        guard let target = settlements[lg.target], !target.abandoned, let enemy = target.nation, enemy != lg.nation, realm.atWar(lg.nation, enemy) else { sendHome(lg); return }
        // --- on the march
        if lg.state == 1 {
            if needsRoute(lg, to: target.center) { replan(lg, to: target.center) }
            var arrived = advance(lg, dt, speed: cfg.marchSpeed * (0.5 + 0.5 * min(1, lg.supply)) * marchWeather() * (lg.forded == true ? 0.6 : 1), stopShort: 56)
            if arrived {
                switch RouteStatus(rawValue: lg.routeStatus ?? 0) ?? .complete {
                case .complete: break
                case .needsSiege: arrived = lg.pos.distance(to: target.center.center) < 26 * 16      // at the walls: the siege begins here
                case .partial: arrived = false; lg.route = nil                                        // keep going: plan the next stretch
                case .needsBridge, .unreachable: arrived = false; blocked(lg, home: hm)
                }
            }
            if arrived {
                lg.state = 2
                if world.time >= target.cityT { surveyTown(target) }
                let walled = target.walls.count >= cfg.wallMin
                lg.phase = walled ? 0 : 1
                lg.wallHP = cfg.wallHP * (1 + Double(min(1, target.count("fortress", done: true))))
                lg.wallsAtStart = target.walls.count
                lg.hold = 0
                target.siege = lg.id
                for g in target.gates where world.tile(2, g.x, g.y) == content.tid("gate_open") { world.setTile(2, g.x, g.y, content.tid("gate")); displace(from: g, in: world) }
                emit("siege", [realm.nation(lg.nation)?.name(zh: zh) ?? "", cityName(target)], target.center.center,
                     nations: [lg.nation, enemy], city: target.id, cause: "march", result: walled ? "walls stand" : "open town")
            }
            return
        }
        // --- at the city
        let def = garrison(target, create: false)
        def?.members.removeAll { agents[$0] == nil }
        let defenders = def?.members.count ?? 0
        let u = units(lg)
        var phase = lg.phase ?? 1
        if phase == 0 {
            // walls: engines batter, ladders scratch; archers trade volleys; anyone opening a gate or a gap ends this phase
            if world.time >= target.cityT { surveyTown(target) }
            let gateOpen = target.gates.contains { world.tile(2, $0.x, $0.y) == content.tid("gate_open") }
            var hp = lg.wallHP ?? cfg.wallHP
            hp -= (Double(lg.engines ?? 0) * cfg.engineHit + Double(u[0]) * cfg.ladderHit) * dt
            if let d = def, defenders > 0 {
                let da = units(d)[1], aa = u[1]
                lg.lossAcc += cfg.lethality * Double(da) * 1.5 * dt
                lg.defLossAcc += cfg.lethality * Double(aa) * 0.5 * dt
                if da + aa > 0 { pushFX("volley", da >= aa ? target.center.center : lg.pos, to: da >= aa ? lg.pos : target.center.center, nation: da >= aa ? enemy : lg.nation) }
            }
            if gateOpen || target.walls.count < (lg.wallsAtStart ?? 0) || target.walls.count < cfg.wallMin { phase = 1 }
            else if hp <= 0 {
                // a real gap: the wall tiles nearest the army come down
                let near = target.walls.sorted { $0.center.distance(to: lg.pos) < $1.center.distance(to: lg.pos) }.prefix(3)
                for t in near { world.setTile(2, t.x, t.y, 0); if world.tile(3, t.x, t.y) == 0 { world.setTile(3, t.x, t.y, content.tid("rubble")) } }
                target.walls.removeAll { near.contains($0) }
                phase = 1
                addFatigue(enemy, cfg.fatigueDamage * 2)
                emit("breach", [realm.nation(lg.nation)?.name(zh: zh) ?? "", cityName(target)], near.first?.center ?? target.center.center,
                     nations: [lg.nation, enemy], city: target.id, cause: "engines \(lg.engines ?? 0)", result: "wall opened")
                pushFX("breach", near.first?.center ?? target.center.center, to: target.center.center, nation: lg.nation)
            }
            lg.wallHP = hp
        } else if phase == 1 {
            let ap = legionPower(lg, mode: 2), dp = def.map { legionPower($0, mode: 3, breached: true) } ?? 0
            lg.lossAcc += cfg.lethality * dp * dt
            lg.defLossAcc += cfg.lethality * ap * dt
            if defenders == 0 { phase = 2; lg.hold = 0 }
        } else {
            // the square is taken; it has to be held before the city changes hands
            if defenders > 0 { phase = 1 }
            else {
                lg.hold = (lg.hold ?? 0) + dt
                if (lg.hold ?? 0) >= cfg.occupyTime { lg.phase = nil; capture(target, by: lg); return }
            }
        }
        lg.phase = phase
        let dl = min(defenders, Int(lg.defLossAcc)), al = Int(lg.lossAcc)
        if dl > 0, let d = def { kill(from: d, dl); lg.defLossAcc -= Double(dl) }
        if al > 0 { lose(lg, al); lg.lossAcc -= Double(al) }
        if lg.members.isEmpty {
            endSiege(target)
            realm.legions.removeAll { $0 === lg }
            emit("repelled", [cityName(target), realm.nation(lg.nation)?.name(zh: zh) ?? ""], target.center.center, nations: [enemy, lg.nation], city: target.id, cause: "assault failed", result: "army destroyed")
            return
        }
        let m = lg.morale ?? cfg.moraleStart
        if m < cfg.waver || Double(lg.members.count) < max(1, Double(lg.startN) * cfg.retreatShare) {
            if m < cfg.rout { lose(lg, Int((Double(lg.members.count) * cfg.routLoss).rounded(.up))); pushFX("rout", lg.pos, to: hm.center.center, nation: lg.nation) }
            emit("repelled", [cityName(target), realm.nation(lg.nation)?.name(zh: zh) ?? ""], target.center.center, nations: [enemy, lg.nation], city: target.id,
                 cause: m < cfg.waver ? "morale broke" : "losses", result: m < cfg.rout ? "rout" : "retreat")
            sendHome(lg)
        }
    }

    /// A route is planned again when it is missing, aimed elsewhere, or something along it changed.
    func needsRoute(_ lg: Legion, to goal: TilePos) -> Bool {
        if lg.route == nil { return true }
        if let g = lg.routeGoal, g.count == 2, g[0] != goal.x || g[1] != goal.y { return true }
        // a blocked army waits before looking again (backing off), so it never re-plans every step
        if let st = lg.routeStatus, st == RouteStatus.needsBridge.rawValue || st == RouteStatus.unreachable.rawValue {
            let wait = realm.cfg.routeRetry * pow(2, Double(min(5, lg.routeFails ?? 0)))
            return world.time - (lg.routeT ?? 0) >= wait
        }
        return routeStale(lg)
    }

    /// No legal way on: wait where the route ends and look again later; after a few tries give up
    /// the march (an attack goes home; an army that cannot get home stands down in its own country).
    func blocked(_ lg: Legion, home hm: Settlement) {
        // standing at the dead end of one route counts once, however many steps it waits there
        if let t = lg.routeFailT, t == lg.routeT { return }
        lg.routeFailT = lg.routeT
        let fails = (lg.routeFails ?? 0) + 1
        lg.routeFails = fails
        if fails < realm.cfg.routeMaxFails { return }
        if lg.state == 1 || lg.state == 2 {
            emit("no_road", [realm.nation(lg.nation)?.name(zh: zh) ?? "", settlements[lg.target].map { cityName($0) } ?? ""], lg.pos,
                 nations: [lg.nation], city: lg.target, cause: (lg.routeStatus == RouteStatus.needsBridge.rawValue ? "deep water" : "no legal route"), result: "turned back")
            lg.routeFails = 0
            sendHome(lg)
        } else {
            // cannot get home either: the soldiers stand down where they are and belong to the nearest town of their nation
            let town = towns(of: lg.nation).min { $0.center.center.distance(to: lg.pos) < $1.center.center.distance(to: lg.pos) } ?? hm
            for id in lg.members { if let a = agents[id] { move(a, to: town); discharge(a) } }
            lg.members = []
            realm.legions.removeAll { $0 === lg }
        }
    }

    /// Move a legion along its route. Returns true on arrival.
    func advance(_ lg: Legion, _ dt: Double, speed: Double, stopShort: Double = 40) -> Bool {
        guard let r = lg.route, !r.isEmpty else { return true }
        var i = min(lg.routeI ?? 0, r.count - 1)
        var left = speed * dt
        if let tile = Optional(lg.pos.tile), world.tile(1, tile.x, tile.y) == T["cobble_road"] { left *= 1.25 }      // roads are quicker
        while left > 0 {
            let to = r[i] - lg.pos
            let last = i == r.count - 1
            if last && to.length <= max(stopShort, left) { lg.routeI = i; return true }
            if to.length <= left { lg.pos = r[i]; left -= to.length; if !last { i += 1 } else { lg.routeI = i; return true } }
            else { lg.pos = lg.pos + to.normalized * left; left = 0 }
        }
        lg.routeI = i
        return false
    }

    // MARK: a war on purpose (cheat panel, demonstrations)
    /// Raise armies on both sides, give the defender's nearest town a wall with a gate,
    /// and declare war. Marks the save as cheated. Returns the attacking legion's id.
    @discardableResult public func stageCampaign(attacker: Int, defender: Int, walls: Bool = true) -> Int? {
        guard attacker != defender, realm.nation(attacker)?.exileSince == nil, realm.nation(defender)?.exileSince == nil,
              let r = realm.ri(attacker, defender) else { return nil }
        realm.player.cheated = true
        let now = world.time
        func raise(_ nation: Int, _ per: Int) {
            for t in towns(of: nation) {
                guard let g = garrison(t, create: true) else { continue }
                g.nation = nation
                for a in t.members.compactMap({ agents[$0] }).sorted(by: { $0.id < $1.id }) where a.legion == nil && a.stage(now) == "adult" && a.refugee == nil && g.members.count < per { enlist(a, g) }
            }
        }
        raise(attacker, 16); raise(defender, 5)
        for t in towns(of: attacker) { t.addGood("engines", 3); t.food = max(t.food, 600); t.addGood("weapons", 10) }
        if walls, let home = towns(of: attacker).first,
           let target = towns(of: defender).min(by: { ($0.center - home.center).lengthSquared < ($1.center - home.center).lengthSquared }) {
            let rad = 7
            for d in -rad...rad {
                for p in [TilePos(target.center.x + d, target.center.y - rad), TilePos(target.center.x + d, target.center.y + rad),
                          TilePos(target.center.x - rad, target.center.y + d), TilePos(target.center.x + rad, target.center.y + d)] {
                    let gate = d == 0 && p.y == target.center.y + rad
                    world.setTile(1, p.x, p.y, 0)
                    world.setTile(2, p.x, p.y, content.tid(gate ? "gate_open" : "wall_stone"))
                    displace(from: p, in: world)
                }
            }
            surveyTown(target)
        }
        if realm.relations[r].state != 0 { realm.relations[r].state = 0 }
        realm.relations[r].since = -1e9
        refreshNations()
        if let k = realm.ni(attacker) { realm.nations[k].fatigue = 0 }
        declare(attacker, on: defender)
        return realm.legions.first { $0.nation == attacker && $0.state == 1 }?.id
    }

    // MARK: what the player can do for an army
    /// Hand food to a friendly army in the field. Returns how much was given.
    @discardableResult public func playerFeedLegion(near pos: Vec2, amount: Double = 20) -> Double {
        guard let lg = realm.legions.filter({ $0.state != 0 && $0.nation == realm.player.nation && realm.player.nation != 0 && $0.pos.distance(to: pos) < 120 })
                .min(by: { $0.pos.distance(to: pos) < $1.pos.distance(to: pos) }) else { return 0 }
        let give = min(amount, realm.player.food)
        if give <= 0 { return 0 }
        realm.player.food -= give
        lg.food = (lg.food ?? 0) + give
        lg.morale = min(1, (lg.morale ?? 0.5) + 0.05)
        addRep(lg.nation, give / 80)
        return give
    }

    public struct LegionInfo {
        public var id = 0, nation = 0, color = "", name = "", state = "", target = ""
        public var count = 0, units = [0, 0, 0, 0, 0], engines = 0
        public var morale = 0.0, food = 0.0, supply = 0.0
        public var pos = Vec2.zero, route: [Vec2] = [], convoy: Vec2?
        public var phase = -1, forded = false
        public var foe: Vec2?
        public var targetPos: Vec2?
    }

    public func legionInfos() -> [LegionInfo] {
        realm.legions.filter { $0.state != 0 }.sorted { $0.id < $1.id }.map { lg in
            var i = LegionInfo()
            let n = realm.nation(lg.nation)
            i.id = lg.id; i.nation = lg.nation; i.color = n?.color ?? "#ffffff"; i.name = n?.name(zh: zh) ?? ""
            let states = zh ? ["驻守", "行军", "围城", "撤退", "野战"] : ["garrison", "marching", "besieging", "retreating", "in battle"]
            i.state = states[min(4, lg.state)]
            if lg.state == 2 { i.state = (zh ? ["围攻城墙", "强攻", "占领中"] : ["at the walls", "storming", "occupying"])[min(2, lg.phase ?? 1)] }
            i.target = settlements[lg.target].map { cityName($0) } ?? ""
            i.count = lg.members.count; i.units = units(lg); i.engines = lg.engines ?? 0
            i.morale = lg.morale ?? 0; i.food = lg.food ?? 0; i.supply = lg.supply
            i.pos = lg.pos; i.route = lg.route ?? []; i.phase = lg.phase ?? -1; i.forded = lg.forded == true
            i.foe = lg.foe.flatMap { realm.legion($0) }?.pos
            i.targetPos = settlements[lg.target]?.center.center
            if let at = lg.convoyAt, let h = settlements[lg.home] { i.convoy = point(on: [h.center.center] + (lg.route ?? [lg.pos]).prefix(max(1, (lg.routeI ?? 0) + 1)) + [lg.pos], at: at) }
            return i
        }
    }
}
