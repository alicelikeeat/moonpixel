import Foundation

/// World laws: one-tap, irreversible deletion. A law first becomes a `LawPlan`
/// (decided only by the current state, the options and a seed), is written to a
/// journal, then executed in batches. Re-running a plan is harmless, which is
/// what makes an interrupted law recoverable.
public enum LawMode: String, Codable, CaseIterable { case thanos, annihilation, genesis, guixu }

public struct LawOptions: Codable, Equatable {
    public var ratio = 0.3                 // annihilation: share of each kind to delete
    public var spaceTarget = 0             // annihilation: > 0 means "free about this many bytes" instead
    public var wResidents = 1.0, wBuildings = 1.0, wProps = 1.0, wChunks = 1.0, wHistory = 1.0
    public var newSeed = true              // genesis: new seed, or the same one again
    public var radius = 2                  // guixu: region is (2r+1) x (2r+1) chunks
    public var thanosHold = 1.0            // years without newcomers after thanos
    public init() {}
}

public struct BuildingRef: Codable, Equatable { public var sid: Int, bid: Int }
public struct PropRef: Codable, Equatable { public var cx: Int, cy: Int, id: Int }
public struct ChunkRef: Codable, Equatable, Hashable { public var cx: Int, cy: Int }

public struct LawPlan: Codable, Equatable {
    public var mode: LawMode
    public var seed: Int
    public var options = LawOptions()
    public var agents: [Int] = []
    public var buildings: [BuildingRef] = []
    public var props: [PropRef] = []
    public var chunks: [ChunkRef] = []
    public var towns: [Int] = []
    public var logLines = 0                // history: log lines to drop (oldest first)
    public var graves = 0                  // history: grave markers to remove
    public var region: [Int] = []          // guixu: cx0, cy0, cx1, cy1 (inclusive)
    public var newSeed = 0                 // genesis
    public var estimate = 0                // bytes the planner expects to free (annihilation by space)
}

public struct LawResult: Codable, Equatable {
    public var mode = LawMode.thanos
    public var agents = 0, buildings = 0, props = 0, chunks = 0, towns = 0, logLines = 0, graves = 0, displaced = 0
    public var bytesBefore = 0, bytesAfter = 0, assetsRemoved = 0, refsFixed = 0
    public var restart = false
    public var freed: Int { max(0, bytesBefore - bytesAfter) }
}

public struct LawJournal: Codable {
    public var plan: LawPlan
    public var started: Double
    public static func url(_ dir: URL) -> URL { dir.appendingPathComponent("law-journal.json") }
    public static func read(_ dir: URL) -> LawJournal? { (try? Data(contentsOf: url(dir))).flatMap { try? JSONDecoder().decode(LawJournal.self, from: $0) } }
    @discardableResult public static func write(_ plan: LawPlan, _ dir: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(LawJournal(plan: plan, started: Date().timeIntervalSince1970)) else { return false }
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try data.write(to: url(dir), options: .atomic); return true } catch { return false }
    }
    public static func clear(_ dir: URL) { try? FileManager.default.removeItem(at: url(dir)) }
}

/// Three ways to stay inside the storage limit. Destruction is only automatic
/// after the player has chosen it.
public enum StorageMode: String, Codable, CaseIterable { case cacheFirst, autoAnnihilation, regionCycle }

public struct StoragePolicy: Codable, Equatable {
    public var mode = StorageMode.cacheFirst
    public var high = 0.85, low = 0.70     // start above `high` of the limit, aim for `low`
    public var cooldown = 300.0            // seconds of real time between automatic runs
    public var lastRun = -1e12
    public init() {}

    /// What, if anything, to run now. Never destructive in `cacheFirst`.
    public mutating func decide(used: Int, limit: Int, clock: Double) -> (LawMode, LawOptions)? {
        guard mode != .cacheFirst, limit > 0, Double(used) >= high * Double(limit), clock - lastRun >= cooldown else { return nil }
        lastRun = clock
        var o = LawOptions()
        if mode == .autoAnnihilation {
            o.spaceTarget = max(1, used - Int(low * Double(limit)))
            // technical reclamation prefers map data and history over people
            o.wResidents = 0.25; o.wBuildings = 0.5; o.wChunks = 3; o.wHistory = 2
            return (.annihilation, o)
        }
        return (.guixu, o)
    }
}

