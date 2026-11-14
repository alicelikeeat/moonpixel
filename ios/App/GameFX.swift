import SpriteKit
import MoonPixelCore

/// Everything that flashes, flies or falls: weapon and spell effects, weather and animals.
/// All of it is drawn only for what is on screen and is capped by `maxEffects`.
extension GameScene {
    // MARK: building blocks
    func fx(_ node: SKNode, _ actions: [SKAction], on parent: SKNode? = nil) {
        if effects >= effectBudget { return }
        effects += 1
        (parent ?? self).addChild(node)
        node.run(.sequence(actions + [.run { [weak self] in self?.effects -= 1 }, .removeFromParent()]))
    }

    func ring(at p: CGPoint, radius: CGFloat, color: UIColor, width: CGFloat = 2.5, time: Double = 0.5, fill: UIColor = .clear) {
        let r = SKShapeNode(circleOfRadius: radius)
        r.strokeColor = color; r.lineWidth = width; r.fillColor = fill; r.position = p; r.zPosition = 800; r.setScale(0.12)
        fx(r, [.group([.scale(to: 1, duration: time), .fadeOut(withDuration: time)])])
    }

    func sparks(at p: CGPoint, color: UIColor, count: Int = 10, reach: CGFloat = 34, size: CGFloat = 2) {
        for n in 0..<count {
            let s = SKSpriteNode(color: color, size: CGSize(width: size, height: size))
            s.position = p; s.zPosition = 801
            let a = CGFloat(n) * 2 * .pi / CGFloat(count) + CGFloat(n % 3) * 0.3
            let d = reach * (0.6 + CGFloat((n * 7) % 5) / 10)
            fx(s, [.group([.moveBy(x: cos(a) * d, y: sin(a) * d, duration: 0.55), .fadeOut(withDuration: 0.55)])])
        }
    }

    func explosion(at p: CGPoint, radius: CGFloat, color: UIColor) {
        ring(at: p, radius: radius, color: color, width: 3, time: 0.45, fill: color.withAlphaComponent(0.35))
        ring(at: p, radius: radius * 0.6, color: .white, width: 2, time: 0.3)
        sparks(at: p, color: color, count: 12, reach: radius)
    }

    /// A streak that crosses from a to b: a bullet, a bolt or a ball of light.
    func streak(from a: CGPoint, to b: CGPoint, color: UIColor, length: CGFloat, thickness: CGFloat, speed: CGFloat, delay: Double = 0, glow: Bool = false, then: (() -> Void)? = nil) {
        let dx = b.x - a.x, dy = b.y - a.y
        let dist = max(1, hypot(dx, dy))
        let node: SKNode
        if glow {
            let o = SKShapeNode(circleOfRadius: thickness)
            o.fillColor = color; o.strokeColor = .white; o.glowWidth = thickness
            node = o
        } else {
            node = SKSpriteNode(color: color, size: CGSize(width: length, height: thickness))
            node.zRotation = atan2(dy, dx)
        }
        node.position = a; node.zPosition = 805; node.alpha = delay > 0 ? 0 : 1
        var acts: [SKAction] = []
        if delay > 0 { acts += [.wait(forDuration: delay), .fadeIn(withDuration: 0)] }
        acts.append(.move(to: b, duration: Double(dist / speed)))
        if let t = then { acts.append(.run(t)) }
        fx(node, acts)
    }

    func beam(from a: CGPoint, to b: CGPoint, color: UIColor, width: CGFloat) {
        let path = CGMutablePath()
        path.move(to: a); path.addLine(to: b)
        for (w, c, z) in [(width, color, CGFloat(804)), (max(1, width / 3), UIColor.white, CGFloat(805))] {
            let l = SKShapeNode(path: path)
            l.strokeColor = c; l.lineWidth = w; l.glowWidth = w; l.lineCap = .round; l.zPosition = z
            fx(l, [.wait(forDuration: 0.08), .fadeOut(withDuration: 0.3)])
        }
        sparks(at: b, color: color, count: 8, reach: 22)
    }

