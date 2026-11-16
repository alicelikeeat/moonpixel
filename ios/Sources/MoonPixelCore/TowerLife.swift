import Foundation

// How a tower lives: what holds it up, how food and water get up it, who lives in it.
//
// Structure (a game rule, not engineering). Each floor weighs its plan (slab, walls, fittings) plus the
// people and food on it. A floor carries its own weight and everything above. It can carry its
// columns times what one column of its material holds (less for damage). Over 100% it is overloaded:
// people are moved out and it is marked damaged; over 125% (or wrecked) it fails, and it and everything
// above come down, once: those still inside die, what was stored is lost, and it is written into the
// tower's history. A change to one floor recomputes that floor and those below it, nothing above.
// Field-lift (the last material) holds far more, but only while it has power; without power it holds
// what composite holds, so a tower built on it must keep its power or come down to a safe height.
//
// Getting things up. Stairs carry a little; each bank of lifts carries a lot, less the higher it goes.
// With sky lobbies every N floors, express lifts run to the lobbies and local ones from there, so the
// cost of reaching floor k grows with k / N plus the distance from the lobby, not with k. Food reaches a
// floor only by these; when they cannot carry all of it, every floor gets the same share, and the
// short floors go hungry like anyone else (the grain in the cellar does not feed the 300th floor).

public enum TowerRules {
    /// Load one column of each material carries: timber, stone, steel, composite, field-lift (powered).
    public static let column: [Double] = [40, 120, 900, 6000, 40000]
    public static let materialNames = [("timber", "木构"), ("stone", "石构"), ("steel", "钢构"), ("composite", "复合材料"), ("field-lift", "场升力")]
    public static let materialTech: [String?] = [nil, "metallurgy", "steel", "robotics", "lift"]
    public static let fieldLiftEnergy = 0.6                   // a floor a day
    public static let personLoad = 0.08, foodLoad = 0.002
    public static let overload = 1.0, failure = 1.25
    public static let stairsPerDay = 600.0, liftPerDay = 9000.0
    public static let liftEnergy = 2.0                        // a bank a day
    public static let pumpEvery = 40                          // floors a pump room lifts water
    public static let moveInPerDay = 0.2                      // share of free beds filled in a day
    /// Materials for one floor of a plan: slab and walls of the tower's material, fittings by use.
    public static func cost(_ p: FloorPlan, material m: Int) -> [String: Double] {
        let cells = Double(p.parts.filter { $0 != .empty }.count)
        var c: [String: Double]
        switch m {
        case 0: c = ["timber": cells * 0.4]
        case 1: c = ["stone": cells * 0.5, "timber": cells * 0.1]
        case 2: c = ["steel": cells * 0.15, "stone": cells * 0.2]
        case 3: c = ["steel": cells * 0.2, "parts": cells * 0.05]
        default: c = ["steel": cells * 0.25, "electronics": cells * 0.05, "parts": cells * 0.05]
        }
        if p.use == .farm { c["parts", default: 0] += 4 }
        if p.use == .works { c["parts", default: 0] += 6 }
        return c.filter { $0.value > 0 }
    }
    public static let liftCost: [String: Double] = ["steel": 30, "parts": 20, "electronics": 4]
}

extension Civ {
    public func towers(of city: Int) -> [Tower] { towerIndex.towers.values.filter { $0.city == city }.sorted { $0.id < $1.id } }
    func plan(_ f: TowerFloor) -> FloorPlan? { towerIndex.plans[f.plan] }

    // MARK: - structure

    /// Work out loads from floor `from` downwards (a change at `from` cannot change anything above it).
    public func restructure(_ t: Tower, from: Int? = nil, powered: Bool = true) {
        let n = t.floors.count
        if t.load.count != n { t.load = [Double](repeating: 0, count: n); t.strength = [Double](repeating: 0, count: n) }
        guard n > 0 else { t.recomputed = 0; return }
        let start = min(n - 1, from ?? (n - 1))
        var above = start + 1 < n ? t.load[start + 1] : 0
        var count = 0
        for i in stride(from: start, through: 0, by: -1) {
            let f = t.floors[i]
            let built = f.stage >= .structure && f.stage != .failed
            let p = plan(f)
            let own = built ? (p?.weight ?? 0) + Double(f.people.total) * TowerRules.personLoad + f.food * TowerRules.foodLoad : 0
            above += own
            t.load[i] = above
            var cols = Double(p?.columns ?? 0)
            for (_, part) in f.diff { if part == .column { cols += 1 } }
            // a column taken out of this floor: count the plan's columns that the diff removed
            if let p = p { for (i2, part) in f.diff where p.parts[i2] == .column && part != .column { cols -= 1; _ = i2 } }
            let per = t.material == 4 && !powered ? TowerRules.column[3] : TowerRules.column[min(4, t.material)]
            t.strength[i] = built ? max(0, cols) * per * (1 - f.damage) : .infinity
            count += 1
        }
        t.recomputed = count
    }

