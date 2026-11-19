import Foundation

// Landmarks of the land: UFO airports with their saucers, and the towns' public swimming pools.
//
// Every UFO airport keeps two saucers. Each flies the same round, set by the clock so it needs no saving:
// it rests on the pad, lifts straight up with its beam on, climbs, circles the airport wide and high, comes
// back over the pad and settles. The two keep half a round apart, so one is nearly always in the air.

public struct UfoState: Equatable {
    public var id: Int                  // stable: the airport's chunk and which saucer
    public var pos: Vec2                // in the world's units (16 a tile)
    public var z: Double                // height above the pad, tiles
    public var spin: Double             // radians, the saucer turning on itself
    public var beam: Bool               // its light beam down (lifting off and landing)
    public var landed: Bool
}

extension Society {
    /// The round of a saucer: seconds.
    public static let ufoRound = 180.0

    /// The saucers of the UFO airports within `reach` (world units) of `p`, where they are now.
    public func ufos(near p: Vec2, reach: Double) -> [UfoState] {
        // (before the view has a place, e.g. the first frame of a new world, there is nothing to show)
        guard p.x.isFinite, p.y.isFinite, reach.isFinite, reach > 0, abs(p.x) < 1e12, abs(p.y) < 1e12 else { return [] }
        let t0 = world.time
        let r = Int(reach / 512) + 1
        let cx = Int((p.x / 512).rounded(.down)), cy = Int((p.y / 512).rounded(.down))
        var out: [UfoState] = []
        for y in (cy - r)...(cy + r) { for x in (cx - r)...(cx + r) where ufoPortOpen(x, y) {
            let pad = Vec2(Double(x * 32) + 16, Double(y * 32) + 14) * 16
            for k in 0..<2 {
                let s = Society.ufoState(pad: pad, time: t0, saucer: k, seed: Int(MP.h2(world.seed, x, y) % 1000))
                var u = s
                u.id = (x & 0xffff) << 16 | (y & 0x7fff) << 1 | k
                if u.pos.distance(to: p) <= reach + 600 { out.append(u) }
            }
        } }
        return out
    }

    /// Where a saucer is at a time: rest (0-40% of the round), rise (40-50%), circle (50-85%), descend (85-100%).
    public static func ufoState(pad: Vec2, time: Double, saucer k: Int, seed: Int) -> UfoState {
        let round = ufoRound
        let phase = ((time + Double(seed) + Double(k) * round * 0.5).truncatingRemainder(dividingBy: round) + round).truncatingRemainder(dividingBy: round) / round
        let home = pad + Vec2(k == 0 ? -4 : 4, 0) * 16              // the two rest side by side on the pad
        let top = 14.0, wide = 30.0 * 16
        var pos = home, z = 0.0, beam = false
        switch phase {
        case ..<0.4: z = 0
        case ..<0.5:
            let u = (phase - 0.4) / 0.1
            z = top * u * u * (3 - 2 * u); beam = true
        case ..<0.85:
            let u = (phase - 0.5) / 0.35
            let a = u * 2 * .pi + (k == 0 ? 0 : .pi)
            // out from the pad and round a wide circle, then back to it
            let out = sin(u * .pi)
            pos = home + Vec2(cos(a), sin(a)) * (wide * out)
            z = top + 4 * sin(u * 4 * .pi)
        default:
            let u = (phase - 0.85) / 0.15
            z = top * (1 - u * u * (3 - 2 * u)); beam = true
        }
        return UfoState(id: 0, pos: pos, z: z, spin: time * (z > 0.1 ? 3.0 : 0.4), beam: beam, landed: z < 0.05)
    }

    // MARK: riding a saucer, and jumping out

    /// A saucer at rest on its pad within `reach` tiles of a place, if any.
    public func landedUfo(near p: Vec2, reach: Double = 4) -> UfoState? {
        ufos(near: p, reach: reach * 16 + 64).filter { $0.landed && $0.pos.distance(to: p) <= reach * 16 }.min { $0.pos.distance(to: p) < $1.pos.distance(to: p) }
    }

