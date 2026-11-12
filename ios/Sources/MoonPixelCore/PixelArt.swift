import Foundation

public struct RGBA: Equatable {
    public var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt32(h, radix: 16) ?? 0xff00ff
        self.init(UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255))
    }
    public static let clear = RGBA(0, 0, 0, 0)
    public static let white = RGBA(255, 255, 255)
    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    public func lerp(_ o: RGBA, _ t: Double) -> RGBA {
        func m(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8(max(0, min(255, Double(a) + (Double(b) - Double(a)) * t))) }
        return RGBA(m(r, o.r), m(g, o.g), m(b, o.b), a)
    }
    public func darkened(_ t: Double) -> RGBA { lerp(RGBA(0, 0, 0), t) }
    public func lightened(_ t: Double) -> RGBA { lerp(.white, t) }
    public func dist(_ o: RGBA) -> Double {
        let dr = Double(r) - Double(o.r), dg = Double(g) - Double(o.g), db = Double(b) - Double(o.b)
        return (dr * dr + dg * dg + db * db).squareRoot() / 255.0
    }
}

/// Plain RGBA8 pixel buffer; all art is drawn into these by code.
public struct Bitmap {
    public let w: Int, h: Int
    public var px: [UInt8]
    public init(_ w: Int, _ h: Int, fill: RGBA = .clear) {
        self.w = w; self.h = h
        px = [UInt8](repeating: 0, count: w * h * 4)
        if fill.a != 0 { rect(0, 0, w, h, fill) }
    }
    @inline(__always) public mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        let i = (y * w + x) * 4
        px[i] = c.r; px[i + 1] = c.g; px[i + 2] = c.b; px[i + 3] = c.a
    }
    @inline(__always) public func get(_ x: Int, _ y: Int) -> RGBA {
        if x < 0 || y < 0 || x >= w || y >= h { return .clear }
        let i = (y * w + x) * 4
        return RGBA(px[i], px[i + 1], px[i + 2], px[i + 3])
    }
    public mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: RGBA) {
        if rw <= 0 || rh <= 0 { return }
        for yy in y..<(y + rh) { for xx in x..<(x + rw) { set(xx, yy, c) } }
    }
    public mutating func disc(_ cx: Double, _ cy: Double, _ r: Double, _ c: RGBA) {
        for yy in Int(cy - r)...Int(cy + r) { for xx in Int(cx - r)...Int(cx + r) {
            let dx = Double(xx) + 0.5 - cx, dy = Double(yy) + 0.5 - cy
            if dx * dx + dy * dy <= r * r { set(xx, yy, c) }
        } }
    }
    public mutating func speck(_ ox: Int, _ oy: Int, _ sw: Int, _ sh: Int, _ c: RGBA, salt: Int, density: Double) {
        for y in 0..<sh { for x in 0..<sw where MP.h01(salt, x, y) < density { set(ox + x, oy + y, c) } }
    }
    /// Copy (opaque) or alpha-test blend a region of another bitmap.
    public mutating func blit(_ src: Bitmap, sx: Int, sy: Int, sw: Int, sh: Int, dx: Int, dy: Int, blend: Bool) {
        for y in 0..<sh { for x in 0..<sw {
            let c = src.get(sx + x, sy + y)
            if !blend || c.a > 0 { set(dx + x, dy + y, c) }
        } }
    }
    public func scaled(to nw: Int, _ nh: Int) -> Bitmap {
        var o = Bitmap(nw, nh)
        for y in 0..<nh { for x in 0..<nw { o.set(x, y, get(x * w / nw, y * h / nh)) } }
        return o
    }
    /// Box-filtered downscale (for photos).
    public func resampled(to nw: Int, _ nh: Int) -> Bitmap {
        var o = Bitmap(nw, nh)
        for y in 0..<nh { for x in 0..<nw {
            let x0 = x * w / nw, x1 = max(x0 + 1, (x + 1) * w / nw), y0 = y * h / nh, y1 = max(y0 + 1, (y + 1) * h / nh)
            var r = 0, g = 0, b = 0, a = 0, n = 0
            for yy in y0..<min(h, y1) { for xx in x0..<min(w, x1) {
                let c = get(xx, yy)
                r += Int(c.r) * Int(c.a); g += Int(c.g) * Int(c.a); b += Int(c.b) * Int(c.a); a += Int(c.a); n += 1
            } }
            if a > 0 { o.set(x, y, RGBA(UInt8(r / a), UInt8(g / a), UInt8(b / a), UInt8(a / max(1, n)))) }
        } }
        return o
    }
}

