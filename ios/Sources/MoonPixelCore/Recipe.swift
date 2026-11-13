import Foundation

/// A world described in one sentence ("a snowy island world with 200 people in
/// the industrial age"). `parse` reads climate, size, population, era and name
/// out of free text in Chinese or English; everything not mentioned keeps its
/// default. The analysis runs on the device and is fully deterministic.
public struct WorldRecipe: Codable, Equatable {
    public var prompt = ""
    public var name = ""
    public var seed = 1
    public var tempBias = 0.0, moistBias = 0.0, elevBias = 0.0
    public var villages = 4, perVillage = 30
    public var startTech = 0
    public var minPopulation = 100
    /// Keys of what was recognised, in order (e.g. "desert", "island", "era:5").
    public var tags: [String] = []
    public init() {}

    static let climates: [(key: String, words: [String], t: Double, m: Double, e: Double, zh: String, en: String)] = [
        ("desert", ["沙漠", "荒漠", "戈壁", "炎热", "酷热", "desert", "dune", "arid", "scorching"], 0.26, -0.18, 0.02, "沙漠", "Desert"),
        ("snow", ["雪", "冰", "寒", "冬", "极地", "北极", "南极", "snow", "ice", "frozen", "winter", "arctic", "polar", "cold"], -0.27, 0.0, 0.0, "冰雪", "Snow"),
        ("forest", ["森林", "丛林", "雨林", "树林", "林海", "forest", "jungle", "woods", "rainforest"], 0.0, 0.16, 0.02, "森林", "Forest"),
        ("grass", ["草原", "平原", "田园", "牧场", "grassland", "plains", "prairie", "meadow", "pastoral"], 0.0, -0.07, 0.0, "草原", "Plains"),
        ("wetland", ["沼泽", "湿地", "水乡", "swamp", "marsh", "wetland"], 0.0, 0.2, -0.03, "湿地", "Wetland"),
        ("island", ["岛", "海洋", "大海", "海边", "群岛", "island", "archipelago", "ocean", "sea "], 0.0, 0.03, -0.075, "海岛", "Islands"),
        ("mountain", ["山", "高原", "峡谷", "mountain", "highland", "alpine", "canyon"], 0.0, 0.0, 0.07, "山地", "Mountains"),
        ("warm", ["温暖", "热带", "夏", "warm", "tropical", "summer"], 0.12, 0.05, 0.0, "温暖", "Warm"),
    ]
    static let eras: [(tech: Int, words: [String], zh: String, en: String)] = [
        (9, ["人工智能", "ai", "未来", "科幻", "赛博", "机器人", "future", "futuristic", "sci-fi", "scifi", "cyber", "robot"], "人工智能时代", "AI age"),
        (8, ["信息时代", "计算机", "电脑", "互联网", "computer", "information age", "digital"], "信息时代", "Information age"),
        (7, ["现代", "当代", "都市", "制造", "modern", "contemporary", "manufactur"], "现代", "Modern age"),
        (6, ["电气", "电力", "electric"], "电气时代", "Electric age"),
        (5, ["工业", "蒸汽", "机械", "industrial", "steam", "machine"], "工业时代", "Industrial age"),
        (4, ["铁器", "冶金", "青铜", "iron age", "bronze", "metal"], "金属时代", "Metal age"),
        (3, ["中世纪", "古代", "王国", "古风", "武侠", "medieval", "ancient", "kingdom", "feudal"], "古代", "Ancient age"),
        (1, ["农耕", "农业", "farming", "agricultur"], "农耕时代", "Farming age"),
        (0, ["原始", "石器", "部落", "蛮荒", "stone age", "primitive", "tribal", "tribe"], "原始时代", "Stone age"),
    ]

