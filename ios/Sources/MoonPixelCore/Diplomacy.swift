import Foundation

// Envoys, vassals and wars for a place (world warfare task book, sections 3 and 4).
//
// * A nation three times stronger than another (everything it could put in the field) that can reach it
//   sends an envoy before any war. The envoy is answered once, when it arrives: submit (90 %) or refuse
//   (10 %; 20 % for a small nation that holds a key way in, can sit out a siege and faces a first wave too
//   weak to be sure). The answer, its reason and the envoy's id are kept.
// * A nation that submits keeps its name, capital, colour and towns; it pays tribute every day and is its
//   suzerain's vassal. Vassalage never goes round in a circle; it ends when the suzerain passes into history.
// * A refusal starts a war for one place (a port, a pass or a border city): muster, set out, arrive, contest,
//   then taken or withdrawn, then a truce. The fight for the place is settled once, from a snapshot frozen
//   when it starts: an attacker with ten times the defender's effective strength wins for certain; below
//   that it may always have to withdraw. No ground force there: no city taken, whatever is in the air.
// * All numbers are in one table (`WarBalance`), so the balance can be changed without touching who owns
//   what, which machine is which, or the save format.
//
// Only worlds made under the coast rule use envoys (`Civ.envoys`); older worlds keep their old wars.

/// The balance of war, in one place.
public struct WarBalance: Codable, Equatable {
    /// Envoys go out when a nation is this many times stronger than the other.
    public var envoyRatio = 3.0
    /// The chance a nation submits; and the chance it refuses when it holds a key way in, can hold out and
    /// faces a first wave that is not sure to win.
    public var refuse = 0.10, refuseFortified = 0.20
    /// Days of food a city needs to hold out a round of siege (for the higher refusal).
    public var siegeDays = 20.0
    /// Days an envoy takes per region of the way.
    public var envoyDaysPerRegion = 0.5
    /// Share of a vassal's treasury paid to its suzerain each day.
    public var tribute = 0.02
    /// Days of truce after a war for a place: no new war between the two meanwhile.
    public var truceDays = 8.0
    /// Days a war for a place waits for its forces to muster and to arrive before it is given up.
    public var musterDays = 1.0, arriveDays = 12.0
    /// Win chance by effective strength ratio (attacker : defender), straight lines between the nodes.
    public var ratioNodes: [Double] = [0.5, 1, 2, 5, 9, 10]
    public var winNodes: [Double] = [0.20, 0.40, 0.65, 0.85, 0.98, 1.0]
    /// From this ratio on the attacker always wins.
    public var sureRatio = 10.0
    /// Effective strength points of one unit of each kind (whole, supplied, on open ground).
    public var points: [String: Double] = [
        "levy": 40, "infantry": 100, "lancers": 120, "armour": 220, "artillery": 160, "air_defence": 90,
        "drone": 60, "fighter": 180, "escort": 200, "submarine": 160, "carrier": 400, "frame": 600, "shifter": 500, "sky_carrier": 800,
    ]
    /// Kinds that can take and hold a city (ground units with people in them).
    public var occupiers: Set<String> = ["levy", "infantry", "lancers", "armour", "artillery", "frame", "shifter"]
    /// Landing from the sea, and a defender fighting from a pass or walls.
    public var landing = 0.75, fortified = 1.5
    /// What a shipyard's fleet lifts in a round, and what a port takes in (strength points; Logistics.swift).
    public var liftPerYard = 4000.0, intakePerPort = 3000.0
    /// Hours a shifter takes to change form, and how much faster it runs as a vehicle (Mechs.swift).
    public var shiftHours = 0.5, vehicleSpeed = 2.4
    /// Hours between the first troops standing at the place and the assault (the frozen reckoning).
    public var assaultHours = 24.0
    public init() {}

