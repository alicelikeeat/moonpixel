import Foundation

// What a villager says, written by a language model on the device (the app's VillagerVoice: Apple's on-device
// model). The simulation decides what is true; the model only puts it into words. So the model is given the
// facts of the villager's life, as the simulation has them, and told to say nothing beyond them; and every
// villager can always speak without it (the written lines of `Society.talk`), on a device without the model,
// or when it declines.

/// A villager's facts, for a language model to speak from.
public struct VillagerPersona: Equatable, Sendable {
    public var id = 0
    public var name = "", age = 0, female = false, stage = "adult"
    public var job = "", town = "", townPeople = 0, townHouses = 0
    public var doing = ""
    public var feeling: [String] = []
    public var family: [String] = []
    public var recent: [String] = []
    public var knowsPlayer = false
    /// The written line (what is shown at once, and when there is no model).
    public var fallback = ""
    public var zh = true

    /// What the conversation turns to this time (talking again moves on to the next).
    public static let topics = ["greeting", "life", "family", "work", "town", "worry"]

    /// The standing instructions: who the model is, how long, what it may not do.
    public var instructions: String {
        zh ? """
        你在一个温暖的像素风生活模拟游戏里扮演一位村民，正在和路过的旅人说话。
        只用简体中文，第一人称，像日常聊天一样说一到三句话，合计不超过六十个字。
        只根据给出的事实说话：不要编造事实里没有的人名、地名、事件或数字。
        不要提到游戏、人工智能或模型，不要使用引号或表情符号。语气符合你的年龄和心情。
        """ : """
        You play a villager in a warm pixel-art life simulation, talking with a traveller passing by.
        Speak in English, first person, one to three short sentences, under 45 words, like everyday talk.
        Say only what the facts below support: invent no names, places, events or numbers that are not in them.
        Never mention games, AI or models; no quotation marks or emoji. Sound your age and your mood.
        """
    }

    /// The facts, and what to talk about.
    public func prompt(topic: String) -> String {
        var f: [String] = []
        if zh {
            f.append("名字：\(name)；\(female ? "女" : "男")，\(age)岁（\(stage == "child" ? "孩子" : (stage == "elder" ? "老人" : "成年人"))）")
            if !job.isEmpty { f.append("职业：\(job)") }
            f.append("住在：\(town)（\(townPeople)人，\(townHouses)座房子）")
            if !doing.isEmpty { f.append("现在：\(doing)") }
            if !feeling.isEmpty { f.append("状态：" + feeling.joined(separator: "，")) }
            if !family.isEmpty { f.append("家人：" + family.joined(separator: "；")) }
            if !recent.isEmpty { f.append("最近的心事：" + recent.joined(separator: "；")) }
            f.append(knowsPlayer ? "你认识这位旅人，关系不错。" : "你和这位旅人还不熟。")
        } else {
            f.append("Name: \(name); \(female ? "woman" : "man"), \(age) (\(stage))")
            if !job.isEmpty { f.append("Work: \(job)") }
            f.append("Lives in: \(town) (\(townPeople) people, \(townHouses) houses)")
            if !doing.isEmpty { f.append("Now: \(doing)") }
            if !feeling.isEmpty { f.append("Feeling: " + feeling.joined(separator: ", ")) }
            if !family.isEmpty { f.append("Family: " + family.joined(separator: "; ")) }
            if !recent.isEmpty { f.append("On your mind lately: " + recent.joined(separator: "; ")) }
            f.append(knowsPlayer ? "You know this traveller and like them." : "You do not know this traveller well yet.")
        }
        let ask: String
        switch topic {
        case "life": ask = zh ? "说说你最近过得怎么样。" : "Say how life has been lately."
        case "family": ask = zh ? "聊聊你的家人（没有家人就说说一个人的生活）。" : "Talk about your family (or about living alone if you have none)."
        case "work": ask = zh ? "聊聊你的工作或今天在忙什么。" : "Talk about your work or what you are busy with today."
        case "town": ask = zh ? "聊聊你住的城镇。" : "Talk about your town."
        case "worry": ask = zh ? "说说你最近在想的一件事。" : "Say one thing that has been on your mind."
        default: ask = zh ? "旅人刚向你打招呼，回应一句。" : "The traveller has just greeted you: answer."
        }
        return (zh ? "事实：\n" : "Facts:\n") + f.map { "- " + $0 }.joined(separator: "\n") + "\n\n" + ask
    }

    /// A key for the line written from these facts on this topic (the same facts and topic: the same line,
    /// written once).
    public func key(topic: String) -> String {
        "\(id)|\(topic)|\(zh)|\(age)|\(job)|\(doing)|\(feeling.joined())|\(family.joined())|\(recent.joined())|\(knowsPlayer)"
    }
}

extension Society {
    /// The facts of a villager's life for a language model (nil for nobody).
    public func persona(_ id: Int) -> VillagerPersona? {
        guard let a = agents[id], let s = settlements[a.sid], let info = talk(id, speak: false) else { return nil }
        let now = world.time
        var p = VillagerPersona()
        p.id = id; p.zh = zh
        p.name = info.name; p.age = info.age; p.female = a.female; p.stage = a.stage(now)
        p.job = info.job; p.town = info.settlement
        p.townPeople = s.members.count; p.townHouses = s.count("house", done: true)
        if a.sleeping { p.doing = zh ? "正要睡觉" : "about to sleep" }
        else if let t = a.task, t.stage == 1 {
            let acts: [String: (String, String)] = ["chop": ("在砍树", "chopping wood"), "mine": ("在采石挖矿", "mining"), "build": ("在盖房子", "building"),
                                                    "forage": ("在采集", "foraging"), "reap": ("在收割庄稼", "harvesting"), "sow": ("在播种", "sowing"), "plant": ("在种树", "planting")]
            if let d = acts[t.act] { p.doing = zh ? d.0 : d.1 }
        }
        func level(_ v: Double, _ hi: (String, String), _ lo: (String, String)) -> String? {
            v > 0.7 ? (zh ? hi.0 : hi.1) : (v < 0.3 ? (zh ? lo.0 : lo.1) : nil)
        }
        p.feeling = [level(info.mood, ("心情很好", "in a good mood"), ("心情低落", "feeling low")),
                     level(info.hunger, ("很饿", "very hungry"), ("吃得饱", "well fed")),
                     level(info.energy, ("精神很好", "full of energy"), ("很累", "tired")),
                     a.grief > 0.5 ? (zh ? "正在为失去亲人而难过" : "grieving someone lost") : nil,
                     a.home == -1 ? (zh ? "还没有自己的房子" : "without a home of their own") : nil,
                     info.pregnant ? (zh ? "怀孕了" : "expecting a baby") : nil].compactMap { $0 }
        p.family = Array(info.family.prefix(4)).map { $0.replacingOccurrences(of: "♥ ", with: "").replacingOccurrences(of: "· ", with: "") }
        p.recent = info.thoughts
        p.knowsPlayer = (a.rel[0] ?? 0) > 0.4
        p.fallback = info.line
        return p
    }
}
