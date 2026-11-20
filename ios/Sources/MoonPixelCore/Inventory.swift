import Foundation

// The traveller's things. There is one store: the pack the game always had (`realm.player.food / wood /
// stone / goods`). Everything here reads and writes that store and nothing else: equipment holds real
// units taken out of it, the hotbar holds only keys, a dropped stack is a real thing in the world.
// Every operation goes through `Society.inventory(_:)` with a command id; an id is carried out once.

public enum ItemKind: String, Codable, CaseIterable { case food, material, tool, weapon, armour, part, machine }

/// What one kind of thing is. The keys are the pack's own keys: old saves mean the same thing by them
/// (the open world's "weapons", "parts" and "armor" are its own goods, not the regional industry's).
public struct ItemDef: Equatable {
    public let key: String, en: String, zh: String
    public let kind: ItemKind
    public let weight: Double          // per unit
    public let stack: Double           // units per slot (display and capacity both count slots by it)
    public let nutrition: Double       // adult-days per unit (0: not food)
    public let shelfDays: Double       // a share 1/shelfDays of what is carried spoils each day (0: keeps)
    public let equip: String?          // "hand" or "body"
    public let icon: String            // the tile or tool picture the panel shows
}

public enum Items {
    public static let all: [ItemDef] = [
        ItemDef(key: "food", en: "Grain", zh: "粮食", kind: .food, weight: 0.5, stack: 99, nutrition: 1.0, shelfDays: 360, equip: nil, icon: "wheat_3"),
        ItemDef(key: "meal", en: "Meals", zh: "口粮", kind: .food, weight: 0.4, stack: 40, nutrition: 1.5, shelfDays: 2, equip: nil, icon: "kitchen"),
        ItemDef(key: "wood", en: "Wood", zh: "木材", kind: .material, weight: 1, stack: 99, nutrition: 0, shelfDays: 0, equip: nil, icon: "log"),
        ItemDef(key: "stone", en: "Stone", zh: "石料", kind: .material, weight: 1.5, stack: 99, nutrition: 0, shelfDays: 0, equip: nil, icon: "rock"),
        ItemDef(key: "iron_ore", en: "Iron ore", zh: "铁矿", kind: .material, weight: 2, stack: 64, nutrition: 0, shelfDays: 0, equip: nil, icon: "ore_iron"),
        ItemDef(key: "moon_ore", en: "Moon ore", zh: "月矿", kind: .material, weight: 2, stack: 64, nutrition: 0, shelfDays: 0, equip: nil, icon: "ore_moon"),
        ItemDef(key: "gold_ore", en: "Gold ore", zh: "金矿", kind: .material, weight: 2.5, stack: 64, nutrition: 0, shelfDays: 0, equip: nil, icon: "ore_gold"),
        ItemDef(key: "planks", en: "Planks", zh: "木板", kind: .material, weight: 0.6, stack: 99, nutrition: 0, shelfDays: 0, equip: nil, icon: "planks"),
        ItemDef(key: "iron", en: "Iron", zh: "铁锭", kind: .material, weight: 1.5, stack: 64, nutrition: 0, shelfDays: 0, equip: nil, icon: "anvil"),
        ItemDef(key: "moonsteel", en: "Moonsteel", zh: "月钢", kind: .material, weight: 1.2, stack: 64, nutrition: 0, shelfDays: 0, equip: nil, icon: "anvil"),
        ItemDef(key: "fuel", en: "Fuel", zh: "燃油", kind: .material, weight: 0.5, stack: 100, nutrition: 0, shelfDays: 0, equip: nil, icon: "barrel"),
        ItemDef(key: "parts", en: "Parts", zh: "构件", kind: .part, weight: 1, stack: 32, nutrition: 0, shelfDays: 0, equip: nil, icon: "workbench"),
        ItemDef(key: "tools", en: "Tools", zh: "工具", kind: .tool, weight: 2, stack: 8, nutrition: 0, shelfDays: 0, equip: "hand", icon: "pick"),
        ItemDef(key: "weapons", en: "Weapons", zh: "武器", kind: .weapon, weight: 3, stack: 8, nutrition: 0, shelfDays: 0, equip: "hand", icon: "sword"),
        ItemDef(key: "armor", en: "Armour", zh: "防具", kind: .armour, weight: 6, stack: 4, nutrition: 0, shelfDays: 0, equip: "body", icon: "armor"),
        ItemDef(key: "engines", en: "Siege engines", zh: "攻城器械", kind: .machine, weight: 40, stack: 1, nutrition: 0, shelfDays: 0, equip: nil, icon: "ballista"),
    ]
    public static let byKey: [String: ItemDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    /// Something the pack holds that this table does not know (a key from a content pack, say): it is kept
    /// as it is, weighs 1 a unit and is never merged into anything else.
    public static func def(_ key: String) -> ItemDef {
        byKey[key] ?? ItemDef(key: key, en: key, zh: key, kind: .material, weight: 1, stack: 64, nutrition: 0, shelfDays: 0, equip: nil, icon: "crate")
    }
}

/// A stack lying in the world. It belongs to nobody until picked up. It lies in a supply box: a block on the
/// tile (`bx`, `by`) of its layer, which anyone sees and which a tap opens; several stacks share a box.
public struct Dropped: Codable, Equatable {
    public var id = 0
    public var key = "", amount = 0.0
    public var x = 0.0, y = 0.0, depth = 0
    public var t = 0.0
    /// The supply box it lies in (nil: dropped before boxes, lying loose).
    public var bx: Int?, by: Int?
}

/// The pack's sizes: each one bigger, each made from the pack's own materials (sewn, framed and reinforced),
/// so that the traveller can carry what large machines are built from (an aircraft carrier takes some 840).
public enum PackTune {
    public static let capacity: [Double] = [2000, 6000, 15000, 40000, 100000, 250000]
    public static let names: [(String, String)] = [("Satchel", "行囊"), ("Pack frame", "背架"), ("Expedition pack", "远征背包"), ("Cargo harness", "货运背具"),
                                                    ("Pocket hold", "随身货舱"), ("Folded warehouse", "折叠仓库")]
    /// What making the next size costs (from the size now).
    public static func cost(from level: Int) -> [String: Double] {
        let n = Double(level + 1)
        var c: [String: Double] = ["wood": 80 * n, "iron": 30 * n]
        if level >= 1 { c["parts"] = 15 * n }
        if level >= 3 { c["moonsteel"] = 10 * n }
        return c
    }
}

public struct InventoryState: Codable, Equatable {
    /// Units in use, taken out of the pack: "hand" -> key, "body" -> key (one unit each).
    public var equipped: [String: String] = [:]
    /// Eight hotbar places, each a key (or empty). A binding is not a copy: it points at what the pack holds.
    public var hotbar: [String] = Array(repeating: "", count: 8)
    public var dropped: [Dropped] = []
    public var nextDrop = 1
    /// How hungry the traveller is: 0 fed ... 1 starving.
    public var hunger = 0.2
    /// Commands carried out (most recent last, at most 512) and what each did, so a command sent twice is done once.
    public var done: [Int] = []
    public var results: [Int: InvResult] = [:]
    /// Spoilage is worked out once a day from this time.
    public var spoilT = 0.0
    /// What spoiled in the pack, by key (kept so the totals add up).
    public var spoiled: [String: Double] = [:]
    public init() {}
}

public enum InvOp: Codable, Equatable {
    case eat(String, Double)
    case equip(String)
    case unequip(String)                           // slot
    case bind(Int, String)                         // hotbar place, key ("" clears)
    case drop(String, Double)                      // at the body's place
    case pickUp(Int)                               // dropped id
    case openBox(Int, Int, depth: Int)             // everything in the supply box on that tile
    case deposit(String, Double, town: Int)        // pack -> town store
    case withdraw(String, Double, town: Int)       // town store -> pack
}

public struct InvResult: Codable, Equatable {
    public var ok = false
    public var amount = 0.0                        // how much actually moved, was eaten, ...
    public var reason = ""                         // why not (or why only part): "duplicate" never appears; a duplicate gets the first result back
    public init() {}
}

public struct InventoryConfig: Codable, Equatable {
    public var capacity = 400.0                    // weight the traveller can carry
    public var reach = 40.0                        // simulation units: how far one can pick up, drop or reach a store
    public var hungerPerDay = 0.9                  // a day without food
    public var starveHP = 4.0                      // hp an hour when starving
    public var playerNeed = 1.0                    // adult-days of food a day
    public init() {}
}

extension Society {
    public var inv: InventoryState { get { realm.player.invBox ?? InventoryState() } set { realm.player.invBox = newValue } }
    public var invCfg: InventoryConfig {
        var c = InventoryConfig()
        c.capacity = PackTune.capacity[max(0, min(PackTune.capacity.count - 1, realm.player.packLevel ?? 0))]
        return c
    }