extension Society {
    // MARK: planning
    public func planLaw(_ mode: LawMode, options: LawOptions = LawOptions(), seed: Int) -> LawPlan {
        var plan = LawPlan(mode: mode, seed: seed)
        plan.options = options
        var r = RNG(seed: seed &* 31 &+ (LawMode.allCases.firstIndex(of: mode) ?? 0))
        func shuffled<T>(_ list: [T]) -> [T] {
            var l = list
            if l.count > 1 { for i in stride(from: l.count - 1, to: 0, by: -1) { l.swapAt(i, r.index(i + 1)) } }
            return l
        }
        let ids = agents.keys.sorted()
        let towns = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        switch mode {
        case .thanos:
            plan.agents = Array(shuffled(ids).prefix(ids.count / 2)).sorted()
        case .genesis:
            plan.newSeed = options.newSeed ? Int(r.next() % 99991) + 1 : world.seed
        case .annihilation:
            let brefs = towns.flatMap { s in s.buildings.map { BuildingRef(sid: s.id, bid: $0.id) } }
            var prefs: [PropRef] = []
            var keys = Set(world.storedChunks)
            for k in world.cache.keys { keys.insert(k) }
            for k in keys.sorted() { if let c = world.peekStored(k) { for p in c.props.sorted(by: { $0.id < $1.id }) { prefs.append(PropRef(cx: c.cx, cy: c.cy, id: p.id)) } } }
            let crefs = world.storedChunks.filter { world.pins[$0] == nil }.map { ChunkRef(cx: MP.keyCX($0), cy: MP.keyCY($0)) }
            let graves = towns.reduce(0) { $0 + min($1.graves, realm.cfg.maxGraves) }
            let weights = [options.wResidents, options.wBuildings, options.wProps, options.wChunks, options.wHistory]
            let mean = weights.reduce(0, +) / 5
            if mean <= 0 { break }
            if options.spaceTarget <= 0 {
                func share(_ w: Double, _ n: Int) -> Int { Int((Double(n) * min(1, options.ratio * w / mean)).rounded(.down)) }
                plan.agents = Array(shuffled(ids).prefix(share(weights[0], ids.count))).sorted()
                plan.buildings = Array(shuffled(brefs).prefix(share(weights[1], brefs.count)))
                plan.props = Array(shuffled(prefs).prefix(share(weights[2], prefs.count)))
                plan.chunks = Array(shuffled(crefs).prefix(share(weights[3], crefs.count)))
                plan.logLines = share(weights[4], log.count)
                plan.graves = share(weights[4], graves)
            } else {
                var pa = shuffled(ids), pb = shuffled(brefs), pp = shuffled(prefs), pc = shuffled(crefs)
                var lines = log.count, gr = graves
                var est = 0
                while est < options.spaceTarget {
                    let avail = [!pa.isEmpty, !pb.isEmpty, !pp.isEmpty, !pc.isEmpty, lines + gr > 0]
                    let total = zip(weights, avail).reduce(0.0) { $0 + ($1.1 ? $1.0 : 0) }
                    if total <= 0 { break }
                    var x = r.unit() * total, cat = 0
                    for i in 0..<5 where avail[i] { cat = i; x -= weights[i]; if x < 0 { break } }
                    switch cat {
                    case 0: plan.agents.append(pa.removeLast()); est += 700
                    case 1:
                        let b = pb.removeLast(); plan.buildings.append(b)
                        est += 200 + 60 * (settlements[b.sid]?.building(b.bid)?.cells.count ?? 0)
                    case 2: plan.props.append(pp.removeLast()); est += 90
                    case 3:
                        let c = pc.removeLast(); plan.chunks.append(c)
                        est += world.storedSize(MP.chunkKey(c.cx, c.cy))
                    default:
                        if lines > 0 { lines -= 1; plan.logLines += 1; est += 80 } else { gr -= 1; plan.graves += 1; est += 8 }
                    }
                }
                plan.agents.sort()
                plan.estimate = est
            }
        case .guixu:
            var centres = Set(world.storedChunks.map { ChunkRef(cx: MP.keyCX($0), cy: MP.keyCY($0)) })
            for s in towns { centres.insert(ChunkRef(cx: s.center.x >> 5, cy: s.center.y >> 5)) }
            let list = centres.sorted { $0.cx != $1.cx ? $0.cx < $1.cx : $0.cy < $1.cy }
            let c = list.isEmpty ? ChunkRef(cx: 0, cy: 0) : list[r.index(list.count)]
            let rad = max(0, options.radius)
            plan.region = [c.cx - rad, c.cy - rad, c.cx + rad, c.cy + rad]
            for cy in (c.cy - rad)...(c.cy + rad) { for cx in (c.cx - rad)...(c.cx + rad) { plan.chunks.append(ChunkRef(cx: cx, cy: cy)) } }
            let x0 = (c.cx - rad) * 32, y0 = (c.cy - rad) * 32, x1 = (c.cx + rad + 1) * 32, y1 = (c.cy + rad + 1) * 32
            for s in towns {
                if s.center.x >= x0 && s.center.x < x1 && s.center.y >= y0 && s.center.y < y1 { plan.towns.append(s.id); continue }
                // a building that reaches into the region goes as a whole, never half of it
                for b in s.buildings where b.x < x1 && b.x + b.w > x0 && b.y < y1 && b.y + b.h > y0 { plan.buildings.append(BuildingRef(sid: s.id, bid: b.id)) }
            }
            for ch in plan.chunks { if let k = world.peekStored(MP.chunkKey(ch.cx, ch.cy)) { for p in k.props { plan.props.append(PropRef(cx: ch.cx, cy: ch.cy, id: p.id)) } } }
        }
        return plan
    }

