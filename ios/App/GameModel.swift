import SwiftUI
import SpriteKit
import MoonPixelCore

/// Saved-world summary shown in the world list.
struct WorldMeta: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var seed: Int
    var savedAt: Date
    var year: Int
    var population: Int
    var diskBytes: Int
    var tech: String
}

enum PhotoPick: Equatable { case none, player, villager(Int), asset }

/// Owns the worlds, the running society and everything the SwiftUI HUD shows.
@MainActor
final class GameModel: ObservableObject {
    static let zh: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    static let speeds: [Double] = [0, 1, 4, 16, 64]
    static let weapons = ["", "sword", "bow", "staff", "axe", "pick"]
    static let mapLimitBytes = 5 * 1024 * 1024 * 1024       // 5 GB per world

    @Published var scene: GameScene?
    @Published var worlds: [WorldMeta] = []
    @Published var status = ""
    @Published var statsText = ""
    @Published var memoryText = ""
    @Published var techText = ""
    @Published var techProgress = 0.0
    @Published var mapSizeText = ""
    @Published var mapSizeFraction = 0.0
    @Published var logLines: [String] = []
    @Published var toast = ""
    @Published var toastID = 0
    @Published var speedIndex = 1
    @Published var selected: Society.TalkInfo?
    @Published var selectedID = 0
    @Published var following = false
    @Published var showDetails = false
    @Published var showMap = false
    @Published var mapImage: UIImage?
    @Published var mapCaption = ""
    @Published var autoClean = true
    @Published var weaponIndex = 1
    @Published var pick: PhotoPick = .none
    @Published var placingAsset: String? = nil
    @Published var selectedPortrait: UIImage?
    @Published var playerPortrait: UIImage?
    // three nations, world laws, storage
    @Published var nationCards: [NationCard] = []
    @Published var relationLines: [String] = []
    @Published var eraLine = ""
    @Published var playerLine = ""
    @Published var showRealm = false
    @Published var showLaws = false
    @Published var lawBusy = false
    @Published var lawProgress = 0.0
    @Published var lawReport = ""
    @Published var storageLines: [String] = []
    @Published var policy = StoragePolicy()
    @Published var limitMB = 5 * 1024
    @Published var buildMode = ""
    @Published var activePower = ""
    @Published var powerCards: [PowerCard] = []
    @Published var arsenalLines: [String] = []
    @Published var showArsenal = false
    @Published var showCheats = false
    @Published var mapPick: TilePos?
    @Published var mapZoom = 1.0
    var mapOrigin = TilePos(0, 0)
    var mapSide = 0
    @Published var lawRatio = 0.3
    @Published var lawSpaceMB = 0
    @Published var lawNewSeed = true
    @Published var lawRadius = 2
    var lawRun: LawRun?
    var lawBefore = 0
    /// Bumped whenever the world is replaced, so late photo jobs cannot land in the wrong world.
    var epoch = 0
    var limitBytes: Int { limitMB * 1024 * 1024 }
    var limitText: String { limitMB >= 1024 ? "\(limitMB / 1024) GB" : "\(limitMB) MB" }

    var world: OpenWorld!
    var society: Society!
    var worldID = ""
    var worldName = ""
    var playerLook = GameModel.defaultLook
    var assets: [String: SKTexture] = [:]
    var portraits: [String: UIImage] = [:]
    /// Animated sprites made from GIFs and videos (asset id -> frames).
    var anims: [String: [SKTexture]] = [:]
    var recipe: WorldRecipe?
    var lastLogCount = 0
    var lastSeenEvent = 0
    // v1.3: building, crafting, cities, chronicle, war watching
    @Published var showBuild = false
    @Published var showCraft = false
    @Published var showCities = false
    @Published var showChronicle = false
    @Published var showWar = false
    @Published var pendingPlan: BuildPlan?
    @Published var previewText = ""
    var planSeq = Int(Date().timeIntervalSince1970) % 1_000_000 * 1000
    @Published var packLine = ""
    @Published var craftLine = ""
    @Published var cityRows: [CityRow] = []
    @Published var cityDetailID: Int?
    @Published var cityDetail: Society.CityInfo?
    @Published var chronRows: [ChronRow] = []
    @Published var chronMajorOnly = true
    @Published var notices: [Notice] = []
    @Published var watch: Watch = .none
    @Published var warRows: [WarRow] = []
    @Published var lawSavePending = false
    @Published var actualSpeed = 1.0
    var assetCacheAt = Date.distantPast
    var assetCache = (images: 0, portraits: 0)
    var cleanCooldown = 0.0
    private var memObserver: NSObjectProtocol?

