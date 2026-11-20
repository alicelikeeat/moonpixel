import SwiftUI
import SpriteKit
import MoonPixelCore

/// A clickable news item (war, siege, a capital lost...). Tapping it points the camera there.
struct Notice: Identifiable, Equatable {
    var id: Int
    var text: String
    var pos: Vec2
    var kind: String
    var until: Date
    static func == (a: Notice, b: Notice) -> Bool { a.id == b.id }
}

/// What the camera is looking at. The player's character stays where it is either way.
enum Watch: Equatable { case none, point(Vec2), legion(Int) }

/// Building, crafting, the underground, cities, the chronicle and watching wars.
extension GameModel {
    // MARK: layers
    var depth: Int { society?.realm.player.depth ?? 0 }
    /// The layer the player is on: the surface, or the underground.
    var activeWorld: OpenWorld { depth == 0 ? world : society.layer(depth) }

    /// Anything that changes the world waits while a world law is running or its result is not yet saved.
    var worldLocked: Bool { lawBusy || lawSavePending || lawCommitting || exitBlocked != nil }

    // MARK: building
    func chooseBuild(_ key: String) {
        if worldLocked { showToast(L("世界法则尚未完成保存，暂时不能建造", "A world law has not been saved yet; building is paused")); return }
        buildMode = key
        pendingPlan = nil
        previewText = ""
        showBuild = false
        if key == "demolish" { showToast(L("拆除模式：点击要拆除的建筑格，返还一半材料", "Demolish: tap a built tile to take it down and get half back")) }
        else if let p = Piece.byKey[key] { showToast(String(format: L("建造「%@」：点按放置一格，拖动连续铺设，再按确认", "Building %@: tap for one tile, drag for a line, then confirm"), p.name(zh: GameModel.zh))) }
    }

    func stopBuilding() { buildMode = ""; pendingPlan = nil; previewText = ""; scene?.clearPreview() }

    /// Called by the scene while the finger is down: a fresh plan and its preview, nothing paid yet.
    func planCells(_ cells: [TilePos]) {
        guard let s = society, Piece.byKey[buildMode] != nil else { return }
        planSeq += 1
        let plan = BuildPlan(id: planSeq, piece: buildMode, cells: cells)
        pendingPlan = plan
        let pre = s.previewBuild(plan, in: activeWorld)
        scene?.showPreview(pre)
        let cost = pre.cost.sorted { $0.key < $1.key }.map { Recipe.goodName($0.key, zh: GameModel.zh) + " " + String(format: "%g", $0.value) }.joined(separator: " · ")
        let bad = pre.cells.count - pre.valid
        previewText = String(format: L("%d 格可放置%@ · 需要 %@%@", "%d tiles%@ · cost %@%@"), pre.valid,
                             bad > 0 ? String(format: L("（%d 格无效）", " (%d invalid)"), bad) : "",
                             cost.isEmpty ? "-" : cost, pre.affordable ? "" : L(" · 材料不足", " · not enough materials"))
    }

    func confirmBuild() {
        guard let plan = pendingPlan, let s = society, let sc = scene else { return }
        if worldLocked { return }
        let r = s.commitBuild(plan, in: activeWorld, player: sc.player)
        switch r.reason {
        case "": showToast(String(format: L("已放置 %d 格", "Placed %d tiles"), r.placed))
        case "cost": showToast(L("材料不足：去采集、采矿或制造", "Not enough materials: gather, mine or craft"))
        case "duplicate": showToast(L("这个计划已经执行过", "That plan was already carried out"))
        default: showToast(L("没有可以放置的格子", "Nothing can be placed there"))
        }
        if let m = r.moved { sc.player = m }
        pendingPlan = nil
        previewText = ""
        sc.clearPreview()
        markStorageDirty()
    }

    func demolish(at t: TilePos) {
        guard let s = society, !worldLocked else { return }
        // a landmark's part (a hall, a gate, a courtyard house) or a building inside it comes down whole
        if depth == 0, let part = s.demolishLandmarkPart(at: t) {
            showToast(String(format: L("拆除了 %@，回收部分石料", "Took down %@ and got some stone back"), part))
            return
        }
        if let p = s.demolishBuild(at: t, in: activeWorld) { showToast(String(format: L("拆除了%@，回收一半材料", "Took down the %@ and got half back"), p.name(zh: GameModel.zh))) }
        else { showToast(L("这里没有可拆除的建筑", "Nothing built here to take down")) }
    }

