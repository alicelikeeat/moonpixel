import Foundation

// The civilisation layer: nations beyond the few towns around the player, their people as groups
// (counted to the person, by age and by how hungry they are), their food from field to mouth, their
// industry, research and arms. It is the regional and the national level of the same world the towns
// of Society.swift live in; those towns are its detailed level and are not counted twice.
//
// Rules that hold everywhere here:
// * People are whole numbers. Every change of a city's people is a birth, a death with a cause, a
//   move (to another city, onto the road, into an army) or the first count of a place found for the
//   first time. `audit()` checks the sum every day.
// * Goods are moved by taking them in one step and putting them down in another; what is on the
//   road belongs to the trip. Nothing is in two places, and nothing eats from a store it cannot reach.
// * It runs on the game clock alone, in fixed hourly steps, the same near and far and at any speed.
//   The camera, the 3D view and the frame rate never change what happens.

public struct CivPeople: Codable, Equatable {
    /// [band * 6 + hunger state]: band 0 children, 1 adults, 2 elders; state 0 fed ... 5 dying.
    public var n = [Int](repeating: 0, count: 18)
    public init() {}
    public init(adults: Int, children: Int = 0, elders: Int = 0) { n[6] = adults; n[0] = children; n[12] = elders }
    public var total: Int { n.reduce(0, +) }
    public func band(_ b: Int) -> Int { (0..<6).reduce(0) { $0 + n[b * 6 + $1] } }
    public func state(_ s: Int) -> Int { n[s] + n[6 + s] + n[12 + s] }
    public var isEmpty: Bool { total == 0 }
    public mutating func add(_ o: CivPeople) { for i in 0..<18 { n[i] += o.n[i] } }

    /// Take `k` people spread over `slots` in proportion (largest remainders, ties by slot), so the
    /// same people are taken every time. Returns who was taken.
    public mutating func take(_ k: Int, from slots: [Int] = Array(0..<18)) -> CivPeople {
        var out = CivPeople()
        let have = slots.reduce(0) { $0 + n[$1] }
        let want = min(k, have)
        guard want > 0 else { return out }
        var rem: [(Int, Double)] = []
        var given = 0
        for s in slots {
            let exact = Double(want) * Double(n[s]) / Double(have)
            let f = Int(exact)
            out.n[s] = f; given += f
            rem.append((s, exact - Double(f)))
        }
        rem.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var i = 0
        while given < want { let s = rem[i % rem.count].0; if out.n[s] < n[s] { out.n[s] += 1; given += 1 }; i += 1 }
        for s in slots { n[s] -= out.n[s] }
        return out
    }
    public mutating func takeAdults(_ k: Int) -> CivPeople { take(k, from: Array(6..<12)) }
    /// Average fullness 0 (all fed) ... 1 (all dying), for display only.
    public var hungerIndex: Double { total == 0 ? 0 : Double((0..<6).reduce(0) { $0 + state($1) * $1 }) / Double(total * 5) }
}

/// Everything that changed a place's people and food, so any figure can be checked by adding up.
public struct CivLedger: Codable, Equatable {
    public var births = 0, newly = 0, migIn = 0, migOut = 0, enlisted = 0, discharged = 0
    public var deaths: [String: Int] = [:]                 // by cause: old, illness, hunger, battle, journey, accident
    public var made: [String: Double] = [:], cameIn: [String: Double] = [:], wentOut: [String: Double] = [:]
    /// Goods that enter the layer from outside it: a place's stores when first found, gifts from the detailed towns.
    public var found: [String: Double] = [:]
    public var eaten: [String: Double] = [:], spoiled: [String: Double] = [:], lost: [String: Double] = [:], used: [String: Double] = [:]
    public init() {}
    public var deathTotal: Int { deaths.values.reduce(0, +) }
    mutating func add(_ d: WritableKeyPath<CivLedger, [String: Double]>, _ k: String, _ v: Double) { if v != 0 { self[keyPath: d][k, default: 0] += v } }
}

public struct CivRegion: Codable, Equatable {
    public var rx = 0, ry = 0
    public var land = 0.0, water = 0.0, deep = 0.0, mountain = 0.0
    public var fertility = 0.0, forest = 0.0, ore = 0.0, coal = 0.0, oil = 0.0
    public var river = false
    public var city: Int?                                   // the city in it (one at most)
    public var foundAt = 0.0
    public var key: Int64 { MP.chunkKey(rx, ry) }
    public var coast: Bool { land > 0.25 && water > 0.12 }
}

public struct CivTrip: Codable, Equatable {
    public var id = 0, nation = 0
    public var from = 0, to = 0                             // city ids
    public var route: [Int64] = []                          // regions, from first to last
    public var leg = 0                                      // index in route where it is
    public var progress = 0.0                               // days into the current leg
    public var people = CivPeople()
    public var cargo: [String: Double] = [:]
    public var refugee = false
    public var settle: Int64?                               // a new town is founded here when they arrive
    public var waiting = 0.0                                // days held up by a blockade
}

public struct CivNews: Codable, Equatable {
    public var t = 0.0, key = "", args: [String] = [], nations: [Int] = [], region: Int64?
}

public final class CivCity: Codable {
    public var id = 0, nation = 0
    public var nameEn = "", nameZh = ""
    public var rx = 0, ry = 0
    public var founded = 0.0
    /// The Society town this city is (detailed level); its people and food are counted there, not here.
    public var detail: Int?
    public var people = CivPeople()
    public var sick = 0
    /// Who the people feel they belong to: nation id -> share (sums to 1). Changes slowly, not with the flag.
    public var culture: [Int: Double] = [:]
    public var stock: [String: Double] = [:]
    public var reserved: [String: Double] = [:]
    public var facilities: [String: Int] = [:]
    public var cropDue = 0.0, cropPlots = 0
    public var ration = CivRation.normal
    public var rationNext: CivRation?
    public var rationAt = 0.0
    public var unrest = 0.0, wealth = 0.0
    public var crowding = 0.0, thirst = 0.0, foodDays = 99.0, coverage = 1.0, jobs = 0.0
    public var dailyNeed = 0.0, dailyMade = 0.0
    public var energyMade = 0.0, energyUsed = 0.0
    public var besieged = false
    public var occupier: Int?, occupyHours = 0.0
    public var ledger = CivLedger()
    public var today = CivLedger()                          // the day so far; becomes `yesterday`
    public var yesterday = CivLedger()
    public var builds: [CivBuild] = []
    public var lastDay = -1
    public init() {}
    public func name(zh: Bool) -> String { zh ? nameZh : nameEn }
    public var pop: Int { people.total }
    public var regionKey: Int64 { MP.chunkKey(rx, ry) }
    public func has(_ f: String) -> Int { facilities[f] ?? 0 }
    public func free(_ k: String) -> Double { max(0, (stock[k] ?? 0) - (reserved[k] ?? 0)) }
    public var foodNutrition: Double { CivFood.all.reduce(0) { $0 + (stock[$1.key] ?? 0) * $1.nutrition } }
    public var identity: Int { culture.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? nation }
}