    /// The saucer the traveller rides, where it is now.
    public var ridingUfo: UfoState? {
        guard let id = realm.player.ufo, let b = realm.player.body else { return nil }
        return ufos(near: b.pos, reach: 4000).first { $0.id == id }
    }

    /// Board a saucer resting on its pad beside the traveller: it takes them up on its round.
    @discardableResult public func boardUfo() -> Bool {
        guard realm.player.ufo == nil, var b = realm.player.body, b.depth == 0, b.platform == nil, let u = landedUfo(near: b.pos) else { return false }
        realm.player.ufo = u.id
        b.x = u.pos.x; b.y = u.pos.y; b.vx = 0; b.vy = 0; b.vz = 0; b.state = .standing; b.chute = nil
        realm.player.body = b
        ufoRideStep()
        return true
    }

    /// Every frame while aboard: the traveller stands on the saucer's top, wherever it is.
    public func ufoRideStep() {
        guard var b = realm.player.body else { return }
        guard let u = ridingUfo else { realm.player.ufo = nil; b.state = .falling; b.chute = true; realm.player.body = b; return }
        let ground = WorldGround(self).floor(0, u.pos.tile) ?? b.z
        b.x = u.pos.x; b.y = u.pos.y; b.z = ground + u.z + 1.1
        b.vx = 0; b.vy = 0; b.vz = 0; b.state = .standing; b.depth = 0
        realm.player.body = b
        realm.player.depth = 0
    }

    /// Jump out of the saucer with a parachute: down slowly, steering, and no harm on landing.
    @discardableResult public func jumpFromUfo() -> Bool {
        guard realm.player.ufo != nil, var b = realm.player.body else { return false }
        realm.player.ufo = nil
        b.state = .falling; b.vz = 0; b.chute = true; b.sinceGround = 1
        realm.player.body = b
        return true
    }

    /// Step off a saucer resting on its pad.
    @discardableResult public func leaveUfo() -> Bool {
        guard realm.player.ufo != nil, var b = realm.player.body, let u = ridingUfo, u.landed else { return false }
        realm.player.ufo = nil
        let spot = world.findFree(near: TilePos(u.pos.tile.x, u.pos.tile.y + 3), maxR: 4)
        b.x = spot.center.x; b.y = spot.center.y
        b.z = WorldGround(self).floor(0, spot) ?? b.z
        b.state = .standing
        realm.player.body = b
        return true
    }

    // MARK: a public swimming pool