    // MARK: things within reach on any layer
    /// Levers, gates, doors, stairs, ruin chests, maze chests and flowers. Returns true when the tap was used.
    func reach(_ t: TilePos) -> Bool {
        guard let sc = scene, let s = society, (t - sc.player.tile).lengthSquared <= 9 else { return false }
        let w = activeWorld
        let key = Content.shared.tile(w.tile(2, t.x, t.y))?.key ?? ""
        if key == "supply_box" {
            invoke(.openBox(t.x, t.y, depth: depth))
            return true
        }
        if key == "stairs_down" || key == "stairs_up" {
            if let r = s.useStairs(at: t.center) { switchLayer(to: r.pos) }
            return true
        }
        let done = s.interact(at: t, in: w)
        if !done.isEmpty {
            let says: [String: String] = ["lever_on": L("拉杆：开", "Lever on"), "lever_off": L("拉杆：关", "Lever off"), "gate_open": L("城门打开", "Gate opened"),
                                          "gate": L("城门关闭", "Gate closed"), "door_open": L("铁门打开", "Door opened"), "door": L("铁门关闭", "Door closed")]
            showToast(says[done] ?? done)
            return true
        }
        if depth == 1 {
            let v = s.playerOpenVault(at: t)
            if v.ok {
                if let p = v.power { showToast(String(format: L("地下城宝库：粮木石各 +30，并获得神器「%@」", "Underground city vault: +30 food, wood and stone, and the artifact \"%@\""), p.name(zh: GameModel.zh))) }
                else { showToast(L("地下城宝库：粮木石各 +30", "Underground city vault: +30 food, wood and stone")) }
                sc.firework(at: CGPoint(x: t.center.x, y: -(t.center.y - 30)))
                refreshPowers()
                return true
            }
        }
        if depth == 1, let loot = s.playerOpenRuin(at: t) {
            let list = loot.sorted { $0.key < $1.key }.map { Recipe.goodName($0.key, zh: GameModel.zh) + " +\(Int($0.value))" }.joined(separator: L("、", ", "))
            showToast(L("遗迹宝箱：", "Ruin chest: ") + list)
            sc.firework(at: CGPoint(x: t.center.x, y: -(t.center.y - 30)))
            return true
        }
        return depth == 0 && tapWorld(t)
    }

    /// Change between the surface and the underground.
    func switchLayer(to pos: Vec2) {
        guard let sc = scene else { return }
        sc.player = pos
        // between the surface and its storeys the old picture stays until the new one is ready; underground it does not
        let wasUnder = sc.chunkKeys.values.contains { $0.depth == 1 }
        sc.resetLayer(keepChunks: depth != 1 && !wasUnder)
        following = false
        watch = .none
        if depth == SkyTune.depth {
            showToast(L("天空城：岛中央的楼梯直通下方地面；东侧空港可以坐飞机或飞碟去别处", "A sky city: the stairway in the middle goes straight down to the ground; its airport to the east flies planes and saucers"))
            return
        }
        if depth >= OpenWorld.storeyBase {
            let n = depth - OpenWorld.storeyBase
            showToast(String(format: L("第 %d 层：只能站在楼板上；墙下三格内可以铺楼板，放“向上楼梯”可以继续往上盖", "Storey %d: stand only on floors; lay floor within three tiles of a wall below; place Stairs up to build higher"), n))
            return
        }
        showToast(depth > 0 ? L("进入地下：用镐挖掘岩壁和矿脉，阶梯可以返回地面", "Underground: dig rock and ore with the pick; take the stairs back up")
                            : L("回到地面", "Back on the surface"))
    }

    /// Always possible underground: cut a way up where you stand.
    func climbOut() {
        guard let sc = scene, let s = society, depth == 1 else { return }
        switchLayer(to: s.climbOut(from: sc.player))
    }

    func dig(at t: TilePos) -> Bool {
        guard let s = society, !worldLocked, let r = s.playerDig(at: t, in: activeWorld) else { return false }
        showToast(String(format: L("获得 %@ +%g", "Got %@ +%g"), Recipe.goodName(r.good, zh: GameModel.zh), r.amount))
        return true
    }

    // MARK: crafting
    func craft(_ key: String) {
        guard let s = society, let sc = scene else { return }
        switch s.playerCraft(key, near: sc.player, in: activeWorld) {
        case nil: showToast(String(format: L("开始制作：%@", "Crafting: %@"), Recipe.byKey[key]?.name(zh: GameModel.zh) ?? key))
        case "busy": showToast(L("上一件还没做好", "The last job is not finished yet"))
        case let why?:
            if why.hasPrefix("station:") {
                let st = String(why.dropFirst(8))
                showToast(String(format: L("需要站在%@旁边（可在建造面板放置）", "Stand next to a %@ (place one from the Build panel)"), Content.shared.tile(Content.shared.tid(st)).map { GameModel.zh ? $0.nameZh : $0.nameEn } ?? st))
            } else if why.hasPrefix("input:") {
                showToast(String(format: L("缺少%@", "Missing %@"), Recipe.goodName(String(why.dropFirst(6)), zh: GameModel.zh)))
            }
        }
        refreshCraft()
    }

