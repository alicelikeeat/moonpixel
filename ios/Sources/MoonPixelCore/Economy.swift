import Foundation

/// Gathering -> processing -> manufacture. Towns and the player use the same
/// recipes. Every step moves goods atomically: inputs leave and outputs arrive
/// in one place in the code, so nothing is produced twice or lost on the way.
public struct Recipe {
    public let key: String, station: String, en: String, zh: String
    public let inputs: [(String, Double)], outputs: [(String, Double)]
    public let hours: Double
    public func name(zh z: Bool) -> String { z ? zh : en }

    public static let all: [Recipe] = [
        Recipe(key: "planks", station: "workbench", en: "Saw planks", zh: "锯木板", inputs: [("wood", 2)], outputs: [("planks", 2)], hours: 1),
        Recipe(key: "iron", station: "furnace", en: "Smelt iron", zh: "冶炼铁锭", inputs: [("iron_ore", 2), ("wood", 1)], outputs: [("iron", 1)], hours: 2),
        Recipe(key: "moonsteel", station: "furnace", en: "Smelt moonsteel", zh: "冶炼月钢", inputs: [("moon_ore", 2), ("iron", 1), ("wood", 2)], outputs: [("moonsteel", 1)], hours: 4),
        Recipe(key: "meal", station: "kitchen", en: "Cook meals", zh: "烹制口粮", inputs: [("food", 4), ("wood", 1)], outputs: [("meal", 4)], hours: 1),
        Recipe(key: "parts", station: "workbench", en: "Building parts", zh: "建筑构件", inputs: [("planks", 2), ("stone", 2)], outputs: [("parts", 2)], hours: 2),
        Recipe(key: "tools", station: "workbench", en: "Tools", zh: "工具", inputs: [("planks", 1), ("iron", 1)], outputs: [("tools", 1)], hours: 2),
        Recipe(key: "weapons", station: "anvil", en: "Weapons", zh: "武器", inputs: [("iron", 2), ("planks", 1)], outputs: [("weapons", 1)], hours: 3),
        Recipe(key: "armor", station: "anvil", en: "Armour", zh: "防具", inputs: [("iron", 3)], outputs: [("armor", 1)], hours: 3),
        Recipe(key: "elite", station: "anvil", en: "Moonsteel arms", zh: "月钢兵器", inputs: [("moonsteel", 1), ("iron", 1)], outputs: [("weapons", 3)], hours: 4),
        Recipe(key: "engines", station: "workbench", en: "Siege engine", zh: "攻城器械", inputs: [("planks", 4), ("iron", 2), ("parts", 2)], outputs: [("engines", 1)], hours: 6),
    ]
    public static let byKey: [String: Recipe] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    public static let goods: [(String, String, String)] = [
        ("food", "Food", "粮食"), ("wood", "Wood", "木材"), ("stone", "Stone", "石料"), ("iron_ore", "Iron ore", "铁矿"), ("moon_ore", "Moon ore", "月矿"), ("gold_ore", "Gold ore", "金矿"),
        ("planks", "Planks", "木板"), ("iron", "Iron", "铁锭"), ("moonsteel", "Moonsteel", "月钢"), ("meal", "Meals", "口粮"), ("parts", "Parts", "构件"),
        ("tools", "Tools", "工具"), ("weapons", "Weapons", "武器"), ("armor", "Armour", "防具"), ("engines", "Siege engines", "攻城器械"),
    ]
    public static func goodName(_ key: String, zh: Bool) -> String { goods.first { $0.0 == key }.map { zh ? $0.2 : $0.1 } ?? key }
}

extension Settlement {
    public func good(_ k: String) -> Double {
        switch k {
        case "food": return food
        case "wood": return wood
        case "stone": return stone
        default: return goods?[k] ?? 0
        }
    }

    public func addGood(_ k: String, _ n: Double) {
        switch k {
        case "food": food = max(0, food + n)
        case "wood": wood = max(0, wood + n)
        case "stone": stone = max(0, stone + n)
        default:
            var g = goods ?? [:]
            g[k] = max(0, (g[k] ?? 0) + n)
            if g[k] == 0 { g[k] = nil }
            goods = g
        }
    }
    public func fixture(_ key: String) -> Int { fixtures[key] ?? 0 }
}