    static var defaultLook: Look { var l = Look(); l.hair = "#f0e8d0"; l.shirt = "#f4f0e0"; l.pants = "#5a5a78"; l.style = 3; return l }

    /// Save format: 3 = v1.3 (cities, campaigns, building). Absent in older saves.
    static let saveFormat = 3
    struct Index: Codable {
        var format: Int?
        var world: OpenWorld.Snapshot
        var society: Society.Snapshot
        var px: Double, py: Double
        var look: Look
        var recipe: WorldRecipe?
    }

    // MARK: world store (several worlds side by side)
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var worldsDir: URL { documents.appendingPathComponent("worlds", isDirectory: true) }
    static func dir(_ id: String) -> URL { worldsDir.appendingPathComponent(id, isDirectory: true) }
    var saveDir: URL { GameModel.dir(worldID) }
    var assetsDir: URL { saveDir.appendingPathComponent("assets", isDirectory: true) }

    func refreshWorlds() {
        let fm = FileManager.default
        try? fm.createDirectory(at: GameModel.worldsDir, withIntermediateDirectories: true)
        // adopt the single save made by earlier builds
        let legacy = GameModel.documents.appendingPathComponent("world", isDirectory: true)
        if fm.fileExists(atPath: legacy.appendingPathComponent("index.json").path) {
            try? fm.moveItem(at: legacy, to: GameModel.dir("w-legacy"))
        }
        var list: [WorldMeta] = []
        for id in (try? fm.contentsOfDirectory(atPath: GameModel.worldsDir.path)) ?? [] {
            let d = GameModel.dir(id)
            guard fm.fileExists(atPath: d.appendingPathComponent("index.json").path) else { continue }
            if let data = try? Data(contentsOf: d.appendingPathComponent("meta.json")), let m = try? JSONDecoder().decode(WorldMeta.self, from: data) {
                list.append(m)
            } else {
                list.append(WorldMeta(id: id, name: id == "w-legacy" ? L("旧存档", "Earlier save") : id, seed: 0, savedAt: .distantPast, year: 0, population: 0, diskBytes: 0, tech: ""))
            }
        }
        worlds = list.sorted { $0.savedAt > $1.savedAt }
    }

    func deleteWorld(_ id: String) {
        try? FileManager.default.removeItem(at: GameModel.dir(id))
        refreshWorlds()
    }

    /// One sentence is enough: the recipe was analysed from what the player typed.
    func createWorld(_ recipe: WorldRecipe, overrideMB: Int) {
        let id = "w\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 100..<1000))"
        start(id: id, name: recipe.suggestedName(zh: GameModel.zh, index: worlds.count + 1), seed: recipe.seed, overrideMB: overrideMB, load: false, recipe: recipe)
        if !recipe.prompt.isEmpty { showToast(L("已按你的描述创建：", "Created from your words: ") + recipe.summary(zh: GameModel.zh).prefix(4).joined(separator: " · ")) }
    }

    func openWorld(_ m: WorldMeta, overrideMB: Int) { start(id: m.id, name: m.name, seed: m.seed, overrideMB: overrideMB, load: true) }

