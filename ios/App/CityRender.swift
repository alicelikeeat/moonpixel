import SpriteKit
import UIKit
import MoonPixelCore

/// Roofs and gate crests: each nation's own roofing and device, drawn over finished buildings. A roof
/// fades when the traveller (or the person being followed) is inside it, so nothing is hidden by it.
extension GameScene {
    func updateRoofs(_ society: Society, _ model: GameModel) {
        var seenRoofs = Set<Int>(), seenCrests = Set<TilePos>()
        if model.depth == 0 {
            let half = (Double(size.width / zoom / 2) + 64) / 16, halfH = (Double(size.height / zoom / 2) + 96) / 16
            let c = viewPos.tile
            let minX = c.x - Int(half), maxX = c.x + Int(half), minY = c.y - Int(halfH), maxY = c.y + Int(halfH)
            let who = model.following ? (society.agents[model.selectedID]?.pos ?? player) : player
            for r in society.roofs(minX: minX, minY: minY, maxX: maxX, maxY: maxY) {
                seenRoofs.insert(r.building)
                let node = roofNodes[r.building] ?? {
                    let n = SKSpriteNode(texture: roofTexture(r.nation, r.w, r.h))
                    n.anchorPoint = CGPoint(x: 0, y: 1)
                    addChild(n)
                    roofNodes[r.building] = n
                    return n
                }()
                // the roof sits on the walls; drawn above the people inside, below the labels
                node.position = CGPoint(x: r.x * 16, y: -(r.y * 16 - 6))
                node.zPosition = 10 + CGFloat(r.y + r.h) * 16 * 0.001 + 0.0009
                let inside = who.x >= Double(r.x * 16) && who.x < Double((r.x + r.w) * 16) && who.y >= Double(r.y * 16) && who.y < Double((r.y + r.h) * 16) + 8
                let want: CGFloat = inside ? 0.18 : 1
                if abs(node.alpha - want) > 0.01 { node.alpha += (want - node.alpha) * 0.25 }
                if node.userData?["nation"] as? Int != r.nation {          // rebuilt by someone else: new roof
                    node.texture = roofTexture(r.nation, r.w, r.h); node.size = node.texture!.size()
                    node.userData = ["nation": r.nation]
                }
            }
            for g in society.gateCrests(minX: minX, minY: minY, maxX: maxX, maxY: maxY) {
                seenCrests.insert(g.pos)
                let node = crestNodes[g.pos] ?? {
                    let n = SKSpriteNode(); n.anchorPoint = CGPoint(x: 0.5, y: 0); addChild(n); crestNodes[g.pos] = n; return n
                }()
                if node.userData?["nation"] as? Int != g.nation {
                    let t = PixelArt.gateCrest(nation: g.nation, color: g.color).texture
                    node.texture = t; node.size = t.size(); node.userData = ["nation": g.nation]
                }
                node.position = CGPoint(x: g.pos.x * 16 + 8, y: -(g.pos.y * 16 - 20))
                node.zPosition = 10 + CGFloat(g.pos.y * 16 + 16) * 0.001 + 0.0009
            }
        }
        for (id, n) in roofNodes where !seenRoofs.contains(id) { n.removeFromParent(); roofNodes[id] = nil }
        for (p, n) in crestNodes where !seenCrests.contains(p) { n.removeFromParent(); crestNodes[p] = nil }
    }

    private func roofTexture(_ nation: Int, _ w: Int, _ h: Int) -> SKTexture {
        let key = "roof\(nation)-\(w)x\(h)"
        if let t = animalTex[key] { return t }
        let t = PixelArt.roof(nation: nation, w: w, h: h).texture
        animalTex[key] = t
        return t
    }

    /// Outside elevators in 2D: the shaft as a frame on every layer it serves, the car filled in on the
    /// layer it is at (and its level written on it while it moves), so a car going up is seen from any floor.
    func updateLifts2D(_ society: Society, _ model: GameModel) {
        var seen = Set<Int>()
        for e in society.realm.lifts where e.stops.contains(where: { $0.depth == model.depth }) || model.depth == 0 {
            seen.insert(e.id)
            let n = liftNodes[e.id] ?? {
                let shaft = SKShapeNode(rect: CGRect(x: 0, y: 0, width: e.w * 16, height: e.d * 16))
                shaft.strokeColor = UIColor(red: 0.7, green: 0.85, blue: 0.95, alpha: 0.9); shaft.lineWidth = 2
                let car = SKSpriteNode(color: UIColor(red: 0.55, green: 0.8, blue: 0.95, alpha: 0.85), size: CGSize(width: e.w * 16 - 6, height: e.d * 16 - 6))
                car.name = "car"; car.anchorPoint = .zero; car.position = CGPoint(x: 3, y: 3)
                let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
                label.name = "level"; label.fontSize = 10; label.fontColor = .white; label.position = CGPoint(x: e.w * 8, y: e.d * 8 - 4)
                shaft.addChild(car); shaft.addChild(label)
                shaft.zPosition = 9; addChild(shaft)
                liftNodes[e.id] = shaft
                return shaft
            }()
            n.position = CGPoint(x: e.x * 16, y: -(e.y + e.d) * 16)
            let here = e.at.map { e.stops[$0].depth == model.depth } ?? false
            (n.childNode(withName: "car") as? SKSpriteNode)?.alpha = here ? 0.95 : 0.25
            let level = e.stops.lastIndex { $0.z <= e.z + 1e-6 }.map { e.stops[$0].level } ?? 0
            (n.childNode(withName: "level") as? SKLabelNode)?.text = e.state == .moving ? "\(level)↕" : "\(level)"
        }
        for (id, n) in liftNodes where !seen.contains(id) { n.removeFromParent(); liftNodes[id] = nil }
    }
}