extension Society {
    /// Count the things that matter inside a town: stations, beds, stores, walls, gates, landmarks.
    /// Villagers' buildings and the player's free building are counted the same way.
    func surveyTown(_ s: Settlement) {
        let r = realm.cfg.cityRadius
        var f: [String: Int] = [:]
        var beds: [TilePos] = [], gates: [TilePos] = [], walls: [TilePos] = []
        let floors: Set<UInt8> = [content.tid("wood_floor"), content.tid("stone_floor"), content.tid("brick_floor")]
        let bed = content.tid("bed"), built = buildingTiles(s)
        for dy in -r...r { for dx in -r...r {
            let x = s.center.x + dx, y = s.center.y + dy
            let o = world.tile(2, x, y)
            if o == 0 { continue }
            guard let key = content.tile(o)?.key, Society.counted.contains(key) || key.hasPrefix("banner_") else { continue }
            f[key.hasPrefix("banner_") ? "banner" : key, default: 0] += 1
            let t = TilePos(x, y)
            // a bed the player (or anyone) put on a proper floor outside the villagers' own houses is housing too
            if o == bed && floors.contains(world.tile(0, x, y)) && !built.contains(t) { beds.append(t) }
            if key == "gate" || key == "gate_open" { gates.append(t) }
            if (key == "wall_stone" || key == "wall_wood" || key == "wall_brick") && !built.contains(t) { walls.append(t) }
        } }
        s.fixtures = f
        s.freeBeds = beds
        s.gates = gates
        s.walls = walls
        s.cityT = world.time + 60
    }
    static let counted: Set<String> = ["workbench", "furnace", "anvil", "kitchen", "chest", "crate", "bed", "stairs_down", "tower", "ballista", "throne", "market_stall",
                                       "mill", "gate", "gate_open", "wall_stone", "wall_wood", "wall_brick", "barrel", "bookshelf", "machine", "server", "well", "fence"]

    func buildingTiles(_ s: Settlement) -> Set<TilePos> {
        var out = Set<TilePos>()
        for b in s.buildings { for dy in 0..<b.h { for dx in 0..<b.w { out.insert(TilePos(b.x + dx, b.y + dy)) } } }
        return out
    }

    public func storageCap(_ s: Settlement) -> Double { realm.cfg.storeBase + realm.cfg.storePerChest * Double(s.fixture("chest") + s.fixture("crate")) }

    /// How much of a good a town wants to hold before its stations turn to something else.
    func demand(_ s: Settlement, _ good: String) -> Double {
        let pop = Double(s.members.count)
        let soldiers = Double(s.members.filter { agents[$0]?.legion != nil }.count)
        switch good {
        case "planks": return 14
        case "iron": return 10
        case "parts": return 8
        case "tools": return max(2, pop / 5)
        case "weapons": return soldiers + 3
        case "armor": return soldiers + 1
        case "engines": return realm.atWar(s.nation ?? 0) ? 3 : 1
        case "meal": return s.food > pop * 10 ? pop * 2 : 0
        case "moonsteel": return 2
        default: return 0
        }
    }