    /// A public swimming pool: a fenced deck of stone, a big lane pool (lane ropes as lily-pad dots, a diving
    /// board at the deep end), a children's paddling pool, sun loungers under umbrellas (tables), changing rooms
    /// with a door, lamps, and trees round the edge.
    func raisePool(_ b: CityBuilding, _ d: District) {
        let fence = content.tid("fence"), gate = content.tid("fence_gate"), deck = content.tid("stone_floor")
        let water = content.tid("shallow_water"), wall = content.tid("wall_brick"), glass = content.tid("wall_glass")
        let door = content.tid("door_wood"), wood = content.tid("wood_floor")
        for y in 0..<b.d { for x in 0..<b.w {
            let t = TilePos(b.x + x, b.y + y)
            world.setTile(1, t.x, t.y, 0); world.setTile(3, t.x, t.y, 0)
            world.setTile(0, t.x, t.y, deck)
            let edge = x == 0 || y == 0 || x == b.w - 1 || y == b.d - 1
            if edge { world.setTile(2, t.x, t.y, t == b.entrance ? gate : fence); continue }
            world.setTile(2, t.x, t.y, 0)
            // the lane pool: x 2...w-3, y 2...6
            if x >= 2 && x <= b.w - 3 && y >= 2 && y <= 6 {
                world.setTile(0, t.x, t.y, water)
                if y == 3 || y == 5 { if x % 2 == 0 { world.setTile(3, t.x, t.y, content.tid("lily_pad")) } }   // lane ropes
            }
            // the paddling pool: x 2...5, y 8...9
            if x >= 2 && x <= 5 && y >= 8 && y <= 9 { world.setTile(0, t.x, t.y, water) }
            // the changing rooms: x w-6...w-2, y 8...b.d-2
            if x >= b.w - 6 && x <= b.w - 2 && y >= 8 && y <= b.d - 2 {
                world.setTile(0, t.x, t.y, wood)
                let e = x == b.w - 6 || x == b.w - 2 || y == 8 || y == b.d - 2
                world.setTile(2, t.x, t.y, e ? (x == b.w - 4 && y == 8 ? door : (y == 8 && x % 2 == 1 ? glass : wall)) : 0)
            }
        } }
        // the diving board at the deep end, loungers and umbrellas, lamps, trees
        world.setTile(2, b.x + b.w - 2, b.y + 4, content.tid("plate"))
        for x in stride(from: 7, to: b.w - 7, by: 2) { world.setTile(2, b.x + x, b.y + 8, content.tid("table")) }
        world.setTile(2, b.x + 7, b.y + 10, content.tid("chair")); world.setTile(2, b.x + 9, b.y + 10, content.tid("chair"))
        for (x, y) in [(1, 1), (b.w - 2, 1), (1, b.d - 2)] { world.setTile(2, b.x + x, b.y + y, content.tid("lantern_post")) }
        world.setTile(2, b.x + 6, b.y + b.d - 2, content.tid("tree_oak"))
        world.setTile(3, b.x + 1, b.y + 7, content.tid("flower_blue")); world.setTile(3, b.x + 1, b.y + 9, content.tid("flower_red"))
        keepClear(b.front); keepClear(b.entrance)
    }
}

// MARK: - drawing the saucers

extension Figure3D {
    /// A flying saucer, centred on the origin, the underside's lowest point at y = 0: a wide lens-shaped hull of
    /// polished metal, a glass dome on top, a ring of coloured lights round the rim, three landing legs, and a
    /// glowing core underneath.
    public static func ufo() -> Mesh3D {
        var m = Mesh3D()
        let metal = RGBA(196, 204, 216), dark = RGBA(120, 128, 142), glass = RGBA(120, 220, 236), glow = RGBA(110, 240, 255)
        let R: Float = 2.2
        // the hull: the underside a flat cone up to the rim, the top a shallower one up to the dome's base
        m.frustum(SIMD3(0, 0.25, 0), SIMD3(0, 0.62, 0), R * 0.42, R, dark, seg: 24, caps: false)
        m.frustum(SIMD3(0, 0.62, 0), SIMD3(0, 0.7, 0), R, R, metal.darkened(0.08), seg: 24, caps: false)       // the rim band
        m.frustum(SIMD3(0, 0.7, 0), SIMD3(0, 1.05, 0), R, R * 0.4, metal, seg: 24, caps: false)
        m.ellipsoid(SIMD3(0, 1.05, 0), SIMD3(R * 0.4, 0.62, R * 0.4), glass, seg: 18, rings: 6, from: 0.5, to: 1)   // the dome
        m.ellipsoid(SIMD3(0, 0.25, 0), SIMD3(R * 0.42, 0.18, R * 0.42), glow, seg: 16, rings: 4, from: 0, to: 0.5)  // the core below
        // lights round the rim, in turn cyan, magenta and amber
        let lights = [RGBA(110, 240, 255), RGBA(255, 110, 220), RGBA(255, 210, 90)]
        for i in 0..<12 {
            let a = Float(i) / 12 * 2 * .pi
            m.ellipsoid(SIMD3(cos(a) * R * 1.005, 0.66, sin(a) * R * 1.005), SIMD3(0.09, 0.07, 0.09), lights[i % 3], seg: 6, rings: 3)
        }
        // landing legs with pads
        for i in 0..<3 {
            let a = Float(i) / 3 * 2 * .pi + 0.5
            let top = SIMD3(cos(a) * R * 0.5, 0.45, sin(a) * R * 0.5), foot = SIMD3(cos(a) * R * 0.75, 0.04, sin(a) * R * 0.75)
            m.frustum(top, foot, 0.06, 0.05, dark, seg: 6)
            m.frustum(foot - SIMD3(0, 0.04, 0), foot + SIMD3(0, 0.02, 0), 0.16, 0.16, dark, seg: 8)
        }
        return m
    }