    func refreshCraft() {
        guard let s = society else { return }
        var pack: [String] = []
        for g in Recipe.goods { let v = s.carried(g.0); if v >= 0.25 { pack.append((GameModel.zh ? g.2 : g.1) + " " + String(format: "%g", (v * 4).rounded() / 4)) } }
        packLine = pack.isEmpty ? L("背包是空的", "Your pack is empty") : pack.joined(separator: " · ")
        if let job = s.realm.player.craft, let r = Recipe.byKey[job.recipe] {
            let left = max(0, job.done - s.world.time) / Society.hour
            craftLine = String(format: L("正在制作 %@，还需约 %.1f 小时", "Making %@, about %.1f h left"), r.name(zh: GameModel.zh), left)
        } else { craftLine = "" }
    }

    // MARK: cities
    func refreshCities() {
        guard let s = society else { return }
        cityRows = s.cityLabels(far: false).map { c in
            let info = s.cityInfo(c.id)
            return CityRow(id: c.id, name: c.name, nation: s.realm.nation(c.nation)?.name(zh: GameModel.zh) ?? "-", color: s.realm.nation(c.nation)?.color ?? "#ffffff",
                           kind: info?.kindName ?? "", capital: c.capital, siege: c.siege, pop: info?.pop ?? 0, pos: c.pos)
        }
        if let id = cityDetailID { cityDetail = s.cityInfo(id) }
    }

    func petitionCapital(_ id: Int) {
        guard let s = society else { return }
        let says: [String: String] = ["nation": L("只能为你所属国家的城市申请", "Only for a city of your own nation"), "already": L("这里已经是首都", "This is already the capital"),
                                      "moving": L("迁都正在进行", "A move is already under way"), "siege": L("城市正被围攻", "The city is under siege"),
                                      "palace": L("需要王宫或王座", "It needs a palace or a throne"), "people": String(format: L("人口不足 %d", "Needs %d people"), s.realm.cfg.capitalPop),
                                      "food": L("存粮不足", "Not enough food in store")]
        if let why = s.petitionCapital(id) { showToast(says[why] ?? why) }
        else { showToast(L("迁都已开始：备齐物资并经过一段时间后正式迁都", "The move has begun: once stores are ready and time has passed, the court moves")) }
        refreshCities()
    }

    func registerCityHere(_ name: String) {
        guard let s = society, let sc = scene, depth == 0, !worldLocked else { return }
        let says: [String: String] = ["nation": L("先加入一个国家", "Join a nation first"), "maze": L("UFO 机场和火山上不能建城", "Not on a UFO airport or a volcano"),
                                      "close": String(format: L("离其他城镇太近（至少 %d 格）", "Too close to another town (at least %d tiles)"), s.realm.cfg.cityMinGap),
                                      "limit": L("城镇数量已达上限", "Too many towns already"),
                                      "beds": String(format: L("附近需要至少 %d 张铺在地板上的床", "Needs at least %d beds on floors nearby"), s.realm.cfg.cityBeds),
                                      "store": L("附近需要一个仓库", "Needs a warehouse chest nearby"),
                                      "food": String(format: L("需要随身携带 %g 份粮食", "Bring %g food"), s.realm.cfg.cityFood)]
        if let why = s.registerCity(at: sc.player.tile, name: name) { showToast(says[why] ?? why) }
        else { showToast(L("城市已登记，居民会陆续迁入", "The city is registered; people will move in")) }
        refreshCities()
    }

    // MARK: chronicle and notices
    func refreshChronicle() {
        guard let s = society else { return }
        chronRows = s.chronicleView(majorOnly: chronMajorOnly, limit: 120).map { v in
            let year = Int(v.entry.t / MP.year) + 1
            var place = v.place
            if v.gone { place = (place.isEmpty ? "" : place + " · ") + L("此地已不存在", "this place is gone") }
            return ChronRow(id: v.entry.id, text: String(format: L("第 %d 年 · ", "Year %d · "), year) + v.entry.text, place: place,
                            major: v.entry.major, pos: Vec2(v.entry.x, v.entry.y), gone: v.gone, locatable: v.entry.x != 0 || v.entry.y != 0)
        }
    }

    static let noticeKinds: Set<String> = ["war", "siege", "breach", "battle", "captured", "capital_lost", "capital_moved", "capital_restored", "truce", "unified", "split", "repelled", "fell"]

    /// New events since the last look, by id (not by how many lines the log has).
    func pollEvents() {
        guard let s = society else { return }
        let fresh = s.events(after: lastSeenEvent)
        guard let last = fresh.last else { return }
        lastSeenEvent = last.id
        showNews(last.text)
        for e in fresh where GameModel.noticeKinds.contains(e.kind) {
            notices.append(Notice(id: e.id, text: e.text, pos: Vec2(e.x, e.y), kind: e.kind, until: Date().addingTimeInterval(14)))
        }
        if notices.count > 3 { notices.removeFirst(notices.count - 3) }
    }

    func expireNotices() {
        let now = Date()
        if notices.contains(where: { $0.until < now }) { notices.removeAll { $0.until < now } }
    }

