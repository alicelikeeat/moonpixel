import Foundation

// What an army takes to war, by the age of its nation (CivTech eras), and where each machine is in its column.
//
// * Before industry an army marches as it always did: swords, bows, horse and siege engines.
// * Industry (era 2): troop carriers (APCs) and Humvees ride with it.
// * From era 3: main battle tanks lead the column, rocket launcher trucks follow at the back, strike fighters
//   fly cover overhead.
// * From era 4: drones scout and strike low over the column; the age of AI sends more of everything.
// * Each machine is drawn where the army is (the column faces the way it marches: tanks in front, Humvees on
//   the flanks, APCs in the middle, rockets at the back; fighters circle wide and high, drones hover low and
//   close). Nothing here is saved: the kit follows from the army and its nation, its places from the clock.
// * Sizes are life-sized (a tile is 2 m): a tank 8 m long, a Humvee 4.6 m, an APC 7 m, a rocket truck 7 m,
//   a fighter 19 m shortened like every aircraft, a drone with a 3 m span.

public enum WarKit {
    public static let order = ["tank", "humvee", "apc", "rocket", "fighter", "drone"]
    public static let names: [String: (String, String)] = [
        "tank": ("Main battle tank", "主战坦克"), "humvee": ("Humvee", "悍马车"), "apc": ("Troop carrier", "运兵车"),
        "rocket": ("Rocket launcher", "火箭炮车"), "fighter": ("Strike fighter", "战斗机"), "drone": ("Attack drone", "攻击无人机"),
    ]
    public static func name(_ k: String, zh: Bool) -> String { names[k].map { zh ? $0.1 : $0.0 } ?? k }

    /// The machines an army of `members` soldiers takes, in an age.
    public static func kit(era: Int, members: Int) -> [(kind: String, count: Int)] {
        let n = max(1, members / 8)
        var out: [(String, Int)] = []
        guard era >= 2 else { return [] }
        out.append(("apc", n))
        out.append(("humvee", max(1, n / 2 + (era >= 3 ? 1 : 0))))
        if era >= 3 {
            out.append(("tank", max(1, n * (era >= 4 ? 3 : 2) / 2)))
            out.append(("rocket", max(1, n / 2)))
            out.append(("fighter", era >= 5 ? 3 : 2))
        }
        if era >= 4 { out.append(("drone", era >= 5 ? 6 : 3)) }
        return out.map { (kind: $0.0, count: min(12, $0.1)) }
    }
}

/// One of an army's machines where it is now.
public struct WarMachine: Equatable {
    public var id: Int
    public var kind: String
    public var pos: Vec2                   // world units (16 a tile)
    public var heading: Double             // radians, the way its nose points
    public var z: Double                   // tiles above the ground (aircraft)
    public var color: String               // its nation's
    public var moving: Bool
}

extension Society {
    /// The age an army's nation is in (the regional layer's eras; a nation it does not know is taken as modern).
    public func era(ofNation n: Int) -> Int {
        guard let c = realm.civBox, c.polities[n] != nil else { return 3 }
        return c.era(n)
    }

    /// What an army takes to war.
    public func legionKit(_ lg: Legion) -> [(kind: String, count: Int)] {
        WarKit.kit(era: era(ofNation: lg.nation), members: lg.members.count)
    }