    /// A jagged bolt from a to b, with a couple of forks.
    func lightning(from a: CGPoint, to b: CGPoint, color: UIColor = UIColor(red: 0.8, green: 0.9, blue: 1, alpha: 1), forks: Int = 2) {
        func jag(_ p0: CGPoint, _ p1: CGPoint, _ seed: Int) -> CGPath {
            let path = CGMutablePath()
            path.move(to: p0)
            let n = max(4, Int(hypot(p1.x - p0.x, p1.y - p0.y) / 18))
            for i in 1..<n {
                let t = CGFloat(i) / CGFloat(n)
                let off = CGFloat(((i * 73 + seed * 31) % 21) - 10)
                path.addLine(to: CGPoint(x: p0.x + (p1.x - p0.x) * t + off, y: p0.y + (p1.y - p0.y) * t + off * 0.4))
            }
            path.addLine(to: p1)
            return path
        }
        let seed = Int(abs(a.x + b.y)) % 97
        let main = SKShapeNode(path: jag(a, b, seed))
        main.strokeColor = .white; main.lineWidth = 2.5; main.glowWidth = 5; main.zPosition = 806
        fx(main, [.wait(forDuration: 0.07), .fadeOut(withDuration: 0.25)])
        let halo = SKShapeNode(path: jag(a, b, seed))
        halo.strokeColor = color; halo.lineWidth = 6; halo.alpha = 0.5; halo.zPosition = 805
        fx(halo, [.fadeOut(withDuration: 0.3)])
        for k in 0..<forks {
            let t = CGFloat(k + 1) / CGFloat(forks + 2)
            let mid = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let end = CGPoint(x: mid.x + CGFloat(k % 2 == 0 ? 40 : -44), y: mid.y - 36)
            let f = SKShapeNode(path: jag(mid, end, seed + k + 3))
            f.strokeColor = color; f.lineWidth = 1.2; f.glowWidth = 2; f.zPosition = 805
            fx(f, [.wait(forDuration: 0.05), .fadeOut(withDuration: 0.2)])
        }
        sparks(at: b, color: color, count: 8, reach: 26)
    }

    func skyFlash(_ alpha: CGFloat = 0.5) {
        let f = SKSpriteNode(color: .white, size: CGSize(width: 4000, height: 4000))
        f.zPosition = 940; f.alpha = alpha
        fx(f, [.fadeOut(withDuration: 0.25)], on: cam)
    }

    /// A column of light from the sky, with rays.
    func pillar(at p: CGPoint, color: UIColor, width: CGFloat) {
        let col = SKSpriteNode(color: color, size: CGSize(width: width, height: 700))
        col.anchorPoint = CGPoint(x: 0.5, y: 0); col.position = p; col.zPosition = 803; col.alpha = 0.85
        fx(col, [.group([.scaleX(to: 0.1, duration: 0.5), .fadeOut(withDuration: 0.5)])])
        let core = SKSpriteNode(color: .white, size: CGSize(width: max(2, width / 3), height: 700))
        core.anchorPoint = CGPoint(x: 0.5, y: 0); core.position = p; core.zPosition = 804
        fx(core, [.fadeOut(withDuration: 0.35)])
        for n in 0..<8 {
            let ray = SKSpriteNode(color: color, size: CGSize(width: 26, height: 1.5))
            ray.anchorPoint = CGPoint(x: 0, y: 0.5); ray.position = p; ray.zRotation = CGFloat(n) * .pi / 4; ray.zPosition = 803
            fx(ray, [.group([.scaleX(to: 2.2, duration: 0.45), .fadeOut(withDuration: 0.45)])])
        }
        ring(at: p, radius: width * 1.2, color: color)
    }

