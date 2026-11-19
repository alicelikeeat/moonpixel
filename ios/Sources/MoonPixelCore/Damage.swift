import Foundation

// Breaking things (world warfare task book: "全物品与方块破坏").
//
// Every block and object of the world can be hit: it wears down by its material's durability and is removed
// when worn through; what it is made of is gained once, at that moment. Who may break what:
//
// * the player: anything they choose, a hit at a time (letting go stops at once: nothing wears by itself);
// * a builder (the computer, building, paving or gathering): only inside the ground it was given, and never
//   a block of a building, a monument or something the player built: it reports why and goes round;
// * a war (the computer, in a war for a place): only blocks of the buildings marked as targets of that war,
//   and only while the war lasts and the place is still the enemy's; anything else is spared.
//
// Wear is kept per chunk with the chunk (saved and loaded with it); a block removed is simply gone from the
// chunk, so it can never be broken, or give its materials, twice.

public enum Material: String, Codable, CaseIterable {
    case wood, earth, stone, metal, glass, plant, cloth
    /// Hits to wear it through with bare hands (tools and weapons hit harder).
    public var durability: Double {
        switch self {
        case .plant: return 1; case .cloth: return 2; case .glass: return 2; case .earth: return 3
        case .wood: return 4; case .stone: return 8; case .metal: return 12
        }
    }
    /// What breaking it gives (into the pack or the town's stores).
    public var yield: (String, Int)? {
        switch self {
        case .wood: return ("wood", 3); case .stone, .earth: return ("stone", self == .stone ? 3 : 1)
        case .plant: return ("food", 0); case .metal: return ("stone", 2); default: return nil
        }
    }
}

public enum Breaker: Equatable {
    case player
    /// The computer building: it may clear only these tiles.
    case builder(clearing: Set<TilePos>)
    /// The computer at war for a place: attacker, and the target war's id.
    case war(attacker: Int, targetWar: Int)
}

public struct HitResult: Equatable {
    public var layer = -1
    public var material: Material?
    /// What is left of it (1 whole ... 0 gone).
    public var left = 1.0
    public var broke = false
    public var gained: [String: Int] = [:]
    /// Why the hit was refused ("protected", "not_cleared", "not_a_target", "no_war", "nothing").
    public var refused: String?
}

extension Content {
    /// The material a tile is made of (from its key and kind).
    public func material(_ id: UInt8) -> Material? {
        guard id != 0, let t = tile(id) else { return nil }
        let k = t.key
        if water[Int(id)] || k == "lava" { return nil }
        if k.contains("glass") { return .glass }
        if t.layer == 0 {
            if k == "wood_floor" { return .wood }
            if ["stone_floor", "brick_floor", "ruin_floor", "stone", "canyon_rock", "basalt"].contains(k) { return .stone }
            return .earth
        }
        if ["tree", "pine", "deadtree"].contains(t.artKind) { return .wood }
        if ["cactus", "bush", "berrybush", "sapling", "crop", "flower", "tuft", "mushroom", "lily", "leaves", "grass"].contains(t.artKind) { return .plant }
        if k.contains("iron") || k.contains("steel") || ["anvil", "machine", "server", "antenna", "ai_core", "lever", "lever_on", "lamp", "plate", "trap", "wire", "rail", "ballista"].contains(t.artKind) { return .metal }
        if k.contains("wood") || ["fence", "gate", "workbench", "chest", "bed", "table", "chair", "bookshelf", "barrel", "crate", "sign", "stall", "desk", "scarecrow", "mill", "planks", "bridge"].contains(t.artKind) { return .wood }
        if ["tent", "banner"].contains(t.artKind) { return .cloth }
        if ["speck", "dune", "rows", "path"].contains(t.artKind) || k == "mud" || k == "dirt" || k == "sand" { return .earth }
        return .stone
    }
}

extension Chunk {
    /// Wear key: layer and cell.
    @inline(__always) static func wearKey(_ layer: Int, _ i: Int) -> Int { layer << 12 | i }
}

extension Society {
    /// The ground under a tile that cannot be removed (the world's floor): it becomes dirt instead, or stays.
    static let groundAfter = ["grass": "dirt", "forest_floor": "dirt", "dry_grass": "dirt", "marsh_grass": "mud", "tundra": "dirt",
                              "farmland": "dirt", "wood_floor": "dirt", "stone_floor": "dirt", "brick_floor": "dirt", "ruin_floor": "dirt"]