    /// The attacker's chance to win a fight for a place at this ratio of effective strength.
    public func winChance(_ ratio: Double) -> Double {
        guard ratio.isFinite, ratio > 0 else { return ratio.isInfinite ? 1 : 0 }
        if ratio >= sureRatio { return 1 }
        let xs = ratioNodes, ys = winNodes
        if ratio <= xs[0] { return ys[0] * ratio / xs[0] }           // towards nothing at nothing
        for i in 1..<xs.count where ratio <= xs[i] {
            let t = (ratio - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + (ys[i] - ys[i - 1]) * t
        }
        return ys.last!
    }

    /// The chance as shown: a whole percent, but never "100 %" below the sure ratio.
    public func chanceText(_ ratio: Double, zh: Bool) -> String {
        let p = winChance(ratio)
        if ratio < sureRatio && (p * 100).rounded() >= 100 { return zh ? "约 99%，仍可能撤军" : "about 99%, may still withdraw" }
        if ratio >= sureRatio { return zh ? "100%（十倍兵力，必胜）" : "100% (ten to one: certain)" }
        return String(format: "%.0f%%", p * 100)
    }

    /// One side's contribution: count x base points x condition x supply x terrain and training.
    public static func contribution(count: Double, base: Double, condition: Double = 1, supply: Double = 1, terrain: Double = 1) -> Double {
        count * base * condition * supply * terrain
    }
}

/// An envoy on its way, or answered.
public struct CivEnvoy: Codable, Equatable {
    public enum State: Int, Codable { case travelling = 0, submitted, refused, recalled }
    public var id = 0, from = 0, to = 0
    public var sent = 0.0, arrives = 0.0
    public var state = State.travelling
    public var answeredAt: Double?
    /// Why it was sent ("ratio 3.4, the port of X") and why it was answered so.
    public var why = "", answer = ""
    /// Strength of both sides when it was sent.
    public var ratio = 0.0
    /// The place the sender wants (a city id), and what kind of place it is ("port", "pass", "city").
    public var target: Int?, targetKind = ""
}

/// A vassal and its suzerain.
public struct CivVassal: Codable, Equatable {
    public var vassal = 0, suzerain = 0
    public var since = 0.0
    public var paid = 0.0                          // tribute paid in all
    public var envoy: Int?
}

/// The fight for a place, settled once from a frozen snapshot.
public struct CivContest: Codable, Equatable {
    public var at = 0.0
    public var attacker = 0.0, defender = 0.0      // effective strength, unrounded
    public var ratio = 0.0, chance = 0.0, roll = 0.0
    public var won = false
    /// Lines that explain the result: forces, modifiers, what was waiting and could not fight.
    public var lines: [String] = []
}

/// A war for one place.
public struct CivTargetWar: Codable, Equatable {
    public enum Stage: Int, Codable { case muster = 0, depart, arrive, contest, taken, withdrawn, truce }
    public var id = 0, attacker = 0, defender = 0
    public var target = 0                          // city
    public var targetKind = ""
    public var envoy: Int?
    public var stage = Stage.muster
    public var since = 0.0, stageSince = 0.0
    /// Strength the attacker could put in the field, what it has sent and what has arrived (points).
    public var mobilisable = 0.0, sent = 0.0, arrived = 0.0
    /// Forces sent for this place.
    public var forces: [Int] = []
    public var contests: [CivContest] = []
    public var ended: Double?
    /// When the first troops able to take the place stood there: the assault comes `assaultHours` later, so
    /// reinforcements may still change the reckoning before it is frozen.
    public var groundSince: Double?
}

extension Civ {
    // MARK: - strength

    /// A unit's effective strength now (points x condition), before supply and terrain.
    public func unitPoints(_ u: CivUnit) -> Double {
        (cfg.war.points[u.kind] ?? 50) * max(0, min(1, u.hp / max(1, u.def.hp)))
    }

    /// A force's supply (1 well fed ... 0 starving).
    public func supply(_ f: CivForce) -> Double { max(0, 1 - f.crew.hungerIndex) }

    /// Everything a nation could put in the field: its forces and the machines waiting in its depots (points).
    public func mobilisable(_ n: Int) -> Double {
        units.values.filter { $0.nation == n }.reduce(0.0) { $0 + unitPoints($1) }
    }

