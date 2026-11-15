import Foundation

// The nanite swarm: a very large number of points that flow from one shape into the next. The
// simulation itself runs on the GPU in the app (Swarm.metal); this file only says where every point
// belongs in each shape, so it has no graphics framework in it and is tested on Linux.
//
// A target is four floats: x, y, z in tile units around the swarm's own origin (y up), and the
// colour packed into the bits of the fourth (0x00BBGGRR), which the shader unpacks.

public enum SwarmShapes {
    /// Tiers of swarm size; the largest is the "million" of the name (2^20).
    public static let sizes = [65_536, 262_144, 524_288, 1_048_576]

    /// A size a device with this much memory can hold comfortably: the swarm needs about 96 bytes a point.
    public static func size(forMemoryGB gb: Double) -> Int {
        gb >= 7.5 ? sizes[3] : (gb >= 5.5 ? sizes[2] : (gb >= 3.5 ? sizes[1] : sizes[0]))
    }

    @inline(__always) public static func pack(_ c: RGBA) -> Float {
        Float(bitPattern: UInt32(c.r) | (UInt32(c.g) << 8) | (UInt32(c.b) << 16))
    }

    public static func unpack(_ w: Float) -> RGBA {
        let v = w.bitPattern
        return RGBA(UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255))
    }

    /// The sheen of the swarm: steel that shifts between teal, violet and amber.
    static func sheen(_ t: Double, _ jitter: Double) -> RGBA {
        let a = RGBA(hex: "#3a4a5a"), b = RGBA(hex: "#59d8ff"), c = RGBA(hex: "#b48cff"), d = RGBA(hex: "#ffb040")
        let u = (t - t.rounded(.down)) * 3
        let base = u < 1 ? b.lerp(c, u) : (u < 2 ? c.lerp(d, u - 1) : d.lerp(b, u - 2))
        return a.lerp(base, 0.35 + 0.45 * jitter)
    }

    /// Points spread evenly over a ball's surface, with a thin shell so it reads as a solid of grains.
    public static func sphere(into out: UnsafeMutableBufferPointer<SIMD4<Float>>, radius: Float = 1.7, lift: Float = 2.2, seed: Int = 1) {
        var rng = RNG(seed: seed)
        let n = out.count
        let golden = Double.pi * (3 - 5.0.squareRoot())
        for i in 0..<n {
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let r = (1 - y * y).squareRoot(), th = golden * Double(i)
            let k = Double(radius) * (0.94 + 0.06 * rng.unit())
            out[i] = SIMD4(Float(cos(th) * r * k), Float(y * k) + lift, Float(sin(th) * r * k), pack(sheen(y * 0.5 + th * 0.01, rng.unit())))
        }
    }

    /// A double helix with rungs, standing on the ground: two strands in two colours, pale rungs between.
    public static func helix(into out: UnsafeMutableBufferPointer<SIMD4<Float>>, radius: Float = 1.1, height: Float = 5.2, turns: Float = 2.5, seed: Int = 2) {
        var rng = RNG(seed: seed)
        let n = out.count
        let s1 = RGBA(hex: "#59d8ff"), s2 = RGBA(hex: "#ff6fa8"), rung = RGBA(hex: "#e8ecf4")
        let rungs = 22
        for i in 0..<n {
            let kind = i % 5                      // two points in five on each strand, one in five on the rungs
            let j: Float = 0.07
            let jx = Float(rng.range(-1, 1)) * j, jy = Float(rng.range(-1, 1)) * j, jz = Float(rng.range(-1, 1)) * j
            if kind < 4 {
                let t = Float(rng.unit())
                let a = t * turns * 2 * .pi + (kind % 2 == 0 ? 0 : .pi)
                let c = (kind % 2 == 0 ? s1 : s2).darkened(0.25 * rng.unit())
                out[i] = SIMD4(cos(a) * radius + jx, 0.3 + t * height + jy, sin(a) * radius + jz, pack(c))
            } else {
                let r = Float(Int(rng.unit() * Double(rungs))) / Float(rungs)
                let a = r * turns * 2 * .pi
                let u = Float(rng.range(-1, 1))
                out[i] = SIMD4(cos(a) * radius * u + jx * 0.5, 0.3 + r * height + jy * 0.5, sin(a) * radius * u + jz * 0.5, pack(rung.darkened(0.3 * abs(Double(u)))))
            }
        }
    }

    /// Points scattered evenly over the surface of a mesh (by triangle area), in the mesh's own colours,
    /// scaled up and stood on the ground. Used to make the swarm stand as a giant of the caster, or as a beast.
    public static func mesh(_ m: Mesh3D, into out: UnsafeMutableBufferPointer<SIMD4<Float>>, scale: Float = 3, seed: Int = 3) {
        let n = out.count
        let tris = m.indices.count / 3
        guard tris > 0, n > 0 else { for i in 0..<n { out[i] = SIMD4(0, 0, 0, pack(.white)) }; return }
        var cum = [Float](repeating: 0, count: tris)
        var total: Float = 0
        for t in 0..<tris {
            let a = m.positions[Int(m.indices[t * 3])], b = m.positions[Int(m.indices[t * 3 + 1])], c = m.positions[Int(m.indices[t * 3 + 2])]
            let u = b - a, v = c - a
            let cr = SIMD3<Float>(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            total += 0.5 * (cr.x * cr.x + cr.y * cr.y + cr.z * cr.z).squareRoot()
            cum[t] = total
        }
        let colors: [RGBA] = (0..<tris).map { Palette3D.color(at: m.uvs[Int(m.indices[$0 * 3])]) }
        var rng = RNG(seed: seed)
        for i in 0..<n {
            let want = Float(rng.unit()) * total
            var lo = 0, hi = tris - 1
            while lo < hi { let mid = (lo + hi) / 2; if cum[mid] < want { lo = mid + 1 } else { hi = mid } }
            let a = m.positions[Int(m.indices[lo * 3])], b = m.positions[Int(m.indices[lo * 3 + 1])], c = m.positions[Int(m.indices[lo * 3 + 2])]
            var r1 = Float(rng.unit()), r2 = Float(rng.unit())
            if r1 + r2 > 1 { r1 = 1 - r1; r2 = 1 - r2 }
            let p = (a + (b - a) * r1 + (c - a) * r2) * scale
            out[i] = SIMD4(p.x, p.y, p.z, pack(colors[lo].darkened(0.18 * rng.unit())))
        }
    }

    /// Where the points start: a flat, slowly turning disc of dust around the caster's feet. The fourth
    /// number is a per-point random value the simulation uses to make every point move a little differently.
    public static func dust(into out: UnsafeMutableBufferPointer<SIMD4<Float>>, radius: Float = 1.4, seed: Int = 4) {
        var rng = RNG(seed: seed)
        for i in 0..<out.count {
            let a = Float(rng.unit()) * 2 * .pi, r = radius * Float(rng.unit().squareRoot())
            out[i] = SIMD4(cos(a) * r, 0.05 + Float(rng.unit()) * 0.5, sin(a) * r, Float(rng.unit()))
        }
    }

    /// The show a cast puts on: (seconds from the start, which shape the swarm is in or moving to).
    /// 0 sphere, 1 the caster as a giant, 2 a wolf, 3 the double helix; after the last time it scatters.
    public static let show: [(at: Float, shape: Int)] = [(0, 0), (2.0, 1), (4.2, 2), (6.2, 3)]
    public static let showLength: Float = 9.4
    public static let scatterAt: Float = 8.4

    /// Which two shapes the swarm is between at a time, and how far along (0 = all the first).
    public static func stage(at t: Float) -> (from: Int, to: Int, blend: Float) {
        var i = 0
        while i + 1 < show.count && t >= show[i + 1].at { i += 1 }
        if i == 0 { return (0, 0, 1) }
        let k = Swift.min(1, (t - show[i].at) / 0.9)
        return (show[i - 1].shape, show[i].shape, k * k * (3 - 2 * k))
    }
}