    // MARK: erasing (no graves, no mourning, nothing left behind)
    func erase(_ a: Agent) {
        a.alive = false
        if let s = settlements[a.sid] {
            abort(a, s)
            leaveHome(a, s)
            s.members.removeAll { $0 == a.id }
        }
        if let lid = a.legion, let lg = realm.legion(lid) { lg.members.removeAll { $0 == a.id } }
        agents[a.id] = nil
        for rid in [a.partner, a.mother, a.father] + a.children where rid != 0 {
            guard let rel = agents[rid] else { continue }
            if rel.partner == a.id { rel.partner = 0 }
            if rel.mother == a.id { rel.mother = 0 }
            if rel.father == a.id { rel.father = 0 }
            rel.children.removeAll { $0 == a.id }
        }
    }

    func eraseBuilding(_ s: Settlement, _ b: Building, restore: Bool) {
        for mid in s.members {
            guard let a = agents[mid] else { continue }
            if a.task?.bid == b.id { if let t = a.task { s.claims[t.target] = nil }; a.task = nil; a.path = [] }
            if a.home == b.id { a.home = -1 }
        }
        if restore { for dy in 0..<b.h { for dx in 0..<b.w { world.restoreNatural(b.x + dx, b.y + dy) } } }
        s.buildings.removeAll { $0 === b }
        let gx = Double(b.x + b.w / 2 - s.center.x) / 9, gy = Double(b.y + b.h / 2 - s.center.y) / 8
        if gx == gx.rounded() && gy == gy.rounded() { s.usedSlots.remove("\(Int(gx)),\(Int(gy))") }
        s.planT = 0
    }

    func stampCore(_ s: Settlement) {
        let center = s.center
        for dy in -2...2 { for dx in -2...2 {
            let x = center.x + dx, y = center.y + dy
            world.setTile(2, x, y, 0); world.setTile(3, x, y, 0)
            if world.isLand(x, y) && dx * dx + dy * dy <= 5 { world.setTile(1, x, y, T["cobble_road"]!) }
        } }
        world.setTile(2, center.x, center.y, T["campfire"]!)
        world.setTile(2, center.x - 2, center.y - 2, T["chest"]!)
        world.setTile(2, center.x + 2, center.y - 2, T["crate"]!)
    }

    func refreshNav(_ s: Settlement) {
        guard let nav = s.nav else { return }
        for y in 0..<Settlement.span { for x in 0..<Settlement.span { nav.solid[y * Settlement.span + x] = world.blocked(s.origin.x + x, s.origin.y + y) } }
        s.resT = 0; s.planT = 0
        s.unreachable.removeAll()
    }

    /// Everything on disk and in memory that a look or a placed prop still points at.
    public func referencedAssets(extra: [Look] = []) -> Set<String> {
        var out = Set<String>()
        for l in agents.values.map({ $0.look }) + extra {
            if !l.face.isEmpty { out.insert(l.face) }
            if let p = l.portrait { out.insert(p) }
            if let a = l.anim { out.insert(a) }
        }
        var keys = Set(world.storedChunks)
        for k in world.cache.keys { keys.insert(k) }
        for k in keys { if let c = world.peekStored(k) { for p in c.props { out.insert(p.key) } } }
        return out
    }

