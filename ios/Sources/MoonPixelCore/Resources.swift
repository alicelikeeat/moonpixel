import Foundation

// Oil, gold and the other things nations need, and what they do to get them (worlds with envoys).
//
// * Gold lies in some regions (mostly under mountains) and is dug by gold mines; oil is pumped by oil wells
//   and refined to fuel. Both are worth a great deal (`ResourceTune.price`).
// * A nation short of something (oil, fuel, gold, ore, steel or food) looks for a nation at peace with it that
//   has plenty and opens a trade route between their cities: over the sea between their ports when the sea
//   joins them, else over land. Every few days a shipment goes, paid for on delivery; trade warms the two
//   nations to each other. A shipment at sea whose way passes warships of a nation at war with either side is
//   sunk, cargo and all.
// * A nation short of oil or gold that is strong enough wants the place that has it: its envoy asks for the
//   city on the oilfield or the gold mine first, and a refusal is a war for that place.
// * Spies: a nation sends spies to rivals and to nations with what it lacks: to steal a technology, steal gold,
//   sabotage an oil well, or look at their strength. Some are caught: the victim's regard falls, and a nation
//   that catches spies again and again may go to war over it.

public struct CivTradeRoute: Codable, Equatable {
    public var id = 0
    public var seller = 0, buyer = 0                 // cities
    public var good = ""
    public var sea = false
    public var path: [Int64] = []                    // regions, sea or land
    public var since = 0.0, next = 0.0
    public var shipped = 0.0, paid = 0.0, lost = 0
    public var active = true
}

public struct CivShipment: Codable, Equatable {
    public var route = 0
    public var good = "", amount = 0.0
    public var arrives = 0.0
}

public struct CivSpy: Codable, Equatable {
    public enum Mission: String, Codable { case stealTech, stealGold, sabotage, scout }
    public var id = 0, from = 0, to = 0
    public var mission = Mission.scout
    public var city = 0
    public var arrives = 0.0
    public var outcome: String?                      // "success", "caught", "nothing"
    public var note = ""
}

public enum ResourceTune {
    /// What a unit of each good is worth (treasury).
    public static let price: [String: Double] = ["crude": 4, "fuel": 7, "gold": 30, "ore": 2, "coal": 1.5, "steel": 9, "grain": 1, "fish": 1.2, "meat": 2]
    /// What a nation must hold to be "not short" (per city), and what it can spare above.
    public static let need: [String: Double] = ["crude": 40, "fuel": 40, "gold": 20, "ore": 60, "steel": 30, "grain": 400]
    public static let spare: [String: Double] = ["crude": 120, "fuel": 120, "gold": 60, "ore": 150, "steel": 80, "grain": 1500]
    public static let shipEvery = 3.0, shipAmount = 80.0, seaDaysPerRegion = 0.25, landDaysPerRegion = 0.5
    public static let spyChance = 0.04, caughtChance = 0.3
}

extension Civ {
    /// The hour being simulated: inside a long `advance`, `time` is already the end of the jump.
    var now: Double { time - hourAcc }

    // MARK: - what a nation has and lacks

    /// How much of a good a nation holds, over all its cities.
    public func held(_ n: Int, _ good: String) -> Double { cities(of: n).reduce(0.0) { $0 + ($1.stock[good] ?? 0) } }

    /// The goods a nation is short of (it uses them or wants them and holds too little).
    public func shortages(_ n: Int) -> [String] {
        guard let p = polities[n] else { return [] }
        let k = Double(max(1, cities(of: n).count))
        var out: [String] = []
        if p.knows("oil") || p.knows("engines") { for g in ["crude", "fuel"] where held(n, g) < ResourceTune.need[g]! * k { out.append(g) } }
        if held(n, "gold") < ResourceTune.need["gold"]! * k { out.append("gold") }
        if p.knows("metallurgy") && held(n, "ore") < ResourceTune.need["ore"]! * k { out.append("ore") }
        if p.knows("steel") && held(n, "steel") < ResourceTune.need["steel"]! * k { out.append("steel") }
        if p.foodDays < 10 { out.append("grain") }
        return out
    }

    /// Its city with the most of a good to spare, if any.
    func spareCity(_ n: Int, _ good: String) -> CivCity? {
        cities(of: n).filter { ($0.stock[good] ?? 0) > ResourceTune.spare[good] ?? 100 }.max { ($0.stock[good] ?? 0) < ($1.stock[good] ?? 0) }
    }

