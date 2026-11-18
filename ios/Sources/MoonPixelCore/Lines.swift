import Foundation

// Stops, lines, trips and freight.
//
// A stop is a real place on the network where a vehicle stands (a kerb by a street, a track by a
// platform, a stand by a runway, a berth by a quay). A line is a list of stops run back and forth by the
// vehicles given to it, one leaving each end every `headway` seconds. People wait at stops and ride in
// vehicles; goods wait in a stop's yard and ride as cargo. A person or a crate is in exactly one place at
// any time: at a stop, in one vehicle, or arrived. Every hand-over writes one line in the books.
//
// Borders: a vehicle does not leave for a stop of a nation at war with its own, and nobody boards for
// one; the line says it is suspended and why. When the war ends it runs again.

public enum StopKind: String, Codable, CaseIterable {
    case busStop, station, airport, port, yard
    public var mode: TravelMode {
        switch self { case .busStop, .yard: return .road; case .station: return .rail; case .airport: return .air; case .port: return .water }
    }
    public func name(zh: Bool) -> String {
        let n: [StopKind: (String, String)] = [.busStop: ("Bus stop", "公交站"), .station: ("Station", "车站"), .airport: ("Airport", "机场"), .port: ("Port", "港口"), .yard: ("Goods yard", "货场")]
        return zh ? n[self]!.1 : n[self]!.0
    }
}

public final class Stop: Codable {
    public var id = 0
    public var name = ""
    public var kind = StopKind.busStop
    public var x = 0, y = 0, l = 0        // where a vehicle stands
    public var nation = 0
    public var district: Int?
    public var waiting: [Rider] = []
    /// Goods in the yard, by shipment.
    public var yard: [Int: Double] = [:]
    public var served = 0
    public init() {}
    public var node: NetNode { NetNode(x, y, l) }
    public var tile: TilePos { TilePos(x, y) }
    public var mode: TravelMode { kind.mode }
}

public final class Line: Codable {
    public var id = 0
    public var name = ""
    public var kind = VehicleKind.bus
    public var stops: [Int] = []
    public var vehicles: [Int] = []
    public var headway = 600.0            // seconds between departures from each end
    public var fare = 2.0
    public var nation = 0
    public var payer = Payer.pack
    public var freight = false
    public var suspended: String?
    public var nextDepart: [Double] = [0, 0]     // from the first stop, from the last stop
    public var trips = 0, riders = 0
    public var delaySum = 0.0, arrivals = 0
    public var revenue = 0.0, costs = 0.0
    public var carried = 0.0
    public init() {}
    public var mode: TravelMode { kind.mode }
    public var meanDelay: Double { arrivals > 0 ? delaySum / Double(arrivals) : 0 }
}

/// Where goods start or end.
public enum Place: Codable, Equatable, Hashable {
    case district(Int)                    // a district's warehouse
    case town(Int)                        // a town's store
    case stop(Int)                        // a stop's yard
}

public struct Leg: Codable, Equatable { public var line: Int; public var from: Int; public var to: Int }

public final class Shipment: Codable {
    public enum State: String, Codable { case waiting, aboard, delivered, returned }
    public var id = 0
    public var key = "food"
    public var amount = 0.0
    public var origin = Place.district(0), dest = Place.district(0)
    public var legs: [Leg] = []
    public var leg = 0
    public var state = State.waiting
    public var delivered = 0.0
    public var created = 0.0
    public var done: Double?
    public var note = ""
    public init() {}
}

/// A journey worked out for someone: walking and lines, with the changes between them.
public struct TripLeg: Equatable {
    public var line: Int?                 // nil: walking
    public var from: Int?, to: Int?       // stops
    public var seconds = 0.0
}
public struct TripPlan: Equatable {
    public var legs: [TripLeg] = []
    public var seconds = 0.0
    public var transfers: Int { max(0, legs.filter { $0.line != nil }.count - 1) }
    public var ok = false
    public var reason = ""
}

