import Foundation

// Using a lift should be as easy as in a real building. Walk up to the doors and the car is called to you; it
// waits with its doors open while you are at them. Step in (or press Enter) and choose a floor. When it gets
// there the doors open and stay open until you are out; press Exit (or walk out any way) and you are set down on
// the landing, in front of the doors, on that floor. Nobody has to aim at a one-tile doorway any more.

extension Society {
    /// How close to a landing's door (tiles) counts as waiting for the lift.
    public static let liftReach = 2.6

    /// The lift landing the traveller stands at (on the same floor, within reach of its doors), if any.
    public func playerLanding() -> (lift: Elevator, stop: Int)? {
        guard let b = realm.player.body, b.platform == nil, b.pos.x.isFinite, b.pos.y.isFinite else { return nil }
        var best: (Elevator, Int, Double)?
        for e in realm.lifts {
            for (k, s) in e.stops.enumerated() where s.depth == b.depth {
                let d = s.door.center.distance(to: b.pos) / 16
                if d <= Society.liftReach, d < (best?.2 ?? .infinity) { best = (e, k, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// The lift the traveller rides, if any.
    public var playerLift: Elevator? { realm.player.body?.platform.flatMap { lift($0) } }

    /// Every step: call the car to the landing the traveller waits at, and hold its doors open while they are
    /// at them or riding it standing at a landing (doors never shut on someone stepping in or out).
    public func playerLiftAssist() {
        if let e = playerLift {
            // standing at a floor with you inside: the doors wait for you, until you choose another floor
            if e.docked && !e.calls.keys.contains(where: { $0 != e.at }) { e.blocked = true }
            return
        }
        guard let (e, k) = playerLanding() else { return }
        if e.open(at: k) || (e.docked && e.at == k && (e.state == .opening || e.state == .open || e.state == .idle)) {
            // right at the doors: they are held for you (from further off the car is only called)
            if let b = realm.player.body, e.stops[k].door.center.distance(to: b.pos) / 16 <= 1.6 { e.blocked = true }
            if e.state == .idle && e.door < 1 { e.state = .opening }
        } else if e.calls[k] == nil {
            e.call(k, at: world.time)
        }
    }

    public enum LiftMove: Equatable { case entered, exited, called, wait, none }

    /// Step into the lift at the landing one stands at: in at once if its doors are open here, otherwise it
    /// is called (and opens when it comes).
    @discardableResult public func playerEnterLift() -> LiftMove {
        guard var b = realm.player.body, let (e, k) = playerLanding() else { return .none }
        guard e.docked && e.at == k else { e.call(k, at: world.time); return .called }
        if e.door < 0.95 { e.state = .opening; e.blocked = true; return .wait }
        b.x = e.minX + Double(e.w) * 8; b.y = e.minY + Double(e.d) * 8
        b.z = e.z; b.vx = 0; b.vy = 0; b.vz = 0
        b.platform = e.id; b.state = .riding; b.depth = e.stops[k].depth
        realm.player.body = b
        e.playerAboard = true; e.blocked = true
        return .entered
    }

    /// Choose where to go once inside.
    public func playerRideLift(to k: Int) {
        guard let e = playerLift, e.stops.indices.contains(k) else { return }
        e.call(k, at: world.time)
    }

    /// Step out of the lift onto the landing of the floor it stands at: set down in front of its doors (or the
    /// nearest free spot of floor there). Returns where, or nil while it is between floors (then the doors open
    /// at the next stop).
    @discardableResult public func playerExitLift() -> (pos: Vec2, depth: Int)? {
        guard var b = realm.player.body, let e = playerLift else { return nil }
        guard e.docked, let k = e.at else {
            if let t = e.target { e.call(t, at: world.time) }
            return nil
        }
        if e.door < 0.95 { e.state = .opening }
        let s = e.stops[k]
        let w = layer(s.depth)
        // the landing tile, or the nearest free floor beside it
        var spot = s.door
        if w.tile(2, spot.x, spot.y) != 0, let t = content.tile(w.tile(2, spot.x, spot.y)), t.solid {
            spot = w.findFree(near: spot, maxR: 4)
        }
        b.x = spot.center.x; b.y = spot.center.y
        b.z = s.z; b.vx = 0; b.vy = 0; b.vz = 0
        b.platform = nil; b.state = .standing; b.depth = s.depth
        realm.player.body = b
        realm.player.depth = s.depth
        e.playerAboard = false
        return (spot.center, s.depth)
    }
}


extension Figure3D {
    /// A lift landing, one tile, its doorway facing +x (towards the shaft): a lit steel frame as tall as a
    /// storey, a glowing strip over it, the call panel on the post, and a striped mat on the floor, so the
    /// way in and out is plain to see on every floor.
    public static func liftLanding() -> Mesh3D {
        var m = Mesh3D()
        let steel = RGBA(196, 204, 214), dark = RGBA(60, 66, 78), glow = RGBA(120, 255, 170), amber = RGBA(255, 200, 70)
        m.box(0.86, 0, 0.02, 1.0, 2.2, 0.14, steel, faces: .all)            // the posts
        m.box(0.86, 0, 0.86, 1.0, 2.2, 0.98, steel, faces: .all)
        m.box(0.86, 2.2, 0.02, 1.0, 2.45, 0.98, steel, faces: .all)         // the lintel
        m.box(0.84, 2.24, 0.12, 0.86, 2.4, 0.88, glow, faces: .all)          // its lit strip
        m.box(0.78, 1.0, 0.16, 0.86, 1.45, 0.3, dark, faces: .all)           // the call panel
        m.box(0.76, 1.12, 0.2, 0.78, 1.2, 0.26, amber, faces: .all)          //   up
        m.box(0.76, 1.26, 0.2, 0.78, 1.34, 0.26, glow, faces: .all)          //   down
        // the mat, striped at its edge
        m.box(0.08, 0.005, 0.12, 0.84, 0.03, 0.88, dark, faces: .all)
        for k in 0..<4 { let z = 0.14 + Float(k) * 0.19; m.box(0.74, 0.03, z, 0.84, 0.04, z + 0.1, amber, faces: .all) }
        return m
    }
}
