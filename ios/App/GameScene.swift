import SpriteKit
import UIKit
import MoonPixelCore

/// Renders the world with SpriteKit and turns touches into movement, taps and pinches.
final class GameScene: SKScene {
    weak var model: GameModel?
    var player = Vec2.zero
    var facing = Vec2(0, 1)
    var moving = false
    var zoom: CGFloat = 2
    var chunkNodes: [Int64: SKSpriteNode] = [:]
    private var dirty: Set<Int64> = []
    private var agentNodes: [Int: SKSpriteNode] = [:]
    private var texCache: [String: SKTexture] = [:]
    private let cam = SKCameraNode()
    private let playerNode = SKSpriteNode()
    private let playerRing = SKShapeNode(circleOfRadius: 8)
    private let selectRing = SKShapeNode(circleOfRadius: 9)
    private let staffGlow = SKShapeNode(circleOfRadius: 5)
    private let night = SKSpriteNode(color: UIColor(red: 0.04, green: 0.07, blue: 0.25, alpha: 1), size: CGSize(width: 4000, height: 4000))
    private let joyBase = SKShapeNode(circleOfRadius: 46)
    private let joyKnob = SKShapeNode(circleOfRadius: 20)
    private let ghost = SKSpriteNode()
    private var joyTouch: UITouch?
    private var joyOrigin = CGPoint.zero
    private var joyVec = CGVector.zero
    private var tapStart: [ObjectIdentifier: CGPoint] = [:]
    private var lastTime: TimeInterval = 0
    private var hudAcc = 0.0, maintAcc = 0.0, saveAcc = 0.0, walkT = 0.0, attackT = 0.0
    private var hooked = false
    private var badgeNodes: [TilePos: SKNode] = [:]
    private var otherTouches: [UITouch] = []
    private var pinchDist: CGFloat = 0
    private var pinchZoom: CGFloat = 2
    private var pinching = false
    static let maxCharacters = 50

