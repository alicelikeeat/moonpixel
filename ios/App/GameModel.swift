import SwiftUI
import SpriteKit
import MoonPixelCore

/// Owns the world, the society and everything the SwiftUI HUD shows.
@MainActor
final class GameModel: ObservableObject {
    static let zh: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    static let speeds: [Double] = [0, 1, 4, 16, 64]
    static let weapons = ["", "sword", "bow", "staff"]

    @Published var scene: GameScene?
    @Published var status = ""
    @Published var statsText = ""
    @Published var memoryText = ""
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
    @Published var photoTarget: Int? = nil       // nil = no picker; 0 = player; else villager id
    @Published var importingAsset = false
    @Published var placingAsset: String? = nil

    var world: OpenWorld!
    var society: Society!
    var playerLook: Look = { var l = Look(); l.hair = "#f0e8d0"; l.shirt = "#f4f0e0"; l.pants = "#5a5a78"; l.style = 3; return l }()
    var assets: [String: SKTexture] = [:]
    private var lastLogCount = 0
    private var cleanCooldown = 0.0
    private var memObserver: NSObjectProtocol?

    var saveDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("world", isDirectory: true)
    }
    var hasSave: Bool { FileManager.default.fileExists(atPath: saveDir.appendingPathComponent("index.json").path) }

    struct Index: Codable {
        var world: OpenWorld.Snapshot
        var society: Society.Snapshot
        var px: Double, py: Double
        var look: Look
    }

    // MARK: lifecycle
    func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard scene == nil, let i = args.firstIndex(of: "--autostart") else { return }
        let seed = (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 7
        start(seed: seed, overrideMB: 0, load: false)
        speedIndex = 2
        if args.contains("--select") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let sc = self.scene, let a = self.society.agent(near: sc.player, radius: 600) else { return }
                self.select(a.id)
            }
        }
        if args.contains("--map") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.toggleMap() }
        }
    }

    func start(seed: Int, overrideMB: Int, load: Bool) {
        let budget = MemoryBudget(overrideMB: overrideMB)
        var index: Index?
        if load, let data = try? Data(contentsOf: saveDir.appendingPathComponent("index.json")) {
            index = try? JSONDecoder().decode(Index.self, from: data)
        }
        if index == nil { try? FileManager.default.removeItem(at: saveDir) }
        let w = OpenWorld(seed: index?.world.seed ?? seed, budget: budget)
        w.open(directory: saveDir)
        let s = Society(world: w, seed: w.seed)
        s.zh = GameModel.zh
        var start = Vec2(8, 8)
        if let ix = index {
            w.restore(ix.world)
            s.restore(ix.society)
            start = Vec2(ix.px, ix.py)
            playerLook = ix.look
        } else {
            s.bootstrap(origin: TilePos(0, 0), villages: 4, per: 30)
            if let first = s.settlements[1] { start = w.findFree(near: first.center + TilePos(0, 4), maxR: 8).center }
        }
        world = w
        society = s
        loadAssets()
        let sc = GameScene(size: CGSize(width: 874, height: 402))
        sc.scaleMode = .resizeFill
        sc.model = self
        sc.player = start
        scene = sc
        lastLogCount = s.log.count
        if memObserver == nil {
            memObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cleanMemory(announce: true) }
            }
        }
        refreshHUD()
    }

    func save(announce: Bool) {
        guard let w = world, let s = society, let sc = scene else { return }
        w.saveAll()
        let ix = Index(world: w.snapshot(), society: s.snapshot(), px: sc.player.x, py: sc.player.y, look: playerLook)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ix) { try? data.write(to: saveDir.appendingPathComponent("index.json"), options: .atomic) }
        if announce { showToast(L("已保存", "Saved")) }
    }

    // MARK: HUD
    func showToast(_ text: String) { toast = text; toastID += 1 }

    /// Called a few times per second from the scene.
    func refreshHUD() {
        guard let w = world, let s = society else { return }
        let h = w.hour
        status = String(format: L("第 %d 年 %02d:%02d · %d 人", "Year %d %02d:%02d · %d people"), w.year + 1, Int(h), Int(h.truncatingRemainder(dividingBy: 1) * 60), s.agents.count)
        if s.log.count != lastLogCount, let last = s.log.last {
            lastLogCount = s.log.count
            showToast(last.text)
        }
        if showDetails {
            let st = s.stats
            let houses = s.settlements.values.reduce(0) { $0 + $1.count("house", done: true) }
            statsText = String(format: L("出生 %d · 死亡 %d · 伴侣 %d\n村落 %d · 房屋 %d · 建筑 %d", "Births %d · Deaths %d · Couples %d\nVillages %d · Houses %d · Built %d"),
                               st.births, st.deaths, st.pairs, s.livingSettlements, houses, st.buildings)
            let b = w.budget
            memoryText = String(format: L("内存：设备 %d MB · 预算 %d MB%@ · 已用 %d MB\n区块：缓存 %d/%d · 生成 %d · 回收 %d · 地图 %d",
                                          "Memory: device %d MB · budget %d MB%@ · used %d MB\nChunks: cached %d/%d · generated %d · evicted %d · mapped %d"),
                                b.physicalMB, b.budgetMB, b.overrideMB > 0 ? L("（手动）", " (manual)") : L("（自动）", " (auto)"), MemoryBudget.usedMB(),
                                w.cache.count, b.maxChunks, w.generated, w.evicted, w.surveyed)
            logLines = s.log.suffix(5).map { "· " + $0.text }
        }
        if selectedID != 0 {
            if let info = s.talk(selectedID, speak: false) {
                var i = info
                i.line = selected?.line ?? info.line
                selected = i
            } else { selectedID = 0; selected = nil; following = false }
        }
    }

    func tickHousekeeping(_ dt: Double) {
        cleanCooldown = max(0, cleanCooldown - dt)
        if autoClean && cleanCooldown <= 0 && world.budget.pressure() > 0.9 { cleanMemory(announce: true) }
    }

    func select(_ id: Int) {
        selectedID = id
        following = false
        selected = society.talk(id, speak: true)
    }

    func deselect() { selectedID = 0; selected = nil; following = false }
    func talk() { if selectedID != 0 { selected = society.talk(selectedID, speak: true) } }
    func feed() { if selectedID != 0 { society.giftFood(selectedID); talk() } }
    func cycleWeapon() { weaponIndex = (weaponIndex + 1) % GameModel.weapons.count }

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
        var ext = 24
        for k in w.regions.keys {
            ext = max(ext, abs(k.x * R + R / 2 - pc.x) + R / 2, abs(k.y * R + R / 2 - pc.y) + R / 2)
        }
        ext = min(ext, 160)
        let side = ext * 2 + 1
        var bmp = Bitmap(side, side, fill: RGBA(8, 10, 18))
        let cols = Content.shared.biomes.map { RGBA(hex: $0.color) }
        for y in 0..<side { for x in 0..<side {
            let v = w.known(pc.x - ext + x, pc.y - ext + y)
            if v != 0 { bmp.set(x, y, cols[Int(v) - 1]) }
        } }
        for s in society.settlements.values {
            let x = (s.center.x >> 5) - pc.x + ext, y = (s.center.y >> 5) - pc.y + ext
            bmp.rect(x - 1, y - 1, 3, 3, s.abandoned ? RGBA(90, 90, 90) : RGBA(255, 216, 77))
        }
        bmp.rect(ext - 1, ext - 1, 3, 3, RGBA(128, 230, 255))
        mapImage = bmp.uiImage
        mapCaption = String(format: L("已探明 %d 个区块 · 地图随村民扩张自动生长", "%d chunks mapped · the map grows as villagers spread"), w.surveyed)
    }

    // MARK: photos and assets
    var assetsDir: URL { saveDir.appendingPathComponent("assets", isDirectory: true) }

    func loadAssets() {
        assets.removeAll()
        for f in (try? FileManager.default.contentsOfDirectory(atPath: assetsDir.path)) ?? [] where f.hasSuffix(".png") {
            guard let img = UIImage(contentsOfFile: assetsDir.appendingPathComponent(f).path), let bmp = Bitmap(image: img, maxSide: 128) else { continue }
            let id = String(f.dropLast(4))
            if id.hasPrefix("face_") { PixelArt.faces[id] = bmp } else { assets[id] = bmp.texture }
        }
    }

    private func store(_ bmp: Bitmap, id: String) {
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        if let data = bmp.uiImage?.pngData() { try? data.write(to: assetsDir.appendingPathComponent(id + ".png")) }
    }

    /// Photo -> character look (target 0 = the player, otherwise a villager).
    func applyPhoto(_ image: UIImage, target: Int) {
        guard let bmp = Bitmap(image: image, maxSide: 512) else { showToast(L("无法读取图片", "Could not read the picture")); return }
        let out = AssetImporter.photoToLook(bmp)
        let id = "face_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 0..<100000))"
        PixelArt.faces[id] = out.face
        store(out.face, id: id)
        var look = out.look
        look.face = id
        if target != 0, let a = society.agents[target] {
            look.style = a.look.style
            a.look = look
            showToast(L("村民外观已更新", "Villager updated from photo"))
        } else {
            look.style = playerLook.style
            look.shoes = playerLook.shoes
            playerLook = look
            showToast(L("已用照片生成角色", "Character created from photo"))
        }
        scene?.clearTextureCache()
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
