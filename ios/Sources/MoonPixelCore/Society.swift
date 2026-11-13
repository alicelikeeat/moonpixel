import Foundation

/// A* over a square grid of walkable/solid cells (8 directions, no corner
/// cutting). Scratch buffers are reused between searches (generation stamps),
/// so a search allocates nothing but its result.
public final class PathGrid {
    public let size: Int
    public var solid: [Bool]
    private var g: [Float], came: [Int32], stamp: [Int32], closed: [Int32]
    private var heapF: [Float] = [], heapI: [Int32] = []
    private var gen: Int32 = 0
    public static var calls = 0, fails = 0, expanded = 0

    public init(size: Int) {
        self.size = size
        let n = size * size
        solid = [Bool](repeating: false, count: n)
        g = [Float](repeating: 0, count: n)
        came = [Int32](repeating: -1, count: n)
        stamp = [Int32](repeating: 0, count: n)
        closed = [Int32](repeating: 0, count: n)
        heapF.reserveCapacity(1024); heapI.reserveCapacity(1024)
    }

    public func path(from a: TilePos, to b: TilePos) -> [TilePos] {
        let n = size
        guard a.x >= 0, a.y >= 0, a.x < n, a.y < n, b.x >= 0, b.y >= 0, b.x < n, b.y < n else { return [] }
        if a == b { return [a] }
        gen &+= 1
        PathGrid.calls += 1
        let cur_gen = gen
        let start = a.y * n + a.x, goal = b.y * n + b.x
        heapF.removeAll(keepingCapacity: true); heapI.removeAll(keepingCapacity: true)
        g[start] = 0; came[start] = -1; stamp[start] = cur_gen
        heapF.append(0); heapI.append(Int32(start))
        var found = false
        var expandedHere = 0
        solid.withUnsafeBufferPointer { sol in
            while !heapI.isEmpty {
                // pop min
                let cur = Int(heapI[0])
                let lastF = heapF.removeLast(), lastI = heapI.removeLast()
                if !heapI.isEmpty {
                    var p = 0
                    let cnt = heapI.count
                    while true {
                        let l = 2 * p + 1
                        if l >= cnt { break }
                        let r = l + 1
                        let m = (r < cnt && heapF[r] < heapF[l]) ? r : l
                        if heapF[m] >= lastF { break }
                        heapF[p] = heapF[m]; heapI[p] = heapI[m]
                        p = m
                    }
                    heapF[p] = lastF; heapI[p] = lastI
                }
                if cur == goal { found = true; break }
                if closed[cur] == cur_gen { continue }
                closed[cur] = cur_gen
                PathGrid.expanded += 1
                expandedHere += 1
                if expandedHere > 3000 { break }      // give up on hopeless searches
                let cx = cur % n, cy = cur / n
                let gc = g[cur]
                var dy = -1
                while dy <= 1 {
                    var dx = -1
                    while dx <= 1 {
                        defer { dx += 1 }
                        if dx == 0 && dy == 0 { continue }
                        let nx = cx + dx, ny = cy + dy
                        if nx < 0 || ny < 0 || nx >= n || ny >= n { continue }
                        let ni = ny * n + nx
                        if closed[ni] == cur_gen || (sol[ni] && ni != goal) { continue }
                        if dx != 0 && dy != 0 && (sol[cy * n + nx] || sol[ny * n + cx]) { continue }
                        let ng = gc + (dx != 0 && dy != 0 ? 1.41 : 1.0)
                        if stamp[ni] != cur_gen || ng < g[ni] {
                            stamp[ni] = cur_gen; g[ni] = ng; came[ni] = Int32(cur)
                            let ddx = abs(nx - b.x), ddy = abs(ny - b.y)
                            let f = ng + Float(max(ddx, ddy)) + 0.41 * Float(min(ddx, ddy))
                            // push
                            heapF.append(f); heapI.append(Int32(ni))
                            var c = heapI.count - 1
                            while c > 0 {
                                let p = (c - 1) / 2
                                if heapF[p] <= f { break }
                                heapF[c] = heapF[p]; heapI[c] = heapI[p]
                                c = p
                            }
                            heapF[c] = f; heapI[c] = Int32(ni)
                        }
                    }
                    dy += 1
                }
            }
        }
        if !found { PathGrid.fails += 1; return [] }
        var out: [TilePos] = []
        var c = goal
        while c != start { out.append(TilePos(c % n, c / n)); c = Int(came[c]) }
        out.append(a)
        return out.reversed()
    }
}

public struct Thought: Codable { public var t: Double, k: String, a: [String] }

public struct AgentTask {
    public var act: String, target: TilePos, dur: Double, t = 0.0, stage = 0, bid = 0, cell = 0
}

public struct Look: Codable, Equatable {
    public var skin = "#f2c8a4", hair = "#5a3a22", shirt = "#5a8ae8", pants = "#4a4a5a", shoes = "#5a3a2a", face = "", style = 0
    /// Asset id of the pixel portrait generated from a photo (optional: older saves have none).
    public var portrait: String?
    public init() {}
}

/// One autonomous villager (data; behaviour lives in Society).
public final class Agent: Codable {
    public var id = 0
    public var nameEn = "", nameZh = "", clanEn = "", clanZh = ""
    public var female = false
    public var birth = 0.0
    public var sid = 0, home = -1, partner = 0, mother = 0, father = 0
    public var children: [Int] = []
    public var pos = Vec2.zero
    public var hunger = 0.2, energy = 0.9, social = 0.3, health = 1.0, grief = 0.0
    public var dil = 0.5, soc = 0.5
    public var look = Look()
    public var job = ""
    public var rel: [Int: Double] = [:]
    public var thoughts: [Thought] = []
    public var pregnantDue = -1.0
    public var birthFather = 0
    public var lastBirth = -1e9
    public var travelling = false
    public var travelTo = Vec2.zero
    public var carryKind = ""
    public var carryN = 0.0
    // transient
    public var prevPos = Vec2.zero
    public var facing = Vec2(0, 1)
    public var moving = false, sleeping = false, alive = true
    public var task: AgentTask?
    public var path: [Vec2] = []
    public var pathI = 0
    public var thinkT = 0.0

    enum CodingKeys: String, CodingKey {
        case id, nameEn, nameZh, clanEn, clanZh, female, birth, sid, home, partner, mother, father, children, pos, hunger, energy, social,
             health, grief, dil, soc, look, job, rel, thoughts, pregnantDue, birthFather, lastBirth, travelling, travelTo, carryKind, carryN
    }

    public init() {}
    public func age(_ now: Double) -> Double { (now - birth) / MP.year }
    public func stage(_ now: Double) -> String { let a = age(now); return a < 14 ? "child" : (a < 62 ? "adult" : "elder") }
    public func think(_ now: Double, _ key: String, _ args: [String] = []) {
        thoughts.append(Thought(t: now, k: key, a: args))
        if thoughts.count > 6 { thoughts.removeFirst() }
    }
    public var mood: Double {
        var m = 1.0 - hunger * 0.45 - (1 - energy) * 0.15 - social * 0.15 - grief * 0.3
        if home < 0 { m -= 0.12 }
        return min(1, max(0, m * health))
    }
    public func name(zh: Bool) -> String { zh ? clanZh + nameZh : nameEn + " " + clanEn }
}

public struct BuildCell: Codable { public var dx: Int, dy: Int, layer: Int, key: String, wood: Double, stone: Double }

public final class Building: Codable {
    public var id = 0, type = "", x = 0, y = 0, w = 0, h = 0
    public var cells: [BuildCell] = []
    public var next = 0, placed = 0
    public var retry: [Int] = []
    public var done = false
    public var residents: [Int] = []
    public var cap = 0
    /// Household that owns this house (optional so that older saves still load).
    public var owner: Int?
    public var door = TilePos(0, 0)
    public init() {}
}

public final class Settlement: Codable {
    public static let span = 96
    public var id = 0, nameEn = "", nameZh = ""
    public var center = TilePos(0, 0)
    public var founded = 0.0, lastFound = 0.0
    public var food = 0.0, wood = 0.0, stone = 0.0
    public var buildings: [Building] = []
    public var members: [Int] = []
    public var usedSlots: Set<String> = []
    public var graves = 0
    public var abandoned = false
    // transient
    public var nav: PathGrid?
    public var origin = TilePos(0, 0)
    var trees: [TilePos] = [], rocks: [TilePos] = [], berries: [TilePos] = []
    var claims: [TilePos: Int] = [:]
    var unreachable: Set<TilePos> = []
    var unreachT = 0.0
    var resT = 0.0, planT = 0.0, aiAcc = 0.0

