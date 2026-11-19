import Foundation

// Seas, land and the ground a nation stands on (world warfare task book, section 2).
//
// * The sea: regions mostly of water are sea; the sea regions joined edge to edge make bodies of water. A
//   body of at least `openSeaRegions` regions is open sea: every nation may sail it. Smaller ones are lakes.
// * A port site is a land region on the edge of open sea (or a coastal region of open sea itself).
// * Land has a legal owner (who it belongs to by right) and a controller (who holds it now). Taking a city
//   changes who controls its land at once; only a truce that cedes it changes who owns it. Land no city
//   claims belongs to no one; the sea belongs to no one.
// * Every nation found at the start of a new world can reach a port on open sea from its capital: when it
//   cannot, the nearest port site it can reach by land that nobody owns is given to it. Worlds made before
//   this rule keep their land as it was.
// * The ground a nation stands on is read from real routes (passes are edges a vehicle can cross only
//   through mountains; a basin with an open plain way in is no basin), and reported in a line.
//
// Everything here is a pure function of the known regions, cities and ownership: the same world gives
// the same answers, whatever order it was explored in, and nothing here draws from the world's dice.

public struct CivGeoTrait: Equatable, Codable {
    public enum Kind: String, Codable, CaseIterable {
        case strait          // 双门海峡国: ports on two seas (or two coasts of one sea far apart by water)
        case basin           // 三关盆地国: fertile land reached only through a few mountain passes
        case delta           // 千汊河洲国: river land and wharves along many channels
        case islands         // 群岛跳港国: a chain of islands, supplied hop by hop
        case innerSea        // 内海环抱国 (later)
        case plateau         // 高原水塔国 (later)
        case terraces        // 瀑布台地国 (later)
        case longBay         // 长湾双港国 (later)
        case atoll           // 环礁泻湖国 (later)
        case blackSoil       // 背山黑土国 (later)
    }
    public var kind: Kind
    /// The places that make it so: the ports of a strait, the passes of a basin, the river regions of a
    /// delta, one region of each island of a chain.
    public var places: [Int64] = []
    /// How many of `places` the nation still holds.
    public var held = 0
    /// What the ground is worth: a strait's detour by sea (regions), a basin's passes, a chain's longest hop.
    public var value = 0.0
    public func line(zh: Bool) -> String {
        switch kind {
        case .strait:
            return zh ? "海峡两港仍控制 \(held) 座（绕行外海多 \(Int(value)) 个区域）" : "holds \(held) of \(places.count) strait ports (the way round is \(Int(value)) regions longer)"
        case .basin:
            let n = ["零", "一", "两", "三", "四", "五", "六"]
            return zh ? "\(n[min(places.count, 6)])关仍控制\(n[min(held, 6)])关" : "holds \(held) of its \(places.count) passes"
        case .delta: return zh ? "河洲 \(places.count) 处，仍控制 \(held) 处" : "\(held) of \(places.count) river isles held"
        case .islands: return zh ? "岛链 \(places.count) 岛，最长一跳 \(Int(value)) 个区域" : "a chain of \(places.count) islands, longest hop \(Int(value)) regions"
        case .innerSea: return zh ? "环抱内海，港口 \(held)/\(places.count) 在手" : "round an inner sea, \(held) of \(places.count) ports held"
        case .plateau: return zh ? "高原水塔，河谷 \(held)/\(places.count) 在手" : "a high plateau, \(held) of \(places.count) valleys held"
        case .terraces: return zh ? "瀑布台地，\(places.count) 层仍连通 \(held) 层" : "terraced land, \(held) of \(places.count) steps joined"
        case .longBay: return zh ? "长湾双港，港口 \(held)/\(places.count) 在手" : "a long bay, \(held) of \(places.count) ports held"
        case .atoll: return zh ? "环礁泻湖，\(places.count) 处礁岛" : "an atoll of \(places.count) reef islands"
        case .blackSoil: return zh ? String(format: "背山黑土，平原肥力 %.0f%%", value * 100) : String(format: "black soil under the mountains, %.0f%% fertile", value * 100)
        }
    }
}