    /// Is this tile part of something that must not be broken by the computer in peace: a town's or a district's
    /// building, a monument, or something the player built?
    public func protectedTile(_ t: TilePos) -> Bool {
        for s in settlements.values where !s.abandoned {
            for b in s.buildings where t.x >= b.x && t.x < b.x + b.w && t.y >= b.y && t.y < b.y + b.h { return true }
        }
        for d in net.districts { for b in d.buildings where t.x >= b.x && t.x < b.x + b.w && t.y >= b.y && t.y < b.y + b.d { return true } }
        for m in realm.monuments ?? [] where t.x >= m.x && t.x < m.x + m.w && t.y >= m.y && t.y < m.y + m.d { return true }
        // anything built (walls, doors, floors, furniture: the player's work as much as the towns')
        for l in [1, 2] { if let d = Content.shared.tile(world.tile(l, t.x, t.y)), d.built { return true } }
        return false
    }

    /// The tiles of the buildings a war for a place may strike: every block of every building of the target
    /// town (the mark covers each block of a building, not a corner of it).
    public func warTargets(_ w: CivTargetWar) -> Set<TilePos> {
        guard let city = civ.cities[w.target], let sid = city.detail, let s = settlements[sid] else { return [] }
        var out = Set<TilePos>()
        for b in s.buildings where b.done { for y in b.y..<(b.y + b.h) { for x in b.x..<(b.x + b.w) { out.insert(TilePos(x, y)) } } }
        return out
    }

    /// Hit the tile: the topmost thing on it (an object, then a way or floor, then a plant on the ground, then
    /// the ground itself). `power` is in bare-hand hits. Returns what happened; nothing changes when refused.
    @discardableResult public func hitTile(_ t: TilePos, power: Double = 1, by who: Breaker) -> HitResult {
        var out = HitResult()
        // who may
        switch who {
        case .player: break
        case .builder(let clearing):
            if !clearing.contains(t) { out.refused = "not_cleared"; return out }
            if protectedTile(t) { out.refused = "protected"; return out }
        case .war(let attacker, let wid):
            guard let w = civ.targetWars.first(where: { $0.id == wid }), w.ended == nil, w.attacker == attacker,
                  let city = civ.cities[w.target], city.nation != attacker, civ.atWar(attacker, city.nation) else { out.refused = "no_war"; return out }
            if !warTargets(w).contains(t) { out.refused = "not_a_target"; return out }
        }
        let c = Content.shared
        var layer = -1
        for l in [2, 1, 3, 0] where world.tile(l, t.x, t.y) != 0 && c.material(world.tile(l, t.x, t.y)) != nil { layer = l; break }
        guard layer >= 0 else { out.refused = "nothing"; return out }
        let id = world.tile(layer, t.x, t.y)
        guard let m = c.material(id) else { out.refused = "nothing"; return out }
        if layer == 0, Society.groundAfter[c.tile(id)?.key ?? ""] == nil { out.refused = "nothing"; return out }
        out.layer = layer; out.material = m
        let ch = world.chunk(t.x >> 5, t.y >> 5)
        let wk = Chunk.wearKey(layer, OpenWorld.idx(t.x, t.y))
        let worn = (ch.wear[wk] ?? 0) + Float(power / m.durability)
        if worn < 1 {
            ch.wear[wk] = worn; ch.touch()
            out.left = Double(1 - worn)
            return out
        }
        // worn through: gone, and its material gained once
        ch.wear[wk] = nil
        if layer == 0 { world.setTile(0, t.x, t.y, c.tid(Society.groundAfter[c.tile(id)!.key]!)) }
        else { world.setTile(layer, t.x, t.y, 0) }
        out.left = 0; out.broke = true
        if let (what, n) = m.yield, n > 0 {
            out.gained[what] = n
            switch who {
            case .player:
                let d = Double(n); if what == "wood" { realm.player.wood += d } else if what == "stone" { realm.player.stone += d } else if what == "food" { realm.player.food += d }
            case .builder:
                // into the stores of the town whose ground it is
                if let s = settlements.values.filter({ !$0.abandoned }).min(by: { ($0.center - t).lengthSquared < ($1.center - t).lengthSquared }) {
                    if what == "wood" { s.wood += Double(n) } else if what == "stone" { s.stone += Double(n) }
                }
            case .war: out.gained = [:]                      // what a war smashes is lost
            }
        }
        return out
    }
}