/// A facility going up: materials are taken when it starts, work is done over days.
public struct CivBuild: Codable, Equatable { public var facility = "", daysLeft = 0.0 }

public final class Civ: Codable {
    public static let schemaVersion = 1
    public var schema = Civ.schemaVersion
    public var cfg = CivConfig()
    public var seed = 0
    public var time = 0.0                                   // game seconds, as the world's clock
    public var day = 0
    public var hourAcc = 0.0
    public var regions: [Int64: CivRegion] = [:]
    public var cities: [Int: CivCity] = [:]
    public var trips: [Int: CivTrip] = [:]
    public var polities: [Int: CivPolity] = [:]
    public var relations: [String: CivRelation] = [:]
    public var forces: [Int: CivForce] = [:]
    public var units: [Int: CivUnit] = [:]
    public var projects: [Int: CivProject] = [:]
    public var strikes: [CivStrike] = []
    public var wrecks: [CivWreck] = []
    public var news: [CivNews] = []
    public var fights: [CivFight] = []
    /// How many times each kind of news has happened, ever (the news list itself keeps only the latest).
    public var happened: [String: Int] = [:]
    /// What each nation knows of enemy machines: "nation:unit" -> where and when last seen.
    public var intel: [String: CivSighting] = [:]
    public var nextCity = 1, nextTrip = 1, nextForce = 1, nextUnit = 1, nextProject = 1
    /// The ids nations are given; never handed out twice (shared with the realm's own nations).
    public var nextNation = 1
    public var totals = CivLedger()
    public var rng = RNG(seed: 1)
    /// New nations the realm must learn of (id, names, colour, emblem); the bridge takes them.
    public var born: [Int] = []
    public init(seed: Int) { self.seed = seed; rng = RNG(seed: seed &* 7919 &+ 17) }

