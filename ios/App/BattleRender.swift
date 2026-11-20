import SpriteKit
import UIKit
import MoonPixelCore

/// Soldiers of armies in the field: only real members are drawn, as many as the render budget allows
/// (50 / 100 / 200 / 400), front line first; the rest are counted at their own standard. Nodes are
/// pooled. How much of each soldier is drawn depends on the zoom (far: none, mid: the figure, near:
/// figure, horse, flag and the swing of a weapon in the fight). Nothing here feeds back into the battle.
extension GameScene {
    func updateSoldiers(_ society: Society, _ model: GameModel) {
        let detail = BattleDetail.at(zoom: Double(zoom))
        var seen = Set<Int>()
        battleMasses = [:]
        if model.depth == 0 {
            let halfW = Double(size.width / zoom / 2) + 40, halfH = Double(size.height / zoom / 2) + 56
            let limit = detail == .far ? 0 : renderBudget.soldiers
            let v = society.battleView(center: viewPos, halfW: halfW, halfH: halfH, limit: limit, previous: shownSoldiers)
            for m in v.masses { battleMasses[m.legion] = m.hidden }
            let phase = Int(CACurrentMediaTime() * 6.5)
            for a in v.shown {
                seen.insert(a.id)
                let node = soldierNodes[a.id] ?? takeSoldierNode()
                soldierNodes[a.id] = node
                guard let lid = a.legion, let lg = society.realm.legion(lid) else { continue }
                // near the enemy in a fight: the weapon swings (frames come from the real state, not from chance)
                var fighting = false
                if detail == .near {
                    if lg.state == 4, let f = lg.foe.flatMap({ society.realm.legion($0) }) { fighting = a.pos.distance(to: f.pos) < 150 }
                    else if lg.state == 2, (lg.phase ?? 0) >= 1, let t = society.settlements[lg.target] { fighting = a.pos.distance(to: t.center.center) < 220 }
                }
                let held = ["sword", "bow", "sword", "hammer", "basket"][min(4, a.unit ?? 0)]
                let tex = soldierTexture(a.look, a.facing, moving: a.moving, acting: fighting, held: held, female: a.female, phase: phase + a.id)
                node.texture = tex
                node.size = GameScene.personSize(tex)
                let side = abs(a.facing.x) > abs(a.facing.y)
                node.xScale = side && a.facing.x < 0 ? -1 : 1
                node.position = CGPoint(x: a.pos.x, y: -(a.pos.y + 4))
                node.zPosition = 10 + CGFloat(a.pos.y) * 0.001
                let rich = detail == .near
                if let flag = node.childNode(withName: "flag") as? SKSpriteNode {
                    flag.isHidden = !rich
                    if rich { flag.color = nationColor(lg.nation, society) }
                }
                let rides = rich && a.unit == Unit.cavalry
                var horse = node.childNode(withName: "horse") as? SKSpriteNode
                if rides && horse == nil {
                    let h = SKSpriteNode(texture: horseTexture()); h.name = "horse"; h.anchorPoint = CGPoint(x: 0.5, y: 0.1); h.position = CGPoint(x: 0, y: -4); h.zPosition = -0.5
                    node.addChild(h); horse = h
                }
                horse?.isHidden = !rides
            }
        }
        for (id, n) in soldierNodes where !seen.contains(id) { soldierNodes[id] = nil; giveBackSoldierNode(n) }
        shownSoldiers = seen
    }

    private func takeSoldierNode() -> SKSpriteNode {
        if let n = soldierPool.popLast() { n.isHidden = false; addChild(n); return n }
        let n = SKSpriteNode()
        n.anchorPoint = CGPoint(x: 0.5, y: 0.05)
        let flag = SKSpriteNode(color: .white, size: CGSize(width: 5, height: 4))
        flag.name = "flag"; flag.position = CGPoint(x: 9, y: 40); flag.zPosition = 1; flag.isHidden = true
        n.addChild(flag)
        addChild(n)
        return n
    }

    private func giveBackSoldierNode(_ n: SKSpriteNode) {
        n.removeFromParent()
        if soldierPool.count < 420 { soldierPool.append(n) }
    }

    private func soldierTexture(_ look: Look, _ facing: Vec2, moving: Bool, acting: Bool, held: String, female: Bool, phase: Int) -> SKTexture {
        let dir = abs(facing.x) > abs(facing.y) ? "side" : (facing.y < 0 ? "up" : "down")
        let frame = acting ? (phase % 2 == 0 ? 3 : 0) : (moving ? 1 + phase % 2 : 0)
        let key = "s\(look.skin)\(look.hair)\(look.shirt)\(look.pants)\(look.shoes)\(look.face)\(look.style)\(look.model ?? "")\(dir)\(frame)\(held)\(female)"
        if let t = texCache[key] { return t }
        if texCache.count > 4000 { texCache.removeAll() }          // bounded: rebuilt on demand
        let t = PixelArt.character(look, dir: dir, frame: frame, held: held, child: false, female: female).texture
        texCache[key] = t
        return t
    }
}