/// What the geography keeps between asks (not saved: it is worked out again from the regions).
public final class CivGeoCache {
    var water: (regions: Int, of: [Int64: Int64], size: [Int64: Int])?
    var traits: [Int: (hour: Int, regions: Int, list: [CivGeoTrait])] = [:]
    public init() {}
    /// Something changed: the land, who holds a pass, who holds a city.
    public func clear() { water = nil; traits = [:] }
}

extension Civ {
    // MARK: - sea

    /// A region of sea (ships can sail it).
    @inline(__always) public func isSea(_ r: CivRegion) -> Bool { r.water >= 0.35 && r.land < 0.65 }
    /// A region of land (people can live on it).
    @inline(__always) public func isLand(_ r: CivRegion) -> Bool { r.land >= 0.2 }

    static let four: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// The bodies of water among the known regions: region -> body id (the smallest region key in it), and
    /// each body's size. Open sea is a body of `openSeaRegions` regions or more.
    public func waterBodies() -> (of: [Int64: Int64], size: [Int64: Int]) {
        // the sea changes only when regions are found: kept until then (panels ask every second)
        if let w = geoCache.water, w.regions == regions.count { return (w.of, w.size) }
        var of: [Int64: Int64] = [:], size: [Int64: Int] = [:]
        for k in regions.keys.sorted() {
            guard of[k] == nil, let r = regions[k], isSea(r) else { continue }
            var q = [k], h = 0, members: [Int64] = []
            of[k] = k
            while h < q.count {
                let c = q[h]; h += 1; members.append(c)
                guard let cr = regions[c] else { continue }
                for (dx, dy) in Civ.four {
                    let nk = MP.chunkKey(cr.rx + dx, cr.ry + dy)
                    guard of[nk] == nil, let nr = regions[nk], isSea(nr) else { continue }
                    of[nk] = k; q.append(nk)
                }
            }
            let id = members.min()!
            for m in members { of[m] = id }
            size[id] = members.count
        }
        geoCache.water = (regions.count, of, size)
        return (of, size)
    }

    public func isOpenSea(_ body: Int64, _ size: [Int64: Int]) -> Bool { (size[body] ?? 0) >= cfg.openSeaRegions }

    /// Where a port can be built: a land region beside open sea. Returns the bodies of open sea it touches
    /// (nil when it is no port site) and whether the water there is deep (carriers and liners).
    public func portSite(_ key: Int64, bodies: (of: [Int64: Int64], size: [Int64: Int])) -> (seas: [Int64], deep: Bool)? {
        guard let r = regions[key], isLand(r) else { return nil }
        var seas = Set<Int64>(), deep = r.deep >= 0.15
        if let b = bodies.of[key], isOpenSea(b, bodies.size) { seas.insert(b) }
        for (dx, dy) in Civ.four {
            let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
            guard let b = bodies.of[nk], isOpenSea(b, bodies.size) else { continue }
            seas.insert(b)
            if (regions[nk]?.deep ?? 0) >= 0.3 { deep = true }
        }
        return seas.isEmpty ? nil : (seas.sorted(), deep)
    }

    // MARK: - land: who owns it, who holds it

    /// Who owns a region by right (nil: no one).
    public func legalOwner(_ key: Int64) -> Int? { regions[key]?.legal }
    /// Who holds a region now (nil: no one): whoever holds the city it answers to, the moment it changes hands.
    public func controller(_ key: Int64) -> Int? { regions[key].flatMap(holder) }
    @inline(__always) public func holder(_ r: CivRegion) -> Int? {
        if let h = heldPasses[r.key] { return h }
        if let cl = r.claim, let c = cities[cl], polities[c.nation]?.status != .history { return c.nation }
        return r.control
    }

