import SpriteKit
import SwiftUI
import UIKit
import MoonPixelCore

// Command mode on screen. The battle itself is MoonPixelCore's `Skirmish`; this file draws it from
// above and turns touches into orders. A tap picks one of your units or structures, or sends what is
// picked to a place or at an enemy; a drag moves the view (or draws a box while "Box" is on); a pinch
// zooms; a finished structure is put down with a tap.

@MainActor
final class SkirmishSession: ObservableObject {
    let sim: Skirmish
    let scene: CommandScene
    @Published var credits = 0
    @Published var powerMade = 0
    @Published var powerUsed = 0
    @Published var making: [Int?] = [nil, nil, nil]
    @Published var progress: [Double] = [0, 0, 0]
    @Published var waiting: [Int] = [0, 0, 0]
    @Published var ready: Int?
    @Published var placing = false
    @Published var boxing = false
    @Published var selected: [Int] = []
    @Published var selectionText = ""
    @Published var winner: Int?
    @Published var notice = ""
    @Published var clock = 0
    @Published var tick = 0
    var noticeUntil = 0.0
    var onExit: () -> Void = {}

    init(sim: Skirmish) {
        self.sim = sim
        scene = CommandScene(size: CGSize(width: 874, height: 402))
        scene.scaleMode = .resizeFill
        scene.session = self
    }

    func say(_ t: String) { notice = t; noticeUntil = CACurrentMediaTime() + 3 }

    func build(_ kind: Int) {
        let d = SkKind.all[kind]
        if d.structure, ready == kind { placing.toggle(); return }
        if !sim.queue(0, kind) {
            say(sim.sides[0].credits < d.cost ? L("月矿不足", "Not enough moonstone") : (d.structure ? L("一次只能造一座建筑", "One structure at a time") : L("还不能造", "Not available yet")))
        }
        refresh()
    }

    func cancel(_ line: Int) { if sim.cancel(0, line: line) { placing = false }; refresh() }
    func selectArmy() { select(sim.entities.values.filter { $0.side == 0 && !$0.def.structure && $0.def.damage > 0 }.map { $0.id }.sorted()) }
    func stop() { sim.stop(selected) }
    func harvest() { sim.orderHarvest(selected) }

    func select(_ ids: [Int]) {
        selected = ids
        let es = ids.compactMap { sim.entities[$0] }
        if es.isEmpty { selectionText = "" }
        else if es.count == 1, let e = es.first { selectionText = "\(e.def.name(zh: GameModel.zh))  \(Int(max(0, e.hp)))/\(Int(e.def.hp))" }
        else {
            let groups = Dictionary(grouping: es, by: { $0.kind }).sorted { $0.key < $1.key }
            selectionText = groups.map { "\(SkKind.all[$0.key].name(zh: GameModel.zh))×\($0.value.count)" }.joined(separator: "  ")
        }
    }

    /// The numbers the HUD shows, a few times a second.
    func refresh() {
        let s = sim.sides[0]
        credits = Int(s.credits); powerMade = Int(s.powerMade); powerUsed = Int(s.powerUsed)
        making = s.making; progress = s.progress; waiting = s.queued.map { $0.count }
        if ready != s.ready { ready = s.ready; if s.ready == nil { placing = false } }
        winner = sim.winner
        clock = Int(sim.time)
        let alive = selected.filter { sim.entities[$0] != nil }
        if alive.count != selected.count || selected.count == 1 { select(alive) }
        if !notice.isEmpty && CACurrentMediaTime() > noticeUntil { notice = "" }
        tick &+= 1
    }
}

final class CommandScene: SKScene {
    weak var session: SkirmishSession?
    private let cam = SKCameraNode()
    private var nodes: [Int: SKSpriteNode] = [:]
    private var oreNodes: [Int: SKSpriteNode] = [:]
    private var tex: [String: SKTexture] = [:]
    private var lastTime: TimeInterval = 0
    private var hudAcc = 0.0, oreAcc = 1.0
    private var zoom: CGFloat = 1.6
    private var touchesDown: [UITouch] = []
    private var startPoint: [ObjectIdentifier: CGPoint] = [:]
    private var dragged = false, pinching = false
    private var pinchDist: CGFloat = 1, pinchZoom: CGFloat = 1
    private var boxStart: CGPoint?
    private let box = SKShapeNode()
    private let ghost = SKSpriteNode()
    private var shots = 0
    /// Run the battle this many times faster (the demo flag uses it).
    var pace = 1.0

