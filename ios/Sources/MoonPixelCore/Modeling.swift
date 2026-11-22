import Foundation

// Vector helpers that work on every platform (the simd module is not on Linux).
@inline(__always) func vdot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
@inline(__always) func vcross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
@inline(__always) func vlen(_ a: SIMD3<Float>) -> Float { vdot(a, a).squareRoot() }
@inline(__always) func vnorm(_ a: SIMD3<Float>) -> SIMD3<Float> { let l = vlen(a); return l > 1e-12 ? a / l : a }

// Modelling beyond boxes: curved surfaces made of quads, each lit by its own normal.
//
// Every shape here is built from quads (a triangle is a quad with its last corner repeated), so the ink
// outline (`inked`) and the palette texture work on them as on boxes. A face's colour is the shape's colour lit
// by a fixed sun (from above, a little to the south-east): faces turned to it are lit, faces turned away go to
// the shadow tone, smoothly in between, or in two flat cel bands in the anime look.
//
// The shapes: cylinders and cones on any axis (wheels, limbs, trunks), ellipsoids (heads, bodies), frustums
// between two points (arms and legs at any angle), rounded-rectangle cross-sections, and lofts that sweep a
// cross-section along a path, changing shape as they go (a car's body from tail to nose, a torso from the
// waist to the shoulders).

extension Mesh3D {
    /// The direction the sun comes from.
    public static let sun = vnorm(SIMD3<Float>(0.35, 0.85, 0.4))

    /// How much darker a face turned to `n` is drawn (0 lit ... 0.5 in shadow).
    public static func shade(for n: SIMD3<Float>) -> Double {
        let l = Swift.max(-1, Swift.min(1, vdot(vnorm(n), sun)))
        return Double((1 - l) * 0.27)
    }