    /// The way goods go from one city to another: over the sea between their ports (when both are ports and the
    /// sea joins them), else over land. Nil when there is none.
    public func tradeWay(from a: CivCity, to b: CivCity) -> (sea: Bool, path: [Int64])? {
        let bodies = waterBodies()
        func waterBeside(_ c: CivCity) -> Int64? {
            Civ.four.map { MP.chunkKey(c.rx + $0.0, c.ry + $0.1) }.first { k in bodies.of[k].map { isOpenSea($0, bodies.size) } ?? false }
        }
        if portSite(a.regionKey, bodies: bodies) != nil, portSite(b.regionKey, bodies: bodies) != nil, let wa = waterBeside(a), let wb = waterBeside(b),
           let p = route(from: wa, to: wb, size: .vehicle, layer: .sea) { return (true, [a.regionKey] + p + [b.regionKey]) }
        if let p = route(from: a.regionKey, to: b.regionKey, size: .vehicle) { return (false, p) }
        return nil
    }

    // MARK: - the day

    func resourcesDaily() {
        tradeChoices()
        shipping()
        spyChoices()
        spiesArrive()
        for id in polities.keys.sorted() {
            // gold is wealth: a little of what is dug is coined into the treasury every day
            for c in cities(of: id) where (c.stock["gold"] ?? 0) > 0 {
                let coin = (c.stock["gold"] ?? 0) * 0.05
                c.stock["gold"]! -= coin
                polities[id]!.treasury += coin * ResourceTune.price["gold"]!
            }
        }
    }

    /// Open trade routes for what nations lack, from nations at peace that have it to spare.
    func tradeChoices() {
        for id in polities.keys.sorted() {
            guard let p = polities[id], p.status == .active, polities[id]!.underground != true, let home = homeCity(id) else { continue }
            for good in shortages(id) {
                if tradeRoutes.contains(where: { $0.active && $0.good == good && cities[$0.buyer]?.nation == id }) { continue }
                var best: (Double, CivCity, (sea: Bool, path: [Int64]))?
                for o in polities.keys.sorted() where o != id {
                    guard let q = polities[o], q.status == .active, q.underground != true, !atWar(id, o), let seller = spareCity(o, good) else { continue }
                    guard let way = tradeWay(from: seller, to: home) else { continue }
                    let len = Double(way.path.count) * (way.sea ? ResourceTune.seaDaysPerRegion : ResourceTune.landDaysPerRegion)
                    if best == nil || len < best!.0 { best = (len, seller, way) }
                }
                guard let (_, seller, way) = best else { continue }
                var r = CivTradeRoute()
                r.id = nextRoute; nextRoute += 1
                r.seller = seller.id; r.buyer = home.id; r.good = good; r.sea = way.sea; r.path = way.path
                r.since = now; r.next = now
                tradeRoutes.append(r)
                say(way.sea ? "sea_route" : "trade_route", [polities[seller.nation]!.nameEn, polities[seller.nation]!.nameZh, p.nameEn, p.nameZh, good, good], [seller.nation, id], region: seller.regionKey)
                record(way.sea ? "sea_route" : "trade_route", nations: [seller.nation, id], region: seller.regionKey, ids: [r.id], note: good)
            }
        }
    }

