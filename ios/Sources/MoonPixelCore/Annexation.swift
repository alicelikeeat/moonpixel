import Foundation

// Alliances, annexation, and the nations' great landmarks.
//
// The leading power of an alliance (its suzerain: the stronger of the two) keeps faith while it is one power
// among others. Once it holds more than half the world's strength it may turn on its ally to swallow it, but
// not surely: the likelier the larger it looms over the ally and the ally's friends. A war of annexation it
// finds going badly (its people tiring, its armies thinned, a town of its own lost) it calls off: it makes a
// truce and takes the ally back into the alliance.
//
// Allies help a fallen ally to rise again: a nation driven from its land is given settlers, food and timber by
// its ally and founds a new town long before it would alone. Every nation that rises again raises a great
// landmark of its own at once.
//
// Landmarks belong to a nation: whoever holds the town a landmark stands by holds the landmark. A nation that
// takes a landmark another raised fights with twice its strength, so landmark towns keep the largest garrisons.

/// A war of annexation under way: who is swallowing whom, since when, and how they stood when it began.
public struct Annexation: Codable, Equatable {
    public var suzerain = 0, target = 0
    public var since = 0.0
    public var ratio = 0.0          // suzerain's strength over the target side's, at the start
    public var towns = 0            // towns the suzerain held at the start
    public init() {}
}

extension Society {
    // MARK: alliance and annexation

    /// The pacts as they stand (both nations still on their land or not).
    func pacts() -> [(a: Int, b: Int)] { realm.relations.filter { $0.pact }.map { ($0.a, $0.b) } }

    /// The strength of a nation with its allies (the target side of an annexation).
    func sideStrength(_ n: Int, without: Int) -> Double {
        var p = realm.nation(n).map { power($0) } ?? 0
        for c in allies(of: n) where c != without { p += realm.nation(c).map { power($0) } ?? 0 }
        return max(1, p)
    }

    /// Once a day: a suzerain over half the world may set out to annex its ally; an annexation going badly is
    /// called off and the alliance made again.
    func annexationDay() {
        var list = realm.annexations ?? []
        // wars of annexation going badly are called off
        for (i, ax) in list.enumerated().reversed() {
            guard let r = realm.ri(ax.suzerain, ax.target), let sz = realm.nation(ax.suzerain), let tg = realm.nation(ax.target) else { list.remove(at: i); continue }
            if realm.relations[r].state != 1 || tg.exileSince != nil {
                // over: the ally was swallowed (or peace came by itself)
                list.remove(at: i); continue
            }
            let ratio = power(sz) / sideStrength(ax.target, without: ax.suzerain)
            let tiring = sz.fatigue >= realm.cfg.fatigueSoft * 0.8
            let thinning = ratio < ax.ratio * 0.6 || ratio < 1.3
            let losing = towns(of: ax.suzerain).count < ax.towns
            if tiring || thinning || losing {
                setState(r, 2)
                realm.relations[r].pact = true
                realm.relations[r].value = min(1, max(0.2, realm.relations[r].value + 0.4))
                for lg in realm.legions where lg.nation == ax.suzerain && (lg.state == 1 || lg.state == 2 || lg.state == 4) { sendHome(lg) }
                emit("annex_off", [sz.name(zh: zh), tg.name(zh: zh)], towns(of: ax.target).first?.center.center ?? .zero,
                     nations: [ax.suzerain, ax.target], cause: tiring ? "tired" : (losing ? "lost a town" : "outmatched"), result: "allied again")
                list.remove(at: i)
            }
        }
        // a suzerain over half the world may turn on its ally
        for p in pacts() {
            guard let na = realm.nation(p.a), let nb = realm.nation(p.b), na.exileSince == nil, nb.exileSince == nil else { continue }
            let (sz, ally) = power(na) >= power(nb) ? (na, nb) : (nb, na)
            guard powerShare(sz.id) > realm.cfg.dominance, !list.contains(where: { $0.suzerain == sz.id }) else { continue }
            let ratio = power(sz) / sideStrength(ally.id, without: sz.id)
            // the larger it looms, the likelier: nothing at 1.5 times the ally's side, at most one in five a day
            let chance = min(0.2, max(0, (ratio - 1.5) / 3) * 0.2)
            guard chance > 0, realm.rng.unit() < chance, let r = realm.ri(sz.id, ally.id), realm.relations[r].state == 0 else { continue }
            realm.relations[r].pact = false
            realm.relations[r].value = max(-1, realm.relations[r].value - 0.5)
            var ax = Annexation()
            ax.suzerain = sz.id; ax.target = ally.id; ax.since = world.time; ax.ratio = ratio; ax.towns = towns(of: sz.id).count
            list.append(ax)
            emit("annex", [sz.name(zh: zh), ally.name(zh: zh)], towns(of: ally.id).first?.center.center ?? .zero,
                 nations: [sz.id, ally.id], cause: String(format: "share %.2f, %.1fx", powerShare(sz.id), ratio), result: "war")
            declare(sz.id, on: ally.id)
        }
        realm.annexations = list.isEmpty ? nil : list
    }