/// Procedural pixel art: tiles, baked chunks and chibi characters.
public enum PixelArt {
    public static let cell = 32
    public static let charW = 32, charH = 40
    public static let outline = RGBA(hex: "#2a1e24")
    public static let held = ["", "sword", "bow", "staff", "axe", "pick", "hoe", "hammer", "basket", "cane"]

    public static let atlas: Bitmap = {
        var img = Bitmap(16 * cell, 16 * cell)
        for t in Content.shared.tiles { if let t = t { drawTile(&img, (t.id % 16) * cell, (t.id / 16) * cell, t) } }
        return img
    }()

    static func drawTile(_ img: inout Bitmap, _ ox: Int, _ oy: Int, _ t: TileDef) {
        let c1 = RGBA(hex: t.c1)
        let c2 = t.c2.isEmpty ? c1.darkened(0.2) : RGBA(hex: t.c2)
        let c3 = t.c3.isEmpty ? c1.lightened(0.2) : RGBA(hex: t.c3)
        let salt = t.id * 31
        let kind = t.artKind
        if t.layer == 0 || (t.layer == 1 && kind != "cliff") {
            img.rect(ox, oy, 16, 16, c1)
            switch kind {
            case "grass":
                img.speck(ox, oy, 16, 16, c2, salt: salt, density: 0.14)
                img.speck(ox, oy, 16, 16, c3, salt: salt + 1, density: 0.07)
            case "water":
                for y in [3, 9, 13] { img.rect(ox + (y * 5) % 9, oy + y, 5, 1, c2) }
            case "planks":
                for y in [0, 4, 8, 12] { img.rect(ox, oy + y, 16, 1, c2) }
                for y in 0..<4 { img.set(ox + (y * 7 + 3) % 16, oy + y * 4 + 2, c2) }
            case "bricks", "cobble":
                for y in [0, 5, 10, 15] { img.rect(ox, oy + y, 16, 1, c2) }
                for r in 0..<3 { for x in [2 + r * 4, 10 + r * 3] { img.rect(ox + x % 16, oy + r * 5 + 1, 1, 4, c2) } }
            case "rows":
                for y in [2, 6, 10, 14] { img.rect(ox, oy + y, 16, 2, c2) }
            case "bridge":
                for x in [0, 5, 10, 15] { img.rect(ox + x, oy, 1, 16, c2) }
                img.rect(ox, oy, 16, 1, c2.darkened(0.2)); img.rect(ox, oy + 15, 16, 1, c2.darkened(0.2))
            case "ice":
                img.speck(ox, oy, 16, 16, c2, salt: salt, density: 0.08)
                img.rect(ox + 3, oy + 5, 6, 1, .white)
            default:
                img.speck(ox, oy, 16, 16, c2, salt: salt, density: 0.16)
            }
            return
        }
        let bx = ox + 8, by = oy + 16
        switch kind {
        case "cliff":
            img.rect(bx, by - 8, 16, 24, c2); img.rect(bx, by - 8, 16, 10, c1)
            img.speck(bx, by - 8, 16, 10, c3, salt: salt, density: 0.12)
            img.speck(bx, by + 2, 16, 14, c2.darkened(0.2), salt: salt + 2, density: 0.2)
        case "tree":
            img.rect(bx + 6, by + 6, 4, 9, c3)
            img.disc(Double(bx) + 8, Double(by) - 2, 10, c2)
            img.disc(Double(bx) + 7, Double(by) - 4, 8, c1)
            img.disc(Double(bx) + 4, Double(by) - 6, 3, c1.lightened(0.18))
        case "pine":
            img.rect(bx + 7, by + 9, 3, 6, c3)
            for i in 0..<3 { let w = 6 + i * 4; for r in 0..<7 {
                let ww = w * (r + 1) / 7
                img.rect(bx + 8 - ww / 2, by - 12 + i * 7 + r, ww, 1, r < 5 ? c1 : c2)
            } }
        case "deadtree":
            img.rect(bx + 7, by - 2, 3, 17, c1); img.rect(bx + 3, by + 2, 5, 2, c2); img.rect(bx + 9, by - 1, 5, 2, c2)
        case "cactus":
            img.rect(bx + 6, by + 1, 4, 14, c1)
            img.rect(bx + 2, by + 5, 3, 5, c2); img.rect(bx + 2, by + 9, 5, 2, c2)
            img.rect(bx + 11, by + 3, 3, 5, c2); img.rect(bx + 9, by + 7, 5, 2, c2)
        case "bush", "berrybush":
            img.disc(Double(bx) + 8, Double(by) + 10, 6, c2); img.disc(Double(bx) + 7, Double(by) + 9, 5, c1)
            if kind == "berrybush" { for p in [(5, 8), (9, 7), (8, 11), (11, 10)] { img.rect(bx + p.0, by + p.1, 2, 2, c3) } }
        case "rock", "ore":
            img.disc(Double(bx) + 8, Double(by) + 10, 6, c2); img.disc(Double(bx) + 7, Double(by) + 9, 5, c1)
            img.rect(bx + 4, by + 6, 3, 1, c1.lightened(0.25))
            if kind == "ore" { for p in [(5, 9), (9, 7), (8, 11)] { img.rect(bx + p.0, by + p.1, 2, 2, c3) } }
        case "wall":
            img.rect(bx, by - 6, 16, 22, c2); img.rect(bx, by - 6, 16, 8, c1.lightened(0.12))
            for y in [4, 9, 14] { img.rect(bx, by + y, 16, 1, c2.darkened(0.25)) }
            img.rect(bx, by + 15, 16, 1, c2.darkened(0.4))
        case "door":
            img.rect(bx + 2, by - 4, 12, 20, c2); img.rect(bx + 3, by - 3, 10, 19, c1)
            img.rect(bx + 11, by + 6, 2, 2, RGBA(hex: "#e8c84a"))
        case "fence", "gate":
            img.rect(bx, by + 6, 16, 2, c1); img.rect(bx, by + 11, 16, 2, c1)
            for x in [1, 7, 13] { img.rect(bx + x, by + 3, 2, 12, c2) }
        case "crop":
            for x in [2, 7, 12] {
                img.rect(bx + x, by + 13 - t.stage * 4, 2, 3 + t.stage * 4, c1)
                if t.stage == 2 { img.rect(bx + x - 1, by + 4, 4, 3, c1.lightened(0.15)) }
            }
        case "sapling":
            img.rect(bx + 7, by + 9, 2, 6, c2); img.disc(Double(bx) + 8, Double(by) + 7, 3.5, c1)
        case "flower":
            img.rect(bx + 7, by + 9, 1, 5, c2); img.rect(bx + 6, by + 6, 3, 3, c1); img.set(bx + 7, by + 7, RGBA(hex: "#fff7cf"))
        case "tuft", "leaves":
            for p in [(3, 10), (6, 8), (9, 11), (12, 9), (7, 12)] { img.rect(bx + p.0, by + p.1, 1, 4, p.0 % 2 == 0 ? c1 : c2) }
        case "mushroom":
            img.rect(bx + 7, by + 10, 2, 4, c2); img.rect(bx + 5, by + 8, 6, 3, c1)
        case "pebbles", "shell", "bones":
            for p in [(4, 11), (9, 9), (11, 13)] { img.rect(bx + p.0, by + p.1, 3, 2, p.0 != 9 ? c1 : c2) }
        case "lily":
            img.disc(Double(bx) + 8, Double(by) + 9, 4, c1); img.rect(bx + 8, by + 8, 2, 2, c2)
        case "campfire", "campfire_out":
            img.rect(bx + 3, by + 11, 10, 3, c1); img.rect(bx + 2, by + 13, 12, 2, RGBA(hex: "#6e7079"))
            if kind == "campfire" { img.disc(Double(bx) + 8, Double(by) + 8, 4, c2); img.disc(Double(bx) + 8, Double(by) + 9, 2.2, c3) }
        case "bed":
            img.rect(bx + 1, by + 2, 14, 13, c3); img.rect(bx + 2, by + 6, 12, 8, c1); img.rect(bx + 3, by + 3, 10, 3, c2)
        case "chest":
            img.rect(bx + 2, by + 5, 12, 10, c2); img.rect(bx + 2, by + 5, 12, 4, c1); img.rect(bx + 7, by + 8, 2, 3, c3)
        case "well", "well_broken":
            img.disc(Double(bx) + 8, Double(by) + 9, 7, c2); img.disc(Double(bx) + 8, Double(by) + 9, 5, c1)
            img.disc(Double(bx) + 8, Double(by) + 9, 3, kind == "well" ? c3 : RGBA(hex: "#2a2a2a"))
        case "lantern", "moonlantern", "torch":
            img.rect(bx + 7, by - 2, 2, 17, c1); img.rect(bx + 5, by - 6, 6, 5, c2)
        case "grave":
            img.rect(bx + 4, by + 4, 8, 11, c1); img.rect(bx + 5, by + 2, 6, 2, c1)
            img.rect(bx + 7, by + 6, 2, 5, c2); img.rect(bx + 6, by + 7, 4, 1, c2)
        default:
            img.rect(bx + 2, by + 3, 12, 12, c2); img.rect(bx + 2, by + 3, 12, 5, c1); img.rect(bx + 4, by + 10, 8, 1, c3)
        }
    }