    enum CodingKeys: String, CodingKey { case id, nameEn, nameZh, center, founded, lastFound, food, wood, stone, buildings, members, usedSlots, graves, abandoned }
    public init() {}
    public func inArea(_ t: TilePos) -> Bool { t.x >= origin.x && t.y >= origin.y && t.x < origin.x + Settlement.span && t.y < origin.y + Settlement.span }
    public func building(_ id: Int) -> Building? { buildings.first { $0.id == id } }
    public func count(_ type: String, done: Bool = false) -> Int { buildings.filter { $0.type == type && ($0.done || !done) }.count }
    public var activeProject: Building? { buildings.first { !$0.done } }
    public func name(zh: Bool) -> String { zh ? nameZh : nameEn }
    func stock(_ k: String) -> Double { k == "food" ? food : (k == "wood" ? wood : stone) }
    func addStock(_ k: String, _ n: Double) { if k == "food" { food += n } else if k == "wood" { wood += n } else if k == "stone" { stone += n } }
}

public struct SocietyStats: Codable {
    public var births = 0, deaths = 0, old = 0, hunger = 0, ill = 0, pairs = 0, buildings = 0, founded = 0, immigrants = 0, tilesPlaced = 0
}

/// Autonomous NPC society: needs, jobs, tile-by-tile construction, friendships,
/// couples, births, ageing, death, immigration and expeditions that found new
/// settlements. Local, seeded, rule/utility based -- no network, no cloud model.
public final class Society {
    public static let hour = MP.daySeconds / 24.0
    static let speed = 46.0
    public static var failActs: [String: Int] = [:]
    static let namesEn = ["Aren", "Bela", "Cato", "Dara", "Elin", "Faro", "Gwen", "Hale", "Iris", "Joss", "Kira", "Lorn", "Mira", "Nico", "Orla", "Penn", "Quin", "Rhea", "Sol", "Tess", "Ulan", "Vera", "Wyn", "Yara", "Zed", "Ash", "Bryn", "Cole", "Dawn", "Eben", "Fern", "Gale"]
    static let namesZh = ["岚", "禾", "青", "石", "月", "川", "竹", "溪", "松", "雨", "晴", "木", "星", "云", "叶", "砚", "舟", "霜", "朔", "棠", "原", "薇", "风", "遥", "泽", "灰", "岭", "炭", "晓", "岩", "蕨", "澜"]
    static let clansEn = ["Oakhand", "Riverun", "Stonefield", "Moonvale", "Ashgrove", "Brightwater", "Hollowell", "Thornwick", "Greyfen", "Summerlea", "Windmere", "Deepwood"]
    static let clansZh = ["橡", "江", "石田", "月谷", "梣", "明川", "空井", "荆", "灰泽", "夏原", "风湖", "深林"]
    static let townEn = ["Moonfall", "Reedmere", "Oakrest", "Stonebrook", "Ashford", "Brightmoor", "Fernhollow", "Willowend", "Frostgate", "Dunehaven", "Mistvale", "Larkfield", "Emberly", "Pinewatch", "Saltmarsh", "Goldlea"]
    static let townZh = ["月落", "苇湖", "橡息", "石溪", "梣渡", "明泽", "蕨谷", "柳尾", "霜门", "沙港", "雾谷", "雀田", "余烬", "松望", "盐沼", "金原"]
    public static let skins = ["#fbe0cc", "#f6d2b4", "#f2c8a4", "#e6b088", "#c98a62", "#a06a46"]
    public static let hairs = ["#3a3038", "#5a3a22", "#8a5a30", "#d8b068", "#c85a3a", "#e8a0b8", "#7a8ad8"]
    public static let shirts = ["#5a8ae8", "#ee6a7a", "#58b888", "#e8c050", "#a878e0", "#58bcd0", "#f09a58", "#8a90b0", "#f0a0c0", "#88c860"]
    static let pantsList = ["#4a4a5a", "#6a5a48", "#3a4a6a", "#5a3a4a"]

    public static let text: [String: (String, String)] = [
        "born": ("%@ was born in %@", "%@ 在%@出生了"), "died_old": ("%@ died of old age (%@)", "%@ 寿终正寝（%@ 岁）"),
        "died_hunger": ("%@ starved to death (%@)", "%@ 饿死了（%@ 岁）"), "died_ill": ("%@ died of illness (%@)", "%@ 因病去世（%@ 岁）"),
        "paired": ("%@ and %@ became a couple", "%@ 和 %@ 结为伴侣"), "built": ("%@ finished a %@", "%@ 建成了一座%@"),
        "founded": ("%@ settlers from %@ founded %@", "%@ 位来自%@的开拓者建立了%@"), "arrived": ("%@ wanderers joined %@", "%@ 位流浪者加入了%@"),
        "abandoned": ("%@ has been abandoned", "%@ 已被废弃"), "tech": ("The people discovered %@", "人们掌握了%@"),
        "school": ("school", "学校"), "workshop": ("workshop", "工坊"), "factory": ("factory", "工厂"), "lab": ("research lab", "研究所"),
        "ai_center": ("AI centre", "人工智能中心"),
        "house": ("house", "房屋"), "farm": ("farm", "农田"), "well": ("well", "水井"), "lights": ("lantern square", "灯火广场"),
        "job_": ("resting", "休息"), "job_child": ("child", "孩子"), "job_elder": ("elder", "长者"), "job_forager": ("forager", "采集者"),
        "job_woodcutter": ("woodcutter", "伐木工"), "job_miner": ("stonecutter", "采石工"), "job_farmer": ("farmer", "农夫"), "job_builder": ("builder", "建筑工"),
        "t_hungry": ("I'm so hungry... the stores are empty.", "好饿……仓库已经空了。"), "t_ate": ("A good meal.", "吃了顿饱饭。"),
        "t_chat": ("Had a nice talk with %@.", "和%@聊得很开心。"), "t_quarrel": ("Argued with %@.", "和%@吵了一架。"),
        "t_love": ("%@ and I are together now.", "我和%@在一起了。"), "t_child": ("Our child %@ was born!", "我们的孩子%@出生了！"),
        "t_grief": ("I miss %@.", "我很想念%@。"), "t_built": ("We finished building a %@.", "我们把%@盖好了。"), "t_home": ("I have a home now.", "我终于有家了。"),
        "t_new_land": ("We set out to found %@.", "我们出发去建立%@。"), "t_gift": ("A traveler gave me food. Kind soul.", "一位旅人送了我食物，真是好人。"),
        "t_work_forager": ("Picking berries for the stores.", "在给仓库采浆果。"), "t_work_woodcutter": ("Felling trees. We need timber.", "在伐木，我们需要木材。"),
        "t_work_miner": ("Breaking stone.", "在采石。"), "t_work_farmer": ("Tending the wheat.", "在照料麦田。"), "t_work_builder": ("Raising walls.", "在砌墙盖房。"),
        "s_hello": ("Hello, traveler.", "你好，旅行者。"), "s_friend": ("Good to see you again, friend!", "又见面了，朋友！"),
        "s_hungry": ("Do you have anything to eat? We are short of food.", "你有吃的吗？我们的粮食不够了。"), "s_tired": ("I can barely keep my eyes open.", "我困得睁不开眼了。"),
        "s_grief": ("I lost someone dear. Forgive my mood.", "我失去了亲人，请原谅我的情绪。"), "s_preg": ("We are expecting a child!", "我们要有孩子了！"),
        "s_nohome": ("I sleep by the fire for now. We are building more houses.", "我暂时睡在篝火旁，大家正在盖更多的房子。"),
        "s_child": ("Wanna play? I'm %@!", "要一起玩吗？我 %@ 岁啦！"),
        "s_elder": ("I have seen %@ winters. This village grew from a single campfire.", "我已经度过了 %@ 个冬天。这个村子是从一堆篝火发展起来的。"),
        "s_town": ("%@ has %@ people and %@ houses now.", "%@现在有 %@ 人、%@ 座房屋。"),
    ]

    /// Technologies the civilisation discovers on its own, in order.
    /// (key, English, Chinese, research cost)
    public static let techs: [(String, String, String, Double)] = [
        ("farming", "Farming", "农耕", 80), ("masonry", "Masonry", "石工", 180), ("writing", "Writing", "文字", 320),
        ("metalwork", "Metalworking", "冶金", 520), ("machinery", "Machinery", "机械", 840), ("electricity", "Electricity", "电力", 1300),
        ("manufacturing", "Advanced manufacturing", "先进制造", 1900), ("computing", "Computing", "计算机", 2600),
        ("ai", "Artificial intelligence", "人工智能", 3600),
    ]
    /// Buildings a technology unlocks: (tech key, building type, minimum population).
    static let techBuildings: [(String, String, Int)] = [
        ("writing", "school", 10), ("metalwork", "workshop", 12), ("manufacturing", "factory", 14), ("computing", "lab", 16), ("ai", "ai_center", 18),
    ]
    /// Number of technologies discovered so far, and progress towards the next.
    public private(set) var techCount = 0
    public private(set) var research = 0.0