    private func pt(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: -v.y) }
    private func world(_ p: CGPoint) -> Vec2 { Vec2(Double(p.x), Double(-p.y)) }

    override func didMove(to view: SKView) {
        guard cam.parent == nil, let sim = session?.sim else { return }
        backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        addChild(cam); camera = cam
        box.strokeColor = UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1); box.fillColor = UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 0.12); box.lineWidth = 1; box.zPosition = 900; box.isHidden = true
        ghost.alpha = 0.6; ghost.anchorPoint = CGPoint(x: 0, y: 1); ghost.zPosition = 800; ghost.isHidden = true
        addChild(box); addChild(ghost)
        // the ground: the nine chunks of generated land, baked off the main thread
        let layers = sim.layers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (i, l) in layers.enumerated() {
                let cg = PixelArt.bakeChunk(layers: l).cgImage
                DispatchQueue.main.async {
                    guard let self = self, let cg = cg else { return }
                    let t = SKTexture(cgImage: cg); t.filteringMode = .nearest
                    let n = SKSpriteNode(texture: t)
                    n.anchorPoint = CGPoint(x: 0, y: 1)
                    n.position = CGPoint(x: (i % 3) * 512 - 8, y: -((i / 3) * 512 - 24))
                    n.zPosition = -100
                    self.addChild(n)
                }
            }
        }
        if let hq = sim.entities.values.first(where: { $0.side == 0 && $0.def.key == "hq" }) { cam.position = pt(hq.pos) }
        cam.setScale(1 / zoom)
    }

    // MARK: frame

    override func update(_ currentTime: TimeInterval) {
        guard let session = session else { return }
        let sim = session.sim
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        sim.tick(dt * pace)
        sync(sim, session)
        for e in sim.takeEvents() { show(e, sim, session) }
        oreAcc += dt
        if oreAcc > 0.5 { oreAcc = 0; syncOre(sim) }
        hudAcc += dt
        if hudAcc > 0.2 { hudAcc = 0; session.refresh() }
        // what is ready follows the middle of the view until it is put down
        if session.placing, let k = session.ready {
            let d = SkKind.all[k]
            let t = corner(of: d, at: world(cam.position))
            ghost.isHidden = false
            ghost.texture = texture(for: d, side: 0); ghost.size = ghost.texture?.size() ?? .zero
            ghost.position = CGPoint(x: t.x * 16, y: -(t.y * 16 - 8))
            ghost.color = sim.canPlace(k, side: 0, at: t) ? .green : .red
            ghost.colorBlendFactor = 0.5
        } else { ghost.isHidden = true }
    }

    private func corner(of d: SkKind, at p: Vec2) -> TilePos { TilePos(p.tile.x - d.w / 2, p.tile.y - d.h / 2) }

    private func texture(for d: SkKind, side: Int, facing: Vec2 = Vec2(0, 1), frame: Int = 0) -> SKTexture {
        let color = session?.sim.sides[side].color ?? "#ffffff"
        if d.armor == .infantry {
            let dir = abs(facing.x) > abs(facing.y) ? "side" : (facing.y < 0 ? "up" : "down")
            let key = "i\(d.key)\(color)\(dir)\(frame)"
            if let t = tex[key] { return t }
            var look = Look()
            look.shirt = color; look.pants = d.key == "lancer" ? "#3a3a44" : "#5a5a4a"; look.hair = d.key == "lancer" ? "#2a2a2a" : "#5a3a22"
            let t = PixelArt.character(look, dir: dir, frame: frame, held: d.key == "lancer" ? "staff" : "bow", child: false, female: false).texture
            tex[key] = t
            return t
        }
        let key = "k\(d.key)\(color)"
        if let t = tex[key] { return t }
        let t = PixelArt.skirmish(d, color: RGBA(hex: color)).texture
        tex[key] = t
        return t
    }

    private func sync(_ sim: Skirmish, _ session: SkirmishSession) {
        let phase = Int(CACurrentMediaTime() * 6)
        let picked = Set(session.selected)
        for (id, e) in sim.entities {
            let d = e.def
            let node = nodes[id] ?? {
                let n = SKSpriteNode()
                let bar = SKSpriteNode(color: .green, size: CGSize(width: 16, height: 2))
                bar.name = "hp"; bar.anchorPoint = CGPoint(x: 0, y: 0.5); bar.zPosition = 2
                let ring = SKShapeNode(circleOfRadius: d.structure ? CGFloat(max(d.w, d.h)) * 9 : 9)
                ring.name = "ring"; ring.strokeColor = UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1); ring.lineWidth = 1.2; ring.zPosition = -1; ring.isHidden = true
                n.addChild(bar); n.addChild(ring)
                if d.structure {
                    n.anchorPoint = CGPoint(x: 0, y: 1)
                    n.texture = texture(for: d, side: e.side); n.size = n.texture?.size() ?? .zero
                    n.position = CGPoint(x: e.tile.x * 16, y: -(e.tile.y * 16 - 8))
                    n.zPosition = 5 + CGFloat(e.tile.y + d.h) * 0.01
                    bar.position = CGPoint(x: n.size.width / 2 - 8, y: -2)
                    ring.position = CGPoint(x: n.size.width / 2, y: -n.size.height / 2 - 4)
                } else if d.armor == .infantry {
                    n.anchorPoint = CGPoint(x: 0.5, y: 0.1); n.setScale(0.42)
                    bar.position = CGPoint(x: -8, y: 42); bar.setScale(2.4); ring.position = CGPoint(x: 0, y: 4); ring.setScale(2.4)
                } else {
                    n.texture = texture(for: d, side: e.side); n.size = n.texture?.size() ?? .zero
                    bar.position = CGPoint(x: -8, y: 15)
                }
                addChild(n)
                nodes[id] = n
                return n
            }()
            if !d.structure {
                node.position = pt(e.pos)
                node.zPosition = 10 + CGFloat(e.pos.y) * 0.001
                if d.armor == .infantry {
                    let side = abs(e.facing.x) > abs(e.facing.y)
                    let t = texture(for: d, side: e.side, facing: e.facing, frame: e.sinceShot < 0.25 ? 3 : (e.moving ? 1 + (phase + id) % 2 : 0))
                    node.texture = t; node.size = t.size()
                    node.xScale = (side && e.facing.x < 0 ? -1 : 1) * 0.42
                } else {
                    node.zRotation = CGFloat(atan2(-e.facing.x, -e.facing.y)) + .pi            // the picture points up
                    // the bar and ring stay level while the hull turns
                    node.childNode(withName: "hp")?.zRotation = -node.zRotation
                }
            }
            let hurt = e.hp < d.hp * 0.999, sel = picked.contains(id)
            if let bar = node.childNode(withName: "hp") as? SKSpriteNode {
                bar.isHidden = !(hurt || sel)
                let f = CGFloat(max(0.03, min(1, e.hp / d.hp)))
                bar.xScale = f * (d.armor == .infantry ? 2.4 : 1)
                bar.color = f > 0.5 ? .green : (f > 0.25 ? .yellow : .red)
            }
            node.childNode(withName: "ring")?.isHidden = !sel
            node.colorBlendFactor = e.sinceHurt < 0.12 ? 0.5 : 0
            node.color = .white
        }
        for (id, n) in nodes where sim.entities[id] == nil { n.removeFromParent(); nodes[id] = nil }
    }

    private func syncOre(_ sim: Skirmish) {
        let t = tex["ore"] ?? {
            var b = Bitmap(16, 16)
            for (x, y, w, h) in [(3, 6, 4, 7), (8, 3, 5, 9), (6, 10, 6, 4)] { b.rect(x, y, w, h, RGBA(hex: "#59d8ff")); b.rect(x, y, w, 1, RGBA(hex: "#d8f6ff")); b.rect(x, y + h - 1, w, 1, RGBA(hex: "#2a7aa8")) }
            let t = b.texture; tex["ore"] = t; return t
        }()
        for i in sim.ore.indices {
            if sim.ore[i] > 0 {
                if oreNodes[i] == nil {
                    let n = SKSpriteNode(texture: t)
                    n.position = CGPoint(x: (i % Skirmish.size) * 16 + 8, y: -((i / Skirmish.size) * 16 + 8)); n.zPosition = 1
                    addChild(n); oreNodes[i] = n
                }
                oreNodes[i]?.alpha = CGFloat(0.45 + 0.55 * min(1, sim.ore[i] / 600))
            } else if let n = oreNodes[i] { n.removeFromParent(); oreNodes[i] = nil }
        }
    }

    private func show(_ e: SkEvent, _ sim: Skirmish, _ session: SkirmishSession) {
        switch e.kind {
        case "shot":
            guard shots < 60 else { return }
            shots += 1
            let path = CGMutablePath(); path.move(to: pt(e.a)); path.addLine(to: pt(e.b))
            let n = SKShapeNode(path: path)
            let big = SkKind.all[e.what].damage >= 40
            n.strokeColor = big ? UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1) : UIColor(white: 1, alpha: 0.9); n.lineWidth = big ? 2 : 1; n.zPosition = 500
            addChild(n)
            n.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent(), .run { [weak self] in self?.shots -= 1 }]))
        case "died":
            let n = SKShapeNode(circleOfRadius: SkKind.all[e.what].structure ? 22 : 7)
            n.fillColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.9); n.strokeColor = .clear; n.position = pt(e.a); n.zPosition = 510
            addChild(n)
            n.run(.sequence([.group([.scale(to: 1.8, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
            if e.side == 0 && SkKind.all[e.what].structure { session.say(L("我方建筑被毁：", "Structure lost: ") + SkKind.all[e.what].name(zh: GameModel.zh)) }
        case "built": if e.side == 0 { session.say(SkKind.all[e.what].name(zh: GameModel.zh) + L(" 已就绪，点它再点地图放置", " ready: tap it, then tap the map")) }
        case "lowpower": if e.side == 0 { session.say(L("电力不足", "Low power")) }
        case "attack": if e.side == 1 { session.say(L("敌军出动", "The enemy is on the move")) }
        default: break
        }
    }

    /// Look at a place (the minimap uses it).
    func look(at p: Vec2) { cam.position = pt(p); clampCamera() }
    var viewRect: (Vec2, Vec2) {
        let w = Double(size.width / zoom), h = Double(size.height / zoom)
        let c = world(cam.position)
        return (Vec2(c.x - w / 2, c.y - h / 2), Vec2(c.x + w / 2, c.y + h / 2))
    }

    private func clampCamera() {
        let m = CGFloat(Skirmish.size * 16)
        cam.position = CGPoint(x: min(m, max(0, cam.position.x)), y: max(-m, min(0, cam.position.y)))
    }

    // MARK: touches

    private func spread() -> CGFloat {
        guard let v = view, touchesDown.count >= 2 else { return 1 }
        let a = touchesDown[0].location(in: v), b = touchesDown[1].location(in: v)
        return max(1, hypot(a.x - b.x, a.y - b.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view, let session = session else { return }
        for t in touches {
            touchesDown.append(t)
            startPoint[ObjectIdentifier(t)] = t.location(in: v)
        }
        if touchesDown.count == 1 { dragged = false; if session.boxing { boxStart = touches.first?.location(in: self) } }
        if touchesDown.count == 2 { pinching = true; pinchDist = spread(); pinchZoom = zoom; boxStart = nil; box.isHidden = true }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view, let t = touchesDown.first else { return }
        if pinching && touchesDown.count >= 2 {
            zoom = min(4, max(0.5, pinchZoom * spread() / pinchDist))
            cam.setScale(1 / zoom)
            return
        }
        guard touches.contains(t), let s = startPoint[ObjectIdentifier(t)] else { return }
        let p = t.location(in: v)
        if hypot(p.x - s.x, p.y - s.y) > 12 { dragged = true }
        guard dragged else { return }
        if let b0 = boxStart {
            let b1 = t.location(in: self)
            box.path = CGPath(rect: CGRect(x: min(b0.x, b1.x), y: min(b0.y, b1.y), width: abs(b1.x - b0.x), height: abs(b1.y - b0.y)), transform: nil)
            box.isHidden = false
        } else {
            let q = t.previousLocation(in: v)
            cam.position = CGPoint(x: cam.position.x - (p.x - q.x) / zoom, y: cam.position.y + (p.y - q.y) / zoom)
            clampCamera()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let session = session else { return }
        let sim = session.sim
        for t in touches {
            let first = touchesDown.first === t
            touchesDown.removeAll { $0 === t }
            startPoint[ObjectIdentifier(t)] = nil
            let wasPinch = pinching
            if touchesDown.isEmpty { pinching = false }
            guard first, !wasPinch else { continue }
            let wp = world(t.location(in: self))
            if let b0 = boxStart, dragged {
                session.select(sim.units(of: 0, in: world(b0), wp))
                session.boxing = false
            } else if !dragged {
                tap(wp, session, sim)
            }
            boxStart = nil; box.isHidden = true
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { touchesDown.removeAll { $0 === t }; startPoint[ObjectIdentifier(t)] = nil }
        if touchesDown.isEmpty { pinching = false }
        boxStart = nil; box.isHidden = true
    }

    private func tap(_ wp: Vec2, _ session: SkirmishSession, _ sim: Skirmish) {
        if session.placing, let k = session.ready {
            // the finished structure goes where the ghost is shown: around the middle of the view; a tap elsewhere moves the view there first
            let t = corner(of: SkKind.all[k], at: wp)
            if sim.placeReady(0, at: t) { session.placing = false; session.refresh() }
            else { cam.position = pt(wp); clampCamera(); session.say(L("这里放不下（要空地，并靠近己方建筑）", "It does not fit here (free ground next to your own structures)")) }
            return
        }
        let hit = sim.entity(at: wp, radius: 14)
        let mine = session.selected.filter { sim.entities[$0]?.def.structure == false }
        if let e = hit, e.side == 0 { session.select([e.id]); return }
        if mine.isEmpty { session.select([]); return }
        if let e = hit, e.side != 0 { sim.order(mine, attack: e.id); mark(wp, UIColor.red) }
        else if sim.ore[min(sim.ore.count - 1, max(0, wp.tile.y * Skirmish.size + wp.tile.x))] > 0, mine.contains(where: { sim.entities[$0]?.def.key == "harvester" }) {
            sim.orderHarvest(mine); sim.order(mine.filter { sim.entities[$0]?.def.key != "harvester" }, move: wp); mark(wp, UIColor.cyan)
        } else { sim.order(mine, move: wp, attacking: false); mark(wp, UIColor.green) }
    }

    private func mark(_ p: Vec2, _ c: UIColor) {
        let n = SKShapeNode(circleOfRadius: 8)
        n.strokeColor = c; n.lineWidth = 1.5; n.position = pt(p); n.zPosition = 600
        addChild(n)
        n.run(.sequence([.group([.scale(to: 0.3, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
    }
}

/// The battle with its HUD: moonstone and power on top, what can be made on the right, orders at the bottom.
struct CommandView: View {
    @ObservedObject var session: SkirmishSession

    var body: some View {
        ZStack {
            SpriteView(scene: session.scene, preferredFramesPerSecond: 60).ignoresSafeArea()
            VStack(spacing: 6) {
                top
                if !session.notice.isEmpty {
                    Text(session.notice).font(.system(size: 12, weight: .medium, design: .rounded)).padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier("cmd-notice")
                }
                Spacer()
                bottom
            }.padding(.horizontal, 14).padding(.vertical, 10)
            HStack { Spacer(); sidebar }.padding(.trailing, 10).padding(.vertical, 54)
            if let w = session.winner { ending(w) }
        }
        .foregroundStyle(.white)
    }

    private var top: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(UIColor(hex: session.sim.sides[0].color))).frame(width: 10, height: 10)
                Text(session.sim.sides[0].name).font(.system(size: 13, weight: .bold, design: .rounded))
                Label("\(session.credits)", systemImage: "diamond.fill").font(.system(size: 13, weight: .semibold, design: .rounded)).accessibilityIdentifier("cmd-credits")
                Label("\(session.powerUsed)/\(session.powerMade)", systemImage: "bolt.fill").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(session.powerUsed > session.powerMade ? Color.red : Color.white)
                Text(String(format: "%d:%02d", session.clock / 60, session.clock % 60)).font(.system(size: 12, design: .monospaced)).opacity(0.8)
            }.padding(.horizontal, 14).padding(.vertical, 8).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule())
            Spacer()
            Minimap(session: session).frame(width: 84, height: 84).background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10)).glass(RoundedRectangle(cornerRadius: 10))
            Button { session.onExit() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36) }
                .buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Circle()).glass(Circle()).accessibilityIdentifier("cmd-exit")
        }
    }

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 5) {
                ForEach(Array(SkKind.all.enumerated()), id: \.offset) { p in
                    if p.element.key != "hq" { item(p.offset, p.element) }
                }
            }.padding(6)
        }
        .frame(width: 128).background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14)).glass(RoundedRectangle(cornerRadius: 14))
    }

    private func item(_ i: Int, _ d: SkKind) -> some View {
        let open = session.sim.available(0, i)
        let isMaking = session.making[d.line] == i
        let isReady = d.structure && session.ready == i
        return Button { session.build(i) } label: {
            ZStack(alignment: .leading) {
                if isMaking { GeometryReader { g in Rectangle().fill(Color.green.opacity(0.35)).frame(width: g.size.width * session.progress[d.line]) } }
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name(zh: GameModel.zh)).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                        Text(isReady ? (session.placing ? L("点地图放置", "tap the map") : L("就绪 · 点此放置", "ready · tap")) : "◆\(Int(d.cost))").font(.system(size: 9, design: .rounded)).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    if isMaking && session.waiting[d.line] > 0 && !d.structure { Text("+\(session.waiting[d.line])").font(.system(size: 10, weight: .bold, design: .rounded)) }
                }.padding(.horizontal, 7).padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isReady ? Color.green.opacity(0.45) : Color.white.opacity(d.structure ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(open ? (session.credits >= Int(d.cost) || isMaking || isReady ? 1 : 0.6) : 0.3)
        }
        .buttonStyle(PressStyle()).disabled(!open)
        .accessibilityIdentifier("cmd-build-\(d.key)")
    }

    private var bottom: some View {
        HStack(spacing: 8) {
            pill(session.boxing ? L("拖动框选…", "Drag a box…") : L("框选", "Box"), "rectangle.dashed", on: session.boxing, id: "cmd-box") { session.boxing.toggle() }
            pill(L("全军", "Army"), "shield.lefthalf.filled", id: "cmd-army") { session.selectArmy() }
            if !session.selected.isEmpty {
                pill(L("停止", "Stop"), "stop.fill", id: "cmd-stop") { session.stop() }
                pill(L("采矿", "Mine"), "diamond", id: "cmd-mine") { session.harvest() }
                Text(session.selectionText).font(.system(size: 11, weight: .medium, design: .rounded)).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 7).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier("cmd-selection")
            }
            if session.making[0] != nil || session.ready != nil { pill(L("取消建筑", "Cancel"), "xmark.circle", id: "cmd-cancel") { session.cancel(0) } }
            Spacer()
        }.padding(.trailing, 140)
    }

    private func pill(_ title: String, _ icon: String, on: Bool = false, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 11).padding(.vertical, 8)
                .background(on ? Color.green.opacity(0.4) : Color.clear, in: Capsule())
        }.buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier(id)
    }

    private func ending(_ w: Int) -> some View {
        VStack(spacing: 10) {
            Text(w == 0 ? L("胜利", "Victory") : L("战败", "Defeat")).font(.system(size: 34, weight: .heavy, design: .rounded))
            Text(L("击毁 \(session.sim.sides[0].killed) · 损失 \(session.sim.sides[0].lost) · 采矿 \(Int(session.sim.sides[0].mined))", "Destroyed \(session.sim.sides[0].killed) · lost \(session.sim.sides[0].lost) · mined \(Int(session.sim.sides[0].mined))"))
                .font(.system(size: 13, design: .rounded)).opacity(0.85)
            Button { session.onExit() } label: { Text(L("返回世界", "Back to the world")).font(.system(size: 15, weight: .bold, design: .rounded)).padding(.horizontal, 18).padding(.vertical, 10) }
                .buttonStyle(PressStyle()).background(Color.black.opacity(0.55), in: Capsule()).glass(Capsule()).accessibilityIdentifier("cmd-back")
        }.padding(26).background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 22)).glass(RoundedRectangle(cornerRadius: 22)).accessibilityIdentifier("cmd-ending")
    }
}

