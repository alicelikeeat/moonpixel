import Foundation

// The sky over the world: the sun crossing from east to west by day, the moon with its phases (a full round of
// them every eight days), three other planets wheeling across the sky at their own pace (a great ringed giant,
// a small red world and a blue one with white clouds), and the stars, turning slowly through the night. All of
// it follows the clock, so it needs no saving and looks the same to everyone at the same hour.

public struct SkyBody: Equatable {
    public enum Kind: String { case sun, moon, ringed, red, blue }
    public let kind: Kind
    /// Unit direction from the eye (x east, y up, z south).
    public let dir: SIMD3<Float>
    /// Radius of its disc, at `Sky.distance`.
    public let size: Float
    /// For the moon: 0 new ... 0.5 full ... 1 new again.
    public let phase: Double
    /// Above the horizon.
    public var up: Bool { dir.y > -0.04 }
}

public enum Sky {
    /// How far off the bodies are drawn (well inside the view's far limit).
    public static let distance: Float = 900
    /// The moon's round of phases, days.
    public static let lunarDays = 8.0
    /// The bodies' paths lean to the south by this much (radians), so they cross the southern sky.
    static let tilt: Float = 0.5

    /// A direction on a body's path, `t` radians along it from rising in the east (0) to setting in the west (π).
    static func path(_ t: Double, lean: Float = 0) -> SIMD3<Float> {
        let a = Float(t)
        let tl = tilt + lean
        return vnorm(SIMD3<Float>(cos(a), sin(a) * cos(tl), sin(a) * sin(tl)))
    }

    /// Where the sun, moon and planets are at a moment of the world's clock.
    public static func bodies(time: Double) -> [SkyBody] {
        let day = time / MP.daySeconds
        let h = (time.truncatingRemainder(dividingBy: MP.daySeconds) + MP.daySeconds).truncatingRemainder(dividingBy: MP.daySeconds) / MP.daySeconds * 24
        // the sun: up at 5:30, highest at noon-ish, down at 20:00
        let sunT = (h - 5.5) / 14.5 * .pi
        // the moon trails the sun by its phase: new (with the sun), full (opposite it)
        let phase = (day / lunarDays).truncatingRemainder(dividingBy: 1)
        let moonT = sunT - phase * 2 * .pi
        // the planets: each round the sky in its own time, starting from its own place
        let ringedT = day * 2 * .pi / 1.12 + 2.1, redT = day * 2 * .pi / 0.93 + 4.4, blueT = day * 2 * .pi / 1.31 + 0.6
        return [
            SkyBody(kind: .sun, dir: path(sunT), size: 34, phase: 0),
            SkyBody(kind: .moon, dir: path(moonT, lean: 0.12), size: 26, phase: phase),
            SkyBody(kind: .ringed, dir: path(ringedT, lean: -0.25), size: 52, phase: 0),
            SkyBody(kind: .red, dir: path(redT, lean: 0.3), size: 13, phase: 0),
            SkyBody(kind: .blue, dir: path(blueT, lean: -0.05), size: 19, phase: 0),
        ]
    }

    /// The moon's phase as one of eight drawings.
    public static func phaseIndex(_ p: Double) -> Int { Int((p * 8).rounded()) % 8 }

    /// The angle the stars have turned by at a moment (radians about the sky's axis).
    public static func starTurn(time: Double) -> Float {
        Float((time / MP.daySeconds).truncatingRemainder(dividingBy: 1) * 2 * .pi)
    }

    /// How brightly the stars show: fully at night, fading through dusk and dawn, gone by day.
    public static func starlight(daylight: Double) -> Double { max(0, min(1, 1 - daylight * 1.8)) }
}

extension Figure3D {
    /// A flat disc in the x-y plane facing the viewer along -z (both faces drawn), radius `r`, nudged `z`.
    static func disc(_ m: inout Mesh3D, r: Float, z: Float, _ c: RGBA, seg: Int = 32) {
        m.frustum(SIMD3(0, 0, z + 0.05), SIMD3(0, 0, z - 0.05), r, r, c, seg: seg)
    }

