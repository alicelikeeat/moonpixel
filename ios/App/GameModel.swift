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
    static let weapons = ["", "sword", "bow", "staff"]
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

    var world: OpenWorld!
    var society: Society!
    var worldID = ""
    var worldName = ""
    var playerLook = GameModel.defaultLook
    var assets: [String: SKTexture] = [:]
    var portraits: [String: UIImage] = [:]
    private var lastLogCount = 0
    private var cleanCooldown = 0.0
    private var memObserver: NSObjectProtocol?

    static var defaultLook: Look { var l = Look(); l.hair = "#f0e8d0"; l.shirt = "#f4f0e0"; l.pants = "#5a5a78"; l.style = 3; return l }

    struct Index: Codable {
        var world: OpenWorld.Snapshot
        var society: Society.Snapshot
        var px: Double, py: Double
        var look: Look
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

    func createWorld(name: String, seed: Int, overrideMB: Int) {
        let id = "w\(Int(Date().timeIntervalSince1970))-\(Int.random(in: 100..<1000))"
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        start(id: id, name: clean.isEmpty ? L("世界", "World") + " \(worlds.count + 1)" : clean, seed: seed, overrideMB: overrideMB, load: false)
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

    func start(id: String, name: String, seed: Int, overrideMB: Int, load: Bool) {
        worldID = id
        worldName = name
        let budget = MemoryBudget(overrideMB: overrideMB)
        var index: Index?
        if load, let data = try? Data(contentsOf: saveDir.appendingPathComponent("index.json")) {
            index = try? JSONDecoder().decode(Index.self, from: data)
            if index == nil { showToast(L("存档无法读取，已重新生成世界", "Save could not be read; the world was regenerated")) }
        }
        if !load { try? FileManager.default.removeItem(at: saveDir) }
        let w = OpenWorld(seed: index?.world.seed ?? seed, budget: budget)
        w.diskLimitBytes = GameModel.mapLimitBytes
        w.open(directory: saveDir)
        let s = Society(world: w, seed: w.seed)
        s.zh = GameModel.zh
        var start = Vec2(8, 8)
        playerLook = GameModel.defaultLook
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
        playerPortrait = playerLook.portrait.flatMap { portraits[$0] }
        deselect()
        showMap = false
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
        if !load { save(announce: false) }
    }

    func save(announce: Bool) {
        guard let w = world, let s = society, let sc = scene else { return }
        w.saveAll()
        let ix = Index(world: w.snapshot(), society: s.snapshot(), px: sc.player.x, py: sc.player.y, look: playerLook)
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ix) { try? data.write(to: saveDir.appendingPathComponent("index.json"), options: .atomic) }
        let meta = WorldMeta(id: worldID, name: worldName, seed: w.seed, savedAt: Date(), year: w.year + 1, population: s.agents.count,
                             diskBytes: mapBytes(), tech: s.techCount > 0 ? s.techName(s.techCount - 1) : "")
        if let data = try? JSONEncoder().encode(meta) { try? data.write(to: saveDir.appendingPathComponent("meta.json"), options: .atomic) }
        if announce { showToast(L("已保存", "Saved")) }
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
    func mapBytes() -> Int {
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
        if s.log.count != lastLogCount, let last = s.log.last {
            lastLogCount = s.log.count
            showToast(last.text)
        }
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
            mapSizeFraction = min(1, Double(bytes) / Double(GameModel.mapLimitBytes))
            mapSizeText = String(format: L("地图存档 %@ / 5 GB · 内存中 %@ · 已探明 %d 区块%@", "Map on disk %@ / 5 GB · in memory %@ · %d chunks mapped%@"),
                                 GameModel.sizeText(bytes), GameModel.sizeText(w.memoryBytes), w.surveyed,
                                 w.prunedFiles > 0 ? String(format: L(" · 已回收 %d 个旧区块", " · %d old chunks pruned"), w.prunedFiles) : "")
            let b = w.budget
            memoryText = String(format: L("内存：设备 %d MB · 预算 %d MB%@ · 已用 %d MB · 区块缓存 %d/%d",
                                          "Memory: device %d MB · budget %d MB%@ · used %d MB · chunk cache %d/%d"),
                                b.physicalMB, b.budgetMB, b.overrideMB > 0 ? L("（手动）", " (manual)") : L("（自动）", " (auto)"), MemoryBudget.usedMB(), w.cache.count, b.maxChunks)
            logLines = s.log.suffix(4).map { "· " + $0.text }
        }
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
        var ext = 10
        for (k, r) in w.regions {
            for i in 0..<r.count where r[i] != 0 {
                ext = max(ext, abs(k.x * R + i % R - pc.x) + 2, abs(k.y * R + i / R - pc.y) + 2)
            }
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
        mapCaption = String(format: L("已探明 %d 个区块 · 存档 %@ / 5 GB", "%d chunks mapped · %@ of 5 GB on disk"), w.surveyed, GameModel.sizeText(mapBytes()))
    }

    // MARK: photos and assets
    func loadAssets() {
        assets.removeAll()
        portraits.removeAll()
        for f in (try? FileManager.default.contentsOfDirectory(atPath: assetsDir.path)) ?? [] where f.hasSuffix(".png") {
            guard let img = UIImage(contentsOfFile: assetsDir.appendingPathComponent(f).path), let bmp = Bitmap(image: img, maxSide: 128) else { continue }
            let id = String(f.dropLast(4))
            if id.hasPrefix("face_") { PixelArt.faces[id] = bmp }
            else if id.hasPrefix("portrait_") { portraits[id] = bmp.uiImage }
            else { assets[id] = bmp.texture }
        }
    }

    private func store(_ bmp: Bitmap, id: String) {
        try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        if let data = bmp.uiImage?.pngData() { try? data.write(to: assetsDir.appendingPathComponent(id + ".png")) }
    }

    /// Photo -> pixel character (target 0 = the player, otherwise a villager).
    /// Apple's on-device Vision models find the face and cut the person out; the
    /// pixel face, pixel portrait, colours and hairstyle are generated from that.
    func applyPhoto(_ image: UIImage, target: Int) {
        guard let bmp = Bitmap(image: image, maxSide: 512) else { showToast(L("无法读取图片", "Could not read the picture")); return }
        showToast(L("AI 正在生成像素角色…", "AI is generating the pixel character…"))
        DispatchQueue.global(qos: .userInitiated).async {
            let analysis = PhotoAI.analyze(bmp)
            let result = AssetImporter.photoToCharacter(analysis.bitmap, face: analysis.face)
            DispatchQueue.main.async { [weak self] in self?.finishPhoto(result, analysis: analysis, target: target) }
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
