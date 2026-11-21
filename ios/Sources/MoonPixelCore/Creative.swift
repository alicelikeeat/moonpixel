import Foundation

// Quick building and play helpers asked for by players: build a pillar under your own feet to climb (a block
// placed where you stand holds the floor of the storey above, and you land on it), fill the pack with
// building materials in one go, jump the clock to a chosen time of day. Everything goes through the same
// rules as normal building: what holds a floor up, what can stand where, what the pack can carry.

public enum DayPhase: String, Codable { case dawn, day, dusk, night }

extension OpenWorld {
    /// Where in the day it is: dawn 5–7, day 7–18, dusk 18–20.5, night otherwise.
    public var dayPhase: DayPhase {
        let h = hour
        if h >= 5 && h < 7 { return .dawn }
        if h >= 7 && h < 18 { return .day }
        if h >= 18 && h < 20.5 { return .dusk }
        return .night
    }
    /// "14:05"
    public var clockText: String { let h = hour; return String(format: "%02d:%02d", Int(h), Int((h - Double(Int(h))) * 60)) }
}

extension Society {
    // MARK: time of day

    /// Move the clock forward to the next time it is `hour` o'clock (never backwards: what has grown and
    /// what people did stay done). Returns the seconds skipped.
    @discardableResult public func advanceTo(hour h: Double) -> Double {
        let day = MP.daySeconds
        let now = world.time.truncatingRemainder(dividingBy: day)
        let want = (h.truncatingRemainder(dividingBy: 24) / 24) * day
        var skip = want - now
        if skip <= 1e-6 { skip += day }
        world.time += skip
        return skip
    }

    // MARK: a pillar under your feet

    /// The block a pack good becomes when placed under the feet (nil: not a building block).
    public static func pillarBlock(for good: String) -> (wall: String, floor: String)? {
        switch good {
        case "stone": return ("wall_stone", "stone_floor")
        case "wood", "planks": return ("wall_wood", "wood_floor")
        case "parts", "iron": return ("wall_brick", "brick_floor")
        default: return nil
        }
    }

    /// Put one block where the traveller stands and step up onto the storey above: the block becomes the
    /// column under the new floor tile, the floor is laid there (held up by that block, like any floor), and
    /// the traveller lands on it. One unit of `good` from the pack per block. Refused (nothing taken) when the
    /// traveller is underground or in a vehicle, when the good is not a block, when there is none in the
    /// pack, or when the place above is taken (a floor, a wall: a ceiling). Returns why not, or nil.
    @discardableResult public func pillarUp(with good: String = "stone") -> String? {
        guard var b = realm.player.body, b.vehicle == nil, b.platform == nil else { return "not standing" }
        guard !MP.isBelow(b.depth) else { return "underground" }
        guard let block = Society.pillarBlock(for: good) else { return "not a block" }
        guard carried(good) >= 1 else { return "none left" }
        let t = Motion.tile(b.x, b.y)
        let here = layer(b.depth)
        // where it goes must be free (nothing solid, no stairs) on this layer
        let o = here.tile(2, t.x, t.y)
        if o != 0 && (content.solid[Int(o)] || content.tile(o)?.key.hasPrefix("stairs") == true) { return "something here" }
        let aboveN = b.depth == 0 ? 1 : b.depth - OpenWorld.storeyBase + 1
        let up = storeyWorld(aboveN)
        if up.tile(0, t.x, t.y) != 0 || up.tile(2, t.x, t.y) != 0 { return "ceiling" }
        carry(good, -1)
        here.setTile(2, t.x, t.y, content.tid(block.wall))
        here.setTile(3, t.x, t.y, 0)
        up.setTile(0, t.x, t.y, content.tid(block.floor))
        // the traveller is on the new floor, standing
        let g = WorldGround(self)
        b.depth = OpenWorld.storeyBase + aboveN
        b.z = g.floor(b.depth, t) ?? g.nominal(b.depth, t)
        b.vz = 0; b.state = .standing; b.sinceGround = 0
        realm.player.body = b
        realm.player.depth = b.depth
        stats.tilesPlaced += 2
        return nil
    }

    // MARK: materials in one go