    /// Chunk image (528 x 536): ground/structures, then decor and objects row by
    /// row. Origin of the chunk is at (8, 24) inside the image.
    public static func bakeChunk(_ c: Chunk) -> Bitmap {
        let at = atlas
        var img = Bitmap(MP.chunkPx + 16, MP.chunkPx + 24)
        let g = c.layers[0], st = c.layers[1], ob = c.layers[2], de = c.layers[3]
        let cliff = Content.shared.tid("cliff")
        for i in 0..<MP.chunkArea {
            let x = (i % 32) * 16 + 8, y = (i / 32) * 16 + 24
            img.blit(at, sx: (Int(g[i]) % 16) * cell, sy: (Int(g[i]) / 16) * cell, sw: 16, sh: 16, dx: x, dy: y, blend: false)
            if st[i] != 0 && st[i] != cliff {
                img.blit(at, sx: (Int(st[i]) % 16) * cell, sy: (Int(st[i]) / 16) * cell, sw: 16, sh: 16, dx: x, dy: y, blend: false)
            }
        }
        for i in 0..<MP.chunkArea {
            let x = (i % 32) * 16, y = (i / 32) * 16 + 8
            for id in [de[i], st[i] == cliff ? cliff : 0, ob[i]] where id != 0 {
                img.blit(at, sx: (Int(id) % 16) * cell, sy: (Int(id) / 16) * cell, sw: cell, sh: cell, dx: x, dy: y, blend: true)
            }
        }
        return img
    }