    /// The machines of the armies on campaign near a place, each where it is in its column now.
    public func warMachines(center: Vec2, reach: Double) -> [WarMachine] {
        var out: [WarMachine] = []
        let t = world.time
        for lg in realm.legions where lg.state != 0 && lg.pos.distance(to: center) <= reach + 1200 {
            let kit = legionKit(lg)
            guard !kit.isEmpty else { continue }
            // the way the column faces: along its route, or towards its target or its foe
            var fwd = Vec2(0, 1)
            if let r = lg.route, !r.isEmpty { let to = r[min(lg.routeI ?? 0, r.count - 1)] - lg.pos; if to.length > 1 { fwd = to.normalized } }
            if lg.state == 2, let s = settlements[lg.target] { let to = s.center.center - lg.pos; if to.length > 1 { fwd = to.normalized } }
            if lg.state == 4, let f = lg.foe.flatMap({ realm.legion($0) }) { let to = f.pos - lg.pos; if to.length > 1 { fwd = to.normalized } }
            let side = Vec2(-fwd.y, fwd.x)
            let heading = atan2(fwd.y, fwd.x)
            let col = realm.nation(lg.nation)?.color ?? "#808080"
            let moving = lg.state == 1 || lg.state == 3
            for (ki, k) in kit.enumerated() {
                for i in 0..<k.count {
                    let id = lg.id &* 1000 &+ ki &* 50 &+ i
                    let lane = Double(i % 2 == 0 ? 1 : -1) * Double(i / 2 + 1)
                    var p = lg.pos, z = 0.0, h = heading
                    // a little sway as they drive, so a column at a standstill still looks alive
                    let sway = moving ? sin(t * 0.8 + Double(id)) * 3 : 0
                    switch k.kind {
                    case "tank":   p = lg.pos + fwd * (90 + Double(i / 2) * 70) + side * (lane * 38 + sway)
                    case "humvee": p = lg.pos + fwd * (40 - Double(i / 2) * 90) + side * (lane > 0 ? 130 : -130) + side * sway
                    case "apc":    p = lg.pos - fwd * (40 + Double(i / 2) * 75) + side * (lane * 30 + sway)
                    case "rocket": p = lg.pos - fwd * (220 + Double(i / 2) * 80) + side * (lane * 34)
                    case "fighter":
                        // a wide circle over the army, high up, the fighters spaced round it
                        let a = t * 0.35 + Double(i) * 2 * .pi / Double(k.count)
                        p = lg.pos + Vec2(cos(a), sin(a)) * 900
                        h = a + .pi / 2; z = 70
                    default:
                        // drones: small loops ahead of the column, low
                        let a = t * 1.1 + Double(i) * 2 * .pi / Double(k.count)
                        p = lg.pos + fwd * 260 + Vec2(cos(a), sin(a)) * 160
                        h = a + .pi / 2; z = 10
                    }
                    if p.distance(to: center) <= reach + 200 {
                        out.append(WarMachine(id: id, kind: k.kind, pos: p, heading: h, z: z, color: col, moving: moving || k.kind == "fighter" || k.kind == "drone"))
                    }
                }
            }
        }
        return out
    }
}

// MARK: - drawing them