    /// What a nation defends a city with: its forces on the ground there (fortified in a pass or behind
    /// walls), plus the city's own guard (one point for twenty people).
    public func defence(of c: CivCity) -> (points: Double, lines: [String]) {
        let here = forces.values.filter { $0.region == c.regionKey && $0.nation == c.nation && $0.layer == .ground }.sorted { $0.id < $1.id }
        let fort = (regions[c.regionKey]?.mountain ?? 0) >= cfg.passMountain || c.has("barracks") > 0 ? cfg.war.fortified : 1
        var pts = 0.0, lines: [String] = []
        for f in here {
            let s = supply(f)
            for u in f.units.compactMap({ units[$0] }) {
                let t = cfg.war.occupiers.contains(u.kind) ? fort : 1          // works help only the troops that man them
                pts += WarBalance.contribution(count: 1, base: cfg.war.points[u.kind] ?? 50, condition: u.hp / max(1, u.def.hp), supply: s, terrain: t)
            }
        }
        let guardPts = Double(c.pop) / 20
        pts += guardPts
        let giant = giantDefence(c)
        if giant > 0 { pts += giant; lines.append(String(format: "the giantess stands guard: +%.0f", giant)) }
        lines.append(String(format: "guard %.0f, forces %d, works x%.2f", guardPts, here.count, fort))
        return (pts, lines)
    }

    // MARK: - vassals

    public func suzerain(of n: Int) -> Int? { vassals.first { $0.vassal == n }?.suzerain }
    public func vassalsOf(_ n: Int) -> [Int] { vassals.filter { $0.suzerain == n }.map { $0.vassal }.sorted() }

    /// Would making `v` a vassal of `s` close a circle (s already answers, through its suzerains, to v)?
    public func vassalCycle(_ v: Int, _ s: Int) -> Bool {
        var cur: Int? = s, seen = Set<Int>()
        while let c = cur, !seen.contains(c) {
            if c == v { return true }
            seen.insert(c); cur = suzerain(of: c)
        }
        return false
    }

    @discardableResult public func makeVassal(_ v: Int, of s: Int, envoy: Int? = nil) -> Bool {
        guard v != s, polities[v]?.status == .active, polities[s]?.status == .active, suzerain(of: v) == nil, !vassalCycle(v, s) else { return false }
        vassals.append(CivVassal(vassal: v, suzerain: s, since: time, paid: 0, envoy: envoy))
        let k = touch(v, s)
        relations[k]!.state = 0; relations[k]!.pact = true; relations[k]!.pactSince = time; relations[k]!.value = max(relations[k]!.value, 0.2)
        say("vassal", [polities[v]!.nameEn, polities[v]!.nameZh, polities[s]!.nameEn, polities[s]!.nameZh], [v, s])
        return true
    }

    /// Once a day: tribute flows; a vassal whose suzerain is gone (or became its own vassal's) is free.
    func vassalsDaily() {
        var keep: [CivVassal] = []
        for var v in vassals {
            guard let s = polities[v.suzerain], s.status == .active, polities[v.vassal]?.status == .active else {
                if polities[v.vassal]?.status == .active { say("vassal_free", [polities[v.vassal]!.nameEn, polities[v.vassal]!.nameZh], [v.vassal]) }
                continue
            }
            let pay = max(0, (polities[v.vassal]!.treasury) * cfg.war.tribute)
            polities[v.vassal]!.treasury -= pay; polities[v.suzerain]!.treasury += pay; v.paid += pay
            keep.append(v)
        }
        vassals = keep
    }

    // MARK: - envoys

    /// Days an envoy takes from one nation's capital to another's: by land if there is a way, else over the
    /// sea between their ports (or straight across, counted twice, when neither way is known).
    public func envoyDays(_ a: Int, _ b: Int) -> Double? {
        guard let ha = homeCity(a), let hb = homeCity(b) else { return nil }
        if let w = route(from: ha.regionKey, to: hb.regionKey, size: .person) { return Double(max(1, w.count - 1)) * cfg.war.envoyDaysPerRegion }
        return Double(dist(ha.regionKey, hb.regionKey) * 2) * cfg.war.envoyDaysPerRegion
    }

