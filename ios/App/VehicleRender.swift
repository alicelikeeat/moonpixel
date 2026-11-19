import SpriteKit
import UIKit
import MoonPixelCore

/// Vehicles and bridge decks in the flat view, and the traveller's frame while in a vehicle.
extension GameScene {
    /// In a vehicle: the controls go to it (when driving), the traveller walks or sits inside it, the view follows.
    func rideFrame(_ society: Society, _ model: GameModel, wish: Vec2, dt: Double) {
        guard let v = society.playerVehicle else { return }
        if v.playerDriving && v.control == .manual {
            var c = model.driveInput
            // the stick works too: across steers, forward is throttle, back is brake
            if joyVec.dx != 0 || joyVec.dy != 0 {
                c.steer = max(-1, min(1, Double(joyVec.dx)))
                if joyVec.dy < -0.2 { c.throttle = min(1, Double(-joyVec.dy)); c.brake = 0 } else if joyVec.dy > 0.2 { c.brake = min(1, Double(joyVec.dy)); c.throttle = 0 }
            }
            society.steer(c)
        }
        society.moveAboard(dt: dt, wish: v.playerDriving ? .zero : wish, jump: model.jumpQueued)
        model.jumpQueued = false
        if let b = society.realm.player.body { player = b.pos }
        driveAcc += dt
        if driveAcc >= 0.1 { driveAcc = 0; model.refreshDrive() }
    }