extension Figure3D {
    /// A war machine, centred on the origin, its nose along +x, its wheels or tracks on y = 0; in its nation's
    /// colour on a stripe (a fighter is the aircraft drawn for the air force).
    public static func warMachine(_ kind: String, color: String) -> Mesh3D {
        var m = Mesh3D(detail: detail)
        let nat = RGBA(hex: color)
        let olive = RGBA(96, 104, 70), sand = RGBA(150, 138, 100), dark = RGBA(40, 42, 40), glass = RGBA(120, 160, 190), steel = RGBA(110, 116, 120)
        func wheels(_ xs: [Float], _ hw: Float, r: Float) { for x in xs { for z in [-hw, hw] { m.frustum(SIMD3(x, r, z - 0.06), SIMD3(x, r, z + 0.06), r, r, dark, seg: 8) } } }
        switch kind {
        case "tank":
            // 8 m long, 3.7 m wide, 2.4 m tall: tracks, a sloped hull, a turret and a long gun
            for z: Float in [-0.78, 0.78] {
                m.box(-2.0, 0, z - 0.17, 2.0, 0.42, z + 0.17, dark, faces: .all)
                for i in 0..<6 { let x = -1.7 + Float(i) * 0.68; m.frustum(SIMD3(x, 0.2, z - 0.18), SIMD3(x, 0.2, z + 0.18), 0.2, 0.2, steel, seg: 8) }
            }
            m.loft([(x: -2.0, ring: Mesh3D.roundedSection(w: 1.6, y0: 0.35, y1: 0.78, r: 0.08)),
                    (x: 1.6, ring: Mesh3D.roundedSection(w: 1.6, y0: 0.35, y1: 0.78, r: 0.08)),
                    (x: 2.1, ring: Mesh3D.roundedSection(w: 1.5, y0: 0.38, y1: 0.55, r: 0.06))], olive)
            m.loft([(x: -1.0, ring: Mesh3D.roundedSection(w: 1.25, y0: 0.78, y1: 1.18, r: 0.1)),
                    (x: 0.4, ring: Mesh3D.roundedSection(w: 1.25, y0: 0.78, y1: 1.18, r: 0.1)),
                    (x: 0.85, ring: Mesh3D.roundedSection(w: 0.9, y0: 0.82, y1: 1.08, r: 0.08))], olive.lightened(0.05))
            m.frustum(SIMD3(0.8, 0.98, 0), SIMD3(3.4, 1.0, 0), 0.09, 0.07, dark, seg: 8)
            m.box(-1.0, 1.18, -0.2, -0.6, 1.3, 0.2, dark, faces: .all)                       // the commander's hatch
            m.box(-1.02, 0.86, -0.64, -0.6, 1.0, 0.64, nat, faces: .all)                     // the nation's band
        case "humvee":
            // 4.6 m long, 2.2 m wide, 1.9 m tall: a wide low body, a cab with glass, a gun on the roof
            m.loft([(x: -1.15, ring: Mesh3D.roundedSection(w: 1.08, y0: 0.22, y1: 0.62, r: 0.06)),
                    (x: 0.55, ring: Mesh3D.roundedSection(w: 1.08, y0: 0.22, y1: 0.62, r: 0.06)),
                    (x: 1.15, ring: Mesh3D.roundedSection(w: 1.0, y0: 0.24, y1: 0.5, r: 0.06))], sand)
            m.box(-0.75, 0.62, -0.5, 0.45, 0.95, 0.5, sand.darkened(0.05), faces: .all)
            m.box(0.3, 0.64, -0.46, 0.47, 0.9, 0.46, glass, faces: .all)
            m.frustum(SIMD3(-0.2, 1.0, 0), SIMD3(0.5, 1.02, 0), 0.03, 0.03, dark, seg: 6)
            m.box(-0.3, 0.95, -0.12, -0.05, 1.08, 0.12, dark, faces: .all)
            m.box(-1.16, 0.4, -0.55, -1.0, 0.55, 0.55, nat, faces: .all)
            wheels([-0.78, 0.78], 0.54, r: 0.22)
        case "apc":
            // 7 m long, 2.9 m wide, 2.4 m tall: eight wheels, a boat-shaped hull, a small turret, hatches
            m.loft([(x: -1.75, ring: Mesh3D.roundedSection(w: 1.4, y0: 0.3, y1: 1.15, r: 0.1)),
                    (x: 1.2, ring: Mesh3D.roundedSection(w: 1.4, y0: 0.3, y1: 1.15, r: 0.1)),
                    (x: 1.75, ring: Mesh3D.roundedSection(w: 1.2, y0: 0.45, y1: 0.85, r: 0.08))], olive)
            m.box(-0.2, 1.15, -0.3, 0.4, 1.35, 0.3, olive.darkened(0.1), faces: .all)
            m.frustum(SIMD3(0.4, 1.25, 0), SIMD3(1.3, 1.25, 0), 0.04, 0.04, dark, seg: 6)
            m.box(-1.6, 1.15, -0.3, -1.1, 1.2, 0.3, dark, faces: .all)
            m.box(-1.76, 0.55, -0.71, -1.5, 0.8, 0.71, nat, faces: .all)
            wheels([-1.3, -0.45, 0.45, 1.3], 0.7, r: 0.3)
        case "rocket":
            // 7 m long: a cab and a launcher of twelve tubes raised to fire
            m.box(1.0, 0.3, -0.6, 1.75, 1.2, 0.6, sand, faces: .all)
            m.box(1.5, 0.75, -0.55, 1.76, 1.1, 0.55, glass, faces: .all)
            m.box(-1.75, 0.3, -0.62, 1.0, 0.6, 0.62, sand.darkened(0.08), faces: .all)
            // the launcher: a block of tubes tilted up towards the front
            let tilt: Float = 0.45
            for row in 0..<3 { for col in 0..<4 {
                let y0 = 0.75 + Float(row) * 0.2, z = -0.4 + Float(col) * 0.27
                m.frustum(SIMD3(-1.6, y0, z), SIMD3(0.6, y0 + 2.2 * sin(tilt), z), 0.1, 0.1, steel, seg: 6)
            } }
            m.box(-1.0, 0.6, -0.15, -0.7, 0.85, 0.15, dark, faces: .all)
            m.box(1.0, 1.2, -0.6, 1.4, 1.26, 0.6, nat, faces: .all)
            wheels([-1.3, -0.5, 1.3], 0.62, r: 0.28)
        case "fighter":
            return vehicle(.fighter, livery: nat)
        default:
            // a drone with a 3 m span: a slim body, straight wings, a V tail, a pusher propeller, a sensor ball
            m.loft([(x: -0.7, ring: Mesh3D.roundedSection(w: 0.14, y0: 0.0, y1: 0.14, r: 0.06)),
                    (x: 0.5, ring: Mesh3D.roundedSection(w: 0.2, y0: -0.02, y1: 0.18, r: 0.08)),
                    (x: 0.75, ring: Mesh3D.roundedSection(w: 0.1, y0: 0.03, y1: 0.12, r: 0.04))], RGBA(200, 204, 210))
            m.box(-0.05, 0.12, -0.75, 0.2, 0.15, 0.75, RGBA(200, 204, 210), faces: .all)
            for z: Float in [-0.22, 0.22] { m.box(-0.7, 0.12, z - 0.02, -0.5, 0.35, z + 0.02, nat, faces: .all) }
            m.frustum(SIMD3(-0.75, 0.07, 0), SIMD3(-0.78, 0.07, 0), 0.25, 0.25, dark, seg: 8)
            m.ellipsoid(SIMD3(0.55, -0.04, 0), SIMD3(0.07, 0.07, 0.07), dark, seg: 8, rings: 4)
        }
        return m
    }
}

