import Foundation

// The four realms trade and move people (the civilisation layer).
//
// * Every sky island over a known region is a nation of its own (`foundSky`): a city of the sky, its people
//   farming the island and flying.
// * The realms each make something the others want: the underground stone, ore and sea glass; the sea floor
//   fish; the sky grain from its terraces; the ground timber. Every day a city that has plenty of what its realm
//   makes opens a standing exchange with the nearest city of another realm that has little of it (and the
//   shortages of any nation are met from every realm too). Goods go by the way between the two realms
//   (`realmWay`): by air to and from the sky (planes, saucers), by ship and submarine to and from the sea floor,
//   by the glass elevators between the ground and the cities under it, by the trains below between cities
//   underground.
// * People move between the realms: a crowded or hungry city sends some of its people to a city of another
//   realm that has room and food, by the same ways.
// * War is for the nations of the ground only (`Civ.declare`): the others declare none and none is declared on
//   them.

public enum RealmTune {
    /// A load of a standing exchange, what the seller keeps back, and what makes the buyer full.
    public static let load = 40.0, keep = 60.0, full = 400.0
    /// Days a region for each way between the realms (plus a day's loading and unloading).
    public static let days: [String: Double] = ["air": 0.15, "ship": 0.3, "lift": 0.4, "rail": 0.35]
    /// What each realm makes, a day per city, and sells.
    public static let makes: [String: [(String, Double)]] = [
        "under": [("ore", 4), ("stone", 3)],
        "sea": [("fish", 6)],
        "sky": [("grain", 10)],
        "ground": [("timber", 0)],
    ]
    /// The goods each realm sells to the others.
    public static let sells: [String: [String]] = ["under": ["ore", "stone", "sea_glass"], "sea": ["fish"], "sky": ["grain"], "ground": ["timber", "grain"]]
    /// A city sends people to another realm at most this often (days), this many at a time.
    public static let moveEvery = 6.0, moveGroup = 8
}

extension Civ {
    /// Which realm a city is in: "ground", "under", "sea" or "sky".
    public static func realmOf(_ c: CivCity) -> String { c.sky == true ? "sky" : (c.sea == true ? "sea" : (c.under == true ? "under" : "ground")) }

    /// The way between two cities of different realms, and how long it takes; nil when both are on the ground
    /// (their way is by road or by sea: `tradeWay`).
    public func realmWay(from a: CivCity, to b: CivCity) -> (mode: String, days: Double)? {
        let ra = Civ.realmOf(a), rb = Civ.realmOf(b)
        if ra == "ground" && rb == "ground" { return nil }
        let mode: String
        if ra == "sky" || rb == "sky" { mode = "air" }
        else if ra == "sea" || rb == "sea" { mode = "ship" }
        else if ra == "under" && rb == "under" { mode = "rail" }
        else { mode = "lift" }
        let d = Double(max(1, dist(a.regionKey, b.regionKey)))
        return (mode, 1 + d * (RealmTune.days[mode] ?? 0.5))
    }

    /// How long a shipment takes on a route.
    func routeDays(_ r: CivTradeRoute) -> Double {
        if let m = r.mode, let s = cities[r.seller], let b = cities[r.buyer] {
            return 1 + Double(max(1, dist(s.regionKey, b.regionKey))) * (RealmTune.days[m] ?? 0.5)
        }
        return Double(r.path.count) * (r.sea ? ResourceTune.seaDaysPerRegion : ResourceTune.landDaysPerRegion)
    }

    /// Found the nation of the sky island over a region, once (when the region is first known).
    func foundSky(_ key: Int64, gen: Generator) {
        guard var r = regions[key], r.skySeen != true else { return }
        r.skySeen = true
        regions[key] = r
        guard r.skyCity == nil else { return }
        let per = cfg.regionTiles / 32
        var at: (Int, Int)?
        for cy in (r.ry * per)..<((r.ry + 1) * per) { for cx in (r.rx * per)..<((r.rx + 1) * per) where at == nil && gen.isSkyCity(cx, cy) { at = (cx, cy) } }
        guard let (cx, cy) = at else { return }
        let n = newPolity(origin: "sky", near: key)
        polities[n]!.sky = true
        polities[n]!.leaning = "science"
        polities[n]!.nameEn = gen.skyCityName(cx, cy, zh: false)
        polities[n]!.nameZh = gen.skyCityName(cx, cy, zh: true)
        var h = RNG(seed: gen.seed &* 307 &+ cx &* 11 &+ cy &* 23)
        let adults = 40 + h.index(50)
        let c = newCity(at: key, nation: n, people: CivPeople(adults: adults, children: adults / 3, elders: adults / 5), firstCount: true, sky: true)
        c.nameEn = gen.skyCityName(cx, cy, zh: false); c.nameZh = gen.skyCityName(cx, cy, zh: true)
        c.facilities = ["farm": max(4, adults / 3), "house": adults / 4 + 2, "well": 2]
        c.stock = ["grain": Double(adults) * 18]
        for (k, v) in c.stock where CivFood.isFood(k) { totals.add(\.found, k, v) }
        c.cropDue = Double(day) + 3; c.cropPlots = c.has("farm")
        c.skyAt = (cx, cy)
        polities[n]!.capital = c.id
        say("sky_nation", [polities[n]!.nameEn, polities[n]!.nameZh], [n], region: key)
    }

    /// The cities of the sky islands.
    public func skyCities() -> [CivCity] { cities.values.filter { $0.sky == true }.sorted { $0.id < $1.id } }