/// The whole field at a glance: moonstone, both sides, and the part of it on screen. A tap looks there.
struct Minimap: View {
    @ObservedObject var session: SkirmishSession
    var body: some View {
        Canvas { ctx, size in
            _ = session.tick
            let sim = session.sim
            let k = size.width / CGFloat(Skirmish.size * 16)
            for i in sim.ore.indices where sim.ore[i] > 0 {
                ctx.fill(Path(CGRect(x: CGFloat(i % Skirmish.size) * 16 * k, y: CGFloat(i / Skirmish.size) * 16 * k, width: 1.2, height: 1.2)), with: .color(.cyan.opacity(0.7)))
            }
            for e in sim.entities.values {
                let s: CGFloat = e.def.structure ? 4 : 1.8
                ctx.fill(Path(CGRect(x: CGFloat(e.pos.x) * k - s / 2, y: CGFloat(e.pos.y) * k - s / 2, width: s, height: s)), with: .color(Color(UIColor(hex: sim.sides[e.side].color))))
            }
            let r = session.scene.viewRect
            ctx.stroke(Path(CGRect(x: CGFloat(r.0.x) * k, y: CGFloat(r.0.y) * k, width: CGFloat(r.1.x - r.0.x) * k, height: CGFloat(r.1.y - r.0.y) * k)), with: .color(.white), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let k = Double(Skirmish.size * 16) / 84
            session.scene.look(at: Vec2(Double(g.location.x) * k, Double(g.location.y) * k))
        })
        .accessibilityIdentifier("cmd-minimap")
    }
}