    /// Shipments set out on their routes and arrive (or are sunk on the way).
    func shipping() {
        for i in tradeRoutes.indices where tradeRoutes[i].active {
            var r = tradeRoutes[i]
            guard let s = cities[r.seller], let b = cities[r.buyer], polities[s.nation]?.status == .active, polities[b.nation]?.status == .active, !atWar(s.nation, b.nation) else {
                r.active = false; tradeRoutes[i] = r; continue
            }
            // the buyer has what it needs again: the route closes
            if !shortages(b.nation).contains(r.good) && now - r.since > 4 * MP.daySeconds { r.active = false; tradeRoutes[i] = r; continue }
            if now >= r.next {
                let amount = min(ResourceTune.shipAmount, max(0, (s.stock[r.good] ?? 0) - (ResourceTune.spare[r.good] ?? 0) * 0.5))
                if amount > 1 {
                    s.stock[r.good]! -= amount
                    let days = Double(r.path.count) * (r.sea ? ResourceTune.seaDaysPerRegion : ResourceTune.landDaysPerRegion)
                    shipments.append(CivShipment(route: r.id, good: r.good, amount: amount, arrives: now + max(0.5, days) * MP.daySeconds))
                }
                r.next = now + ResourceTune.shipEvery * MP.daySeconds
            }
            tradeRoutes[i] = r
        }
        var keep: [CivShipment] = []
        for sh in shipments {
            guard let ri = tradeRoutes.firstIndex(where: { $0.id == sh.route }), let s = cities[tradeRoutes[ri].seller], let b = cities[tradeRoutes[ri].buyer] else { continue }
            // a convoy whose way passes warships of a nation at war with either side is sunk
            let r = tradeRoutes[ri]
            if r.sea, forces.values.contains(where: { f in (f.layer == .sea || f.layer == .underwater) && r.path.contains(f.region) && (atWar(f.nation, s.nation) || atWar(f.nation, b.nation)) }) {
                tradeRoutes[ri].lost += 1
                totals.add(\.lost, sh.good, CivFood.isFood(sh.good) ? sh.amount : 0)
                say("convoy_sunk", [polities[s.nation]?.nameEn ?? "", polities[s.nation]?.nameZh ?? "", sh.good, sh.good], [s.nation, b.nation], region: r.path[r.path.count / 2])
                record("convoy_sunk", nations: [s.nation, b.nation], region: r.path[r.path.count / 2], ids: [r.id], note: sh.good)
                continue
            }
            guard sh.arrives <= now else { keep.append(sh); continue }
            b.stock[sh.good, default: 0] += sh.amount
            let price = sh.amount * (ResourceTune.price[sh.good] ?? 1)
            polities[b.nation]!.treasury -= price; polities[s.nation]!.treasury += price
            tradeRoutes[ri].shipped += sh.amount; tradeRoutes[ri].paid += price
            let k = touch(s.nation, b.nation)
            relations[k]!.trade += sh.amount
            relations[k]!.value = min(0.9, relations[k]!.value + 0.02)
        }
        shipments = keep
    }

    // MARK: - spies

    func spyChoices() {
        for id in polities.keys.sorted() {
            guard let p = polities[id], p.status == .active, p.ai, p.underground != true, p.undersea != true, p.treasury > 50 else { continue }
            guard !spies.contains(where: { $0.from == id && $0.outcome == nil }), rng.unit() < ResourceTune.spyChance else { continue }
            let lacks = Set(shortages(id))
            // the target: a rival, or a nation with what it lacks; nearest first
            guard let home = homeCity(id) else { continue }
            let cands = polities.keys.sorted().filter { o in
                guard o != id, let q = polities[o], q.status == .active, q.undersea != true, q.underground != true, let r = relation(id, o) else { return false }
                return r.value < -0.2 || r.state == 1 || lacks.contains { held(o, $0) > (ResourceTune.spare[$0] ?? 100) }
            }
            guard let target = cands.min(by: { a, b in
                let da = homeCity(a).map { dist($0.regionKey, home.regionKey) } ?? 999, db = homeCity(b).map { dist($0.regionKey, home.regionKey) } ?? 999
                return da != db ? da < db : a < b }), let city = homeCity(target) else { continue }
            let theirTech = Set(polities[target]!.techs).subtracting(p.techs)
            let mission: CivSpy.Mission
            if lacks.contains("gold") && held(target, "gold") > 10 { mission = .stealGold }
            else if !theirTech.isEmpty { mission = .stealTech }
            else if relation(id, target)?.state == 1 && cities(of: target).contains(where: { $0.has("oilwell") > 0 }) { mission = .sabotage }
            else { mission = .scout }
            sendSpy(id, to: target, mission: mission)
            _ = city
        }
    }

    /// Send a spy on a mission to a nation's capital. Returns its id.
    @discardableResult public func sendSpy(_ from: Int, to target: Int, mission: CivSpy.Mission) -> Int? {
        guard let home = homeCity(from), let city = homeCity(target) else { return nil }
        var s = CivSpy(); s.id = nextSpy; nextSpy += 1
        s.from = from; s.to = target; s.city = city.id; s.mission = mission
        s.arrives = now + Double(max(1, dist(home.regionKey, city.regionKey))) * 0.3 * MP.daySeconds
        polities[from]?.treasury -= 20
        spies.append(s)
        return s.id
    }