    func updateVehicles2D(_ society: Society, _ model: GameModel) {
        guard society.realm.transportBox != nil, model.depth == 0 else {
            for n in vehicleNodes.values { n.removeFromParent() }; vehicleNodes = [:]; return
        }
        var seen = Set<Int>()
        let reach = 900.0 / Double(max(0.3, zoom)) * 1.4
        for v in society.net.vehicles where v.pos.distance(to: viewPos) <= reach {
            seen.insert(v.id)
            let n = vehicleNodes[v.id] ?? {
                let s = v.spec
                if v.kind == .car {
                    // a car is a drawing seen from above: its model and paint, lights, glass and wheels
                    let paint = v.paint ?? "#d84038"
                    let tex = GameScene.carTextures["\(v.carModel.rawValue)\(paint)"] ?? {
                        let b = CarArt.top(v.carModel, paint: paint, len: s.length, wid: max(0.5, s.deckW + 0.2), ppt: 32)
                        let t = b.cgImage.map { SKTexture(image: UIImage(cgImage: $0, scale: 2, orientation: .up)) } ?? SKTexture()
                        t.filteringMode = .linear
                        GameScene.carTextures["\(v.carModel.rawValue)\(paint)"] = t
                        return t
                    }()
                    let car = SKSpriteNode(texture: tex, size: CGSize(width: s.length * 16, height: max(8, (s.deckW + 0.2) * 16)))
                    let shadow = SKShapeNode(rectOf: CGSize(width: s.length * 16, height: max(8, (s.deckW + 0.2) * 16)), cornerRadius: 4)
                    shadow.name = "shadow"; shadow.fillColor = UIColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear; shadow.zPosition = -1
                    car.addChild(shadow)
                    car.zPosition = 8.5
                    addChild(car)
                    vehicleNodes[v.id] = car
                    return car
                }
                let body = SKShapeNode(rectOf: CGSize(width: s.length * 16, height: max(8, (s.deckW + 0.2) * 16)), cornerRadius: v.kind.mode == .water ? 6 : 3)
                body.fillColor = GameScene.vehicleColor(v.kind); body.strokeColor = UIColor(white: 0, alpha: 0.6); body.lineWidth = 1
                let nose = SKShapeNode(rectOf: CGSize(width: 4, height: max(4, (s.deckW) * 10)))
                nose.fillColor = UIColor(white: 1, alpha: 0.8); nose.strokeColor = .clear; nose.position = CGPoint(x: s.length * 8 - 3, y: 0)
                body.addChild(nose)
                if v.kind.mode == .air {
                    let span: CGFloat = v.kind == .widebody ? 116 : (v.kind == .fighter ? 42 : (v.kind == .turboprop ? 64 : 80))
                    let wing = SKShapeNode(rectOf: CGSize(width: v.kind == .fighter ? 26 : 18, height: span)); wing.fillColor = v.kind == .fighter ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.85, alpha: 1); wing.strokeColor = .clear
                    body.addChild(wing)
                }
                let shadow = SKShapeNode(rectOf: CGSize(width: s.length * 16, height: max(8, (s.deckW + 0.2) * 16)), cornerRadius: 3)
                shadow.name = "shadow"; shadow.fillColor = UIColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear; shadow.zPosition = -1
                body.addChild(shadow)
                body.zPosition = 8.5
                addChild(body)
                vehicleNodes[v.id] = body
                return body
            }()
            // planes are drawn above their shadow by their height; everything turns to its heading
            let lift = v.kind.mode == .air ? v.z * 6 : (v.level == 1 ? 6 : 0)
            n.position = CGPoint(x: v.x, y: -v.y + lift)
            n.zRotation = CGFloat(-v.heading)
            if let sh = n.childNode(withName: "shadow") { sh.position = CGPoint(x: 0, y: 0); sh.isHidden = lift == 0; sh.position = CGPoint(x: -lift * sin(v.heading), y: -lift * cos(v.heading)) }
            n.alpha = v.flight == .crashed ? 0.45 : 1
            n.zPosition = v.kind.mode == .air && v.flight == .air ? 950 : (v.level == 1 ? 9.5 : 8.5)
        }
        for (id, n) in vehicleNodes where !seen.contains(id) { n.removeFromParent(); vehicleNodes[id] = nil }
    }

    /// The saucers of the UFO airports in view: a disc seen from above, lifted above its shadow by its height,
    /// a glowing beam under it while it lifts off or lands, its lights turning.
    func updateUfos2D(_ society: Society, _ model: GameModel) {
        guard model.depth == 0 else { for n in ufoNodes.values { n.removeFromParent() }; ufoNodes = [:]; return }
        let reach = 900.0 / Double(max(0.3, zoom)) * 1.4
        var seen = Set<Int>()
        for u in society.ufos(near: viewPos, reach: reach) {
            seen.insert(u.id)
            let n = ufoNodes[u.id] ?? {
                let tex = GameScene.ufoTexture ?? {
                    let t = UfoArt.top(size: 144).cgImage.map { SKTexture(image: UIImage(cgImage: $0, scale: 2, orientation: .up)) } ?? SKTexture()
                    t.filteringMode = .linear
                    GameScene.ufoTexture = t
                    return t
                }()
                let s = SKSpriteNode(texture: tex, size: CGSize(width: 72, height: 72))
                let shadow = SKShapeNode(ellipseOf: CGSize(width: 62, height: 40))
                shadow.name = "shadow"; shadow.fillColor = UIColor(white: 0, alpha: 0.28); shadow.strokeColor = .clear; shadow.zPosition = -1
                s.addChild(shadow)
                let beam = SKShapeNode(ellipseOf: CGSize(width: 54, height: 34))
                beam.name = "beam"; beam.fillColor = UIColor(red: 0.6, green: 1, blue: 1, alpha: 0.35); beam.strokeColor = .clear; beam.zPosition = -0.5
                s.addChild(beam)
                addChild(s)
                ufoNodes[u.id] = s
                return s
            }()
            let lift = u.z * 6
            n.position = CGPoint(x: u.pos.x, y: -u.pos.y + lift)
            n.zRotation = CGFloat(-u.spin * 0.25)
            n.zPosition = u.landed ? 8.6 : 951
            if let sh = n.childNode(withName: "shadow") { sh.position = CGPoint(x: 0, y: -lift); sh.alpha = u.landed ? 0 : 1 }
            if let b = n.childNode(withName: "beam") { b.position = CGPoint(x: 0, y: -lift); b.isHidden = !u.beam }
        }
        for (id, n) in ufoNodes where !seen.contains(id) { n.removeFromParent(); ufoNodes[id] = nil }
    }

    static var ufoTexture: SKTexture?
    static var monumentTextures: [String: SKTexture] = [:]

    /// The capitals' monuments in the flat view, at their real size: each hall, gate and tower (or the statue,
    /// the tower, the pyramid) painted standing up from its foot; the walls, courts and gardens round them are
    /// the world's own tiles.
    func updateMonuments2D(_ society: Society, _ model: GameModel) {
        guard model.depth == 0, viewPos.x.isFinite, viewPos.y.isFinite else {
            for ns in monumentNodes.values { for n in ns { n.removeFromParent() } }; monumentNodes = [:]; return
        }
        let reach = Int(900.0 / Double(max(0.3, zoom)) * 1.4 / 16) + 200
        var seen = Set<Int>()
        for m in society.monuments(near: viewPos.tile, reach: reach) {
            seen.insert(m.id)
            if monumentNodes[m.id] != nil { continue }
            var ns: [SKSpriteNode] = []
            for sp in MonumentArt.sprites(m.kind) {
                let tex = GameScene.monumentTextures[sp.key] ?? {
                    // as sharp as a texture of at most 2048 pixels allows
                    let ppt = min(16.0, 2048.0 / Double(max(sp.w, sp.h)))
                    let t = sp.draw(ppt).cgImage.map { SKTexture(image: UIImage(cgImage: $0, scale: 1, orientation: .up)) } ?? SKTexture()
                    t.filteringMode = .linear
                    GameScene.monumentTextures[sp.key] = t
                    return t
                }()
                let n = SKSpriteNode(texture: tex)
                n.size = CGSize(width: CGFloat(sp.w) * 16, height: CGFloat(sp.h) * 16)
                n.anchorPoint = CGPoint(x: 0.5, y: 0)
                let foot = Double(m.y) + Double(sp.z)
                n.position = CGPoint(x: (Double(m.x) + Double(sp.x)) * 16, y: -foot * 16)
                n.zPosition = 9 + CGFloat(foot) * 1e-5
                addChild(n)
                ns.append(n)
            }
            monumentNodes[m.id] = ns
        }
        for (id, ns) in monumentNodes where !seen.contains(id) { for n in ns { n.removeFromParent() }; monumentNodes[id] = nil }
    }

    /// Car drawings by model and paint, made once.
    static var carTextures: [String: SKTexture] = [:]

    static func vehicleColor(_ k: VehicleKind) -> UIColor {
        switch k {
        case .car: return UIColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1)
        case .bus: return UIColor(red: 0.95, green: 0.7, blue: 0.15, alpha: 1)
        case .truck: return UIColor(red: 0.45, green: 0.5, blue: 0.6, alpha: 1)
        case .train: return UIColor(red: 0.3, green: 0.45, blue: 0.75, alpha: 1)
        case .hsr: return UIColor(white: 0.94, alpha: 1)
        case .airliner, .cargoPlane, .turboprop, .regionalJet, .widebody: return UIColor(white: 0.9, alpha: 1)
        case .fighter: return UIColor(red: 0.46, green: 0.5, blue: 0.55, alpha: 1)
        case .ferry, .liner: return UIColor(white: 0.97, alpha: 1)
        case .freighter: return UIColor(red: 0.25, green: 0.3, blue: 0.4, alpha: 1)
        }
    }
}