extension AnimeArt {
    /// A war machine seen from above, its nose to the right, `ppt` pixels a tile (2D map).
    public static func warMachineTop(_ kind: String, color: String, ppt: Int = 32) -> Bitmap {
        let len: Double = ["tank": 4.2, "humvee": 2.3, "apc": 3.5, "rocket": 3.5, "fighter": 5, "drone": 1.6][kind] ?? 2
        let wid: Double = ["tank": 1.9, "humvee": 1.1, "apc": 1.45, "rocket": 1.25, "fighter": 3.2, "drone": 1.6][kind] ?? 1
        let W = Int((len * Double(ppt)).rounded(.up)) + 4, H = Int((wid * Double(ppt)).rounded(.up)) + 4
        var c = Canvas(W, H)
        let k = Double(ppt), cx = Double(W) / 2, cy = Double(H) / 2
        func X(_ v: Double) -> Double { cx + v * k }
        func Y(_ v: Double) -> Double { cy + v * k }
        let nat = RGBA(hex: color)
        let olive = RGBA(96, 104, 70), sand = RGBA(150, 138, 100), dark = RGBA(40, 42, 40), glass = RGBA(120, 160, 190)
        switch kind {
        case "tank":
            for s in [-1.0, 1.0] { c.rect(X(-2.05), Y(s * 0.78 - 0.18), 4.1 * k, 0.36 * k, dark, ink: 0.8, radius: 2) }
            c.rect(X(-1.9), Y(-0.65), 3.9 * k, 1.3 * k, olive, ink: 0.9, radius: 3)
            c.ellipse(X(-0.3), Y(0), 0.62 * k, 0.55 * k, olive.lightened(0.08), ink: 0.9)
            c.rect(X(0.3), Y(-0.06), 1.8 * k, 0.12 * k, dark, ink: 0.5)
            c.rect(X(-1.0), Y(-0.6), 0.25 * k, 1.2 * k, nat)
        case "humvee":
            c.rect(X(-1.15), Y(-0.55), 2.3 * k, 1.1 * k, sand, ink: 0.9, radius: 3)
            c.rect(X(0.2), Y(-0.45), 0.3 * k, 0.9 * k, glass)
            c.ellipse(X(-0.2), Y(0), 0.16 * k, 0.16 * k, dark)
            c.rect(X(-1.15), Y(-0.55), 0.18 * k, 1.1 * k, nat)
        case "apc":
            c.rect(X(-1.75), Y(-0.72), 3.5 * k, 1.44 * k, olive, ink: 0.9, radius: 4)
            c.rect(X(-0.2), Y(-0.3), 0.6 * k, 0.6 * k, olive.darkened(0.12), ink: 0.6, radius: 2)
            c.rect(X(0.4), Y(-0.03), 0.9 * k, 0.06 * k, dark)
            c.rect(X(-1.75), Y(-0.72), 0.25 * k, 1.44 * k, nat)
        case "rocket":
            c.rect(X(1.0), Y(-0.6), 0.75 * k, 1.2 * k, sand, ink: 0.8, radius: 2)
            c.rect(X(1.45), Y(-0.5), 0.25 * k, 1.0 * k, glass)
            c.rect(X(-1.75), Y(-0.62), 2.7 * k, 1.24 * k, sand.darkened(0.1), ink: 0.8, radius: 2)
            for col in 0..<4 { for r in 0..<3 { c.ellipse(X(-1.4 + Double(r) * 0.7), Y(-0.4 + Double(col) * 0.27), 0.1 * k, 0.1 * k, dark) } }
            c.rect(X(0.85), Y(-0.6), 0.12 * k, 1.2 * k, nat)
        case "fighter":
            let grey = RGBA(118, 126, 136)
            c.poly([(X(2.5), Y(0)), (X(0.4), Y(-0.25)), (X(-0.6), Y(-1.6)), (X(-1.2), Y(-1.6)), (X(-1.0), Y(-0.3)), (X(-2.4), Y(-0.7)), (X(-2.5), Y(0)),
                    (X(-2.4), Y(0.7)), (X(-1.0), Y(0.3)), (X(-1.2), Y(1.6)), (X(-0.6), Y(1.6)), (X(0.4), Y(0.25))], grey, ink: 0.9)
            c.ellipse(X(1.3), Y(0), 0.35 * k, 0.1 * k, glass)
            for s in [-1.0, 1.0] { c.rect(X(-2.3), Y(s * 0.3 - 0.04), 0.5 * k, 0.08 * k, nat) }
        default:
            let body = RGBA(200, 204, 210)
            c.rect(X(-0.7), Y(-0.08), 1.45 * k, 0.16 * k, body, ink: 0.7, radius: 2)
            c.rect(X(-0.05), Y(-0.75), 0.25 * k, 1.5 * k, body, ink: 0.7, radius: 1)
            for s in [-1.0, 1.0] { c.rect(X(-0.7), Y(s * 0.22 - 0.03), 0.2 * k, 0.06 * k, nat) }
            c.ellipse(X(-0.78), Y(0), 0.05 * k, 0.25 * k, dark)
        }
        return c.image()
    }
}