    /// Lay out the land: every city claims its own region, and land within `claimRadius` regions goes to
    /// the nearest city (ties to the older city). A region keeps the owner it was given; it is held by
    /// whoever holds the city that claims it. Sea is never claimed. Cheap; run daily and after captures.
    public func refreshTerritory() {
        let live = cities.values.filter { polities[$0.nation]?.status != .history }.sorted { $0.id < $1.id }
        // which city each piece of land answers to (nearest; a city always answers for its own region)
        var best: [Int64: (d: Int, city: Int)] = [:]
        let R = cfg.claimRadius
        for c in live {
            for dy in -R...R { for dx in -R...R {
                let d = abs(dx) + abs(dy)
                guard d <= R else { continue }
                let k = MP.chunkKey(c.rx + dx, c.ry + dy)
                guard let r = regions[k], isLand(r) else { continue }
                if r.city != nil && r.city != c.id { continue }
                if let b = best[k], b.d < d || (b.d == d && b.city < c.id) { continue }
                best[k] = (d, c.id)
            } }
        }
        for k in regions.keys.sorted() {
            guard var r = regions[k] else { continue }
            let old = r
            if let b = best[k], let c = cities[b.city] {
                // land already given (by a cession or the coast rule) keeps its owner; new land takes the city's
                if r.claim == nil || cities[r.claim!] == nil || r.legal == nil { r.claim = b.city }
                if r.legal == nil { r.legal = c.nation }
                if let owner = r.claim.flatMap({ cities[$0] }) { r.control = owner.nation }
                else { r.control = c.nation }
            } else if let cl = r.claim, let c = cities[cl] {
                r.control = c.nation              // given land far from the city still follows it
            } else if r.claim != nil {
                r.claim = nil; r.control = r.legal.flatMap { polities[$0]?.status == .active ? $0 : nil }
            }
            if r.legal.map({ polities[$0] == nil }) == true { r.legal = nil }
            if r != old { regions[k] = r }
        }
        // a nation that passed into another hands its land on by right
        for k in regions.keys.sorted() {
            guard let lg = regions[k]?.legal, let p = polities[lg], p.status == .history, let into = p.mergedInto else { continue }
            regions[k]!.legal = into
        }
    }

    /// A truce gives the land of a city to the nation holding it: its region and the land that answers to it.
    public func cede(city id: Int) {
        guard let c = cities[id] else { return }
        for k in regions.keys.sorted() where regions[k]?.claim == id || k == c.regionKey { regions[k]!.legal = c.nation; regions[k]!.control = c.nation }
    }

    /// Regions held by someone other than their owner (occupied or contested).
    public func occupied() -> [Int64] { regions.keys.sorted().filter { k in regions[k].map { r in let h = holder(r); return r.legal != nil && h != nil && r.legal != h } ?? false } }

    /// Land a nation owns, and land it holds.
    public func territory(of n: Int, legal: Bool = false) -> [Int64] {
        regions.keys.sorted().filter { k in legal ? regions[k]?.legal == n : regions[k].flatMap(holder) == n }
    }

    // MARK: - ground routes over land someone holds

    /// A ground route for a nation's people: never through a stronghold (a city or a mountain pass) held by
    /// a nation it is at war with; taking the pass opens the way at once. Nil when there is none.
    public func landRoute(for n: Int, from a: Int64, to b: Int64, size: CivSize = .vehicle, through: ((CivRegion) -> Bool)? = nil) -> [Int64]? {
        if a == b { return [a] }
        guard regions[a] != nil, regions[b] != nil else { return nil }
        var prev: [Int64: Int64] = [a: a]
        var q = [a], h = 0
        while h < q.count {
            let k = q[h]; h += 1
            guard let r = regions[k] else { continue }
            for (dx, dy) in Civ.four {
                let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                guard prev[nk] == nil, let nr = regions[nk], passable(r, nr, size: size, layer: .ground) else { continue }
                // strongholds close the way: a city or a mountain pass held by an enemy (open land does not)
                if let c = holder(nr), c != n, atWar(c, n), nk != b, nr.city != nil || nr.mountain >= cfg.passMountain { continue }
                if let t = through, !t(nr), nk != b { continue }
                prev[nk] = k
                if nk == b {
                    var path = [b], cur = b
                    while cur != a { cur = prev[cur]!; path.append(cur) }
                    return path.reversed()
                }
                q.append(nk)
            }
        }
        return nil
    }