    static let jobTool = ["woodcutter": "axe", "miner": "pick", "farmer": "hoe", "builder": "hammer", "forager": "basket"]

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        if cam.parent == nil {
            addChild(cam)
            camera = cam
            playerRing.strokeColor = UIColor(red: 0.5, green: 0.9, blue: 1, alpha: 0.9); playerRing.lineWidth = 1; playerRing.zPosition = 9
            selectRing.strokeColor = UIColor(red: 1, green: 0.95, blue: 0.4, alpha: 1); selectRing.lineWidth = 1.5; selectRing.zPosition = 9; selectRing.isHidden = true
            staffGlow.fillColor = UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.35); staffGlow.strokeColor = .clear; staffGlow.isHidden = true
            staffGlow.run(.repeatForever(.sequence([.scale(to: 1.5, duration: 0.5), .scale(to: 1.0, duration: 0.5)])))
            playerNode.anchorPoint = CGPoint(x: 0.5, y: 0.05)
            ghost.alpha = 0.6; ghost.anchorPoint = CGPoint(x: 0.5, y: 0); ghost.isHidden = true; ghost.zPosition = 2000
            for n in [playerRing, selectRing, playerNode, staffGlow, ghost] as [SKNode] { addChild(n) }
            night.zPosition = 500; night.alpha = 0
            cam.addChild(night)
            joyBase.fillColor = UIColor(white: 1, alpha: 0.10); joyBase.strokeColor = UIColor(white: 1, alpha: 0.35); joyBase.lineWidth = 1.5; joyBase.zPosition = 900
            joyKnob.fillColor = UIColor(white: 1, alpha: 0.35); joyKnob.strokeColor = .clear; joyKnob.zPosition = 901
            cam.addChild(joyBase); cam.addChild(joyKnob)
        }
        if !hooked, let w = model?.world {
            hooked = true
            w.onChunkChanged.append { [weak self] cx, cy in self?.dirty.insert(MP.chunkKey(cx, cy)) }
        }
    }

    /// After a photo is applied, turn the player towards the camera so the new face is visible.
    func faceCameraOnce() { facing = Vec2(0, 1) }

    func zoomBy(_ d: CGFloat) { zoom = min(5, max(1, zoom + d)) }

    @discardableResult func clearTextureCache() -> Int {
        let n = texCache.count
        texCache.removeAll()
        return n
    }

    private func pt(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: -v.y) }

    // MARK: frame
    override func update(_ currentTime: TimeInterval) {
        guard let model = model, let world = model.world, let society = model.society else { return }
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, currentTime - lastTime)
        lastTime = currentTime
        var sim = dt * GameModel.speeds[model.speedIndex]
        while sim > 0 { let step = min(sim, 1.0); society.tick(step); sim -= step }

        // traveller
        attackT = max(0, attackT - dt)
        let mv = Vec2(Double(joyVec.dx), Double(joyVec.dy))
        moving = mv.length > 0.15
        if moving {
            model.following = false
            let speed = 90.0 * (mv.length > 0.92 ? 1.8 : 1.0)
            let d = (mv.length > 1 ? mv.normalized : mv) * (speed * dt)
            for axis in [Vec2(d.x, 0), Vec2(0, d.y)] {
                let np = player + axis
                let t = np.tile
                if !world.blocked(t.x, t.y) { player = np }
            }
            if attackT <= 0 { facing = mv.normalized }
            walkT += dt * 8
        }
        if model.following, let a = society.agents[model.selectedID] { player = a.pos }
        cam.position = pt(player)
        cam.setScale(1 / zoom)
        night.alpha = CGFloat((1 - world.daylight) * 0.55)
        layoutJoystick()
        updateChunks(world, model)
        updateActors(world, society, model)

        hudAcc += dt
        if hudAcc > 0.25 { hudAcc = 0; model.refreshHUD() }
        maintAcc += dt
        if maintAcc > 2 {
            maintAcc = 0
            world.survey(center: TilePos(Int((player.x / 512).rounded(.down)), Int((player.y / 512).rounded(.down))), count: 16)
            world.maintain()
            model.tickHousekeeping(2)
            if model.showMap { model.rebuildMap() }
        }
        saveAcc += dt
        if saveAcc > 120 { saveAcc = 0; model.save(announce: false) }
    }

    private func layoutJoystick() {
        guard let v = view else { return }
        let w = v.bounds.width, h = v.bounds.height
        // camera children are laid out in screen points around the screen centre
        let base = joyTouch != nil ? CGPoint(x: joyOrigin.x - w / 2, y: h / 2 - joyOrigin.y) : CGPoint(x: -w / 2 + 110, y: -h / 2 + 120)
        joyBase.position = base
        joyKnob.position = CGPoint(x: base.x + joyVec.dx * 32, y: base.y - joyVec.dy * 32)
    }

    private func updateChunks(_ world: OpenWorld, _ model: GameModel) {
        let half = CGSize(width: size.width / zoom / 2, height: size.height / zoom / 2)
        let c0x = Int(((player.x - Double(half.width)) / 512).rounded(.down)) - 1, c1x = Int(((player.x + Double(half.width)) / 512).rounded(.down)) + 1
        let c0y = Int(((player.y - Double(half.height)) / 512).rounded(.down)) - 1, c1y = Int(((player.y + Double(half.height)) / 512).rounded(.down)) + 1
        var made = 0
        for cy in c0y...c1y { for cx in c0x...c1x {
            let k = MP.chunkKey(cx, cy)
            if made >= 1 || (chunkNodes[k] != nil && !dirty.contains(k)) { continue }
            made += 1
            dirty.remove(k)
            let chunk = world.chunk(cx, cy)
            let node = chunkNodes[k] ?? {
                let n = SKSpriteNode()
                n.anchorPoint = CGPoint(x: 0, y: 1)
                n.position = CGPoint(x: cx * 512 - 8, y: -(cy * 512 - 24))
                n.zPosition = -100
                addChild(n)
                chunkNodes[k] = n
                return n
            }()
            let tex = PixelArt.bakeChunk(chunk).texture
            node.texture = tex
            node.size = tex.size()
            node.removeAllChildren()
            for p in chunk.props {
                guard let t = model.assets[String(p.key.dropFirst(6))] else { continue }
                let s = SKSpriteNode(texture: t)
                s.anchorPoint = CGPoint(x: 0.5, y: 0)
                s.position = CGPoint(x: p.x - Double(cx * 512 - 8), y: -(p.y - Double(cy * 512 - 24)))
                s.zPosition = 1
                node.addChild(s)
            }
        } }
        for (k, n) in chunkNodes {
            let cx = MP.keyCX(k), cy = MP.keyCY(k)
            if cx < c0x - 1 || cy < c0y - 1 || cx > c1x + 1 || cy > c1y + 1 { n.removeFromParent(); chunkNodes[k] = nil; dirty.remove(k) }
        }
    }

    private func charTexture(_ look: Look, _ facing: Vec2, moving: Bool, acting: Bool, held: String, child: Bool, female: Bool, phase: Int) -> SKTexture {
        let dir = abs(facing.x) > abs(facing.y) ? "side" : (facing.y < 0 ? "up" : "down")
        let frame = acting ? (phase % 2 == 0 ? 3 : 0) : (moving ? 1 + phase % 2 : 0)
        let key = "\(look.skin)\(look.hair)\(look.shirt)\(look.pants)\(look.shoes)\(look.face)\(look.style)\(dir)\(frame)\(held)\(child)\(female)"
        if let t = texCache[key] { return t }
        let t = PixelArt.character(look, dir: dir, frame: frame, held: held, child: child, female: female).texture
        texCache[key] = t
        return t
    }

    private func updateActors(_ world: OpenWorld, _ society: Society, _ model: GameModel) {
        let now = world.time
        let phase = Int(CACurrentMediaTime() * 6.5)
        let halfW = Double(size.width / zoom / 2) + 40, halfH = Double(size.height / zoom / 2) + 56
        var seen = Set<Int>()
        // at most 50 characters on screen; everyone else becomes a number on their building
        let split = society.crowdSplit(center: player, halfW: halfW, halfH: halfH, limit: GameScene.maxCharacters)
        updateBadges(split.badges)
        for a in split.shown {
            seen.insert(a.id)
            let node = agentNodes[a.id] ?? {
                let n = SKSpriteNode()
                n.anchorPoint = CGPoint(x: 0.5, y: 0.05)
                let bar = SKSpriteNode(color: UIColor(red: 0.5, green: 1, blue: 0.5, alpha: 1), size: CGSize(width: 14, height: 2))
                bar.name = "bar"; bar.anchorPoint = CGPoint(x: 0, y: 0.5); bar.position = CGPoint(x: -7, y: 42); bar.zPosition = 1
                let carry = SKSpriteNode(color: .white, size: CGSize(width: 5, height: 5))
                carry.name = "carry"; carry.position = CGPoint(x: -11, y: 14); carry.zPosition = 1
                n.addChild(bar); n.addChild(carry)
                addChild(n)
                agentNodes[a.id] = n
                return n
            }()
            let st = a.stage(now)
            var look = a.look
            if a.age(now) >= 58 && look.face.isEmpty { look.hair = "#e0e0e8" }
            let working = a.task.map { $0.stage == 1 && ["chop", "mine", "build", "forage", "reap", "sow", "plant"].contains($0.act) } ?? false
            var held = st == "elder" ? "cane" : (GameScene.jobTool[a.job] ?? "")
            if working && a.task?.act == "build" { held = "hammer" }
            let tex: SKTexture
            if let fr = look.anim.flatMap({ model.anims[$0] }), !fr.isEmpty {
                tex = fr[a.sleeping ? 0 : (phase + a.id) % fr.count]      // GIF / video character: its own frames are the animation
            } else {
                tex = charTexture(look, a.facing, moving: a.moving, acting: working, held: held, child: st == "child", female: a.female, phase: phase + a.id)
            }
            node.texture = tex
            node.size = tex.size()
            let side = abs(a.facing.x) > abs(a.facing.y)
            node.xScale = side && a.facing.x < 0 ? -1 : 1
            node.zRotation = a.sleeping ? -.pi / 2 : 0
            node.position = CGPoint(x: a.pos.x, y: -(a.pos.y + 4))
            node.zPosition = 10 + CGFloat(a.pos.y) * 0.001
            if let bar = node.childNode(withName: "bar") as? SKSpriteNode {
                bar.isHidden = !working
                if working, let t = a.task { bar.xScale = CGFloat(min(1, max(0.05, t.t / t.dur))) * node.xScale; bar.position.x = -7 * node.xScale }
            }
            if let carry = node.childNode(withName: "carry") as? SKSpriteNode {
                carry.isHidden = a.carryN <= 0
                carry.color = a.carryKind == "wood" ? UIColor(red: 0.66, green: 0.44, blue: 0.23, alpha: 1) : (a.carryKind == "stone" ? .gray : UIColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1))
            }
        }
        for (id, n) in agentNodes where !seen.contains(id) { n.removeFromParent(); agentNodes[id] = nil }

        // player
        let held = GameModel.weapons[model.weaponIndex]
        let ptex: SKTexture
        if let fr = model.playerLook.anim.flatMap({ model.anims[$0] }), !fr.isEmpty {
            ptex = fr[phase % fr.count]
        } else {
            ptex = charTexture(model.playerLook, facing, moving: moving, acting: attackT > 0.12, held: held, child: false, female: false, phase: phase)
        }
        playerNode.texture = ptex
        playerNode.size = ptex.size()
        let side = abs(facing.x) > abs(facing.y)
        playerNode.xScale = side && facing.x < 0 ? -1 : 1
        playerNode.position = CGPoint(x: player.x, y: -(player.y + 4))
        playerNode.zPosition = 10 + CGFloat(player.y) * 0.001
        playerRing.position = CGPoint(x: player.x, y: -(player.y + 2))
        staffGlow.isHidden = held != "staff"
        staffGlow.position = CGPoint(x: player.x + (side ? (facing.x >= 0 ? 9 : -9) : 9), y: -(player.y - 28))
        staffGlow.zPosition = playerNode.zPosition + 0.0005
        if let a = society.agents[model.selectedID] {
            selectRing.isHidden = false
            selectRing.position = CGPoint(x: a.pos.x, y: -(a.pos.y + 2))
        } else { selectRing.isHidden = true }
        if let id = model.placingAsset, let t = model.assets[id] {
            ghost.isHidden = false; ghost.texture = t; ghost.size = t.size()
            ghost.position = CGPoint(x: player.x + facing.x * 28, y: -(player.y + facing.y * 28))
        } else { ghost.isHidden = true }
    }

    private func updateBadges(_ badges: [TilePos: Int]) {
        for (t, n) in badges {
            let node = badgeNodes[t] ?? {
                let holder = SKNode()
                let bg = SKShapeNode(rectOf: CGSize(width: 22, height: 13), cornerRadius: 6.5)
                bg.fillColor = UIColor(red: 0.08, green: 0.1, blue: 0.18, alpha: 0.85); bg.strokeColor = UIColor(white: 1, alpha: 0.7); bg.lineWidth = 0.75
                let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
                label.fontSize = 9; label.fontColor = .white; label.verticalAlignmentMode = .center; label.name = "n"
                holder.addChild(bg); holder.addChild(label)
                holder.position = CGPoint(x: t.x * 16 + 8, y: -(t.y * 16 - 14))
                holder.zPosition = 700
                addChild(holder)
                badgeNodes[t] = holder
                return holder
            }()
            (node.childNode(withName: "n") as? SKLabelNode)?.text = "\(n)"
        }
        for (t, node) in badgeNodes where badges[t] == nil { node.removeFromParent(); badgeNodes[t] = nil }
    }

    // MARK: weapons and magic (visual)
    func attack(toward target: Vec2) {
        guard attackT <= 0, let model = model else { return }
        var dir = (target - player).normalized
        if dir == .zero { dir = facing }
        facing = dir
        attackT = 0.3
        let origin = CGPoint(x: player.x, y: -(player.y - 14))
        let ang = atan2(-dir.y, dir.x)
        switch GameModel.weapons[model.weaponIndex] {
        case "bow":
            let arrow = SKSpriteNode(color: UIColor(red: 0.66, green: 0.44, blue: 0.23, alpha: 1), size: CGSize(width: 12, height: 1.5))
            arrow.position = origin; arrow.zRotation = ang; arrow.zPosition = 800
            addChild(arrow)
            arrow.run(.sequence([.moveBy(x: dir.x * 270, y: -dir.y * 270, duration: 0.9), .removeFromParent()]))
        case "staff":
            let from = CGPoint(x: origin.x + 9, y: origin.y + 18)
            let bolt = SKShapeNode(circleOfRadius: 4)
            bolt.fillColor = UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 0.9); bolt.strokeColor = .white; bolt.glowWidth = 3
            bolt.position = from; bolt.zPosition = 800
            addChild(bolt)
            let to = pt(target)
            let dist = hypot(to.x - from.x, to.y - from.y)
            bolt.run(.sequence([.move(to: to, duration: min(1.1, Double(dist) / 190)), .run { [weak self] in self?.burst(at: to) }, .removeFromParent()]))
        default:
            let path = UIBezierPath(arcCenter: .zero, radius: 20, startAngle: ang - 0.9, endAngle: ang + 0.9, clockwise: true)
            let slash = SKShapeNode(path: path.cgPath)
            slash.strokeColor = .white; slash.lineWidth = 3; slash.lineCap = .round
            slash.position = origin; slash.zPosition = 800
            addChild(slash)
            slash.run(.sequence([.group([.fadeOut(withDuration: 0.22), .rotate(byAngle: 0.5, duration: 0.22)]), .removeFromParent()]))
        }
    }

    private func burst(at p: CGPoint) {
        let ring = SKShapeNode(circleOfRadius: 26)
        ring.strokeColor = UIColor(red: 0.45, green: 0.9, blue: 1, alpha: 1); ring.lineWidth = 2.5; ring.fillColor = .clear
        ring.position = p; ring.zPosition = 800; ring.setScale(0.15)
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        for n in 0..<8 {
            let s = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 2))
            s.position = p; s.zPosition = 801
            addChild(s)
            let a = CGFloat(n) * .pi / 4
            s.run(.sequence([.group([.moveBy(x: cos(a) * 30, y: sin(a) * 30, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
    }

    // MARK: touches
    private func inJoyZone(_ p: CGPoint) -> Bool {
        guard let v = view else { return false }
        return p.x < v.bounds.width * 0.36 && p.y > v.bounds.height * 0.34 && p.y < v.bounds.height - 70
    }

    private func touchDistance() -> CGFloat {
        guard let v = view, otherTouches.count >= 2 else { return 0 }
        let a = otherTouches[0].location(in: v), b = otherTouches[1].location(in: v)
        return hypot(a.x - b.x, a.y - b.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view else { return }
        for t in touches {
            let p = t.location(in: v)
            if joyTouch == nil && otherTouches.isEmpty && inJoyZone(p) { joyTouch = t; joyOrigin = p; joyVec = .zero }
            else {
                tapStart[ObjectIdentifier(t)] = p
                otherTouches.append(t)
                if otherTouches.count == 2 { pinching = true; pinchDist = max(1, touchDistance()); pinchZoom = zoom }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view else { return }
        if pinching && otherTouches.count >= 2 {
            zoom = min(5, max(1, (pinchZoom * touchDistance() / pinchDist * 2).rounded() / 2))
        }
        guard let jt = joyTouch, touches.contains(jt) else { return }
        let p = jt.location(in: v)
        var d = CGVector(dx: (p.x - joyOrigin.x) / 40, dy: (p.y - joyOrigin.y) / 40)
        let l = hypot(d.dx, d.dy)
        if l > 1 { d = CGVector(dx: d.dx / l, dy: d.dy / l) }
        joyVec = d
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let v = view, let model = model else { return }
        for t in touches {
            if t === joyTouch { joyTouch = nil; joyVec = .zero; continue }
            let wasPinch = pinching
            otherTouches.removeAll { $0 === t }
            if otherTouches.isEmpty { pinching = false }
            guard let start = tapStart.removeValue(forKey: ObjectIdentifier(t)), !wasPinch else { continue }
            let p = t.location(in: v)
            if hypot(p.x - start.x, p.y - start.y) > 14 { continue }
            let sp = t.location(in: self)
            let wp = Vec2(Double(sp.x), Double(-sp.y))
            if let id = model.placingAsset {
                model.world.addProp(key: "asset:" + id, at: wp)
                model.placingAsset = nil
                continue
            }
            if let a = model.society.agent(near: wp + Vec2(0, 14), radius: 18) { model.select(a.id) }
            else if model.selectedID != 0 { model.deselect() }
            else { attack(toward: wp) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t === joyTouch { joyTouch = nil; joyVec = .zero }
            tapStart.removeValue(forKey: ObjectIdentifier(t))
            otherTouches.removeAll { $0 === t }
        }
        if otherTouches.isEmpty { pinching = false }
    }
}