    /// Make the pack the next size bigger, from what it holds. Returns why not, or nil when done.
    @discardableResult public func upgradePack() -> String? {
        let lv = realm.player.packLevel ?? 0
        guard lv + 1 < PackTune.capacity.count else { return "largest" }
        let cost = PackTune.cost(from: lv)
        for (k, v) in cost where carried(k) + 1e-9 < v { return "need " + k }
        for (k, v) in cost { carry(k, -v) }
        realm.player.packLevel = lv + 1
        return nil
    }

    /// Where a supply box goes when something is dropped: an existing box beside the traveller (on their
    /// layer), else the first free tile round them (nothing standing there, a floor under it, not water).
    func boxTile(for b: Body, _ st: InventoryState) -> TilePos? {
        let t = b.pos.tile
        let ring = [TilePos(1, 0), TilePos(-1, 0), TilePos(0, 1), TilePos(0, -1), TilePos(1, 1), TilePos(-1, 1), TilePos(1, -1), TilePos(-1, -1),
                    TilePos(2, 0), TilePos(-2, 0), TilePos(0, 2), TilePos(0, -2)]
        for d in ring.prefix(8) {
            let q = t + d
            if st.dropped.contains(where: { $0.depth == b.depth && $0.bx == q.x && $0.by == q.y }) { return q }
        }
        let w = layer(b.depth), g = WorldGround(self)
        for d in ring {
            let q = t + d
            if w.tile(2, q.x, q.y) == 0 && g.floor(b.depth, q) != nil && !content.water[Int(w.tile(0, q.x, q.y))] && !g.blocked(b.depth, q) { return q }
        }
        return nil
    }