extension Society {
    // MARK: stops and lines

    /// A stop where a vehicle of its kind can really stand (a kerb on a street, a track by a platform...).
    @discardableResult public func addStop(_ kind: StopKind, at t: TilePos, name: String, nation: Int = 0, district: Int? = nil) -> Stop? {
        let n = NetNode(t.x, t.y, 0)
        let ok: Bool
        switch kind {
        case .busStop, .yard: ok = passable(n, Profile(mode: .road))
        case .station: ok = passable(n, Profile(mode: .rail))
        case .airport: ok = wayKind(at: t)?.mode == .air
        case .port: ok = waterDepth(t) >= 1.5 && quayBeside(t)
        }
        guard ok else { return nil }
        let s = Stop(); s.id = realm.transport.take(); s.kind = kind; s.x = t.x; s.y = t.y; s.name = name; s.nation = nation; s.district = district
        realm.transport.stops.append(s)
        return s
    }

    /// A line between stops of the kind its vehicles use.
    @discardableResult public func addLine(_ kind: VehicleKind, stops: [Int], name: String, headway: Double, fare: Double = 2, nation: Int = 0, payer: Payer = .pack, freight: Bool = false) -> Line? {
        let ss = stops.compactMap { net.stop($0) }
        guard ss.count >= 2, ss.allSatisfy({ $0.mode == kind.mode || ($0.kind == .yard && kind.mode == .road) || ($0.kind == .yard && kind.mode == .rail && passable($0.node, profile(kind))) }) else { return nil }
        let l = Line(); l.id = realm.transport.take(); l.kind = kind; l.stops = stops; l.name = name; l.headway = headway; l.fare = fare; l.nation = nation; l.payer = payer; l.freight = freight
        l.nextDepart = [world.time, world.time]
        realm.transport.lines.append(l)
        return l
    }

    /// Put a vehicle on a line: it goes to the line's nearest end and runs from there.
    public func assign(_ v: Vehicle, to l: Line) {
        if let old = v.task.line, let ol = net.line(old) { ol.vehicles.removeAll { $0 == v.id } }
        l.vehicles.append(v.id)
        var t = VehicleTask(); t.line = l.id
        let first = net.stop(l.stops.first!)!, last = net.stop(l.stops.last!)!
        if last.tile.distance2(v.tile) < first.tile.distance2(v.tile) { t.at = l.stops.count - 1; t.dir = -1 } else { t.at = 0; t.dir = 1 }
        t.due = world.time
        v.task = t
        v.replan = true
    }

    /// Two nations' borders are open unless they are at war.
    public func borderOpen(_ a: Int, _ b: Int) -> Bool { a == 0 || b == 0 || a == b || !realm.atWar(a, b) }

    /// Why a line cannot run now (nil: it can).
    func lineBlocked(_ l: Line) -> String? {
        let nations = Set(l.stops.compactMap { net.stop($0)?.nation }.filter { $0 != 0 } + [l.nation].filter { $0 != 0 })
        for a in nations { for b in nations where a < b && realm.atWar(a, b) { return "war" } }
        return nil
    }

    // MARK: at a stop