    /// The port a nation reaches from its capital (or first city): a port site it holds that its people can
    /// get to by land without passing a city or pass held by an enemy, nearest first. Nil: no way to the sea.
    public func seaAccess(_ n: Int, bodies: (of: [Int64: Int64], size: [Int64: Int])? = nil) -> Int64? { seaPath(n, bodies: bodies)?.last }

    /// The way from a nation's capital to that port (capital first, port last).
    public func seaPath(_ n: Int, bodies: (of: [Int64: Int64], size: [Int64: Int])? = nil) -> [Int64]? {
        let bodies = bodies ?? waterBodies()
        guard let home = homeCity(n) else { return nil }
        var best: [Int64]?
        for k in regions.keys.sorted() {
            guard let r = regions[k], holder(r) == n, portSite(k, bodies: bodies) != nil,
                  let way = landRoute(for: n, from: home.regionKey, to: k, size: .person) else { continue }
            if best == nil || way.count < best!.count { best = way }
        }
        return best
    }

    /// A nation's capital, or its first city.
    func homeCity(_ n: Int) -> CivCity? {
        (polities[n]?.capital.flatMap { cities[$0] }).flatMap({ $0.nation == n ? $0 : nil }) ?? cities(of: n).first
    }

    /// The coast rule of a new world: each nation without a port on open sea is given the nearest port site its
    /// people can reach by land: one nobody owns if there is one, else a piece of a neighbour's coast that is
    /// neither a city nor that neighbour's only port. When the known land has none in reach, more of the world
    /// is surveyed (up to `coastSearch` regions out), the same for the same world. Each nation is looked at
    /// once; one that still has none is reported, never made up.
    @discardableResult public func applyCoastRule(gen: Generator?) -> [Int] {
        guard coastRule else { return [] }
        let todo = polities.keys.sorted().filter { polities[$0]!.status == .active && !seaChecked.contains($0) && homeCity($0) != nil }
        guard !todo.isEmpty else { return [] }
        refreshTerritory()
        var bodies = waterBodies()
        for id in todo { seaChecked.insert(id) }
        for id in todo {
            guard let p = polities[id], let home = homeCity(id), seaAccess(id, bodies: bodies) == nil else { continue }
            var port = freeCoast(for: id, from: home.regionKey, bodies: bodies)
            if port == nil, let gen = gen {
                for ring in 1...cfg.coastSearch {
                    var added = false
                    for dy in -ring...ring { for dx in -ring...ring where max(abs(dx), abs(dy)) == ring {
                        if discover(home.rx + dx, home.ry + dy, gen: gen, occupied: true) { added = true }
                    } }
                    if added { bodies = waterBodies() }
                    if let k = freeCoast(for: id, from: home.regionKey, bodies: bodies) { port = k; break }
                }
            }
            guard let k = port else { continue }
            let from = regions[k]!.legal
            regions[k]!.legal = id; regions[k]!.control = id; regions[k]!.claim = home.id
            say("coast_granted", [p.nameEn, p.nameZh], [id] + (from.map { [$0] } ?? []), region: k)
        }
        return todo.filter { polities[$0]?.status == .active && seaAccess($0, bodies: bodies) == nil }
    }