    // MARK: characters
    public static var faces: [String: Bitmap] = [:]

    static func heldItem(_ img: inout Bitmap, _ kind: String, _ hx: Int, _ hy: Int) {
        let wood = RGBA(hex: "#9a6a3a"), steel = RGBA(hex: "#d8dce8"), dark = RGBA(hex: "#8f93a6")
        switch kind {
        case "sword":
            for i in 0..<10 { img.rect(hx + i / 5, hy - 3 - i, 2, 1, steel); img.set(hx + i / 5, hy - 3 - i, .white) }
            img.rect(hx - 2, hy - 2, 6, 1, RGBA(hex: "#f0c84a")); img.rect(hx, hy - 1, 2, 3, wood)
        case "axe", "hammer", "pick", "hoe":
            img.rect(hx, hy - 8, 2, 11, wood)
            if kind == "axe" { img.rect(hx + 2, hy - 9, 4, 5, steel); img.rect(hx + 5, hy - 8, 1, 3, .white) }
            else if kind == "hammer" { img.rect(hx - 1, hy - 11, 6, 4, dark); img.rect(hx - 1, hy - 11, 6, 1, steel) }
            else if kind == "pick" { img.rect(hx - 1, hy - 9, 7, 2, steel); img.set(hx + 6, hy - 8, steel); img.set(hx - 2, hy - 8, steel) }
            else { img.rect(hx + 2, hy - 9, 4, 2, steel); img.rect(hx + 5, hy - 8, 1, 3, steel) }
        case "bow":
            for i in 0..<13 {
                let bend = Int((3.0 * sin(Double.pi * Double(i) / 12.0)).rounded())
                img.rect(hx + bend, hy - 8 + i, 2, 1, wood); img.set(hx - 1, hy - 8 + i, RGBA(hex: "#f6f2e6"))
            }
        case "staff":
            img.rect(hx, hy - 18, 2, 24, wood)
            img.rect(hx - 1, hy - 23, 4, 5, RGBA(hex: "#59d8ff")); img.rect(hx, hy - 22, 2, 3, .white)
            for p in [(-3, -25), (4, -24), (-3, -19), (5, -20)] { img.set(hx + p.0, hy + p.1, RGBA(hex: "#bff2ff")) }
        case "cane":
            img.rect(hx, hy - 1, 1, 8, wood); img.rect(hx, hy - 2, 3, 1, wood)
        case "basket":
            img.rect(hx - 1, hy + 2, 7, 4, RGBA(hex: "#c89050")); img.rect(hx - 1, hy + 2, 7, 1, RGBA(hex: "#8f6030"))
            img.rect(hx, hy + 1, 2, 1, RGBA(hex: "#e84a5a")); img.rect(hx + 3, hy + 1, 2, 1, RGBA(hex: "#e84a5a"))
        default: break
        }
    }

