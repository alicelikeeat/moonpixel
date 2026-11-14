import SwiftUI
import SpriteKit
import MoonPixelCore

struct PowerCard: Identifiable {
    var id = ""
    var name = "", note = ""
    var school = 0, tier = 1
    var known = false, equipped = false
}

/// Powers, teleporting, romance, animals, leisure and cheats as the player uses them.
extension GameModel {
    // MARK: arsenal
    func refreshPowers() {
        guard let s = society else { return }
        let mine = Set(s.playerPowers().map { $0.key })
        let tree = s.arsenalTree()
        var cards: [PowerCard] = []
        for p in Power.all {
            var c = PowerCard()
            c.id = p.key; c.name = p.name(zh: GameModel.zh); c.school = p.school; c.tier = p.tier
            c.known = mine.contains(p.key) || s.realm.player.god == true
            c.equipped = activePower == p.key
            if c.known {
                let dmg = p.damage > 0 ? String(format: L("伤害 %d · ", "damage %d · "), Int(p.damage)) : ""
                c.note = dmg + String(format: L("冷却 %.1f 秒", "cooldown %.1f s"), p.cooldown) + (p.focus > 0 ? String(format: L(" · 专注 %d", " · focus %d"), Int(p.focus)) : "")
            } else {
                let needs = (tree.needs[p.key] ?? []).compactMap { Power.byKey[$0]?.name(zh: GameModel.zh) }
                let civ = p.civNeed > 0 ? String(format: L("需要 %d 项民用科技", "needs %d civil techs"), p.civNeed) : ""
                let pre = needs.isEmpty ? "" : L("前置：", "after: ") + needs.joined(separator: L("、", ", "))
                c.note = [pre, civ].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            cards.append(c)
        }
        powerCards = cards
        var lines: [String] = []
        for n in s.realm.nations {
            let studying = n.studying.flatMap { Power.byKey[$0]?.name(zh: GameModel.zh) } ?? "-"
            let best = s.signaturePower(n.id)?.name(zh: GameModel.zh) ?? "-"
            lines.append(String(format: L("%@：已掌握 %d 项 · 最强 %@ · 正在研究 %@", "%@: %d learned · best %@ · studying %@"), n.name(zh: GameModel.zh), n.powers?.count ?? 0, best, studying))
        }
        arsenalLines = lines
    }

    func equip(_ key: String) {
        activePower = activePower == key ? "" : key
        if let p = Power.byKey[key], !activePower.isEmpty { showToast(String(format: L("已装备 %@：点击地面使用", "%@ equipped: tap the ground to use it"), p.name(zh: GameModel.zh))) }
        refreshPowers()
    }

    func casted(_ r: Society.CastResult) {
        if r.ok {
            if r.healed > 0 { showToast(String(format: L("恢复生命 %d", "Healed %d"), Int(r.healed))) }
            if selectedID != 0 && society.agents[selectedID] == nil { deselect() }
            return
        }
        switch r.reason {
        case "focus": showToast(L("专注不足，稍等片刻", "Not enough focus yet"))
        case "unknown": showToast(L("你还没有掌握这项能力", "You have not learned that")); activePower = ""
        case "blocked": showToast(L("那里无法落脚", "Nowhere to stand there"))
        default: break          // cooling down: stay quiet
        }
    }

    // MARK: map teleport
    func pickMap(_ fx: Double, _ fy: Double) {
        guard mapSide > 0 else { return }
        let x = mapOrigin.x + Int(fx * Double(mapSide)), y = mapOrigin.y + Int(fy * Double(mapSide))
        mapPick = TilePos(x, y)
        rebuildMap()
    }

    func pickNearestMaze() {
        guard let sc = scene, let m = society.nearestMaze(cx: Int((sc.player.x / 512).rounded(.down)), cy: Int((sc.player.y / 512).rounded(.down))) else {
            showToast(L("附近没有迷宫", "No maze nearby")); return
        }
        mapPick = TilePos(m.0, m.1)
        rebuildMap()
    }

    func teleportToPick() {
        guard let p = mapPick, let sc = scene else { return }
        // a maze is entered by its south gate; anywhere else, the nearest free ground
        let maze = world.gen.isMaze(p.x, p.y)
        let goal = maze ? TilePos(p.x * 32 + 15, p.y * 32 + 33) : TilePos(p.x * 32 + 16, p.y * 32 + 16)
        let t = world.findFree(near: goal, maxR: 24)
        if world.blocked(t.x, t.y) { showToast(L("那里全是水或山，无法落脚", "Nothing but water or rock there")); return }
        let from = CGPoint(x: sc.player.x, y: -sc.player.y)
        sc.player = t.center
        sc.blinkFX(from: from, to: CGPoint(x: t.center.x, y: -t.center.y))
        following = false
        mapPick = nil
        showMap = false
        showToast(maze ? L("已瞬移到迷宫南门", "Teleported to the maze's south gate") : L("已瞬移", "Teleported"))
    }

    // MARK: things within reach
    /// A tap on the world near the player: open maze treasure, pick a flower. Returns true when the tap was used.
    func tapWorld(_ t: TilePos) -> Bool {
        guard let sc = scene, (t - sc.player.tile).lengthSquared <= 9 else { return false }
        let r = society.playerOpenChest(at: t)
        if r.ok {
            if let p = r.power { showToast(String(format: L("宝箱：粮木石各 +30，并获得神器「%@」", "Treasure: +30 food, wood and stone, and the artifact \"%@\""), p.name(zh: GameModel.zh))) }
            else { showToast(L("宝箱：粮木石各 +30", "Treasure: +30 food, wood and stone")) }
            sc.firework(at: CGPoint(x: t.center.x, y: -(t.center.y - 30)))
            refreshPowers()
            return true
        }
        if society.playerPick(at: t) { showToast(L("摘了一朵花", "Picked a flower")); return true }
        return false
    }

    func tame() {
        guard let sc = scene else { return }
        switch society.playerTame(near: sc.player) {
        case nil: showToast(L("它愿意跟着你了", "It will follow you now"))
        case "food": showToast(L("驯养需要 3 份食物", "Taming takes 3 food"))
        case "wild": showToast(L("这种动物无法驯养", "That animal cannot be tamed"))
        default: showToast(L("附近没有动物", "No animal nearby"))
        }
    }

    // MARK: romance and leisure
    func gift(_ kind: String) {
        guard selectedID != 0 else { return }
        if let why = society.playerGift(selectedID, kind) {
            showToast(why == "flower" ? L("你没有花：点击身边的花可以采摘", "You have no flowers: tap one near you to pick it") : L("背包里的食物不够", "Not enough food in your pack"))
        }
        talk()
    }

    func date() {
        guard selectedID != 0 else { return }
        switch society.playerDate(selectedID) {
        case nil: showToast(L("对方愿意陪你走走", "They will walk with you for a while"))
        case "stranger": showToast(L("你们还不够熟（好感需达到 50）", "You are not close enough yet (affection 50)"))
        case "soon": showToast(L("刚约会过，过一阵再来", "You went out not long ago"))
        default: showToast(L("现在不行", "Not now"))
        }
        talk()
    }

    func propose() {
        guard selectedID != 0 else { return }
        switch society.playerPropose(selectedID) {
        case nil: break
        case "notyet": showToast(L("对方还没准备好（好感需达到 85）", "They are not ready (affection 85)"))
        case "taken": showToast(L("对方已有伴侣", "They already have a partner"))
        case "married": showToast(L("你已有伴侣", "You already have a partner"))
        default: showToast(L("现在不行", "Not now"))
        }
        talk()
    }

    func dice() {
        guard selectedID != 0 else { return }
        let r = society.playerDice(selectedID)
        if r.reason == "food" { showToast(L("掷骰子要押 5 份食物", "Dice needs a stake of 5 food")) }
        else if !r.reason.isEmpty { showToast(L("对方不想玩", "They would rather not")) }
        else { showToast(String(format: L("你掷出 %d，对方 %d：%@", "You rolled %d, they rolled %d: %@"), r.you, r.them, r.won > 0 ? L("赢得 5 份食物", "you win 5 food") : (r.won < 0 ? L("输掉 5 份食物", "you lose 5 food") : L("平局", "a draw")))) }
    }

    // MARK: cheats
    func cheat(_ what: String) {
        guard let sc = scene else { return }
        if what == "reveal" {
            society.realm.player.cheated = true
            world.survey(center: TilePos(Int((sc.player.x / 512).rounded(.down)), Int((sc.player.y / 512).rounded(.down))), count: 900)
            showToast(L("已探明周围的地图", "The surrounding map is revealed"))
            return
        }
        let ok = society.cheat(what, at: sc.player)
        showToast(ok ? L("作弊已生效（此存档已标记为使用过作弊）", "Cheat applied (this save is marked as cheated)") : L("这里用不了", "That does not work here"))
        refreshPowers()
        refreshRealm()
    }
}

/// Weapons, energy arms, spells, divine arts and words: what is known, what it needs, what the nations study.
struct ArsenalPanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("武器与法术", "Arsenal"), subtitle: L("每个世界的科技树都不同 · 点击已掌握的能力来装备", "Every world has its own tree · tap a known power to equip it"), close: { model.showArsenal = false }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.arsenalLines, id: \.self) { Text($0).font(.system(size: 11, design: .rounded)).opacity(0.85) }
                ForEach(0..<5, id: \.self) { school in row(school) }
            }
        }
        .onAppear { model.refreshPowers() }
    }

    private func row(_ school: Int) -> some View {
        let name = Power.schoolNames[school]
        let cards = model.powerCards.filter { $0.school == school }
        return VStack(alignment: .leading, spacing: 4) {
            Text(L(name.1, name.0)).font(.system(size: 14, weight: .bold, design: .rounded))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(cards) { c in card(c) } }
            }
        }
    }

    private func card(_ c: PowerCard) -> some View {
        Button { if c.known { model.equip(c.id) } } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: c.known ? (c.equipped ? "checkmark.circle.fill" : "bolt.fill") : "lock.fill").font(.system(size: 10, weight: .bold))
                    Text(c.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                    Text(String(repeating: "★", count: c.tier)).font(.system(size: 8)).opacity(0.8)
                }
                Text(c.note).font(.system(size: 9, design: .rounded)).opacity(0.75).lineLimit(2)
            }
            .padding(8).frame(width: 168, height: 54, alignment: .topLeading)
            .background(Color.white.opacity(c.equipped ? 0.34 : (c.known ? 0.16 : 0.06)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(c.known ? 1 : 0.6)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("power-" + c.id)
    }
}