    public func has(_ tech: String) -> Bool {
        guard let i = Society.techs.firstIndex(where: { $0.0 == tech }) else { return false }
        return i < techCount
    }
    public func techName(_ i: Int) -> String { i < 0 || i >= Society.techs.count ? "" : (zh ? Society.techs[i].2 : Society.techs[i].1) }
    /// 0...1 progress towards the next technology (1 when everything is known).
    public var researchProgress: Double { techCount >= Society.techs.count ? 1 : research / Society.techs[techCount].3 }
    /// Research points per second produced by the whole civilisation right now.
    public var researchRate: Double {
        var rate = 0.0
        for s in settlements.values where !s.abandoned {
            let adults = Double(s.members.count) * 0.7
            let boost = 1.0 + 0.6 * Double(s.count("school", done: true)) + 1.2 * Double(s.count("lab", done: true)) + 2.5 * Double(s.count("ai_center", done: true))
            rate += adults * 0.003 * boost
        }
        return rate
    }

    func advanceResearch(_ dt: Double) {
        guard techCount < Society.techs.count else { return }
        research += researchRate * dt
        while techCount < Society.techs.count && research >= Society.techs[techCount].3 {
            research -= Society.techs[techCount].3
            techCount += 1
            emit("tech", [techName(techCount - 1)], settlements.values.first { !$0.abandoned }?.center.center ?? .zero)
            for s in settlements.values { s.planT = 0 }
        }
    }

    /// Advanced manufacturing and AI change how a village works.
    func automation(_ s: Settlement, _ dt: Double) {
        let factories = Double(s.count("factory", done: true))
        if factories > 0 { s.wood += 0.03 * factories * dt; s.stone += 0.02 * factories * dt }
        if s.count("ai_center", done: true) > 0 {
            // AI-run farms: ripe wheat is harvested and replanted without anyone walking there
            s.aiAcc += dt
            if s.aiAcc >= 4 {
                s.aiAcc = 0
                for b in s.buildings where b.type == "farm" && b.done {
                    for dy in 0..<b.h { for dx in 0..<b.w where world.tile(2, b.x + dx, b.y + dy) == T["wheat_2"] {
                        world.setTile(2, b.x + dx, b.y + dy, T["wheat_0"]!)
                        s.food += 4
                    } }
                }
            }
        }
    }

    public let world: OpenWorld
    let content = Content.shared
    public var zh = false
    public var rng: RNG
    public private(set) var agents: [Int: Agent] = [:]
    public private(set) var settlements: [Int: Settlement] = [:]
    var nextID = 1, nextSID = 1, nextBID = 1
    public var minPopulation = 100
    public var stats = SocietyStats()
    public private(set) var log: [(t: Double, text: String)] = []
    public var onEvent: ((String, String, Vec2) -> Void)?
    var hourAcc = 0.0, migrAcc = 0.0
    var T: [String: UInt8] = [:]

    public init(world: OpenWorld, seed: Int) {
        self.world = world
        rng = RNG(seed: seed)
        for k in ["tree_oak", "rock", "berry_bush", "berry_bush_empty", "wheat_0", "wheat_2", "farmland", "campfire", "chest", "crate",
                  "cobble_road", "path", "grave", "cactus"] { T[k] = content.tid(k) }
        world.onTileChanged.append { [weak self] x, y, _, _, _ in
            guard let self = self else { return }
            let t = TilePos(x, y)
            for s in self.settlements.values where s.nav != nil && s.inArea(t) {
                s.nav!.solid[(y - s.origin.y) * Settlement.span + (x - s.origin.x)] = self.world.blocked(x, y)
            }
        }
    }

    public func tx(_ key: String, _ args: [String] = []) -> String {
        guard let p = Society.text[key] else { return key }
        var s = zh ? p.1 : p.0
        for a in args { if let r = s.range(of: "%@") { s.replaceSubrange(r, with: a) } }
        return s
    }

    func emit(_ key: String, _ args: [String], _ pos: Vec2) {
        let t = tx(key, args)
        log.append((world.time, t))
        if log.count > 60 { log.removeFirst() }
        onEvent?(key, t, pos)
    }

    public func trimLog(_ n: Int) { if log.count > n { log.removeFirst(log.count - n) } }

    // MARK: setup
    @discardableResult func newAgent(_ s: Settlement, age: Double, female: Bool) -> Agent {
        let a = Agent()
        a.id = nextID; nextID += 1
        let ni = rng.index(Society.namesEn.count), ci = rng.index(Society.clansEn.count)
        a.nameEn = Society.namesEn[ni]; a.nameZh = Society.namesZh[ni]
        a.clanEn = Society.clansEn[ci]; a.clanZh = Society.clansZh[ci]
        a.female = female
        a.birth = world.time - age * MP.year
        a.sid = s.id
        a.dil = rng.range(0.2, 1.0); a.soc = rng.range(0.2, 1.0)
        a.look.skin = Society.skins[rng.index(Society.skins.count)]
        a.look.hair = Society.hairs[rng.index(Society.hairs.count)]
        a.look.shirt = Society.shirts[rng.index(Society.shirts.count)]
        a.look.pants = Society.pantsList[rng.index(Society.pantsList.count)]
        a.look.style = rng.index(4)
        a.hunger = rng.range(0, 0.4); a.energy = rng.range(0.6, 1.0); a.social = rng.range(0, 0.6)
        a.thinkT = rng.unit() * 1.5
        let t = world.findFree(near: s.center + TilePos(rng.int(-5, 5), rng.int(2, 6)), maxR: 6)
        a.pos = t.center; a.prevPos = a.pos
        agents[a.id] = a
        s.members.append(a.id)
        return a
    }

    @discardableResult public func foundSettlement(_ center: TilePos) -> Settlement {
        let s = Settlement()
        s.id = nextSID; nextSID += 1
        let ni = (s.id - 1) % Society.townEn.count
        let suffix = s.id <= Society.townEn.count ? "" : " \(1 + (s.id - 1) / Society.townEn.count)"
        s.nameEn = Society.townEn[ni] + suffix; s.nameZh = Society.townZh[ni] + suffix
        s.center = center
        s.founded = world.time; s.lastFound = world.time
        settlements[s.id] = s
        attach(s)
        for dy in -2...2 { for dx in -2...2 {
            let x = center.x + dx, y = center.y + dy
            world.setTile(2, x, y, 0); world.setTile(3, x, y, 0)
            if world.isLand(x, y) && dx * dx + dy * dy <= 5 { world.setTile(1, x, y, T["cobble_road"]!) }
        } }
        world.setTile(2, center.x, center.y, T["campfire"]!)
        world.setTile(2, center.x - 2, center.y - 2, T["chest"]!)
        world.setTile(2, center.x + 2, center.y - 2, T["crate"]!)
        return s
    }

    func attach(_ s: Settlement) {
        let cx = s.center.x >> 5, cy = s.center.y >> 5
        s.origin = TilePos((cx - 1) * 32, (cy - 1) * 32)
        for dy in -1...1 { for dx in -1...1 { world.pin(cx + dx, cy + dy) } }
        let nav = PathGrid(size: Settlement.span)
        for y in 0..<Settlement.span { for x in 0..<Settlement.span {
            nav.solid[y * Settlement.span + x] = world.blocked(s.origin.x + x, s.origin.y + y)
        } }
        s.nav = nav
        s.resT = 0
    }

    func detach(_ s: Settlement) {
        let cx = s.center.x >> 5, cy = s.center.y >> 5
        for dy in -1...1 { for dx in -1...1 { world.unpin(cx + dx, cy + dy) } }
        s.nav = nil
    }

    public func bootstrap(origin: TilePos, villages: Int = 4, per: Int = 30) {
        var centers: [TilePos] = []
        for i in 0..<villages {
            let from = centers.isEmpty ? origin : centers[rng.index(centers.count)]
            var p = world.findSite(from: from, minR: centers.isEmpty ? 0 : 70, maxR: centers.isEmpty ? 40 : 140, salt: 900 + i * 7, avoid: centers, avoidDist: 64)
            if p.isNone { p = world.findSite(from: origin, minR: 0, maxR: 900, salt: 990 + i, avoid: centers, avoidDist: 64) }
            if p.isNone { continue }
            centers.append(p)
            let s = foundSettlement(p)
            s.food = Double(per) * 8; s.wood = 30; s.stone = 6
            var men: [Agent] = [], women: [Agent] = []
            for n in 0..<per {
                let r = rng.unit()
                let age = r < 0.22 ? rng.range(0, 13) : (r < 0.82 ? rng.range(16, 45) : rng.range(45, 72))
                let a = newAgent(s, age: age, female: n % 2 == 0)
                if age >= 20 && age < 50 { if a.female { women.append(a) } else { men.append(a) } }
            }
            for i2 in 0..<(min(men.count, women.count) / 2) { pair(men[i2], women[i2], announce: false) }
        }
    }