    /// The nearest port site a nation's people can reach by land from `from` that it may be given: nobody's
    /// first; else another nation's, if it is not a city and that nation keeps another port.
    func freeCoast(for n: Int, from: Int64, bodies: (of: [Int64: Int64], size: [Int64: Int])) -> Int64? {
        var ports: [Int: Int] = [:]
        for k in regions.keys.sorted() { if let o = regions[k]?.legal, portSite(k, bodies: bodies) != nil { ports[o, default: 0] += 1 } }
        var fallback: Int64?
        var seen: Set<Int64> = [from], q = [from], h = 0
        while h < q.count {
            let k = q[h]; h += 1
            if let r = regions[k], portSite(k, bodies: bodies) != nil, r.city == nil || cities[r.city!]?.nation == n {
                if r.legal == nil || r.legal == n { return k }
                if fallback == nil, let o = r.legal, (ports[o] ?? 0) > 1 { fallback = k }
            }
            guard let r = regions[k] else { continue }
            for (dx, dy) in Civ.four {
                let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                guard !seen.contains(nk), let nr = regions[nk], isLand(nr), passable(r, nr, size: .person, layer: .ground) else { continue }
                seen.insert(nk); q.append(nk)
            }
        }
        return fallback
    }

    // MARK: - the ground a nation stands on

    /// What the ground makes of a nation, judged by real routes. The first four kinds of the task book.
    public func traits(of n: Int, bodies given: (of: [Int64: Int64], size: [Int64: Int])? = nil) -> [CivGeoTrait] {
        // read once a game hour per nation (the ground changes with captures, which are hourly at most)
        let hour = Int(time / (MP.daySeconds / 24))
        if let t = geoCache.traits[n], t.hour == hour, t.regions == regions.count { return t.list }
        let out = computeTraits(n, given)
        geoCache.traits[n] = (hour, regions.count, out)
        return out
    }

    func computeTraits(_ n: Int, _ given: (of: [Int64: Int64], size: [Int64: Int])?) -> [CivGeoTrait] {
        let bodies = given ?? waterBodies()
        let own = Set(territory(of: n, legal: true))
        guard !own.isEmpty else { return [] }
        var out: [CivGeoTrait] = []
        if let t = straitTrait(n, own, bodies) { out.append(t) }
        if let t = basinTrait(n, own) { out.append(t) }
        if let t = deltaTrait(n, own) { out.append(t) }
        if let t = islandTrait(n, own) { out.append(t) }
        out += formTraits(n, own, bodies)
        return out
    }

    /// The most telling line for a nation's card: its first trait, or nil.
    public func groundLine(of n: Int, zh: Bool) -> String? { traits(of: n).first?.line(zh: zh) }

    /// The six later kinds, where the world made them (the region's landform), each with a check on the ground
    /// as it is: ports for the seas and bays, valleys for a plateau, steps still joined for terraces, rich
    /// soil for black-soil land.
    func formTraits(_ n: Int, _ own: Set<Int64>, _ bodies: (of: [Int64: Int64], size: [Int64: Int])) -> [CivGeoTrait] {
        var by: [String: [Int64]] = [:]
        for k in own.sorted() { if let f = regions[k]?.form { by[f, default: []].append(k) } }
        var out: [CivGeoTrait] = []
        for kind in [CivGeoTrait.Kind.innerSea, .plateau, .terraces, .longBay, .atoll, .blackSoil] {
            guard let land = by[kind.rawValue], !land.isEmpty else { continue }
            let held = { (ks: [Int64]) in ks.filter { self.controller($0) == n }.count }
            switch kind {
            case .innerSea, .longBay:
                let ports = land.filter { portSite($0, bodies: bodies) != nil || (regions[$0].map { r in Civ.four.contains { d in bodies.of[MP.chunkKey(r.rx + d.0, r.ry + d.1)] != nil } } ?? false) }
                guard ports.count >= (kind == .longBay ? 2 : 1) else { continue }
                out.append(CivGeoTrait(kind: kind, places: ports, held: held(ports), value: Double(ports.count)))
            case .plateau:
                let valleys = land.filter { (regions[$0]?.mountain ?? 1) < cfg.passMountain }
                out.append(CivGeoTrait(kind: kind, places: valleys, held: held(valleys), value: Double(valleys.count)))
            case .terraces:
                // steps joined: land regions of the form reachable from the first by ground
                let start = land[0]
                let joined = land.filter { landRoute(for: n, from: start, to: $0, size: .vehicle) != nil }
                out.append(CivGeoTrait(kind: kind, places: land, held: joined.count, value: Double(land.count)))
            case .atoll:
                out.append(CivGeoTrait(kind: kind, places: land, held: held(land), value: Double(land.count)))
            default:
                // the plain under the mountains: its fertility, and a mountain at its back
                let plain = land.filter { (regions[$0]?.mountain ?? 1) < cfg.passMountain }
                let backed = land.contains { (regions[$0]?.mountain ?? 0) >= cfg.passMountain } || plain.contains { k in regions[k].map { r in Civ.four.contains { d in (regions[MP.chunkKey(r.rx + d.0, r.ry + d.1)]?.mountain ?? 0) >= cfg.passMountain } } ?? false }
                guard !plain.isEmpty, backed else { continue }
                let fert = plain.compactMap { regions[$0]?.fertility }.reduce(0, +) / Double(plain.count)
                out.append(CivGeoTrait(kind: kind, places: land, held: held(land), value: fert))
            }
        }
        return out
    }