    // MARK: watching
    func look(at p: Vec2) {
        guard p.x != 0 || p.y != 0 else { return }
        if depth > 0 { showToast(L("先回到地面", "Go back to the surface first")); return }
        watch = .point(p)
        showChronicle = false; showCities = false; showWar = false; showMap = false
        scene?.zoom = max(0.6, min(scene?.zoom ?? 1, 1.5))
    }

    func follow(legion id: Int) {
        if depth > 0 { showToast(L("先回到地面", "Go back to the surface first")); return }
        watch = .legion(id)
        showWar = false
    }

    func stopWatching() { watch = .none }

    var watchLabel: String {
        switch watch {
        case .none: return ""
        case .point: return L("观战镜头 · 角色仍在原地", "Watching · your character stays where it is")
        case .legion(let id):
            if let l = society?.legionInfos().first(where: { $0.id == id }) { return String(format: L("跟随 %@ 军团（%d 人，%@）", "Following %@ army (%d, %@)"), l.name, l.count, l.state) }
            return L("军团已解散", "The army has disbanded")
        }
    }

    /// The war panel's line of losses: prisoners taken from each side (nobody is killed), and held now.
    func prisonerLine(_ ledger: CasualtyLedger) -> String {
        let taken: [String] = society.realm.nations.map { n in n.name(zh: GameModel.zh) + " \(ledger.fallen(n.id))" }
        var line: String = L("被俘（无人阵亡）", "Taken prisoner (nobody is killed)") + " · " + taken.joined(separator: " · ")
        let held = society.prisoners().sorted { $0.key < $1.key }
        if !held.isEmpty {
            let parts: [String] = held.map { society.nationName($0.key) + " \($0.value)" }
            line += L(" · 现押战俘 ", " · held now ") + parts.joined(separator: " · ")
        }
        return line
    }

    func refreshWar() {
        guard let s = society else { return }
        warRows = s.legionInfos().map { l in
            let u = l.units
            var mix = String(format: L("步 %d · 弓 %d · 骑 %d · 器械 %d · 补给 %d", "foot %d · bow %d · horse %d · engines %d · supply %d"), u[0], u[1], u[2], l.engines, u[4])
            // the machines it took to war (by its nation's age): tanks, Humvees, troop carriers, rocket trucks, fighters, drones
            if !l.kit.isEmpty { mix = L("装备：", "Kit: ") + l.kit.map { WarKit.name($0.kind, zh: GameModel.zh) + " \($0.count)" }.joined(separator: L("、", ", ")) + " · " + mix }
            else { mix = L("冷兵器时代（工业时代后才有装甲车辆）· ", "before industry (armour comes with industry) · ") + mix }
            return WarRow(id: l.id, title: String(format: L("%@ 军团 · %d 人 · %@%@", "%@ army · %d · %@%@"), l.name, l.count, l.state, l.target.isEmpty ? "" : " → " + l.target),
                          detail: mix + String(format: L(" · 士气 %d%% · 军粮 %d · 补给 %d%%%@", " · morale %d%% · rations %d · supply %d%%%@"), Int(l.morale * 100), Int(l.food), Int(l.supply * 100),
                                                     l.forded ? L(" · 无路可走，涉水行军", " · no road, wading") : ""),
                          color: l.color, pos: l.pos)
        }
    }

    func startDemoWar() {
        guard let s = society else { return }
        let a = s.realm.player.nation != 0 ? s.realm.player.nation : 1
        let b = s.realm.nations.first { $0.id != a && $0.exileSince == nil }?.id ?? 2
        if let id = s.stageCampaign(attacker: a, defender: b) { follow(legion: id); showToast(L("战争开始：镜头正在跟随出征军团", "War: the camera follows the army")) }
        else { showToast(L("现在无法开战", "No war can start right now")) }
        showCheats = false
    }

    // MARK: law saving that failed
    func retryLawSave() {
        guard lawSavePending else { return }
        save(announce: false, purge: true) { [weak self] ok, _ in
            guard let self = self else { return }
            if ok {
                LawJournal.clear(self.saveDir)
                self.lawSavePending = false
                _ = self.collectAssets()
                self.showToast(L("已保存，世界法则完成", "Saved: the world law is complete"))
            } else {
                self.showToast(L("仍然无法保存：请释放手机存储空间后重试", "Still cannot save: free some storage on the phone and try again"))
            }
        }
    }

    // MARK: storage figures without walking the disk every frame
    func markStorageDirty() { assetCacheAt = .distantPast }
}

struct CityRow: Identifiable { var id: Int; var name: String; var nation: String; var color: String; var kind: String; var capital: Bool; var siege: Bool; var pop: Int; var pos: Vec2 }
struct ChronRow: Identifiable { var id: Int; var text: String; var place: String; var major: Bool; var pos: Vec2; var gone: Bool; var locatable: Bool }
struct WarRow: Identifiable { var id: Int; var title: String; var detail: String; var color: String; var pos: Vec2 }

