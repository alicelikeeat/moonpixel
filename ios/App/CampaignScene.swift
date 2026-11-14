import SpriteKit
import MoonPixelCore

/// Scene parts for building previews, the underground and armies in the field.
extension GameScene {
    /// Tiles from a to b along the longer axis (a straight wall, road or floor strip).
    static func line(_ a: TilePos, _ b: TilePos) -> [TilePos] {
        let dx = b.x - a.x, dy = b.y - a.y
        var out: [TilePos] = []
        if abs(dx) >= abs(dy) { for i in 0...abs(dx) { out.append(TilePos(a.x + (dx < 0 ? -i : i), a.y)) } }
        else { for i in 0...abs(dy) { out.append(TilePos(a.x, a.y + (dy < 0 ? -i : i))) } }
        return Array(out.prefix(64))
    }

    func showPreview(_ pre: BuildPreview) {
        clearPreview()
        for c in pre.cells {
            let n = SKSpriteNode(color: c.ok ? UIColor(red: 0.3, green: 1, blue: 0.5, alpha: 1) : UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1), size: CGSize(width: 15, height: 15))
            n.alpha = 0.45
            n.position = CGPoint(x: c.pos.x * 16 + 8, y: -(c.pos.y * 16 + 8))
            n.zPosition = 1900
            addChild(n)
            previewNodes.append(n)
        }
    }

    func clearPreview() { for n in previewNodes { n.removeFromParent() }; previewNodes = [] }

    /// Drop every drawn chunk (and anyone drawn on them) when moving between the surface and the underground.
    func resetLayer() {
        for n in chunkNodes.values { n.removeFromParent() }
        chunkNodes = [:]
        dirty = []
        for n in agentNodes.values { n.removeFromParent() }
        agentNodes = [:]
        for n in animalNodes.values { n.removeFromParent() }
        animalNodes = [:]
        for n in legionNodes.values { n.removeFromParent() }
        legionNodes = [:]
        clearPreview()
    }

    func horseTexture() -> SKTexture {
        if let t = animalTex["mount"] { return t }
        let t = PixelArt.animal(Species.all[Species.index("horse")], frame: 0, tame: false).texture
        animalTex["mount"] = t
        return t
    }

    /// A tile's own picture from the atlas (for engines carried by an army).
    func tileTexture(_ key: String) -> SKTexture {
        if let t = animalTex["tile:" + key] { return t }
        let id = Int(Content.shared.tid(key))
        var b = Bitmap(16, 32)
        b.blit(PixelArt.atlas, sx: (id % 16) * PixelArt.cell + 8, sy: (id / 16) * PixelArt.cell, sw: 16, sh: 32, dx: 0, dy: 0, blend: false)
        let t = b.texture
        animalTex["tile:" + key] = t
        return t
    }

    /// Every army in the field gets a standard, its strength and morale, its engines and, in battle, a front line.
    /// Far away (zoomed out) this is all there is to see of it; close up the soldiers themselves are drawn too.
    func updateLegions(_ society: Society, _ model: GameModel) {
        var seen = Set<Int>()
        if model.depth == 0 {
            for l in society.legionInfos() {
                let reach = 900 / Double(min(1, zoom))
                if abs(l.pos.x - viewPos.x) > reach || abs(l.pos.y - viewPos.y) > reach * 0.7 { continue }
                seen.insert(l.id)
                let node = legionNodes[l.id] ?? makeLegionNode(l)
                legionNodes[l.id] = node
                node.position = CGPoint(x: l.pos.x, y: -l.pos.y)
                node.setScale(1 / max(0.45, min(1, zoom)))
                (node.childNode(withName: "count") as? SKLabelNode)?.text = "\(l.count)"
                (node.childNode(withName: "state") as? SKLabelNode)?.text = l.state
                if let bar = node.childNode(withName: "morale") as? SKSpriteNode { bar.xScale = CGFloat(max(0.05, min(1, l.morale))); bar.color = l.morale < 0.4 ? .red : (l.morale < 0.6 ? .orange : .green) }
                if let eng = node.childNode(withName: "engines") { eng.isHidden = l.engines == 0 || l.phase > 0 }
                // the front: a line facing the enemy army, or the walls being stormed
                let front = node.childNode(withName: "front") as? SKShapeNode
                if let foe = l.foe ?? (l.phase >= 0 ? l.targetPos : nil) {
                    let d = (foe - l.pos).normalized
                    let mid = d * min(40, (foe - l.pos).length / 2)
                    let side = Vec2(-d.y, d.x) * 34
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: mid.x - side.x, y: -(mid.y - side.y)))
                    path.addLine(to: CGPoint(x: mid.x + side.x, y: -(mid.y + side.y)))
                    front?.path = path
                    front?.isHidden = false
                } else { front?.isHidden = true }
                // a convoy on the road
                if let c = l.convoy, let cn = node.childNode(withName: "convoy") {
                    cn.isHidden = false
                    cn.position = CGPoint(x: c.x - l.pos.x, y: -(c.y - l.pos.y))
                } else { node.childNode(withName: "convoy")?.isHidden = true }
            }
        }
        for (id, n) in legionNodes where !seen.contains(id) { n.removeFromParent(); legionNodes[id] = nil }
    }

    func makeLegionNode(_ l: Society.LegionInfo) -> SKNode {
        let color = UIColor(hex: l.color)
        let root = SKNode()
        root.zPosition = 720
        let pole = SKSpriteNode(color: UIColor(red: 0.42, green: 0.29, blue: 0.17, alpha: 1), size: CGSize(width: 2, height: 46))
        pole.anchorPoint = CGPoint(x: 0.5, y: 0); pole.position = CGPoint(x: 0, y: 6)
        let flag = SKSpriteNode(color: color, size: CGSize(width: 20, height: 13))
        flag.anchorPoint = CGPoint(x: 0, y: 1); flag.position = CGPoint(x: 1, y: 52)
        flag.run(.repeatForever(.sequence([.scaleX(to: 0.85, duration: 0.6), .scaleX(to: 1, duration: 0.6)])))
        let emblem = SKSpriteNode(color: color.withAlphaComponent(1).lighter(), size: CGSize(width: 6, height: 5))
        emblem.position = CGPoint(x: 9, y: -6); flag.addChild(emblem)
        let count = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        count.name = "count"; count.fontSize = 11; count.fontColor = .white; count.position = CGPoint(x: 12, y: 30); count.horizontalAlignmentMode = .left
        let state = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        state.name = "state"; state.fontSize = 8; state.fontColor = UIColor(white: 1, alpha: 0.85); state.position = CGPoint(x: 0, y: 60)
        let back = SKSpriteNode(color: UIColor(white: 0, alpha: 0.6), size: CGSize(width: 26, height: 3)); back.position = CGPoint(x: 0, y: 2)
        let morale = SKSpriteNode(color: .green, size: CGSize(width: 26, height: 3))
        morale.name = "morale"; morale.anchorPoint = CGPoint(x: 0, y: 0.5); morale.position = CGPoint(x: -13, y: 2)
        let engines = SKNode(); engines.name = "engines"
        for k in 0..<2 { let e = SKSpriteNode(texture: tileTexture("ballista")); e.position = CGPoint(x: -36 + k * 18, y: -26); engines.addChild(e) }
        let front = SKShapeNode()
        front.name = "front"; front.strokeColor = color; front.lineWidth = 4; front.glowWidth = 3; front.lineCap = .round; front.isHidden = true; front.zPosition = -1
        let convoy = SKSpriteNode(texture: tileTexture("crate"))
        convoy.name = "convoy"; convoy.isHidden = true
        for n in [front, pole, flag, back, morale, count, state, engines, convoy] as [SKNode] { root.addChild(n) }
        addChild(root)
        return root
    }

    /// Volleys, charges, routs and breaches - only where someone can see them.
    func warFX(_ e: WorldFX) {
        if model?.depth ?? 0 > 0 { return }
        let reach = 900 / Double(min(1, zoom))
        if abs(e.pos.x - viewPos.x) > reach && abs(e.to.x - viewPos.x) > reach { return }
        let a = pt(e.pos), b = pt(e.to)
        let color = model?.society.realm.nation(e.nation).map { UIColor(hex: $0.color) } ?? .white
        switch e.kind {
        case "volley":
            // a rain of arrows arcing from one army to the other
            for i in 0..<10 {
                let from = CGPoint(x: a.x + CGFloat((i * 37) % 40) - 20, y: a.y + CGFloat((i * 23) % 24) - 12 + 20)
                let to = CGPoint(x: b.x + CGFloat((i * 53) % 50) - 25, y: b.y + CGFloat((i * 29) % 30) - 15)
                let peak = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 60)
                let arrow = SKSpriteNode(color: UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1), size: CGSize(width: 7, height: 1.2))
                arrow.position = from; arrow.zPosition = 806
                let path = CGMutablePath(); path.move(to: from); path.addQuadCurve(to: to, control: peak)
                fx(arrow, [.wait(forDuration: Double(i) * 0.04), .follow(path, asOffset: false, orientToPath: true, duration: 0.7)])
            }
        case "charge":
            for i in 0..<6 {
                let off = CGFloat(i * 12 - 30)
                streak(from: CGPoint(x: a.x + off, y: a.y), to: CGPoint(x: b.x + off, y: b.y), color: color, length: 14, thickness: 2, speed: 520, delay: Double(i) * 0.05)
            }
            ring(at: b, radius: 40, color: color, width: 2, time: 0.5)
        case "rout":
            sparks(at: a, color: UIColor(white: 0.9, alpha: 1), count: 10, reach: 30)
            let flag = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            flag.text = GameModel.zh ? "溃退" : "ROUT"; flag.fontSize = 14; flag.fontColor = .white; flag.position = CGPoint(x: a.x, y: a.y + 40); flag.zPosition = 830
            fx(flag, [.group([.moveBy(x: (b.x - a.x) * 0.1, y: 20, duration: 1.2), .fadeOut(withDuration: 1.2)])])
        case "breach":
            explosion(at: a, radius: 46, color: UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1))
            sparks(at: a, color: UIColor(white: 0.6, alpha: 1), count: 16, reach: 50, size: 3)
            skyFlash(0.15)
        default: break
        }
    }
}

extension UIColor {
    func lighter() -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r + 0.35), green: min(1, g + 0.35), blue: min(1, b + 0.35), alpha: a)
    }
}