    // MARK: tick
    public func tick(_ dt: Double) {
        world.advance(dt)
        for s in settlements.values.sorted(by: { $0.id < $1.id }) where !s.abandoned {
            s.planT -= dt
            if s.planT <= 0 { s.planT = 6; plan(s) }
            if world.time >= s.resT { s.resT = world.time + 25; scan(s) }
            automation(s, dt)
        }
        advanceResearch(dt)
        for id in agents.keys.sorted() { if let a = agents[id], a.alive { update(a, dt) } }
        hourAcc += dt
        while hourAcc >= Society.hour { hourAcc -= Society.hour; hourly() }
        migrAcc += dt
        if migrAcc >= MP.year * 0.1 {
            migrAcc = 0
            immigration()
            for s in settlements.values where !s.abandoned { world.survey(center: TilePos(s.center.x >> 5, s.center.y >> 5), count: 24) }
            world.maintain()
        }
    }

    public var livingSettlements: Int { settlements.values.filter { !$0.abandoned }.count }

    // MARK: settlement brain
    func scan(_ s: Settlement) {
        var trees: [TilePos] = [], rocks: [TilePos] = [], berries: [TilePos] = []
        // resources nobody could reach are ignored for a while instead of being retried forever
        if world.time > s.unreachT { s.unreachable.removeAll(); s.unreachT = world.time + 600 }
        let inner = 6
        for y in inner..<(Settlement.span - inner) { for x in inner..<(Settlement.span - inner) {
            let wx = s.origin.x + x, wy = s.origin.y + y
            let o = world.tile(2, wx, wy)
            if o == 0 || s.unreachable.contains(TilePos(wx, wy)) { continue }
            if o == T["berry_bush"] { berries.append(TilePos(wx, wy)) }
            else if o == T["rock"] { rocks.append(TilePos(wx, wy)) }
            else if let t = content.tile(o), t.natural && (t.big || o == T["cactus"]) { trees.append(TilePos(wx, wy)) }
        } }
        s.trees = trees; s.rocks = rocks; s.berries = berries
        s.claims = s.claims.filter { agents[$0.value] != nil }
    }

