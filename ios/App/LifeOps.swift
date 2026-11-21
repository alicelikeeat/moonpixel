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
    /// A tap on the map: the exact tile under the finger, and what is there.
    func pickMap(_ fx: Double, _ fy: Double) {
        let t = worldMap.tile(fx: fx, fy: fy)
        mapPick = t
        let d = scene.map { Int(Double(t.distance2($0.player.tile)).squareRoot()) } ?? 0
        if mapLayer == .sky {
            let c = society.world.gen.skyIsland(OpenWorld.floorDiv(t.x, 32), OpenWorld.floorDiv(t.y, 32))
            let what = c.map { society.world.gen.skyCityName($0.0, $0.1, zh: GameModel.zh) + L("（天空城）", " (sky city)") } ?? L("空中（会落在最近的天空岛上）", "Open air (you land on the nearest sky island)")
            mapPickText = String(format: L("(%d, %d) · %@ · 距你 %d 格", "(%d, %d) · %@ · %d tiles away"), t.x, t.y, what, d)
            return
        }
        if mapLayer != .surface {
            let z = society.underlandZones().first { $0.sea == (mapLayer == .seaFloor) && $0.contains(OpenWorld.floorDiv(t.x, 32), OpenWorld.floorDiv(t.y, 32)) }
            let what = z.flatMap { society.civ.polities[$0.nation] }.map { String(format: L("%@的地底世界", "%@'s underland"), $0.name(zh: GameModel.zh)) }
                ?? (mapLayer == .seaFloor ? L("被海水淹没的岩层（会落在附近能站的地方）", "Flooded rock (you land on the nearest floor)") : L("岩层（会挖出一小块落脚处）", "Rock (a small room is cleared for you)"))
            mapPickText = String(format: L("(%d, %d) · %@ · 距你 %d 格", "(%d, %d) · %@ · %d tiles away"), t.x, t.y, what, d)
            return
        }
        mapPickText = String(format: L("(%d, %d) · %@ · 距你 %d 格", "(%d, %d) · %@ · %d tiles away"), t.x, t.y, WorldMap.describe(society, t, zh: GameModel.zh), d)
    }

    func pickNearestUfoPort() {
        guard let sc = scene, let m = society.nearestUfoPort(cx: Int((sc.player.x / 512).rounded(.down)), cy: Int((sc.player.y / 512).rounded(.down))) else {
            showToast(L("附近没有 UFO 机场", "No UFO airport nearby")); return
        }
        let t = TilePos(m.0 * 32 + 16, m.1 * 32 + 30)
        mapPick = t
        mapPickText = L("UFO 机场入口", "The UFO airport's road in") + String(format: " (%d, %d)", t.x, t.y)
    }

    func pickNearestUnderCity() {
        guard let sc = scene, let t0 = society.nearestUnderCity(cx: Int((sc.player.x / 512).rounded(.down)), cy: Int((sc.player.y / 512).rounded(.down))) else {
            showToast(L("附近没有地下城", "No underground city nearby")); return
        }
        let t = TilePos(t0.x, t0.y + 6)        // on the plaza, before the gatehouse's open gate
        mapPick = t
        mapPickText = L("地下城入口（门楼里有通往地下的楼梯；地下国家挖开的地底世界有草地、道路、房屋和人造天光）", "Underground city entrance (the stairway down is in the gatehouse; the underland its nation has dug has grass, roads, houses and a sky of lamps)") + String(format: " (%d, %d)", t.x, t.y)
    }

    func pickNearestSeaCity() {
        guard let sc = scene, let t0 = society.nearestSeaCity(cx: Int((sc.player.x / 512).rounded(.down)), cy: Int((sc.player.y / 512).rounded(.down))) else {
            showToast(L("附近没有海底城（只有有海洋的新世界才有）", "No sea-floor city nearby (only new worlds with oceans have them)")); return
        }
        let t = TilePos(t0.x, t0.y + 1)        // inside the pearl dome, beside the stairway down
        mapPick = t
        mapPickText = L("海底城入口（珍珠穹顶里有通往海底世界的楼梯）", "Sea-floor city entrance (the stairway down to its underland is in the pearl dome)") + String(format: " (%d, %d)", t.x, t.y)
    }

    func pickNearestVolcano() {
        guard let sc = scene, let v = society.nearestVolcano(near: sc.player.tile) else {
            showToast(L("附近没有火山", "No volcano nearby")); return
        }
        // the foot of its slope, on the south side (the crater is lava)
        let t = TilePos(v.x, v.y + 30)
        mapPick = t
        mapPickText = L("火山脚下", "The foot of the volcano") + String(format: " (%d, %d)", t.x, t.y)
    }

    func teleportToPick() {
        guard let p = mapPick else { return }
        switch mapLayer {
        case .surface: teleport(to: p)
        case .sky: teleportAny(TeleportTarget(group: .sky, name: String(format: "(%d, %d)", p.x, p.y), tile: p, depth: SkyTune.depth, detail: ""))
        default: teleportBelow(to: p)
        }
    }

    /// Teleport anywhere, on any layer, from anywhere (out of a vehicle or a saucer first); remembered among the
    /// last places.
    func teleportAny(_ target: TeleportTarget) {
        guard let sc = scene, let s = society else { return }
        let before = depth
        let from = CGPoint(x: sc.player.x, y: -sc.player.y)
        guard let pos = s.teleport(to: target) else {
            showToast(target.depth == SkyTune.depth || target.depth >= OpenWorld.storeyBase ? L("那里是空中，40 格内没有能站的地方", "Open air: nowhere to stand within 40 tiles") : L("那里 40 格内无法落脚", "Nowhere to stand within 40 tiles"))
            return
        }
        mapPick = nil; mapPickText = ""
        showMap = false; showTeleport = false
        following = false
        if target.depth != before { switchLayer(to: pos) } else { sc.player = pos }
        sc.blinkFX(from: from, to: CGPoint(x: pos.x, y: -pos.y))
        showToast(String(format: L("已瞬移：%@（%@）", "Teleported: %@ (%@)"), target.name, Society.layerName(target.depth, zh: GameModel.zh)))
    }

    /// Go below at once: into an underland (or the rock) at that tile.
    func teleportBelow(to t: TilePos, name: String? = nil) {
        teleportAny(TeleportTarget(group: .under, name: name ?? String(format: "(%d, %d)", t.x, t.y), tile: t, depth: 1, detail: ""))
    }

    /// Go to a city of any nation: its town, its region, or its plaza below.
    func goToCity(_ id: Int) {
        guard let gate = society.cityGate(id), let city = society.civ.cities[id] else { return }
        civDetail = nil
        showRealm = false
        if gate.below { teleportBelow(to: gate.tile, name: city.name(zh: GameModel.zh)); return }
        // a city far away is made a real town now, and one arrives in its middle
        if let t = society.arriveAtCity(id) {
            teleport(to: t + TilePos(0, 3), name: city.name(zh: GameModel.zh))
        } else {
            teleport(to: gate.tile, name: city.name(zh: GameModel.zh))
            showToast(String(format: L("%@ 的城镇暂时无法在这里展开（附近没有空地或城镇太多），已送到它所在地区的中心", "%@ cannot be laid out here right now (no room nearby, or too many towns shown): you are at the middle of its region"), city.name(zh: GameModel.zh)))
        }
    }

    /// A place tapped on the map: a city of the regions is made real and one arrives in it; anywhere else, go there.
    func goToMarker(_ m: MapMarker) {
        if let id = m.city { showMap = false; goToCity(id) } else { teleport(to: m.tile, name: m.name) }
    }

    /// Where a material comes from, for a message about what is missing.
    static func whereToGet(_ good: String) -> String {
        switch good {
        case "moonsteel": return L("（月钢：在熔炉旁用月矿×2+铁锭+木材×2冶炼，可在“制造”里一次做 10 个；月矿在地下挖紫色矿脉；本国城镇仓库里的月钢可以在“制造”面板领取）",
                                   " (moonsteel: smelt moon ore ×2 + iron + wood ×2 at a furnace, ten at a time from Craft; moon ore: dig the purple veins underground; your own nation's stores can be taken from the Craft panel)")
        case "moon_ore": return L("（月矿：在地下用镐挖紫色月矿脉，越往下层越多；地下遗迹宝箱里也有）", " (moon ore: dig the purple veins underground with the pick, more on the deeper levels; ruin chests hold some too)")
        case "iron": return L("（铁锭：在熔炉旁用铁矿×2+木材冶炼）", " (iron: smelt iron ore ×2 + wood at a furnace)")
        case "iron_ore": return L("（铁矿：在地下挖铁矿脉）", " (iron ore: dig the veins underground)")
        default: return ""
        }
    }

    /// Take a good from the stores of a town of your own nation you stand in.
    func requisition(_ good: String) {
        let (n, why) = society.playerRequisition(good, amount: good == "moonsteel" ? 40 : 80)
        switch why {
        case nil: showToast(String(format: L("从本国仓库领取了 %@ %g", "Took %@ %g from our stores"), Recipe.goodName(good, zh: GameModel.zh), n.rounded()))
        case "no_town": showToast(L("要站在一座城镇里才能领取仓库物资", "Stand in a town to take from its stores"))
        case "not_ours": showToast(L("这不是你所属国家的城镇（先加入一个国家，或去本国城镇）", "This is not a town of your nation (join a nation, or go to one of its towns)"))
        default: showToast(String(format: L("这座城镇的仓库里没有%@", "This town's stores hold no %@"), Recipe.goodName(good, zh: GameModel.zh)))
        }
        refreshCraft()
    }

    /// Go straight to the plaza of a level a city below has built down to.
    func goDeep(_ id: Int, level: Int) {
        guard let t = society.deepGate(id, level: level), let city = society.civ.cities[id] else { return }
        civDetail = nil
        showRealm = false
        teleportAny(TeleportTarget(group: .under, name: city.name(zh: GameModel.zh) + String(format: L(" · 地下第 %d 层", " · level B%d"), level), tile: t + TilePos(0, 2), depth: level, detail: ""))
    }

    /// Go there at once (on the surface): from anywhere, in a vehicle, underground, upstairs or in the sky.
    func teleport(to t: TilePos, name: String? = nil) {
        let place = name ?? WorldMap.describe(society, t, zh: GameModel.zh)
        teleportAny(TeleportTarget(group: .city, name: place, tile: t, depth: 0, detail: ""))
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