    /// Floors that are over what they can carry: evacuate, mark, and bring down what must come down.
    func checkStructure(_ t: Tower, city c: CivCity) {
        guard !t.floors.isEmpty else { return }
        var failAt: Int?
        for i in t.floors.indices {
            let ratio = t.strength[i] == .infinity ? 0 : t.load[i] / max(1e-9, t.strength[i])
            if ratio > TowerRules.failure || t.floors[i].damage >= 1 { failAt = i; break }
            if ratio > TowerRules.overload && t.floors[i].stage == .inUse {
                t.floors[i].stage = .damaged
                // everyone on it and above goes down to the ground before it gets worse
                for j in i..<t.floors.count { c.people.add(t.floors[j].people); t.floors[j].people = CivPeople() }
                t.history.append("d\(day): floor \(i + 1) overloaded (\(Int(ratio * 100))%), evacuated")
                say("tower_overload", [t.nameEn, t.nameZh, "\(i + 1)"], [t.nation], region: c.regionKey)
            }
        }
        guard let k = failAt else { return }
        // floor k and everything above it come down: once
        var dead = 0
        for j in k..<t.floors.count { dead += t.floors[j].people.total }       // (their food was booked as eaten when it went up)
        if dead > 0 { c.today.deaths["collapse", default: 0] += dead; c.ledger.deaths["collapse", default: 0] += dead; totals.deaths["collapse", default: 0] += dead }
        let n = t.floors.count - k
        t.floors.removeSubrange(k...)
        t.history.append("d\(day): \(n) floors from \(k + 1) up collapsed; \(dead) died")
        say("tower_collapse", [t.nameEn, t.nameZh, "\(n)", "\(dead)"], [t.nation], region: c.regionKey)
        restructure(t)
        if t.floors.isEmpty { towerIndex.towers[t.id] = nil; towerIndex.reindex() }
    }

    /// Take food from a city's free stores, most perishable first, booked as eaten. Returns the nutrition taken.
    func eat(from c: CivCity, nutrition want: Double) -> Double {
        var left = want
        for k in CivFood.eatOrder where left > 1e-9 {
            guard let f = CivFood.byKey[k] else { continue }
            let u = min(c.free(k), left / f.nutrition)
            guard u > 0 else { continue }
            c.stock[k, default: 0] -= u; left -= u * f.nutrition
            c.today.add(\.eaten, k, u); c.ledger.add(\.eaten, k, u); totals.add(\.eaten, k, u)
        }
        return want - left
    }

    // MARK: - getting things up

    /// The cost of getting one unit to floor k: proportional to height, or to lobbies plus the local hop.
    public func liftCost(_ t: Tower, _ k: Int) -> Double {
        guard t.lifts > 0 else { return Double(k + 1) }
        if t.skyLobbyEvery > 0 { return Double(k / t.skyLobbyEvery) * 2 + Double(k % t.skyLobbyEvery) + 1 }
        return Double(k + 1)
    }

    /// What lifts and stairs can move in a day (in unit-floors): lifts need power.
    public func carrying(_ t: Tower, city c: CivCity) -> Double {
        // lifts run on the city's spare power; short of it they slow down, and with none they are wound by hand
        let draw = Double(t.lifts) * TowerRules.liftEnergy, spare = c.energyMade - c.energyUsed
        let liftPower = t.lifts == 0 ? 0 : (spare >= draw ? 1 : max(1.0 / 6, spare / draw))
        return TowerRules.stairsPerDay + Double(t.lifts) * TowerRules.liftPerDay * liftPower
    }