    public static func parse(_ text: String, defaultSeed: Int? = nil) -> WorldRecipe {
        var r = WorldRecipe()
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        r.prompt = raw
        let s = " " + raw.lowercased() + " "
        // climate / terrain
        for c in climates where c.words.contains(where: { s.contains($0) }) {
            r.tempBias += c.t; r.moistBias += c.m; r.elevBias += c.e
            r.tags.append(c.key)
        }
        r.tempBias = min(0.3, max(-0.3, r.tempBias)); r.moistBias = min(0.24, max(-0.22, r.moistBias)); r.elevBias = min(0.08, max(-0.08, r.elevBias))
        // era: the first (most advanced) match wins; "ai" must be a whole word
        for e in eras {
            let hit = e.words.contains { w in
                if w == "ai" { return wholeWord(s, "ai") }
                return s.contains(w)
            }
            if hit { r.startTech = e.tech; r.tags.append("era:\(e.tech)"); break }
        }
        // numbers: "200 人", "6 个村庄", "seed 42"
        var people: Int?, vill: Int?
        for (n, after, before) in numbers(s) {
            if ["种子", "seed"].contains(where: { before.hasSuffix($0) || before.hasSuffix($0 + " ") || before.hasSuffix($0 + ":") || before.hasSuffix($0 + "：") }) { r.seed = n; r.tags.append("seed"); continue }
            let a = after.drop(while: { $0 == " " || $0 == "个" || $0 == "座" || $0 == "名" || $0 == "位" })
            if ["村", "镇", "城", "部落", "聚落", "village", "town", "settlement", "cit", "tribe"].contains(where: { a.hasPrefix($0) }) { vill = n }
            else if ["人", "居民", "村民", "npc", "people", "villager", "person", "citizen", "inhabitant", "pop"].contains(where: { a.hasPrefix($0) }) { people = n }
        }
        if vill == nil {
            if ["巨大", "庞大", "很大", "超大", "大型", "huge", "big", "large", "vast", "giant"].contains(where: { s.contains($0) }) { vill = 7; r.tags.append("big") }
            else if ["小", "迷你", "tiny", "small", "little", "cozy"].contains(where: { s.contains($0) }) && people == nil { vill = 2; r.tags.append("small") }
            else if ["孤独", "独自", "一个村", "lonely", "single village", "one village"].contains(where: { s.contains($0) }) { vill = 1 }
        }
        if let p = people {
            let total = min(600, max(4, p))
            let v = vill ?? min(8, max(1, Int((Double(total) / 30).rounded())))
            r.villages = min(10, max(1, v))
            r.perVillage = min(80, max(2, Int((Double(total) / Double(r.villages)).rounded())))
            r.tags.append("people")
        } else if let v = vill {
            r.villages = min(10, max(1, v))
        }
        if vill != nil { r.tags.append("villages") }
        // three nations need three towns to stand on
        if r.villages < 3 { let total = r.villages * r.perVillage; r.villages = 3; r.perVillage = min(80, max(2, Int((Double(total) / 3).rounded()))) }
        r.minPopulation = max(10, min(600, r.villages * r.perVillage * 5 / 6))
        if !r.tags.contains("seed") { r.seed = defaultSeed ?? stableSeed(raw) }
        r.name = quotedName(raw) ?? ""
        return r
    }

    public var population: Int { villages * perVillage }

    /// Short readable labels of what the analysis understood.
    public func summary(zh: Bool) -> [String] {
        var out: [String] = []
        let cl = WorldRecipe.climates.filter { tags.contains($0.key) }.map { zh ? $0.zh : $0.en }
        out.append(cl.isEmpty ? (zh ? "气候：均衡" : "Climate: balanced") : (zh ? "气候：" : "Climate: ") + cl.joined(separator: zh ? "、" : ", "))
        out.append(zh ? "\(villages) 个村庄" : "\(villages) village\(villages == 1 ? "" : "s")")
        out.append(zh ? "约 \(population) 人" : "about \(population) people")
        if let e = WorldRecipe.eras.first(where: { $0.tech == startTech }), tags.contains("era:\(startTech)") { out.append(zh ? e.zh : e.en) }
        else { out.append(zh ? "原始时代起步" : "Starts in the stone age") }
        out.append((zh ? "种子 " : "Seed ") + String(seed))
        return out
    }