    /// A filled shape in the x-y plane at depth `z` (a fan from its first point).
    static func shape(_ m: inout Mesh3D, _ pts: [SIMD2<Float>], z: Float, _ c: RGBA) {
        guard pts.count >= 3 else { return }
        for i in 1..<(pts.count - 1) {
            let a = SIMD3(pts[0].x, pts[0].y, z), b = SIMD3(pts[i].x, pts[i].y, z), d = SIMD3(pts[i + 1].x, pts[i + 1].y, z)
            m.tri(a, b, d, c); m.tri(a, d, b, c)
        }
    }

    /// The sun: a blazing disc in a soft glow with a ring of short rays.
    public static func sun(r: Float = 34) -> Mesh3D {
        var m = Mesh3D()
        m.unshaded = true
        disc(&m, r: r * 1.9, z: 0.6, RGBA(255, 238, 190))
        disc(&m, r: r * 1.35, z: 0.3, RGBA(255, 228, 140))
        disc(&m, r: r, z: 0, RGBA(255, 250, 225))
        for i in 0..<16 {
            let a = Float(i) / 16 * 2 * .pi, w: Float = 0.07
            let p0 = SIMD2<Float>(cos(a), sin(a)) * r * 1.45, p1 = SIMD2<Float>(cos(a), sin(a)) * r * (i % 2 == 0 ? 2.3 : 1.95)
            let n = SIMD2<Float>(-sin(a), cos(a)) * r * w
            shape(&m, [p0 - n, p0 + n, p1], z: 0.15, RGBA(255, 214, 110))
        }
        return m
    }

    /// The moon at a phase (0...7: new, waxing crescent, first quarter, waxing gibbous, full, waning ...): its
    /// dark disc, the lit part bounded by the terminator, and grey seas on the lit side.
    public static func moon(phase k: Int, r: Float = 26) -> Mesh3D {
        var m = Mesh3D()
        m.unshaded = true
        disc(&m, r: r, z: 0.2, RGBA(58, 62, 84))
        let p = Double(k) / 8
        let waxing = p <= 0.5
        let kx = Float(cos(2 * .pi * p))                    // the terminator: 1 (new) ... -1 (full)
        let n = 32
        if k != 0 {
            // the lit part, in strips from the limb to the terminator (a crescent is not convex)
            let side: Float = waxing ? 1 : -1
            func row(_ i: Int) -> (SIMD2<Float>, SIMD2<Float>) {
                let y = -r + 2 * r * Float(i) / Float(n), w = max(0, r * r - y * y).squareRoot()
                return (SIMD2(side * kx * w, y), SIMD2(side * w, y))
            }
            for i in 0..<n {
                let (a0, b0) = row(i), (a1, b1) = row(i + 1)
                shape(&m, [a0, b0, b1, a1], z: 0, RGBA(246, 242, 222))
            }
            for (x, y, s) in [(Float(-0.3), Float(0.3), Float(0.22)), (0.25, -0.2, 0.16), (-0.1, -0.45, 0.12), (0.4, 0.4, 0.1)] {
                let c = SIMD2<Float>(x, y) * r
                // only on the lit side
                let w = (r * r - c.y * c.y).squareRoot()
                let edge = (waxing ? 1 : -1) * kx * w
                guard waxing ? c.x > edge : c.x < edge else { continue }
                shape(&m, (0..<10).map { i in let a = Float(i) / 10 * 2 * .pi; return c + SIMD2(cos(a), sin(a)) * r * s }, z: -0.1, RGBA(208, 204, 190))
            }
        }
        return m
    }

