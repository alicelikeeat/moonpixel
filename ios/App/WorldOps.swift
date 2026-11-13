import SwiftUI
import SpriteKit
import MoonPixelCore

/// One nation as the panel shows it (strings are prepared here so the views stay simple).
struct NationCard: Identifiable {
    var id = 0
    var name = "", color = "#ffffff"
    var line1 = "", line2 = "", line3 = ""
    var pressure = 0.0, fatigue = 0.0
    var landless = false, joined = false
}

/// Nations, the player's part in them, world laws and storage. Threading: the
/// simulation, laws and all SwiftUI/SpriteKit state live on the main thread;
/// only photo and video pixel work runs on a background queue and hands a
/// finished value back.
extension GameModel {
    // MARK: settings
    func loadSettings() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "mp.policy"), let p = try? JSONDecoder().decode(StoragePolicy.self, from: data) { policy = p }
        let mb = d.integer(forKey: "mp.limitMB")
        if mb > 0 { limitMB = mb }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(policy) { UserDefaults.standard.set(data, forKey: "mp.policy") }
        UserDefaults.standard.set(limitMB, forKey: "mp.limitMB")
        world?.diskLimitBytes = limitBytes
    }

    func setPolicy(_ mode: StorageMode) { policy.mode = mode; saveSettings(); refreshStorage() }
    func setLimit(_ mb: Int) { limitMB = mb; saveSettings(); refreshStorage() }

    // MARK: storage
    func assetBytes() -> (images: Int, portraits: Int) {
        var images = 0, portraits = 0
        for f in (try? FileManager.default.contentsOfDirectory(atPath: assetsDir.path)) ?? [] {
            let size = ((try? FileManager.default.attributesOfItem(atPath: assetsDir.appendingPathComponent(f).path)[.size]) as? NSNumber)?.intValue ?? 0
            if f.hasPrefix("face_") || f.hasPrefix("portrait_") || f.hasPrefix("anim_") { portraits += size } else { images += size }
        }
        return (images, portraits)
    }

    /// Everything this world occupies on disk.
    func totalBytes() -> Int {
        let a = assetBytes()
        return chunkAndIndexBytes() + a.images + a.portraits
    }

    func refreshStorage() {
        guard let w = world, let s = society else { return }
        let a = assetBytes()
        let parts = s.storageBreakdown()
        let total = totalBytes()
        var lines: [String] = []
        lines.append(String(format: L("合计 %@ / 上限 %@", "Total %@ of %@"), GameModel.sizeText(total), limitText))
        lines.append(String(format: L("区块 %@（%d 个文件）", "Chunks %@ (%d files)"), GameModel.sizeText(w.diskBytes), w.storedChunks.count))
        lines.append(String(format: L("人物 %@（%d 人）", "People %@ (%d)"), GameModel.sizeText(parts["people"] ?? 0), s.agents.count))
        lines.append(String(format: L("图片素材 %@ · 头像与动画 %@", "Images %@ · portraits and animations %@"), GameModel.sizeText(a.images), GameModel.sizeText(a.portraits)))
        lines.append(String(format: L("索引（城镇与国家） %@ · 历史 %@", "Index (towns and nations) %@ · history %@"),
                            GameModel.sizeText((parts["towns"] ?? 0) + (parts["nations"] ?? 0)), GameModel.sizeText(parts["history"] ?? 0)))
        storageLines = lines
    }

    /// Automatic destruction happens only when the player chose such a policy.
    func checkPolicy() {
        guard society != nil, !lawBusy, policy.mode != .cacheFirst else { return }
        guard let d = policy.decide(used: totalBytes(), limit: limitBytes, clock: Date().timeIntervalSince1970) else { return }
        saveSettings()
        guard save(announce: false) else { return }
        startLaw(society.planLaw(d.0, options: d.1, seed: Int.random(in: 1..<1_000_000)), auto: true)
    }

    // MARK: nations
    func refreshRealm() {
        guard let s = society, let sc = scene else { return }
        let p = s.realm.player
        let side = s.realm.nation(p.nation)?.name(zh: GameModel.zh) ?? L("自由旅人", "Free traveller")
        playerLine = String(format: L("%@ · 生命 %d · 粮 %d 木 %d 石 %d", "%@ · HP %d · food %d wood %d stone %d"), side, Int(p.hp), Int(p.food), Int(p.wood), Int(p.stone))
        guard showRealm else { return }
        _ = sc
        var cards: [NationCard] = []
        for n in s.nationInfos() {
            var c = NationCard()
            c.id = n.id; c.name = n.name; c.color = n.color
            c.pressure = n.pressure; c.fatigue = n.fatigue; c.landless = n.landless; c.joined = p.nation == n.id
            if n.landless {
                c.line1 = String(format: L("流亡中 · 仍有 %d 人认同", "In exile · %d people still belong"), n.identity)
            } else {
                c.line1 = String(format: L("领袖 %@ · %d 城 · %d 人 · %d 兵", "Leader %@ · %d towns · %d people · %d soldiers"), n.leader, n.towns, n.pop, n.soldiers)
            }
            c.line2 = String(format: L("科技 %@ · 粮 %d · 国力 %d%% · 对你 %+d", "Tech %@ · food %d · power %d%% · you %+d"), n.tech, Int(n.food), Int(n.share * 100), Int(n.rep * 100))
            c.line3 = String(format: L("压力 %d%%（粮 %d 房 %d 岗 %d 地 %d）· 疲劳 %d%%", "Pressure %d%% (food %d housing %d jobs %d land %d) · fatigue %d%%"),
                             Int(n.pressure * 100), Int(n.pFood * 100), Int(n.pHousing * 100), Int(n.pJobs * 100), Int(n.pLand * 100), Int(n.fatigue * 100))
            cards.append(c)
        }
        nationCards = cards
        var rel: [String] = []
        for r in s.relationInfos() {
            let state = r.state == 1 ? L("交战", "at war") : (r.state == 2 ? L("休战", "truce") : L("和平", "peace"))
            let pact = r.pact ? L(" · 结盟", " · allied") : ""
            rel.append(String(format: L("%@ — %@：%@ %.1f 年 · 关系 %+d%@", "%@ — %@: %@ for %.1f y · relations %+d%@"), r.a, r.b, state, r.years, Int(r.value * 100), pact))
        }
        relationLines = rel
        let e = s.eraInfo
        if e.era == 1 {
            eraLine = String(format: L("统一时代：%@ 已统一 %.1f 年 · 裂痕 %d%%", "Age of unity: %@ has ruled for %.1f y · fracture %d%%"), e.unifier, e.years, Int(min(1, e.fracture) * 100))
        } else if e.era == 2 {
            eraLine = L("文明重启中：世间暂无人烟", "Civilisation is restarting: nobody is alive")
        } else {
            eraLine = String(format: L("三国时代 %.1f 年 · 战争烈度 %d%% · 难民 %d", "Three nations for %.1f y · war intensity %d%% · refugees %d"), e.years, Int(e.intensity * 100), s.refugeeCount)
        }
    }

    func joinNation(_ id: Int) {
        society.playerJoin(id)
        let name = society.realm.nation(id)?.name(zh: GameModel.zh) ?? ""
        showToast(id == 0 ? L("你恢复了自由旅人身份", "You are a free traveller again") : String(format: L("你加入了 %@", "You joined %@"), name))
        refreshRealm()
    }

    func nearestTown() -> Settlement? { scene.flatMap { society.town(near: $0.player, radius: 700) } }

    func donate(_ kind: String) {
        guard let t = nearestTown() else { showToast(L("附近没有城镇", "No town nearby")); return }
        let given = society.playerDonate(sid: t.id, kind: kind, amount: 20)
        if given <= 0 { showToast(L("背包里没有这种物资（用斧砍树、用镐采石、采摘浆果获得）", "You carry none of that (chop trees with the axe, mine with the pick, pick berries)")) }
        else {
            let amount = "\(Int(given))"
            showToast(GameModel.zh ? "向 " + t.name(zh: true) + " 捐赠了 " + amount : "Gave " + amount + " to " + t.name(zh: false))
        }
        refreshRealm()
    }

    func acceptRefugees() {
        guard let t = nearestTown() else { showToast(L("附近没有城镇", "No town nearby")); return }
        let n = society.playerAcceptRefugees(sid: t.id)
        showToast(n > 0 ? String(format: L("%@ 接纳了 %d 名难民", "%@ took in %d refugees"), t.name(zh: GameModel.zh), n) : L("没有可接纳的难民，或这座城与你敌对", "No refugees to take in, or this town is hostile to you"))
        refreshRealm()
    }

    func build(at t: TilePos) {
        guard let sc = scene else { return }
        if (t - sc.player.tile).lengthSquared > 64 { showToast(L("太远了，走近一些", "Too far away, walk closer")); return }
        if let why = society.playerBuild(buildMode, at: t) {
            let msg: [String: String] = ["water": L("这里是水面，请改用桥", "That is water: use a bridge"), "land": L("桥只能建在水面上", "Bridges go on water"),
                                         "stone": L("石头不够", "Not enough stone"), "wood": L("木头不够", "Not enough wood"), "occupied": L("这里已有东西", "Something is already there")]
            showToast(msg[why] ?? why)
        }
        refreshRealm()
    }

    /// Feedback for an attack the core has already resolved.
    func struck(_ r: Society.StrikeResult) {
        if !r.gained.isEmpty { showToast(String(format: L("获得 %@ +%d", "Got %@ +%d"), r.gained == "wood" ? L("木头", "wood") : (r.gained == "stone" ? L("石头", "stone") : L("食物", "food")), Int(r.amount))) }
        if !r.demolished.isEmpty { showToast(r.demolished == "depot" ? L("补给站被摧毁", "Supply depot destroyed") : (r.demolished == "bridge" ? L("桥被拆毁", "Bridge destroyed") : L("道路被破坏", "Road destroyed"))) }
        if r.spared > 0 && r.hits.isEmpty { showToast(L("不能攻击本国人", "You cannot attack your own nation")) }
        if selectedID != 0 && society.agents[selectedID] == nil { deselect() }
    }

    func playerDied() {
        guard let sc = scene else { return }
        sc.player = society.spawnPoint(near: sc.player)
        following = false
        showToast(L("你倒下了，在安全的城镇醒来，背包丢了一半", "You fell and woke up in a safe town with half your pack gone"))
    }

    // MARK: world laws
    func photoJobStillValid(_ token: Int, _ target: Int) -> Bool {
        guard token == epoch, society != nil else { return false }             // another world, or genesis happened
        if target != 0 && society.agents[target] == nil {                      // the villager was deleted meanwhile
            showToast(L("目标人物已不存在，照片任务已作废", "That villager no longer exists; the photo job was dropped"))
            return false
        }
        return true
    }

    /// One tap: plan, journal, execute. No item-by-item choice, no second confirmation.
    func runLaw(_ mode: LawMode) {
        guard let s = society, !lawBusy else { return }
        guard save(announce: false) else { return }                            // never start from an unsaved state
        var o = LawOptions()
        o.ratio = lawRatio
        o.spaceTarget = lawSpaceMB * 1_048_576
        o.newSeed = lawNewSeed
        o.radius = lawRadius
        startLaw(s.planLaw(mode, options: o, seed: Int.random(in: 1..<1_000_000)), auto: false)
    }

    func startLaw(_ plan: LawPlan, auto: Bool) {
        guard LawJournal.write(plan, saveDir) else {
            showToast(L("无法写入恢复日志（空间不足？），未执行任何删除", "Could not write the recovery journal (no space?). Nothing was deleted"))
            return
        }
        lawBefore = totalBytes()
        if plan.mode == .genesis { doGenesis(plan); return }
        scene?.lawFX(plan)
        lawRun = society.beginLaw(plan)
        lawBusy = true
        lawProgress = 0
    }

    /// Called once per frame while a law runs: a batch at a time, so the screen keeps moving.
    func stepLaw() {
        guard let run = lawRun else { lawBusy = false; return }
        run.step(40)
        lawProgress = run.progress
        if run.done { lawRun = nil; finishLaw(run.result, plan: run.plan) }
    }

    func finishLaw(_ result: LawResult, plan: LawPlan) {
        var r = result
        if selectedID != 0 && society.agents[selectedID] == nil { deselect() }
        if let sc = scene {
            var move = world.blocked(sc.player.tile.x, sc.player.tile.y)
            if plan.region.count == 4 {
                let cx = Int((sc.player.x / 512).rounded(.down)), cy = Int((sc.player.y / 512).rounded(.down))
                if cx >= plan.region[0] && cx <= plan.region[2] && cy >= plan.region[1] && cy <= plan.region[3] { move = true }
            }
            if move { sc.player = society.spawnPoint(near: sc.player); following = false }
            sc.clearTextureCache()
            sc.markAllDirty()
        }
        r.assetsRemoved = collectAssets()
        let ok = save(announce: false)
        if ok { LawJournal.clear(saveDir) }                                    // the plan is the only recovery data; it goes once committed
        r.bytesBefore = lawBefore
        r.bytesAfter = totalBytes()
        lawBusy = false
        lawReport = describe(r) + (ok ? "" : L("（保存失败，下次启动会继续完成）", " (saving failed; it will be completed at the next start)"))
        showToast(lawReport)
        lastLogCount = society.log.count
        refreshStorage()
        refreshRealm()
    }

    func describe(_ r: LawResult) -> String {
        let name: String
        switch r.mode {
        case .thanos: name = L("灭霸", "Thanos")
        case .annihilation: name = L("湮灭", "Annihilation")
        case .genesis: name = L("创世纪", "Genesis")
        case .guixu: name = L("归墟", "Guixu")
        }
        var parts: [String] = []
        if r.agents > 0 { parts.append(String(format: L("居民 %d", "%d people"), r.agents)) }
        if r.towns > 0 { parts.append(String(format: L("城镇 %d", "%d towns"), r.towns)) }
        if r.buildings > 0 { parts.append(String(format: L("建筑 %d", "%d buildings"), r.buildings)) }
        if r.props > 0 { parts.append(String(format: L("摆件 %d", "%d objects"), r.props)) }
        if r.chunks > 0 { parts.append(String(format: L("区块 %d", "%d chunks"), r.chunks)) }
        if r.logLines + r.graves > 0 { parts.append(String(format: L("历史 %d", "%d history entries"), r.logLines + r.graves)) }
        if r.assetsRemoved > 0 { parts.append(String(format: L("无引用素材 %d", "%d unused assets"), r.assetsRemoved)) }
        if r.displaced > 0 { parts.append(String(format: L("流离失所 %d 人", "%d displaced"), r.displaced)) }
        let what = parts.isEmpty ? L("没有可删除的内容", "nothing to delete") : parts.joined(separator: L("、", ", "))
        let disk = String(format: L("磁盘回收 %@", "disk reclaimed %@"), GameModel.sizeText(r.freed))
        let tail = r.restart ? L(" · 已无人存活，文明进入重启", " · nobody is left: civilisation restarts") : ""
        return String(format: L("%@ 已删除：%@ · %@%@", "%@ deleted: %@ · %@%@"), name, what, disk, tail)
    }

    /// Delete asset files nothing points at any more; assets still used by anyone stay.
    @discardableResult func collectAssets() -> Int {
        var used = Set<String>()
        for k in society.referencedAssets(extra: [playerLook]) { used.insert(k.hasPrefix("asset:") ? String(k.dropFirst(6)) : k) }
        if let p = placingAsset { used.insert(p) }
        var removed = 0
        for f in (try? FileManager.default.contentsOfDirectory(atPath: assetsDir.path)) ?? [] where f.hasSuffix(".png") {
            let id = String(f.dropLast(4))
            if used.contains(id) { continue }
            try? FileManager.default.removeItem(at: assetsDir.appendingPathComponent(f))
            assets[id] = nil; portraits[id] = nil; anims[id] = nil; PixelArt.faces[id] = nil
            removed += 1
        }
        return removed
    }

    /// Genesis: everything of the old world is deleted and a new one generated.
    /// The world's name, the player's look and the assets that look needs are kept.
    func doGenesis(_ plan: LawPlan) {
        guard let old = society else { return }
        epoch += 1                                                             // photo jobs of the old world are void
        deselect()
        placingAsset = nil
        lawRun = nil
        let g = Society.genesis(old: old, plan: plan, villages: recipe?.villages ?? 4, per: recipe?.perVillage ?? 30, startTech: recipe?.startTech ?? 0)
        world = g.world
        society = g.society
        society.zh = GameModel.zh
        if recipe != nil { recipe!.seed = plan.newSeed }
        var r = g.result
        r.assetsRemoved = collectAssets()
        loadAssets()
        playerPortrait = playerLook.portrait.flatMap { portraits[$0] }
        var start = Vec2(8, 8)
        if let first = society.settlements.values.sorted(by: { $0.id < $1.id }).first { start = world.findFree(near: first.center + TilePos(0, 4), maxR: 8).center }
        let sc = GameScene(size: CGSize(width: 874, height: 402))
        sc.scaleMode = .resizeFill
        sc.model = self
        sc.player = start
        sc.flashOnAppear = true
        scene = sc
        lastLogCount = society.log.count
        let ok = save(announce: false)
        if ok { LawJournal.clear(saveDir) }
        r.bytesBefore = lawBefore
        r.bytesAfter = totalBytes()
        lawBusy = false
        lawReport = describe(r) + String(format: L(" · 新种子 %d", " · new seed %d"), plan.newSeed)
        showToast(lawReport)
        refreshStorage()
        refreshRealm()
    }

    /// Finish a law whose journal was still on disk when the world was opened.
    func recoverLaw(_ plan: LawPlan) {
        lawBefore = totalBytes()
        if plan.mode == .genesis { doGenesis(plan) }
        else {
            let run = society.beginLaw(plan)
            while !run.step(400) {}
            finishLaw(run.result, plan: plan)
        }
        showToast(L("已完成上次被中断的世界法则：", "Finished the world law that was interrupted: ") + lawReport)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let c = RGBA(hex: hex)
        self.init(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(UIColor(hex: hex)) }
}