    /// A spoken word of power: the character itself appears, swells and breaks into a shockwave.
    func glyph(_ text: String, at p: CGPoint) {
        let l = SKLabelNode(fontNamed: "PingFangSC-Semibold")
        l.text = text; l.fontSize = 34; l.fontColor = UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 1)
        l.verticalAlignmentMode = .center; l.position = CGPoint(x: p.x, y: p.y + 26); l.zPosition = 830; l.setScale(0.3)
        fx(l, [.scale(to: 1.3, duration: 0.22), .wait(forDuration: 0.25), .group([.scale(to: 2.2, duration: 0.35), .fadeOut(withDuration: 0.35)])])
        ring(at: p, radius: 70, color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), width: 2, time: 0.7)
    }

    func blinkFX(from a: CGPoint, to b: CGPoint) {
        for p in [a, b] {
            ring(at: CGPoint(x: p.x, y: p.y + 14), radius: 22, color: UIColor(red: 0.7, green: 0.6, blue: 1, alpha: 1), time: 0.35)
            sparks(at: CGPoint(x: p.x, y: p.y + 14), color: UIColor(red: 0.8, green: 0.7, blue: 1, alpha: 1), count: 8, reach: 20)
        }
    }

    func firework(at p: CGPoint) {
        let colors: [UIColor] = [.systemPink, .systemYellow, .systemTeal, .systemOrange, .systemGreen, .systemPurple]
        let c = colors[Int(abs(p.x)) % colors.count]
        let start = CGPoint(x: p.x, y: p.y - 90)
        streak(from: start, to: p, color: .white, length: 4, thickness: 1.5, speed: 220) { [weak self] in
            self?.sparks(at: p, color: c, count: 16, reach: 46, size: 2.5)
            self?.ring(at: p, radius: 30, color: c, width: 1.5, time: 0.6)
        }
    }

    // MARK: weapons, spells, divine arts, words
    func castFX(_ r: Society.CastResult) {
        guard let p = r.power else { return }
        let from = CGPoint(x: r.path.first?.x ?? player.x, y: -((r.path.first?.y ?? player.y) - 14))
        let to = pt(r.impact)
        let radius = CGFloat(p.radius)
        let brass = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), fire = UIColor(red: 1, green: 0.5, blue: 0.15, alpha: 1)
        let sky = CGPoint(x: to.x + 70, y: to.y + 420)
        switch p.fx {
        case "bullet":
            let n = p.shape == Power.Shape.burst ? max(1, Int(p.radius)) : 1
            for i in 0..<n {
                let spread = CGFloat((i * 37) % 9) - 4
                streak(from: from, to: CGPoint(x: to.x + spread, y: to.y + spread * 0.6), color: brass, length: 7, thickness: 1.5, speed: 900, delay: Double(i) * 0.05)
            }
            sparks(at: from, color: .white, count: 4, reach: 8)
        case "tracer":
            beam(from: from, to: to, color: brass, width: 1.5)
        case "shell", "rocket":
            streak(from: from, to: to, color: UIColor(white: 0.85, alpha: 1), length: 8, thickness: 3, speed: p.fx == "rocket" ? 420 : 300) { [weak self] in self?.explosion(at: to, radius: radius, color: fire) }
            sparks(at: from, color: UIColor(white: 0.7, alpha: 1), count: 5, reach: 12)
        case "missile":
            streak(from: sky, to: to, color: .white, length: 12, thickness: 3, speed: 700) { [weak self] in self?.explosion(at: to, radius: radius, color: fire) }
        case "barrage":
            for i in 0..<7 {
                let off = CGPoint(x: to.x + CGFloat((i * 53) % 160) - 80, y: to.y + CGFloat((i * 31) % 120) - 60)
                streak(from: CGPoint(x: off.x + 60, y: off.y + 420), to: off, color: UIColor(white: 0.8, alpha: 1), length: 9, thickness: 3, speed: 760, delay: Double(i) * 0.14) { [weak self] in
                    self?.explosion(at: off, radius: 42, color: fire)
                }
            }
        case "rail": beam(from: from, to: to, color: UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 1), width: 4); skyFlash(0.15)
        case "bolt": streak(from: from, to: to, color: UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1), length: 12, thickness: 2.5, speed: 620)
        case "plasma": streak(from: from, to: to, color: UIColor(red: 0.4, green: 1, blue: 0.6, alpha: 1), length: 0, thickness: 3.5, speed: 480, glow: true)
        case "blade":
            let ang = atan2(to.y - from.y, to.x - from.x)
            let arc = SKShapeNode(path: UIBezierPath(arcCenter: .zero, radius: 30, startAngle: ang - 1.1, endAngle: ang + 1.1, clockwise: true).cgPath)
            arc.strokeColor = UIColor(red: 0.5, green: 1, blue: 1, alpha: 1); arc.lineWidth = 4; arc.glowWidth = 6; arc.lineCap = .round; arc.position = from; arc.zPosition = 806
            fx(arc, [.group([.rotate(byAngle: 0.7, duration: 0.2), .fadeOut(withDuration: 0.22)])])
        case "ion": beam(from: from, to: to, color: UIColor(red: 0.4, green: 0.7, blue: 1, alpha: 1), width: 5)
        case "particle": beam(from: from, to: to, color: UIColor(red: 1, green: 0.4, blue: 0.9, alpha: 1), width: 6)
        case "arcane": beam(from: from, to: to, color: UIColor(red: 0.7, green: 0.5, blue: 1, alpha: 1), width: 4)
        case "sun": beam(from: from, to: to, color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1), width: 7); skyFlash(0.2)
        case "gravity", "blackhole":
            let hole = SKShapeNode(circleOfRadius: radius * 0.5)
            hole.fillColor = .black; hole.strokeColor = UIColor(red: 0.6, green: 0.3, blue: 1, alpha: 1); hole.lineWidth = 2; hole.glowWidth = 6; hole.position = to; hole.zPosition = 803; hole.setScale(0.1)
            fx(hole, [.scale(to: 1, duration: 0.3), .wait(forDuration: 0.5), .group([.scale(to: 0.01, duration: 0.3), .fadeOut(withDuration: 0.3)])])
            for n in 0..<14 {
                let a = CGFloat(n) * 2 * .pi / 14
                let s = SKSpriteNode(color: UIColor(red: 0.75, green: 0.6, blue: 1, alpha: 1), size: CGSize(width: 2, height: 2))
                s.position = CGPoint(x: to.x + cos(a) * radius, y: to.y + sin(a) * radius); s.zPosition = 804
                fx(s, [.move(to: to, duration: 0.7)])       // pulled in
            }
        case "orbital":
            pillar(at: to, color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), width: radius); skyFlash(0.35)
            explosion(at: to, radius: radius, color: fire)
        case "antimatter":
            skyFlash(0.8)
            explosion(at: to, radius: radius, color: .white)
            ring(at: to, radius: radius * 1.6, color: UIColor(red: 0.7, green: 0.9, blue: 1, alpha: 1), width: 4, time: 0.9)
        case "orb": streak(from: from, to: to, color: UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1), length: 0, thickness: 3, speed: 420, glow: true) { [weak self] in self?.sparks(at: to, color: UIColor(red: 0.7, green: 0.8, blue: 1, alpha: 1), count: 8, reach: 18) }
        case "fire": streak(from: from, to: to, color: fire, length: 0, thickness: 5, speed: 360, glow: true) { [weak self] in self?.explosion(at: to, radius: radius, color: fire) }
        case "frost":
            ring(at: to, radius: radius, color: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 1), width: 3, time: 0.6, fill: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 0.2))
            sparks(at: to, color: .white, count: 16, reach: radius, size: 3)
        case "meteor":
            streak(from: CGPoint(x: to.x - 220, y: to.y + 460), to: to, color: fire, length: 0, thickness: 8, speed: 640, glow: true) { [weak self] in
                self?.explosion(at: to, radius: radius, color: fire); self?.skyFlash(0.3)
            }
        case "time":
            ring(at: to, radius: radius, color: UIColor(white: 0.9, alpha: 1), width: 2, time: 1.0, fill: UIColor(white: 0.6, alpha: 0.15))
            ring(at: to, radius: radius * 0.5, color: UIColor(white: 1, alpha: 1), width: 1, time: 0.8)
        case "holy":
            let gold = UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 1)
            pillar(at: to, color: gold, width: 18)
            for n in 0..<6 {
                let plus = SKLabelNode(text: "+")
                plus.fontSize = 13; plus.fontColor = UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1); plus.fontName = "AvenirNext-Bold"
                plus.position = CGPoint(x: to.x + CGFloat(n * 9 - 22), y: to.y + 8); plus.zPosition = 820
                fx(plus, [.group([.moveBy(x: 0, y: 30, duration: 0.8), .fadeOut(withDuration: 0.8)])])
            }
        case "pillar": pillar(at: to, color: UIColor(red: 1, green: 0.92, blue: 0.55, alpha: 1), width: max(16, radius)); skyFlash(0.2)
        case "sanctuary", "shield":
            wardRing?.removeFromParent()
            let w = SKShapeNode(circleOfRadius: 22)
            w.strokeColor = p.fx == "shield" ? UIColor(red: 0.4, green: 0.9, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
            w.lineWidth = 2; w.glowWidth = 4; w.fillColor = w.strokeColor.withAlphaComponent(0.12); w.zPosition = 790
            addChild(w); wardRing = w
            w.run(.sequence([.wait(forDuration: Double(p.radius)), .fadeOut(withDuration: 0.4), .removeFromParent()]))
        case "lightning":
            var prev = CGPoint(x: to.x + 30, y: to.y + 420)
            for q in r.path.dropFirst() { let c = CGPoint(x: q.x, y: -(q.y - 14)); lightning(from: prev, to: c); prev = c }
            skyFlash(0.35)
        case "hammer":
            streak(from: from, to: to, color: UIColor(white: 0.85, alpha: 1), length: 9, thickness: 6, speed: 520) { [weak self] in
                self?.lightning(from: CGPoint(x: to.x, y: to.y + 420), to: to, forks: 3)
                self?.explosion(at: to, radius: radius, color: UIColor(red: 0.7, green: 0.85, blue: 1, alpha: 1))
                self?.skyFlash(0.3)
            }
        case "storm":
            for i in 0..<6 {
                let q = CGPoint(x: to.x + CGFloat((i * 71) % 200) - 100, y: to.y + CGFloat((i * 43) % 160) - 80)
                run(.sequence([.wait(forDuration: Double(i) * 0.18), .run { [weak self] in self?.lightning(from: CGPoint(x: q.x + 20, y: q.y + 420), to: q); self?.skyFlash(0.25) }]))
            }
        default:
            if p.fx.hasPrefix("word:") { glyph(String(p.fx.dropFirst(5)), at: to) }
        }
        for h in r.hits.prefix(8) { hitFX(at: CGPoint(x: h.pos.x, y: -(h.pos.y - 20)), damage: h.damage, dead: h.dead) }
        for b in r.beasts.prefix(6) where b.dead { dust(at: pt(b.pos), color: UIColor(red: 0.8, green: 0.5, blue: 0.4, alpha: 1)) }
    }

    func worldFX(_ e: WorldFX) {
        if abs(e.pos.x - player.x) > 900 || abs(e.pos.y - player.y) > 600 { return }      // off screen: nothing to draw
        let p = pt(e.pos)
        switch e.kind {
        case "lightning": lightning(from: CGPoint(x: p.x + 30, y: p.y + 420), to: p, forks: 3); skyFlash(0.4)
        case "firework": firework(at: p)
        case "volley", "charge", "rout", "breach": warFX(e)
        default: break
        }
    }

    // MARK: animals
    func updateAnimals(_ society: Society) {
        if model?.depth ?? 0 > 0 { for n in animalNodes.values { n.removeFromParent() }; animalNodes = [:]; return }
        var seen = Set<Int>()
        let frame = Int(CACurrentMediaTime() * 5)
        for a in society.realm.fauna.animals {
            if abs(a.pos.x - viewPos.x) > 700 / Double(min(1, zoom)) || abs(a.pos.y - viewPos.y) > 460 / Double(min(1, zoom)) { continue }
            seen.insert(a.id)
            let node = animalNodes[a.id] ?? {
                let n = SKSpriteNode()
                n.anchorPoint = CGPoint(x: 0.5, y: 0.1)
                addChild(n)
                animalNodes[a.id] = n
                return n
            }()
            let f = a.moving ? frame % 2 : 0
            let key = "\(a.kind)-\(f)-\(a.tame)"
            let tex = animalTex[key] ?? {
                let t = PixelArt.animal(a.species, frame: f, tame: a.tame).texture
                animalTex[key] = t
                return t
            }()
            node.texture = tex
            node.size = tex.size()
            node.xScale = a.facing < 0 ? -1 : 1
            node.position = CGPoint(x: a.pos.x, y: -(a.pos.y + 4))
            node.zPosition = 10 + CGFloat(a.pos.y) * 0.001
        }
        for (id, n) in animalNodes where !seen.contains(id) { n.removeFromParent(); animalNodes[id] = nil }
    }

    // MARK: weather
    func updateWeather(_ society: Society, _ dt: Double) {
        let w = society.weather(at: player)
        if weatherVeil.parent == nil { weatherVeil.zPosition = 895; weatherVeil.alpha = 0; cam.addChild(weatherVeil) }
        // fog is pale, heat is amber, clouds and rain darken
        weatherVeil.color = w.fall == 3 ? UIColor(white: 0.9, alpha: 1) : (w.fall == 4 ? UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1) : .black)
        let target = w.fall == 3 ? 0.3 : (w.fall == 4 ? 0.08 : CGFloat(w.dim))
        weatherVeil.alpha += (target - weatherVeil.alpha) * CGFloat(min(1, dt * 1.5))
        let want = w.fall == 1 ? 90 : (w.fall == 2 ? 70 : 0)
        if w.fall != weatherFall { for n in weatherNodes { n.removeFromParent() }; weatherNodes = []; weatherFall = w.fall }
        guard let v = view else { return }
        let hw = v.bounds.width / 2 + 20, hh = v.bounds.height / 2 + 20
        while weatherNodes.count < want {
            let i = weatherNodes.count
            let n = w.fall == 1 ? SKSpriteNode(color: UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 0.7), size: CGSize(width: 1, height: 9))
                                : SKSpriteNode(color: .white, size: CGSize(width: 2, height: 2))
            n.zRotation = w.fall == 1 ? -0.25 : 0
            n.zPosition = 896
            n.position = CGPoint(x: CGFloat((i * 97) % Int(hw * 2)) - hw, y: CGFloat((i * 61) % Int(hh * 2)) - hh)
            cam.addChild(n)
            weatherNodes.append(n)
        }
        for (i, n) in weatherNodes.enumerated() {
            if w.fall == 1 { n.position.y -= CGFloat(520 * dt); n.position.x -= CGFloat(130 * dt) }
            else { n.position.y -= CGFloat((40 + Double(i % 5) * 8) * dt); n.position.x += CGFloat(sin(CACurrentMediaTime() * 1.3 + Double(i)) * 14 * dt) }
            if n.position.y < -hh { n.position.y = hh; n.position.x = CGFloat((i * 131 + Int(CACurrentMediaTime() * 60)) % Int(hw * 2)) - hw }
            if n.position.x < -hw { n.position.x = hw }
        }
        if w.thunder {
            thunderT -= dt
            if thunderT <= 0 {
                thunderT = 3.5 + Double(Int(CACurrentMediaTime() * 10) % 50) / 10
                let x = player.x + Double(Int(CACurrentMediaTime() * 100) % 500) - 250, y = player.y + Double(Int(CACurrentMediaTime() * 70) % 260) - 130
                let p = CGPoint(x: x, y: -y)
                lightning(from: CGPoint(x: p.x + 40, y: p.y + 420), to: p, forks: 3)
                skyFlash(0.45)
            }
        }
    }
}
