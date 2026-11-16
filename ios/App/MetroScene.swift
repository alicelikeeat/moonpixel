import SpriteKit
import SwiftUI
import UIKit
import MoonPixelCore

// Metro mode on screen. The city is MoonPixelCore's `Metro`; this file draws it and turns touches into
// building. With no tool picked, one finger moves the view and a tap tells what is there; with a tool,
// a drag lays a road (a line) or zones / clears a rectangle, and a tap puts a service down. Two fingers
// always move and zoom the view. The city is saved in the world's folder.

@MainActor
final class MetroSession: ObservableObject {
    let city: Metro
    let scene: MetroScene
    let file: URL
    @Published var tool = ""                 // "", street, avenue, R, C, I, dezone, bulldoze, or a service key
    @Published var overlay = ""
    @Published var speed = 1
    @Published var money = 0, population = 0, income = 0, expense = 0
    @Published var demand: (Double, Double, Double) = (0, 0, 0)
    @Published var date = ""
    @Published var info: [String] = []
    @Published var notice = ""
    @Published var showBudget = false
    @Published var taxes: [Double] = [0.09, 0.09, 0.09]
    @Published var power = "", water = ""
    @Published var tick = 0
    var noticeUntil = 0.0
    var onExit: () -> Void = {}
    static let daysPerSecond: [Double] = [0, 0.7, 2.5, 8]

    init(city: Metro, file: URL) {
        self.city = city
        self.file = file
        scene = MetroScene(size: CGSize(width: 874, height: 402))
        scene.scaleMode = .resizeFill
        scene.session = self
        taxes = city.taxes
    }

    func say(_ t: String) { notice = t; noticeUntil = CACurrentMediaTime() + 3.5 }

    func pick(_ t: String) { tool = tool == t ? "" : t; info = [] }

    func setTax(_ z: Int, _ v: Double) { city.setTax(z, v); taxes = city.taxes }

    /// Write the city to its file (whole, then swapped in, so a crash leaves the old one).
    @discardableResult func save() -> Bool {
        guard let data = try? JSONEncoder().encode(city) else { return false }
        let tmp = file.appendingPathExtension("tmp")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: tmp)
            _ = try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tmp, to: file)
            return true
        } catch { return false }
    }

    func leave() { save(); onExit() }

    func refresh() {
        money = Int(city.money); population = city.population
        income = Int(city.income); expense = Int(city.expense)
        demand = (city.demand.r, city.demand.c, city.demand.i)
        let d = city.date
        date = L("第\(d.year)年 \(d.month)月\(d.day)日", "Y\(d.year) M\(d.month) D\(d.day)")
        power = "\(Int(city.powerUsed))/\(Int(city.powerMade))"; water = "\(Int(city.waterUsed))/\(Int(city.waterMade))"
        if !notice.isEmpty && CACurrentMediaTime() > noticeUntil { notice = "" }
        for e in city.takeEvents() {
            let parts = e.text.split(separator: "|").map(String.init)
            let what = GameModel.zh ? parts[0] : (parts.count > 1 ? parts[1] : parts[0])
            say(e.good ? L("已解锁：", "Unlocked: ") + what : what)
        }
        tick &+= 1
    }
}

final class MetroScene: SKScene {
    weak var session: MetroSession?
    private let cam = SKCameraNode()
    private var ground: [SKSpriteNode] = []
    private var groundStale: Set<Int> = []
    private var roadNodes: [Int: SKSpriteNode] = [:]
    private var lotNodes: [Int: SKSpriteNode] = [:]
    private var zoneNodes: [Int: SKSpriteNode] = [:]
    private var serviceNodes: [Int: SKSpriteNode] = [:]
    private var shown: (road: [UInt8], zone: [UInt8], level: [UInt8], ab: [Bool]) = ([], [], [], [])
    private var shownServices: [MetroBuilding] = []
    private var tex: [String: SKTexture] = [:]
    private let overlayNode = SKSpriteNode()
    private var overlayShown = "", overlayDay = -1
    private let preview = SKNode()
    private var cars: [SKSpriteNode] = []
    private var lastTime: TimeInterval = 0
    private var hudAcc = 0.0, carAcc = 0.0, saveAcc = 0.0, groundAcc = 0.0
    private var zoom: CGFloat = 1.5
    private var touchesDown: [UITouch] = []
    private var dragStart: TilePos?, dragNow: TilePos?
    private var moved = false, pinching = false
    private var pinchDist: CGFloat = 1, pinchZoom: CGFloat = 1
    private var startPoint: CGPoint = .zero