    /// The place a nation would want from another: a port first, then a pass, then the nearest city.
    public func wantedPlace(by a: Int, from b: Int) -> (city: Int, kind: String)? {
        let theirs = cities(of: b)
        guard !theirs.isEmpty else { return nil }
        let bodies = waterBodies()
        let home = homeCity(a)
        func near(_ c: CivCity) -> Int { home.map { dist($0.regionKey, c.regionKey) } ?? 0 }
        // a port first: the capital's port above all (the most worth having), then the nearest
        let cap = polities[b]?.capital
        let ports = theirs.filter { portSite($0.regionKey, bodies: bodies) != nil }
        if let p = ports.min(by: { ($0.id == cap) != ($1.id == cap) ? $0.id == cap : (near($0) != near($1) ? near($0) < near($1) : $0.id < $1.id) }) { return (p.id, "port") }
        let passes = theirs.filter { (regions[$0.regionKey]?.mountain ?? 0) >= cfg.passMountain }
        if let p = passes.min(by: { near($0) != near($1) ? near($0) < near($1) : $0.id < $1.id }) { return (p.id, "pass") }
        let c = theirs.min { near($0) != near($1) ? near($0) < near($1) : $0.id < $1.id }!
        return (c.id, "city")
    }

    /// Is a pair between envoys, truces or vassalage, so that no envoy may go?
    public func envoyBlocked(_ a: Int, _ b: Int) -> String? {
        if (polities[a]?.underground == true) != (polities[b]?.underground == true) { return "other_world" }
        if polities[a]?.undersea == true || polities[b]?.undersea == true { return "refuses_war" }
        if envoysOut.contains(where: { $0.state == .travelling && Set([$0.from, $0.to]) == Set([a, b]) }) { return "envoy_pending" }
        if let r = relation(a, b) {
            if r.state == 1 { return "at_war" }
            if r.state == 2 && (time - r.since) / MP.daySeconds < cfg.war.truceDays { return "truce" }
        }
        if suzerain(of: a) == b || suzerain(of: b) == a { return "vassal" }
        if targetWars.contains(where: { $0.ended == nil && Set([$0.attacker, $0.defender]) == Set([a, b]) }) { return "at_war" }
        return nil
    }

    /// Send an envoy from `a` to `b` if `a` is strong enough and the way is open. Returns its id.
    @discardableResult public func sendEnvoy(_ a: Int, to b: Int) -> Int? {
        guard a != b, polities[a]?.status == .active, polities[b]?.status == .active, envoyBlocked(a, b) == nil else { return nil }
        let ma = mobilisable(a), mb = max(1, mobilisable(b) + cities(of: b).reduce(0.0) { $0 + Double($1.pop) / 20 })
        guard ma >= cfg.war.envoyRatio * mb, let days = envoyDays(a, b), let want = wantedPlace(by: a, from: b) else { return nil }
        var e = CivEnvoy()
        e.id = nextEnvoy; nextEnvoy += 1
        e.from = a; e.to = b; e.sent = time; e.arrives = time + days * MP.daySeconds
        e.ratio = ma / mb; e.target = want.city; e.targetKind = want.kind
        e.why = String(format: "ratio %.1f; wants %@ (%@)", e.ratio, cities[want.city]?.nameEn ?? "?", want.kind)
        envoysOut.append(e)
        say("envoy_sent", [polities[a]!.nameEn, polities[a]!.nameZh, polities[b]!.nameEn, polities[b]!.nameZh], [a, b])
        return e.id
    }