/// Cheats. Using any of them marks the save.
struct CheatPanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("作弊", "Cheats"), subtitle: L("使用后此存档会被标记", "Using one marks this save"), close: { model.showCheats = false }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip(title: L("无敌开关", "God mode"), icon: "shield.fill", id: "cheat-god") { model.cheat("god") }
                    Chip(title: L("全部能力", "All powers"), icon: "bolt.fill", id: "cheat-powers") { model.cheat("powers") }
                    Chip(title: L("物资 +200", "Resources +200"), icon: "shippingbox.fill", id: "cheat-rich") { model.cheat("rich") }
                    Chip(title: L("回满生命专注", "Full health"), icon: "heart.fill", id: "cheat-heal") { model.cheat("heal") }
                }
                HStack(spacing: 6) {
                    Chip(title: L("各国科技 +1", "Tech +1"), icon: "atom", id: "cheat-tech") { model.cheat("tech") }
                    Chip(title: L("强制休战", "Force truce"), icon: "hand.raised.fill", id: "cheat-peace") { model.cheat("peace") }
                    Chip(title: L("人口 +10", "People +10"), icon: "person.3.fill", id: "cheat-people") { model.cheat("people") }
                    Chip(title: L("好感拉满", "Max affection"), icon: "heart.circle.fill", id: "cheat-love") { model.cheat("love") }
                }
                HStack(spacing: 6) {
                    Chip(title: L("召唤宠物", "Summon pets"), icon: "pawprint.fill", id: "cheat-animals") { model.cheat("animals") }
                    Chip(title: L("跳到清晨", "Skip to dawn"), icon: "sunrise.fill", id: "cheat-dawn") { model.cheat("dawn") }
                    Chip(title: L("探明地图", "Reveal map"), icon: "map.fill", id: "cheat-reveal") { model.cheat("reveal") }
                    Chip(title: L("立即开战", "Start a war"), icon: "flag.2.crossed.fill", id: "cheat-war") { model.startDemoWar() }
                }
                Text(L("天气", "Weather")).font(.system(size: 13, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Chip(title: L("晴", "Clear"), icon: "sun.max.fill", id: "weather-0") { model.cheat("weather:0") }
                    Chip(title: L("雨", "Rain"), icon: "cloud.rain.fill", id: "weather-2") { model.cheat("weather:2") }
                    Chip(title: L("雷暴", "Storm"), icon: "cloud.bolt.rain.fill", id: "weather-3") { model.cheat("weather:3") }
                    Chip(title: L("雾", "Fog"), icon: "cloud.fog.fill", id: "weather-4") { model.cheat("weather:4") }
                    Chip(title: L("酷热", "Heat"), icon: "thermometer.sun.fill", id: "weather-5") { model.cheat("weather:5") }
                }
            }
        }
    }
}