    /// Every step after moving: a vehicle that has come to its stop opens its doors, lets people and goods
    /// off and on, and leaves on time for the next one.
    func linesStep(_ dt: Double) {
        let tr = realm.transport
        for l in tr.lines {
            let was = l.suspended
            l.suspended = lineBlocked(l)
            if was != l.suspended { if let w = l.suspended { lineEvent(l, "suspended: " + w) } else { lineEvent(l, "running again") } }
        }
        for v in tr.vehicles.sorted(by: { $0.id < $1.id }) {
            guard let lid = v.task.line, let l = tr.line(lid), v.task.at < l.stops.count, let st = tr.stop(l.stops[v.task.at]) else { continue }
            if !v.task.standing {
                // arrived? at the stop, stopped (a ship at its berth, a plane on the ground)
                let reach = v.kind.mode == .road ? Int(v.spec.length) + 2 : (v.kind.mode == .rail ? 3 : (v.kind.mode == .air ? 3 : 1))
                let there = v.tile.distance2(st.tile) <= reach * reach && v.pathI >= v.path.count
                let still = v.kind.mode == .water ? (v.berthed || abs(v.speed) < 0.3) : (abs(v.speed) < 0.3 && v.flight == .ground)
                if there && still && v.control == .auto || (v.control == .manual && there && still && v.playerDriving) {
                    v.task.standing = true
                    v.task.dwell = v.kind.mode == .road ? 15 : (v.kind.mode == .rail ? 30 : 60)
                    let late = max(0, world.time - v.task.due)
                    v.delay = late; l.delaySum += late; l.arrivals += 1
                    arriveAt(v, st, l)
                }
                continue
            }
            // standing: people and goods, then off on time
            exchange(v, st, l)
            v.task.dwell -= dt
            guard v.task.dwell <= 0 else { continue }
            if l.suspended != nil { v.halted = "line suspended: " + l.suspended!; continue }
            // next stop (turning round at the ends)
            var next = v.task.at + v.task.dir, dir = v.task.dir
            if next < 0 || next >= l.stops.count { dir = -dir; next = v.task.at + dir }
            // at an end the timetable sets the departure
            let end = v.task.at == 0 ? 0 : (v.task.at == l.stops.count - 1 ? 1 : -1)
            if end >= 0 {
                if world.time < l.nextDepart[end] { continue }
                l.nextDepart[end] = max(world.time, l.nextDepart[end]) + l.headway
                l.trips += 1
                if v.wear > 0.3 { repair(v) }
                if v.spec.energy.good != nil && v.fuel < v.spec.tank * 0.5 { refuel(v) }
            }
            guard let ns = tr.stop(l.stops[next]), borderOpen(v.nation, ns.nation) else { v.halted = "border closed"; continue }
            // an aircraft leaves only with fuel for twice the flight and a reserve (a holding pattern is long)
            if v.kind.mode == .air {
                let need = Double(abs(st.x - ns.x) + abs(st.y - ns.y)) * v.spec.burn * 2 + v.spec.tank * 0.25
                if v.fuel < need { refuel(v) }
                if v.fuel < need { v.halted = "waiting for fuel"; continue }
                if v.halted == "waiting for fuel" { v.halted = nil }
            }
            if v.halted?.hasPrefix("line suspended") == true || v.halted == "border closed" { v.halted = nil }
            v.task.standing = false
            v.task.at = next; v.task.dir = dir
            v.task.due = world.time + estimate(v, from: st, to: ns)
            if v.kind.mode == .air { v.task.dwell = 0; v.task.goal = nil; v.task.phase = nil }
            v.replan = true
        }
    }

    /// Seconds a vehicle should take between two stops at its line speed (for the timetable).
    func estimate(_ v: Vehicle, from a: Stop, to b: Stop) -> Double {
        let d = Double(abs(a.x - b.x) + abs(a.y - b.y))
        let sp: Double
        switch v.kind.mode { case .road: sp = 6; case .rail: sp = v.kind == .hsr ? 28 : 12; case .air: sp = 45; case .water: sp = v.spec.maxSpeed * 0.8; case .foot: sp = 1.5 }
        return d / sp + (v.kind.mode == .air ? 180 : 20)
    }

