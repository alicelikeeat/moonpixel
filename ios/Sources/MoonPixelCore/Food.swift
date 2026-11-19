import Foundation

// Food drives growth. A district builds farms, large farms and ranches ahead of its people (harvest for half as
// many again as live there, plus room for the next arrivals), staffs them right after its services, and the
// more food it has to spare the faster it grows: more children, and settlers drawn from the regional cities or
// the countryside. Growth runs at full speed until the world's towns and districts hold 10 000 people, then
// slows steeply (the land is filling up). Every person still comes from a birth or from somewhere named in the
// district's ledger.

extension Society {
    /// Growth runs at full speed until the towns and districts hold this many people.
    public static var popTarget = 10_000

    /// The people of the world's towns and districts.
    public var totalPopulation: Int {
        settlements.values.filter { !$0.abandoned }.reduce(0) { $0 + $1.members.count } + net.districts.reduce(0) { $0 + $1.population }
    }

    /// 1 while the world is below the target; then (target / people)³: half speed at 12 600, a tenth at 21 500.
    public static func growthBrake(_ total: Int) -> Double {
        total < popTarget ? 1 : pow(Double(popTarget) / Double(max(1, total)), 3)
    }

    /// How many building projects a district runs at once (a big one builds several blocks in parallel).
    public static func parallelProjects(_ pop: Int) -> Int { pop < 100 ? 2 : (pop < 1000 ? 4 : 6) }

    /// Food a district's farms and ranches give a day with every job filled (open ones; with `planned`, the
    /// ones being built too).
    public func foodCapacity(_ d: District, planned: Bool = false) -> Double {
        d.buildings.filter { planned ? $0.state != .burnt : $0.state == .open }.reduce(0) { sum, b in
            sum + (b.def.outputs["food"] ?? 0) * Double(b.def.jobsPerFloor * max(1, b.def.storeys))
        }
    }

    /// The food building a district needs next, or nil when its harvests (with what is being built) feed half as
    /// many again as live there and the homes being filled: a small farm while it is small, then large farms and
    /// ranches in turn.
    func foodToBuild(_ d: District) -> String? {
        let pop = Double(d.population)
        let coming = Double(max(d.homes, d.population))
        let want = max(pop, coming * 0.8) * 1.5 + 60
        guard foodCapacity(d, planned: true) < want else { return nil }
        if pop < 120 && d.buildings.filter({ $0.kind == "farm" }).count < 2 { return "farm" }
        let big = d.buildings.filter { $0.kind == "bigfarm" }.count, ranch = d.buildings.filter { $0.kind == "ranch" }.count
        return big <= ranch ? "bigfarm" : "ranch"
    }

    /// How well fed a district is, 0 (hungry, or nothing to spare) to 1.5 (harvests well beyond what is eaten
    /// and a week and more in store).
    public func plenty(_ d: District) -> Double {
        let pop = Double(max(1, d.population))
        let days = (d.store["food"] ?? 0) / pop
        let harvest = (d.foodMade ?? 0) / pop
        // a real shortage (more than one in twenty went without) means no plenty; a floor waiting for the lift does not
        guard d.foodShort <= pop * 0.05 else { return 0 }
        return max(0, min(1.5, (days - 2) / 6 * 0.6 + (harvest - 0.9) * 1.5))
    }

    /// Children born today: up to 6% of the people a day when food is plentiful, scaled by happiness, slowed
    /// once the world passes the growth target. Fractions are carried by chance, so a small town grows too.
    func birthsToday(_ d: District, eaten: Double, short: Double) -> Int {
        let pop = Double(d.population)
        guard pop >= 2, short <= pop * 0.05 else { return 0 }
        let rate = 0.004 + 0.04 * plenty(d)
        let x = pop * rate * (0.6 + 0.6 * d.happiness) * Society.growthBrake(totalPopulation)
        return Int(x) + (d.rng.unit() < x - Double(Int(x)) ? 1 : 0)
    }

    /// Settlers a district takes today: its free homes, at most a tenth of its people (eight at least) and
    /// more with food to spare, as many as the jobs (and a fifth more) can take, slowed past the target.
    func settlersWanted(_ d: District, free: Int, jobsFree: Int) -> Int {
        let pop = Double(d.population)
        let base = max(8, pop * 0.1) * (0.5 + plenty(d))
        let jobs = jobsFree + d.population / 5
        let n = Int((base * Society.growthBrake(totalPopulation)).rounded())
        return max(0, min(free, jobs, n))
    }

    /// A ranch's herd: cows and sheep inside its fence (tame, they stay with the farm), up to eight.
    func stockRanch(_ b: CityBuilding) {
        let inside = { (a: Animal) -> Bool in
            let t = a.pos.tile
            return t.x > b.x && t.y > b.y && t.x < b.x + b.w - 1 && t.y < b.y + b.d - 1
        }
        let have = realm.fauna.animals.filter { inside($0) && ["cow", "sheep"].contains($0.species.key) }.count
        guard have < 8 else { return }
        for k in have..<8 {
            let t = TilePos(b.x + 7 + (k % 4) * 3, b.y + 3 + (k / 4) * 5)
            guard t.x < b.x + b.w - 1, t.y < b.y + b.d - 1, world.tile(2, t.x, t.y) == 0 else { continue }
            spawnAnimal(k % 2 == 0 ? "cow" : "sheep", at: t.center, tame: true)
        }
    }

    /// Buy from outside what a district lacks of `cost` (at the import price), keeping `keep` money back.
    /// Only what money allows is bought; the purchase is recorded like every other import.
    func buyShortfall(_ d: District, _ cost: [String: Double], keep: Double) {
        for (k, v) in cost.sorted(by: { $0.key < $1.key }) {
            let short = v - (d.store[k] ?? 0)
            guard short > 1e-9, let price = Society.importPrice[k] else { continue }
            let n = min(short, max(0, d.money - keep) / price)
            guard n > 1e-9 else { continue }
            d.money -= n * price; d.add(k, n)
            record([(k, n)], from: "imports", to: d.holding.name, note: "bought for a building, \(Int(n * price))")
        }
    }
}