// MARK: - panels

struct BuildPanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("建造", "Build"), subtitle: L("选择后在场景中点按或拖动，确认前不扣材料", "Pick, then tap or drag in the world; nothing is paid until you confirm"), close: { model.showBuild = false }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.packLine).font(.system(size: 11, design: .rounded)).opacity(0.85)
                ForEach(0..<Piece.groupNames.count, id: \.self) { g in
                    Text(L(Piece.groupNames[g].1, Piece.groupNames[g].0)).font(.system(size: 13, weight: .bold, design: .rounded))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(Piece.all.filter { $0.group == g }, id: \.key) { p in card(p) } }
                    }
                }
                HStack(spacing: 6) {
                    Chip(title: L("拆除", "Demolish"), icon: "hammer.fill", id: "build-demolish") { model.chooseBuild("demolish") }
                    Chip(title: L("补给站", "Supply depot"), icon: "shippingbox.fill", id: "build-depot") { model.chooseBuild("depot") }
                    Chip(title: L("外置电梯", "Outside elevator"), icon: "arrow.up.arrow.down.square.fill", id: "build-lift") { model.showBuild = false; model.buildLiftHere() }
                    if model.depth == 1 { Chip(title: L("就地挖出地面", "Climb out here"), icon: "arrow.up.circle.fill", id: "climb-out") { model.showBuild = false; model.climbOut() } }
                }
            }
        }
        .onAppear { model.refreshCraft() }
    }

    private func card(_ p: Piece) -> some View {
        Button { model.chooseBuild(p.key) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name(zh: GameModel.zh)).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(p.cost.map { Recipe.goodName($0.0, zh: GameModel.zh) + " " + String(format: "%g", $0.1) }.joined(separator: " · "))
                    .font(.system(size: 9, design: .rounded)).opacity(0.75).lineLimit(1)
            }
            .padding(8).frame(width: 128, height: 46, alignment: .topLeading)
            .background(Color.white.opacity(model.buildMode == p.key ? 0.34 : 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("piece-" + p.key)
    }
}

struct CraftPanel: View {
    @EnvironmentObject var model: GameModel

    /// "Iron ore 2 + Wood 1 → Iron 1 · Furnace · 2 h", built in small steps (one long expression is too much for the type checker).
    static func line(_ r: Recipe) -> String {
        func list(_ l: [(String, Double)]) -> String {
            var parts: [String] = []
            for (g, n) in l { parts.append(Recipe.goodName(g, zh: GameModel.zh) + " " + String(format: "%g", n)) }
            return parts.joined(separator: " + ")
        }
        let station: String = Content.shared.tile(Content.shared.tid(r.station)).map { GameModel.zh ? $0.nameZh : $0.nameEn } ?? r.station
        let hours: String = String(format: L(" · %g 小时", " · %g h"), r.hours)
        return list(r.inputs) + " → " + list(r.outputs) + " · " + station + hours
    }

    var body: some View {
        GlassSheet(title: L("制造", "Craft"), subtitle: L("站在对应设施旁制作；投入的材料开工时扣除", "Stand next to the station; inputs are taken when work starts"), close: { model.showCraft = false }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.packLine).font(.system(size: 11, design: .rounded)).opacity(0.85).accessibilityIdentifier("pack")
                if !model.craftLine.isEmpty { Text(model.craftLine).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.9, blue: 0.6)) }
                ForEach(Recipe.all, id: \.key) { r in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name(zh: GameModel.zh)).font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(CraftPanel.line(r)).font(.system(size: 10, design: .rounded)).opacity(0.8)
                        }
                        Spacer(minLength: 4)
                        Chip(title: L("制作", "Make"), icon: "hammer.fill", id: "craft-" + r.key) { model.craft(r.key) }
                    }
                    .padding(8).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .onAppear { model.refreshCraft() }
    }
}

struct CitiesPanel: View {
    @EnvironmentObject var model: GameModel
    @State private var newName = ""