    /// Name for the world when the sentence gave none.
    public func suggestedName(zh: Bool, index: Int) -> String {
        if !name.isEmpty { return name }
        let cl = WorldRecipe.climates.first { tags.contains($0.key) }
        let era = WorldRecipe.eras.first { tags.contains("era:\($0.tech)") }
        if cl == nil && era == nil { return (zh ? "世界 " : "World ") + String(index) }
        let parts = [cl.map { zh ? $0.zh : $0.en }, era.map { zh ? $0.zh : $0.en }].compactMap { $0 }
        return parts.joined(separator: zh ? "·" : " · ")
    }

    static func wholeWord(_ s: String, _ w: String) -> Bool {
        var from = s.startIndex
        while let r = s.range(of: w, range: from..<s.endIndex) {
            let before = r.lowerBound == s.startIndex ? " " : s[s.index(before: r.lowerBound)]
            let after = r.upperBound == s.endIndex ? " " : s[r.upperBound]
            let isLetter: (Character) -> Bool = { $0.isASCII && $0.isLetter }
            if !isLetter(before) && !isLetter(after) { return true }
            from = r.upperBound
        }
        return false
    }

    /// Every number in the text with what follows and what precedes it.
    static func numbers(_ s: String) -> [(Int, Substring, Substring)] {
        var out: [(Int, Substring, Substring)] = []
        var i = s.startIndex
        while i < s.endIndex {
            if s[i].isASCII && s[i].isNumber {
                var j = i
                while j < s.endIndex, s[j].isASCII, s[j].isNumber { j = s.index(after: j) }
                if let n = Int(s[i..<j].prefix(9)) { out.append((n, s[j...].prefix(16), s[..<i].suffix(8))) }
                i = j
            } else { i = s.index(after: i) }
        }
        // a few Chinese numerals in front of a counter ("三个村庄", "一百人")
        let cn: [(String, Int)] = [("一千", 1000), ("五百", 500), ("三百", 300), ("两百", 200), ("二百", 200), ("一百", 100), ("五十", 50), ("二十", 20), ("十", 10),
                                   ("九", 9), ("八", 8), ("七", 7), ("六", 6), ("五", 5), ("四", 4), ("三", 3), ("两", 2), ("二", 2)]
        var used: [Range<String.Index>] = []
        for (w, n) in cn {
            var from = s.startIndex
            while let r = s.range(of: w, range: from..<s.endIndex) {
                from = r.upperBound
                if used.contains(where: { $0.overlaps(r) }) { continue }
                let after = s[r.upperBound...].prefix(16)
                let a = after.drop(while: { $0 == "个" || $0 == "座" || $0 == "名" || $0 == "位" || $0 == "多" })
                if ["村", "镇", "城", "部落", "聚落", "人", "居民", "村民"].contains(where: { a.hasPrefix($0) }) {
                    out.append((n, after.first == "多" ? after.dropFirst() : after, s[..<r.lowerBound].suffix(8)))
                    used.append(r)
                }
            }
        }
        return out
    }

    static func quotedName(_ raw: String) -> String? {
        for (l, r) in [("「", "」"), ("“", "”"), ("《", "》"), ("\"", "\"")] {
            if let a = raw.range(of: l), let b = raw.range(of: r, range: a.upperBound..<raw.endIndex) {
                let n = raw[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespaces)
                if !n.isEmpty && n.count <= 24 { return n }
            }
        }
        for key in ["名叫", "叫做", "名为", "叫", "named ", "called "] {
            if let a = raw.range(of: key, options: .caseInsensitive) {
                let rest = raw[a.upperBound...]
                let n = rest.prefix(while: { !"，。,.!！?？;；、 的".contains($0) })
                let t = String(n.prefix(16)).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { return t }
            }
        }
        return nil
    }

    /// FNV-1a so the same sentence always gives the same world.
    public static func stableSeed(_ s: String) -> Int {
        if s.isEmpty { return 7 }
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Int(h % 99991) + 1
    }
}