    /// Bytes each part of the saved index takes (people, history, nations, towns).
    public func storageBreakdown() -> [String: Int] {
        let enc = JSONEncoder()
        var out: [String: Int] = [:]
        out["people"] = (try? enc.encode(agents.values.sorted { $0.id < $1.id }))?.count ?? 0
        out["history"] = ((try? enc.encode(log.map { LogLine(t: $0.t, text: $0.text) }))?.count ?? 0) + ((try? enc.encode(stats))?.count ?? 0)
        out["nations"] = (try? enc.encode(realm))?.count ?? 0
        out["towns"] = (try? enc.encode(settlements.values.sorted { $0.id < $1.id }))?.count ?? 0
        return out
    }

    /// Start executing a plan (anything but genesis, which replaces the world: see `Society.genesis`).
    public func beginLaw(_ plan: LawPlan) -> LawRun { LawRun(self, plan) }

    /// Genesis: the old world's content is deleted and a new one is generated in
    /// the same save folder. Name, player look and its assets are the caller's to keep.
    public static func genesis(old: Society, plan: LawPlan, villages: Int, per: Int, startTech: Int) -> (world: OpenWorld, society: Society, result: LawResult) {
        var res = LawResult()
        res.mode = .genesis
        res.agents = old.agents.count
        res.towns = old.settlements.count
        res.buildings = old.settlements.values.reduce(0) { $0 + $1.buildings.count }
        res.chunks = old.world.storedChunks.count
        res.logLines = old.log.count
        res.bytesBefore = old.world.diskBytes
        let dir = old.world.directory
        for s in old.settlements.values where !s.abandoned { old.detach(s) }
        old.world.wipe()
        old.underworld().wipe()                  // the underground of the old world goes with it
        let w = OpenWorld(seed: plan.newSeed, budget: old.world.budget)
        w.diskLimitBytes = old.world.diskLimitBytes
        w.gen.tempBias = old.world.gen.tempBias; w.gen.moistBias = old.world.gen.moistBias; w.gen.elevBias = old.world.gen.elevBias
        if let d = dir { w.open(directory: d) }
        let s = Society(world: w, seed: plan.newSeed)
        s.zh = old.zh
        s.minPopulation = old.minPopulation
        s.realm.cfg = old.realm.cfg
        s.grantTech(startTech)
        s.bootstrap(origin: TilePos(0, 0), villages: max(3, villages), per: per)
        res.bytesAfter = w.diskBytes
        return (w, s, res)
    }
}

/// Executes a plan a few items at a time so the interface never stalls.
public final class LawRun {
    public let plan: LawPlan
    public private(set) var result = LawResult()
    public private(set) var done = false
    let s: Society
    var phase = 0, i = 0
    var total: Int
    var doneItems = 0
    var touched = Set<Int>()

    init(_ society: Society, _ plan: LawPlan) {
        s = society
        self.plan = plan
        result.mode = plan.mode
        result.bytesBefore = society.world.diskBytes
        total = max(1, plan.towns.count + plan.buildings.count + plan.agents.count + plan.props.count + plan.chunks.count + 2)
    }

    public var progress: Double { done ? 1 : Double(doneItems) / Double(total) }