    static func headShape(_ img: inout Bitmap, _ y0: Int, _ y1: Int, _ c: RGBA, _ x0: Int = 7, _ x1: Int = 24) {
        if y1 < y0 { return }
        for y in y0...y1 {
            let inset = (y <= 8 || y >= 23) ? 2 : ((y <= 9 || y >= 22) ? 1 : 0)
            img.rect(x0 + inset, y, x1 - x0 + 1 - inset * 2, 1, c)
        }
    }

    static func eye(_ img: inout Bitmap, _ x: Int, _ y: Int) {
        img.rect(x, y, 3, 4, RGBA(hex: "#2a2233")); img.rect(x, y + 2, 3, 2, RGBA(hex: "#4a3a5a"))
        img.set(x, y, .white); img.set(x + 2, y + 3, RGBA(hex: "#8a7aa0"))
    }

    static func addOutline(_ img: inout Bitmap) {
        var marks: [(Int, Int)] = []
        for y in 0..<img.h { for x in 0..<img.w where img.get(x, y).a == 0 {
            if img.get(x - 1, y).a > 0 || img.get(x + 1, y).a > 0 || img.get(x, y - 1).a > 0 || img.get(x, y + 1).a > 0 { marks.append((x, y)) }
        } }
        for m in marks { img.set(m.0, m.1, outline) }
    }