    // Saving. The rules (`cfg`) are not saved: they belong to the version of the game. Every field is
    // read if present, so a save from before a field existed still opens (with that field's default).
    enum CodingKeys: String, CodingKey {
        case schema, seed, time, day, hourAcc, regions, cities, trips, polities, relations, forces, units, projects, strikes, wrecks, news, fights, happened, intel
        case nextCity, nextTrip, nextForce, nextUnit, nextProject, nextNation, totals, rng, born
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema); try c.encode(seed, forKey: .seed); try c.encode(time, forKey: .time); try c.encode(day, forKey: .day); try c.encode(hourAcc, forKey: .hourAcc)
        // dictionaries are written as lists in id order, so the same world always gives the same file
        try c.encode(regions.keys.sorted().map { regions[$0]! }, forKey: .regions)
        try c.encode(cities.keys.sorted().map { cities[$0]! }, forKey: .cities)
        try c.encode(trips.keys.sorted().map { trips[$0]! }, forKey: .trips)
        try c.encode(polities.keys.sorted().map { polities[$0]! }, forKey: .polities)
        try c.encode(relations.keys.sorted().map { relations[$0]! }, forKey: .relations)
        try c.encode(forces.keys.sorted().map { forces[$0]! }, forKey: .forces)
        try c.encode(units.keys.sorted().map { units[$0]! }, forKey: .units)
        try c.encode(projects.keys.sorted().map { projects[$0]! }, forKey: .projects)
        try c.encode(strikes, forKey: .strikes); try c.encode(wrecks, forKey: .wrecks); try c.encode(news, forKey: .news); try c.encode(fights, forKey: .fights)
        try c.encode(happened, forKey: .happened); try c.encode(intel, forKey: .intel)
        try c.encode(nextCity, forKey: .nextCity); try c.encode(nextTrip, forKey: .nextTrip); try c.encode(nextForce, forKey: .nextForce)
        try c.encode(nextUnit, forKey: .nextUnit); try c.encode(nextProject, forKey: .nextProject); try c.encode(nextNation, forKey: .nextNation)
        try c.encode(totals, forKey: .totals); try c.encode(rng, forKey: .rng); try c.encode(born, forKey: .born)
    }
    public required init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        guard schema <= Civ.schemaVersion else { throw DecodingError.dataCorruptedError(forKey: .schema, in: c, debugDescription: "made by a newer version") }
        seed = try c.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
        day = try c.decodeIfPresent(Int.self, forKey: .day) ?? 0
        hourAcc = try c.decodeIfPresent(Double.self, forKey: .hourAcc) ?? 0
        for r in try c.decodeIfPresent([CivRegion].self, forKey: .regions) ?? [] { regions[r.key] = r }
        for x in try c.decodeIfPresent([CivCity].self, forKey: .cities) ?? [] { cities[x.id] = x }
        for x in try c.decodeIfPresent([CivTrip].self, forKey: .trips) ?? [] { trips[x.id] = x }
        for x in try c.decodeIfPresent([CivPolity].self, forKey: .polities) ?? [] { polities[x.id] = x }
        for x in try c.decodeIfPresent([CivRelation].self, forKey: .relations) ?? [] { relations[CivRelation.key(x.a, x.b)] = x }
        for x in try c.decodeIfPresent([CivForce].self, forKey: .forces) ?? [] { forces[x.id] = x }
        for x in try c.decodeIfPresent([CivUnit].self, forKey: .units) ?? [] { units[x.id] = x }
        for x in try c.decodeIfPresent([CivProject].self, forKey: .projects) ?? [] { projects[x.id] = x }
        strikes = try c.decodeIfPresent([CivStrike].self, forKey: .strikes) ?? []
        wrecks = try c.decodeIfPresent([CivWreck].self, forKey: .wrecks) ?? []
        news = try c.decodeIfPresent([CivNews].self, forKey: .news) ?? []
        fights = try c.decodeIfPresent([CivFight].self, forKey: .fights) ?? []
        happened = try c.decodeIfPresent([String: Int].self, forKey: .happened) ?? [:]
        intel = try c.decodeIfPresent([String: CivSighting].self, forKey: .intel) ?? [:]
        nextCity = try c.decodeIfPresent(Int.self, forKey: .nextCity) ?? (cities.keys.max() ?? 0) + 1
        nextTrip = try c.decodeIfPresent(Int.self, forKey: .nextTrip) ?? (trips.keys.max() ?? 0) + 1
        nextForce = try c.decodeIfPresent(Int.self, forKey: .nextForce) ?? (forces.keys.max() ?? 0) + 1
        nextUnit = try c.decodeIfPresent(Int.self, forKey: .nextUnit) ?? (units.keys.max() ?? 0) + 1
        nextProject = try c.decodeIfPresent(Int.self, forKey: .nextProject) ?? (projects.keys.max() ?? 0) + 1
        nextNation = try c.decodeIfPresent(Int.self, forKey: .nextNation) ?? (polities.keys.max() ?? 0) + 1
        totals = try c.decodeIfPresent(CivLedger.self, forKey: .totals) ?? CivLedger()
        rng = try c.decodeIfPresent(RNG.self, forKey: .rng) ?? RNG(seed: seed)
        born = try c.decodeIfPresent([Int].self, forKey: .born) ?? []
    }

    var dayLength: Double { MP.daySeconds }
    public var yearDays: Double { cfg.daysPerYear }
    public var years: Double { Double(day) / cfg.daysPerYear }

    // MARK: - regions

    @inline(__always) public static func regionOf(tile t: TilePos, size: Int = 256) -> (Int, Int) {
        (Int((Double(t.x) / Double(size)).rounded(.down)), Int((Double(t.y) / Double(size)).rounded(.down)))
    }

    /// What a region is like, from the world's own generator: the same every time for the same world.
    public static func survey(_ gen: Generator, _ rx: Int, _ ry: Int, size: Int) -> CivRegion {
        var r = CivRegion(); r.rx = rx; r.ry = ry
        let k = 6
        var land = 0, water = 0, deep = 0, mount = 0
        var fert = 0.0, forest = 0.0
        for j in 0..<k { for i in 0..<k {
            let x = rx * size + (i * size + size / 2) / k, y = ry * size + (j * size + size / 2) / k
            let (e, t, m) = gen.climate(x, y)
            if e < Biome.sea { water += 1; if e < Biome.sea - 0.08 { deep += 1 } }
            else {
                land += 1
                if e > Biome.mountainLevel { mount += 1 }
                else { fert += max(0, 1 - abs(t - 0.55) * 1.6) * (0.4 + 0.6 * m); forest += m }
                if gen.isRiver(x, y, e) { r.river = true }
            }
        } }
        let n = Double(k * k)
        r.land = Double(land) / n; r.water = Double(water) / n; r.deep = Double(deep) / n; r.mountain = Double(mount) / n
        r.fertility = land == 0 ? 0 : fert / Double(land); r.forest = land == 0 ? 0 : forest / Double(land)
        var h = RNG(seed: gen.seed &* 31 &+ rx &* 73856093 &+ ry &* 19349663)
        r.ore = h.unit() * (0.3 + r.mountain); r.coal = h.unit() * 0.8; r.oil = h.unit() < 0.3 ? h.unit() : 0
        return r
    }

    /// The edge between two neighbouring regions: can a thing of this size get across, and by what.
    public func passable(_ a: CivRegion, _ b: CivRegion, size: CivSize, layer: CivLayer) -> Bool {
        switch layer {
        case .lowAir, .highAir, .nearSpace: return true
        case .sea, .underwater:
            // ships keep to water deep and wide enough for them; a carrier needs open deep water
            if size == .huge { return a.deep >= 0.3 && b.deep >= 0.3 }
            return a.water >= 0.35 && b.water >= 0.35
        case .ground:
            guard a.land >= 0.2 && b.land >= 0.2 else { return false }
            let rough = max(a.mountain, b.mountain)
            switch size {
            case .person: return true
            case .vehicle: return rough < 0.6
            case .large: return rough < 0.35          // a frame cannot squeeze through mountain passes
            case .huge: return false
            }
        }
    }

    /// Shortest way across known regions (4 neighbours), or nil. Regions with an enemy army are avoided when `avoid` says so.
    public func route(from a: Int64, to b: Int64, size: CivSize = .person, layer: CivLayer = .ground, avoid: Set<Int64> = []) -> [Int64]? {
        if a == b { return [a] }
        guard regions[a] != nil, regions[b] != nil else { return nil }
        var prev: [Int64: Int64] = [a: a]
        var q = [a], h = 0
        while h < q.count {
            let k = q[h]; h += 1
            guard let r = regions[k] else { continue }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nk = MP.chunkKey(r.rx + dx, r.ry + dy)
                guard prev[nk] == nil, let nr = regions[nk], !avoid.contains(nk) || nk == b, passable(r, nr, size: size, layer: layer) else { continue }
                prev[nk] = k
                if nk == b {
                    var path = [b], c = b
                    while c != a { c = prev[c]!; path.append(c) }
                    return path.reversed()
                }
                q.append(nk)
            }
        }
        return nil
    }

    // MARK: - news, ids

    func say(_ key: String, _ args: [String], _ nations: [Int], region: Int64? = nil) {
        happened[key, default: 0] += 1
        news.append(CivNews(t: time, key: key, args: args, nations: nations, region: region))
        if news.count > 400 { news.removeFirst(news.count - 400) }
    }

    // MARK: - the clock

    /// Advance to the world's time in hourly steps. Days are worked out when a day ends.
    public func advance(to t: Double, world: OpenWorld? = nil) {
        if t <= time { return }
        hourAcc += t - time
        time = t
        let hour = MP.daySeconds / 24
        var steps = 0
        while hourAcc >= hour && steps < 24 * 30 {
            hourAcc -= hour; steps += 1
            hourly()
            let d = Int((time - hourAcc) / MP.daySeconds)
            if d > day { day = d; daily(world: world) }
        }
    }

    /// One hour: armies move and fight, strikes land, aircraft fly. Food, births and deaths go by the day.
    func hourly() {
        warHourly()
    }

    /// One day, in the same order every time: research and plans, then every city, then everyone on the road.
    func daily(world: OpenWorld?) {
        politicsDaily()
        for id in cities.keys.sorted() { if let c = cities[id], c.detail == nil { cityDay(c) } }
        tripsDaily()
        industryDaily()
        forcesDaily()
        for id in cities.keys.sorted() { if let c = cities[id] { c.yesterday = c.today; c.today = CivLedger() } }
    }

    // MARK: - a city's day

    func season(_ d: Int) -> Int { Int(Double(d).truncatingRemainder(dividingBy: yearDays) / yearDays * 4) }    // 0 spring ... 3 winter
    func knows(_ nation: Int, _ tech: String) -> Bool { polities[nation]?.knows(tech) ?? false }

    func stochastic(_ x: Double) -> Int {
        guard x > 0 else { return 0 }
        let f = x.rounded(.down)
        return Int(f) + (rng.unit() < x - f ? 1 : 0)
    }

    /// Good and bad years: a smooth wave per region, the same for the same world and day.
    func weatherYield(_ c: CivCity) -> Double {
        var h = RNG(seed: seed &+ c.rx &* 31 &+ c.ry &* 17 &+ (day / 6) &* 101)
        return 0.8 + 0.4 * h.unit()
    }

    func cityDay(_ c: CivCity) {
        let cfg = self.cfg
        guard let reg = regions[c.regionKey] else { return }
        if let next = c.rationNext, time >= c.rationAt { c.ration = next; c.rationNext = nil }
        let pop = c.pop
        // --- shelter and water
        let beds = Double(c.has("house")) * cfg.housePeople + 18
        c.crowding = Double(pop) / beds
        let water = Double(c.has("well")) * cfg.wellWater + (reg.river || reg.coast ? cfg.riverWater : 30)
        c.thirst = pop == 0 ? 0 : max(0, 1 - water / Double(pop))
        // --- work: food first, then everything else in turn
        // adults work, elders lend a hand; the sick and the hungry less so
        var hands = 0.0
        for st in 0..<6 { let a = Double(c.people.n[6 + st]), e = Double(c.people.n[12 + st]); hands += (a + 0.3 * e) * cfg.work[st] }
        hands = max(0, hands - Double(c.sick) * 0.5)
        var staffed: [String: Double] = [:]
        var jobsTotal = 0.0
        let order = ["farm", "pasture", "fishery", "well", "bakery", "granary", "clinic", "autofarm", "greenhouse", "synth_plant", "ration_works", "plant", "fusion_plant", "mine", "oilwell",
                     "steelworks", "refinery", "factory", "fab", "school", "institute", "laboratory", "barracks", "motor_works", "shipyard", "deep_yard", "airfield", "aircraft_works", "frame_works", "sky_yard"]
        for f in order {
            guard let def = CivFacility.byKey[f], c.has(f) > 0, def.workers > 0 else { if c.has(f) > 0 { staffed[f] = 1 }; continue }
            var need = Double(def.workers * c.has(f))
            // with the granary full, only as many farm hands as keep it full: the rest quarry, cut and build
            if f == "farm" && c.foodDays > 40 { need = min(need, max(Double(def.workers), need * 40 / c.foodDays)) }
            jobsTotal += need
            let got = min(need, hands)
            hands -= got
            staffed[f] = got / need
        }
        c.jobs = jobsTotal
        let spare = hands                                        // adults with no post: woodcutters, quarrymen, foragers
        // --- energy
        c.energyMade = Double(c.has("plant")) * 30 * (staffed["plant"] ?? 0) + Double(c.has("fusion_plant")) * 200 * (staffed["fusion_plant"] ?? 0)
        c.energyUsed = 0
        for (f, k) in c.facilities.sorted(by: { $0.key < $1.key }) { if let d = CivFacility.byKey[f], d.energy < 0 { c.energyUsed += -d.energy * Double(k) * (staffed[f] ?? 0) } }
        let power = c.energyUsed <= 0 ? 1 : min(1, c.energyMade / c.energyUsed)
        func make(_ k: String, _ v: Double) { guard v > 0 else { return }; c.stock[k, default: 0] += v; c.today.add(\.made, k, v); c.ledger.add(\.made, k, v); totals.add(\.made, k, v) }
        // --- the land: a crop takes days to grow; in winter nothing is sown
        let s = season(day)
        var yieldMul = (0.35 + reg.fertility) * (knows(c.nation, "irrigation") ? 1.25 : 1) * (knows(c.nation, "rotation") ? 1.15 : 1) * (knows(c.nation, "fertilizer") ? 1.4 : 1)
        yieldMul *= weatherYield(c)
        // fields lie outside the walls: under siege little is brought in
        let fields = c.besieged ? 0.15 : 1.0
        if c.cropPlots > 0 && Double(day) >= c.cropDue {
            make("grain", Double(c.cropPlots) * cfg.plotYield * yieldMul * fields)
            c.cropPlots = 0
        }
        if c.cropPlots == 0 && s != 3 && c.has("farm") > 0 {
            c.cropPlots = Int((Double(c.has("farm")) * (staffed["farm"] ?? 0)).rounded())
            c.cropDue = Double(day) + 6
        }
        make("vegetable", Double(c.has("farm")) * (staffed["farm"] ?? 0) * 1.2 * yieldMul * (s == 3 ? 0.2 : 1) * fields)
        make("meat", Double(c.has("pasture")) * (staffed["pasture"] ?? 0) * 1.0 * fields)
        make("milk", Double(c.has("pasture")) * (staffed["pasture"] ?? 0) * 2.0 * fields)
        make("fish", Double(c.has("fishery")) * (staffed["fishery"] ?? 0) * 5 * min(1, reg.water * 2) * fields)
        make("hydro", Double(c.has("greenhouse")) * (staffed["greenhouse"] ?? 0) * 8 * power)
        make("grain", Double(c.has("autofarm")) * (staffed["autofarm"] ?? 0) * 30 * power)
        make("timber", spare * 0.2 * (0.3 + reg.forest))
        make("stone", spare * 0.12 * (0.3 + reg.mountain))
        make("ore", Double(c.has("mine")) * (staffed["mine"] ?? 0) * 6 * reg.ore)
        make("coal", Double(c.has("mine")) * (staffed["mine"] ?? 0) * 4 * reg.coal)
        make("crude", Double(c.has("oilwell")) * (staffed["oilwell"] ?? 0) * 8 * reg.oil * power)
        // the hungry go out and find what the land gives, whatever the stores hold: no one starves while standing still
        let hungryAdults = (1..<6).reduce(0) { $0 + c.people.n[6 + $1] }
        make("vegetable", Double(hungryAdults) * cfg.forage * (0.3 + reg.fertility) * (s == 3 ? 0.4 : 1) * fields)
        // processing: kitchens, works and plants turn stock into stock
        for r in CivRecipe.all {
            guard c.has(r.facility) > 0, r.tech == nil || knows(c.nation, r.tech!) else { continue }
            let crews = Double(c.has(r.facility)) * (staffed[r.facility] ?? 0) * (r.energy > 0 ? power : 1)
            var batches = (crews * 24 / r.hours).rounded(.down)
            for (k, v) in r.inputs { batches = min(batches, (c.free(k) / v).rounded(.down)) }
            // kitchens do not bake away grain a hungry city still needs whole
            if r.facility == "bakery" && c.foodDays < 2 && r.key == "bread" { batches = min(batches, 2) }
            guard batches > 0 else { continue }
            for (k, v) in r.inputs { c.stock[k, default: 0] -= v * batches; c.today.add(\.used, k, v * batches); c.ledger.add(\.used, k, v * batches); totals.add(\.used, k, v * batches) }
            for (k, v) in r.outputs { make(k, v * batches) }
        }
        // --- spoiling
        let granary = c.has("granary") > 0, cold = knows(c.nation, "cold_chain")
        for f in CivFood.all {
            let have = c.stock[f.key] ?? 0
            guard have > 0 else { continue }
            var rate = 1 / f.shelfDays
            if granary && (f.key == "grain" || f.key == "bread" || f.key == "ration") { rate *= 0.5 }
            if cold && f.shelfDays < 30 { rate *= 0.4 }
            let lost = min(have - (c.reserved[f.key] ?? 0), have * rate)
            guard lost > 0 else { continue }
            c.stock[f.key] = have - lost
            c.today.add(\.spoiled, f.key, lost); c.ledger.add(\.spoiled, f.key, lost); totals.add(\.spoiled, f.key, lost)
        }
        // --- eating
        feed(c)
        // --- illness
        let healthy = max(0, pop - c.sick)
        let pSick = cfg.sickPerDay + cfg.sickCrowd * max(0, c.crowding - 1) + cfg.sickThirst * c.thirst + cfg.sickHunger * c.people.hungerIndex * 5
        c.sick += stochastic(Double(healthy) * pSick)
        c.sick -= stochastic(Double(c.sick) * cfg.sickRecover * (c.has("clinic") > 0 ? 1.5 : 1))
        c.sick = max(0, min(c.sick, c.pop))
        let care = min(1, Double(c.has("clinic")) * 120 / Double(max(1, pop))) * cfg.careCut * (knows(c.nation, "medicine") ? 1 : 0.5)
        die(c, stochastic(Double(c.sick) * cfg.sickDeath * (1 - care)), "illness", slots: Array(0..<18))
        // --- hunger deaths, then old age and the like
        for st in 4..<6 { for b in 0..<3 { die(c, stochastic(Double(c.people.n[b * 6 + st]) * cfg.starveDeath[st]), "hunger", slots: [b * 6 + st]) } }
        for b in 0..<3 { die(c, stochastic(Double(c.people.band(b)) * cfg.deathPerYear[b] / yearDays * (1 - care)), "old", slots: (0..<6).map { b * 6 + $0 }) }
        // --- births: couples, how fed they are, how crowded, how well off
        let couples = (0..<6).reduce(0.0) { $0 + Double(c.people.n[6 + $1]) * cfg.fertile[$1] } / 2
        var rate = cfg.fertility / yearDays / (1 + cfg.wealthDamp * c.wealth)
        if c.crowding > 1 { rate /= c.crowding * c.crowding }
        rate *= 1 - c.thirst
        let born = stochastic(couples * rate)
        if born > 0 { c.people.n[0] += born; c.today.births += born; c.ledger.births += born; totals.births += born }
        // --- growing up and growing old (each group keeps how hungry it is)
        for st in 0..<6 {
            let up = stochastic(Double(c.people.n[st]) / (cfg.childYears * yearDays))
            c.people.n[st] -= up; c.people.n[6 + st] += up
            let old = stochastic(Double(c.people.n[6 + st]) / (cfg.adultYears * yearDays))
            c.people.n[6 + st] -= old; c.people.n[12 + st] += old
        }
        c.sick = min(c.sick, c.pop)
        // --- how life is: food in store, room, work
        c.foodDays = c.dailyNeed > 0 ? c.foodNutrition / c.dailyNeed : 99
        let fed = 1 - c.people.hungerIndex
        c.wealth = max(0, min(2, 0.5 * min(2, c.foodDays / 20) + 0.4 * min(1.5, 1 / max(0.3, c.crowding)) + 0.3 * fed + 0.2 * min(1, c.jobs / Double(max(1, c.people.band(1))))))
        // --- some leave: the hungry, the crowded
        emigrate(c)
    }

    /// Share out the day's food by the city's rationing, eat it from the stores (what spoils first goes
    /// first) and move every group one step towards or away from hunger. Thresholds have a dead band, so
    /// a city on the edge does not flicker between states.
    func feed(_ c: CivCity) {
        let cfg = self.cfg
        var need = [0.0, 0.0, 0.0]
        for b in 0..<3 { need[b] = Double(c.people.band(b)) * cfg.need[b] }
        need[1] += Double(c.people.band(1)) * cfg.needLabour * 0.6
        let total = need.reduce(0, +)
        c.dailyNeed = total
        guard total > 0 else { c.coverage = 1; return }
        var avail = 0.0
        for f in CivFood.all { avail += c.free(f.key) * f.nutrition }
        var give = [0.0, 0.0, 0.0]
        switch c.ration {
        case .normal, .armyFirst:
            let share = min(1, avail / total); give = need.map { $0 * share }
        case .emergency:
            // stretched: everyone a little short (inside the dead band: peckish, not starving), the stores last longer
            let share = min(cfg.emergencyShare, avail / total); give = need.map { $0 * share }
        case .childrenFirst:
            give[0] = min(need[0], avail)
            let rest = avail - give[0], other = need[1] + need[2]
            let share = other > 0 ? min(1, rest / other) : 0
            give[1] = need[1] * share; give[2] = need[2] * share
        }
        var toEat = give.reduce(0, +)
        for k in CivFood.eatOrder where toEat > 1e-9 {
            guard let f = CivFood.byKey[k] else { continue }
            let units = min(c.free(k), toEat / f.nutrition)
            guard units > 0 else { continue }
            c.stock[k, default: 0] -= units
            toEat -= units * f.nutrition
            c.today.add(\.eaten, k, units); c.ledger.add(\.eaten, k, units); totals.add(\.eaten, k, units)
        }
        let cover = (0..<3).map { need[$0] > 0 ? give[$0] / need[$0] : 1 }
        c.coverage = give.reduce(0, +) / total
        for b in 0..<3 { shift(&c.people, band: b, coverage: cover[b]) }
    }

    func shift(_ p: inout CivPeople, band b: Int, coverage: Double) {
        if coverage >= cfg.fedAbove {
            for st in 1..<6 { let m = stochastic(Double(p.n[b * 6 + st]) * cfg.recoverPerDay); p.n[b * 6 + st] -= m; p.n[b * 6 + st - 1] += m }
        } else if coverage < cfg.hungryBelow {
            let want = (1 - coverage) * cfg.worsenPerDay
            for st in stride(from: 4, through: 0, by: -1) { let m = stochastic(Double(p.n[b * 6 + st]) * min(1, want)); p.n[b * 6 + st] -= m; p.n[b * 6 + st + 1] += m }
        }
    }

    func die(_ c: CivCity, _ k: Int, _ cause: String, slots: [Int]) {
        guard k > 0 else { return }
        let gone = c.people.take(k, from: slots)
        let n = gone.total
        guard n > 0 else { return }
        c.today.deaths[cause, default: 0] += n; c.ledger.deaths[cause, default: 0] += n; totals.deaths[cause, default: 0] += n
        c.sick = min(c.sick, c.pop)
    }

    // MARK: - moving

    func emigrate(_ c: CivCity) {
        let cfg = self.cfg
        var leaving = 0
        for st in 0..<6 { leaving += stochastic(Double(c.people.state(st)) * cfg.leave[st]) }
        leaving += stochastic(Double(c.pop) * cfg.crowdLeave * max(0, c.crowding - 1))
        leaving = min(leaving, c.pop / 4)
        guard leaving >= 3 else { return }
        // where to: the best-off reachable city (their own nation's first; refugees take anyone at peace with them)
        let mine = c.nation
        var best: (CivCity, Double)?
        for id in cities.keys.sorted() {
            guard let d = cities[id], d.id != c.id, d.detail == nil, !d.besieged else { continue }
            let atWar = self.atWar(mine, d.nation)
            if atWar { continue }
            let score = d.wealth - c.wealth - (d.nation == mine ? 0 : 0.3) - (d.crowding > 1 ? d.crowding - 1 : 0)
            guard score > 0.15 else { continue }
            if best == nil || score > best!.1 { best = (d, score) }
        }
        guard let to = best?.0, let path = route(from: c.regionKey, to: to.regionKey, avoid: hostileRegions(of: mine)) else { return }
        // they set out with food for the road, if the city can spare it
        let days = Double(path.count - 1) * cfg.travelDaysPerRegion + 1
        var group = CivPeople()
        for st in stride(from: 5, through: 0, by: -1) where group.total < leaving {
            group.add(c.people.take(leaving - group.total, from: [st, 6 + st, 12 + st]))
        }
        var trip = CivTrip(); trip.id = nextTrip; nextTrip += 1
        trip.nation = mine; trip.from = c.id; trip.to = to.id; trip.route = path; trip.people = group
        trip.refugee = group.state(3) + group.state(4) + group.state(5) > group.total / 2
        trip.cargo = takeFood(from: c, nutrition: days * Double(group.total) * 0.9)
        c.today.migOut += group.total; c.ledger.migOut += group.total; totals.migOut += group.total
        c.sick = min(c.sick, c.pop)
        trips[trip.id] = trip
        if group.total >= 20 { say(trip.refugee ? "refugees_left" : "migrants_left", ["\(group.total)", c.nameEn, c.nameZh, to.nameEn, to.nameZh], [mine], region: c.regionKey) }
    }

    /// Take food for a journey or an army, most lasting first, as much as there is up to `nutrition`.
    func takeFood(from c: CivCity, nutrition want: Double) -> [String: Double] {
        var out: [String: Double] = [:]
        var left = want
        for k in CivFood.eatOrder.reversed() where left > 1e-9 {
            guard let f = CivFood.byKey[k] else { continue }
            let u = min(c.free(k), left / f.nutrition)
            guard u > 0 else { continue }
            c.stock[k, default: 0] -= u; out[k] = u; left -= u * f.nutrition
            c.today.add(\.wentOut, k, u); c.ledger.add(\.wentOut, k, u); totals.add(\.wentOut, k, u)
        }
        return out
    }

    func put(_ cargo: [String: Double], into c: CivCity) {
        for (k, v) in cargo.sorted(by: { $0.key < $1.key }) where v > 0 {
            c.stock[k, default: 0] += v
            c.today.add(\.cameIn, k, v); c.ledger.add(\.cameIn, k, v); totals.add(\.cameIn, k, v)
        }
    }

    /// Send goods from one city to another. They are taken at once (so nothing else can spend them);
    /// they arrive when the road has been travelled, or are lost on it.
    @discardableResult public func ship(_ goods: [String: Double], from a: Int, to b: Int) -> Int? {
        guard let from = cities[a], let to = cities[b], from.detail == nil || to.detail == nil else { return nil }
        guard let path = route(from: from.regionKey, to: to.regionKey, avoid: hostileRegions(of: from.nation)) else { return nil }
        var cargo: [String: Double] = [:]
        for (k, v) in goods.sorted(by: { $0.key < $1.key }) {
            let u = min(v, from.free(k))
            guard u > 0 else { continue }
            from.stock[k, default: 0] -= u; cargo[k] = u
            from.today.add(\.wentOut, k, u); from.ledger.add(\.wentOut, k, u); totals.add(\.wentOut, k, u)
        }
        guard !cargo.isEmpty else { return nil }
        var t = CivTrip(); t.id = nextTrip; nextTrip += 1
        t.nation = from.nation; t.from = a; t.to = b; t.route = path; t.cargo = cargo
        // carters and drivers come along; they are counted where they live, so the trip carries no people
        trips[t.id] = t
        return t.id
    }

    func tripsDaily() {
        let cfg = self.cfg
        for id in trips.keys.sorted() {
            guard var t = trips[id] else { continue }
            // people on the road eat what they carry, and grow hungry when it runs out
            if !t.people.isEmpty {
                var need = 0.0
                for b in 0..<3 { need += Double(t.people.band(b)) * cfg.need[b] }
                var have = 0.0
                for k in t.cargo.keys.sorted() { have += t.cargo[k]! * (CivFood.byKey[k]?.nutrition ?? 0) }
                let eatN = min(need, have)
                var left = eatN
                for k in CivFood.eatOrder where left > 1e-9 {
                    guard let f = CivFood.byKey[k], let v = t.cargo[k], v > 0 else { continue }
                    let u = min(v, left / f.nutrition); t.cargo[k] = v - u; left -= u * f.nutrition
                    totals.add(\.eaten, k, u)
                }
                let cover = need > 0 ? eatN / need : 1
                for b in 0..<3 { shift(&t.people, band: b, coverage: cover) }
                for st in 4..<6 { for b in 0..<3 {
                    let k = stochastic(Double(t.people.n[b * 6 + st]) * cfg.starveDeath[st])
                    let gone = t.people.take(k, from: [b * 6 + st]).total
                    if gone > 0 { totals.deaths["journey", default: 0] += gone }
                } }
            }
            // a blockade or an enemy army ahead holds the trip up; goods may be seized
            let speed = (polities[t.nation]?.knows("railways") ?? false) ? 2.0 : 1.0
            if t.leg + 1 < t.route.count {
                let next = t.route[t.leg + 1]
                if hostileRegions(of: t.nation).contains(next) || (cities[t.to]?.besieged == true && next == t.route.last) {
                    t.waiting += 1
                    if !t.cargo.isEmpty && t.people.isEmpty && t.waiting > 3 {
                        for (k, v) in t.cargo where v > 0 { totals.add(\.lost, k, v) }
                        t.cargo = [:]
                        say("convoy_lost", [cities[t.from]?.nameEn ?? "", cities[t.from]?.nameZh ?? ""], [t.nation])
                    }
                } else {
                    t.progress += speed
                    while t.progress >= cfg.travelDaysPerRegion && t.leg + 1 < t.route.count { t.progress -= cfg.travelDaysPerRegion; t.leg += 1 }
                }
            }
            if t.leg + 1 >= t.route.count || (t.cargo.isEmpty && t.people.isEmpty) {
                arrive(t)
                trips[id] = nil
            } else { trips[id] = t }
        }
    }

    func arrive(_ t: CivTrip) {
        if let s = t.settle, !t.people.isEmpty, regions[s]?.city == nil {
            let c = newCity(at: s, nation: t.nation, people: t.people, firstCount: false)
            put(t.cargo, into: c)
            c.today.migIn += t.people.total; c.ledger.migIn += t.people.total; totals.migIn += t.people.total
            c.facilities = ["farm": max(1, t.people.band(1) / 3), "house": max(1, t.people.total / 6)]
            say("city_founded", [c.nameEn, c.nameZh, polities[t.nation]?.nameEn ?? "", polities[t.nation]?.nameZh ?? ""], [t.nation], region: s)
            return
        }
        // the town they set out for is gone or taken: they go back where they came from, or stop at the nearest friendly one
        let dest = cities[t.to] ?? cities[t.from] ?? cities.values.filter { $0.nation == t.nation && $0.detail == nil }.min { $0.id < $1.id }
        guard let c = dest else {
            if !t.people.isEmpty { totals.deaths["journey", default: 0] += t.people.total }
            for (k, v) in t.cargo { totals.add(\.lost, k, v) }
            return
        }
        if !t.people.isEmpty {
            c.people.add(t.people)
            c.today.migIn += t.people.total; c.ledger.migIn += t.people.total; totals.migIn += t.people.total
            // newcomers bring their loyalties with them
            let share = Double(t.people.total) / Double(max(1, c.pop))
            mixCulture(c, [t.nation: 1], share)
        }
        put(t.cargo, into: c)
    }

    func mixCulture(_ c: CivCity, _ other: [Int: Double], _ share: Double) {
        guard share > 0 else { return }
        var out: [Int: Double] = [:]
        for k in c.culture.keys.sorted() { out[k, default: 0] += c.culture[k]! * (1 - share) }
        for k in other.keys.sorted() { out[k, default: 0] += other[k]! * share }
        c.culture = out.filter { $0.value > 0.005 }
        let sum = c.culture.keys.sorted().reduce(0.0) { $0 + c.culture[$1]! }
        if sum > 0 { for k in c.culture.keys.sorted() { c.culture[k]! /= sum } }
    }

    // MARK: - founding places

    /// A city in a region, with people who were not counted before (a place found for the first time)
    /// or who came from elsewhere (settlers, already counted on the road).
    @discardableResult func newCity(at key: Int64, nation: Int, people: CivPeople, firstCount: Bool) -> CivCity {
        let c = CivCity()
        c.id = nextCity; nextCity += 1
        let (rx, ry) = (MP.keyCX(key), MP.keyCY(key))
        c.rx = rx; c.ry = ry; c.nation = nation; c.founded = time; c.lastDay = day
        var n = RNG(seed: seed &+ rx &* 92821 &+ ry &* 68917)
        let a = ["Ash", "Brin", "Cal", "Dor", "El", "Fen", "Gar", "Hol", "Iv", "Jun", "Kel", "Lor", "Mar", "Nor", "Os", "Pel", "Quel", "Ros", "Sel", "Tor", "Ul", "Ver", "Wyn", "Zor"]
        let b = ["ford", "mere", "hold", "wick", "stead", "haven", "gate", "field", "moor", "crest", "vale", "port"]
        let az = ["灰", "岩", "青", "渡", "风", "苇", "金", "霜", "柳", "云", "雀", "白", "赤", "松", "月", "砂", "桐", "湖", "星", "石", "银", "梅", "竹", "雪"]
        let bz = ["渡", "湖", "堡", "村", "庄", "港", "关", "田", "原", "岭", "谷", "津"]
        let i = n.index(a.count), j = n.index(b.count)
        c.nameEn = a[i] + b[j]; c.nameZh = az[i] + bz[j]
        c.people = people
        c.culture = [nation: 1]
        if firstCount {
            // the first count of people who were always there: not births, and said so in the ledger
            c.ledger.newly += people.total; c.today.newly += people.total; totals.newly += people.total
        }
        regions[key]?.city = c.id
        cities[c.id] = c
        return c
    }

    // MARK: - checking

    /// The whole state in a fixed order, for comparing two runs (dictionaries otherwise encode in any order).
    public func digest() -> String {
        func m(_ d: [String: Double]) -> String { d.keys.sorted().map { "\($0)=\(d[$0]!)" }.joined(separator: ",") }
        var out = "t\(time) d\(day) h\(hourAcc) rng\(rng.state) n\(nextNation)/\(nextCity)/\(nextTrip)/\(nextForce)/\(nextUnit)/\(nextProject)\n"
        for k in regions.keys.sorted() { let r = regions[k]!; out += "r\(k) \(r.city ?? 0)\n" }
        for k in cities.keys.sorted() { let c = cities[k]!
            out += "c\(k) \(c.nation) \(c.people.n) s\(c.sick) \(m(c.stock)) | \(m(c.reserved)) | \(c.facilities.keys.sorted().map { "\($0)\(c.facilities[$0]!)" }) \(c.culture.keys.sorted().map { "\($0):\(c.culture[$0]!)" }) u\(c.unrest) \(c.ration) \(c.cropPlots)@\(c.cropDue) \(c.builds)\n" }
        for k in polities.keys.sorted() { let p = polities[k]!; out += "p\(k) \(p.status) \(p.techs) \(m(p.progress)) \(p.treasury) \(p.fatigue) \(p.capital ?? 0)\n" }
        for k in relations.keys.sorted() { let r = relations[k]!; out += "rel\(k) \(r.state) \(r.value) \(r.pact)\n" }
        for k in trips.keys.sorted() { let t = trips[k]!; out += "trip\(k) \(t.people.n) \(m(t.cargo)) \(t.leg) \(t.progress)\n" }
        for k in forces.keys.sorted() { let f = forces[k]!; out += "f\(k) \(f.region) \(f.units) \(f.crew.n) \(m(f.food)) \(f.path) \(f.morale)\n" }
        for k in units.keys.sorted() { let u = units[k]!; out += "u\(k) \(u.hp) \(m(u.parts)) \(u.fuel) \(u.ammo) \(u.energy) \(u.heat) \(u.air) \(u.at ?? 0)\n" }
        for k in projects.keys.sorted() { let p = projects[k]!; out += "pr\(k) \(p.stage) \(p.hours) \(m(p.invested))\n" }
        out += "strikes \(strikes.count) totals b\(totals.births) d\(totals.deaths.keys.sorted().map { "\($0)\(totals.deaths[$0]!)" }) n\(totals.newly) \(m(totals.eaten))\n"
        return out
    }

    /// Everyone alive in the regional layer: in cities, on the road and under arms.
    public var people: Int {
        cities.values.reduce(0) { $0 + ($1.detail == nil ? $1.pop : 0) } + trips.values.reduce(0) { $0 + $1.people.total } + forces.values.reduce(0) { $0 + $1.crew.total }
    }

    /// What must hold every day. Empty when everything adds up.
    public func audit() -> [String] {
        var out: [String] = []
        let expect = totals.newly + totals.births - totals.deathTotal
        if people != expect { out.append("people \(people) != first counted \(totals.newly) + born \(totals.births) - died \(totals.deathTotal)") }
        for c in cities.values {
            if c.people.n.contains(where: { $0 < 0 }) { out.append("negative people in \(c.nameEn)") }
            for (k, v) in c.stock where v < -1e-6 { out.append("negative \(k) in \(c.nameEn): \(v)") }
            if c.sick > c.pop { out.append("more sick than people in \(c.nameEn)") }
        }
        for t in trips.values where t.people.n.contains(where: { $0 < 0 }) { out.append("negative people on trip \(t.id)") }
        for f in forces.values where f.crew.n.contains(where: { $0 < 0 }) { out.append("negative crew in force \(f.id)") }
        var seen = Set<Int>()
        for f in forces.values { for u in f.units { if !seen.insert(u).inserted { out.append("unit \(u) in two forces") }; if units[u] == nil { out.append("force \(f.id) holds missing unit \(u)") } } }
        for u in units.values where u.force != nil && forces[u.force!] == nil { out.append("unit \(u.id) in missing force") }
        for r in regions.values { if let c = r.city, cities[c] == nil { out.append("region points to missing city \(c)") } }
        for c in cities.values where polities[c.nation] == nil && c.detail == nil { out.append("city \(c.nameEn) of unknown nation \(c.nation)") }
        return out
    }

    /// Food that must be held now by the ledger: found + made - eaten - spoiled - lost - used as an ingredient.
    public func foodExpected() -> [String: Double] {
        var out: [String: Double] = [:]
        for f in CivFood.all {
            let k = f.key
            let gained: Double = (totals.found[k] ?? 0) + (totals.made[k] ?? 0)
            let gone: Double = (totals.eaten[k] ?? 0) + (totals.spoiled[k] ?? 0) + (totals.lost[k] ?? 0) + (totals.used[k] ?? 0)
            out[k] = gained - gone
        }
        return out
    }

    /// How much food there is in total (stores, roads, armies), for checking against the ledger.
    public func foodHeld() -> [String: Double] {
        var out: [String: Double] = [:]
        for c in cities.values where c.detail == nil { for (k, v) in c.stock where CivFood.isFood(k) { out[k, default: 0] += v } }
        for t in trips.values { for (k, v) in t.cargo where CivFood.isFood(k) { out[k, default: 0] += v } }
        for f in forces.values { for (k, v) in f.food { out[k, default: 0] += v } }
        return out
    }
}