    /// Do up to `budget` deletions. Returns true once the law has been carried out completely.
    @discardableResult public func step(_ budget: Int = 48) -> Bool {
        if done { return true }
        var left = budget
        while left > 0 && !done {
            switch phase {
            case 0:     // whole towns (guixu)
                if i >= plan.towns.count { next(); continue }
                if let t = s.settlements[plan.towns[i]], !t.abandoned { removeTown(t) }
                i += 1; left -= 8; doneItems += 1
            case 1:     // buildings
                if i >= plan.buildings.count { next(); continue }
                let ref = plan.buildings[i]
                if let t = s.settlements[ref.sid], let b = t.building(ref.bid) {
                    s.eraseBuilding(t, b, restore: true)
                    touched.insert(t.id)
                    result.buildings += 1
                }
                i += 1; left -= 4; doneItems += 1
            case 2:     // people
                if i >= plan.agents.count { next(); continue }
                if let a = s.agents[plan.agents[i]] { s.erase(a); result.agents += 1 }
                i += 1; left -= 1; doneItems += 1
            case 3:     // placed objects
                if i >= plan.props.count { next(); continue }
                let p = plan.props[i]
                if plan.mode == .guixu { result.props += 1 }     // they go with their chunk below
                else if s.world.removeProp(id: p.id, cx: p.cx, cy: p.cy) { result.props += 1 }
                i += 1; left -= 1; doneItems += 1
            case 4:     // map changes
                if i >= plan.chunks.count { next(); continue }
                let c = plan.chunks[i]
                let had = s.world.storedSize(MP.chunkKey(c.cx, c.cy)) > 0 || s.world.loaded(c.cx, c.cy)
                s.world.revertChunk(c.cx, c.cy)
                if had { result.chunks += 1 }
                // the land returns to nature all the way down: mines, ruins dug out and stairs under it go too
                if plan.mode == .guixu { let u = s.underworld(); if u.storedSize(MP.chunkKey(c.cx, c.cy)) > 0 || u.loaded(c.cx, c.cy) { u.revertChunk(c.cx, c.cy); result.chunks += 1 } }
                s.pressed = s.pressed.filter { $0.x >> 5 != c.cx || $0.y >> 5 != c.cy }
                i += 1; left -= 2; doneItems += 1
            case 5:     // history
                let n = min(plan.logLines, s.log.count)
                if n > 0 { s.log.removeFirst(n); result.logLines = n }
                var g = plan.graves
                let grave = s.content.tid("grave")
                for t in s.settlements.values.sorted(by: { $0.id < $1.id }) where g > 0 && t.graves > 0 && !t.abandoned {
                    let k = min(g, min(t.graves, s.realm.cfg.maxGraves))
                    // markers were placed row by row beside the square; take the newest away first
                    for n2 in stride(from: min(t.graves, s.realm.cfg.maxGraves) - 1, through: min(t.graves, s.realm.cfg.maxGraves) - k, by: -1) {
                        let p = t.center + TilePos(-8 - n2 % 6, 6 + n2 / 6)
                        if s.world.tile(2, p.x, p.y) == grave { s.world.setTile(2, p.x, p.y, 0) }
                    }
                    t.graves = min(t.graves, s.realm.cfg.maxGraves) - k
                    g -= k; result.graves += k
                }
                next(); doneItems += 1
            default:
                finish(); doneItems += 1
            }
        }
        return done
    }

    func next() { phase += 1; i = 0 }

    func removeTown(_ t: Settlement) {
        let others = s.settlements.values.filter { !$0.abandoned && $0 !== t && !plan.towns.contains($0.id) }
        let dest = others.min { a, b in
            let da = (a.center - t.center).lengthSquared, db = (b.center - t.center).lengthSquared
            return da != db ? da < db : a.id < b.id }
        for b in t.buildings { s.eraseBuilding(t, b, restore: false); result.buildings += 1 }
        t.graves = 0
        result.towns += 1
        guard let d = dest else { touched.insert(t.id); return }      // the last town keeps its people; only its works are gone
        let now = s.world.time
        if let g = s.garrison(t, create: false) { s.disband(g, into: d) }
        for mid in t.members {
            guard let a = s.agents[mid] else { continue }
            s.move(a, to: d)
            if a.legion == nil { a.refugee = now + s.realm.cfg.refugeeIntegrate * MP.year; a.job = "" }
            a.travelling = true
            a.travelTo = s.world.findFree(near: d.center + TilePos(a.id % 15 - 7, 9 + a.id % 4), maxR: 8).center
            result.displaced += 1
        }
        t.members = []
        t.abandoned = true
        s.detach(t)
        s.realm.legions.removeAll { $0.home == t.id }
        touched.insert(d.id)
    }

    func finish() {
        // towns that lost ground to a regional reset get their square back
        if plan.mode == .guixu {
            for id in plan.towns { if let t = s.settlements[id], !t.abandoned { s.stampCore(t) } }
            for t in s.settlements.values where !t.abandoned { touched.insert(t.id) }
        }
        for id in touched { if let t = s.settlements[id], !t.abandoned { s.refreshNav(t) } }
        result.refsFixed = s.repairReferences()
        if plan.mode == .thanos { s.realm.immigrationHold = s.world.time + plan.options.thanosHold * MP.year }
        s.realm.depots.removeAll { s.world.tile(2, $0.x, $0.y) != s.content.tid("crate") }
        // anyone left standing inside something solid is moved to free ground
        for a in s.agents.values where s.world.blocked(a.pos.tile.x, a.pos.tile.y) && a.legion == nil { a.pos = s.world.findFree(near: a.pos.tile, maxR: 8).center; a.task = nil; a.path = [] }
        if s.agents.isEmpty { s.restart(); result.restart = true }
        else { s.landCheck(); s.refreshNations() }
        result.bytesAfter = s.world.diskBytes
        done = true
    }
}