    /// The great ringed planet: a banded disc in pale gold and rust, its ring tilted across it (the near half in
    /// front of the disc, the far half behind).
    public static func ringedPlanet(r: Float = 52) -> Mesh3D {
        var m = Mesh3D()
        m.unshaded = true
        disc(&m, r: r, z: 0, RGBA(226, 196, 140))
        let bands: [(Float, Float, RGBA)] = [(0.55, 0.7, RGBA(196, 150, 100)), (0.15, 0.3, RGBA(210, 170, 116)), (-0.25, -0.1, RGBA(180, 130, 90)), (-0.65, -0.5, RGBA(205, 165, 120))]
        for (y0, y1, c) in bands {
            var pts: [SIMD2<Float>] = []
            for i in 0...8 { let y = (y0 + (y1 - y0) * Float(i) / 8) * r; pts.append(SIMD2(-(r * r - y * y).squareRoot() * 0.99, y)) }
            for i in stride(from: 8, through: 0, by: -1) { let y = (y0 + (y1 - y0) * Float(i) / 8) * r; pts.append(SIMD2((r * r - y * y).squareRoot() * 0.99, y)) }
            shape(&m, pts, z: -0.1, c)
        }
        // the ring: an ellipse band, tilted
        let tiltA: Float = 0.32, inner: Float = 1.35, outer: Float = 2.15, flat: Float = 0.24
        let n = 48
        for i in 0..<n {
            let a0 = Float(i) / Float(n) * 2 * .pi, a1 = Float(i + 1) / Float(n) * 2 * .pi
            func at(_ a: Float, _ k: Float) -> SIMD2<Float> {
                let x = cos(a) * r * k, y = sin(a) * r * k * flat
                return SIMD2(x * cos(tiltA) - y * sin(tiltA), x * sin(tiltA) + y * cos(tiltA))
            }
            let front = sin((a0 + a1) / 2) < 0                 // the lower half of the ellipse passes in front
            let c = (i / 3) % 2 == 0 ? RGBA(236, 222, 186) : RGBA(206, 188, 150)
            shape(&m, [at(a0, inner), at(a1, inner), at(a1, outer), at(a0, outer)], z: front ? -0.4 : 0.4, c)
        }
        return m
    }

    /// A small red world with a white polar cap and dark lowlands.
    public static func redPlanet(r: Float = 13) -> Mesh3D {
        var m = Mesh3D()
        m.unshaded = true
        disc(&m, r: r, z: 0, RGBA(206, 92, 62))
        shape(&m, (0...10).map { i in let a = Float(i) / 10 * .pi; return SIMD2(cos(a) * r * 0.55, r * 0.82 + sin(a) * r * 0.16) }, z: -0.1, RGBA(250, 244, 240))
        shape(&m, (0..<10).map { i in let a = Float(i) / 10 * 2 * .pi; return SIMD2(-r * 0.2 + cos(a) * r * 0.32, -r * 0.1 + sin(a) * r * 0.2) }, z: -0.1, RGBA(160, 66, 50))
        return m
    }

    /// A blue world with white cloud swirls.
    public static func bluePlanet(r: Float = 19) -> Mesh3D {
        var m = Mesh3D()
        m.unshaded = true
        disc(&m, r: r, z: 0, RGBA(70, 130, 220))
        for (x, y, w, hgt) in [(Float(-0.2), Float(0.45), Float(0.55), Float(0.1)), (0.2, 0.05, 0.6, 0.09), (-0.1, -0.4, 0.5, 0.1)] {
            shape(&m, (0..<12).map { i in let a = Float(i) / 12 * 2 * .pi; return SIMD2((x + cos(a) * w) * r * 0.95, (y + sin(a) * hgt) * r) }, z: -0.1, RGBA(240, 246, 255))
        }
        shape(&m, (0..<10).map { i in let a = Float(i) / 10 * 2 * .pi; return SIMD2(r * 0.35 + cos(a) * r * 0.22, -r * 0.15 + sin(a) * r * 0.16) }, z: -0.12, RGBA(86, 160, 96))
        return m
    }

    /// A sky body's model, by kind (the moon by phase).
    public static func skyBody(_ b: SkyBody) -> Mesh3D {
        switch b.kind {
        case .sun: return sun(r: b.size)
        case .moon: return moon(phase: Sky.phaseIndex(b.phase), r: b.size)
        case .ringed: return ringedPlanet(r: b.size)
        case .red: return redPlanet(r: b.size)
        case .blue: return bluePlanet(r: b.size)
        }
    }
}