    /// Once a day, for each nation the computer runs: an envoy to the best candidate, now and then. Candidates
    /// are nations it is three times stronger than and can reach, nearest first, then the ones with a port or
    /// a pass to want.
    func envoyChoices() {
        for id in polities.keys.sorted() {
            guard let p = polities[id], p.status == .active, p.ai, p.fatigue < 0.5, p.treasury > 0 else { continue }
            guard !envoysOut.contains(where: { $0.from == id && $0.state == .travelling }), !targetWars.contains(where: { $0.attacker == id && $0.ended == nil }) else { continue }
            guard rng.unit() < cfg.warChance / yearDays else { continue }
            let ma = mobilisable(id)
            guard ma > 0, let home = homeCity(id) else { continue }
            var best: (score: Int, id: Int)?
            for o in polities.keys.sorted() where o != id {
                guard polities[o]!.status == .active, envoyBlocked(id, o) == nil, suzerain(of: id) != o else { continue }
                let mb = max(1, mobilisable(o) + cities(of: o).reduce(0.0) { $0 + Double($1.pop) / 20 })
                guard ma >= cfg.war.envoyRatio * mb, let theirs = homeCity(o), let want = wantedPlace(by: id, from: o) else { continue }
                let score = dist(home.regionKey, theirs.regionKey) * 10 + (want.kind == "port" ? 0 : want.kind == "pass" ? 3 : 6)
                if best == nil || score < best!.score { best = (score, o) }
            }
            if let b = best { sendEnvoy(id, to: b.id) }
        }
    }

    /// Does `b` hold a key way in that `a` must take: a pass of its basin, or a strait port?
    func holdsKeyWay(_ b: Int) -> Bool {
        traits(of: b).contains { ($0.kind == .basin || $0.kind == .strait) && $0.held > 0 }
    }

    /// Envoys that have arrived are answered, once each.
    func envoysHourly() {
        for i in envoysOut.indices where envoysOut[i].state == .travelling && envoysOut[i].arrives <= time {
            var e = envoysOut[i]
            guard polities[e.from]?.status == .active, polities[e.to]?.status == .active else { e.state = .recalled; e.answeredAt = time; envoysOut[i] = e; continue }
            // a small nation holding a key way in, with food for a siege, against a first wave that is not sure
            let food = cities(of: e.to).map { $0.foodDays }.min() ?? 0
            let firstWave = mobilisable(e.from) * 0.5
            let defend = max(1, mobilisable(e.to) + cities(of: e.to).reduce(0.0) { $0 + Double($1.pop) / 20 })
            let fortified = holdsKeyWay(e.to) && food >= cfg.war.siegeDays && firstWave < cfg.war.sureRatio * defend
            let p = fortified ? cfg.war.refuseFortified : cfg.war.refuse
            let roll = rng.unit()
            e.answeredAt = time
            if roll < p {
                e.state = .refused
                e.answer = fortified ? "refused: holds a key way in and can sit out a siege" : "refused"
                envoysOut[i] = e
                say("envoy_refused", [polities[e.to]!.nameEn, polities[e.to]!.nameZh, polities[e.from]!.nameEn, polities[e.from]!.nameZh], [e.from, e.to])
                if let t = e.target { startTargetWar(e.from, on: e.to, target: t, kind: e.targetKind, envoy: e.id) }
            } else if makeVassal(e.to, of: e.from, envoy: e.id) {
                e.state = .submitted; e.answer = "submitted"
                envoysOut[i] = e
            } else {
                e.state = .recalled; e.answer = "no longer possible"
                envoysOut[i] = e
            }
        }
        // only the latest few answered envoys are kept
        let answered = envoysOut.filter { $0.state != .travelling }
        if answered.count > 40 { let drop = Set(answered.prefix(answered.count - 40).map { $0.id }); envoysOut.removeAll { drop.contains($0.id) } }
    }

    // MARK: - wars for a place

    @discardableResult public func startTargetWar(_ a: Int, on b: Int, target: Int, kind: String, envoy: Int?) -> Int? {
        guard cities[target]?.nation == b else { return nil }
        declare(a, on: b)
        var w = CivTargetWar()
        w.id = nextTargetWar; nextTargetWar += 1
        w.attacker = a; w.defender = b; w.target = target; w.targetKind = kind; w.envoy = envoy
        w.since = time; w.stageSince = time
        w.mobilisable = mobilisable(a)
        targetWars.append(w)
        record("war_for_place", nations: [a, b], region: cities[target]?.regionKey, ids: [w.id, target], note: kind)
        return w.id
    }

