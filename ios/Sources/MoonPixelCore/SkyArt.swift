import Foundation

// The sky storey drawn from above (2D): the islands float.
//
// * The ground far below shows through the open air, washed pale blue by the distance;
// * clouds drift between, white with soft blue-grey undersides;
// * under the coast of an island its underside hangs: a grassy lip, earth, then darker rock tapering into
//   points (a few tiles of it, longer in some places than others), so the island reads as a lump of land in
//   the air, not a floor.

public struct SkyBackdrop {
    /// The ground layer of the chunk to the north (its underside reaches into this one).
    public var north: [UInt8]?
    public var cx: Int, cy: Int, seed: Int
    public init(north: [UInt8]?, cx: Int, cy: Int, seed: Int) { self.north = north; self.cx = cx; self.cy = cy; self.seed = seed }

    static let haze = RGBA(178, 212, 244)
    static let lip = RGBA(112, 182, 88), earth = RGBA(150, 110, 74), earthDeep = RGBA(118, 84, 58)
    static let rock = RGBA(106, 98, 120), rockDeep = RGBA(74, 68, 90), crystal = RGBA(170, 214, 255)

    @inline(__always) static func blend(_ img: inout Bitmap, _ x: Int, _ y: Int, _ c: RGBA, _ a: Double) {
        guard x >= 0, y >= 0, x < img.w, y < img.h else { return }
        let d = img.get(x, y), t = max(0, min(1, a))
        img.set(x, y, RGBA(UInt8(Double(d.r) * (1 - t) + Double(c.r) * t), UInt8(Double(d.g) * (1 - t) + Double(c.g) * t),
                           UInt8(Double(d.b) * (1 - t) + Double(c.b) * t), 255))
    }

    /// How many tiles the underside hangs below the coast at world column x (2 ... 6, rising and falling).
    func hang(_ x: Int) -> Int {
        let v = sin(Double(x) * 0.61 + Double(seed % 97)) * 0.5 + sin(Double(x) * 0.23 + 1.7) * 0.35 + Double(MP.h2(seed &+ 7171, x, 0) % 100) / 100 * 0.3
        return 2 + Int(((v + 0.85) / 1.7 * 4.5).rounded(.down).clamped(0, 4))
    }

    /// The island tile `k` rows above (k 1 ... 6) of column tx, row ty of this chunk, from this chunk or the
    /// one to the north.
    func islandAbove(_ g: [UInt8], _ tx: Int, _ ty: Int, _ k: Int) -> Bool {
        let y = ty - k
        if y >= 0 { return g[y * 32 + tx] != 0 }
        guard let n = north else { return false }
        return n[(32 + y) * 32 + tx] != 0
    }

    /// Paint the backdrop over `img`, which holds the ground below already (scale 1: pixel art, 2: anime).
    public func paint(_ img: inout Bitmap, ground g: [UInt8], scale s: Int) {
        // the far ground, washed with the blue of the air
        for i in 0..<(img.w * img.h) {
            let o = i * 4
            img.px[o] = UInt8(Double(img.px[o]) * 0.32 + Double(SkyBackdrop.haze.r) * 0.68)
            img.px[o + 1] = UInt8(Double(img.px[o + 1]) * 0.32 + Double(SkyBackdrop.haze.g) * 0.68)
            img.px[o + 2] = UInt8(Double(img.px[o + 2]) * 0.32 + Double(SkyBackdrop.haze.b) * 0.68)
            img.px[o + 3] = 255
        }
        // clouds: a few heaps of soft round puffs, lit from above
        var r = RNG(seed: Int(MP.h2(seed &+ 8282, cx, cy)))
        let n = 2 + r.index(3)
        for _ in 0..<n {
            let ox = (8 + r.range(30, 480)) * Double(s), oy = (24 + r.range(30, 480)) * Double(s)
            let puffs = 5 + r.index(4)
            var parts: [(Double, Double, Double)] = []
            for p in 0..<puffs {
                let rad = r.range(10, 24) * Double(s)
                parts.append((ox + (Double(p) - Double(puffs) / 2) * 14 * Double(s) + r.range(-6, 6) * Double(s), oy + r.range(-8, 8) * Double(s), rad))
            }
            for (pass, col, alpha, dy) in [(0, RGBA(196, 210, 232), 0.55, 0.28), (1, RGBA(255, 255, 255), 0.82, 0.0)] {
                _ = pass
                for (px, py, rad) in parts {
                    let x0 = Int(px - rad), x1 = Int(px + rad), y0 = Int(py - rad), y1 = Int(py + rad)
                    for y in y0...y1 { for x in x0...x1 {
                        let dx = (Double(x) - px) / rad, dyy = (Double(y) - py - rad * dy) / rad
                        let d2 = dx * dx + dyy * dyy
                        if d2 <= 1 { SkyBackdrop.blend(&img, x, y, col, alpha * min(1, (1 - d2) * 3)) }
                    } }
                }
            }
        }
        // the underside of the island hanging below its coast
        let t = 16 * s
        for tx in 0..<32 {
            let hang = self.hang(cx * 32 + tx)
            for ty in 0..<32 where g[ty * 32 + tx] == 0 {
                guard let k = (1...6).first(where: { islandAbove(g, tx, ty, $0) }), k <= hang else { continue }
                // the tiles straight above must all be underside down to here (no gap of air between)
                let ox = (tx * 16 + 8) * s, oy = (ty * 16 + 24) * s
                let last = k == hang
                for py in 0..<t {
                    let f = Double(py) / Double(t)
                    // the last tile tapers to a point, its tip wandering left or right a little
                    let inset = last ? Int(Double(t) * 0.5 * pow(f, 0.8)) : 0
                    let shift = last ? Int(Double(MP.h2(seed &+ 3, cx * 32 + tx, ty) % 5) - 2) * s : 0
                    for px in inset..<(t - inset) {
                        let depth = Double(k - 1) + f
                        var col: RGBA
                        if k == 1 && py < 3 * s { col = SkyBackdrop.lip }
                        else if depth < 1.2 { col = SkyBackdrop.earth }
                        else if depth < 2.2 { col = SkyBackdrop.earthDeep }
                        else { col = depth < 3.6 ? SkyBackdrop.rock : SkyBackdrop.rockDeep }
                        // strata and the light from the left
                        if (py / s) % 5 == 4 { col = col.darkened(0.12) }
                        if px < t / 6 { col = col.lightened(0.08) } else if px > t * 5 / 6 { col = col.darkened(0.1) }
                        if last && f > 0.85 && (tx + ty) % 3 == 0 { col = SkyBackdrop.crystal }
                        img.set(ox + px + shift, oy + py, col)
                    }
                }
            }
        }
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}

extension AnimeArt {
    /// The sky storey in the anime style: the backdrop, then the island's tiles.
    public static func bakeSky(layers: [[UInt8]], ground: [[UInt8]], sky: SkyBackdrop) -> Bitmap {
        var img = bakeChunk(layers: ground)
        sky.paint(&img, ground: layers[0], scale: 2)
        return bakeStorey(layers: layers, onto: img)
    }
}

extension PixelArt {
    /// The sky storey in pixel art: the backdrop, then the island's tiles.
    public static func bakeSky(layers: [[UInt8]], ground: [[UInt8]], sky: SkyBackdrop) -> Bitmap {
        var img = bakeChunk(layers: ground)
        sky.paint(&img, ground: layers[0], scale: 1)
        return bakeStorey(layers: layers, onto: img)
    }
}