    /// Once a day: each realm makes its own goods, standing exchanges open between the realms, and people move.
    func realmsDaily() {
        let active = cities.values.filter { polities[$0.nation]?.status == .active && $0.detail == nil }.sorted { $0.id < $1.id }
        // what each realm makes (beyond the farms and mines every city has)
        for c in active {
            let realm = Civ.realmOf(c)
            let hands = Double(max(1, c.people.band(1))) / 40
            for (good, perDay) in RealmTune.makes[realm] ?? [] where perDay > 0 {
                let v = perDay * min(3, hands)
                c.stock[good, default: 0] += v
                c.today.add(\.made, good, v); c.ledger.add(\.made, good, v)
                if CivFood.isFood(good) { totals.add(\.found, good, v) }
            }
        }
        // standing exchanges: what a realm has plenty of, to the nearest city of another realm short of it
        for c in active {
            let realm = Civ.realmOf(c)
            for good in RealmTune.sells[realm] ?? [] where (c.stock[good] ?? 0) > RealmTune.keep + RealmTune.load {
                if tradeRoutes.contains(where: { $0.active && $0.exchange == true && $0.seller == c.id && $0.good == good }) { continue }
                let buyers = active.filter { b in
                    b.nation != c.nation || Civ.realmOf(b) != realm
                }.filter { b in
                    Civ.realmOf(b) != realm && (b.stock[good] ?? 0) < RealmTune.keep && !atWar(c.nation, b.nation)
                        && !tradeRoutes.contains(where: { $0.active && $0.exchange == true && $0.buyer == b.id && $0.good == good })
                }
                guard let b = buyers.min(by: { x, y in
                    let dx = dist(x.regionKey, c.regionKey), dy = dist(y.regionKey, c.regionKey)
                    return dx != dy ? dx < dy : x.id < y.id
                }), let way = realmWay(from: c, to: b) else { continue }
                var r = CivTradeRoute()
                r.id = nextRoute; nextRoute += 1
                r.seller = c.id; r.buyer = b.id; r.good = good; r.path = [c.regionKey, b.regionKey]
                r.mode = way.mode; r.exchange = true
                r.since = now; r.next = now
                tradeRoutes.append(r)
                let names = [polities[c.nation]?.nameEn ?? "", polities[c.nation]?.nameZh ?? "", polities[b.nation]?.nameEn ?? "", polities[b.nation]?.nameZh ?? "",
                             CivItem.byKey[good]?.en ?? good, CivItem.byKey[good]?.zh ?? good]
                say("realm_trade_" + way.mode, names, [c.nation, b.nation], region: c.regionKey)
                record("realm_trade", nations: [c.nation, b.nation], region: c.regionKey, ids: [r.id], note: good + ":" + way.mode)
                break
            }
        }
        // people move between the realms: from a crowded or hungry city to one of another realm with room and food
        for c in active where c.pop > 60 && (c.crowding > 0.9 || c.foodDays < 8) {
            if trips.values.contains(where: { $0.from == c.id && $0.mode != nil && $0.settle == nil }) { continue }
            guard Double(day).truncatingRemainder(dividingBy: RealmTune.moveEvery) == Double(c.id % Int(RealmTune.moveEvery)) else { continue }
            let realm = Civ.realmOf(c)
            guard let to = active.filter({ Civ.realmOf($0) != realm && $0.crowding < 0.8 && $0.foodDays > 15 && !atWar(c.nation, $0.nation) })
                .min(by: { x, y in
                    let dx = dist(x.regionKey, c.regionKey), dy = dist(y.regionKey, c.regionKey)
                    return dx != dy ? dx < dy : x.id < y.id
                }), let way = realmWay(from: c, to: to) else { continue }
            var group = c.people.take(RealmTune.moveGroup, from: Array(6..<12))
            group.add(c.people.take(RealmTune.moveGroup / 4, from: Array(0..<6)))
            guard group.total > 0 else { continue }
            var t = CivTrip(); t.id = nextTrip; nextTrip += 1
            t.nation = c.nation; t.from = c.id; t.to = to.id; t.forNation = to.nation
            t.route = c.regionKey == to.regionKey ? [c.regionKey] : [c.regionKey, to.regionKey]
            t.people = group; t.mode = way.mode
            t.cargo = takeFood(from: c, nutrition: Double(group.total) * 3)
            c.today.migOut += group.total; c.ledger.migOut += group.total; totals.migOut += group.total
            c.sick = min(c.sick, c.pop)
            trips[t.id] = t
            say("realm_move_" + way.mode, ["\(group.total)", c.nameEn, c.nameZh, to.nameEn, to.nameZh], [c.nation, to.nation], region: c.regionKey)
        }
    }

    /// The trade and travel between the realms going on now, by way: routes open, shipments under way and
    /// people travelling (for the panels and the map).
    public func realmTraffic() -> [String: (routes: Int, loads: Int, people: Int)] {
        var out: [String: (routes: Int, loads: Int, people: Int)] = [:]
        for r in tradeRoutes where r.active { if let m = r.mode { out[m, default: (0, 0, 0)].routes += 1 } }
        for sh in shipments { if let r = tradeRoutes.first(where: { $0.id == sh.route }), let m = r.mode { out[m, default: (0, 0, 0)].loads += 1 } }
        for t in trips.values { if let m = t.mode { out[m, default: (0, 0, 0)].people += t.people.total } }
        return out
    }
}