    /// The stacks in the supply box on a tile of a layer.
    public func boxContents(_ t: TilePos, depth: Int) -> [Dropped] { inv.dropped.filter { $0.depth == depth && $0.bx == t.x && $0.by == t.y } }

    /// Everything the pack holds, by key (the one store).
    public func packContents() -> [String: Double] {
        var out: [String: Double] = [:]
        if realm.player.food > 0 { out["food"] = realm.player.food }
        if realm.player.wood > 0 { out["wood"] = realm.player.wood }
        if realm.player.stone > 0 { out["stone"] = realm.player.stone }
        for (k, v) in realm.player.goods ?? [:] where v > 0 { out[k] = v }
        return out
    }

    /// Weight carried, equipment included (it is on you).
    public func packWeight() -> Double {
        packContents().reduce(0) { $0 + $1.value * Items.def($1.key).weight } + inv.equipped.values.reduce(0) { $0 + Items.def($1).weight }
    }

    /// The pack as the panel shows it: stacks of at most `stack` units, sorted by kind then name.
    public func packStacks(zh: Bool, filter: ItemKind? = nil, search: String = "") -> [(key: String, name: String, amount: Double, kind: ItemKind)] {
        var out: [(String, String, Double, ItemKind)] = []
        for (k, v) in packContents().sorted(by: { $0.key < $1.key }) {
            let d = Items.def(k)
            if let f = filter, d.kind != f { continue }
            let name = zh ? d.zh : d.en
            if !search.isEmpty && !name.localizedCaseInsensitiveContains(search) && !k.contains(search) { continue }
            var left = v
            while left > 1e-9 { let n = min(left, d.stack); out.append((k, name, n, d.kind)); left -= n }
        }
        let order = ItemKind.allCases
        return out.sorted { a, b in a.3 != b.3 ? order.firstIndex(of: a.3)! < order.firstIndex(of: b.3)! : (a.1 != b.1 ? a.1 < b.1 : a.2 > b.2) }
            .map { (key: $0.0, name: $0.1, amount: $0.2, kind: $0.3) }
    }

