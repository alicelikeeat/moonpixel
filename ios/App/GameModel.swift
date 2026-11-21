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

enum ViewMode: String { case third, first }

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
    /// A nation of the known world shown in full (CivPanel.swift).
    @Published var civDetail: Int?
    /// The regional nation the player governs, if any (its rations, building, orders and forces are theirs).
    @Published var civCommand: Int?
    /// A tower shown floor by floor (TowerPanel.swift).
    @Published var towerDetail: Int?
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
    /// The battle of the twin ports, played on its own fixed seeds (WarDemoView.swift).
    @Published var showWarDemo = false
    @Published var showDiagnostics = false
    /// Frame-time diagnostics shown over the game (More → Performance).
    @Published var showPerf = false
    @Published var perfLines: [String] = []
    /// `--perf-log N`: write a diagnostics reading to Documents/perf.json every N seconds (simulator runs in CI).
    var perfLogEvery = 0.0
    /// `--plain-render`: draw without the v1.6 roofs, gate crests and soldier view (same-machine A/B measurements)
    var plainRender = false
    /// The world is drawn as solids by RealityKit instead of as sprites; the game underneath is the same.
    @Published var render3D = UserDefaults.standard.bool(forKey: "render3D") {
        didSet { if GameModel.keepViewSettings { UserDefaults.standard.set(render3D, forKey: "render3D") } }
    }
    /// Views chosen in the game are kept; a view asked for by a launch argument (tests, demos) is for that run only.
    static var keepViewSettings = true
    /// In 3D: from behind the traveller (third person) or through their eyes (first person).
    @Published var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .third {
        didSet { if GameModel.keepViewSettings { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }; inputReset += 1 }
    }
    /// How fast a drag turns the view (0.4 ... 2.5), and whether up and down are swapped.
    @Published var lookSensitivity: Double = (UserDefaults.standard.object(forKey: "lookSensitivity") as? Double) ?? 1 {
        didSet { UserDefaults.standard.set(lookSensitivity, forKey: "lookSensitivity") }
    }
    @Published var invertLook = UserDefaults.standard.bool(forKey: "invertLook") {
        didSet { UserDefaults.standard.set(invertLook, forKey: "invertLook") }
    }
    /// How see-through the floors of storeys are drawn (0.15 ... 1; 1 is solid). Drawing only: they hold the same either way.
    @Published var floorOpacity: Double = (UserDefaults.standard.object(forKey: "floorOpacity") as? Double) ?? 0.45 {
        didSet { UserDefaults.standard.set(floorOpacity, forKey: "floorOpacity") }
    }
    @Published var showBackpack = false { didSet { if showBackpack { inputReset += 1 } } }
    /// The elevator whose panel is open (inside it, or at one of its landings).
    @Published var liftPanel: Int?
    /// The elevator the traveller is in or beside, if any (the button to open its panel shows then).
    @Published var nearLift: Int?
    @Published var inLift = false              // riding a lift
    @Published var nearUfo = false             // a saucer resting on its pad beside the traveller
    @Published var onUfo = false               // aboard a saucer
    @Published var ufoLanded = false           // ... and it rests on its pad
    @Published var chuting = false             // falling under a parachute
    @Published var atLiftDoor = false          // standing at a lift's doors (it is called to you)
    // transport (v2.7): the vehicle the traveller is in, its controls, the travel and network panels
    /// What the driving or passenger display shows (nil when not in a vehicle).
    @Published var drive: DriveState?
    /// The controls the traveller holds (sent to the vehicle every frame while driving).
    @Published var driveInput = Controls()
    /// From the driver's seat (first person) or from behind (third person).
    @Published var cockpit = true
    @Published var showTravel = false { didSet { if showTravel { inputReset += 1; refreshTravel() } } }
    @Published var showTransport = false { didSet { if showTransport { inputReset += 1; refreshTransport() } } }
    /// Vehicles close enough to get into, and stops to travel to (for the travel panel).
    @Published var vehiclesHere: [VehicleRow] = []
    @Published var destinations: [StopRow] = []
    /// Other cities' airports, nearest first: where a charter flight can take you.
    @Published var flights: [StopRow] = []
    /// The air network: the place the traveller is at, and the others (planes and saucers).
    @Published var airHere: AirHub?
    @Published var airHubs: [AirHub] = []
    /// The teleport centre.
    @Published var showTeleport = false { didSet { if showTeleport { inputReset += 1 } } }
    @Published var trip: TripPlan?
    @Published var tripTo: Int?
    @Published var transportLines: [String] = []
    @Published var wayKindPick = WayKind.street
    @Published var wayStart: TilePos?
    @Published var wayPreview: WayPlan?
    /// A vehicle or stop the traveller is near (shows the travel button).
    @Published var nearTransport = false
    /// What the transport demo built (for UI tests).
    var demoNotes = ""
    /// The fastest the traveller's vehicle has gone since they got in (km/h).
    var topKmh = 0.0
    /// Pixel art as made, or the anime look; kept between sessions.
    @Published var artStyle: ArtStyle = ArtStyle(rawValue: UserDefaults.standard.string(forKey: "artStyle") ?? "") ?? .pixel {
        didSet {
            UserDefaults.standard.set(artStyle.rawValue, forKey: "artStyle")
            Bitmap.animeStyle = artStyle == .anime
            styleEpoch += 1
            scene?.restyle()
        }
    }
    /// A count for the HUD: 12,345 → "1.2万" in Chinese, "12.3k" in English (exact below ten thousand).
    static func count(_ n: Int) -> String {
        if n < 10_000 { return "\(n)" }
        if zh { return n >= 100_000_000 ? String(format: "%.2f亿", Double(n) / 1e8) : String(format: "%.1f万", Double(n) / 1e4) }
        return n >= 1_000_000 ? String(format: "%.2fM", Double(n) / 1e6) : String(format: "%.1fk", Double(n) / 1e3)
    }

    /// How finely people, animals, vehicles and machines are modelled in 3D: 1 standard, 2 high (four times the
    /// faces on every curve, the default), 3 very high (nine times); kept between sessions.
    @Published var modelDetail: Int = UserDefaults.standard.object(forKey: "modelDetail") as? Int ?? 2 {
        didSet {
            UserDefaults.standard.set(modelDetail, forKey: "modelDetail")
            Figure3D.detail = modelDetail
        }
    }
    /// How people are drawn in the anime look (soft moe figures, or hero proportions); kept between sessions.
    @Published var figureStyle: AnimeArt.Figure = AnimeArt.Figure(rawValue: UserDefaults.standard.string(forKey: "figureStyle") ?? "") ?? .moe {
        didSet {
            UserDefaults.standard.set(figureStyle.rawValue, forKey: "figureStyle")
            AnimeArt.figure = figureStyle
            styleEpoch += 1
            scene?.restyle()
        }
    }
    /// Bumped when the art style changes (the 3D view rebuilds its textures).
    var styleEpoch = 0
    /// "☀ 14:05" / "☾ 23:40": the time of day, shown on the HUD.
    @Published var clockLine = ""
    /// "Storey 3 · 6.0 m" and, in a car, where it is going.
    @Published var heightLine = ""
    /// Yaw and pitch of the 3D view, for assistive technology and UI tests.
    @Published var cameraLine = ""
    /// Bumped whenever held touches must be let go (a panel opens, the view changes): nothing keeps walking or striking.
    var inputReset = 0
    /// The jump button was pressed and the next movement step has not used it yet.
    var jumpQueued = false
    /// The 3D view while it is on screen (effects are sent to it).
    weak var solid: SolidRenderer?
    /// The nanite swarm's view, and how many points a swarm has on this device (by its memory; --swarm-count overrides).
    weak var swarm: SwarmView?
    /// `--swarm-count` asks for one size exactly (pictures, tests): no adapting.
    var swarmFixed = false
    var swarmCount = SwarmShapes.size(forMemoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
    /// What the last swarm cost (shown in the performance panel).
    var swarmReport = ""
    /// A battle of command mode, while one is being fought (the world waits meanwhile).
    @Published var command: SkirmishSession?
    /// The city of metro mode, while it is open (the world waits meanwhile).
    @Published var metro: MetroSession?
    var commandCount = 0
    private var perfLogAcc = 0.0
    /// The tile picked on the map (exact to the tile), and what is there.
    @Published var mapPick: TilePos?
    @Published var mapPickText = ""
    @Published var mapZoom = 1.0
    /// The map shows the nations (国土) rather than the land (地形).
    @Published var mapPolitical = false
    /// Which world the map shows: the surface, the underground or the sea floor.
    @Published var mapLayer = WorldMap.Layer.surface
    func setMapLayer(_ l: WorldMap.Layer) {
        guard l != mapLayer else { return }
        mapLayer = l
        worldMap.layer = l
        mapPick = nil; mapPickText = ""
        rebuildMap()
    }
    /// The level the maps below show (B1 ... B8).
    @Published var mapLevel = 1
    func setMapLevel(_ l: Int) {
        guard l != mapLevel else { return }
        mapLevel = l
        worldMap.level = l
        mapPick = nil; mapPickText = ""
        rebuildMap()
    }
    func setMapPolitical(_ on: Bool) {
        guard on != mapPolitical else { return }
        mapPolitical = on
        worldMap.political = on
        rebuildMap()
    }
    /// Zoom the map: 1x, 2x and 4x enlarge the whole map; 8x is the detailed map of the land round you.
    func setMapZoom(_ z: Double) {
        let wasDetail = mapZoom >= 8
        mapZoom = z
        if (z >= 8) != wasDetail { rebuildMap() }
    }
    /// Places on the map: towns, capitals, cities, districts, airports, mazes, armies, you.
    @Published var mapMarkers: [MapMarker] = []
    let worldMap = WorldMap()
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
    // saving (SaveCoordinator.swift)
    var saveRunning = false
    var saveAgain = false
    var saveWaiters: [(Bool, String?) -> Void] = []
    var savePurgeNext = false
    var saveAnnounceNext = false
    var exitRequested = false
    var failSaves = 0
    /// `--fail-exit-saves N`: the next N saves started by leaving the world fail (UI tests); other saves are untouched.
    var failExitSaves = 0
    var failNextSave = false
    var lawCommitting = false
    @Published var saveError: String?
    @Published var exitBlocked: String?
    @Published var lastSavedGen = 0
    var lastSavedAt: Date?
    var storeDiskBytes = 0
    let perf = PerfStats()
    // v1.3: building, crafting, cities, chronicle, war watching
    @Published var showBuild = false
    @Published var showCraft = false
    @Published var showCities = false
    @Published var showChronicle = false
    @Published var showWar = false
    @Published var showMore = false
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

    /// Save format: 3 = v1.3 (cities, campaigns, building); 4 = v2.6 (the traveller's body and backpack,
    /// outside elevators, standing towers, the exact list of storeys). Absent in older saves. A save of a
    /// newer format is refused, never read halfway (an older game would drop what it does not know).
    static let saveFormat = 5
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
            guard fm.fileExists(atPath: d.appendingPathComponent("HEAD").path) || fm.fileExists(atPath: d.appendingPathComponent("index.json").path) else { continue }
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
        if let i = args.firstIndex(of: "--fail-saves"), i + 1 < args.count { failSaves = Int(args[i + 1]) ?? 0 }
        if let i = args.firstIndex(of: "--fail-metro-saves"), i + 1 < args.count { MetroSession.failSaves = Int(args[i + 1]) ?? 0 }
        if let i = args.firstIndex(of: "--fail-exit-saves"), i + 1 < args.count { failExitSaves = Int(args[i + 1]) ?? 0 }
        if let i = args.firstIndex(of: "--perf-log"), i + 1 < args.count { perfLogEvery = Double(args[i + 1]) ?? 0 }
        if args.contains("--perf") { showPerf = true }
        if args.contains("--plain-render") { plainRender = true }
        let launchView = args.contains("--3d") || args.contains("--2d") || args.contains("--first-person")
        if launchView { GameModel.keepViewSettings = false }
        // the saved art style applies before anything is drawn (--anime / --pixel choose it for this run)
        // (--anime / --pixel choose it for this run only, without changing the saved setting; UI tests start in pixel art)
        Bitmap.animeStyle = args.contains("--anime") || (!(args.contains("--pixel") || args.contains("--autostart")) && artStyle == .anime)
        AnimeArt.figure = args.contains("--hero") ? .hero : figureStyle
        Figure3D.detail = modelDetail
        if args.contains("--3d") { render3D = true } else if args.contains("--2d") || args.contains("--autostart") { render3D = false }
        if args.contains("--autostart") && !args.contains("--first-person") { viewMode = .third }
        if let i = args.firstIndex(of: "--swarm-count"), i + 1 < args.count, let n = Int(args[i + 1]) { swarmCount = max(1024, min(SwarmShapes.sizes[3], n)); swarmFixed = true }
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
        if args.contains("--command") || args.contains("--command-auto") {
            // straight into a battle of command mode; with -auto the computer plays both sides, faster, for pictures
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.startCommand()
                if args.contains("--command-auto") { self.command?.sim.setComputer(0, true); self.command?.scene.pace = 3 }
            }
        }
        if args.contains("--metro") || args.contains("--metro-auto") {
            // straight into metro mode; with -auto a ready-made town grows at full speed (for pictures)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.startMetro(fresh: args.contains("--metro-auto"))
                if args.contains("--metro-auto") { self.metro?.city.layOutDemo(); self.metro?.speed = 3 }
                if let i = args.firstIndex(of: "--metro-view"), i + 1 < args.count { self.metro?.overlay = args[i + 1] }
            }
        }
        if args.contains("--demo-swarm") {
            // the traveller sends the nanite swarm out again and again, so a picture at any moment shows it
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.cheat("powers"); self?.cheat("god") }
            for i in 0..<12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8 + Double(i) * 10) { [weak self] in
                    guard let self = self, let sc = self.scene else { return }
                    self.activePower = "nano"
                    self.society.realm.player.cooldowns = [:]
                    sc.attack(toward: sc.player + Vec2(Double(i % 2 == 0 ? 60 : -60), -24))
                }
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
        if let i = args.firstIndex(of: "--stress-battle"), i + 1 < args.count, let n = Int(args[i + 1]) {
            // a fixed battle of n real soldiers, watched from close by, with the draw tier pinned to n (for measurements)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self = self, let s = self.society, let sc = self.scene, let ids = s.stageFieldBattle(perSide: n / 2),
                      let la = s.realm.legion(ids.0), let lb = s.realm.legion(ids.1) else { return }
                sc.renderBudget.pin(soldiers: n); sc.budgetPinned = true
                self.watch = .point((la.pos + lb.pos) * 0.5)
                sc.zoom = 1.7
                self.speedIndex = 1
                self.perf.reset()
            }
        }
        if args.contains("--tour-cities") {
            // the camera visits each nation's capital in turn (for screenshots of the running game)
            // first let the towns grow for about a year at the highest speed
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.speedIndex = 4 }
            for k in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 48 + Double(k) * 8) { [weak self] in
                    guard let self = self, let s = self.society else { return }
                    self.speedIndex = 1
                    let ids = s.realm.nations.map { $0.id }.sorted()
                    guard k < ids.count, let c = s.capital(of: ids[k]) ?? s.towns(of: ids[k]).first else { return }
                    self.watch = .point(c.center.center)
                    self.scene?.zoom = 1.2
                }
            }
        }
        if args.contains("--demo-war") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self else { return }
                self.startDemoWar()
                self.speedIndex = 2          // 4x: slow enough to see the march, the walls, the breach and the storming
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
        if args.contains("--first-person") { viewMode = .first; render3D = true }
        if args.contains("--lift-demo") {
            // a six-storey house, an outside elevator against it (paid from a filled pack), the traveller in the car
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let s = self.society, let sc = self.scene else { return }
                let o0 = self.world.findSite(from: sc.player.tile, minR: 6, maxR: 30, salt: 91, avoid: [], avoidDist: 0)
                let o = o0.isNone ? sc.player.tile + TilePos(6, 0) : o0
                s.raiseHouse(at: o, storeys: 6, w: 7, d: 7)
                let sx = o.x + 8, sy = o.y + 2
                for yy in sy..<(sy + 2) { for xx in sx..<(sx + 2) { for l in 1...3 { self.world.setTile(l, xx, yy, 0) } } }
                let plan = s.planLift(x: sx, y: sy, levels: Array(0..<6), landingSide: TilePos(-1, 0))
                for (k, v) in plan.cost { s.carry(k, v) }
                guard let id = s.buildLift(plan, x: sx, y: sy, town: s.settlements.values.filter { !$0.abandoned }.min { $0.id < $1.id }?.id ?? 0, tower: nil, planID: 900_001),
                      let e = s.lift(id) else { self.showToast("lift demo: " + plan.reason); return }
                self.world.setTile(2, sx + 3, sy, Content.shared.tid("machine"))      // its power: a machine beside the shaft
                var b = Body(at: Vec2(e.minX + 16, e.minY + 16), z: e.z, depth: 0); b.platform = id; b.state = .riding
                s.realm.player.body = b; s.realm.player.depth = 0
                sc.player = b.pos
                e.call(4, at: self.world.time)
                self.refreshHUD()
            }
        }
        if args.contains("--transport-demo") {
            // a street, a car, a bus line, a high-speed line, a runway and (by water) a ferry, near the traveller
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self = self, let s = self.society, let sc = self.scene else { return }
                let d = s.transportDemo(near: sc.player.tile)
                self.demoNotes = "demo near \(sc.player.tile.x),\(sc.player.tile.y): car \(d.car.map(String.init) ?? "-") bus \(d.bus.map(String.init) ?? "-") train \(d.train.map(String.init) ?? "-") plane \(d.plane.map(String.init) ?? "-") " + d.notes.joined(separator: "; ")
                if let id = d.car, let v = s.net.vehicle(id) {
                    var b = Body(at: v.world(0, 1.2), z: 0, depth: 0); b.state = .standing
                    s.realm.player.body = b; s.realm.player.depth = 0
                    sc.player = b.pos
                }
                if !d.notes.isEmpty { self.showToast(d.notes.joined(separator: "; ")) }
                if args.contains("--drive-plane"), let id = d.plane, let v = s.net.vehicle(id) {
                    s.realm.player.body = Body(at: v.pos, z: 0, depth: 0); sc.player = v.pos
                    _ = s.board(id, drive: true)
                }
                self.refreshDrive()
            }
        }
        if args.contains("--storey-demo") {
            // a four-storey house beside the player, and the player on its second storey (for pictures)
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
                guard let self = self, let s = self.society, let sc = self.scene else { return }
                let o = self.world.findSite(from: sc.player.tile, minR: 4, maxR: 20, salt: 77, avoid: [], avoidDist: 0)
                let stairs = s.raiseHouse(at: o.isNone ? sc.player.tile + TilePos(4, 0) : o, storeys: 4)
                if let first = stairs.first, let r = s.useStairs(at: first.center), let second = stairs.dropFirst().first, let r2 = s.useStairs(at: second.center) {
                    _ = r; self.switchLayer(to: r2.pos)
                }
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
        if !load { try? FileManager.default.removeItem(at: saveDir) }
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        let st = WorldStore(directory: saveDir)
        if load && st.hasLegacyLayout {
            // a save from before 1.6: its files are copied into generation 1 and left exactly as they were
            do { try st.importLegacy(); migrated = true }
            catch {
                showToast(L("旧存档迁移失败，原文件没有改动，世界未打开", "The older save could not be migrated; its files were not changed and the world was not opened"))
                worldID = ""; refreshWorlds(); return
            }
        }
        if load {
            Diagnostics.shared.phase("open:index")
            guard let data = st.readIndex() else {
                showToast(L("找不到完整的存档，世界未打开，文件没有改动", "No complete save was found; the world was not opened and nothing was changed"))
                worldID = ""; refreshWorlds(); return
            }
            Diagnostics.shared.phase("open:decode")
            index = try? JSONDecoder().decode(Index.self, from: data)
            if let ix = index, (ix.format ?? 2) > GameModel.saveFormat {
                showToast(L("这个存档来自更新的版本，请更新游戏后再打开", "This save comes from a newer version; update the game to open it"))
                worldID = ""; refreshWorlds(); return
            }
            if let ix = index, (ix.format ?? 2) < GameModel.saveFormat {
                // the save as it was is kept whole (its generation and everything it points to) before it is changed
                st.pinBackup("v\(ix.format ?? 2)")
                migrated = true
            }
            if index == nil {
                // never lose a save we could not read: its generation stays on disk and a copy is put beside it
                corrupt = true
                try? data.write(to: saveDir.appendingPathComponent("index.corrupt-\(Int(Date().timeIntervalSince1970)).json"))
            }
            if let r = st.recoveredFrom { showToast(String(format: L("存档第 %d 次不完整，已回到最近一次完整的存档（第 %d 次）", "Save #%d was incomplete; the last complete save (#%d) was opened"), r, st.headGen)) }
        }
        let w = OpenWorld(seed: index?.world.seed ?? seed, budget: budget)
        loadSettings()
        w.diskLimitBytes = limitBytes
        recipe = index?.recipe ?? (load ? nil : newRecipe)
        if let r = recipe { w.gen.tempBias = r.tempBias; w.gen.moistBias = r.moistBias; w.gen.elevBias = r.elevBias; w.gen.oceans = r.oceans ?? false }
        w.open(store: st)
        storeDiskBytes = st.diskBytes()
        lastSavedGen = st.headGen
        let s = Society(world: w, seed: w.seed)
        s.zh = GameModel.zh
        if let r = recipe { s.minPopulation = r.minPopulation }
        var start = Vec2(8, 8)
        playerLook = GameModel.defaultLook
        Diagnostics.shared.phase("open:restore")
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
        Diagnostics.shared.phase("open:scene")
        let sc = GameScene(size: CGSize(width: 874, height: 402))
        sc.scaleMode = .resizeFill
        sc.model = self
        sc.player = start
        scene = sc
        lastLogCount = s.log.count
        lastSeenEvent = s.lastEventID
        notices = []; watch = .none; pendingPlan = nil; buildMode = ""; lawSavePending = false; exitBlocked = nil; saveError = nil
        if memObserver == nil {
            memObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cleanMemory(announce: true) }
            }
        }
        refreshHUD()
        Diagnostics.shared.phase("play")
        if !load { save(announce: false) }
        if migrated { showToast(L("旧存档已迁移，原文件保留在世界目录中未改动", "This save was migrated; its original files are kept unchanged in the world folder")) }
        if corrupt { showToast(L("存档已损坏，原文件已另存为 index.corrupt，未被覆盖；世界已重新生成", "The save was damaged. It was kept as index.corrupt and not overwritten; the world was regenerated")) }
        // a world law that was interrupted (app killed, power lost) is finished now
        if load, index != nil {
            switch LawJournal.recovery(saveDir, store: st) {
            case .replay(let plan): recoverLaw(plan)                  // the law never reached a save: carry out the same plan again
            case .alreadyCommitted:                                     // it was saved; only its journal was left behind
                LawJournal.clear(saveDir)
                GameModel.saveQueue.async { _ = try? st.collectGarbage(purge: true) }
            case .none: break
            }
        }
    }

    // MARK: HUD
    func showToast(_ text: String) { toast = text; toastID += 1; ownToastUntil = Date().addingTimeInterval(4) }
    /// World news (a house finished, a couple courting) waits while the answer to the player's own action is on screen.
    func showNews(_ text: String) { if Date() >= ownToastUntil { toast = text; toastID += 1 } }
    private var ownToastUntil = Date.distantPast

    /// Bytes this world occupies on disk (chunks + index + assets).
    func mapBytes() -> Int { totalBytes() }

    /// Map and index in the current view, kept up to date as chunks change (no walking the disk).
    /// The real size on disk, previous generation included, is measured after each save in the background.
    func chunkAndIndexBytes() -> Int {
        guard let w = world else { return 0 }
        return w.diskBytes + (w.store?.head?.index?.s ?? 0) + (w.store?.head?.meta?.s ?? 0)
    }

    static func sizeText(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: mb >= 10 ? "%.0f MB" : "%.1f MB", mb)
    }

    /// Called a few times per second from the scene.
    func refreshHUD() {
        Diagnostics.shared.sample()
        guard let w = world, let s = society else { return }
        refreshHeight()
        if s.playerVehicle == nil { refreshDrive() }
        let phaseIcon: String
        switch w.dayPhase { case .dawn: phaseIcon = "🌅"; case .day: phaseIcon = "☀︎"; case .dusk: phaseIcon = "🌇"; case .night: phaseIcon = "☾" }
        // in ten-minute steps: a HUD that changed every game minute would redraw all the time at 64x
        let mins = Int(w.hour * 60) / 10 * 10
        let cl = phaseIcon + " " + String(format: "%02d:%02d", mins / 60, mins % 60)
        if clockLine != cl { clockLine = cl }
        cameraLine = render3D ? (solid?.cameraState ?? "") : "2d"
        if showPerf, let sc = scene { perfLines = sc.perfReport().lines + (render3D ? [solid?.report ?? "3D"] : []) + (swarmReport.isEmpty ? [] : [swarmReport]) }
        let h = w.hour
        // the people about you (the villagers of the towns drawn round you) and the whole known world (every
        // nation's cities, the districts, the metro city): two numbers, each named, so they are never confused
        status = String(format: L("第 %d 年 %02d:%02d · 附近 %@ 人 · 世界 %@ 人", "Year %d %02d:%02d · %@ people nearby · %@ in the world"), w.year + 1, Int(h), Int(h.truncatingRemainder(dividingBy: 1) * 60),
                        GameModel.count(s.nearbyPopulation(around: scene?.player.tile ?? TilePos(0, 0), depth: depth)), GameModel.count(s.knownPopulation))
        if depth == SkyTune.depth { status += L(" · 天空城", " · sky city") }
        else if depth >= OpenWorld.storeyBase { status += String(format: L(" · 第 %d 层", " · storey %d"), depth - OpenWorld.storeyBase) }
        else if depth == 1 { status += L(" · 地下", " · underground") }
        else if MP.isBelow(depth) { status += String(format: L(" · 地下第 %d 层", " · level B%d"), depth) }
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
        if perfLogEvery > 0, let sc = scene {
            perfLogAcc += dt
            if perfLogAcc >= perfLogEvery {
                perfLogAcc = 0
                let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .prettyPrinted]
                if let d = try? e.encode(sc.perfReport()), let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? d.write(to: docs.appendingPathComponent("perf.json"), options: .atomic)
                }
            }
        }
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
        let dropped = w.purge(keep: Set(sc.chunkNodes.keys).union(solid?.chunkKeys ?? []))
        let tex = sc.clearTextureCache()
        solid?.trim()
        swarm?.stop()
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
        Diagnostics.shared.phase("map"); defer { Diagnostics.shared.phase("play") }
        let pc = TilePos(Int((sc.player.x / 512).rounded(.down)), Int((sc.player.y / 512).rounded(.down)))
        // as far as anything is known: explored land and the cities of the nations of the known world
        var ext = 10
        let R = OpenWorld.region
        for (k, r) in w.regions { for i in 0..<r.count where r[i] != 0 { ext = max(ext, abs(k.x * R + i % R - pc.x) + 2, abs(k.y * R + i / R - pc.y) + 2) } }
        let civ = society.civ, rcs = civ.cfg.regionTiles / 32
        for city in civ.cities.values where city.detail == nil { ext = max(ext, abs(city.rx * rcs + rcs / 2 - pc.x) + rcs, abs(city.ry * rcs + rcs / 2 - pc.y) + rcs) }
        // 8x: the detailed map, the land round you at three pixels a tile, every building named
        let detail = mapZoom >= 8
        let (bmp, marks) = detail ? worldMap.render(society, centre: sc.player.tile, reach: 6, ppc: 96, zh: GameModel.zh)
                                  : worldMap.render(society, centre: sc.player.tile, reach: min(ext, 80), zh: GameModel.zh)
        mapImage = bmp.uiImage
        mapMarkers = marks
        mapCaption = String(format: L("已探明 %d 个区块 · 每个像素 %.0f 格 · 存档 %@ / %@", "%d chunks mapped · %.0f tiles a pixel · %@ of %@ on disk"), w.surveyed, worldMap.tilesPerPixel, GameModel.sizeText(mapBytes()), limitText)
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