    private func world(_ p: CGPoint) -> TilePos { TilePos(Int((p.x / 16).rounded(.down)), Int((-p.y / 16).rounded(.down))) }
    private func scenePoint(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: x * 16, y: -(y * 16)) }

    override func didMove(to view: SKView) {
        guard cam.parent == nil, let city = session?.city else { return }
        backgroundColor = UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        addChild(cam); camera = cam
        overlayNode.anchorPoint = CGPoint(x: 0, y: 1); overlayNode.zPosition = 300; overlayNode.isHidden = true
        overlayNode.size = CGSize(width: Metro.size * 16, height: Metro.size * 16)
        addChild(overlayNode)
        preview.zPosition = 900
        addChild(preview)
        for k in 0..<4 {
            let n = SKSpriteNode()
            n.anchorPoint = CGPoint(x: 0, y: 1)
            n.position = CGPoint(x: (k % 2) * 512 - 8, y: -((k / 2) * 512 - 24))
            n.zPosition = -100
            addChild(n); ground.append(n)
            groundStale.insert(k)
        }
        // look at the middle of what is built, or the middle of the land
        let built = city.road.indices.filter { city.road[$0] != 0 }
        let c = built.isEmpty ? Metro.size * Metro.size / 2 + Metro.size / 2 : built[built.count / 2]
        cam.position = CGPoint(x: (c % Metro.size) * 16, y: -((c / Metro.size) * 16))
        cam.setScale(1 / zoom)
        bakeGround()
    }

    private func bakeGround() {
        guard let city = session?.city, !groundStale.isEmpty else { return }
        let todo = groundStale; groundStale = []
        let layers = city.layers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for k in todo.sorted() {
                let cg = PixelArt.bakeChunk(layers: layers[k]).cgImage
                DispatchQueue.main.async {
                    guard let self = self, let cg = cg else { return }
                    let t = SKTexture(cgImage: cg); t.filteringMode = .nearest
                    self.ground[k].texture = t; self.ground[k].size = t.size()
                }
            }
        }
    }

    private func texture(_ key: String, _ make: () -> Bitmap) -> SKTexture {
        if let t = tex[key] { return t }
        let t = make().texture
        tex[key] = t
        return t
    }

    // MARK: frame

    override func update(_ currentTime: TimeInterval) {
        guard let session = session else { return }
        let city = session.city
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        city.tick(dt, daysPerSecond: MetroSession.daysPerSecond[session.speed])
        syncTiles(city)
        syncOverlay(city, session.overlay)
        hudAcc += dt
        if hudAcc > 0.25 { hudAcc = 0; session.refresh() }
        carAcc += dt
        if carAcc > 0.3 { carAcc = 0; drive(city) }
        groundAcc += dt
        if groundAcc > 1 { groundAcc = 0; bakeGround() }
        saveAcc += dt
        if saveAcc > 60 { saveAcc = 0; session.save() }
    }

    private func syncTiles(_ city: Metro) {
        let n = Metro.size * Metro.size
        if shown.road.count != n { shown = ([UInt8](repeating: 0, count: n), [UInt8](repeating: 0, count: n), [UInt8](repeating: 0, count: n), [Bool](repeating: false, count: n)) }
        var roadChanged = Set<Int>()
        for i in 0..<n {
            let r = city.road[i], z = city.zone[i], lv = city.level[i], ab = city.abandoned[i] > 0
            if r != shown.road[i] { roadChanged.insert(i); for j in [i - 1, i + 1, i - Metro.size, i + Metro.size] where j >= 0 && j < n { roadChanged.insert(j) }; groundStale.insert(chunkOf(i)) }
            if z != shown.zone[i] || lv != shown.level[i] || ab != shown.ab[i] {
                if lv > 0 && shown.level[i] == 0 { groundStale.insert(chunkOf(i)) }
                lot(i, z, lv, ab, city)
            }
            shown.road[i] = r; shown.zone[i] = z; shown.level[i] = lv; shown.ab[i] = ab
        }
        for i in roadChanged { roadTile(i, city) }
        if city.services != shownServices {
            let ids = Set(city.services.map { $0.id })
            for (id, node) in serviceNodes where !ids.contains(id) { node.removeFromParent(); serviceNodes[id] = nil }
            for b in city.services where serviceNodes[b.id] == nil {
                let d = b.def
                let t = texture("s\(d.key)") { PixelArt.metroService(d) }
                let node = SKSpriteNode(texture: t)
                node.anchorPoint = CGPoint(x: 0, y: 0)
                node.position = CGPoint(x: b.x * 16, y: -((b.y + d.h) * 16))
                node.zPosition = 10 + CGFloat(b.y + d.h) * 0.01
                addChild(node)
                serviceNodes[b.id] = node
                groundStale.insert(chunkOf(Metro.size * b.y + b.x))
            }
            shownServices = city.services
        }
    }

    private func chunkOf(_ i: Int) -> Int { ((i / Metro.size) / 32) * 2 + (i % Metro.size) / 32 }

    private func roadTile(_ i: Int, _ city: Metro) {
        let x = i % Metro.size, y = i / Metro.size
        let r = city.road[i]
        guard r != 0 else { roadNodes[i]?.removeFromParent(); roadNodes[i] = nil; return }
        var mask = 0
        if city.isRoad(x, y - 1) { mask |= 1 }
        if city.isRoad(x + 1, y) { mask |= 2 }
        if city.isRoad(x, y + 1) { mask |= 4 }
        if city.isRoad(x - 1, y) { mask |= 8 }
        let avenue = r == MetroRoad.avenue.rawValue
        let t = texture("r\(mask)\(avenue)") { PixelArt.metroRoad(mask: mask, avenue: avenue) }
        let node = roadNodes[i] ?? { let n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0, y: 1); n.position = scenePoint(x, y); n.zPosition = 1; addChild(n); roadNodes[i] = n; return n }()
        node.texture = t; node.size = t.size()
    }

    private func lot(_ i: Int, _ z: UInt8, _ lv: UInt8, _ ab: Bool, _ city: Metro) {
        let x = i % Metro.size, y = i / Metro.size
        // the zone shows as a tint while the lot is empty
        if z != 0 && lv == 0 {
            let node = zoneNodes[i] ?? { let n = SKSpriteNode(color: .clear, size: CGSize(width: 14, height: 14)); n.anchorPoint = CGPoint(x: 0, y: 1); n.position = CGPoint(x: x * 16 + 1, y: -(y * 16 + 1)); n.zPosition = 2; addChild(n); zoneNodes[i] = n; return n }()
            node.color = [UIColor.clear, UIColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1), UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1), UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1)][Int(z)]
            node.alpha = 0.35
        } else { zoneNodes[i]?.removeFromParent(); zoneNodes[i] = nil }
        guard lv > 0 else { lotNodes[i]?.removeFromParent(); lotNodes[i] = nil; return }
        let variant = Int(MP.h2(city.seed, x, y) % 40)
        let t = texture("b\(z)\(lv)\(variant)\(ab)") { PixelArt.metro(zone: Int(z), level: Int(lv), variant: variant, abandoned: ab) }
        let node = lotNodes[i] ?? { let n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0, y: 0); n.position = CGPoint(x: x * 16, y: -((y + 1) * 16)); n.zPosition = 10 + CGFloat(y + 1) * 0.01; addChild(n); lotNodes[i] = n; return n }()
        if node.texture != t {
            node.texture = t; node.size = t.size()
            node.setScale(0.6); node.run(.scale(to: 1, duration: 0.25))          // a new or rebuilt building rises
        }
    }

    private func syncOverlay(_ city: Metro, _ k: String) {
        guard !k.isEmpty else { overlayNode.isHidden = true; overlayShown = ""; return }
        if k == overlayShown && city.day == overlayDay { return }
        overlayShown = k; overlayDay = city.day
        let v = city.overlay(k)
        var b = Bitmap(Metro.size, Metro.size)
        let bad = ["traffic", "pollution"].contains(k)
        for i in v.indices where v[i] >= 0 {
            let t = Double(max(0, min(1, v[i])))
            let good = RGBA(hex: "#3ad06a"), poor = RGBA(hex: "#e8443a"), mid = RGBA(hex: "#f0d040")
            let c = bad ? (t < 0.5 ? good.lerp(mid, t * 2) : mid.lerp(poor, (t - 0.5) * 2)) : (t < 0.5 ? poor.lerp(mid, t * 2) : mid.lerp(good, (t - 0.5) * 2))
            b.set(i % Metro.size, i / Metro.size, RGBA(c.r, c.g, c.b, k == "traffic" ? 230 : 150))
        }
        let t = b.texture
        overlayNode.texture = t
        overlayNode.size = CGSize(width: Metro.size * 16, height: Metro.size * 16)
        overlayNode.isHidden = false
    }

    /// A few cars on the busiest roads, for life (they do not take part in the traffic numbers).
    private func drive(_ city: Metro) {
        cars.removeAll { $0.parent == nil }
        guard cars.count < 90 else { return }
        let busy = city.road.indices.filter { city.road[$0] != 0 && city.load[$0] > 2 }
        guard !busy.isEmpty else { return }
        for _ in 0..<min(6, 90 - cars.count) {
            var i = busy[Int.random(in: 0..<busy.count)]
            var steps: [SKAction] = []
            var last = -1
            for _ in 0..<10 {
                let x = i % Metro.size, y = i / Metro.size
                let next = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)].filter { city.isRoad($0.0, $0.1) && Metro.size * $0.1 + $0.0 != last }
                guard let n = next.randomElement() else { break }
                last = i
                i = n.1 * Metro.size + n.0
                steps.append(.move(to: CGPoint(x: n.0 * 16 + 8, y: -(n.1 * 16 + 8)), duration: 0.45))
            }
            guard !steps.isEmpty else { continue }
            let car = SKSpriteNode(color: [UIColor.white, .systemRed, .systemBlue, .systemYellow, .darkGray].randomElement()!, size: CGSize(width: 4, height: 4))
            let s = busy.randomElement()!
            car.position = CGPoint(x: (s % Metro.size) * 16 + 8, y: -((s / Metro.size) * 16 + 8))
            car.zPosition = 5
            addChild(car); cars.append(car)
            car.run(.sequence(steps + [.fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
    }

    // MARK: touches

    private func spread() -> CGFloat {
        guard let v = view, touchesDown.count >= 2 else { return 1 }
        let a = touchesDown[0].location(in: v), b = touchesDown[1].location(in: v)
        return max(1, hypot(a.x - b.x, a.y - b.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view else { return }
        for t in touches { touchesDown.append(t) }
        if touchesDown.count == 1, let t = touchesDown.first {
            moved = false
            startPoint = t.location(in: v)
            dragStart = world(t.location(in: self)); dragNow = dragStart
            showPreview()
        }
        if touchesDown.count == 2 { pinching = true; pinchDist = spread(); pinchZoom = zoom; dragStart = nil; preview.removeAllChildren() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view, let session = session else { return }
        if pinching && touchesDown.count >= 2 {
            zoom = min(4, max(0.45, pinchZoom * spread() / pinchDist))
            cam.setScale(1 / zoom)
            // two fingers also move the view
            let a = touchesDown[0], b = touchesDown[1]
            let now = CGPoint(x: (a.location(in: v).x + b.location(in: v).x) / 2, y: (a.location(in: v).y + b.location(in: v).y) / 2)
            let was = CGPoint(x: (a.previousLocation(in: v).x + b.previousLocation(in: v).x) / 2, y: (a.previousLocation(in: v).y + b.previousLocation(in: v).y) / 2)
            cam.position = CGPoint(x: cam.position.x - (now.x - was.x) / zoom, y: cam.position.y + (now.y - was.y) / zoom)
            clamp()
            return
        }
        guard let t = touchesDown.first, touches.contains(t) else { return }
        let p = t.location(in: v)
        if hypot(p.x - startPoint.x, p.y - startPoint.y) > 10 { moved = true }
        if session.tool.isEmpty {
            let q = t.previousLocation(in: v)
            cam.position = CGPoint(x: cam.position.x - (p.x - q.x) / zoom, y: cam.position.y + (p.y - q.y) / zoom)
            clamp()
        } else {
            dragNow = world(t.location(in: self))
            showPreview()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let session = session else { return }
        let city = session.city
        for t in touches {
            let first = touchesDown.first === t
            touchesDown.removeAll { $0 === t }
            let wasPinch = pinching
            if touchesDown.isEmpty { pinching = false }
            guard first, !wasPinch, let a = dragStart else { continue }
            let b = dragNow ?? a
            preview.removeAllChildren()
            dragStart = nil
            switch session.tool {
            case "":
                if !moved { session.info = city.describe(a.x, a.y, zh: GameModel.zh) }
            case "street", "avenue":
                let kind: MetroRoad = session.tool == "avenue" ? .avenue : .street
                let plan = city.roadPlan(a, b, kind)
                if city.buildRoad(a, b, kind) { session.say(L("道路 −\(Int(plan.cost))", "Road −\(Int(plan.cost))")) }
                else { session.say(kind == .avenue && !city.avenueUnlocked ? L("大道在 900 人时解锁", "Avenues unlock at 900 people") : (plan.cost > city.money ? L("资金不足", "Not enough money") : L("这里修不了路（水域或建筑）", "No road here (water or a building)"))) }
            case "R", "C", "I", "dezone":
                let z: MetroZone = ["R": .residential, "C": .commercial, "I": .industrial][session.tool] ?? .none
                if city.setZone(a, b, z) == 0 && z != .none { session.say(L("只能沿道路规划（3 格以内）", "Zones go along roads (within 3 tiles)")) }
            case "bulldoze":
                city.bulldoze(a, b)
            default:
                guard let k = MetroService.index[session.tool] else { break }
                let d = MetroService.all[k]
                let at = TilePos(b.x - d.w / 2, b.y - d.h / 2)
                if city.placeService(k, at: at) { session.say(d.name(zh: GameModel.zh) + L(" 已建成", " built")) }
                else { session.say(!city.unlocked(k) ? L("\(d.unlock) 人时解锁", "Unlocks at \(d.unlock) people") : (city.money < d.cost ? L("资金不足", "Not enough money") : L("放不下（要空地，靠路才能运作）", "It does not fit (open land; it works next to a road)"))) }
            }
            session.refresh()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { touchesDown.removeAll { $0 === t } }
        if touchesDown.isEmpty { pinching = false }
        dragStart = nil; preview.removeAllChildren()
    }

    private func clamp() {
        let m = CGFloat(Metro.size * 16)
        cam.position = CGPoint(x: min(m, max(0, cam.position.x)), y: max(-m, min(0, cam.position.y)))
    }

    /// What the tool would do, drawn on the map while the finger is down.
    private func showPreview() {
        preview.removeAllChildren()
        guard let session = session, let a = dragStart, let b = dragNow, !session.tool.isEmpty else { return }
        let city = session.city
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UIColor) {
            let n = SKSpriteNode(color: c, size: CGSize(width: w * 16, height: h * 16))
            n.anchorPoint = CGPoint(x: 0, y: 1); n.position = scenePoint(x, y); n.alpha = 0.45
            preview.addChild(n)
        }
        switch session.tool {
        case "street", "avenue":
            let p = city.roadPlan(a, b, session.tool == "avenue" ? .avenue : .street)
            for t in p.tiles { box(t.x, t.y, 1, 1, p.ok ? .white : .red) }
            let l = SKLabelNode(text: "\(Int(p.cost))")
            l.fontName = "AvenirNext-Bold"; l.fontSize = 10; l.fontColor = p.ok ? .white : .red
            l.position = CGPoint(x: b.x * 16 + 8, y: -(b.y * 16) + 6)
            preview.addChild(l)
        case "R", "C", "I", "dezone", "bulldoze":
            let c: UIColor = ["R": .green, "C": .systemBlue, "I": .systemYellow, "dezone": .gray, "bulldoze": .red][session.tool] ?? .white
            box(min(a.x, b.x), min(a.y, b.y), abs(b.x - a.x) + 1, abs(b.y - a.y) + 1, c)
        default:
            guard let k = MetroService.index[session.tool] else { return }
            let d = MetroService.all[k]
            let at = TilePos(b.x - d.w / 2, b.y - d.h / 2)
            box(at.x, at.y, d.w, d.h, city.canPlace(k, at: at) ? .green : .red)
            if d.radius > 0 {
                let r = SKShapeNode(circleOfRadius: CGFloat(d.radius) * 16)
                r.position = CGPoint(x: CGFloat(at.x) * 16 + CGFloat(d.w) * 8, y: -(CGFloat(at.y) * 16 + CGFloat(d.h) * 8)); r.strokeColor = .white; r.lineWidth = 1; r.alpha = 0.6
                preview.addChild(r)
            }
        }
    }
}

/// The city with its HUD: money, people, date and demand on top; tools at the bottom; overlays and budget.
struct MetroView: View {
    @ObservedObject var session: MetroSession
    @State private var group = ""

    var body: some View {
        ZStack {
            SpriteView(scene: session.scene, preferredFramesPerSecond: 60).ignoresSafeArea()
            VStack(spacing: 6) {
                top
                if !session.notice.isEmpty {
                    Text(session.notice).font(.system(size: 12, weight: .medium, design: .rounded)).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.black.opacity(0.6), in: Capsule()).accessibilityIdentifier("metro-notice")
                }
                Spacer()
                if !session.info.isEmpty { infoCard }
                if !group.isEmpty { palette }
                bottom
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if session.showBudget { budget }
        }
        .foregroundStyle(.white)
    }

    private var top: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(session.city.name).font(.system(size: 13, weight: .bold, design: .rounded))
                Label("\(session.money)", systemImage: "dollarsign.circle.fill").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.money < 0 ? Color.red : Color.white).accessibilityIdentifier("metro-money")
                Label("\(session.population)", systemImage: "person.3.fill").font(.system(size: 13, weight: .semibold, design: .rounded)).accessibilityIdentifier("metro-pop")
                Text(session.date).font(.system(size: 11, design: .rounded)).opacity(0.85)
                demandBars
            }.padding(.horizontal, 14).padding(.vertical, 8).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule())
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<4) { s in
                    Button { session.speed = s } label: {
                        Image(systemName: s == 0 ? "pause.fill" : (s == 1 ? "play.fill" : (s == 2 ? "forward.fill" : "forward.end.alt.fill"))).font(.system(size: 12, weight: .bold)).frame(width: 32, height: 32)
                            .background(session.speed == s ? Color.white.opacity(0.25) : Color.clear, in: Circle())
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("metro-speed-\(s)")
                }
            }.padding(3).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule())
            Button { session.leave() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36) }
                .buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Circle()).glass(Circle()).accessibilityIdentifier("metro-exit")
        }
    }

    private var demandBars: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3) { k in
                let v = [session.demand.0, session.demand.1, session.demand.2][k]
                VStack(spacing: 1) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.15)).frame(width: 7, height: 22)
                        RoundedRectangle(cornerRadius: 1).fill([Color.green, Color.blue, Color.yellow][k].opacity(v > 0 ? 1 : 0.35)).frame(width: 7, height: CGFloat(max(2, abs(v) / 100 * 22)))
                    }
                    Text(["R", "C", "I"][k]).font(.system(size: 7, weight: .bold, design: .rounded))
                }
            }
        }.accessibilityIdentifier("metro-demand")
    }

    private var bottom: some View {
        HStack(spacing: 6) {
            groupButton(L("道路", "Roads"), "road.lanes", "roads")
            groupButton(L("分区", "Zones"), "square.grid.3x3.fill", "zones")
            groupButton(L("设施", "Services"), "building.2.fill", "services")
            groupButton(L("图层", "Views"), "map.fill", "views")
            tool(L("拆除", "Bulldoze"), "hammer.fill", "bulldoze")
            Button { session.showBudget = true } label: { Label(L("预算", "Budget"), systemImage: "chart.bar.fill").font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 8) }
                .buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier("metro-budget")
            Spacer()
            if !session.tool.isEmpty {
                Button { session.tool = "" } label: { Label(L("完成", "Done"), systemImage: "checkmark").font(.system(size: 12, weight: .bold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 8) }
                    .buttonStyle(PressStyle()).background(Color.green.opacity(0.5), in: Capsule()).accessibilityIdentifier("metro-done")
            }
        }
    }

    private func groupButton(_ title: String, _ icon: String, _ g: String) -> some View {
        Button { group = group == g ? "" : g } label: {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 8)
                .background(group == g ? Color.white.opacity(0.25) : Color.clear, in: Capsule())
        }.buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier("metro-group-\(g)")
    }

    private func tool(_ title: String, _ icon: String, _ t: String, enabled: Bool = true, sub: String = "") -> some View {
        Button { session.pick(t) } label: {
            VStack(spacing: 1) {
                Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold, design: .rounded))
                if !sub.isEmpty { Text(sub).font(.system(size: 9, design: .rounded)).opacity(0.8) }
            }.padding(.horizontal, 10).padding(.vertical, 7)
            .background(session.tool == t ? Color.green.opacity(0.5) : Color.clear, in: Capsule())
        }.buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule())
        .opacity(enabled ? 1 : 0.4).disabled(!enabled).accessibilityIdentifier("metro-tool-\(t)")
    }

    private var palette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                switch group {
                case "roads":
                    tool(L("街道", "Street"), "road.lanes", "street", sub: "\(Int(MetroRoad.street.cost))/" + L("格", "tile"))
                    tool(L("大道", "Avenue"), "road.lanes.curved.right", "avenue", enabled: session.city.avenueUnlocked, sub: session.city.avenueUnlocked ? "\(Int(MetroRoad.avenue.cost))/" + L("格", "tile") : L("900 人", "900 people"))
                case "zones":
                    tool(L("住宅", "Homes"), "house.fill", "R")
                    tool(L("商业", "Shops"), "cart.fill", "C")
                    tool(L("工业", "Industry"), "gearshape.2.fill", "I")
                    tool(L("取消分区", "Unzone"), "square.dashed", "dezone")
                case "services":
                    ForEach(Array(MetroService.all.enumerated()), id: \.offset) { p in
                        let open = session.city.unlocked(p.offset)
                        tool(p.element.name(zh: GameModel.zh), icon(p.element.effect), p.element.key, enabled: open, sub: open ? "\(Int(p.element.cost))" : L("\(p.element.unlock) 人", "\(p.element.unlock) people"))
                    }
                default:
                    ForEach(["traffic", "pollution", "value", "happiness", "power", "water", "police", "fire", "health", "education"], id: \.self) { k in
                        Button { session.overlay = session.overlay == k ? "" : k } label: {
                            Text(viewName(k)).font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 8)
                                .background(session.overlay == k ? Color.green.opacity(0.5) : Color.clear, in: Capsule())
                        }.buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier("metro-view-\(k)")
                    }
                }
            }
        }
    }

    private func icon(_ effect: String) -> String {
        ["power": "bolt.fill", "water": "drop.fill", "park": "leaf.fill", "police": "shield.fill", "fire": "flame.fill", "health": "cross.fill", "education": "graduationcap.fill", "landmark": "moon.stars.fill"][effect] ?? "building.2.fill"
    }

    private func viewName(_ k: String) -> String {
        let zh = ["traffic": "交通", "pollution": "污染", "value": "地价", "happiness": "幸福", "power": "电力", "water": "供水", "police": "治安", "fire": "消防", "health": "医疗", "education": "教育"]
        let en = ["traffic": "Traffic", "pollution": "Pollution", "value": "Land value", "happiness": "Happiness", "power": "Power", "water": "Water", "police": "Police", "fire": "Fire", "health": "Health", "education": "Schools"]
        return (GameModel.zh ? zh[k] : en[k]) ?? k
    }

    private var infoCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(session.info.enumerated()), id: \.offset) { p in
                    Text(p.element).font(.system(size: p.offset == 0 ? 13 : 11, weight: p.offset == 0 ? .bold : .regular, design: .rounded))
                }
            }
            Spacer()
            Button { session.info = [] } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }.buttonStyle(PressStyle())
        }
        .padding(10).frame(maxWidth: 320).background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("metro-info")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var budget: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { session.showBudget = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("预算", "Budget")).font(.system(size: 19, weight: .bold, design: .rounded))
                    Spacer()
                    Button { session.showBudget = false } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 30, height: 30) }.buttonStyle(PressStyle()).accessibilityIdentifier("metro-budget-close")
                }
                Text(L("每日收入 \(session.income) · 支出 \(session.expense) · 结余 \(session.income - session.expense)", "Daily income \(session.income) · costs \(session.expense) · net \(session.income - session.expense)"))
                    .font(.system(size: 12, design: .rounded)).accessibilityIdentifier("metro-budget-line")
                Text(L("电力 \(session.power) · 供水 \(session.water)", "Power \(session.power) · water \(session.water)")).font(.system(size: 12, design: .rounded)).opacity(0.85)
                ForEach(0..<3) { z in
                    HStack {
                        Text([L("住宅税", "Homes tax"), L("商业税", "Shops tax"), L("工业税", "Industry tax")][z]).font(.system(size: 12, weight: .semibold, design: .rounded)).frame(width: 82, alignment: .leading)
                        Slider(value: Binding(get: { session.taxes[z] }, set: { session.setTax(z, ($0 * 100).rounded() / 100) }), in: 0.01...0.25).accessibilityIdentifier("metro-tax-\(z)")
                        Text("\(Int((session.taxes[z] * 100).rounded()))%").font(.system(size: 12, design: .monospaced)).frame(width: 38)
                    }
                }
                Text(L("税率高于 9% 会降低需求和幸福；低于 9% 则相反。", "Taxes above 9% cool demand and happiness; below 9% the reverse.")).font(.system(size: 10, design: .rounded)).opacity(0.75)
            }
            .padding(18).frame(maxWidth: 440).background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20)).glass(RoundedRectangle(cornerRadius: 20))
        }
    }
}