    /// Chibi character on a 32x40 canvas (feet at y 38). dir: "down" | "up" | "side";
    /// frame 0 stand, 1/2 walk, 3 acting.
    public static func character(_ look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool) -> Bitmap {
        var img = Bitmap(charW, charH)
        let sk = RGBA(hex: look.skin), hr = RGBA(hex: look.hair), hr2 = hr.lightened(0.22)
        let sh = RGBA(hex: look.shirt), pa = RGBA(hex: look.pants), so = RGBA(hex: look.shoes)
        let blush = sk.lerp(RGBA(hex: "#ff7f96"), 0.55), mouth = RGBA(hex: "#b05a5a")
        let style = look.style % 4
        let lUp = frame == 1 ? 1 : 0, rUp = frame == 2 ? 1 : 0
        let act = frame == 3
        if dir == "side" {
            let spread = frame == 1 ? 1 : (frame == 2 ? -1 : 0)
            img.rect(12 - spread, 33, 3, 3, pa.darkened(0.15)); img.rect(12 - spread, 36, 4, 2, so.darkened(0.1))
            img.rect(16 + spread, 33, 3, 3, pa); img.rect(16 + spread, 36, 4, 2, so)
            img.rect(12, 24, 8, 9, sh); img.rect(12, 24, 2, 9, sh.darkened(0.15)); img.rect(12, 32, 8, 1, sh.darkened(0.25))
            headShape(&img, 8, 23, sk, 8, 23); headShape(&img, 7, 12, hr, 8, 23)
            img.rect(10, 7, 12, 1, hr); img.rect(8, 10, 7, female ? 13 : 9, hr); img.rect(11, 8, 6, 1, hr2)
            for x in [16, 17, 20] { img.set(x, 13, hr) }
            if style == 1 && female { img.disc(7.5, 15, 3, hr) }
            if style == 3 { img.set(15, 5, hr); img.set(16, 4, hr); img.set(17, 5, hr); img.set(16, 6, hr) }
            eye(&img, 19, 15); img.rect(20, 20, 2, 1, blush); img.set(22, 21, mouth)
            if act {
                img.rect(17, 25, 5, 2, sh.lightened(0.1)); img.rect(22, 24, 2, 2, sk); heldItem(&img, held, 24, 24)
            } else if !held.isEmpty {
                img.rect(17, 27, 5, 2, sh.lightened(0.1)); img.rect(22, 27, 2, 2, sk); heldItem(&img, held, 24, 28)
            } else {
                let sw = frame == 1 ? 1 : (frame == 2 ? -1 : 0)
                img.rect(15 + sw, 25, 2, 5, sh.lightened(0.1)); img.rect(15 + sw, 30, 2, 2, sk)
            }
        } else {
            let back = dir == "up"
            img.rect(12, 33, 3, 3 - lUp, pa); img.rect(11, 36 - lUp, 4, 2, so)
            img.rect(17, 33, 3, 3 - rUp, pa.darkened(0.1)); img.rect(17, 36 - rUp, 4, 2, so)
            img.rect(11, 24, 10, 9, sh); img.rect(19, 24, 2, 9, sh.darkened(0.15)); img.rect(11, 32, 10, 1, sh.darkened(0.25))
            img.rect(12, 25, 2, 1, sh.lightened(0.2))
            let a1 = frame == 2 ? 1 : 0
            img.rect(9, 25, 2, 5 - a1, sh.darkened(0.08)); img.rect(9, 30 - a1, 2, 2, sk)
            headShape(&img, 8, 23, sk)
            if back {
                headShape(&img, 8, female ? 23 : 19, hr); img.rect(9, 7, 14, 1, hr); img.rect(10, 9, 6, 1, hr2)
                if female && style != 2 { img.rect(7, 20, 3, 5, hr); img.rect(22, 20, 3, 5, hr) }
            } else {
                headShape(&img, 8, 12, hr); img.rect(9, 7, 14, 1, hr); img.rect(10, 9, 6, 1, hr2)
                for x in [8, 9, 12, 13, 14, 18, 19, 22, 23] { img.set(x, 13, hr) }
                img.set(13, 14, hr); img.set(18, 14, hr)
                let sideLen = style == 2 ? 8 : (female ? 10 : 4)
                img.rect(7, 13, 2, sideLen, hr); img.rect(23, 13, 2, sideLen, hr)
                if !look.face.isEmpty, let f = faces[look.face] {
                    img.blit(f, sx: 0, sy: 0, sw: 10, sh: 8, dx: 11, dy: 14, blend: false)
                } else {
                    eye(&img, 11, 15); eye(&img, 18, 15)
                    img.rect(9, 20, 2, 1, blush); img.rect(21, 20, 2, 1, blush)
                    img.rect(15, 21, 2, 1, mouth); img.set(14, 20, mouth); img.set(17, 20, mouth)
                }
            }
            if style == 1 {
                if female { img.disc(6, 11, 3.2, hr); img.disc(26, 11, 3.2, hr); img.set(5, 10, hr2); img.set(25, 10, hr2) }
                else { for p in [(12, 6), (13, 5), (15, 6), (16, 4), (17, 5), (19, 6), (20, 5)] { img.set(p.0, p.1, hr) } }
            } else if style == 3 {
                for p in [(15, 5), (16, 4), (17, 4), (18, 5), (16, 6)] { img.set(p.0, p.1, hr) }
                if female && !back {
                    img.rect(19, 7, 2, 3, RGBA(hex: "#ff5a7a")); img.rect(22, 7, 2, 3, RGBA(hex: "#ff5a7a")); img.set(21, 8, RGBA(hex: "#ffd24a"))
                }
            }
            if act {
                img.rect(21, 24, 3, 2, sh.darkened(0.08)); img.rect(24, 21, 2, 4, sh.darkened(0.08)); img.rect(24, 19, 2, 2, sk)
                heldItem(&img, held, 26, 20)
            } else {
                let a2 = frame == 1 ? 1 : 0
                img.rect(21, 25, 2, 5 - a2, sh.darkened(0.08)); img.rect(21, 30 - a2, 2, 2, sk)
                heldItem(&img, held, (held == "sword" || held == "staff") ? 24 : 23, 30 - a2)
            }
        }
        if frame == 1 || frame == 2 {
            var shifted = Bitmap(charW, charH)
            shifted.blit(img, sx: 0, sy: 1, sw: charW, sh: 32, dx: 0, dy: 0, blend: false)
            shifted.blit(img, sx: 0, sy: 33, sw: charW, sh: 7, dx: 0, dy: 33, blend: false)
            shifted.rect(11, 32, 10, 1, sh.darkened(0.25))
            img = shifted
        }
        if child {
            let small = img.scaled(to: 26, 32)
            img = Bitmap(charW, charH)
            img.blit(small, sx: 0, sy: 0, sw: 26, sh: 32, dx: 3, dy: 7, blend: false)
        }
        addOutline(&img)
        return img
    }
}