    /// A parachute canopy, its lines meeting below at the harness (the origin is at the canopy's middle).
    public static func parachute() -> Mesh3D {
        var m = Mesh3D()
        let colors = [RGBA(240, 80, 70), RGBA(250, 246, 236)]
        let n = 12, R: Float = 1.7
        for i in 0..<n {
            let a0 = Float(i) / Float(n) * 2 * .pi, a1 = Float(i + 1) / Float(n) * 2 * .pi
            let p0 = SIMD3<Float>(cos(a0) * R, -0.35, sin(a0) * R), p1 = SIMD3<Float>(cos(a1) * R, -0.35, sin(a1) * R)
            let q0 = SIMD3<Float>(cos(a0) * R * 0.55, 0.3, sin(a0) * R * 0.55), q1 = SIMD3<Float>(cos(a1) * R * 0.55, 0.3, sin(a1) * R * 0.55)
            let c = colors[i % 2]
            m.face(p0, p1, q1, q0, c); m.face(p0, q0, q1, p1, c.darkened(0.2))
            m.tri(q0, q1, SIMD3(0, 0.45, 0), c); m.tri(q0, SIMD3(0, 0.45, 0), q1, c.darkened(0.2))
            if i % 3 == 0 { m.frustum(p0, SIMD3(0, -1.5, 0), 0.02, 0.02, RGBA(60, 60, 60), seg: 3) }
        }
        return m
    }

    /// The light beam under a saucer: a pale cone from its belly down `height` tiles.
    public static func ufoBeam(height: Float) -> Mesh3D {
        var m = Mesh3D()
        m.frustum(SIMD3(0, height, 0), SIMD3(0, 0, 0), 0.6, 2.0, RGBA(170, 250, 255), seg: 16, caps: false)
        return m
    }
}

public enum UfoArt {
    /// A saucer seen from above (`size` pixels across): the metal disc with its rim of lights and the dome.
    public static func top(size: Int = 72, spin: Double = 0) -> Bitmap {
        var c = Canvas(size, size, scale: 1)
        let s = Double(size), cx = s / 2
        c.inkColor = RGBA(60, 66, 80)
        c.ellipse(cx, cx, s * 0.47, s * 0.47, RGBA(186, 194, 208), ink: 1.2, shade: Shade(shadow: 0.2, light: 0.25))
        c.ellipse(cx, cx, s * 0.36, s * 0.36, RGBA(206, 214, 226), ink: 0.6)
        let lights = [RGBA(110, 240, 255), RGBA(255, 110, 220), RGBA(255, 210, 90)]
        c.inkColor = nil
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi + spin
            c.ellipse(cx + cos(a) * s * 0.42, cx + sin(a) * s * 0.42, s * 0.03, s * 0.03, lights[i % 3])
        }
        c.inkColor = RGBA(40, 120, 140)
        c.ellipse(cx, cx, s * 0.17, s * 0.17, RGBA(130, 226, 240), ink: 0.8, shade: Shade(shadow: 0.25, light: 0.4))
        c.inkColor = nil
        c.ellipse(cx - s * 0.05, cx - s * 0.05, s * 0.05, s * 0.035, RGBA(255, 255, 255, 220))
        return c.image()
    }
}