    var body: some View {
        GlassSheet(title: L("城市", "Cities"), subtitle: L("★ 首都 · ⚔ 被围攻 · 点击查看详情", "★ capital · ⚔ under siege · tap for details"), close: { model.showCities = false; model.cityDetailID = nil }) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.cityRows) { c in
                        Button { model.cityDetailID = c.id; model.refreshCities() } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: c.color)).frame(width: 9, height: 9)
                                Text((c.capital ? "★ " : "") + c.name + (c.siege ? " ⚔" : "")).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                                Spacer(minLength: 2)
                                Text("\(c.kind) · \(c.pop)").font(.system(size: 10, design: .rounded)).opacity(0.75).lineLimit(1)
                            }
                            .padding(.horizontal, 10).frame(height: 34)
                            .background(Color.white.opacity(model.cityDetailID == c.id ? 0.26 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("city-\(c.id)")
                    }
                    HStack(spacing: 6) {
                        TextField(L("新城名称", "New city name"), text: $newName).font(.system(size: 12, design: .rounded))
                            .padding(.horizontal, 10).frame(height: 34).background(Color.white.opacity(0.12), in: Capsule())
                        Chip(title: L("在此建城", "Found here"), icon: "flag.fill", id: "found-city") { model.registerCityHere(newName) }
                    }
                }
                .frame(width: 300)
                if let d = model.cityDetail { detail(d) }
            }
        }
        .onAppear { model.refreshCities() }
    }

    private func detail(_ d: Society.CityInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: d.color)).frame(width: 10, height: 10)
                Text(d.name).font(.system(size: 16, weight: .bold, design: .rounded))
                Text(d.nation + " · " + d.kindName + (d.capital ? L(" · 首都", " · capital") : "")).font(.system(size: 11, design: .rounded)).opacity(0.85)
            }
            Text(String(format: L("人口 %d · 士兵 %d · 无房 %d · 城墙 %d 格 · 城门 %d · 治理 %d%% · 不满 %d%%", "%d people · %d soldiers · %d homeless · %d wall tiles · %d gates · governance %d%% · unrest %d%%"),
                        d.pop, d.soldiers, d.homeless, d.wallCount, d.gateCount, Int(d.governance * 100), Int(d.unrest * 100)))
                .font(.system(size: 11, design: .rounded))
            if !d.former.isEmpty { Text(String(format: L("曾是 %@ 的首都", "Once the capital of %@"), d.former)).font(.system(size: 11, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.85, blue: 0.5)) }
            if d.siege { Text(L("正被围攻：运输与补给受阻", "Under siege: transport and supply are cut")).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.red) }
            Text(d.stocks.map { "\($0.0) \($0.1)" }.joined(separator: " · ")).font(.system(size: 10, design: .rounded)).opacity(0.85)
            ForEach(Array(d.landmarks.enumerated()), id: \.offset) { _, l in
                Button { model.look(at: l.pos) } label: {
                    Text("· \(l.name)：\(l.function)（\(l.state)）").font(.system(size: 11, design: .rounded)).foregroundStyle(l.damaged ? Color.orange : Color.white).multilineTextAlignment(.leading)
                }
                .buttonStyle(PressStyle())
            }
            ForEach(d.stations, id: \.self) { Text("· " + $0).font(.system(size: 10, design: .rounded)).opacity(0.75) }
            ForEach(d.history, id: \.self) { Text($0).font(.system(size: 10, design: .rounded)).opacity(0.7) }
            HStack(spacing: 6) {
                Chip(title: L("定位", "Show"), icon: "scope", id: "city-locate") { model.look(at: d.pos) }
                Chip(title: L("申请定为首都", "Petition for capital"), icon: "crown.fill", id: "city-capital") { model.petitionCapital(d.id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChroniclePanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("纪事", "Chronicle"), subtitle: L("按事件编号记录 · 点击定位", "Every event has its number · tap to locate"), close: { model.showChronicle = false }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Chip(title: L("重要历史", "Major history"), icon: "books.vertical.fill", tint: Color.white.opacity(model.chronMajorOnly ? 0.34 : 0.14), id: "chron-major") { model.chronMajorOnly = true; model.refreshChronicle() }
                    Chip(title: L("全部", "Everything"), icon: "list.bullet", tint: Color.white.opacity(model.chronMajorOnly ? 0.14 : 0.34), id: "chron-all") { model.chronMajorOnly = false; model.refreshChronicle() }
                }
                ForEach(model.chronRows) { r in
                    Button { if r.locatable { model.look(at: r.pos) } } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("#\(r.id) " + r.text).font(.system(size: 12, weight: r.major ? .semibold : .regular, design: .rounded)).multilineTextAlignment(.leading)
                            if !r.place.isEmpty { Text(r.place).font(.system(size: 10, design: .rounded)).foregroundStyle(r.gone ? Color.orange : Color.white.opacity(0.7)) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .onAppear { model.refreshChronicle() }
    }
}

struct WarPanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("战争", "War"), subtitle: L("军团、补给与士气 · 跟随或定位战场", "Armies, supply and morale · follow one or locate the battle"), close: { model.showWar = false }) {
            VStack(alignment: .leading, spacing: 6) {
                if model.warRows.isEmpty { Text(L("现在没有军团出征", "No army is in the field")).font(.system(size: 12, design: .rounded)).opacity(0.75) }
                ForEach(model.warRows) { r in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: r.color)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(r.detail).font(.system(size: 10, design: .rounded)).opacity(0.8)
                        }
                        Spacer(minLength: 4)
                        Chip(title: L("跟随", "Follow"), icon: "video.fill", id: "war-follow-\(r.id)") { model.follow(legion: r.id) }
                        Chip(title: L("送军粮", "Rations"), icon: "fork.knife", id: "war-feed-\(r.id)") {
                            let n = model.society.playerFeedLegion(near: r.pos)
                            model.showToast(n > 0 ? String(format: L("送去军粮 %d", "Sent %d rations"), Int(n)) : L("需要走到本国军团附近，并携带粮食", "Walk up to an army of your nation with food in your pack"))
                            model.refreshWar()
                        }
                    }
                    .padding(8).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                // losses come from the casualty ledger only: the same numbers whether a battle was watched or not
                let ledger = model.society.realm.ledger
                if ledger.total > 0 {
                    // nobody is killed in war: the losses are prisoners (held now, by whom)
                    Text(model.prisonerLine(ledger))
                        .font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.85)
                        .accessibilityIdentifier("war-fallen")
                    ForEach(ledger.battles.suffix(3).reversed(), id: \.key) { b in
                        Text(b.nations.map { id in "\(model.society.realm.nation(id)?.name(zh: GameModel.zh) ?? "?") −\(b.losses["\(id)"] ?? 0)" }.joined(separator: "  "))
                            .font(.system(size: 10, design: .rounded)).opacity(0.7)
                    }
                }
                Text(L("修桥铺路能让军团走得更快更稳；拆桥、截断补给车队会让敌军断粮、士气下降。",
                       "Bridges and roads let armies march faster and better supplied; breaking bridges and cutting supply trains starves the enemy and breaks their spirit."))
                    .font(.system(size: 10, design: .rounded)).opacity(0.6)
            }
        }
        .onAppear { model.refreshWar() }
    }
}