    /// The attacker's strength in the fight for the target now, and what is not there to fight.
    public func attack(on w: CivTargetWar) -> (points: Double, ground: Bool, lines: [String]) {
        guard let c = cities[w.target] else { return (0, false, []) }
        var pts = 0.0, ground = false, lines: [String] = [], waiting = 0
        // by sea when no way over land exists at all from any of the attacker's cities (geography, not who stands
        // in the way): a port taken on the far shore means the next place there is reached by land
        let bySea = !cities(of: w.attacker).contains { route(from: $0.regionKey, to: c.regionKey, size: .person) != nil }
        let landing = bySea ? cfg.war.landing : 1
        // by sea, only what the fleet lifts and the port takes in lands this round (counted once, here)
        let round = bySea ? landingRound(w.attacker, at: c) : (lands: Double.infinity, lift: Double.infinity, intake: Double.infinity)
        var landed = 0.0, onShips = 0
        for f in forces.values.sorted(by: { $0.id < $1.id }) where f.nation == w.attacker {
            let s = supply(f)
            let there = f.region == c.regionKey
            for u in f.units.compactMap({ units[$0] }) {
                guard there else { waiting += 1; continue }
                if u.air == .parked && f.layer != .ground { waiting += 1; continue }          // in a hangar: not deployed
                let onGround = f.layer == .ground && cfg.war.occupiers.contains(u.kind) && !shifting(u)     // mid-shift: neither moves nor takes
                let fromSky = u.dropped == true                                                  // dropped from a sky carrier: no quay, no boats
                if onGround {
                    let raw = unitPoints(u)
                    if !fromSky {
                        if landed + raw > round.lands { onShips += 1; continue }                 // still on the ships
                        landed += raw
                    }
                    ground = true
                }
                pts += WarBalance.contribution(count: 1, base: cfg.war.points[u.kind] ?? 50, condition: u.hp / max(1, u.def.hp), supply: s, terrain: onGround && !fromSky ? landing : 1)
            }
        }
        lines.append(String(format: "landing x%.2f, %d units not there yet", landing, waiting))
        if bySea { lines.append(String(format: "by sea: fleet lifts %.0f, the port takes in %.0f, %d units still on the ships", round.lift, round.intake, onShips)) }
        return (pts, ground, lines)
    }

    /// Settle the fight for a place once, from a snapshot frozen now. Later arrivals fight the next one.
    @discardableResult func contest(_ i: Int) -> CivContest? {
        var w = targetWars[i]
        guard let c = cities[w.target] else { return nil }
        let a = attack(on: w), d = defence(of: c)
        guard a.ground else { return nil }          // nobody on the ground to take it: no fight for the city yet
        var k = CivContest()
        k.at = time; k.attacker = a.points; k.defender = d.points
        k.ratio = d.points <= 0 ? .infinity : a.points / d.points
        k.chance = cfg.war.winChance(k.ratio)
        k.roll = rng.unit()
        k.won = k.ratio >= cfg.war.sureRatio || k.roll < k.chance
        k.lines = a.lines + d.lines
        w.contests.append(k)
        w.arrived = a.points
        record(k.won ? "contest_won" : "contest_lost", nations: [w.attacker, w.defender], region: c.regionKey, ids: [w.id],
               note: String(format: "%.1f : %.1f = %.2f, chance %.3f, roll %.3f", k.attacker, k.defender, k.ratio, k.chance, k.roll))
        targetWars[i] = w
        return k
    }

