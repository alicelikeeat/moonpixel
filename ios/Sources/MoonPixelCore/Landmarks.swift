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
        let t0 = world.time
        let r = Int(reach / 512) + 1
        let cx = Int((p.x / 512).rounded(.down)), cy = Int((p.y / 512).rounded(.down))
        var out: [UfoState] = []
        for y in (cy - r)...(cy + r) { for x in (cx - r)...(cx + r) where world.gen.isUfoPort(x, y) {
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
