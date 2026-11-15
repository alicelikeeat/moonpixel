import Foundation

/// What the player did that measurably changed the world. Each entry carries the state before and after,
/// checked by the simulation itself, and a key: the same deed (the same bridge, the same town's shortage
/// in the same year, the same convoy) is credited once, also after a reload or a replayed law.
public struct Contribution: Codable, Equatable {
    public var kind: String          // transport_restored, shortage_relieved, convoy_protected, convoy_raided, capital_retaken, refugees_taken_in
    public var key: String
    public var nation: Int           // who it helped
    public var before: String, after: String
    public var t: Double, x: Double, y: Double
    public var rep: Double
}

public struct ContributionLog: Codable, Equatable {
    public var keys = StringSet()
    public var list: [Contribution] = []
    public static let keep = 64
}

extension Realm {
    public var contrib: ContributionLog { get { contribBox ?? ContributionLog() } set { contribBox = newValue } }
}

extension Society {
    static let contribText: [String: (String, String)] = [
        "transport_restored": ("Your bridge reopened the road between %@ and %@", "你修的桥让 %@ 与 %@ 之间重新通路"),
        "shortage_relieved": ("Your food ended the shortage in %@", "你送的粮食解除了 %@ 的饥荒"),
        "convoy_protected": ("You escorted %@'s supply train through", "你护送 %@ 的补给车队安全抵达"),
        "convoy_raided": ("You cut down %@'s supply train", "你截断了 %@ 的补给车队"),
        "capital_retaken": ("%@ retook its old capital %@ with you", "%@ 在你的协助下收复旧都 %@"),
        "refugees_taken_in": ("%@ took in %@ refugees you brought", "%@ 收留了你带来的 %@ 名难民"),
    ]

    /// Credit a deed once. Returns false (and changes nothing) for a key already credited.
    @discardableResult func credit(_ kind: String, key: String, nation: Int, before: String, after: String, at p: Vec2, rep: Double, args: [String]) -> Bool {
        let k = kind + ":" + key
        if realm.contrib.keys.contains(k) { return false }
        realm.contrib.keys.insert(k)
        realm.contrib.list.append(Contribution(kind: kind, key: k, nation: nation, before: before, after: after, t: world.time, x: p.x, y: p.y, rep: rep))
        if realm.contrib.list.count > ContributionLog.keep { realm.contrib.list.removeFirst(realm.contrib.list.count - ContributionLog.keep) }
        if nation != 0 { addRep(nation, rep) }
        let txt = Society.contribText[kind].map { zh ? $0.1 : $0.0 } ?? kind
        let text = args.reduce(txt) { s, a in s.replacingOccurrences(of: "%@", with: a, options: [], range: s.range(of: "%@")) }
        chronicle("contribution", text, p, nations: nation != 0 ? [nation] : [], cause: before, result: after)
        onEvent?("contribution", text, p)
        return true
    }

    var gameYear: Int { Int(world.time / MP.year) }

    // MARK: bridges
    /// Town pairs whose way passes near these cells, with how a march between them comes out now.
    func routesNear(_ cells: [TilePos]) -> [(Settlement, Settlement, RouteStatus, Double)] {
        let live = settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        var out: [(Settlement, Settlement, RouteStatus, Double)] = []
        for (i, a) in live.enumerated() { for b in live[(i + 1)...] {
            let pa = a.center.center, pb = b.center.center
            if pa.distance(to: pb) > 3200 { continue }
            let ab = pb - pa
            let near = cells.contains { c in
                let p = c.center - pa
                let t = max(0, min(1, (p.x * ab.x + p.y * ab.y) / max(1, ab.x * ab.x + ab.y * ab.y)))
                return (pa + ab * t).distance(to: c.center) < 160
            }
            if !near { continue }
            let plan = planMarch(from: a.center, to: b.center, budget: 20000)
            out.append((a, b, plan.status, routeLength(plan.points)))
            if out.count >= 4 { return out }
        } }
        return out
    }

    func creditBridge(before: [(Settlement, Settlement, RouteStatus, Double)], cells: [TilePos]) {
        for (a, b, st, _) in before where st != .complete {
            let now = planMarch(from: a.center, to: b.center, budget: 20000)
            guard now.status == .complete else { continue }
            let p = cells.first?.center ?? a.center.center
            credit("transport_restored", key: "\(a.id)-\(b.id):\(gameYear)", nation: a.nation ?? 0, before: "\(st)", after: "complete, \(Int(routeLength(now.points) / 16)) tiles",
                   at: p, rep: 0.08, args: [cityName(a), cityName(b)])
            if let n = b.nation, n != a.nation { addRep(n, 0.04) }
        }
    }

    // MARK: food
    func shortage(_ s: Settlement) -> Bool { s.food < Double(max(1, s.members.count)) * realm.cfg.foodPerHead * 0.35 }

    // MARK: convoys
    /// Called every army step for convoys of the player's nation: escort time and threats are noted.
    func noteEscort(_ lg: Legion, at p: Vec2, dt: Double) {
        guard lg.nation == realm.player.nation, lg.nation != 0, let v = viewer else { return }
        lg.convoyTrip = (lg.convoyTrip ?? 0) + dt
        if v.distance(to: p) < 160 {
            lg.escortT = (lg.escortT ?? 0) + dt
            if lg.escortThreat != true, realm.legions.contains(where: { $0.state != 0 && $0.nation != lg.nation && realm.atWar($0.nation, lg.nation) && $0.pos.distance(to: p) < 600 }) { lg.escortThreat = true }
        }
    }

    func convoyEnded(_ lg: Legion, delivered: Bool, at p: Vec2) {
        defer { lg.convoyTrip = nil; lg.escortT = nil; lg.escortThreat = nil; lg.raidT = nil }
        let name = realm.nation(lg.nation)?.name(zh: zh) ?? ""
        if delivered, let trip = lg.convoyTrip, trip > 0, (lg.escortT ?? 0) >= trip * 0.4, lg.escortThreat == true {
            credit("convoy_protected", key: "\(lg.id):\(lg.convoyStart ?? 0)", nation: lg.nation, before: "convoy under threat", after: "delivered \(Int(lg.convoyLoad ?? 0)) food",
                   at: p, rep: 0.05, args: [name])
        }
        if !delivered, let r = lg.raidT, world.time - r < 60, realm.player.nation != lg.nation {
            credit("convoy_raided", key: "\(lg.id):\(lg.convoyStart ?? 0)", nation: realm.player.nation, before: "convoy carrying \(Int(lg.convoyLoad ?? 0)) food",
                   after: "convoy lost", at: p, rep: 0.04, args: [name])
        }
    }
}