    /// One game hour of work in every town.
    func economyHourly() {
        let cfg = realm.cfg
        let now = world.time
        for s in settlements.values.filter({ !$0.abandoned }).sorted(by: { $0.id < $1.id }) {
            if now >= s.cityT { surveyTown(s) }
            let living = s.members.compactMap { agents[$0] }
            let adults = living.filter { $0.stage(now) == "adult" && $0.legion == nil && $0.refugee == nil }
            // ore comes up from the mine with the miners
            if s.fixture("stairs_down") > 0 {
                let miners = Double(min(4, adults.filter { $0.job == "miner" }.count + 1))
                if s.good("iron_ore") < storageCap(s) { s.addGood("iron_ore", cfg.mineIron * miners) }
                if (realm.nation(s.nation ?? 0)?.techCount ?? 0) >= 5 { s.addGood("moon_ore", cfg.mineMoon * miners); s.addGood("gold_ore", cfg.mineMoon * miners * 0.5) }
            }
            // meals stretch food when the pot runs low
            if s.food < Double(living.count) * 2, s.good("meal") >= 1 { s.addGood("meal", -1); s.food += 1.5 }
            var crew = max(1, adults.count / cfg.artisansPer)
            var work = s.work ?? [:]
            var pause: [String: String] = [:]
            let cap = storageCap(s)
            for kind in ["furnace", "workbench", "anvil", "kitchen"] {
                let n = s.fixture(kind)
                if n == 0 { continue }
                for k in 0..<min(n, 4) {
                    let slot = "\(kind)#\(k)"
                    if crew <= 0 { pause[slot] = "worker"; continue }
                    // the first recipe of this station that is wanted and can be made
                    var chosen: Recipe?
                    var why = "idle"
                    for r in Recipe.all where r.station == kind {
                        let out = r.outputs[0]
                        if s.good(out.0) >= demand(s, out.0) { continue }
                        if s.good(out.0) + out.1 > cap { why = "full"; continue }
                        if let lack = r.inputs.first(where: { s.good($0.0) < $0.1 + (($0.0 == "food" || $0.0 == "wood") ? Double(living.count) : 0) }) { if why == "idle" { why = "input:" + lack.0 }; continue }
                        chosen = r; break
                    }
                    guard let r = chosen else { pause[slot] = why; continue }
                    crew -= 1
                    work[slot] = (work[slot] ?? 0) + 1
                    if work[slot]! >= r.hours {
                        // settle the batch in one step
                        for (g, q) in r.inputs { s.addGood(g, -q) }
                        for (g, q) in r.outputs { s.addGood(g, q) }
                        work[slot] = 0
                        stats.crafted = (stats.crafted ?? 0) + 1
                    }
                }
            }
            s.work = work
            s.pause = pause
        }
        // the player's own job at a station
        if let job = realm.player.craft, now >= job.done, let r = Recipe.byKey[job.recipe] {
            for (g, q) in r.outputs { carry(g, q) }
            realm.player.craft = nil
        }
    }

    public func craftTick() {
        if let job = realm.player.craft, world.time >= job.done, let r = Recipe.byKey[job.recipe] {
            for (g, q) in r.outputs { carry(g, q) }
            realm.player.craft = nil
        }
    }

    /// Start a recipe at a station within reach. Inputs are taken now, the product arrives when the work is done.
    public func playerCraft(_ key: String, near pos: Vec2, in w: OpenWorld? = nil) -> String? {
        guard let r = Recipe.byKey[key] else { return "unknown" }
        if realm.player.craft != nil { return "busy" }
        let w = w ?? world
        let want = content.tid(r.station)
        var found = false
        for dy in -2...2 { for dx in -2...2 where w.tile(2, pos.tile.x + dx, pos.tile.y + dy) == want { found = true } }
        if !found { return "station:" + r.station }
        if let lack = r.inputs.first(where: { carried($0.0) < $0.1 }) { return "input:" + lack.0 }
        for (g, q) in r.inputs { carry(g, -q) }
        realm.player.craft = CraftJob(recipe: key, done: world.time + r.hours * Society.hour * realm.cfg.playerCraftSpeed)
        return nil
    }

    /// Weapons and armour in a nation's stores make its soldiers count for more.
    func gearBonus(_ nation: Int) -> Double {
        let ts = towns(of: nation)
        let soldiers = max(1, Double(realm.nation(nation)?.soldiers ?? 1))
        let w = ts.reduce(0.0) { $0 + $1.good("weapons") }, a = ts.reduce(0.0) { $0 + $1.good("armor") }
        return 1 + realm.cfg.gearWeapons * min(1, w / soldiers) + realm.cfg.gearArmor * min(1, a / soldiers)
    }

    /// Give goods from the pack to a town (any good, not just the basic three).
    @discardableResult public func playerSupply(sid: Int, good: String, amount: Double) -> Double {
        guard let s = settlements[sid], !s.abandoned else { return 0 }
        if ["food", "wood", "stone"].contains(good) { return playerDonate(sid: sid, kind: good, amount: amount) }
        let give = min(amount, carried(good))
        if give <= 0 { return 0 }
        carry(good, -give)
        s.addGood(good, give)
        addRep(s.nation ?? 0, give / 30)
        return give
    }
}