    func spiesArrive() {
        for i in spies.indices where spies[i].outcome == nil && spies[i].arrives <= now {
            var s = spies[i]
            guard let from = polities[s.from], let to = polities[s.to], to.status == .active else { s.outcome = "nothing"; spies[i] = s; continue }
            // a nation further ahead in its studies is harder to fool
            let caught = rng.unit() < ResourceTune.caughtChance * (era(s.to) >= era(s.from) ? 1.2 : 0.8)
            if caught {
                s.outcome = "caught"
                let k = touch(s.from, s.to)
                relations[k]!.value = max(-1, relations[k]!.value - 0.3)
                relations[k]!.claim = relations[k]!.claim || relations[k]!.value < -0.6
                say("spy_caught", [to.nameEn, to.nameZh, from.nameEn, from.nameZh], [s.to, s.from])
                record("spy_caught", nations: [s.to, s.from], ids: [s.id], note: s.mission.rawValue)
                // caught again and again: the victim, if far the stronger, goes to war over it
                let times = spies.filter { $0.from == s.from && $0.to == s.to && $0.outcome == "caught" }.count + 1
                if times >= 3 && relations[k]!.value < -0.6 && mobilisable(s.to) > 3 * max(1, mobilisable(s.from)) { declare(s.to, on: s.from) }
                spies[i] = s
                continue
            }
            s.outcome = "success"
            switch s.mission {
            case .stealTech:
                if let t = Set(to.techs).subtracting(from.techs).sorted().first(where: { CivTech.byKey[$0]?.needs.allSatisfy(from.techs.contains) ?? false }) {
                    polities[s.from]!.techs.append(t); s.note = t
                } else { s.outcome = "nothing" }
            case .stealGold:
                if let c = cities(of: s.to).max(by: { ($0.stock["gold"] ?? 0) < ($1.stock["gold"] ?? 0) }), (c.stock["gold"] ?? 0) > 1, let home = homeCity(s.from) {
                    let n = (c.stock["gold"] ?? 0) * 0.3
                    c.stock["gold"]! -= n; home.stock["gold", default: 0] += n; s.note = String(format: "%.0f", n)
                } else { s.outcome = "nothing" }
            case .sabotage:
                if let c = cities(of: s.to).first(where: { $0.has("oilwell") > 0 }) { c.facilities["oilwell"]! -= 1; s.note = c.nameEn } else { s.outcome = "nothing" }
            case .scout:
                s.note = String(format: "%.0f", mobilisable(s.to))
                if let city = cities[s.city] { intel["\(s.from):city\(city.id)"] = CivSighting(region: city.regionKey, at: now, live: true) }
            }
            if s.outcome == "success" { record("spy_" + s.mission.rawValue, nations: [s.from, s.to], ids: [s.id], note: s.note) }
            spies[i] = s
        }
        if spies.count > 200 { spies.removeFirst(spies.count - 200) }
    }

    // MARK: - what the panels say

    public func resourceLines(_ n: Int, zh: Bool) -> [String] {
        let fmt = { (d: Double) in String(format: "%.0f", d) }
        var out = [zh ? "资源：原油 \(fmt(held(n, "crude"))) · 燃油 \(fmt(held(n, "fuel"))) · 黄金 \(fmt(held(n, "gold"))) · 铁矿 \(fmt(held(n, "ore")))"
                      : "resources: crude \(fmt(held(n, "crude"))) · fuel \(fmt(held(n, "fuel"))) · gold \(fmt(held(n, "gold"))) · ore \(fmt(held(n, "ore")))"]
        let short = shortages(n)
        if !short.isEmpty { out.append((zh ? "短缺：" : "short of: ") + short.joined(separator: zh ? "、" : ", ")) }
        for r in tradeRoutes where r.active && (cities[r.seller]?.nation == n || cities[r.buyer]?.nation == n) {
            let other = cities[r.seller]?.nation == n ? cities[r.buyer] : cities[r.seller]
            let who = other.flatMap { polities[$0.nation]?.name(zh: zh) } ?? "?"
            let dir = cities[r.seller]?.nation == n ? (zh ? "卖给" : "sells to") : (zh ? "买自" : "buys from")
            out.append((r.sea ? "⚓ " : "🛤 ") + "\(dir) \(who)：\(r.good) · " + (zh ? "已运 \(fmt(r.shipped))，被击沉 \(r.lost) 次" : "\(fmt(r.shipped)) shipped, \(r.lost) sunk"))
        }
        let sent = spies.filter { $0.from == n }, caught = sent.filter { $0.outcome == "caught" }.count
        let theirs = spies.filter { $0.to == n && $0.outcome == "caught" }.count
        if !sent.isEmpty || theirs > 0 { out.append(zh ? "间谍：派出 \(sent.count)，被抓 \(caught)；抓获外国间谍 \(theirs)" : "spies: \(sent.count) sent, \(caught) caught; \(theirs) foreign spies caught") }
        return out
    }
}