    /// One day of a city's towers: move people in or out, carry food and water up, feed every floor,
    /// check what holds. Called from the city's own day.
    func towersDay(_ c: CivCity) {
        let ts = towers(of: c.id)
        guard !ts.isEmpty else { c.upstairs = 0; c.towerBeds = 0; return }
        var beds = 0
        for t in ts {
            restructure(t, powered: t.material < 4 || c.energyMade >= Double(t.floors.count) * TowerRules.fieldLiftEnergy)
            checkStructure(t, city: c)
            guard towerIndex.towers[t.id] != nil else { continue }
            // water: a pump room lifts it so many floors; above that, floors run dry
            var pumpedTo = TowerRules.pumpEvery
            for (i, f) in t.floors.enumerated() where f.stage == .inUse && plan(f)?.use == .pump { pumpedTo = max(pumpedTo, i + TowerRules.pumpEvery) }
            for i in t.floors.indices { t.floors[i].water = i < pumpedTo ? 1 : 0 }
            // people: dry, damaged or unfinished floors are left; free beds are filled from the ground
            for i in t.floors.indices {
                let f = t.floors[i]
                if (f.stage != .inUse || f.water < 1) && f.people.total > 0 { c.people.add(f.people); t.floors[i].people = CivPeople() }
            }
            for i in t.floors.indices where t.floors[i].stage == .inUse && t.floors[i].water >= 1 {
                guard let p = plan(t.floors[i]) else { continue }
                let cap = p.capacity(.home) + p.capacity(.works) / 2
                beds += p.capacity(.home)
                let room = cap - t.floors[i].people.total
                guard room > 0, c.pop > 0 else { continue }
                let k = min(room, max(1, Int(Double(room) * TowerRules.moveInPerDay)), c.people.total / 3)
                guard k > 0 else { continue }
                let movers = c.people.take(k)                            // a move inside the city: not a birth, not a migration
                t.floors[i].people.add(movers)
                c.sick = min(c.sick, c.people.total)
            }
            // food up the tower: the same share for every floor when the lifts cannot carry it all
            var need: [Double] = Array(repeating: 0, count: t.floors.count)
            var work = 0.0
            for (i, f) in t.floors.enumerated() where f.people.total > 0 {
                for b in 0..<3 { need[i] += Double(f.people.band(b)) * cfg.need[b] }
                need[i] = max(0, need[i] - t.floors[i].food)
                work += need[i] * liftCost(t, i)
            }
            let total = need.reduce(0, +)
            if total > 0 {
                let share = min(1, carrying(t, city: c) / max(1e-9, work))
                let have = c.foodNutrition - CivFood.all.reduce(0.0) { $0 + (c.reserved[$1.key] ?? 0) * $1.nutrition }
                let send = min(total * share, max(0, have))
                // what goes up the tower is eaten up there: booked as eaten when it leaves the store
                let got = eat(from: c, nutrition: send)
                for i in t.floors.indices where need[i] > 0 { t.floors[i].food += got * need[i] / total }
                t.liftLoad = work / max(1e-9, carrying(t, city: c))
            } else { t.liftLoad = 0 }
            // every floor eats what reached it and grows hungrier or better fed, like anyone
            for i in t.floors.indices where t.floors[i].people.total > 0 {
                var want = 0.0
                for b in 0..<3 { want += Double(t.floors[i].people.band(b)) * cfg.need[b] }
                let eat = min(want, t.floors[i].food)
                t.floors[i].food -= eat
                let cover = want > 0 ? eat / want : 1
                t.floors[i].coverage = cover
                for b in 0..<3 { shift(&t.floors[i].people, band: b, coverage: cover) }
                for st in 4..<6 { for b in 0..<3 {
                    let k = stochastic(Double(t.floors[i].people.n[b * 6 + st]) * cfg.starveDeath[st])
                    let gone = t.floors[i].people.take(k, from: [b * 6 + st]).total
                    if gone > 0 { c.today.deaths["hunger", default: 0] += gone; c.ledger.deaths["hunger", default: 0] += gone; totals.deaths["hunger", default: 0] += gone }
                } }
            }
            // vertical farms grow food from light and power; it goes down to the city's stores
            for f in t.floors where f.stage == .inUse { if let p = plan(f), p.use == .farm {
                let made = Double(p.capacity(.farm)) * 2.5 * (c.energyMade > c.energyUsed ? 1 : 0.3)
                if made > 0 { c.stock["hydro", default: 0] += made; c.today.add(\.made, "hydro", made); c.ledger.add(\.made, "hydro", made); totals.add(\.made, "hydro", made) }
            } }
        }
        c.towerBeds = beds
        c.upstairs = towers(of: c.id).reduce(0) { a, t in a + t.floors.reduce(0) { $0 + $1.people.total } }
    }
}