    /// How many units of this could still be carried.
    public func roomFor(_ key: String) -> Double {
        let w = Items.def(key).weight
        return w <= 0 ? .infinity : max(0, (invCfg.capacity - packWeight()) / w)
    }

    /// Everything the traveller has anywhere: pack, equipment and their stacks lying in the world (for checks).
    public func ownedTotal() -> [String: Double] {
        var out = packContents()
        for k in inv.equipped.values { out[k, default: 0] += 1 }
        for d in inv.dropped { out[d.key, default: 0] += d.amount }
        return out
    }

    // MARK: commands

    /// Carry out an inventory command once. The same id again returns the first result and changes nothing.
    @discardableResult public func inventory(_ id: Int, _ op: InvOp, at body: Body? = nil) -> InvResult {
        var st = inv
        if let r = st.results[id] { return r }
        let r = runInv(op, &st, body: body ?? realm.player.body ?? Body())
        st.done.append(id); st.results[id] = r
        while st.done.count > 512 { st.results[st.done.removeFirst()] = nil }
        inv = st
        return r
    }

    private func runInv(_ op: InvOp, _ st: inout InventoryState, body b: Body) -> InvResult {
        var r = InvResult()
        let cfg = invCfg
        switch op {
        case .eat(let key, let want):
            let d = Items.def(key)
            guard d.nutrition > 0 else { r.reason = "not food"; return r }
            // as much as the hunger takes, no more (a full traveller eats nothing)
            let room = st.hunger * cfg.playerNeed / d.nutrition
            let n = min(want, carried(key), room)
            guard n > 1e-9 else { r.reason = carried(key) <= 0 ? "none" : "full"; return r }
            carry(key, -n)
            st.hunger = max(0, st.hunger - n * d.nutrition / cfg.playerNeed)
            r.ok = true; r.amount = n
            if n < want { r.reason = carried(key) <= 0 ? "none" : "full" }
        case .equip(let key):
            let d = Items.def(key)
            guard let slot = d.equip else { r.reason = "cannot equip"; return r }
            guard carried(key) >= 1 else { r.reason = "none"; return r }
            if let old = st.equipped[slot] { carry(old, 1) }          // the old one goes back into the pack
            carry(key, -1)
            st.equipped[slot] = key
            r.ok = true; r.amount = 1
        case .unequip(let slot):
            guard let key = st.equipped[slot] else { r.reason = "empty"; return r }
            // a unit worn weighs the same in the pack: taking it off never needs room
            carry(key, 1); st.equipped[slot] = nil
            r.ok = true; r.amount = 1
        case .bind(let i, let key):
            guard i >= 0, i < st.hotbar.count else { r.reason = "no such place"; return r }
            st.hotbar[i] = key
            r.ok = true
        case .drop(let key, let want):
            let n = min(want, carried(key))
            guard n > 1e-9 else { r.reason = "none"; return r }
            // only where something can lie: a floor at the layer the body is on, nothing solid there
            let g = WorldGround(self), t = b.pos.tile
            guard b.platform == nil, g.floor(b.depth, t) != nil, !g.blocked(b.depth, t) else { r.reason = "nowhere to put it"; return r }
            carry(key, -n)
            var d = Dropped(id: st.nextDrop, key: key, amount: n, x: b.x, y: b.y, depth: b.depth, t: world.time)
            // into a supply box: a block beside the traveller, which a tap opens (the same kind joins its stack)
            if let q = boxTile(for: b, st) {
                d.bx = q.x; d.by = q.y; d.x = q.center.x; d.y = q.center.y
                layer(b.depth).setTile(2, q.x, q.y, content.tid("supply_box"))
                if let j = st.dropped.firstIndex(where: { $0.depth == b.depth && $0.bx == q.x && $0.by == q.y && $0.key == key }) {
                    st.dropped[j].amount += n; st.dropped[j].t = world.time
                    r.ok = true; r.amount = n
                    return r
                }
            }
            st.dropped.append(d)
            st.nextDrop += 1
            r.ok = true; r.amount = n
        case .pickUp(let did):
            guard let i = st.dropped.firstIndex(where: { $0.id == did }) else { r.reason = "gone"; return r }
            let d = st.dropped[i]
            guard d.depth == b.depth, Vec2(d.x, d.y).distance(to: b.pos) <= cfg.reach else { r.reason = "out of reach"; return r }
            let n = min(d.amount, roomFor(d.key))
            guard n > 1e-9 else { r.reason = "pack full"; return r }
            carry(d.key, n)
            if d.amount - n > 1e-9 { st.dropped[i].amount -= n; r.reason = "pack full" } else { st.dropped.remove(at: i) }
            clearEmptyBox(d, st)
            r.ok = true; r.amount = n
        case .openBox(let x, let y, let depth):
            let here = st.dropped.filter { $0.depth == depth && $0.bx == x && $0.by == y }
            guard !here.isEmpty else { r.reason = "gone"; return r }
            guard depth == b.depth, TilePos(x, y).center.distance(to: b.pos) <= cfg.reach + 16 else { r.reason = "out of reach"; return r }
            for d in here {
                guard let i = st.dropped.firstIndex(where: { $0.id == d.id }) else { continue }
                let n = min(d.amount, roomFor(d.key))
                guard n > 1e-9 else { r.reason = "pack full"; continue }
                carry(d.key, n); r.amount += n
                if d.amount - n > 1e-9 { st.dropped[i].amount -= n; r.reason = "pack full" } else { st.dropped.remove(at: i) }
            }
            clearEmptyBox(here[0], st)
            r.ok = r.amount > 0
        case .deposit(let key, let want, let town), .withdraw(let key, let want, let town):
            guard let s = settlements[town], !s.abandoned else { r.reason = "no store"; return r }
            guard b.depth == 0 || b.depth >= OpenWorld.storeyBase, s.center.center.distance(to: b.pos) <= Double(Settlement.span) * 8 else { r.reason = "out of reach"; return r }
            if let n = s.nation, n != 0, n != realm.player.nation, case .withdraw = op { r.reason = "not yours"; return r }
            let into: Bool
            if case .deposit = op { into = true } else { into = false }
            let from = into ? pack : s.holding, to = into ? s.holding : pack
            var n = min(want, from.free(key))
            if !into { n = min(n, roomFor(key)) }
            // a town keeps any amount of food, wood and stone; of other goods as much as its chests hold (the same cap its workshops stop at)
            if into && !["food", "wood", "stone"].contains(key) { n = min(n, max(0, storageCap(s) - s.good(key))) }
            guard n > 1e-9 else { r.reason = into ? "store full" : (from.free(key) <= 0 ? "none" : "pack full"); return r }
            Goods.move([(key, n)], from: from, to: to)
            r.ok = true; r.amount = n
            if n < want { r.reason = "only part" }
        }
        return r
    }