/// Everything that does not fit on the tab bar, as one glass sheet (a menu overflowed in landscape).
struct MorePanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("更多", "More"), subtitle: "", close: { model.showMore = false }) {
            VStack(alignment: .leading, spacing: 8) {
                group(L("世界与城市", "World and towns")) {
                    Chip(title: L("制造", "Craft"), icon: "hammer.fill", id: "Craft") { model.showMore = false; model.showCraft = true }
                    Chip(title: L("城市", "Cities"), icon: "building.columns.fill", id: "Cities") { model.showMore = false; model.showCities = true }
                    Chip(title: L("战争", "War"), icon: "shield.lefthalf.filled", id: "War") { model.showMore = false; model.showWar = true }
                    Chip(title: L("纪事", "History"), icon: "book.closed.fill", id: "History") { model.showMore = false; model.showChronicle = true }
                    Chip(title: L("法则", "Laws"), icon: "flame.fill", id: "Laws") { model.showMore = false; model.showLaws = true }
                }
                group(L("玩法", "Ways to play")) {
                    Chip(title: L("都市模式", "Metro"), icon: "building.2.crop.circle.fill", id: "Metro") { model.showMore = false; model.startMetro() }
                    Chip(title: L("指挥模式", "Command"), icon: "flag.2.crossed.fill", id: "Command") { model.showMore = false; model.startCommand() }
                    Chip(title: model.render3D ? L("2D 视角", "2D view") : L("3D 视角", "3D view"), icon: model.render3D ? "square.grid.3x3.fill" : "cube.fill", id: "View3D") {
                        model.showMore = false; model.render3D.toggle()
                    }
                    Chip(title: L("村落", "Village"), icon: "house.fill", id: "Village") { model.showMore = false; model.nextVillage() }
                }
                group(L("形象与素材", "Looks and pictures")) {
                    Chip(title: L("形象", "Photo"), icon: "person.crop.circle.badge.plus", id: "Photo") { model.showMore = false; model.pick = .player }
                    Chip(title: L("素材", "Import"), icon: "photo.badge.plus", id: "Import") { model.showMore = false; model.pick = .asset }
                }
                group(L("系统", "System")) {
                    Chip(title: L("保存", "Save"), icon: "square.and.arrow.down.fill", id: "Save") { model.showMore = false; model.save(announce: true) }
                    Chip(title: L("清理", "Clean"), icon: "sparkles", id: "Clean") { model.showMore = false; model.cleanMemory(announce: true) }
                    Chip(title: model.showPerf ? L("关闭性能", "Hide perf") : L("性能", "Performance"), icon: "speedometer", id: "Perf") {
                        model.showMore = false; model.showPerf.toggle(); if !model.showPerf { model.perfLines = [] }
                    }
                    Chip(title: L("作弊", "Cheats"), icon: "wand.and.rays", id: "Cheats") { model.showMore = false; model.showCheats = true }
                    Chip(title: L("诊断", "Diagnostics"), icon: "stethoscope", id: "Diagnostics") { model.showMore = false; model.showDiagnostics = true }
                    Chip(title: L("世界", "Worlds"), icon: "globe.asia.australia.fill", id: "Worlds") { model.showMore = false; model.exitToMenu() }
                }
                // (last, so the buttons above stay where they always were)
                group(L("视角与操作", "View and controls")) {
                    Chip(title: model.viewMode == .first ? L("第三人称", "Third person") : L("第一人称", "First person"), icon: model.viewMode == .first ? "person.fill.viewfinder" : "eye.fill", id: "ViewFirst") {
                        model.showMore = false; model.viewMode = model.viewMode == .first ? .third : .first; if !model.render3D { model.render3D = true }
                    }
                    Chip(title: L("交通管理", "Transport"), icon: "tram.fill", id: "Transport") { model.showMore = false; model.showTransport = true }
                    Chip(title: L("都市并入开放世界", "Bring the metro city in"), icon: "building.2.fill", id: "MetroImport") { model.showMore = false; model.importMetroCity() }
                    Chip(title: model.artStyle == .anime ? L("像素风格", "Pixel style") : L("动漫风格", "Anime style"), icon: "paintbrush.pointed.fill", id: "ArtStyle") {
                        model.showMore = false; model.artStyle = model.artStyle == .anime ? .pixel : .anime
                    }
                }
                // (its own row: one row per group, and the row above was already as wide as a phone)
                group(L("角色与瞬移", "Figures and teleport")) {
                    Chip(title: L("瞬移中心", "Teleport centre"), icon: "sparkles", id: "TeleportCentre") { model.showMore = false; model.showTeleport = true }
                    Chip(title: L("3D 精细度：", "3D detail: ") + [L("标准", "standard"), L("高", "high"), L("极高", "very high")][max(0, min(2, model.modelDetail - 1))], icon: "cube.transparent.fill", id: "ModelDetail") {
                        // standard -> high (4x faces on curves) -> very high (9x) -> standard
                        model.modelDetail = model.modelDetail % 3 + 1
                    }
                    Chip(title: L("我的角色：", "My figure: ") + (CharacterModels.of(model.playerLook.model).map { GameModel.zh ? $0.zh : $0.en } ?? L("普通", "everyday")), icon: "person.fill.questionmark", id: "PlayerModel") {
                        // everyday -> wayfarer -> sage -> knight -> tinker -> puffling -> everyday (the sea floor's own five are for its people)
                        let keys: [String?] = [nil] + CharacterModels.land.map { $0.key }
                        let i = keys.firstIndex(of: model.playerLook.model) ?? 0
                        model.playerLook.model = keys[(i + 1) % keys.count]
                        if model.playerLook.model != nil { model.playerLook.anim = nil }
                        model.scene?.clearTextureCache()
                    }
                    Chip(title: model.figureStyle == .moe ? L("人物：萌系", "People: moe") : (model.figureStyle == .hero ? L("人物：英雄比例", "People: hero") : L("人物：天使", "People: angel")), icon: "person.crop.artframe", id: "FigureStyle") {
                        // moe -> hero -> angel (wings, halo and crown, an ivory robe with gold) -> moe
                        model.showMore = false; model.figureStyle = model.figureStyle == .moe ? .hero : (model.figureStyle == .hero ? .angel : .moe)
                    }
                }
                group(L("日夜", "Day and night")) {
                    Chip(title: L("清晨", "Dawn"), icon: "sunrise.fill", id: "time-6") { model.showMore = false; model.setTime(6) }
                    Chip(title: L("正午", "Noon"), icon: "sun.max.fill", id: "time-12") { model.showMore = false; model.setTime(12) }
                    Chip(title: L("黄昏", "Dusk"), icon: "sunset.fill", id: "time-19") { model.showMore = false; model.setTime(19) }
                    Chip(title: L("午夜", "Midnight"), icon: "moon.stars.fill", id: "time-0") { model.showMore = false; model.setTime(0) }
                }
                group(L("战争演示", "War demonstration")) {
                    Chip(title: L("双港之战", "The twin ports"), icon: "flag.2.crossed.circle.fill", id: "TwinPorts") { model.showMore = false; model.showWarDemo = true }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("转头灵敏度", "Look speed")).font(.system(size: 11, design: .rounded)).frame(width: 84, alignment: .leading)
                        Slider(value: $model.lookSensitivity, in: 0.4...2.5).accessibilityIdentifier("look-speed")
                    }
                    Toggle(L("上下反转", "Invert up and down"), isOn: $model.invertLook).font(.system(size: 11, design: .rounded)).accessibilityIdentifier("invert-look")
                    HStack {
                        Text(L("楼板透明度", "Floor see-through")).font(.system(size: 11, design: .rounded)).frame(width: 84, alignment: .leading)
                        Slider(value: $model.floorOpacity, in: 0.15...1).accessibilityIdentifier("floor-opacity")
                    }
                    Text(L("只改变画面：楼板照样承重、照样挡人。", "Only the picture changes: floors hold and stop you the same.")).font(.system(size: 9, design: .rounded)).opacity(0.6)
                }
            }
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.65)
            // one plain row per group (not a lazy grid: every button exists at once and the panel fits on screen)
            HStack(spacing: 6) { content() }
        }
    }
}
