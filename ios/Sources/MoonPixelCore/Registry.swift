import Foundation

// The content registry: every kind of food, item, facility, recipe, technology, weapon and machine the
// game knows, under a stable namespaced key. The rules never list kinds themselves; they ask the
// registry, and they ask about capabilities ("has a hangar bay", "makes steel"), not names.
//
// Keys. A key is "namespace:name". The game's own content is the namespace "moonpixel", written bare
// in saves for compatibility ("frame" is "moonpixel:frame"); any other pack must use its own prefix.
// Saves store keys, never positions in a list.
//
// Packs. The built-in tables of CivData.swift are the "moonpixel" pack. More packs are JSON
// (`ContentPack`): adding a factory, a recipe or a variant of an existing machine needs only a pack,
// which is checked as a whole before it is accepted. A pack that fails a check changes nothing.

public enum ContentKey {
    public static let builtin = "moonpixel"
    /// The canonical form of a key: built-in content without its prefix, everything else with one.
    public static func canonical(_ k: String) -> String {
        let p = builtin + ":"
        return k.hasPrefix(p) ? String(k.dropFirst(p.count)) : k
    }
    public static func namespace(_ k: String) -> String { k.contains(":") ? String(k.split(separator: ":", maxSplits: 1)[0]) : builtin }
    public static func full(_ k: String) -> String { k.contains(":") ? k : builtin + ":" + k }
}

/// Something wrong with content: which kind, which key, which field, and what.
public struct ContentIssue: Error, Equatable, CustomStringConvertible {
    public var kind: String, key: String, field: String, problem: String
    public var description: String { "\(kind) \(ContentKey.full(key)).\(field): \(problem)" }
}

public struct ContentError: Error, CustomStringConvertible {
    public var issues: [ContentIssue]
    public var description: String { issues.map { $0.description }.joined(separator: "\n") }
}

/// A JSON content pack.
public struct ContentPack: Codable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var namespace: String
    public var foods: [CivFood]?
    public var items: [CivItem]?
    public var facilities: [CivFacility]?
    public var recipes: [CivRecipe]?
    public var techs: [CivTech]?
    public var weapons: [CivWeapon]?
    public var prototypes: [CivUnitDef]?
    /// Variants: a new machine made from an existing one by changing only some capabilities.
    public var variants: [Variant]?

    public struct Variant: Codable {
        public var key: String, base: String
        public var en: String?, zh: String?
        public var build: CivUnitDef.Build?
        public var move: CivUnitDef.Move?
        public var hull: CivUnitDef.Hull?
        public var crewing: CivUnitDef.Crew?
        public var stores: CivUnitDef.Stores?
        public var hangarBay: CivUnitDef.HangarBay?
        public var power: CivUnitDef.Power?
        public var fuelTank: CivUnitDef.Tank?
        public var weaponKeys: [String]?
        public var art: String?
    }
}

public final class ContentRegistry {
    /// The registry the game runs on. Set once at start-up (with any packs); tests may swap it.
    public static var shared = ContentRegistry.builtin()

    public private(set) var foods: [CivFood] = [], items: [CivItem] = [], facilities: [CivFacility] = [], recipes: [CivRecipe] = []
    public private(set) var techs: [CivTech] = [], weapons: [CivWeapon] = [], units: [CivUnitDef] = []
    public private(set) var foodsByKey: [String: CivFood] = [:], itemsByKey: [String: CivItem] = [:], facilitiesByKey: [String: CivFacility] = [:]
    public private(set) var recipesByKey: [String: CivRecipe] = [:], techsByKey: [String: CivTech] = [:], weaponsByKey: [String: CivWeapon] = [:], unitsByKey: [String: CivUnitDef] = [:]
    public private(set) var eatOrder: [String] = []
    /// Worked out once when content changes, not on every use: recipes upstream first, each machine's weapons.
    public private(set) var recipeOrder: [CivRecipe] = []
    public private(set) var unitWeapons: [String: [CivWeapon]] = [:]
    public private(set) var packs: [String] = [ContentKey.builtin]
    /// Pictures the game can draw (a machine whose art is missing is refused rather than drawn as something else).
    public var art: Set<String> = []

    init() {}