/// Photos and pictures -> game assets, entirely on device (image analysis, not a neural network).
public enum AssetImporter {
    public static let maxSprite = 64

    static func isSkin(_ c: RGBA) -> Bool {
        let r = Double(c.r), g = Double(c.g), b = Double(c.b)
        let cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b
        let cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b
        return cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173 && r > 60
    }

    static func mean(_ img: Bitmap, _ x0: Int, _ y0: Int, _ w: Int, _ h: Int, skin: Int) -> (RGBA, Int) {
        var r = 0, g = 0, b = 0, n = 0
        for y in max(0, y0)..<max(max(0, y0), min(img.h, y0 + h)) { for x in max(0, x0)..<max(max(0, x0), min(img.w, x0 + w)) {
            let c = img.get(x, y)
            if c.a < 128 || (skin >= 0 && (isSkin(c) ? 1 : 0) != skin) { continue }
            r += Int(c.r); g += Int(c.g); b += Int(c.b); n += 1
        } }
        return n == 0 ? (RGBA(0, 0, 0), 0) : (RGBA(UInt8(r / n), UInt8(g / n), UInt8(b / n)), n)
    }

    /// Face box (x, y, w, h) in a 64x64 working image, from skin-tone density.
    public static func findFace(_ small: Bitmap) -> (Int, Int, Int, Int) {
        let w = small.w, h = small.h
        var cols = [Int](repeating: 0, count: w), rows = [Int](repeating: 0, count: h), total = 0
        for y in 0..<(h * 8 / 10) { for x in 0..<w where isSkin(small.get(x, y)) { cols[x] += 1; rows[y] += 1; total += 1 } }
        if Double(total) < Double(w * h) * 0.03 { return (w * 3 / 10, h * 15 / 100, w * 4 / 10, h * 4 / 10) }
        let cmax = Double(cols.max() ?? 1), rmax = Double(rows.max() ?? 1)
        var x0 = 0, x1 = w - 1, y0 = 0, y1 = h - 1
        while x0 < w - 1 && Double(cols[x0]) < cmax * 0.35 { x0 += 1 }
        while x1 > x0 && Double(cols[x1]) < cmax * 0.35 { x1 -= 1 }
        while y0 < h - 1 && Double(rows[y0]) < rmax * 0.35 { y0 += 1 }
        while y1 > y0 && Double(rows[y1]) < rmax * 0.35 { y1 -= 1 }
        return (x0, y0, max(4, x1 - x0 + 1), max(4, y1 - y0 + 1))
    }

    /// Portrait -> character colours + a 10x8 pixel face for the sprite's head.
    public static func photoToLook(_ photo: Bitmap) -> (look: Look, face: Bitmap, faceRect: (Int, Int, Int, Int)) {
        let small = photo.resampled(to: 64, 64)
        let f = findFace(small)
        let fh = f.3
        var skin = mean(small, f.0, f.1, f.2, f.3, skin: 1)
        if skin.1 == 0 { skin = mean(small, f.0, f.1, f.2, f.3, skin: -1) }
        var hair = mean(small, f.0 + f.2 / 4, f.1 - max(2, fh * 28 / 100), max(2, f.2 / 2), max(2, fh * 28 / 100), skin: 0)
        if hair.1 < 6 { hair = mean(small, f.0 - 4, f.1 - 2, 4, fh / 2, skin: 0) }
        var shirt = mean(small, f.0 - f.2 / 2, f.1 + fh + fh * 3 / 10, f.2 * 2, fh * 8 / 10, skin: 0)
        if shirt.1 < 6 { shirt = mean(small, 0, 52, 64, 12, skin: -1) }
        let pants = mean(small, 8, 58, 48, 6, skin: 0)
        var look = Look()
        look.skin = skin.0.hex
        look.hair = hair.1 > 0 ? hair.0.hex : "#3a2a22"
        let shirtC = shirt.1 > 0 ? shirt.0 : RGBA(hex: "#3a6ac8")
        look.shirt = shirtC.hex
        look.pants = (pants.1 > 20 && pants.0.dist(shirtC) > 0.18 ? pants.0 : shirtC.darkened(0.45)).hex
        let ix = max(0, f.0 + f.2 / 8), iy = max(0, f.1 + fh / 5)
        let iw = max(4, f.2 * 3 / 4), ih = max(4, fh * 7 / 10)
        let sx = photo.w * ix / 64, sy = photo.h * iy / 64, sw = max(1, photo.w * iw / 64), sh = max(1, photo.h * ih / 64)
        var crop = Bitmap(sw, sh)
        crop.blit(photo, sx: sx, sy: sy, sw: sw, sh: sh, dx: 0, dy: 0, blend: false)
        var face = crop.resampled(to: 10, 8)
        for y in 0..<8 { for x in 0..<10 {
            let c = face.get(x, y)
            func q(_ v: UInt8) -> UInt8 { UInt8(min(255, (Int(v) + 10) / 21 * 21)) }
            face.set(x, y, RGBA(q(c.r), q(c.g), q(c.b)))
        } }
        return (look, face, f)
    }