    // MARK: allies help a fallen ally rise again

    /// A landless nation with an ally on its land: the ally gives settlers (who take up the fallen nation's
    /// banner), food and timber from its largest town, and they found a new town. Returns whether it happened.
    @discardableResult func allyRebuild(_ id: Int) -> Bool {
        guard let n = realm.nation(id), n.exileSince != nil else { return false }
        let friends = realm.relations.filter { ($0.a == id || $0.b == id) && ($0.pact || $0.value >= realm.cfg.coopTrust) && $0.state == 0 }
            .map { $0.a == id ? $0.b : $0.a }.filter { realm.nation($0)?.exileSince == nil }.sorted()
        for c in friends {
            guard let src = towns(of: c).filter({ $0.members.count >= 12 }).max(by: { $0.members.count < $1.members.count }) else { continue }
            let site = world.findSite(from: src.center, minR: 70, maxR: 170, salt: 6100 + nextSID * 13, avoid: settlements.values.map { $0.center }, avoidDist: 60)
            if site.isNone { continue }
            let now = world.time
            let group = src.members.compactMap { agents[$0] }.filter { $0.legion == nil && !$0.travelling && $0.age(now) >= 16 }
                .sorted { ($0.nation == id ? 0 : 1, $0.id) < ($1.nation == id ? 0 : 1, $1.id) }.prefix(min(14, max(4, src.members.count / 4)))
            guard group.count >= 4 else { continue }
            let ns = foundSettlement(site)
            ns.nation = id
            let food = min(src.food * 0.4, Double(group.count) * 12), wood = min(src.wood * 0.4, 50)
            src.food -= food; src.wood -= wood
            ns.food = food; ns.wood = wood; ns.stone = min(src.stone * 0.3, 30); src.stone -= ns.stone
            for a in group {
                move(a, to: ns)
                a.nation = id
                a.travelling = true
                a.travelTo = world.findFree(near: site + TilePos(realm.rng.int(-4, 4), realm.rng.int(2, 5)), maxR: 6).center
            }
            if let k = realm.ni(id) { realm.nations[k].exileSince = nil; realm.nations[k].leader = pickLeader(id) }
            stats.founded += 1
            emit("ally_rebuild", [realm.nation(c)?.name(zh: zh) ?? "", n.name(zh: zh), ns.name(zh: zh)], site.center, nations: [c, id], cause: "alliance", result: "revived")
            grantLandmark(id, at: ns)
            return true
        }
        return false
    }

    /// A nation risen again raises a great landmark by its new town at once (a landmark of its own design).
    func grantLandmark(_ nation: Int, at s: Settlement) {
        let kind: MonumentKind = realm.rng.unit() < 0.6 ? .fusion : MonumentKind.classic[realm.rng.int(0, MonumentKind.classic.count - 1)]
        if let m = raiseMonument(kind, near: s, nation: nation, seed: Int(realm.rng.int(1, 1_000_000))) {
            emit("monument", [realm.nation(nation)?.name(zh: zh) ?? "", s.name(zh: zh), m.title(zh: zh)], m.center.center)
        }
    }

    // MARK: landmarks belong to nations

    /// Once a day: a landmark belongs to whoever holds its town; one taken from another nation is announced.
    func landmarkOwnersDay() {
        guard var ms = realm.monuments, !ms.isEmpty else { return }
        var changed = false
        for i in ms.indices {
            guard let s = settlements[ms[i].town], !s.abandoned, let owner = s.nation, owner != ms[i].nation else { continue }
            let was = ms[i].nation
            if ms[i].builder == nil { ms[i].builder = was }
            ms[i].nation = owner
            changed = true
            emit("monument_taken", [realm.nation(owner)?.name(zh: zh) ?? "", realm.nation(was)?.name(zh: zh) ?? "", ms[i].title(zh: zh)], ms[i].center.center,
                 nations: [owner, was], cause: "town taken", result: "landmark held")
        }
        if changed { realm.monuments = ms }
    }

    /// Landmarks a nation holds that another nation raised.
    public func capturedLandmarks(_ nation: Int) -> [Monument] {
        (realm.monuments ?? []).filter { $0.nation == nation && ($0.builder ?? $0.nation) != nation }
    }

    /// A nation that holds a landmark taken from another fights with twice its strength.
    public func landmarkBonus(_ nation: Int) -> Double { capturedLandmarks(nation).isEmpty ? 1 : 2 }

    /// Towns with a landmark keep the largest garrisons: twice the soldiers, and four more.
    func landmarkTown(_ s: Settlement) -> Bool { (realm.monuments ?? []).contains { $0.town == s.id } }
}