    /// A supply box with nothing left in it goes.
    func clearEmptyBox(_ d: Dropped, _ st: InventoryState) {
        guard let x = d.bx, let y = d.by, !st.dropped.contains(where: { $0.depth == d.depth && $0.bx == x && $0.by == y }) else { return }
        let w = layer(d.depth)
        if w.tile(2, x, y) == content.tid("supply_box") { w.setTile(2, x, y, 0) }
    }

    // MARK: hunger and spoilage

    /// The traveller grows hungry with time and is hurt when starving; meals in the pack spoil. Call with
    /// game time (`Society.tick` does it). Nothing here eats by itself: food is eaten only when the player eats.
    public func travellerHourly() {
        var st = inv
        let cfg = invCfg
        st.hunger = min(1, st.hunger + cfg.hungerPerDay * Society.hour / MP.daySeconds)
        if st.hunger >= 1 { var t = Threat(); t.damage = cfg.starveHP; _ = harmPlayer(t) }
        if st.spoilT <= 0 { st.spoilT = world.time }                  // the clock starts when the pack is first looked after
        if world.time - st.spoilT >= MP.daySeconds {
            let days = ((world.time - st.spoilT) / MP.daySeconds).rounded(.down)
            st.spoilT += days * MP.daySeconds
            for (k, v) in packContents() {
                let d = Items.def(k)
                guard d.shelfDays > 0 else { continue }
                // the regional rule: a share 1/shelfDays of what there is spoils each day
                let lost = v * (1 - pow(max(0, 1 - 1 / d.shelfDays), days))
                if lost > 1e-9 { carry(k, -lost); st.spoiled[k, default: 0] += lost }
            }
        }
        inv = st
    }
}