    /// Median-cut palette (at most n colours) of the opaque pixels.
    public static func palette(_ img: Bitmap, _ n: Int) -> [RGBA] {
        var px: [[Double]] = []
        for y in 0..<img.h { for x in 0..<img.w { let c = img.get(x, y); if c.a >= 128 { px.append([Double(c.r), Double(c.g), Double(c.b)]) } } }
        if px.isEmpty { return [] }
        var boxes = [px]
        while boxes.count < n {
            var bi = -1, best = 0.0, axis = 0
            for (i, b) in boxes.enumerated() where b.count >= 2 {
                for ax in 0..<3 {
                    var lo = 255.0, hi = 0.0
                    for v in b { lo = min(lo, v[ax]); hi = max(hi, v[ax]) }
                    let score = (hi - lo) * Double(b.count).squareRoot()
                    if score > best { best = score; bi = i; axis = ax }
                }
            }
            if bi < 0 || best < 0.5 { break }
            let box = boxes[bi].sorted { $0[axis] < $1[axis] }
            boxes[bi] = Array(box[..<(box.count / 2)])
            boxes.append(Array(box[(box.count / 2)...]))
        }
        return boxes.map { b in
            var s = [0.0, 0.0, 0.0]
            for v in b { s[0] += v[0]; s[1] += v[1]; s[2] += v[2] }
            let k = Double(b.count)
            return RGBA(UInt8(s[0] / k), UInt8(s[1] / k), UInt8(s[2] / k))
        }
    }

    /// Any picture -> small palette-reduced sprite with the background removed.
    public static func pixelize(_ src: Bitmap, maxSide: Int = 32, colors: Int = 16, removeBackground: Bool = true) -> Bitmap {
        let side = min(maxSprite, max(8, maxSide))
        let k = Double(side) / Double(max(src.w, src.h))
        let w = max(1, Int((Double(src.w) * k).rounded())), h = max(1, Int((Double(src.h) * k).rounded()))
        var img = src.resampled(to: w, h)
        if removeBackground {
            let corners = [img.get(0, 0), img.get(w - 1, 0), img.get(0, h - 1), img.get(w - 1, h - 1)]
            let bg = RGBA(UInt8(corners.reduce(0) { $0 + Int($1.r) } / 4), UInt8(corners.reduce(0) { $0 + Int($1.g) } / 4), UInt8(corners.reduce(0) { $0 + Int($1.b) } / 4))
            var stack: [(Int, Int)] = []
            for x in 0..<w { stack.append((x, 0)); stack.append((x, h - 1)) }
            for y in 0..<h { stack.append((0, y)); stack.append((w - 1, y)) }
            var seen = [Bool](repeating: false, count: w * h)
            while let p = stack.popLast() {
                if p.0 < 0 || p.1 < 0 || p.0 >= w || p.1 >= h || seen[p.1 * w + p.0] { continue }
                seen[p.1 * w + p.0] = true
                let c = img.get(p.0, p.1)
                if c.a >= 128 && c.dist(bg) > 0.16 { continue }
                img.set(p.0, p.1, .clear)
                stack.append((p.0 + 1, p.1)); stack.append((p.0 - 1, p.1)); stack.append((p.0, p.1 + 1)); stack.append((p.0, p.1 - 1))
            }
        }
        let pal = palette(img, min(64, max(2, colors)))
        for y in 0..<h { for x in 0..<w {
            let c = img.get(x, y)
            if c.a < 128 || pal.isEmpty { img.set(x, y, .clear); continue }
            var best = pal[0], bd = 9.0
            for pc in pal { let d = c.dist(pc); if d < bd { bd = d; best = pc } }
            img.set(x, y, best)
        } }
        return img
    }
}
