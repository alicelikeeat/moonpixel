import Foundation

// MARK: - the one record of who fell

/// Every soldier killed in battle is written here, once, when they die. War panels, chronicles and
/// tests read this, never a count kept by the renderer, so what the camera sees cannot change it.
public struct CasualtyLedger: Codable, Equatable {
    public struct Battle: Codable, Equatable {
        public var key: String
        public var nations: [Int]
        public var losses: [String: Int] = [:]     // nation id -> fallen
        public var first = 0.0, last = 0.0
        public var x = 0.0, y = 0.0
        public var total: Int { losses.values.reduce(0, +) }
    }
    public var fallen: [String: Int] = [:]          // nation id -> fallen in all battles
    public var total = 0
    public var battles: [Battle] = []                // most recent last, bounded
    public static let keep = 48

    public func fallen(_ nation: Int) -> Int { fallen["\(nation)"] ?? 0 }

    mutating func record(nation: Int, battle key: String, sides: [Int], at p: Vec2, time: Double) {
        fallen["\(nation)", default: 0] += 1
        total += 1
        if let i = battles.lastIndex(where: { $0.key == key }) {
            battles[i].losses["\(nation)", default: 0] += 1
            battles[i].last = time
        } else {
            var b = Battle(key: key, nations: sides.sorted())
            b.losses["\(nation)"] = 1; b.first = time; b.last = time; b.x = p.x; b.y = p.y
            battles.append(b)
            if battles.count > CasualtyLedger.keep { battles.removeFirst(battles.count - CasualtyLedger.keep) }
        }
    }
}

extension Realm {
    public var ledger: CasualtyLedger { get { ledgerBox ?? CasualtyLedger() } set { ledgerBox = newValue } }
}

extension Society {
    /// Which battle a death belongs to: a field battle is the pair of armies, a siege is the army and the town.
    func battleKey(_ lg: Legion?, side: Int, near p: Vec2) -> (String, [Int]) {
        if let lg = lg {
            if let f = lg.foe, let o = realm.legion(f) { return ("field:\(min(lg.id, o.id))-\(max(lg.id, o.id))", [lg.nation, o.nation]) }
            if lg.state == 2, let t = settlements[lg.target] { return ("siege:\(t.id):\(lg.id)", [lg.nation, t.nation ?? 0]) }
            if lg.state == 0, let besieger = realm.legions.first(where: { $0.state == 2 && $0.target == lg.home }) {
                return ("siege:\(lg.home):\(besieger.id)", [besieger.nation, lg.nation])
            }
            return ("skirmish:\(lg.id)", [lg.nation])
        }
        return ("skirmish:\(Int(p.x / 512)):\(Int(p.y / 512))", [side])
    }
}

// MARK: - how many soldiers are drawn

/// Draw tiers and decoration, chosen from measured frame times. Decoration (weather, sparks, smoke)
/// is given up before soldiers are; going down is quick, coming back up is slow, so it never flickers.
public struct RenderBudget: Equatable {
    public static let tiers = [50, 100, 200, 400]
    public static let effects = [40, 80, 120]
    /// Levels from cheapest to richest: (soldier tier index, effect level index).
    public static let levels: [(Int, Int)] = [(0, 0), (1, 0), (2, 0), (3, 0), (3, 1), (3, 2)]
    public private(set) var level: Int
    var overT = 0.0, underT = 0.0
    public var slow = 20.0, fast = 14.0          // p95 in ms
    public var downAfter = 1.0, upAfter = 4.0     // seconds

    public init(level: Int = RenderBudget.levels.count - 1) { self.level = level }
    public var soldiers: Int { RenderBudget.tiers[RenderBudget.levels[level].0] }
    public var effectCap: Int { RenderBudget.effects[RenderBudget.levels[level].1] }

    public mutating func update(p95 ms: Double, dt: Double) {
        if ms > slow { overT += dt; underT = 0 } else if ms < fast { underT += dt; overT = 0 } else { overT = 0; underT = 0 }
        if overT >= downAfter && level > 0 { level -= 1; overT = 0 }
        if underT >= upAfter && level < RenderBudget.levels.count - 1 { level += 1; underT = 0 }
    }
    /// A fixed tier (stress scenes, tests).
    public mutating func pin(soldiers n: Int) {
        let t = RenderBudget.tiers.lastIndex { $0 <= n } ?? 0
        level = RenderBudget.levels.firstIndex { $0.0 == t } ?? 0
    }
}