    public static func builtin() -> ContentRegistry {
        let r = ContentRegistry()
        r.foods = CivFood.builtin; r.items = CivItem.builtin; r.facilities = CivFacility.builtin; r.recipes = CivRecipe.builtin
        r.techs = CivTech.builtin; r.weapons = CivUnitDef.builtinWeapons; r.units = CivUnitDef.builtin
        r.art = Set(r.units.compactMap { $0.art })
        r.index()
        return r
    }

    func index() {
        foodsByKey = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        itemsByKey = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        facilitiesByKey = Dictionary(facilities.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        recipesByKey = Dictionary(recipes.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        techsByKey = Dictionary(techs.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        weaponsByKey = Dictionary(weapons.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        unitsByKey = Dictionary(units.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        eatOrder = CivFood.eatOrder(foods)
        recipeOrder = Civ.recipeOrderKeys.compactMap { recipesByKey[$0] } + recipes.filter { !Civ.recipeOrderKeys.contains($0.key) }
        unitWeapons = Dictionary(units.map { u in (u.key, u.weaponKeys.compactMap { weaponsByKey[$0] }) }, uniquingKeysWith: { a, _ in a })
    }

    func copy() -> ContentRegistry {
        let r = ContentRegistry()
        r.foods = foods; r.items = items; r.facilities = facilities; r.recipes = recipes; r.techs = techs; r.weapons = weapons; r.units = units
        r.art = art; r.packs = packs
        r.index()
        return r
    }

    /// This registry with a pack added. The pack is checked together with everything already known;
    /// on any problem nothing is added and every problem is reported.
    public func adding(_ data: Data) throws -> ContentRegistry {
        let pack: ContentPack
        do { pack = try JSONDecoder().decode(ContentPack.self, from: data) }
        catch { throw ContentError(issues: [ContentIssue(kind: "pack", key: "?", field: "json", problem: "\(error)")]) }
        return try adding(pack)
    }

    public func adding(_ pack: ContentPack) throws -> ContentRegistry {
        var issues: [ContentIssue] = []
        let ns = pack.namespace
        if pack.schemaVersion != ContentPack.schemaVersion { issues.append(ContentIssue(kind: "pack", key: ns, field: "schemaVersion", problem: "version \(pack.schemaVersion) is not supported (this game reads \(ContentPack.schemaVersion))")) }
        if ns.isEmpty || ns == ContentKey.builtin || ns.contains(":") { issues.append(ContentIssue(kind: "pack", key: ns, field: "namespace", problem: "a pack needs its own namespace")) }
        if packs.contains(ns) { issues.append(ContentIssue(kind: "pack", key: ns, field: "namespace", problem: "already loaded")) }
        func own(_ kind: String, _ key: String) { if ContentKey.namespace(key) != ns { issues.append(ContentIssue(kind: kind, key: key, field: "key", problem: "must start with \(ns):")) } }
        let r = copy()
        r.packs.append(ns)
        for x in pack.foods ?? [] { own("food", x.key); r.foods.append(x) }
        for x in pack.items ?? [] { own("item", x.key); r.items.append(x) }
        for x in pack.facilities ?? [] { own("facility", x.key); r.facilities.append(x) }
        for x in pack.recipes ?? [] { own("recipe", x.key); r.recipes.append(x) }
        for x in pack.techs ?? [] { own("tech", x.key); r.techs.append(x) }
        for x in pack.weapons ?? [] { own("weapon", x.key); r.weapons.append(x) }
        for x in pack.prototypes ?? [] { own("prototype", x.key); r.units.append(x); if let a = x.art { r.art.insert(a) } }
        for v in pack.variants ?? [] {
            own("variant", v.key)
            guard let base = r.units.first(where: { $0.key == ContentKey.canonical(v.base) }) else {
                issues.append(ContentIssue(kind: "variant", key: v.key, field: "base", problem: "no machine \(v.base)")); continue
            }
            var u = base
            u.key = v.key; u.en = v.en ?? base.en; u.zh = v.zh ?? base.zh
            if let x = v.build { u.build = x }
            if let x = v.move { u.move = x }
            if let x = v.hull { u.hull = x }
            if let x = v.crewing { u.crewing = x }
            if let x = v.stores { u.stores = x }
            if let x = v.hangarBay { u.hangarBay = x }
            if let x = v.power { u.power = x }
            if let x = v.fuelTank { u.fuelTank = x }
            if let x = v.weaponKeys { u.weaponKeys = x }
            u.art = v.art ?? base.art
            r.units.append(u)
        }
        r.index()
        issues += r.validate()
        if !issues.isEmpty { throw ContentError(issues: issues) }
        return r
    }

    // MARK: - checking

    /// Every problem with the content as it stands. Empty means it is sound.
    public func validate() -> [ContentIssue] {
        var out: [ContentIssue] = []
        func bad(_ kind: String, _ key: String, _ field: String, _ problem: String) { out.append(ContentIssue(kind: kind, key: key, field: field, problem: problem)) }
        // one key, one thing (across every kind of goods too: a food and an item may not share a key)
        for (kind, keys) in [("food", foods.map { $0.key }), ("item", items.map { $0.key }), ("facility", facilities.map { $0.key }), ("recipe", recipes.map { $0.key }),
                             ("tech", techs.map { $0.key }), ("weapon", weapons.map { $0.key }), ("prototype", units.map { $0.key })] {
            var seen = Set<String>()
            for k in keys where !seen.insert(k).inserted { bad(kind, k, "key", "defined twice") }
        }
        for k in Set(foods.map { $0.key }).intersection(items.map { $0.key }) { bad("item", k, "key", "is both a food and an item") }
        let goods = Set(foods.map { $0.key }).union(items.map { $0.key })
        func amounts(_ kind: String, _ key: String, _ field: String, _ d: [String: Double]) {
            for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                if !goods.contains(k) { bad(kind, key, field, "unknown goods \(k)") }
                if !(v > 0) || !v.isFinite { bad(kind, key, field, "amount of \(k) must be a positive number, not \(v)") }
            }
        }
        func tech(_ kind: String, _ key: String, _ t: String?) { if let t = t, techsByKey[t] == nil { bad(kind, key, "tech", "unknown technology \(t)") } }
        for f in foods {
            if !(f.nutrition > 0) { bad("food", f.key, "nutrition", "must be above 0") }
            if !(f.shelfDays > 0) { bad("food", f.key, "shelfDays", "must be above 0") }
            tech("food", f.key, f.tech)
        }
        for f in facilities {
            amounts("facility", f.key, "cost", f.cost); tech("facility", f.key, f.tech)
            if f.workers < 0 { bad("facility", f.key, "workers", "cannot be negative") }
            if let n = f.needs, !["coast", "deep"].contains(n) { bad("facility", f.key, "needs", "unknown site \(n)") }
        }
        for r in recipes {
            if facilitiesByKey[r.facility] == nil { bad("recipe", r.key, "facility", "unknown facility \(r.facility)") }
            if r.inputs.isEmpty { bad("recipe", r.key, "inputs", "a recipe must take something (nothing is made from nothing)") }
            if r.outputs.isEmpty { bad("recipe", r.key, "outputs", "a recipe must make something") }
            amounts("recipe", r.key, "inputs", r.inputs); amounts("recipe", r.key, "outputs", r.outputs)
            if !(r.hours > 0) { bad("recipe", r.key, "hours", "must be above 0") }
            if r.energy < 0 { bad("recipe", r.key, "energy", "cannot be negative") }
            tech("recipe", r.key, r.tech)
        }
        for t in techs {
            for n in t.needs where techsByKey[n] == nil { bad("tech", t.key, "needs", "unknown technology \(n)") }
            if t.cost < 0 { bad("tech", t.key, "cost", "cannot be negative") }
        }
        for c in techCycles() { bad("tech", c[0], "needs", "circular: " + c.joined(separator: " → ")) }
        for c in gainLoops() { bad("recipe", c.recipes[0], "outputs", "a loop of recipes makes \(c.item) from nothing (×\(String(format: "%.2f", c.gain)) each round): " + c.recipes.joined(separator: " → ")) }
        for w in weapons {
            if w.layers.isEmpty { bad("weapon", w.key, "layers", "reaches no layer") }
            if w.vs.count != 4 { bad("weapon", w.key, "vs", "needs 4 multipliers (soft, armoured, heavy, structure)") }
            if !(w.damage > 0) { bad("weapon", w.key, "damage", "must be above 0") }
            if w.range < 0 || w.cooldown <= 0 || w.flight < 0 { bad("weapon", w.key, "range/cooldown/flight", "out of range") }
        }
        for u in units {
            if facilitiesByKey[u.facility] == nil { bad("prototype", u.key, "build.facility", "unknown facility \(u.facility)") }
            for t in u.tech where techsByKey[t] == nil { bad("prototype", u.key, "build.tech", "unknown technology \(t)") }
            if u.stages.isEmpty { bad("prototype", u.key, "build.stages", "needs at least one stage") }
            for (i, st) in u.stages.enumerated() { amounts("prototype", u.key, "build.stages[\(i)]", st) }
            if !(u.hours > 0) { bad("prototype", u.key, "build.hours", "must be above 0") }
            if !(u.hp > 0) { bad("prototype", u.key, "hull.hp", "must be above 0") }
            if u.armor < 0 || u.armor > 3 { bad("prototype", u.key, "hull.armor", "must be 0...3") }
            if u.crew < 0 { bad("prototype", u.key, "crewing.people", "cannot be negative") }
            for w in u.weaponKeys where weaponsByKey[w] == nil { bad("prototype", u.key, "weaponKeys", "unknown weapon \(w)") }
            // capabilities that need each other
            if let h = u.hangarBay, h.capacity <= 0 || h.deckPerHour <= 0 { bad("prototype", u.key, "hangarBay", "a hangar needs room and a deck that can launch (capacity and deckPerHour above 0)") }
            if u.weapons.contains(where: { $0.ammo > 0 }) && u.ammoCap <= 0 { bad("prototype", u.key, "stores.ammo", "carries a weapon that fires ammunition but has nowhere to keep it") }
            if u.weapons.contains(where: { $0.energy > 0 }) && u.energyPerDay <= 0 { bad("prototype", u.key, "power", "carries an energy weapon but draws no power") }
            if u.weapons.contains(where: { $0.heat > 0 }) && u.heatCap <= 0 { bad("prototype", u.key, "thermal", "a weapon makes heat but nothing takes it away") }
            if u.layer.air && !u.carrierBased && u.hangar == 0 && u.energyPerDay <= 0 && u.endurance <= 0 { bad("prototype", u.key, "flight", "flies with no endurance and no power") }
            if u.speed > 0 && u.fuelPerDay > 0 && u.fuelCap <= 0 { bad("prototype", u.key, "fuelTank", "burns fuel but has no tank") }
            if u.size == .huge && u.layer == .ground { bad("prototype", u.key, "move", "nothing of that size can move on the ground") }
            if u.crew > 0 && u.foodCap <= 0 && !u.carrierBased { bad("prototype", u.key, "stores.food", "has a crew but carries no food") }
            if let a = u.art, !art.contains(a) { bad("prototype", u.key, "art", "no picture \(a)") }
        }
        return out
    }

    /// Technologies that need themselves, one way round or another.
    func techCycles() -> [[String]] {
        var state: [String: Int] = [:], stack: [String] = [], out: [[String]] = []
        func visit(_ k: String) {
            state[k] = 1; stack.append(k)
            for n in techsByKey[k]?.needs ?? [] {
                if state[n] == 1, let i = stack.firstIndex(of: n) { out.append(Array(stack[i...]) + [n]) }
                else if state[n] == nil { visit(n) }
            }
            stack.removeLast(); state[k] = 2
        }
        for t in techs.map({ $0.key }).sorted() where state[t] == nil { visit(t) }
        return out
    }

    /// Chains of recipes that end with more of something than they started with (a free source).
    func gainLoops() -> [(item: String, gain: Double, recipes: [String])] {
        var out: [(String, Double, [String])] = []
        var found = Set<String>()
        func walk(_ start: String, _ item: String, _ mult: Double, _ path: [String], _ depth: Int) {
            guard depth < 6 else { return }
            for r in recipes.sorted(by: { $0.key < $1.key }) {
                guard let need = r.inputs[item], !path.contains(r.key) else { continue }
                for (o, made) in r.outputs.sorted(by: { $0.key < $1.key }) {
                    let m = mult * made / need
                    if o == start {
                        if m > 1 + 1e-9 { let sig = (path + [r.key]).sorted().joined(separator: ","); if found.insert(sig).inserted { out.append((start, m, path + [r.key])) } }
                    } else { walk(start, o, m, path + [r.key], depth + 1) }
                }
            }
        }
        let goods = Set(recipes.flatMap { Array($0.inputs.keys) })
        for g in goods.sorted() { walk(g, g, 1, [], 0) }
        return out.map { ($0.0, $0.1, $0.2) }
    }
}