    // MARK: lifecycle
    func handleLaunchArguments() {
        refreshWorlds()
        let args = ProcessInfo.processInfo.arguments
        guard scene == nil, let i = args.firstIndex(of: "--autostart") else { return }
        let seed = (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 7
        start(id: "w-autostart", name: "Autostart", seed: seed, overrideMB: 0, load: false)
        speedIndex = 2
        if args.contains("--select") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let sc = self.scene, let a = self.society.agent(near: sc.player, radius: 600) else { return }
                self.select(a.id)
            }
        }
        if args.contains("--map") { DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.toggleMap() } }
        if args.contains("--details") { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.showDetails = true; self?.refreshHUD() } }
        if args.contains("--powers") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                self.cheat("powers"); self.cheat("weather:3"); self.cheat("animals")
                self.showArsenal = true
            }
        }
        if args.contains("--storm") {
            // cast a few powers in a thunderstorm so the effects are on screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                self.cheat("powers"); self.cheat("god"); self.cheat("weather:3"); self.cheat("animals")
            }
            // keep casting for a while so a screenshot at any moment catches something
            let keys = ["mg", "thunder", "judgment", "perish", "meteor", "fireball", "storm", "railgun", "rocket", "sun_spear", "blackhole", "orbital"]
            for i in 0..<40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8 + Double(i) * 0.35) { [weak self] in
                    guard let self = self, let sc = self.scene else { return }
                    self.activePower = keys[i % keys.count]
                    self.society.realm.player.cooldowns = [:]
                    sc.attack(toward: sc.player + Vec2(Double((i * 67) % 300 - 150), Double((i * 41) % 160 - 110)))
                }
            }
        }
        if args.contains("--demo-war") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                self.startDemoWar()
                self.speedIndex = 3
                self.scene?.zoom = 0.8
            }
        }
        if args.contains("--demo-build") {
            // lay out a small house with a workbench and furnace, smelt iron, go down a mine and come back
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, let s = self.society, let sc = self.scene else { return }
                for g in ["wood", "stone", "iron", "parts", "iron_ore"] { s.carry(g, 200) }
                let o = sc.player.tile + TilePos(3, -2)
                var steps: [(String, [TilePos])] = []
                steps.append(("floor_wood", (0..<5).flatMap { y in (0..<6).map { TilePos(o.x + $0, o.y + y) } }))
                steps.append(("wall_stone", (0..<6).map { TilePos(o.x + $0, o.y - 1) }))
                steps.append(("bed", [TilePos(o.x + 1, o.y + 1), TilePos(o.x + 3, o.y + 1)]))
                steps.append(("workbench", [TilePos(o.x + 1, o.y + 3)]))
                steps.append(("furnace", [TilePos(o.x + 3, o.y + 3)]))
                steps.append(("lever", [TilePos(o.x - 2, o.y + 5)]))
                steps.append(("wire", [TilePos(o.x - 1, o.y + 5), TilePos(o.x, o.y + 5)]))
                steps.append(("lamp", [TilePos(o.x + 1, o.y + 5)]))
                steps.append(("stairs", [TilePos(o.x + 7, o.y + 2)]))
                for (i, st) in steps.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.6) {
                        self.buildMode = st.0
                        self.planCells(st.1)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.confirmBuild() }
                    }
                }
                let t = Double(steps.count) * 1.6 + 1
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { self.stopBuilding(); sc.player = TilePos(o.x + 2, o.y + 4).center; _ = self.reach(TilePos(o.x - 2, o.y + 5)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 1) { self.craft("iron"); self.showCraft = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 4) { self.showCraft = false; sc.player = TilePos(o.x + 7, o.y + 3).center; _ = self.reach(TilePos(o.x + 7, o.y + 2)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 7) { for k in 1...4 { _ = self.dig(at: sc.player.tile + TilePos(k, 0)) } }
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 10) { _ = self.reach(TilePos(o.x + 7, o.y + 2)) }
            }
        }
        if args.contains("--demo-city") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let s = self.society else { return }
                self.showCities = true
                self.cityDetailID = s.realm.nations.compactMap { s.capital(of: $0.id)?.id }.first
                self.refreshCities()
            }
        }
        if args.contains("--realm") { DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.showRealm = true; self?.refreshRealm() } }
        if args.contains("--laws") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.showLaws = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.runLaw(.thanos) }
        }
        if args.contains("--test-anim") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                let clip = GameModel.syntheticClip()
                self.applyMotion(clip, target: 0)
                if let sc = self.scene, let a = self.society.agent(near: sc.player, radius: 600) {
                    self.applyMotion(clip, target: a.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.select(a.id) }
                }
            }
        }
        if args.contains("--test-photo") {
            // end-to-end check of the photo pipeline with a synthetic portrait (player + nearest villager)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, let img = GameModel.syntheticPortrait() else { return }
                self.applyPhoto(img, target: 0)
                if let sc = self.scene, let a = self.society.agent(near: sc.player, radius: 600) {
                    self.applyPhoto(img, target: a.id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.select(a.id) }
                }
            }
        }
    }

    static func syntheticPortrait() -> UIImage? {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320))
        return r.image { ctx in
            UIColor(red: 0.56, green: 0.7, blue: 0.85, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
            UIColor(red: 0.85, green: 0.2, blue: 0.5, alpha: 1).setFill(); UIBezierPath(roundedRect: CGRect(x: 40, y: 215, width: 160, height: 120), cornerRadius: 30).fill()
            UIColor(red: 0.2, green: 0.25, blue: 0.7, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: 48, y: 16, width: 144, height: 168)).fill()
            UIColor(red: 0.79, green: 0.54, blue: 0.38, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: 58, y: 70, width: 124, height: 130)).fill()
        }
    }

    func start(id: String, name: String, seed: Int, overrideMB: Int, load: Bool, recipe newRecipe: WorldRecipe? = nil) {
        worldID = id
        worldName = name
        let budget = MemoryBudget(overrideMB: overrideMB)
        var index: Index?
        epoch += 1
        var corrupt = false
        var migrated = false
        let indexURL = saveDir.appendingPathComponent("index.json")
        if load, let data = try? Data(contentsOf: indexURL) {
            index = try? JSONDecoder().decode(Index.self, from: data)
            // an older save is copied aside before it is migrated, so the original can always be recovered
            if let ix = index, (ix.format ?? 2) < GameModel.saveFormat {
                let keep = saveDir.appendingPathComponent("index.v\(ix.format ?? 2)-backup.json")
                if !FileManager.default.fileExists(atPath: keep.path) { try? FileManager.default.copyItem(at: indexURL, to: keep) }
                migrated = true
            }
            if index == nil {
                // never overwrite a save we could not read: keep it beside the new one
                corrupt = true
                let keep = saveDir.appendingPathComponent("index.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: indexURL, to: keep)
            }
        }
        if !load { try? FileManager.default.removeItem(at: saveDir) }
        let w = OpenWorld(seed: index?.world.seed ?? seed, budget: budget)
        loadSettings()
        w.diskLimitBytes = limitBytes
        recipe = index?.recipe ?? (load ? nil : newRecipe)
        if let r = recipe { w.gen.tempBias = r.tempBias; w.gen.moistBias = r.moistBias; w.gen.elevBias = r.elevBias }
        w.open(directory: saveDir)
        let s = Society(world: w, seed: w.seed)
        s.zh = GameModel.zh
        if let r = recipe { s.minPopulation = r.minPopulation }
        var start = Vec2(8, 8)
        playerLook = GameModel.defaultLook
        if let ix = index {
            w.restore(ix.world)
            s.restore(ix.society)
            start = Vec2(ix.px, ix.py)
            playerLook = ix.look
        } else {
            s.grantTech(recipe?.startTech ?? 0)
            s.bootstrap(origin: TilePos(0, 0), villages: recipe?.villages ?? 4, per: recipe?.perVillage ?? 30)
            if let first = s.settlements[1] { start = w.findFree(near: first.center + TilePos(0, 4), maxR: 8).center }
        }
        world = w
        society = s
        loadAssets()
        playerPortrait = playerLook.portrait.flatMap { portraits[$0] }
        deselect()
        showMap = false
        let sc = GameScene(size: CGSize(width: 874, height: 402))
        sc.scaleMode = .resizeFill
        sc.model = self
        sc.player = start
        scene = sc
        lastLogCount = s.log.count
        lastSeenEvent = s.lastEventID
        notices = []; watch = .none; pendingPlan = nil; buildMode = ""; lawSavePending = false
        if memObserver == nil {
            memObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cleanMemory(announce: true) }
            }
        }
        refreshHUD()
        if !load { save(announce: false) }
        if migrated { showToast(L("旧存档已迁移到 1.3，原文件已另存为 index.v2-backup.json", "This save was migrated to 1.3; the original is kept as index.v2-backup.json")) }
        if corrupt { showToast(L("存档已损坏，原文件已另存为 index.corrupt，未被覆盖；世界已重新生成", "The save was damaged. It was kept as index.corrupt and not overwritten; the world was regenerated")) }
        // a world law that was interrupted (app killed, power lost) is finished now
        if load, index != nil, let j = LawJournal.read(saveDir) { recoverLaw(j.plan) }
    }

    /// Writes the world to disk. Returns false (and says so) when anything could not be written;
    /// the previous save file is left intact in that case because writes are atomic.
    @discardableResult func save(announce: Bool) -> Bool {
        guard let w = world, let s = society, let sc = scene else { return false }
        let failures = w.writeFailures, underFailures = s.under?.writeFailures ?? 0
        w.saveAll()
        s.under?.saveAll()
        var ok = w.writeFailures == failures && (s.under?.writeFailures ?? 0) == underFailures
        let ix = Index(format: GameModel.saveFormat, world: w.snapshot(), society: s.snapshot(), px: sc.player.x, py: sc.player.y, look: playerLook, recipe: recipe)
        let tech = s.techCount > 0 ? s.techName(s.techCount - 1) : ""
        let meta = WorldMeta(id: worldID, name: worldName, seed: w.seed, savedAt: Date(), year: w.year + 1, population: s.agents.count, diskBytes: totalBytes(), tech: tech)
        do {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            try JSONEncoder().encode(ix).write(to: saveDir.appendingPathComponent("index.json"), options: .atomic)
            try JSONEncoder().encode(meta).write(to: saveDir.appendingPathComponent("meta.json"), options: .atomic)
        } catch { ok = false }
        if !ok { showToast(L("保存失败：存储空间不足或文件不可写。上一次的存档仍然完好。", "Save failed: no space left or the file cannot be written. The previous save is intact.")) }
        else if announce { showToast(L("已保存", "Saved")) }
        return ok
    }

    /// Save and go back to the world list.
    func exitToMenu() {
        save(announce: false)
        scene?.isPaused = true
        scene = nil
        world = nil
        society = nil
        refreshWorlds()
    }

    // MARK: HUD
    func showToast(_ text: String) { toast = text; toastID += 1 }

    /// Bytes this world occupies on disk (chunks + index + assets).
    func mapBytes() -> Int { totalBytes() }

    func chunkAndIndexBytes() -> Int {
        guard let w = world else { return 0 }
        var n = w.diskBytes
        for f in ["index.json", "meta.json"] {
            n += ((try? FileManager.default.attributesOfItem(atPath: saveDir.appendingPathComponent(f).path)[.size]) as? NSNumber)?.intValue ?? 0
        }
        return n
    }

    static func sizeText(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: mb >= 10 ? "%.0f MB" : "%.1f MB", mb)
    }

    /// Called a few times per second from the scene.
    func refreshHUD() {
        guard let w = world, let s = society else { return }
        let h = w.hour
        status = String(format: L("第 %d 年 %02d:%02d · %d 人", "Year %d %02d:%02d · %d people"), w.year + 1, Int(h), Int(h.truncatingRemainder(dividingBy: 1) * 60), s.agents.count)
        pollEvents()
        expireNotices()
        if showDetails {
            let st = s.stats
            let houses = s.settlements.values.reduce(0) { $0 + $1.count("house", done: true) }
            statsText = String(format: L("出生 %d · 死亡 %d · 伴侣 %d\n村落 %d · 房屋 %d · 建筑 %d", "Births %d · Deaths %d · Couples %d\nVillages %d · Houses %d · Built %d"),
                               st.births, st.deaths, st.pairs, s.livingSettlements, houses, st.buildings)
            let known = s.techCount > 0 ? s.techName(s.techCount - 1) : L("原始", "Primitive")
            if s.techCount < Society.techs.count {
                techText = String(format: L("科技：%@ → 正在研究 %@（%d%%）", "Tech: %@ → researching %@ (%d%%)"), known, s.techName(s.techCount), Int(s.researchProgress * 100))
            } else {
                techText = String(format: L("科技：%@（已全部掌握）", "Tech: %@ (everything discovered)"), known)
            }
            techProgress = s.researchProgress
            let bytes = mapBytes()
            mapSizeFraction = min(1, Double(bytes) / Double(max(1, limitBytes)))
            mapSizeText = String(format: L("地图存档 %@ / %@ · 内存中 %@ · 已探明 %d 区块%@", "Map on disk %@ / %@ · in memory %@ · %d chunks mapped%@"),
                                 GameModel.sizeText(bytes), limitText, GameModel.sizeText(w.memoryBytes), w.surveyed,
                                 w.prunedFiles > 0 ? String(format: L(" · 已回收 %d 个旧区块", " · %d old chunks pruned"), w.prunedFiles) : "")
            let b = w.budget
            memoryText = String(format: L("内存：设备 %d MB · 预算 %d MB%@ · 已用 %d MB · 区块缓存 %d/%d",
                                          "Memory: device %d MB · budget %d MB%@ · used %d MB · chunk cache %d/%d"),
                                b.physicalMB, b.budgetMB, b.overrideMB > 0 ? L("（手动）", " (manual)") : L("（自动）", " (auto)"), MemoryBudget.usedMB(), w.cache.count, b.maxChunks)
            logLines = s.log.suffix(4).map { "· " + $0.text }
        }
        refreshRealm()
        if selectedID != 0 {
            if let info = s.talk(selectedID, speak: false) {
                var i = info
                i.line = selected?.line ?? info.line
                selected = i
            } else { deselect() }
        }
    }

    func tickHousekeeping(_ dt: Double) {
        cleanCooldown = max(0, cleanCooldown - dt)
        if autoClean && cleanCooldown <= 0 && world.budget.pressure() > 0.9 { cleanMemory(announce: true) }
        if world.diskBytes > world.diskLimitBytes { world.enforceDiskLimit() }
        checkPolicy()
    }

    func select(_ id: Int) {
        selectedID = id
        following = false
        selected = society.talk(id, speak: true)
        selectedPortrait = society.agents[id]?.look.portrait.flatMap { portraits[$0] }
    }

    func deselect() { selectedID = 0; selected = nil; following = false; selectedPortrait = nil }
    func talk() { if selectedID != 0 { selected = society.talk(selectedID, speak: true) } }
    func feed() { if selectedID != 0 { society.giftFood(selectedID); talk() } }
    func cycleWeapon() { weaponIndex = (weaponIndex + 1) % GameModel.weapons.count; activePower = "" }

    func nextVillage() {
        guard let sc = scene else { return }
        let list = society.settlements.values.filter { !$0.abandoned }.sorted { $0.id < $1.id }
        guard !list.isEmpty else { return }
        let cur = sc.player.tile
        let nearest = list.enumerated().min { ($0.element.center - cur).lengthSquared < ($1.element.center - cur).lengthSquared }!.offset
        let s = list[(nearest + 1) % list.count]
        sc.player = world.findFree(near: s.center + TilePos(0, 4), maxR: 8).center
        following = false
        showToast(s.name(zh: GameModel.zh))
    }

    /// One-tap cleanup: save, then drop off-screen chunks and cached textures.
    @discardableResult func cleanMemory(announce: Bool) -> Int {
        guard let w = world, let sc = scene else { return 0 }
        let before = MemoryBudget.usedMB()
        let dropped = w.purge(keep: Set(sc.chunkNodes.keys))
        let tex = sc.clearTextureCache()
        society.trimLog(12)
        cleanCooldown = 30
        let freed = max(0, before - MemoryBudget.usedMB())
        if announce {
            showToast(String(format: L("已清理：%d 个区块、%d 张贴图，释放约 %d MB", "Cleaned %d chunks, %d textures, freed ~%d MB"), dropped, tex, freed))
        }
        return dropped
    }

    // MARK: map
    func toggleMap() {
        showMap.toggle()
        if showMap { rebuildMap() }
    }

    func rebuildMap() {
        guard let w = world, let sc = scene else { return }
        let R = OpenWorld.region
        let pc = TilePos(Int((sc.player.x / 512).rounded(.down)), Int((sc.player.y / 512).rounded(.down)))
        var ext = 10
        for (k, r) in w.regions {
            for i in 0..<r.count where r[i] != 0 {
                ext = max(ext, abs(k.x * R + i % R - pc.x) + 2, abs(k.y * R + i / R - pc.y) + 2)
            }
        }
        ext = min(ext, 160)
        let side = ext * 2 + 1
        mapOrigin = TilePos(pc.x - ext, pc.y - ext)
        mapSide = side
        var bmp = Bitmap(side, side, fill: RGBA(8, 10, 18))
        let cols = Content.shared.biomes.map { RGBA(hex: $0.color) }
        for y in 0..<side { for x in 0..<side {
            let v = w.known(pc.x - ext + x, pc.y - ext + y)
            if v != 0 { bmp.set(x, y, cols[Int(v) - 1]) }
        } }
        for s in society.settlements.values {
            let x = (s.center.x >> 5) - pc.x + ext, y = (s.center.y >> 5) - pc.y + ext
            // towns in their nation's colour: the map shows who holds what
            let col = society.realm.nation(s.nation ?? 0).map { RGBA(hex: $0.color) } ?? RGBA(255, 216, 77)
            bmp.rect(x - 2, y - 2, 5, 5, RGBA(20, 20, 28))
            bmp.rect(x - 1, y - 1, 3, 3, s.abandoned ? RGBA(90, 90, 90) : col)
        }
        for lg in society.realm.legions where lg.state != 0 {
            let x = Int((lg.pos.x / 512).rounded(.down)) - pc.x + ext, y = Int((lg.pos.y / 512).rounded(.down)) - pc.y + ext
            bmp.rect(x, y, 2, 2, .white)
        }
        // old mazes in country that has been surveyed
        for y in 0..<side { for x in 0..<side where w.known(pc.x - ext + x, pc.y - ext + y) != 0 && w.gen.isMaze(pc.x - ext + x, pc.y - ext + y) {
            bmp.set(x, y, RGBA(200, 110, 255))
        } }
        bmp.rect(ext - 1, ext - 1, 3, 3, RGBA(128, 230, 255))
        if let p = mapPick {
            let x = p.x - mapOrigin.x, y = p.y - mapOrigin.y
            bmp.rect(x - 3, y, 7, 1, .white); bmp.rect(x, y - 3, 1, 7, .white)
        }
        mapImage = bmp.uiImage
        mapCaption = String(format: L("已探明 %d 个区块 · 存档 %@ / %@ · 城镇按国家着色", "%d chunks mapped · %@ of %@ on disk · towns in their nation's colour"), w.surveyed, GameModel.sizeText(mapBytes()), limitText)
    }

    // MARK: photos and assets
    func loadAssets() {
        assets.removeAll()
        portraits.removeAll()
        anims.removeAll()
        for f in (try? FileManager.default.contentsOfDirectory(atPath: assetsDir.path)) ?? [] where f.hasSuffix(".png") {
            let id = String(f.dropLast(4))
            guard let img = UIImage(contentsOfFile: assetsDir.appendingPathComponent(f).path),
                  let bmp = Bitmap(image: img, maxSide: id.hasPrefix("anim_") ? 2048 : 128) else { continue }
            if id.hasPrefix("anim_") {
                // "anim_<stamp>_n<frames>": one PNG strip holding every frame
                let n = Int(id.components(separatedBy: "_n").last ?? "") ?? 1
                anims[id] = AssetImporter.unsheet(bmp, count: n).map { $0.texture }
            }
            else if id.hasPrefix("face_") { PixelArt.faces[id] = bmp }
            else if id.hasPrefix("portrait_") { portraits[id] = bmp.uiImage }
            else { assets[id] = bmp.texture }
        }
    }

    func store(_ bmp: Bitmap, id: String) {
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        if let data = bmp.uiImage?.pngData() { try? data.write(to: assetsDir.appendingPathComponent(id + ".png")) }
    }

    /// Photo -> pixel character (target 0 = the player, otherwise a villager).
    /// Apple's on-device Vision models find the face and cut the person out; the
    /// pixel face, pixel portrait, colours and hairstyle are generated from that.
    func applyPhoto(_ image: UIImage, target: Int) {
        guard let bmp = Bitmap(image: image, maxSide: 512) else { showToast(L("无法读取图片", "Could not read the picture")); return }
        showToast(L("AI 正在生成像素角色…", "AI is generating the pixel character…"))
        let token = epoch
        // pixel work happens off the main thread; only the finished result comes back to it
        DispatchQueue.global(qos: .userInitiated).async {
            let analysis = PhotoAI.analyze(bmp)
            let result = AssetImporter.photoToCharacter(analysis.bitmap, face: analysis.face)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.photoJobStillValid(token, target) else { return }
                self.finishPhoto(result, analysis: analysis, target: target)
            }
        }
    }

    private func finishPhoto(_ r: AssetImporter.PhotoResult, analysis: PhotoAI.Analysis, target: Int) {
        guard society != nil else { return }
        let stamp = "\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 0..<100000))"
        let faceID = "face_" + stamp, portraitID = "portrait_" + stamp
        PixelArt.faces[faceID] = r.face
        store(r.face, id: faceID)
        store(r.portrait, id: portraitID)
        portraits[portraitID] = r.portrait.uiImage
        var look = r.look
        look.face = faceID
        look.portrait = portraitID
        let how = analysis.face != nil ? (analysis.segmented ? L("AI 识别了人脸并抠出人像", "AI found the face and cut the person out")
                                                             : L("AI 识别了人脸", "AI found the face"))
                                       : L("未检测到人脸，按画面估计", "no face detected, estimated from the picture")
        if target != 0, let a = society.agents[target] {
            a.look = look
            showToast(String(format: L("%@ 已生成像素形象（%@）", "%@ became a pixel character (%@)"), a.name(zh: GameModel.zh), how))
            if selectedID == target { selectedPortrait = portraits[portraitID] }
        } else {
            look.shoes = playerLook.shoes
            playerLook = look
            playerPortrait = portraits[portraitID]
            showToast(String(format: L("已生成你的像素角色（%@）", "Your pixel character is ready (%@)"), how))
        }
        scene?.clearTextureCache()
        scene?.faceCameraOnce()
    }

    /// GIF or video -> animated pixel character. No skeleton: the frames are
    /// pixelised together (one crop, one palette) and played back in the world.
    func applyMotion(_ frames: [Bitmap], target: Int) {
        guard frames.count > 1 else { return }
        showToast(L("AI 正在把动画逐帧像素化…", "AI is pixelising the animation frame by frame…"))
        let token = epoch
        DispatchQueue.global(qos: .userInitiated).async {
            let analyses = frames.map { PhotoAI.analyze($0) }
            // use the AI cut-outs only when the person was found in every frame
            let cut = analyses.allSatisfy { $0.segmented }
            let sprites = AssetImporter.spriteFrames(cut ? analyses.map { $0.bitmap } : frames, maxFrames: 12)
            let first = analyses[0]
            let still = AssetImporter.photoToCharacter(first.bitmap, face: first.face)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.photoJobStillValid(token, target) else { return }
                self.finishMotion(sprites, still: still, foundFace: first.face != nil, cut: cut, target: target)
            }
        }
    }

    private func finishMotion(_ sprites: [Bitmap], still: AssetImporter.PhotoResult, foundFace: Bool, cut: Bool, target: Int) {
        guard society != nil, !sprites.isEmpty else { showToast(L("无法读取动画", "Could not read the animation")); return }
        let stamp = "\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 0..<100000))"
        let animID = "anim_\(stamp)_n\(sprites.count)", portraitID = "portrait_" + stamp
        store(AssetImporter.sheet(sprites), id: animID)
        anims[animID] = sprites.map { $0.texture }
        // card picture: the AI portrait when a face was found, otherwise the first frame
        let portrait = foundFace ? still.portrait : sprites[0]
        store(portrait, id: portraitID)
        portraits[portraitID] = portrait.uiImage
        var look = foundFace ? still.look : Look()
        look.face = ""
        look.anim = animID
        look.portrait = portraitID
        let how = String(format: L("%d 帧%@", "%d frames%@"), sprites.count, cut ? L("，AI 抠出人像", ", person cut out by AI") : "")
        if target != 0, let a = society.agents[target] {
            a.look = look
            showToast(String(format: L("%@ 已变成动画像素角色（%@）", "%@ is now an animated pixel character (%@)"), a.name(zh: GameModel.zh), how))
            if selectedID == target { selectedPortrait = portraits[portraitID] }
        } else {
            playerLook = look
            playerPortrait = portraits[portraitID]
            showToast(String(format: L("已生成你的动画像素角色（%@）", "Your animated pixel character is ready (%@)"), how))
        }
        scene?.clearTextureCache()
        scene?.faceCameraOnce()
    }

    /// A short synthetic clip (a waving figure) for the simulator smoke test.
    static func syntheticClip() -> [Bitmap] {
        (0..<8).compactMap { i -> Bitmap? in
            let r = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 220))
            let bob = CGFloat(i % 4 < 2 ? 0 : 8), arm = CGFloat(i % 4) * 14
            let img = r.image { ctx in
                UIColor(red: 0.2, green: 0.75, blue: 0.4, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 220))
                UIColor(red: 0.95, green: 0.6, blue: 0.15, alpha: 1).setFill(); UIBezierPath(roundedRect: CGRect(x: 50, y: 95 + bob, width: 60, height: 80), cornerRadius: 14).fill()
                UIColor(red: 0.25, green: 0.25, blue: 0.6, alpha: 1).setFill()
                ctx.fill(CGRect(x: 54, y: 172 + bob, width: 20, height: 38 - bob)); ctx.fill(CGRect(x: 86, y: 172 + bob, width: 20, height: 38 - bob))
                UIColor(red: 0.98, green: 0.82, blue: 0.68, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: 44, y: 22 + bob, width: 72, height: 72)).fill()
                ctx.fill(CGRect(x: 110, y: 110 + bob - arm, width: 16, height: 44)); ctx.fill(CGRect(x: 34, y: 110 + bob, width: 16, height: 44))
                UIColor(red: 0.3, green: 0.15, blue: 0.4, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: 44, y: 16 + bob, width: 72, height: 36)).fill()
            }
            return Bitmap(image: img, maxSide: 220)
        }
    }

    /// Any picture -> placeable pixel object.
    func importAsset(_ image: UIImage) {
        guard let bmp = Bitmap(image: image, maxSide: 256) else { showToast(L("无法读取图片", "Could not read the picture")); return }
        let px = AssetImporter.pixelize(bmp, maxSide: 40, colors: 16, removeBackground: true)
        let id = "a\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 0..<100000))"
        store(px, id: id)
        assets[id] = px.texture
        placingAsset = id
        showToast(L("点击地面放置素材", "Tap the ground to place it"))
    }
}