    func footprintOK(_ s: Settlement, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Bool {
        if !s.inArea(TilePos(x - 2, y - 2)) || !s.inArea(TilePos(x + w + 2, y + h + 2)) { return false }
        for b in s.buildings where x - 1 < b.x + b.w && x + w + 1 > b.x && y - 1 < b.y + b.h && y + h + 1 > b.y { return false }
        for yy in (y - 1)...(y + h) { for xx in (x - 1)...(x + w) {
            if !world.isLand(xx, yy) { return false }
            let g = world.tile(0, xx, yy)
            if content.tile(g)?.built == true || g == T["farmland"] { return false }
            let o = world.tile(2, xx, yy)
            if o != 0, content.tile(o)?.natural == false { return false }
        } }
        return true
    }

    func freeSlot(_ s: Settlement, _ w: Int, _ h: Int) -> TilePos {
        var cands: [TilePos] = []
        for gy in -4...4 { for gx in -4...4 where gx != 0 || gy != 0 { cands.append(TilePos(gx, gy)) } }
        cands.sort { $0.lengthSquared != $1.lengthSquared ? $0.lengthSquared < $1.lengthSquared : ($0.y * 16 + $0.x) < ($1.y * 16 + $1.x) }
        for g in cands {
            let key = "\(g.x),\(g.y)"
            if s.usedSlots.contains(key) { continue }
            s.usedSlots.insert(key)
            let x = s.center.x + g.x * 9 - w / 2, y = s.center.y + g.y * 8 - h / 2
            if footprintOK(s, x, y, w, h) { return TilePos(x, y) }
        }
        return .none
    }

    @discardableResult func queue(_ s: Settlement, _ type: String) -> Bool {
        let b = Building()
        b.type = type
        var w = 6, h = type == "farm" ? 4 : 5
        if let spec = Society.roomSpecs[type] { w = spec.w; h = spec.h }
        var pos = TilePos(0, 0)
        if type == "well" {
            pos = s.center + TilePos(3, 3); w = 1; h = 1
            b.cells = [BuildCell(dx: 0, dy: 0, layer: 2, key: "", wood: 0, stone: 0), BuildCell(dx: 0, dy: 0, layer: 2, key: "well", wood: 0, stone: 8)]
        } else if type == "lights" {
            pos = s.center + TilePos(-4, -4); w = 9; h = 9
            for c in [(0, 0), (8, 0), (0, 8), (8, 8)] {
                b.cells.append(BuildCell(dx: c.0, dy: c.1, layer: 2, key: "", wood: 0, stone: 0))
                b.cells.append(BuildCell(dx: c.0, dy: c.1, layer: 2, key: "lantern_post", wood: 2, stone: 1))
            }
        } else {
            pos = freeSlot(s, w, h)
            if pos.isNone { return false }
            for dy in 0..<h { for dx in 0..<w {
                if world.tile(2, pos.x + dx, pos.y + dy) != 0 { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 2, key: "", wood: 0, stone: 0)) }
                if world.tile(3, pos.x + dx, pos.y + dy) != 0 { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 3, key: "", wood: 0, stone: 0)) }
            } }
        }
        if type == "farm" {
            for dy in 0..<h { for dx in 0..<w { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 0, key: "farmland", wood: 0, stone: 0)) } }
            for dy in 0..<h { for dx in 0..<w { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 2, key: "wheat_0", wood: 0, stone: 0)) } }
            b.door = pos + TilePos(w / 2, h)
        } else if type == "house" {
            b.cap = 4
            let stone = has("masonry") && s.stone > 24
            let wall = stone ? "wall_stone" : "wall_wood"
            let cx = pos.x + w / 2, cy = pos.y + h / 2
            var dd = TilePos(2, h - 1), out = TilePos(0, 1)
            if abs(s.center.y - cy) >= abs(s.center.x - cx) {
                if s.center.y < cy { dd = TilePos(2, 0); out = TilePos(0, -1) }
            } else {
                dd = s.center.x < cx ? TilePos(0, 2) : TilePos(w - 1, 2)
                out = s.center.x < cx ? TilePos(-1, 0) : TilePos(1, 0)
            }
            for dy in 1..<(h - 1) { for dx in 1..<(w - 1) { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 0, key: "wood_floor", wood: 0, stone: 0)) } }
            for dy in 0..<h { for dx in 0..<w where dx == 0 || dy == 0 || dx == w - 1 || dy == h - 1 {
                if TilePos(dx, dy) == dd { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 2, key: "door_wood", wood: 1, stone: 0)) }
                else { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 2, key: wall, wood: stone ? 0 : 1, stone: stone ? 1 : 0)) }
            } }
            let farY = dd.y == 0 && dd.x == 2 ? h - 2 : 1
            let farX = dd.x == 0 && dd.y == 2 ? w - 2 : 1
            b.cells.append(BuildCell(dx: farX, dy: farY, layer: 2, key: "bed", wood: 2, stone: 0))
            b.cells.append(BuildCell(dx: w - 1 - farX, dy: farY, layer: 2, key: "bed", wood: 2, stone: 0))
            b.door = pos + dd + out
        }
        if let spec = Society.roomSpecs[type] {
            // public buildings: a walled room facing the square with its signature equipment
            let dd = TilePos(w / 2, h - 1)
            for dy in 1..<(h - 1) { for dx in 1..<(w - 1) { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 0, key: spec.floor, wood: 0, stone: 0)) } }
            for dy in 0..<h { for dx in 0..<w where dx == 0 || dy == 0 || dx == w - 1 || dy == h - 1 {
                if TilePos(dx, dy) == dd { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 2, key: "door_wood", wood: 1, stone: 0)) }
                else { b.cells.append(BuildCell(dx: dx, dy: dy, layer: 2, key: spec.wall, wood: spec.wall == "wall_wood" ? 1 : 0, stone: spec.wall == "wall_wood" ? 0 : 1)) }
            } }
            for f in spec.items where f.0 < w - 1 && f.1 < h - 1 { b.cells.append(BuildCell(dx: f.0, dy: f.1, layer: 2, key: f.2, wood: 2, stone: 2)) }
            b.door = pos + dd + TilePos(0, 1)
        }
        b.id = nextBID; nextBID += 1
        b.x = pos.x; b.y = pos.y; b.w = w; b.h = h
        s.buildings.append(b)
        return true
    }

    struct RoomSpec { let w: Int, h: Int, wall: String, floor: String, items: [(Int, Int, String)] }
    static let roomSpecs: [String: RoomSpec] = [
        "school": RoomSpec(w: 6, h: 5, wall: "wall_stone", floor: "wood_floor", items: [(1, 1, "bookshelf"), (2, 2, "desk"), (4, 2, "desk")]),
        "workshop": RoomSpec(w: 6, h: 5, wall: "wall_wood", floor: "stone_floor", items: [(1, 1, "anvil"), (4, 1, "workbench"), (3, 2, "furnace")]),
        "factory": RoomSpec(w: 8, h: 6, wall: "wall_brick", floor: "stone_floor", items: [(1, 1, "chimney"), (3, 1, "machine"), (5, 1, "machine"), (2, 3, "machine"), (6, 3, "crate")]),
        "lab": RoomSpec(w: 6, h: 5, wall: "wall_stone", floor: "stone_floor", items: [(1, 1, "server"), (4, 1, "server"), (2, 2, "desk")]),
        "ai_center": RoomSpec(w: 8, h: 6, wall: "wall_stone", floor: "stone_floor", items: [(1, 1, "server"), (2, 1, "server"), (5, 1, "server"), (6, 1, "antenna"), (3, 3, "ai_core")]),
    ]

    /// Household id: couples share one, children belong to a parent's, everyone else has their own.
    func household(_ a: Agent, _ now: Double) -> Int {
        if a.age(now) < 16 {
            for pid in [a.mother, a.father] where pid != 0 {
                if let p = agents[pid], p.sid == a.sid { return household(p, now) }
            }
        }
        if a.partner != 0, let p = agents[a.partner], p.sid == a.sid { return min(a.id, p.id) }
        return a.id
    }

    func plan(_ s: Settlement) {
        let living = s.members.compactMap { agents[$0] }
        s.members = living.map { $0.id }
        if living.isEmpty {
            s.abandoned = true
            detach(s)
            emit("abandoned", [s.name(zh: zh)], s.center.center)
            return
        }
        let pop = living.count
        let now = world.time
        s.food = min(s.food, 40 + Double(pop) * 14)
        var workers = living.filter { $0.stage(now) == "adult" && !$0.travelling }
        // households: every family gets a house of its own
        var households: [Int: [Agent]] = [:]
        for a in living { households[household(a, now), default: []].append(a) }
        let houses = s.buildings.filter { $0.type == "house" }
        for b in houses where b.owner != nil && households[b.owner!] == nil { b.owner = nil; b.residents = [] }
        for hid in households.keys.sorted() {
            let members = households[hid]!
            var hb = houses.first { $0.owner == hid }
            if hb == nil, let free = houses.first(where: { $0.done && $0.owner == nil }) { free.owner = hid; hb = free }
            for m in members {
                let newHome = (hb?.done ?? false) ? hb!.id : -1
                if newHome >= 0 && m.home != newHome { m.think(now, "t_home") }
                m.home = newHome
            }
            hb?.residents = members.map { $0.id }
        }
        let open = s.buildings.filter { !$0.done }.count
        if open < 2 {
            let farmsWanted = Int((Double(pop) / (has("farming") ? 12 : 9)).rounded(.up))
            if s.count("farm") < farmsWanted && s.count("farm") * 3 <= s.count("house") { queue(s, "farm") }
            else if houses.count < households.count { queue(s, "house") }
            else if pop >= 14 && s.count("well") == 0 { queue(s, "well") }
            else if (pop >= 22 || has("electricity")) && s.count("lights") == 0 { queue(s, "lights") }
            else {
                for tb in Society.techBuildings where has(tb.0) && pop >= tb.2 && s.count(tb.1) == 0 { queue(s, tb.1); break }
            }
        }
        let n = workers.count
        let project = s.activeProject
        var needWood = 10.0, needStone = 4.0
        if let p = project, p.next < p.cells.count { for i in p.next..<p.cells.count { needWood += p.cells[i].wood; needStone += p.cells[i].stone } }
        var quota = ["builder": 0, "woodcutter": 0, "miner": 0, "farmer": 0, "forager": 0]
        if project != nil { quota["builder"] = min(5, max(1, 1 + n / 7)) }
        quota["woodcutter"] = min(n, max(1, Int(Double(n) * (s.wood < needWood ? 0.3 : 0.1))))
        quota["miner"] = min(n, max(0, Int(Double(n) * (s.stone < needStone ? 0.18 : 0.04))))
        quota["farmer"] = min(s.count("farm", done: true) * 2, Int(Double(n) * 0.4))
        if s.food < Double(pop) * 4 {
            quota["woodcutter"] = min(quota["woodcutter"]!, 1 + n / 10)
            quota["builder"] = min(quota["builder"]!, 2)
        }
        workers.sort { $0.id < $1.id }
        var pending: [Agent] = []
        for a in workers {
            if let q = quota[a.job], q > 0 { quota[a.job] = q - 1 } else { pending.append(a) }
        }
        for a in pending {
            a.job = s.food < Double(pop) * 8 ? "forager" : (s.wood < 80 ? "woodcutter" : (project != nil ? "builder" : "forager"))
            for j in ["builder", "farmer", "woodcutter", "miner"] where quota[j]! > 0 { quota[j]! -= 1; a.job = j; break }
        }
        for a in living where a.stage(now) != "adult" { a.job = "" }
        if pop >= 34 && now - s.lastFound > 1.5 * MP.year && livingSettlements < world.budget.maxSettlements && agents.count < world.budget.maxAgents {
            expedition(s, living)
        }
    }

    func expedition(_ s: Settlement, _ living: [Agent]) {
        s.lastFound = world.time
        let site = world.findSite(from: s.center, minR: 80, maxR: 170, salt: 2000 + nextSID * 13, avoid: settlements.values.map { $0.center }, avoidDist: 70)
        if site.isNone { return }
        var group: [Agent] = []
        let now = world.time
        func add(_ a: Agent) { if !group.contains(where: { $0 === a }) { group.append(a) } }
        for a in living {
            if group.count >= 9 { break }
            let age = a.age(now)
            if age < 17 || age > 42 || a.travelling || group.contains(where: { $0 === a }) { continue }
            add(a)
            if let p = agents[a.partner] { add(p) }
            for cid in a.children { if let c = agents[cid], c.age(now) < 14 { add(c) } }
        }
        if group.count < 5 { return }
        let ns = foundSettlement(site)
        let food = min(s.food * 0.3, Double(group.count) * 8), wood = min(s.wood * 0.3, 30)
        s.food -= food; s.wood -= wood
        ns.food = food + Double(group.count) * 3; ns.wood = wood + 10
        for a in group {
            leaveHome(a, s)
            s.members.removeAll { $0 == a.id }
            ns.members.append(a.id)
            a.sid = ns.id
            a.task = nil; a.path = []
            a.travelling = true
            a.travelTo = world.findFree(near: site + TilePos(rng.int(-4, 4), rng.int(2, 5)), maxR: 6).center
            a.think(now, "t_new_land", [ns.name(zh: zh)])
        }
        stats.founded += 1
        emit("founded", ["\(group.count)", s.name(zh: zh), ns.name(zh: zh)], site.center)
    }

    func leaveHome(_ a: Agent, _ s: Settlement) {
        if a.home >= 0, let b = s.building(a.home) { b.residents.removeAll { $0 == a.id } }
        a.home = -1
    }

    func immigration() {
        if agents.count >= minPopulation { return }
        guard let best = settlements.values.filter({ !$0.abandoned }).min(by: { $0.members.count != $1.members.count ? $0.members.count < $1.members.count : $0.id < $1.id }) else { return }
        let n = rng.int(3, 6)
        for i in 0..<n { newAgent(best, age: rng.range(17, 34), female: i % 2 == 0) }
        best.food += Double(n) * 6
        stats.immigrants += n
        emit("arrived", ["\(n)", best.name(zh: zh)], best.center.center)
    }

    // MARK: agent brain
    func update(_ a: Agent, _ dt: Double) {
        a.prevPos = a.pos
        a.moving = false
        guard let s = settlements[a.sid] else { return }
        a.hunger = min(1, a.hunger + dt / (0.45 * MP.daySeconds))
        a.social = min(1, a.social + dt / (0.6 * MP.daySeconds))
        a.grief = max(0, a.grief - dt / (1.5 * MP.year))
        if a.sleeping { a.energy = min(1, a.energy + dt / (0.3 * MP.daySeconds)) }
        else { a.energy = max(0, a.energy - dt / (0.75 * MP.daySeconds)) }
        if a.hunger >= 1 {
            a.health -= dt / (0.6 * MP.daySeconds)
            if a.health <= 0 { die(a, "hunger"); return }
        } else { a.health = min(1, a.health + dt / MP.daySeconds) }
        if a.travelling {
            let to = a.travelTo - a.pos
            let step = Society.speed * 1.2 * dt
            a.moving = true
            a.facing = to.normalized
            if to.length <= step { a.pos = a.travelTo; a.travelling = false } else { a.pos = a.pos + a.facing * step }
            return
        }
        if s.nav == nil { return }
        if a.task == nil {
            a.thinkT -= dt
            if a.thinkT > 0 { return }
            a.thinkT = 0.6 + rng.unit() * 0.8
            decide(a, s)
            if a.task == nil { return }
        }
        run(a, s, dt)
    }

    func standTile(_ s: Settlement, _ a: Agent, _ target: TilePos, beside: Bool) -> TilePos {
        if !beside && !world.blocked(target.x, target.y) { return target }
        var best = TilePos.none
        var bestD = Int.max
        let me = a.pos.tile
        for d in [(0, 1), (1, 0), (-1, 0), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
            let t = TilePos(target.x + d.0, target.y + d.1)
            if s.inArea(t) && !world.blocked(t.x, t.y) {
                let dd = (t - me).lengthSquared
                if dd < bestD { bestD = dd; best = t }
            }
        }
        return best
    }

    @discardableResult func go(_ a: Agent, _ s: Settlement, _ target: TilePos, _ act: String, _ dur: Double, bid: Int = 0, cell: Int = 0, beside: Bool = false) -> Bool {
        let stand = standTile(s, a, target, beside: beside)
        if stand.isNone || !s.inArea(stand) { return false }
        var from = a.pos.tile
        if !s.inArea(from) || world.blocked(from.x, from.y) {
            from = world.findFree(near: s.center + TilePos(0, 3), maxR: 8)
            a.pos = from.center
        }
        let ids = s.nav!.path(from: from - s.origin, to: stand - s.origin)
        if ids.isEmpty { Society.failActs[act, default: 0] += 1; return false }
        a.path = ids.map { ($0 + s.origin).center }
        a.pathI = 1
        a.task = AgentTask(act: act, target: target, dur: dur, bid: bid, cell: cell)
        return true
    }

    func decide(_ a: Agent, _ s: Settlement) {
        let now = world.time
        let st = a.stage(now)
        a.sleeping = false
        if a.carryN > 0, go(a, s, s.center, "deliver", 0.4) { return }
        if a.hunger > 0.55 {
            if s.food >= 1 {
                if go(a, s, s.center, "eat", 1.5) { return }
                if a.hunger > 0.85 { s.food -= 1; a.hunger -= 0.6; return }
            } else if st != "child", work(a, s, "forager") { a.think(now, "t_hungry"); return }
        }
        if (world.isNight && a.energy < 0.85) || a.energy < 0.15 {
            var spot = s.center + TilePos(a.id % 5 - 2, 3 + a.id % 2)
            if a.home >= 0, let hb = s.building(a.home), hb.done { spot = TilePos(hb.x + 2 + a.id % 2, hb.y + 2) }
            if go(a, s, spot, "sleep", 9999) { return }
        }
        if st == "child" { wander(a, s, 7, "play"); return }
        let h = world.hour
        if a.social > 0.7 || (h > 17 && a.social > 0.35) || (st == "elder" && rng.unit() < 0.5) {
            if go(a, s, s.center + TilePos(rng.int(-4, 4), rng.int(-4, 4)), "social", 3) { return }
        }
        if st == "adult" && !a.job.isEmpty && work(a, s, a.job) { return }
        if st == "elder" && rng.unit() < 0.4 && work(a, s, "forager") { return }
        wander(a, s, 6, "idle")
    }

    func wander(_ a: Agent, _ s: Settlement, _ radius: Int, _ act: String) {
        var base = s.center
        if a.home >= 0, let hb = s.building(a.home) { base = hb.door }
        for _ in 0..<4 {
            let t = base + TilePos(rng.int(-radius, radius), rng.int(-radius, radius))
            if s.inArea(t) && !world.blocked(t.x, t.y) && go(a, s, t, act, rng.range(1, 3)) { return }
        }
    }

    func nearest(_ a: Agent, _ s: Settlement, _ list: [TilePos], _ valid: (TilePos) -> Bool) -> TilePos {
        if list.isEmpty { return .none }
        var best = TilePos.none
        var bestD = Int.max
        let me = a.pos.tile
        let n = list.count
        let start = rng.index(n)
        for k in 0..<min(n, 40) {
            let t = list[(start + k * 7) % n]
            if s.claims[t] != nil || !valid(t) { continue }
            let d = (t - me).lengthSquared
            if d < bestD { bestD = d; best = t }
        }
        return best
    }

    func isTree(_ p: TilePos) -> Bool {
        let o = world.tile(2, p.x, p.y)
        return o != 0 && (content.tile(o)?.big == true || o == T["cactus"])
    }

    func work(_ a: Agent, _ s: Settlement, _ job: String) -> Bool {
        switch job {
        case "builder":
            guard let b = s.activeProject else { return work(a, s, "woodcutter") }
            var idx = -1
            if !b.retry.isEmpty { idx = b.retry.removeLast() } else if b.next < b.cells.count { idx = b.next }
            if idx < 0 { return false }
            var cell = b.cells[idx]
            if s.wood < cell.wood && s.stone >= cell.wood + cell.stone + 2 {
                // no timber left: build this piece from stone instead
                cell.stone += cell.wood
                cell.wood = 0
                if cell.key == "wall_wood" { cell.key = "wall_stone" }
                b.cells[idx] = cell
            }
            if s.wood < cell.wood || s.stone < cell.stone {
                if idx != b.next { b.retry.append(idx) }
                return work(a, s, s.wood < cell.wood ? "woodcutter" : "miner")
            }
            let target = TilePos(b.x + cell.dx, b.y + cell.dy)
            let solid = !cell.key.isEmpty && content.solid[Int(content.tid(cell.key))]
            if !go(a, s, target, "build", has("machinery") ? 0.5 : 1.2, bid: b.id, cell: idx, beside: solid) {
                if idx != b.next { b.retry.append(idx) } else { b.next = idx + 1; b.retry.insert(idx, at: 0) }
                return false
            }
            if idx == b.next { b.next = idx + 1 }
            s.wood -= cell.wood; s.stone -= cell.stone
            return true
        case "woodcutter":
            let t = nearest(a, s, s.trees, isTree)
            if !t.isNone {
                if go(a, s, t, "chop", 5) { s.claims[t] = a.id; return true }
                s.trees.removeAll { $0 == t }       // unreachable (e.g. across water)
                s.unreachable.insert(t)
            } else if s.trees.count < 12 {
                // forestry: plant saplings around the village so timber never runs out for good
                for _ in 0..<6 {
                    let ang = rng.unit() * 2 * Double.pi, rad = rng.range(12, 30)
                    let p = TilePos(s.center.x + Int(cos(ang) * rad), s.center.y + Int(sin(ang) * rad))
                    if !s.inArea(p) || s.claims[p] != nil || !world.isLand(p.x, p.y) || world.tile(2, p.x, p.y) != 0 || world.tile(1, p.x, p.y) != 0 { continue }
                    let g = world.tile(0, p.x, p.y)
                    if content.tile(g)?.built == true || g == T["farmland"] { continue }
                    if s.buildings.contains(where: { p.x >= $0.x - 1 && p.x <= $0.x + $0.w && p.y >= $0.y - 1 && p.y <= $0.y + $0.h }) { continue }
                    if go(a, s, p, "plant", 2) { s.claims[p] = a.id; return true }
                }
            }
        case "miner":
            let t = nearest(a, s, s.rocks) { self.world.tile(2, $0.x, $0.y) == self.T["rock"] }
            if !t.isNone {
                if go(a, s, t, "mine", 6) { s.claims[t] = a.id; return true }
                s.rocks.removeAll { $0 == t }
                s.unreachable.insert(t)
            }
        case "farmer":
            for b in s.buildings where b.type == "farm" && b.done {
                for dy in 0..<b.h { for dx in 0..<b.w {
                    let t = TilePos(b.x + dx, b.y + dy)
                    if s.claims[t] != nil { continue }
                    let o = world.tile(2, t.x, t.y)
                    if (o == T["wheat_2"] || o == 0) && go(a, s, t, o != 0 ? "reap" : "sow", 2) { s.claims[t] = a.id; return true }
                } }
            }
            return work(a, s, "forager")
        case "forager":
            let t = nearest(a, s, s.berries) { self.world.tile(2, $0.x, $0.y) == self.T["berry_bush"] }
            if !t.isNone {
                if go(a, s, t, "forage", 3) { s.claims[t] = a.id; return true }
                s.berries.removeAll { $0 == t }
                s.unreachable.insert(t)
            }
            if s.wood < 60 { return work(a, s, "woodcutter") }
            if s.stone < 30 { return work(a, s, "miner") }
        default: break
        }
        return false
    }

    func abort(_ a: Agent, _ s: Settlement) {
        if let t = a.task {
            s.claims[t.target] = nil
            if t.act == "build", let b = s.building(t.bid) {
                b.retry.append(t.cell)
                s.wood += b.cells[t.cell].wood; s.stone += b.cells[t.cell].stone
            }
        }
        a.task = nil; a.path = []; a.sleeping = false
    }

    func run(_ a: Agent, _ s: Settlement, _ dt: Double) {
        guard var task = a.task else { return }
        if task.stage == 0 {
            var budget = Society.speed * dt * (a.stage(world.time) != "adult" ? 0.75 : 1.0) * (0.6 + 0.4 * a.health)
            while budget > 0 && a.pathI < a.path.count {
                let wp = a.path[a.pathI]
                let to = wp - a.pos
                let d = to.length
                if d <= budget { a.pos = wp; budget -= d; a.pathI += 1 }
                else { a.facing = to * (1 / d); a.pos = a.pos + a.facing * budget; budget = 0 }
                a.moving = true
            }
            if a.pathI < a.path.count { return }
            task.stage = 1
            let look = task.target.center - a.pos
            if look.length > 1 { a.facing = look.normalized }
            if task.act == "sleep" { a.sleeping = true }
        }
        task.t += dt * (0.7 + 0.6 * a.dil)
        a.task = task
        if task.act == "sleep" {
            if (a.energy >= 0.98 && !world.isNight) || a.hunger > 0.9 { a.sleeping = false; a.task = nil }
            return
        }
        if task.t < task.dur { return }
        finish(a, s, task)
    }

    func finish(_ a: Agent, _ s: Settlement, _ task: AgentTask) {
        let t = task.target
        let now = world.time
        s.claims[t] = nil
        a.task = nil
        switch task.act {
        case "eat":
            if s.food >= 1 { s.food -= 1; a.hunger = max(0, a.hunger - 0.6); if rng.unit() < 0.2 { a.think(now, "t_ate") } }
        case "deliver":
            if !a.carryKind.isEmpty { s.addStock(a.carryKind, a.carryN) }
            a.carryKind = ""; a.carryN = 0
        case "chop":
            let o = world.tile(2, t.x, t.y)
            if o != 0, let td = content.tile(o), td.big || o == T["cactus"] {
                world.setTile(2, t.x, t.y, content.tid(td.after))
                a.carryKind = "wood"; a.carryN = (has("metalwork") ? 5 : 3) - (td.big ? 0 : 1)
                s.trees.removeAll { $0 == t }
                if rng.unit() < 0.15 { a.think(now, "t_work_woodcutter") }
            }
        case "mine":
            if world.tile(2, t.x, t.y) == T["rock"] {
                world.setTile(2, t.x, t.y, 0)
                world.schedule(t.x, t.y, layer: 2, to: T["rock"]!, delay: 700, expect: 0)
                a.carryKind = "stone"; a.carryN = has("metalwork") ? 5 : 3
                if rng.unit() < 0.15 { a.think(now, "t_work_miner") }
            }
        case "forage":
            if world.tile(2, t.x, t.y) == T["berry_bush"] {
                world.setTile(2, t.x, t.y, T["berry_bush_empty"]!)
                a.carryKind = "food"; a.carryN = 3
                if rng.unit() < 0.15 { a.think(now, "t_work_forager") }
            }
        case "reap":
            if world.tile(2, t.x, t.y) == T["wheat_2"] {
                world.setTile(2, t.x, t.y, T["wheat_0"]!)
                a.carryKind = "food"; a.carryN = has("farming") ? 6 : 4
                if rng.unit() < 0.15 { a.think(now, "t_work_farmer") }
            }
        case "plant":
            if world.tile(2, t.x, t.y) == 0 && world.isLand(t.x, t.y) {
                world.setTile(2, t.x, t.y, content.tid("sapling"))
                world.setTile(3, t.x, t.y, 0)
            }
        case "sow":
            if world.tile(2, t.x, t.y) == 0 && world.tile(0, t.x, t.y) == T["farmland"] { world.setTile(2, t.x, t.y, T["wheat_0"]!) }
        case "build": buildCell(a, s, task)
        default: socialize(a, s)
        }
    }

    func occupied(_ t: TilePos, except: Agent) -> Bool {
        for o in agents.values where o !== except && o.pos.tile == t { return true }
        return false
    }

    func buildCell(_ a: Agent, _ s: Settlement, _ task: AgentTask) {
        guard let b = s.building(task.bid) else { return }
        let cell = b.cells[task.cell]
        let t = TilePos(b.x + cell.dx, b.y + cell.dy)
        let id = cell.key.isEmpty ? UInt8(0) : content.tid(cell.key)
        if id != 0 && content.solid[Int(id)] && (occupied(t, except: a) || a.pos.tile == t) {
            b.retry.insert(task.cell, at: 0)
            s.wood += cell.wood; s.stone += cell.stone
            return
        }
        if id == 0 && cell.layer == 2 {
            let old = world.tile(2, t.x, t.y)
            if old != 0 { if content.tile(old)?.big == true { s.wood += 2 } else if old == T["rock"] { s.stone += 2 } }
        }
        world.setTile(cell.layer, t.x, t.y, id)
        stats.tilesPlaced += 1
        b.placed += 1
        if rng.unit() < 0.05 { a.think(world.time, "t_work_builder") }
        if b.placed >= b.cells.count {
            b.done = true
            stats.buildings += 1
            if b.type != "well" && b.type != "lights" { layPath(s, b.door) }
            for id2 in s.members { if let m = agents[id2], m.job == "builder" { m.think(world.time, "t_built", [tx(b.type)]) } }
            emit("built", [s.name(zh: zh), tx(b.type)], TilePos(b.x, b.y).center)
            s.planT = 0
        }
    }

    func layPath(_ s: Settlement, _ from: TilePos) {
        var p = from
        var guardN = 0
        while p != s.center && guardN < 200 {
            guardN += 1
            if world.isLand(p.x, p.y) && world.tile(2, p.x, p.y) == 0 && world.tile(1, p.x, p.y) == 0 {
                let g = world.tile(0, p.x, p.y)
                if content.tile(g)?.built != true && g != T["farmland"] {
                    world.setTile(1, p.x, p.y, T["path"]!)
                    world.setTile(3, p.x, p.y, 0)
                }
            }
            if abs(s.center.x - p.x) > abs(s.center.y - p.y) { p.x += (s.center.x - p.x).signum() } else { p.y += (s.center.y - p.y).signum() }
        }
    }

    // MARK: social life
    func related(_ a: Agent, _ b: Agent) -> Bool {
        if a.mother == b.id || a.father == b.id || b.mother == a.id || b.father == a.id { return true }
        if a.mother != 0 && a.mother == b.mother { return true }
        return a.father != 0 && a.father == b.father
    }

    func socialize(_ a: Agent, _ s: Settlement) {
        var best: Agent?
        var bestD = 56.0
        for id in s.members where id != a.id {
            guard let o = agents[id], !o.travelling, !o.sleeping else { continue }
            let d = o.pos.distance(to: a.pos)
            if d < bestD { bestD = d; best = o }
        }
        guard let b = best else { return }
        let now = world.time
        var chem = 0.06 + 0.1 * a.soc * b.soc + rng.range(-0.05, 0.08)
        if rng.unit() < 0.07 { chem = -0.2; a.think(now, "t_quarrel", [zh ? b.nameZh : b.nameEn]) }
        else if rng.unit() < 0.3 { a.think(now, "t_chat", [zh ? b.nameZh : b.nameEn]) }
        a.rel[b.id] = min(1, max(-1, (a.rel[b.id] ?? 0) + chem))
        b.rel[a.id] = min(1, max(-1, (b.rel[a.id] ?? 0) + chem))
        a.social = max(0, a.social - 0.5); b.social = max(0, b.social - 0.3)
        if a.partner == 0 && b.partner == 0 && a.female != b.female && !related(a, b) {
            let aa = a.age(now), ab = b.age(now)
            if aa >= 18 && ab >= 18 && abs(aa - ab) < 16 && (a.rel[b.id] ?? 0) > 0.45 && (b.rel[a.id] ?? 0) > 0.45 { pair(a, b, announce: true) }
        }
    }

    func pair(_ a: Agent, _ b: Agent, announce: Bool) {
        a.partner = b.id; b.partner = a.id
        a.rel[b.id] = max(0.8, a.rel[b.id] ?? 0); b.rel[a.id] = max(0.8, b.rel[a.id] ?? 0)
        stats.pairs += 1
        guard announce, let s = settlements[a.sid] else { return }
        a.think(world.time, "t_love", [zh ? b.nameZh : b.nameEn])
        b.think(world.time, "t_love", [zh ? a.nameZh : a.nameEn])
        for (has, joins) in [(a, b), (b, a)] where has.home >= 0 && joins.sid == has.sid {
            if let hb = s.building(has.home), hb.residents.count < hb.cap {
                leaveHome(joins, s)
                joins.home = has.home
                hb.residents.append(joins.id)
                break
            }
        }
        emit("paired", [a.name(zh: zh), b.name(zh: zh)], a.pos)
    }

    func hourly() {
        let now = world.time
        let dty = Society.hour / MP.year
        let crowd = min(1, max(0, 1 - Double(agents.count) / Double(world.budget.maxAgents)))
        for id in agents.keys.sorted() {
            guard let a = agents[id] else { continue }
            let age = a.age(now)
            var hazard = 0.004
            if age > 55 { hazard += 0.02 * exp((age - 55) / 8) }
            if age < 3 { hazard += 0.01 }
            if rng.unit() < hazard * dty { die(a, age > 55 ? "old" : "ill"); continue }
            if !a.female { continue }
            if a.pregnantDue > 0 { if now >= a.pregnantDue { birth(a) }; continue }
            guard a.partner != 0, let p = agents[a.partner], age >= 18, age <= 43, !a.travelling, let s = settlements[a.sid] else { continue }
            if p.sid != a.sid || now - a.lastBirth < 1.2 * MP.year || a.children.count >= 6 { continue }
            let fed = s.food >= Double(s.members.count) * 2.5 && a.hunger < 0.7
            let boost = agents.count < minPopulation ? 2.5 : 1.0
            if fed && rng.unit() < 0.75 * dty * crowd * boost * (a.home >= 0 ? 1.0 : 0.35) {
                a.pregnantDue = now + 0.7 * MP.year
                a.birthFather = p.id
            }
        }
    }

    func birth(_ m: Agent) {
        guard let s = settlements[m.sid] else { return }
        m.pregnantDue = -1
        m.lastBirth = world.time
        let c = newAgent(s, age: 0, female: rng.unit() < 0.5)
        let f = agents[m.birthFather]
        c.mother = m.id
        c.father = f?.id ?? 0
        c.clanEn = f?.clanEn ?? m.clanEn; c.clanZh = f?.clanZh ?? m.clanZh
        c.pos = m.pos; c.prevPos = m.pos
        c.hunger = 0.1
        m.children.append(c.id)
        m.think(world.time, "t_child", [zh ? c.nameZh : c.nameEn])
        if let f = f {
            f.children.append(c.id)
            f.think(world.time, "t_child", [zh ? c.nameZh : c.nameEn])
            c.dil = min(1, max(0.05, (m.dil + f.dil) / 2 + rng.range(-0.15, 0.15)))
            c.soc = min(1, max(0.05, (m.soc + f.soc) / 2 + rng.range(-0.15, 0.15)))
            c.look.skin = (rng.unit() < 0.5 ? m : f).look.skin
            c.look.hair = (rng.unit() < 0.5 ? m : f).look.hair
        }
        if m.home >= 0, let hb = s.building(m.home) { c.home = m.home; hb.residents.append(c.id) }
        stats.births += 1
        emit("born", [c.name(zh: zh), s.name(zh: zh)], c.pos)
    }

    func die(_ a: Agent, _ cause: String) {
        guard a.alive, let s = settlements[a.sid] else { return }
        a.alive = false
        abort(a, s)
        leaveHome(a, s)
        s.members.removeAll { $0 == a.id }
        agents[a.id] = nil
        stats.deaths += 1
        if cause == "old" { stats.old += 1 } else if cause == "hunger" { stats.hunger += 1 } else { stats.ill += 1 }
        for rid in [a.partner, a.mother, a.father] + a.children where rid != 0 {
            if let r = agents[rid] {
                r.grief = 1
                r.think(world.time, "t_grief", [zh ? a.nameZh : a.nameEn])
                if r.partner == a.id { r.partner = 0 }
            }
        }
        if s.nav != nil && s.graves < 24 {
            let g = s.center + TilePos(-8 - s.graves % 6, 6 + s.graves / 6)
            if s.inArea(g) && world.isLand(g.x, g.y) && world.tile(2, g.x, g.y) == 0 && !occupied(g, except: a) { world.setTile(2, g.x, g.y, T["grave"]!) }
            s.graves += 1
        }
        emit(cause == "old" ? "died_old" : (cause == "hunger" ? "died_hunger" : "died_ill"), [a.name(zh: zh), "\(Int(a.age(world.time)))"], a.pos)
    }

    // MARK: player interaction
    public func agent(near pos: Vec2, radius: Double = 20) -> Agent? {
        var best: Agent?
        var bestD = radius
        for a in agents.values { let d = a.pos.distance(to: pos); if d < bestD { bestD = d; best = a } }
        return best
    }

    /// Which villagers to draw and which to summarise. At most `limit` villagers
    /// (nearest to `center` first, never the ones asleep indoors) are shown as
    /// characters; everybody else in view is counted on the building they belong
    /// to (their home, else the village square), so nobody silently disappears.
    public func crowdSplit(center: Vec2, halfW: Double, halfH: Double, limit: Int = 50) -> (shown: [Agent], badges: [TilePos: Int]) {
        var candidates: [(Double, Agent)] = []
        var badges: [TilePos: Int] = [:]
        func anchor(_ a: Agent) -> TilePos {
            guard let s = settlements[a.sid] else { return a.pos.tile }
            if a.home >= 0, let b = s.building(a.home) { return TilePos(b.x + b.w / 2, b.y) }
            return s.center
        }
        for a in agents.values {
            let inside = a.sleeping && a.home >= 0
            let dx = abs(a.pos.x - center.x), dy = abs(a.pos.y - center.y)
            if inside {
                let t = anchor(a)
                if abs(Double(t.x * 16) - center.x) <= halfW + 48 && abs(Double(t.y * 16) - center.y) <= halfH + 48 { badges[t, default: 0] += 1 }
                continue
            }
            if dx > halfW || dy > halfH { continue }
            candidates.append((dx * dx + dy * dy, a))
        }
        candidates.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.id < $1.1.id }
        var shown: [Agent] = []
        for (i, c) in candidates.enumerated() {
            if i < limit { shown.append(c.1) } else { badges[anchor(c.1), default: 0] += 1 }
        }
        return (shown, badges)
    }

    public func jobLabel(_ a: Agent) -> String {
        let st = a.stage(world.time)
        return st != "adult" ? tx("job_" + st) : tx("job_" + a.job)
    }

    public struct TalkInfo {
        public var name = "", age = 0, female = false, job = "", mood = 0.0, hunger = 0.0, energy = 0.0, settlement = "", line = ""
        public var thoughts: [String] = [], family: [String] = [], pregnant = false, stock = ""
    }

    /// Talk to a villager: the answer comes from their own current situation.
    public func talk(_ id: Int, speak: Bool = true) -> TalkInfo? {
        guard let a = agents[id], let s = settlements[a.sid] else { return nil }
        let now = world.time
        var info = TalkInfo()
        if speak {
            a.rel[0] = min(1, (a.rel[0] ?? 0) + 0.05)
            a.social = max(0, a.social - 0.3)
            if !a.sleeping && !a.travelling { abort(a, s); a.thinkT = 3 }
        }
        let age = Int(a.age(now))
        var line = (a.rel[0] ?? 0) > 0.4 ? tx("s_friend") : tx("s_hello")
        if a.stage(now) == "child" { line = tx("s_child", ["\(age)"]) }
        else if a.hunger > 0.75 { line = tx("s_hungry") }
        else if a.grief > 0.5 { line = tx("s_grief") }
        else if a.pregnantDue > 0 || (agents[a.partner]?.pregnantDue ?? -1) > 0 { line = tx("s_preg") }
        else if a.energy < 0.2 { line = tx("s_tired") }
        else if a.home < 0 { line = tx("s_nohome") }
        else if a.stage(now) == "elder" { line = tx("s_elder", ["\(age)"]) }
        else if a.id % 2 == 0 { line = tx("s_town", [s.name(zh: zh), "\(s.members.count)", "\(s.count("house", done: true))"]) }
        info.name = a.name(zh: zh); info.age = age; info.female = a.female; info.job = jobLabel(a)
        info.mood = a.mood; info.hunger = a.hunger; info.energy = a.energy; info.settlement = s.name(zh: zh); info.line = line
        info.thoughts = a.thoughts.suffix(3).map { tx($0.k, $0.a) }
        if let p = agents[a.partner] { info.family.append("♥ " + p.name(zh: zh)) }
        for cid in a.children { if let c = agents[cid] { info.family.append("· \(c.name(zh: zh)) (\(Int(c.age(now))))") } }
        info.pregnant = a.pregnantDue > 0
        info.stock = zh ? "粮 \(Int(s.food)) · 木 \(Int(s.wood)) · 石 \(Int(s.stone))" : "food \(Int(s.food)) · wood \(Int(s.wood)) · stone \(Int(s.stone))"
        return info
    }

    @discardableResult public func giftFood(_ id: Int) -> Bool {
        guard let a = agents[id] else { return false }
        a.hunger = max(0, a.hunger - 0.6)
        a.rel[0] = min(1, (a.rel[0] ?? 0) + 0.2)
        a.think(world.time, "t_gift")
        return true
    }

    // MARK: persistence
    public struct Snapshot: Codable {
        var agents: [Agent], settlements: [Settlement], nextID: Int, nextSID: Int, nextBID: Int, stats: SocietyStats, rng: RNG
        var techCount: Int?, research: Double?
    }

    public func snapshot() -> Snapshot {
        Snapshot(agents: agents.values.sorted { $0.id < $1.id }, settlements: settlements.values.sorted { $0.id < $1.id },
                 nextID: nextID, nextSID: nextSID, nextBID: nextBID, stats: stats, rng: rng, techCount: techCount, research: research)
    }

    public func restore(_ s: Snapshot) {
        agents.removeAll(); settlements.removeAll()
        for st in s.settlements { settlements[st.id] = st; if !st.abandoned { attach(st) } }
        for a in s.agents where settlements[a.sid] != nil { a.prevPos = a.pos; agents[a.id] = a }
        nextID = s.nextID; nextSID = s.nextSID; nextBID = s.nextBID; stats = s.stats; rng = s.rng
        techCount = min(Society.techs.count, s.techCount ?? 0); research = s.research ?? 0
    }
}