    /// Sea distance (regions, 4 neighbours) between two sea regions within one body; nil when apart.
    func seaDistance(_ a: Int64, _ b: Int64, bodies: (of: [Int64: Int64], size: [Int64: Int])) -> Int? {
        if a == b { return 0 }
        var dist: [Int64: Int] = [a: 0], q = [a], h = 0
        while h < q.count {
            let k = q[h]; h += 1
            guard let r = regions[k] else { continue }
            for (dx, dy) in Civ.four {
                let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                guard dist[nk] == nil, bodies.of[nk] != nil else { continue }
                dist[nk] = dist[k]! + 1
                if nk == b { return dist[nk] }
                q.append(nk)
            }
        }
        return nil
    }

    /// Two ports on two seas (or on two coasts of one sea, the way round by water much longer than the way
    /// across the nation's land): a strait. Its value is how much longer the way round is.
    func straitTrait(_ n: Int, _ own: Set<Int64>, _ bodies: (of: [Int64: Int64], size: [Int64: Int])) -> CivGeoTrait? {
        var ports: [(key: Int64, seas: [Int64], water: [Int64])] = []
        for k in own.sorted() {
            guard let ps = portSite(k, bodies: bodies), let r = regions[k] else { continue }
            var water: [Int64] = []
            if bodies.of[k] != nil { water.append(k) }
            for (dx, dy) in Civ.four { let nk = MP.chunkKey(r.rx + dx, r.ry + dy); if let b = bodies.of[nk], isOpenSea(b, bodies.size) { water.append(nk) } }
            ports.append((k, ps.seas, water))
        }
        guard ports.count >= 2 else { return nil }
        var best: (Int64, Int64, Double)?
        for i in 0..<ports.count { for j in (i + 1)..<ports.count {
            let a = ports[i], b = ports[j]
            let land = Double(landRoute(for: n, from: a.key, to: b.key, size: .person, through: { own.contains($0.key) })?.count ?? 0) - 1
            guard land >= 0 else { continue }
            let twoSeas = Set(a.seas).isDisjoint(with: b.seas)
            var detour: Double
            if twoSeas { detour = Double(cfg.straitDetour * 4) }        // no way round at all among the known seas
            else {
                var d = Int.max
                for wa in a.water { for wb in b.water { if let x = seaDistance(wa, wb, bodies: bodies) { d = min(d, x) } } }
                guard d != Int.max else { continue }
                detour = Double(d) - land
            }
            if detour >= Double(cfg.straitDetour), best == nil || detour > best!.2 { best = (a.key, b.key, detour) }
        } }
        guard let s = best else { return nil }
        let held = [s.0, s.1].filter { controller($0) == n }.count
        return CivGeoTrait(kind: .strait, places: [s.0, s.1], held: held, value: s.2)
    }