    func arriveAt(_ v: Vehicle, _ st: Stop, _ l: Line) {
        st.served += 1
        // people for here get off
        var stay: [Rider] = []
        for r in v.riders {
            if r.to == st.id { alight(r, at: st) } else { stay.append(r) }
        }
        v.riders = stay
        // goods for here are unloaded: into the yard (to change), or into their destination
        for (sid, amt) in v.cargo.sorted(by: { $0.key < $1.key }) {
            // each load finds its own leg: the one of this line that ends here (a shipment may be split over several loads)
            guard let sh = net.shipments.first(where: { $0.id == sid }), let k = sh.legs.firstIndex(where: { $0.line == l.id && $0.to == st.id }) else { continue }
            v.cargo[sid] = nil
            sh.leg = max(sh.leg, k + 1)
            record([(sh.key, amt)], from: "vehicle \(v.id)", to: "yard \(st.name)", note: "unload shipment \(sid)")
            if k + 1 >= sh.legs.count {
                deliver(sh, amt, at: st)
            } else {
                st.yard[sid, default: 0] += amt
                sh.state = .waiting
            }
            l.carried += amt
        }
        if v.playerAboard && !v.playerDriving { vehicleEvents.append(VehicleEvent(t: world.time, vehicle: v.id, what: "arrived at " + st.name)) }
    }

    func exchange(_ v: Vehicle, _ st: Stop, _ l: Line) {
        guard l.suspended == nil else { return }
        let ahead = upcoming(l, from: v.task.at, dir: v.task.at == 0 ? 1 : (v.task.at == l.stops.count - 1 ? -1 : v.task.dir))
        // people waiting for a stop further along this line, in this direction, board as seats allow
        if !l.freight {
            var left: [Rider] = []
            for r in st.waiting {
                guard ahead.contains(r.to), v.seatsFree > 0, let dst = net.stop(r.to), borderOpen(riderNation(r), dst.nation) else { left.append(r); continue }
                var rr = r; rr.boarded = world.time
                v.riders.append(rr)
                l.riders += 1
                payFare(r, l)
                boarded(r, v)
            }
            st.waiting = left
        }
        // goods whose next leg is this line, to a stop ahead
        for (sid, amt) in st.yard.sorted(by: { $0.key < $1.key }) where amt > 0 {
            guard let sh = net.shipments.first(where: { $0.id == sid }), let k = sh.legs.firstIndex(where: { $0.from == st.id }), sh.legs[k].line == l.id, ahead.contains(sh.legs[k].to) else { continue }
            let room = v.spec.cargo - v.load
            guard room > 1e-9 else { break }
            let take = min(room, amt)
            st.yard[sid] = amt - take
            if st.yard[sid]! <= 1e-9 { st.yard[sid] = nil }
            v.cargo[sid, default: 0] += take
            sh.state = .aboard
            record([(sh.key, take)], from: "yard \(st.name)", to: "vehicle \(v.id)", note: "load shipment \(sid)")
        }
    }

    func upcoming(_ l: Line, from i: Int, dir: Int) -> Set<Int> {
        var out = Set<Int>(); var k = i + dir
        while k >= 0 && k < l.stops.count { out.insert(l.stops[k]); k += dir }
        return out
    }

    func riderNation(_ r: Rider) -> Int {
        switch r.who {
        case .player: return realm.player.nation
        case .agent(let id): return agents[id]?.nation ?? 0
        case .commuter(let id): return net.commuter(id).flatMap { net.district($0.home) }?.nation ?? 0
        }
    }

    func payFare(_ r: Rider, _ l: Line) {
        guard l.fare > 0 else { return }
        // a commuter's fare comes out of their district's purse; the traveller's is not charged (no coin)
        if case .commuter(let id) = r.who, let c = net.commuter(id), let d = net.district(c.home) {
            d.money -= l.fare
            if case .district(let owner) = l.payer, let od = net.district(owner) { od.money += l.fare } else { }
            l.revenue += l.fare
            realm.transport.stats.fares += l.fare
        }
    }

    func boarded(_ r: Rider, _ v: Vehicle) {
        if case .commuter(let id) = r.who, let i = net.commuters.firstIndex(where: { $0.id == id }) { net.commuters[i].state = .riding; net.commuters[i].vehicle = v.id }
    }