    /// Fill what room the pack has with building materials, in fixed shares (stone, planks, wood, iron,
    /// parts, food, tools); never past what it can carry. The save is marked like any other cheat.
    /// Returns what was given.
    @discardableResult public func supplyPack() -> [String: Double] {
        let shares: [(String, Double)] = [("stone", 0.28), ("planks", 0.16), ("wood", 0.12), ("iron", 0.12), ("parts", 0.12), ("food", 0.10), ("fuel", 0.06), ("tools", 0.04)]
        var given: [String: Double] = [:]
        let free = max(0, invCfg.capacity - packWeight())
        guard free >= 1 else { return given }
        for (k, share) in shares {
            let w = max(1e-9, Items.def(k).weight)
            let n = min((free * share / w).rounded(.down), roomFor(k).rounded(.down))
            if n >= 1 { carry(k, n); given[k] = n }
        }
        if !given.isEmpty { realm.player.cheated = true }
        return given
    }
}

// MARK: - anime style

/// How the world is drawn: pixel art as made, or the anime look (smooth edges, ink outlines, cel shading).
public enum ArtStyle: String, Codable, CaseIterable { case pixel, anime }

extension Bitmap {
    @inline(__always) func at(_ x: Int, _ y: Int) -> RGBA {
        let i = (y * w + x) * 4
        return RGBA(px[i], px[i + 1], px[i + 2], px[i + 3])
    }

    /// Cel shading: brighter, more saturated colours in a few flat bands of light (same size, same alpha).
    public func animeGraded() -> Bitmap {
        var out = self
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] != 0 {
            var r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            let l = (mx + mn) / 2
            // saturation up a third, then light in four flat bands
            r = l + (r - l) * 1.35; g = l + (g - l) * 1.35; b = l + (b - l) * 1.35
            let band = (min(0.999, max(0, l)) * 4).rounded(.down) / 4 + 0.16
            let k = l > 1e-6 ? min(1.6, band / l) : 1
            r = min(1, max(0, r * k)); g = min(1, max(0, g * k)); b = min(1, max(0, b * k))
            out.px[i] = UInt8(r * 255); out.px[i + 1] = UInt8(g * 255); out.px[i + 2] = UInt8(b * 255)
        }
        return out
    }

    /// The anime look: twice the size with the stair-steps smoothed (Scale2x), cel-shaded colours, and a dark
    /// ink line round every shape (where it meets transparency) and between strongly different colours.
    public func anime() -> Bitmap {
        let src = animeGraded()
        var big = Bitmap(w * 2, h * 2)
        for y in 0..<h { for x in 0..<w {
            let p = src.at(x, y)
            let a = y > 0 ? src.at(x, y - 1) : p, d = y < h - 1 ? src.at(x, y + 1) : p
            let c = x > 0 ? src.at(x - 1, y) : p, b = x < w - 1 ? src.at(x + 1, y) : p
            let e0 = (c == a && c != d && a != b) ? a : p
            let e1 = (a == b && a != c && b != d) ? b : p
            let e2 = (d == c && d != b && c != a) ? c : p
            let e3 = (b == d && b != a && d != c) ? d : p
            big.set(2 * x, 2 * y, e0); big.set(2 * x + 1, 2 * y, e1); big.set(2 * x, 2 * y + 1, e2); big.set(2 * x + 1, 2 * y + 1, e3)
        } }
        // ink: an opaque pixel next to transparency, or next to a much darker or lighter colour, is drawn dark
        var out = big
        func lum(_ c: RGBA) -> Double { (0.3 * Double(c.r) + 0.59 * Double(c.g) + 0.11 * Double(c.b)) / 255 }
        for y in 0..<big.h { for x in 0..<big.w {
            let p = big.at(x, y)
            guard p.a != 0 else { continue }
            var edge = false, contrast = false
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < big.w, ny < big.h else { continue }
                let q = big.at(nx, ny)
                if q.a == 0 { edge = true }
                else if lum(q) - lum(p) > 0.30 && (dx > 0 || dy > 0) { contrast = true }
            }
            if edge || contrast {
                let k = edge ? 0.30 : 0.55
                out.set(x, y, RGBA(UInt8(Double(p.r) * k), UInt8(Double(p.g) * k), UInt8(Double(p.b) * k), p.a))
            }
        } }
        return out
    }
}