    /// Every hour: the wars for places move on.
    func targetWarsHourly() {
        for i in targetWars.indices where targetWars[i].ended == nil {
            var w = targetWars[i]
            let days = (time - w.stageSince) / MP.daySeconds
            guard let c = cities[w.target], polities[w.attacker]?.status == .active, polities[w.defender]?.status == .active || c.nation == w.attacker else {
                w.stage = .truce; w.ended = time; targetWars[i] = w; continue
            }
            switch w.stage {
            case .muster:
                // everything on the ground near home sets out for the place
                if days >= cfg.war.musterDays {
                    for f in forces.values.sorted(by: { $0.id < $1.id }) where f.nation == w.attacker && f.path.isEmpty && f.layer == .ground && !piloted(f) {
                        if send(f.id, to: c.regionKey, attack: true) { w.forces.append(f.id) }
                    }
                    w.sent = w.forces.compactMap { forces[$0] }.reduce(0.0) { acc, f in acc + f.units.compactMap { units[$0] }.reduce(0.0) { $0 + unitPoints($1) } }
                    w.stage = .depart; w.stageSince = time
                }
            case .depart, .arrive:
                let a = attack(on: w)
                if a.ground {
                    if w.groundSince == nil { w.groundSince = time; w.stage = .arrive; record("arrived", nations: [w.attacker, w.defender], region: c.regionKey, ids: [w.id]) }
                    if time - w.groundSince! >= cfg.war.assaultHours * MP.daySeconds / 24 { w.stage = .contest; w.stageSince = time }
                }
                else if days >= cfg.war.arriveDays { w.stage = .withdrawn; w.stageSince = time }
                else if a.points > 0 { w.stage = .arrive }
            case .contest:
                targetWars[i] = w
                guard let k = contest(i) else { w.stage = .arrive; break }
                w = targetWars[i]
                if c.nation == w.attacker { w.stage = .taken }
                else if k.won {
                    let old = c.nation
                    transfer(c, to: w.attacker)
                    say("captured", [polities[w.attacker]?.nameEn ?? "", polities[w.attacker]?.nameZh ?? "", c.nameEn, c.nameZh, polities[old]?.nameEn ?? "", polities[old]?.nameZh ?? ""], [w.attacker, old], region: c.regionKey)
                    w.stage = .taken
                } else { w.stage = .withdrawn }
                w.stageSince = time
            case .taken, .withdrawn:
                // the war for this place is over: a truce (the land taken is ceded with it); forces go home
                if w.stage == .taken { cede(city: c.id) }
                for fid in w.forces { if let f = forces[fid], f.nation == w.attacker, let h = homeCity(w.attacker) { _ = send(f.id, to: h.regionKey) } }
                makePeace(w.attacker, w.defender)
                w.stage = .truce; w.ended = time
            case .truce: break
            }
            targetWars[i] = w
        }
    }

    /// Is this city the place of a war for a place under way (its fate is settled there, not by occupation)?
    func contested(_ c: CivCity) -> Bool { targetWars.contains { $0.ended == nil && $0.target == c.id } }
}

// MARK: - what the panels say

extension Civ {
    /// A nation's card: land owned and held, people, cities, ports, strength, vassalage, and the one line
    /// about its ground that matters most.
    public func nationFacts(_ n: Int, zh: Bool) -> [String] {
        guard let p = polities[n] else { return [] }
        let bodies = waterBodies()
        let owned = territory(of: n, legal: true).count, held = territory(of: n).count
        let mine = cities(of: n)
        let ports = mine.filter { portSite($0.regionKey, bodies: bodies) != nil }.count
        var out = [zh ? "土地 \(owned) 区（实控 \(held)）· 人口 \(p.pop + p.detailPop) · 城市 \(mine.count) · 港口 \(ports) · 可动员 \(Int(mobilisable(n))) 战力点"
                      : "land \(owned) regions (\(held) held) · \(p.pop + p.detailPop) people · \(mine.count) cities · \(ports) ports · \(Int(mobilisable(n))) strength points"]
        if let s = suzerain(of: n), let q = polities[s] { out.append(zh ? "附属于 \(q.nameZh)，累计纳贡 \(Int(vassals.first { $0.vassal == n }?.paid ?? 0))" : "vassal of \(q.nameEn), \(Int(vassals.first { $0.vassal == n }?.paid ?? 0)) paid in tribute") }
        let vs = vassalsOf(n).compactMap { polities[$0]?.name(zh: zh) }
        if !vs.isEmpty { out.append((zh ? "附属国：" : "vassals: ") + vs.joined(separator: zh ? "、" : ", ")) }
        if let g = groundLine(of: n, zh: zh) { out.append(g) }
        if seaAccess(n, bodies: bodies) == nil && !mine.isEmpty { out.append(zh ? "内陆国：没有可抵达的出海口" : "landlocked: no port it can reach") }
        return out
    }