/// How much is drawn of each soldier, by zoom.
public enum BattleDetail: Int { case far = 0, mid, near
    public static func at(zoom: Double) -> BattleDetail { zoom >= 1.6 ? .near : (zoom >= 0.8 ? .mid : .far) }
}

public struct BattleView {
    public struct Mass { public var legion: Int, nation: Int, pos: Vec2, hidden: Int }
    /// Real soldiers to draw, best first.
    public var shown: [Agent] = []
    /// For every army on screen, the soldiers that are not drawn one by one; shown at the army itself.
    public var masses: [Mass] = []
    public var onScreen = 0
}

extension Society {
    /// Pick which real soldiers to draw: those at the front of a fight first, then those nearest the
    /// centre of the view. Soldiers drawn last time keep their place unless someone is clearly more
    /// important (hysteresis), so the picture does not flicker. Everyone else is counted at their army.
    public func battleView(center: Vec2, halfW: Double, halfH: Double, limit: Int, previous: Set<Int> = []) -> BattleView {
        var v = BattleView()
        var cands: [(Double, Agent, Legion)] = []
        var perLegion: [Int: Int] = [:]
        let pad = 120.0
        for lg in realm.legions where lg.state != 0 {
            if abs(lg.pos.x - center.x) > halfW + 400 || abs(lg.pos.y - center.y) > halfH + 400 { continue }
            let foe = lg.foe.flatMap { realm.legion($0) }?.pos ?? (lg.state == 2 ? settlements[lg.target]?.center.center : nil)
            for id in lg.members {
                guard let a = agents[id] else { continue }
                if abs(a.pos.x - center.x) > halfW + pad || abs(a.pos.y - center.y) > halfH + pad { continue }
                perLegion[lg.id, default: 0] += 1
                var score = a.pos.distance(to: center)
                if let f = foe { score += 0.6 * a.pos.distance(to: f) - 400 }      // the front line matters most
                if previous.contains(id) { score -= 90 }                         // keep who was drawn
                cands.append((score, a, lg))
            }
        }
        v.onScreen = cands.count
        cands.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.id < $1.1.id }
        var shownPer: [Int: Int] = [:]
        for c in cands.prefix(limit) { v.shown.append(c.1); shownPer[c.2.id, default: 0] += 1 }
        for lg in realm.legions where perLegion[lg.id] != nil {
            let hidden = perLegion[lg.id]! - (shownPer[lg.id] ?? 0)
            if hidden > 0 { v.masses.append(BattleView.Mass(legion: lg.id, nation: lg.nation, pos: lg.pos, hidden: hidden)) }
        }
        return v
    }

    // MARK: stress scene
    /// Two real armies of `perSide` soldiers each, facing each other in open country between two warring
    /// nations, already in battle. Soldiers are real residents (made adult in their home towns), so the
    /// battle runs through the same rules as any other. Marks the save as cheated.
    @discardableResult public func stageFieldBattle(perSide: Int) -> (Int, Int)? {
        let ids = realm.nations.map { $0.id }.sorted()
        guard ids.count >= 2, let ta = towns(of: ids[0]).first, let tb = towns(of: ids[1]).first,
              let r = realm.ri(ids[0], ids[1]) else { return nil }
        realm.player.cheated = true
        if realm.relations[r].state != 1 { realm.relations[r].state = 1; realm.relations[r].since = world.time }
        let mid = (ta.center.center + tb.center.center) * 0.5
        let field = world.findFree(near: mid.tile, maxR: 40).center
        func army(_ t: Settlement, _ nation: Int, _ at: Vec2) -> Legion {
            let lg = Legion()
            lg.id = realm.nextLegion; realm.nextLegion += 1
            lg.nation = nation; lg.home = t.id; lg.state = 4; lg.pos = at
            lg.morale = 1; lg.food = Double(perSide) * 4; lg.supply = 1
            for i in 0..<perSide {
                let a = newAgent(t, age: 24, female: i % 2 == 1)
                a.nation = nation
                enlist(a, lg)
                a.legion = lg.id
                a.unit = [Unit.infantry, Unit.infantry, Unit.archer, Unit.cavalry][i % 4]
                a.pos = at
            }
            lg.startN = lg.members.count
            realm.legions.append(lg)
            return lg
        }
        let a = army(ta, ids[0], field + Vec2(-90, 0)), b = army(tb, ids[1], field + Vec2(90, 0))
        a.foe = b.id; b.foe = a.id
        invalidateGrid()
        return (a.id, b.id)
    }
}
