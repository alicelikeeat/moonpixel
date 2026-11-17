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
                let body = SKShapeNode(rectOf: CGSize(width: s.length * 16, height: max(8, (s.deckW + 0.2) * 16)), cornerRadius: v.kind.mode == .water ? 6 : 3)
                body.fillColor = GameScene.vehicleColor(v.kind); body.strokeColor = UIColor(white: 0, alpha: 0.6); body.lineWidth = 1
                let nose = SKShapeNode(rectOf: CGSize(width: 4, height: max(4, (s.deckW) * 10)))
                nose.fillColor = UIColor(white: 1, alpha: 0.8); nose.strokeColor = .clear; nose.position = CGPoint(x: s.length * 8 - 3, y: 0)
                body.addChild(nose)
                if v.kind.mode == .air {
                    let wing = SKShapeNode(rectOf: CGSize(width: 18, height: 80)); wing.fillColor = UIColor(white: 0.85, alpha: 1); wing.strokeColor = .clear
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

    static func vehicleColor(_ k: VehicleKind) -> UIColor {
        switch k {
        case .car: return UIColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1)
        case .bus: return UIColor(red: 0.95, green: 0.7, blue: 0.15, alpha: 1)
        case .truck: return UIColor(red: 0.45, green: 0.5, blue: 0.6, alpha: 1)
        case .train: return UIColor(red: 0.3, green: 0.45, blue: 0.75, alpha: 1)
        case .hsr: return UIColor(white: 0.94, alpha: 1)
        case .airliner, .cargoPlane: return UIColor(white: 0.9, alpha: 1)
        case .ferry, .liner: return UIColor(white: 0.97, alpha: 1)
        case .freighter: return UIColor(red: 0.25, green: 0.3, blue: 0.4, alpha: 1)
        }
    }
}