    /// An envoy in a line: who sent it, when it arrives (or arrived), why, and how it was answered.
    public func envoyLine(_ e: CivEnvoy, zh: Bool) -> String {
        let a = polities[e.from]?.name(zh: zh) ?? "#\(e.from)", b = polities[e.to]?.name(zh: zh) ?? "#\(e.to)"
        let place = e.target.flatMap { cities[$0]?.name(zh: zh) } ?? "—"
        let d = Int(e.arrives / MP.daySeconds)
        let ratio = String(format: "%.1f", e.ratio)
        switch e.state {
        case .travelling: return zh ? "\(a) 的使者前往 \(b)，第 \(d) 天抵达：兵力 \(ratio) 倍，劝其归附，索要 \(place)" : "\(a)'s envoy to \(b) arrives day \(d): \(ratio) times stronger, asks it to submit and wants \(place)"
        case .submitted: return zh ? "\(b) 接受 \(a) 的劝降，成为附属国（第 \(d) 天）" : "\(b) submitted to \(a)'s envoy (day \(d))"
        case .refused: return zh ? "\(b) 拒绝 \(a) 的劝降（第 \(d) 天）：\(e.answer.contains("key way") ? "握有要道、存粮足以守城" : "不愿归附")，战争目标：\(place)" : "\(b) refused \(a)'s envoy (day \(d)): \(e.answer); war for \(place)"
        case .recalled: return zh ? "\(a) 的使者被召回" : "\(a)'s envoy was recalled"
        }
    }

    /// A war for a place: where it stands (air, transport, ground) and, once fought, the report: the result and
    /// its main reason first, then strength, ratio, chance and what was not there.
    public func warLines(_ w: CivTargetWar, zh: Bool) -> (head: String, details: [String]) {
        let a = polities[w.attacker]?.name(zh: zh) ?? "#\(w.attacker)", d = polities[w.defender]?.name(zh: zh) ?? "#\(w.defender)"
        let place = cities[w.target]?.name(zh: zh) ?? "—"
        let stages = zh ? ["集结", "出发", "抵达", "争夺", "占领", "撤军", "停战"] : ["mustering", "setting out", "arriving", "contest", "taken", "withdrawn", "truce"]
        let att = attack(on: w)
        let airUp = forces.values.filter { $0.nation == w.attacker && ($0.layer == .highAir || $0.layer == .lowAir) && $0.region == cities[w.target]?.regionKey }.count
        var details = [zh ? String(format: "空域：%d 支飞行编队在目标上空 · 运输：可动员 %.0f，已派出 %.0f，已到场 %.0f 战力点 · 地面：%@",
                                   airUp, w.mobilisable, w.sent, att.points, att.ground ? "已有可占领部队" : "无可占领部队到场")
                          : String(format: "air: %d flights over the place · transport: %.0f could go, %.0f sent, %.0f there (points) · ground: %@",
                                   airUp, w.mobilisable, w.sent, att.points, att.ground ? "troops able to take it" : "nobody able to take it")]
        guard let k = w.contests.last else {
            return ((zh ? "\(a) 争夺 \(d) 的 \(place)：\(stages[w.stage.rawValue])" : "\(a) fights \(d) for \(place): \(stages[w.stage.rawValue])"), details)
        }
        let r = k.ratio.isFinite ? String(format: "%.1f∶1", k.ratio) : "∞"
        let held = !k.won
        let head: String
        if zh { head = held ? "\(place) 守住。攻方有效战力仅为守方的 \(r)，\(a) 撤军。" : "\(place) 失守。\(a) 以 \(r) 的有效战力夺取。" }
        else { head = held ? "\(place) held. The attackers had only \(r) of the defence; \(a) withdrew." : "\(place) fell. \(a) took it at \(r)." }
        details.append(zh ? String(format: "攻方 %.1f，守方 %.1f，比值 %@，胜率 %@，掷点 %.3f", k.attacker, k.defender, r, cfg.war.chanceText(k.ratio, zh: true), k.roll)
                          : String(format: "attack %.1f, defence %.1f, ratio %@, chance %@, roll %.3f", k.attacker, k.defender, r, cfg.war.chanceText(k.ratio, zh: false), k.roll))
        details += k.lines
        return (head, details)
    }
}