    /// A quad lit by its own normal (from its corners: a, b, c, d counter-clockwise seen from outside).
    /// Each of its two triangles is kept only if it has area (a pinched quad at the pole of a sphere, or a
    /// triangle given as a quad, keeps its one real half); the normal is that of the quad as a whole.
    public mutating func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ color: RGBA) {
        let n1 = vcross(b - a, c - a), n2 = vcross(c - a, d - a)
        let keep1 = vlen(n1) > 2e-6, keep2 = vlen(n2) > 2e-6
        guard keep1 || keep2 else { return }
        let n = vnorm((keep1 ? n1 : .zero) + (keep2 ? n2 : .zero))
        let k1 = keep1 && vdot(n1, n) > 1e-6, k2 = keep2 && vdot(n2, n) > 1e-6
        guard k1 || k2 else { return }
        let sh = unshaded ? 0 : Mesh3D.shade(for: n)
        let t = book.map { $0.uv(color, tone: SwatchBook.tone(shade: sh < 0.06 ? 0 : sh)) }
            ?? Palette3D.uv(cel ? Mesh3D.celColor(color, shade: sh < 0.06 ? 0 : sh) : color.darkened(sh))
        // four corners always (the ink outline works on quads), triangles only where they have area
        let i = UInt32(positions.count)
        positions.append(a); positions.append(b); positions.append(c); positions.append(d)
        if bones != nil { for _ in 0..<4 { bones!.append(bone) } }
        for _ in 0..<4 { normals.append(n); uvs.append(t) }
        if k1 { indices.append(i); indices.append(i + 1); indices.append(i + 2) }
        if k2 { indices.append(i); indices.append(i + 2); indices.append(i + 3) }
    }

    /// A triangle (a quad with its last corner repeated).
    public mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ color: RGBA) { face(a, b, c, c, color) }

    /// An orthonormal pair across an axis.
    static func across(_ axis: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let a = vnorm(axis)
        let helper: SIMD3<Float> = abs(a.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let u = vnorm(vcross(a, helper))
        return (u, vcross(a, u))
    }

    /// A frustum from `p0` (radius `r0`) to `p1` (radius `r1`) with `seg` sides, its ends closed: a cylinder when
    /// the radii are equal, a cone when one is 0. Arms, legs, wheels, trunks, masts.
    public mutating func frustum(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ r0: Float, _ r1: Float, _ color: RGBA, seg asked: Int = 10, caps: Bool = true, capColor: RGBA? = nil) {
        let seg = asked * detail
        let axis = p1 - p0
        guard vlen(axis) > 1e-6 else { return }
        let (u, v) = Mesh3D.across(axis)
        func ring(_ c: SIMD3<Float>, _ r: Float) -> [SIMD3<Float>] {
            (0..<seg).map { i in let a = Float(i) / Float(seg) * 2 * .pi; return c + (u * cos(a) + v * sin(a)) * r }
        }
        let a = ring(p0, r0), b = ring(p1, r1)
        for i in 0..<seg {
            let j = (i + 1) % seg
            face(a[i], a[j], b[j], b[i], color)
        }
        if caps {
            let cc = capColor ?? color
            if r0 > 1e-6 { for i in 0..<seg { tri(p0, a[(i + 1) % seg], a[i], cc) } }
            if r1 > 1e-6 { for i in 0..<seg { tri(p1, b[i], b[(i + 1) % seg], cc) } }
        }
    }

    /// An ellipsoid round `c` with radii `r` (x, y, z): `rings` bands from the bottom to the top, `seg` around.
    /// `from`/`to` (0 bottom ... 1 top) keep only a band of it (a dome is 0.5...1).
    public mutating func ellipsoid(_ c: SIMD3<Float>, _ r: SIMD3<Float>, _ color: RGBA, seg askedSeg: Int = 12, rings askedRings: Int = 8, from: Float = 0, to: Float = 1) {
        let seg = askedSeg * detail, rings = askedRings * detail
        func p(_ i: Int, _ t: Float) -> SIMD3<Float> {
            let lat = (t - 0.5) * .pi, lon = Float(i) / Float(seg) * 2 * .pi
            return c + SIMD3(cos(lat) * cos(lon) * r.x, sin(lat) * r.y, cos(lat) * sin(lon) * r.z)
        }
        for k in 0..<rings {
            let t0 = from + (to - from) * Float(k) / Float(rings), t1 = from + (to - from) * Float(k + 1) / Float(rings)
            for i in 0..<seg {
                let j = (i + 1) % seg
                face(p(i, t0), p(i, t1), p(j, t1), p(j, t0), color)
            }
        }
        // an open band is closed flat at the cut
        if from > 0.001 { let y = c.y + sin((from - 0.5) * .pi) * r.y; for i in 0..<seg { tri(SIMD3(c.x, y, c.z), p(i, from), p((i + 1) % seg, from), color) } }
        if to < 0.999 { let y = c.y + sin((to - 0.5) * .pi) * r.y; for i in 0..<seg { tri(SIMD3(c.x, y, c.z), p((i + 1) % seg, to), p(i, to), color) } }
    }

    /// A rounded rectangle as a cross-section in the y-z plane: `w` wide (z), from `y0` to `y1`, its corners
    /// rounded by `r` (top corners by `rt`), `k` points to each corner; counter-clockwise seen from +x.
    public static func roundedSection(w: Float, y0: Float, y1: Float, r: Float, rt: Float? = nil, k: Int = 3) -> [SIMD2<Float>] {
        let hw = w / 2, rb = Swift.min(r, hw, (y1 - y0) / 2), rtop = Swift.min(rt ?? r, hw, (y1 - y0) / 2)
        var pts: [SIMD2<Float>] = []                       // (y, z)
        func arc(_ cy: Float, _ cz: Float, _ rr: Float, _ a0: Float, _ a1: Float) {
            for i in 0...k { let a = a0 + (a1 - a0) * Float(i) / Float(k); pts.append(SIMD2(cy + sin(a) * rr, cz + cos(a) * rr)) }
        }
        arc(y0 + rb, hw - rb, rb, -.pi / 2, 0)              // bottom right, up the right side
        arc(y1 - rtop, hw - rtop, rtop, 0, .pi / 2)         // top right, along the top
        arc(y1 - rtop, -hw + rtop, rtop, .pi / 2, .pi)      // top left
        arc(y0 + rb, -hw + rb, rb, .pi, 1.5 * .pi)          // bottom left
        return pts
    }

    /// Sweep cross-sections along x: each section is a ring of (y, z) points (all the same count) at its x.
    /// The skin between them is quads; the two ends are closed (`capStart`, `capEnd`).
    public mutating func loft(_ sections: [(x: Float, ring: [SIMD2<Float>])], _ color: RGBA, capStart: Bool = true, capEnd: Bool = true) {
        guard sections.count >= 2, let n = sections.first?.ring.count, n >= 3, sections.allSatisfy({ $0.ring.count == n }) else { return }
        func P(_ s: Int, _ i: Int) -> SIMD3<Float> { let q = sections[s].ring[i % n]; return SIMD3(sections[s].x, q.x, q.y) }
        for s in 0..<(sections.count - 1) {
            for i in 0..<n { face(P(s, i), P(s + 1, i), P(s + 1, i + 1), P(s, i + 1), color) }
        }
        func cap(_ s: Int, _ outward: Bool) {
            let ring = sections[s].ring
            let cy = ring.map { $0.x }.reduce(0, +) / Float(n), cz = ring.map { $0.y }.reduce(0, +) / Float(n)
            let c = SIMD3(sections[s].x, cy, cz)
            for i in 0..<n { if outward { tri(c, P(s, i + 1), P(s, i), color) } else { tri(c, P(s, i), P(s, i + 1), color) } }
        }
        if capStart { cap(0, false) }
        if capEnd { cap(sections.count - 1, true) }
    }

    /// A box with its edges bevelled by `r` (a loft of rounded sections), from (x0, y0, z0) to (x1, y1, z1).
    public mutating func roundedBox(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, r: Float, _ color: RGBA) {
        let w = z1 - z0, zc = (z0 + z1) / 2
        let sec = Mesh3D.roundedSection(w: w, y0: y0, y1: y1, r: r, k: 2 * detail).map { SIMD2($0.x, $0.y + zc) }
        let shrunk = Mesh3D.roundedSection(w: w - 2 * r, y0: y0 + r, y1: y1 - r, r: r * 0.3, k: 2 * detail).map { SIMD2($0.x, $0.y + zc) }
        loft([(x0, shrunk), (x0 + r, sec), (x1 - r, sec), (x1, shrunk)], color)
    }

    /// A wheel at `c`, its axle along z: a tyre, a rim and a hub of `spokes` spokes.
    public mutating func wheel(_ c: SIMD3<Float>, radius r: Float, width w: Float, tyre: RGBA = RGBA(28, 28, 32), rim: RGBA = RGBA(200, 204, 212), spokes: Int = 5) {
        let half = SIMD3<Float>(0, 0, w / 2)
        frustum(c - half, c + half, r, r, tyre, seg: 14, capColor: tyre.lightened(0.08))
        // the rim on the outer face (both sides: a wheel is seen from either)
        for s: Float in [-1, 1] {
            let face = c + half * s * 1.02
            frustum(face, face + SIMD3(0, 0, 0.004 * s), r * 0.66, r * 0.66, rim, seg: 12, capColor: rim)
            for i in 0..<spokes {
                let a = Float(i) / Float(spokes) * 2 * .pi
                let d = SIMD3<Float>(cos(a), sin(a), 0)
                frustum(face + SIMD3(0, 0, 0.006 * s), face + d * r * 0.6 + SIMD3(0, 0, 0.006 * s), r * 0.07, r * 0.05, rim.darkened(0.25), seg: 4, caps: false)
            }
        }
    }
}

extension Bitmap {
    /// Brighten or darken a chunk's ground picture by the relief of its tiles (32 x 32 values), blended smoothly
    /// across each tile so slopes shade softly rather than in squares.
    mutating func shadeRelief(_ r: [Float], tilePx: Int) {
        guard r.count == MP.chunkArea else { return }
        func R(_ x: Int, _ y: Int) -> Float { r[Swift.min(31, Swift.max(0, y)) * 32 + Swift.min(31, Swift.max(0, x))] }
        let tp = Float(tilePx)
        for py in 0..<h { for px in 0..<w {
            let fx = (Float(px) + 0.5) / tp - 0.5, fy = (Float(py) + 0.5) / tp - 0.5
            let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
            let ax = fx - Float(x0), ay = fy - Float(y0)
            let k = (R(x0, y0) * (1 - ax) + R(x0 + 1, y0) * ax) * (1 - ay) + (R(x0, y0 + 1) * (1 - ax) + R(x0 + 1, y0 + 1) * ax) * ay
            if abs(k - 1) < 0.004 { continue }
            let i = (py * w + px) * 4
            for c in 0..<3 { self.px[i + c] = UInt8(Swift.max(0, Swift.min(255, Float(self.px[i + c]) * k))) }
        } }
    }
}