    /// Fertile low land round the capital that a vehicle can leave only through mountain passes (two to four
    /// of them), with no open plain way out: a basin. The low land is found from the capital over the
    /// nation's own land below the mountains; each pass is the mountain region a vehicle can cross from it.
    func basinTrait(_ n: Int, _ own: Set<Int64>) -> CivGeoTrait? {
        guard let home = polities[n]?.capital.flatMap({ cities[$0] }) ?? cities(of: n).first,
              let hr = regions[home.regionKey], hr.mountain < cfg.passMountain else { return nil }
        var core: Set<Int64> = [home.regionKey], q = [home.regionKey], h = 0
        while h < q.count {
            let k = q[h]; h += 1
            guard let r = regions[k] else { continue }
            for (dx, dy) in Civ.four {
                let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                guard !core.contains(nk), own.contains(nk), let nr = regions[nk], isLand(nr), nr.mountain < cfg.passMountain,
                      passable(r, nr, size: .vehicle, layer: .ground) else { continue }
                core.insert(nk); q.append(nk)
            }
        }
        guard core.count >= 3 else { return nil }
        let fert = core.compactMap { regions[$0]?.fertility }.reduce(0, +) / Double(core.count)
        guard fert >= 0.3 else { return nil }
        var passes = Set<Int64>(), plain = false
        for k in core.sorted() {
            guard let r = regions[k] else { continue }
            for (dx, dy) in Civ.four {
                let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                guard !core.contains(nk), let nr = regions[nk], isLand(nr), passable(r, nr, size: .vehicle, layer: .ground) else { continue }
                if nr.mountain >= cfg.passMountain { passes.insert(nk) } else { plain = true }
            }
        }
        guard !plain, (2...4).contains(passes.count) else { return nil }
        let list = passes.sorted()
        return CivGeoTrait(kind: .basin, places: list, held: list.filter { controller($0) == n }.count, value: Double(list.count))
    }

    /// Several river regions with much water in them (`deltaIsles`, `deltaWater`): a delta of channels and wharves.
    func deltaTrait(_ n: Int, _ own: Set<Int64>) -> CivGeoTrait? {
        let isles = own.sorted().filter { k in regions[k].map { $0.river && isLand($0) && $0.water >= cfg.deltaWater } ?? false }
        guard isles.count >= cfg.deltaIsles else { return nil }
        return CivGeoTrait(kind: .delta, places: isles, held: isles.filter { controller($0) == n }.count, value: Double(isles.count))
    }

    /// Land in three or more pieces apart by water: an island chain. Value: the longest hop by sea between
    /// an island and its nearest neighbour (regions).
    func islandTrait(_ n: Int, _ own: Set<Int64>) -> CivGeoTrait? {
        let land = own.filter { regions[$0].map(isLand) ?? false }
        var island: [Int64: Int] = [:], heads: [Int64] = []
        for k in land.sorted() where island[k] == nil {
            let id = heads.count; heads.append(k)
            var q = [k], h = 0; island[k] = id
            while h < q.count {
                let c = q[h]; h += 1
                guard let r = regions[c] else { continue }
                for (dx, dy) in Civ.four {
                    let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                    guard land.contains(nk), island[nk] == nil, let nr = regions[nk], passable(r, nr, size: .person, layer: .ground) else { continue }
                    island[nk] = id; q.append(nk)
                }
            }
        }
        guard heads.count >= 3 else { return nil }
        // longest of the nearest hops (Chebyshev distance between the islands' regions)
        var longest = 0
        for i in 0..<heads.count {
            var near = Int.max
            for (a, ia) in island where ia == i { for (b, ib) in island where ib != i {
                guard let ra = regions[a], let rb = regions[b] else { continue }
                near = min(near, max(abs(ra.rx - rb.rx), abs(ra.ry - rb.ry)))
            } }
            if near != Int.max { longest = max(longest, near) }
        }
        return CivGeoTrait(kind: .islands, places: heads, held: heads.filter { controller($0) == n }.count, value: Double(longest))
    }
}