    func alight(_ r: Rider, at st: Stop) {
        realm.transport.stats.trips += 1
        switch r.who {
        case .commuter(let id): commuterArrived(id, at: st)
        case .agent(let id): agents[id]?.pos = st.tile.center
        case .player: break
        }
    }

    func lineEvent(_ l: Line, _ what: String) {
        vehicleEvents.append(VehicleEvent(t: world.time, vehicle: -l.id, what: l.name + ": " + what))
    }

    // MARK: trips

    /// The quickest journey by the lines that run: walk to a stop, ride, change, walk on. Lines that are
    /// suspended, or that run into a nation the traveller's is at war with, are not used.
    public func planTrip(from a: TilePos, to b: TilePos, nation: Int = 0, walkReach: Int = 40) -> TripPlan {
        var plan = TripPlan()
        let tr = net
        let walk = 1.4                                              // tiles a second on foot
        let reach2 = walkReach * walkReach
        let lines = tr.lines.filter { $0.suspended == nil && !$0.freight }
        func ok(_ s: Stop) -> Bool { borderOpen(nation, s.nation) }
        // Dijkstra over stops; the start and the end are walking distances
        var best: [Int: Double] = [:], came: [Int: TripLeg] = [:]
        var queue: [(Double, Int)] = []
        for s in tr.stops where s.tile.distance2(a) <= reach2 && ok(s) {
            let t = Double(s.tile.distance2(a)).squareRoot() / walk
            best[s.id] = t; came[s.id] = TripLeg(line: nil, from: nil, to: s.id, seconds: t); queue.append((t, s.id))
        }
        var finish: (Double, Int)?
        while !queue.isEmpty {
            queue.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 > $1.1 }
            let (t, sid) = queue.removeLast()
            guard t <= (best[sid] ?? .infinity) + 1e-9, let s = tr.stop(sid) else { continue }
            if s.tile.distance2(b) <= reach2 {
                let total = t + Double(s.tile.distance2(b)).squareRoot() / walk
                if finish == nil || total < finish!.0 { finish = (total, sid) }
            }
            for l in lines where l.stops.contains(sid) {
                guard let i = l.stops.firstIndex(of: sid) else { continue }
                for dir in [1, -1] {
                    var k = i + dir, ride = 0.0
                    var prev = s
                    while k >= 0 && k < l.stops.count, let n = tr.stop(l.stops[k]) {
                        guard ok(n) else { break }
                        let probe = Vehicle(); probe.kind = l.kind
                        ride += estimate(probe, from: prev, to: n)
                        let nt = t + l.headway / 2 + ride
                        if nt < (best[n.id] ?? .infinity) - 1e-9 {
                            best[n.id] = nt; came[n.id] = TripLeg(line: l.id, from: sid, to: n.id, seconds: l.headway / 2 + ride); queue.append((nt, n.id))
                        }
                        prev = n; k += dir
                    }
                }
            }
            // changing on foot to a stop close by
            for n in tr.stops where n.id != sid && n.tile.distance2(s.tile) <= 100 && ok(n) {
                let nt = t + Double(n.tile.distance2(s.tile)).squareRoot() / walk + 30
                if nt < (best[n.id] ?? .infinity) - 1e-9 { best[n.id] = nt; came[n.id] = TripLeg(line: nil, from: sid, to: n.id, seconds: nt - t); queue.append((nt, n.id)) }
            }
        }
        guard let (total, last) = finish else { plan.reason = tr.stops.isEmpty ? "no stops" : "no line goes there"; return plan }
        var legs: [TripLeg] = [TripLeg(line: nil, from: last, to: nil, seconds: total - best[last]!)]
        var k = last
        while let c = came[k] { legs.append(c); guard let f = c.from else { break }; k = f }
        plan.legs = legs.reversed()
        plan.seconds = total
        plan.ok = true
        return plan
    }

    /// Wait at a stop for a line to a stop further along it (the traveller too: then board by walking in).
    public func waitAt(_ stop: Int, for to: Int, who: RiderRef) -> Bool {
        guard let s = net.stop(stop), let d = net.stop(to), borderOpen(riderNationRef(who), d.nation) else { realm.transport.stats.tripsRefused += 1; return false }
        guard net.lines.contains(where: { $0.stops.contains(stop) && $0.stops.contains(to) && !$0.freight }) else { realm.transport.stats.tripsRefused += 1; return false }
        if s.waiting.contains(where: { $0.who == who }) { return true }
        s.waiting.append(Rider(who: who, from: stop, to: to))
        return true
    }
    func riderNationRef(_ w: RiderRef) -> Int { riderNation(Rider(who: w, from: 0, to: 0)) }

    // MARK: freight

    /// Send goods from one place to another over the freight lines: the whole amount leaves the origin
    /// now (or nothing does) and waits in the first yard. Returns nil when no lines join the two.
    @discardableResult public func ship(_ key: String, _ amount: Double, from: Place, to: Place, note: String = "") -> Shipment? {
        guard amount > 0, let a = firstStop(from), let b = firstStop(to), let legs = freightLegs(from: a, to: b) else { return nil }
        guard let h = placeHolding(from), Goods.take([(key, amount)], from: h) == nil else { return nil }
        let sh = Shipment(); sh.id = realm.transport.take(); sh.key = key; sh.amount = amount; sh.origin = from; sh.dest = to; sh.legs = legs; sh.created = world.time; sh.note = note
        realm.transport.shipments.append(sh)
        a.yard[sh.id, default: 0] += amount
        record([(key, amount)], from: h.name, to: "yard \(a.name)", note: "dispatch shipment \(sh.id)")
        return sh
    }

    func placeHolding(_ p: Place) -> Holding? {
        switch p {
        case .district(let id): return net.district(id)?.holding
        case .town(let id): return settlements[id]?.holding
        case .stop(let id):
            guard let s = net.stop(id) else { return nil }
            return Holding("yard \(s.name)", free: { _ in 0 }, change: { _, _ in })
        }
    }

    /// The yard serving a place: the district's goods yard (or any stop of it), a town's nearest yard.
    func firstStop(_ p: Place) -> Stop? {
        switch p {
        case .stop(let id): return net.stop(id)
        case .district(let id): return net.stops.filter { $0.district == id }.min { ($0.kind == .yard ? 0 : 1, $0.id) < ($1.kind == .yard ? 0 : 1, $1.id) }
        case .town(let id):
            guard let s = settlements[id] else { return nil }
            return net.stops.min { ($0.tile.distance2(s.center), $0.id) < ($1.tile.distance2(s.center), $1.id) }
        }
    }

    /// The fewest-changes chain of freight lines from one stop to another (breadth first; stops of the
    /// same district or within 12 tiles of each other count as one yard for changing).
    func freightLegs(from a: Stop, to b: Stop) -> [Leg]? {
        if a.id == b.id { return [] }
        let lines = net.lines.filter { $0.freight }
        var came: [Int: Leg] = [:]
        var seen: Set<Int> = [a.id]
        var frontier = [a.id]
        func linked(_ s: Stop) -> [Stop] { net.stops.filter { $0.id != s.id && ($0.tile.distance2(s.tile) <= 144 || ($0.district != nil && $0.district == s.district)) } }
        while !frontier.isEmpty {
            var next: [Int] = []
            for sid in frontier {
                guard let s = net.stop(sid) else { continue }
                for l in lines where l.stops.contains(sid) {
                    for t in l.stops where t != sid && !seen.contains(t) {
                        seen.insert(t); came[t] = Leg(line: l.id, from: sid, to: t); next.append(t)
                    }
                }
                // a change of yard on foot (a crane, a short haul): a leg with line 0 handled at once
                for n in linked(s) where !seen.contains(n.id) { seen.insert(n.id); came[n.id] = Leg(line: 0, from: sid, to: n.id); next.append(n.id) }
            }
            if seen.contains(b.id) { break }
            frontier = next.sorted()
        }
        guard seen.contains(b.id) else { return nil }
        var legs: [Leg] = []; var k = b.id
        while let c = came[k] { legs.append(c); k = c.from }
        return legs.reversed()
    }

    /// Goods at the end of their journey: into the district's warehouse or the town's store.
    func deliver(_ sh: Shipment, _ amt: Double, at st: Stop) {
        if let h = placeHolding(sh.dest) {
            h.change(sh.key, amt)
            record([(sh.key, amt)], from: "yard \(st.name)", to: h.name, note: "deliver shipment \(sh.id)")
        }
        sh.delivered += amt
        realm.transport.stats.delivered += amt
        if sh.delivered + 1e-9 >= sh.amount { sh.state = .delivered; sh.done = world.time } else { sh.state = .waiting }
    }

    /// Changes of yard that need no vehicle (adjacent yards): done straight away.
    func transferYards() {
        for sh in net.shipments where sh.state != .delivered && sh.state != .returned {
            for (k, lg) in sh.legs.enumerated() where lg.line == 0 {
                guard let a = net.stop(lg.from), let b = net.stop(lg.to), let amt = a.yard[sh.id], amt > 0 else { continue }
                a.yard[sh.id] = nil
                sh.leg = max(sh.leg, k + 1)
                record([(sh.key, amt)], from: "yard \(a.name)", to: "yard \(b.name)", note: "transfer shipment \(sh.id)")
                if k + 1 >= sh.legs.count { deliver(sh, amt, at: b) } else { b.yard[sh.id, default: 0] += amt }
            }
        }
    }

    /// Where every unit of a shipment is right now (for the books and the tests).
    public func whereIs(_ sh: Shipment) -> (yards: Double, aboard: Double, delivered: Double) {
        let y = net.stops.reduce(0.0) { $0 + ($1.yard[sh.id] ?? 0) }
        let v = net.vehicles.reduce(0.0) { $0 + ($1.cargo[sh.id] ?? 0) }
        return (y, v, sh.delivered)
    }

    // MARK: traffic, for the management view and the far simulation

    /// Vehicles on each road tile (the far simulation slows by it; the management view lists the worst).
    func countTraffic() {
        var c: [Int64: Int] = [:]
        for v in net.vehicles where v.kind.mode == .road { c[MP.chunkKey(v.tile.x, v.tile.y), default: 0] += 1 }
        congestion = c
    }

    /// The busiest road tiles and the slowest lines: where the network is short.
    public func bottlenecks() -> [String] {
        var out: [String] = []
        let jams = congestion.filter { $0.value >= 2 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5)
        for (k, n) in jams { out.append("jam:\(MP.keyCX(k)),\(MP.keyCY(k)):\(n)") }
        for l in net.lines.sorted(by: { $0.id < $1.id }) {
            if let s = l.suspended { out.append("suspended:\(l.name):\(s)") }
            else if l.meanDelay > 120 { out.append("late:\(l.name):\(Int(l.meanDelay))") }
            let waiting = l.stops.compactMap { net.stop($0) }.reduce(0) { $0 + $1.waiting.count }
            let seats = l.vehicles.compactMap { net.vehicle($0) }.reduce(0) { $0 + $1.spec.seats }
            if !l.freight && waiting > seats { out.append("full:\(l.name):\(waiting)>\(seats)") }
            if l.vehicles.isEmpty { out.append("no vehicles:\(l.name)") }
        }
        for v in net.vehicles.sorted(by: { $0.id < $1.id }) { if let h = v.halted { out.append("halted:\(v.name):\(h)") } }
        return out
    }
}
