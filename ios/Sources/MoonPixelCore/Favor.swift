import Foundation

// Where the traveller goes, the land thrives. Every game hour the towns, the new towns (districts) and the
// regional cities within `favorReach` tiles of the traveller are favoured for `favorDays` game days: there
// nobody dies of age, illness or hunger (war still kills soldiers), children are born three times as often,
// settlers come twice as fast and the new towns build more at once. When the traveller has been gone long
// enough the favour lapses and growth slows to its ordinary pace.

extension Society {
    public static var favorReach = 480
    public static var favorDays = 3.0

    /// Mark the places near the traveller as favoured for the next few days (called every game hour).
    func favorHour() {
        guard let p = realm.player.body?.pos, p.x.isFinite, p.y.isFinite else { return }
        let here = p.tile, r2 = Society.favorReach * Society.favorReach
        let until = world.time + Society.favorDays * MP.daySeconds
        var f = realm.favorUntil ?? [:]
        for s in settlements.values where !s.abandoned && s.center.distance2(here) <= r2 { f["t\(s.id)"] = until }
        for d in net.districts where d.center.distance2(here) <= r2 { f["d\(d.id)"] = until }
        if let c = realm.civBox {
            let rc = c.cfg.regionTiles
            var near = Set<Int>()
            for city in c.cities.values where TilePos(city.rx * rc + rc / 2, city.ry * rc + rc / 2).distance2(here) <= r2 {
                f["c\(city.id)"] = until; near.insert(city.id)
            }
            c.favored = Set(f.filter { $0.key.hasPrefix("c") && $0.value > world.time }.compactMap { Int($0.key.dropFirst()) })
        }
        f = f.filter { $0.value > world.time }                     // forget what has lapsed
        realm.favorUntil = f
    }

    /// Is this town favoured by the traveller's presence (now, or within the last few days)?
    public func favored(town id: Int) -> Bool { (realm.favorUntil?["t\(id)"] ?? 0) > world.time }
    public func favored(district d: District) -> Bool { (realm.favorUntil?["d\(d.id)"] ?? 0) > world.time }
}
