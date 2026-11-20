import Foundation

// Nobody is killed in war: the beaten are taken prisoner.
//
// * A soldier beaten in the field, on the walls or in the square is taken prisoner by the other side: out of
//   the army, disarmed, and marched to the captor's nearest town, where they live and work as prisoners
//   (they keep their own nation). The battle is still recorded (the ledger counts those lost to each side:
//   now prisoners, not the dead), the army still loses heart and the nation still tires of the war.
// * The traveller's blows in war do the same: a soldier who goes down is taken prisoner by the traveller's
//   nation (a traveller without one disarms them and sends them home); a villager is only knocked down.
// * The traveller beaten by soldiers is taken prisoner too: carried to a town of the army's nation, the pack
//   searched (half of it taken), free to walk out.
// * In the nations' wars of the regional layer, the crews of machines that are lost are taken prisoner by the
//   side that beat them and held in its nearest city; a force whose nation has no city left gives itself up.
// * When the two nations are no longer at war, every prisoner goes home (to the town or city they came from,
//   else the nearest of their nation's).

extension Society {
    /// Who takes an army's beaten soldiers: the army it fights in the field, the town it besieges, or the army
    /// besieging the town it defends. Nil when there is nobody (then they go home).
    func captorOf(_ lg: Legion) -> Int? {
        if let f = lg.foe.flatMap({ realm.legion($0) }) { return f.nation }
        if lg.state == 2, let t = settlements[lg.target], let n = t.nation, n != lg.nation { return n }
        if let besieger = realm.legions.first(where: { $0.state == 2 && $0.target == lg.home && $0.nation != lg.nation }) { return besieger.nation }
        return nil
    }

    /// A soldier (or anyone) beaten in war: taken prisoner by `captor`, never killed.
    func takePrisoner(_ a: Agent, by captor: Int?) {
        guard a.alive, let s = settlements[a.sid] else { return }
        let lg = a.legion.flatMap { realm.legion($0) }
        let side = lg?.nation ?? a.nation ?? s.nation ?? 0
        // the battle is recorded as before: those lost to each side (now prisoners)
        let (key, sides) = battleKey(lg, side: side, near: a.pos)
        realm.ledger.record(nation: side, battle: key, sides: sides, at: lg?.pos ?? a.pos, time: world.time)
        realm.intensity += 1
        addFatigue(side, realm.cfg.fatigueDeath / Double(max(20, realm.nation(side)?.pop ?? 20)))
        lg?.members.removeAll { $0 == a.id }
        a.legion = nil; a.unit = nil; a.lent = nil
        abort(a, s)
        a.hp = realm.cfg.civilianHP
        stats.captured = (stats.captured ?? 0) + 1
        // to the captor's nearest town; without a captor (or a town of theirs), home
        let dest = captor.flatMap { c in
            settlements.values.filter { !$0.abandoned && $0.nation == c }
                .min { $0.center.center.distance(to: a.pos) != $1.center.center.distance(to: a.pos) ? $0.center.center.distance(to: a.pos) < $1.center.center.distance(to: a.pos) : $0.id < $1.id }
        }
        if let d = dest, d.id != s.id {
            a.captiveOf = captor; a.captiveHome = a.captiveHome ?? s.id
            move(a, from: s, to: d)
        }
    }

    /// Someone moves to live in another town (homeless there until a bed is found).
    func move(_ a: Agent, from s: Settlement, to d: Settlement) {
        leaveHome(a, s)
        s.members.removeAll { $0 == a.id }
        a.sid = d.id; a.home = -1
        if !d.members.contains(a.id) { d.members.append(a.id) }
        let t = world.findFree(near: d.center + TilePos(realm.rng.int(-4, 4), realm.rng.int(2, 6)), maxR: 8)
        a.pos = t.center; a.prevPos = a.pos; a.path = []; a.task = nil
    }

    /// Prisoners whose two nations are no longer at war go home. Called as the realm steps.
    func releasePrisoners() {
        for a in agents.values.sorted(by: { $0.id < $1.id }) where a.captiveOf != nil {
            guard let captor = a.captiveOf, let own = a.nation else { a.captiveOf = nil; continue }
            if realm.atWar(captor, own) { continue }
            guard let s = settlements[a.sid] else { continue }
            let home = a.captiveHome.flatMap { settlements[$0] }.flatMap { !$0.abandoned && $0.nation == own ? $0 : nil }
                ?? settlements.values.filter { !$0.abandoned && $0.nation == own }.min { $0.center.center.distance(to: a.pos) < $1.center.center.distance(to: a.pos) }
            // half of them stay with the nation that took them, and their family and relatives join them
            if MP.h2(world.seed &+ 3131, a.id, captor) % 2 == 0, s.nation == captor {
                defect(a, to: captor, in: s)
                continue
            }
            a.captiveOf = nil; a.captiveHome = nil
            stats.freed = (stats.freed ?? 0) + 1
            if let h = home, h.id != s.id { move(a, from: s, to: h) }
        }
    }

    /// The prisoners held now: by the nation holding them.
    public func prisoners() -> [Int: Int] {
        var out: [Int: Int] = [:]
        for a in agents.values { if let c = a.captiveOf { out[c, default: 0] += 1 } }
        return out
    }

    /// Where the traveller is carried when taken prisoner (a town of the captor's), and who took them.
    public func takeTravellerCaptor() -> (pos: Vec2, nation: Int)? {
        guard let c = travellerCaptor else { return nil }
        travellerCaptor = nil
        let at = realm.player.body?.pos ?? .zero
        guard let t = settlements.values.filter({ !$0.abandoned && $0.nation == c }).min(by: { $0.center.center.distance(to: at) < $1.center.center.distance(to: at) }) else { return nil }
        return (world.findFree(near: t.center + TilePos(0, 4), maxR: 10).center, c)
    }
}

extension Civ {
    /// The crew of lost machines taken prisoner by `captor`: held in its nearest city (they stay counted as
    /// people; nobody dies). Without a city of the captor's, they go home.
    func takePrisoners(_ gone: CivPeople, of nation: Int, by captor: Int?, near region: Int64) {
        guard gone.total > 0 else { return }
        let held = captor.flatMap { c in
            cities.values.filter { $0.nation == c && $0.detail == nil && $0.under != true && $0.sea != true }
                .min { dist($0.regionKey, region) != dist($1.regionKey, region) ? dist($0.regionKey, region) < dist($1.regionKey, region) : $0.id < $1.id }
        }
        let home = cities.values.filter { $0.nation == nation && $0.detail == nil }
            .min { dist($0.regionKey, region) != dist($1.regionKey, region) ? dist($0.regionKey, region) < dist($1.regionKey, region) : $0.id < $1.id }
        // with nobody to hold them and nowhere of their own: the nearest city of anyone's takes them in
        let anywhere = cities.values.filter { $0.detail == nil && polities[$0.nation]?.status == .active }
            .min { dist($0.regionKey, region) != dist($1.regionKey, region) ? dist($0.regionKey, region) < dist($1.regionKey, region) : $0.id < $1.id }
        guard let into = held ?? home ?? anywhere else {
            totals.deaths["battle", default: 0] += gone.total            // (no city stands anywhere: cannot happen in a living world)
            return
        }
        into.people.add(gone)
        if held != nil, let c = captor {
            var p = prisoners ?? []
            p.append(CivPrisoners(city: into.id, captor: c, nation: nation, count: gone.total))
            prisoners = p
            totals.captured = (totals.captured ?? 0) + gone.total
        }
    }

    /// Prisoners of nations no longer at war go home, to their nation's nearest city.
    func releasePrisoners() {
        guard var list = prisoners, !list.isEmpty else { return }
        list.removeAll { p in
            guard !atWar(p.captor, p.nation) else { return false }
            guard let c = cities[p.city] else { return true }
            let home = cities.values.filter { $0.nation == p.nation && $0.detail == nil }
                .min { dist($0.regionKey, c.regionKey) != dist($1.regionKey, c.regionKey) ? dist($0.regionKey, c.regionKey) < dist($1.regionKey, c.regionKey) : $0.id < $1.id }
            // half stay with the nation that took them; their families (two for each) come from home to join them
            let stay = p.count / 2, go = p.count - stay
            if let h = home {
                let back = c.people.takeAdults(go)
                h.people.add(back)
                totals.freed = (totals.freed ?? 0) + back.total
                let family = h.people.take(min(stay * 2, max(0, h.pop - 1)), from: Array(0..<h.people.n.count))
                c.people.add(family)
                h.ledger.migOut += family.total; c.ledger.migIn += family.total
                totals.defected = (totals.defected ?? 0) + stay + family.total
            } else {
                totals.defected = (totals.defected ?? 0) + p.count
            }
            return true
        }
        prisoners = list
    }

    /// Prisoners held now, by the nation holding them.
    public func prisonersHeld() -> [Int: Int] {
        var out: [Int: Int] = [:]
        for p in prisoners ?? [] { out[p.captor, default: 0] += p.count }
        return out
    }
}

/// Prisoners of a war held in a city of the regional layer.
public struct CivPrisoners: Codable, Equatable {
    public var city: Int, captor: Int, nation: Int, count: Int
}
