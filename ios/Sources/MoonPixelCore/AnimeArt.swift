import Foundation

// The anime style, drawn by code: every character and every tile is painted again at twice the pixels with
// smooth (antialiased) shapes, flat cel-shaded colour bands, a light from the upper left, and dark ink lines
// round each part, as in hand-inked anime. Characters are chibi anime figures: a large head, large eyes with
// irises and highlights, layered hair with bangs, blush, clothes with shading and folds. Ground, plants,
// water, stone, walls and things each have their own painted look. Nothing here is a filter over the pixel
// art, except for the few tile kinds that have no painting of their own yet (they fall back to `anime()`).
//
// Sizes are exactly twice the pixel art's (a character is 64 x 80, an atlas cell 64 x 64, a chunk image
// 1056 x 1072), so the same sprites and the same chunk layout are used; the app shows them at half scale.

/// A small painting surface: shapes are filled at three times the resolution and averaged down, so every
/// edge is smooth. Coordinates are in output pixels (floating point).
public struct Canvas {
    public let w: Int, h: Int
    static let ss = 3
    var sub: [UInt32]                 // RGBA8 per sub-pixel, 0 = empty

    public init(_ w: Int, _ h: Int) { self.w = w; self.h = h; sub = [UInt32](repeating: 0, count: w * h * Canvas.ss * Canvas.ss) }

    @inline(__always) static func pack(_ c: RGBA) -> UInt32 { UInt32(c.r) | UInt32(c.g) << 8 | UInt32(c.b) << 16 | UInt32(c.a) << 24 }
    @inline(__always) static func unpack(_ v: UInt32) -> RGBA { RGBA(UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8(v >> 24)) }

    /// Paint every sub-pixel inside the shape (with the colour the colour function gives there; nil leaves it).
    /// Colours with alpha below 255 are mixed over what is there.
    public mutating func paint(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, inside: (Double, Double) -> Bool, color: (Double, Double) -> RGBA?) {
        let s = Double(Canvas.ss), sw = w * Canvas.ss
        let ax = max(0, Int((x0 * s).rounded(.down))), bx = min(w * Canvas.ss - 1, Int((x1 * s).rounded(.up)))
        let ay = max(0, Int((y0 * s).rounded(.down))), by = min(h * Canvas.ss - 1, Int((y1 * s).rounded(.up)))
        guard ax <= bx, ay <= by else { return }
        for sy in ay...by {
            let y = (Double(sy) + 0.5) / s
            for sx in ax...bx {
                let x = (Double(sx) + 0.5) / s
                guard inside(x, y), let c = color(x, y) else { continue }
                let i = sy * sw + sx
                if c.a == 255 || sub[i] == 0 { sub[i] = Canvas.pack(c) }
                else {
                    let d = Canvas.unpack(sub[i]), t = Double(c.a) / 255
                    sub[i] = Canvas.pack(RGBA(UInt8(Double(d.r) * (1 - t) + Double(c.r) * t), UInt8(Double(d.g) * (1 - t) + Double(c.g) * t),
                                              UInt8(Double(d.b) * (1 - t) + Double(c.b) * t), max(d.a, c.a)))
                }
            }
        }
    }

    // MARK: shapes (each with an ink line of `ink` pixels round it when asked)

    public mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: RGBA, ink: Double = 0, shade: Shade? = nil) {
        if ink > 0 {
            let ex = rx + ink, ey = ry + ink
            paint(cx - ex, cy - ey, cx + ex, cy + ey, inside: { x, y in let u = (x - cx) / ex, v = (y - cy) / ey; return u * u + v * v <= 1 }, color: { _, _ in AnimeArt.ink })
        }
        paint(cx - rx, cy - ry, cx + rx, cy + ry, inside: { x, y in let u = (x - cx) / rx, v = (y - cy) / ry; return u * u + v * v <= 1 },
              color: { x, y in shade.map { $0.color(c, x: (x - cx) / rx, y: (y - cy) / ry) } ?? c })
    }

    public mutating func rect(_ x: Double, _ y: Double, _ rw: Double, _ rh: Double, _ c: RGBA, ink: Double = 0, radius: Double = 0, shade: Shade? = nil) {
        func inRound(_ px: Double, _ py: Double, _ grow: Double) -> Bool {
            let x0 = x - grow, y0 = y - grow, x1 = x + rw + grow, y1 = y + rh + grow, r = radius + (radius > 0 ? grow : 0)
            guard px >= x0, px <= x1, py >= y0, py <= y1 else { return false }
            if r <= 0 { return true }
            let qx = px < x0 + r ? x0 + r : (px > x1 - r ? x1 - r : px), qy = py < y0 + r ? y0 + r : (py > y1 - r ? y1 - r : py)
            return (px - qx) * (px - qx) + (py - qy) * (py - qy) <= r * r
        }
        if ink > 0 { paint(x - ink, y - ink, x + rw + ink, y + rh + ink, inside: { inRound($0, $1, ink) }, color: { _, _ in AnimeArt.ink }) }
        paint(x, y, x + rw, y + rh, inside: { inRound($0, $1, 0) }, color: { px, py in shade.map { $0.color(c, x: (px - x) / rw * 2 - 1, y: (py - y) / rh * 2 - 1) } ?? c })
    }

    /// A filled polygon (even-odd), optionally inked (the ink is the polygon pushed out from its centre).
    public mutating func poly(_ pts: [(Double, Double)], _ c: RGBA, ink: Double = 0, shade: Shade? = nil) {
        guard pts.count >= 3 else { return }
        let cx = pts.map { $0.0 }.reduce(0, +) / Double(pts.count), cy = pts.map { $0.1 }.reduce(0, +) / Double(pts.count)
        func inside(_ p: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
            var c = false, j = p.count - 1
            for i in 0..<p.count {
                let (xi, yi) = p[i], (xj, yj) = p[j]
                if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi { c.toggle() }
                j = i
            }
            return c
        }
        func bounds(_ p: [(Double, Double)]) -> (Double, Double, Double, Double) { (p.map { $0.0 }.min()!, p.map { $0.1 }.min()!, p.map { $0.0 }.max()!, p.map { $0.1 }.max()!) }
        if ink > 0 {
            let grown = pts.map { p -> (Double, Double) in
                let dx = p.0 - cx, dy = p.1 - cy, l = max(1e-6, (dx * dx + dy * dy).squareRoot())
                return (p.0 + dx / l * ink, p.1 + dy / l * ink)
            }
            let b = bounds(grown)
            paint(b.0, b.1, b.2, b.3, inside: { inside(grown, $0, $1) }, color: { _, _ in AnimeArt.ink })
        }
        let b = bounds(pts), sw = max(1e-6, b.2 - b.0), sh = max(1e-6, b.3 - b.1)
        paint(b.0, b.1, b.2, b.3, inside: { inside(pts, $0, $1) }, color: { x, y in shade.map { $0.color(c, x: (x - b.0) / sw * 2 - 1, y: (y - b.1) / sh * 2 - 1) } ?? c })
    }

    /// A thick line with round ends.
    public mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ width: Double, _ c: RGBA, ink: Double = 0) {
        func dist(_ px: Double, _ py: Double) -> Double {
            let vx = x1 - x0, vy = y1 - y0, l2 = max(1e-9, vx * vx + vy * vy)
            let t = max(0, min(1, ((px - x0) * vx + (py - y0) * vy) / l2))
            let qx = x0 + vx * t - px, qy = y0 + vy * t - py
            return (qx * qx + qy * qy).squareRoot()
        }
        let r = width / 2, e = r + ink
        let bx0 = min(x0, x1) - e, by0 = min(y0, y1) - e, bx1 = max(x0, x1) + e, by1 = max(y0, y1) + e
        if ink > 0 { paint(bx0, by0, bx1, by1, inside: { dist($0, $1) <= e }, color: { _, _ in AnimeArt.ink }) }
        paint(bx0, by0, bx1, by1, inside: { dist($0, $1) <= r }, color: { _, _ in c })
    }

    /// A curved stroke through points (a smooth Catmull-Rom curve drawn as short thick segments).
    public mutating func curve(_ pts: [(Double, Double)], _ width: Double, _ c: RGBA) {
        guard pts.count >= 2 else { return }
        var prev = pts[0]
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            for k in 1...6 {
                let t = Double(k) / 6, t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.0) + (-p0.0 + p2.0) * t + (2 * p0.0 - 5 * p1.0 + 4 * p2.0 - p3.0) * t2 + (-p0.0 + 3 * p1.0 - 3 * p2.0 + p3.0) * t3)
                let y = 0.5 * ((2 * p1.1) + (-p0.1 + p2.1) * t + (2 * p0.1 - 5 * p1.1 + 4 * p2.1 - p3.1) * t2 + (-p0.1 + 3 * p1.1 - 3 * p2.1 + p3.1) * t3)
                line(prev.0, prev.1, x, y, width, c)
                prev = (x, y)
            }
        }
    }

    /// Averaged down to the output pixels: colour by mean of the covered sub-pixels, alpha by coverage.
    public func image() -> Bitmap {
        var out = Bitmap(w, h)
        let s = Canvas.ss, sw = w * s
        for y in 0..<h { for x in 0..<w {
            var r = 0, g = 0, b = 0, a = 0, n = 0
            for dy in 0..<s { for dx in 0..<s {
                let v = sub[(y * s + dy) * sw + x * s + dx]
                if v == 0 { continue }
                let c = Canvas.unpack(v)
                r += Int(c.r) * Int(c.a); g += Int(c.g) * Int(c.a); b += Int(c.b) * Int(c.a); a += Int(c.a); n += 1
            } }
            guard a > 0 else { continue }
            out.set(x, y, RGBA(UInt8(r / a), UInt8(g / a), UInt8(b / a), UInt8(min(255, a / (s * s)))))
            _ = n
        } }
        return out
    }
}

/// Cel shading: one flat shadow band on the side away from the light (upper left), one highlight band near it.
public struct Shade {
    public var shadow = 0.22, light = 0.16
    public var cut = 0.25           // where the shadow starts (along the light axis, -1 near the light ... 1 away)
    public var glint = -0.55        // where the highlight ends
    public init(shadow: Double = 0.22, light: Double = 0.16, cut: Double = 0.25, glint: Double = -0.55) { self.shadow = shadow; self.light = light; self.cut = cut; self.glint = glint }
    func color(_ c: RGBA, x: Double, y: Double) -> RGBA {
        let along = (x + y) * 0.7071
        if along > cut { return AnimeArt.shadowed(c, shadow) }
        if along < glint { return c.lightened(light) }
        return c
    }
}

public enum AnimeArt {
    public static let ink = RGBA(46, 30, 42)
    public static let cell = PixelArt.cell * 2
    public static let charW = PixelArt.charW * 2, charH = PixelArt.charH * 2

    /// Anime shadows lean cool and saturated rather than just darker.
    static func shadowed(_ c: RGBA, _ k: Double) -> RGBA {
        let d = c.darkened(k)
        return RGBA(UInt8(Double(d.r) * 0.92), UInt8(Double(d.g) * 0.95), UInt8(min(255, Double(d.b) * 1.08 + 8)), c.a)
    }
    static func pastel(_ c: RGBA) -> RGBA {
        // brighter, more saturated: anime colour
        let r = Double(c.r), g = Double(c.g), b = Double(c.b), l = (r + g + b) / 3
        func f(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (l + (v - l) * 1.3) * 1.08 + 6))) }
        return RGBA(f(r), f(g), f(b), c.a)
    }

    // MARK: characters

    /// An anime chibi figure on a 64 x 80 canvas (feet at y 76): the same look, directions and frames as the
    /// pixel figure (dir "down" | "up" | "side"; frame 0 stand, 1 and 2 walk, 3 acting), painted.
    public static func character(_ look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool) -> Bitmap {
        var c = Canvas(charW, charH)
        let skin = pastel(RGBA(hex: look.skin)), hair = pastel(RGBA(hex: look.hair)), shirt = pastel(RGBA(hex: look.shirt))
        let pants = pastel(RGBA(hex: look.pants)), shoes = pastel(RGBA(hex: look.shoes))
        let hairLight = hair.lightened(0.28), hairDark = shadowed(hair, 0.28)
        let iris = irisColor(hair)
        let style = look.style % 4
        let walk = frame == 1 ? 1.0 : (frame == 2 ? -1.0 : 0)
        let bob = frame == 1 || frame == 2 ? -1.5 : 0
        let act = frame == 3
        let k: Double = child ? 0.82 : 1
        // everything is laid out round (cx, foot) and scaled for children
        let cx = 32.0, foot = 76.0
        func X(_ v: Double) -> Double { cx + v * k }
        func Y(_ v: Double) -> Double { foot - (76 - v) * k + (v < 60 ? bob : 0) }
        let side = dir == "side", back = dir == "up"
        let cel = Shade()

        // the shadow on the ground
        c.ellipse(X(0), foot - 1, 14 * k, 3.2 * k, RGBA(0, 0, 0, 60))

        // back hair (behind everything of the head)
        if !side {
            let longHair = female || style == 2
            c.ellipse(X(0), Y(25), 18 * k, 16.5 * k, hair, ink: 1.6)
            if longHair { c.rect(X(-17), Y(26), 34 * k, (female ? 26 : 16) * k, hair, ink: 1.6, radius: 8 * k, shade: Shade(shadow: 0.25)) }
        } else {
            c.ellipse(X(-3), Y(26), 17 * k, 16.5 * k, hair, ink: 1.6)
            if female || style == 2 { c.rect(X(-16), Y(28), 14 * k, 24 * k, hair, ink: 1.6, radius: 6 * k) }
        }
        if style == 1 && female && !side {
            // twin tails
            for s in [-1.0, 1.0] {
                c.poly([(X(s * 15), Y(18)), (X(s * 27), Y(30)), (X(s * 25), Y(52)), (X(s * 17), Y(40))], hair, ink: 1.6, shade: cel)
            }
        }

        // legs and shoes
        let legY = Y(60)
        if side {
            c.line(X(-3 - walk * 3), legY, X(-3 - walk * 5), Y(72), 6.5 * k, shadowed(pants, 0.15), ink: 1.4)
            c.line(X(3 + walk * 3), legY, X(3 + walk * 5), Y(72), 6.5 * k, pants, ink: 1.4)
            c.ellipse(X(-1 - walk * 5), Y(73.5), 5 * k, 2.8 * k, shadowed(shoes, 0.15), ink: 1.2)
            c.ellipse(X(5 + walk * 5), Y(73.5), 5 * k, 2.8 * k, shoes, ink: 1.2)
        } else {
            let l = frame == 1 ? 2.0 : 0, r = frame == 2 ? 2.0 : 0
            c.line(X(-5), legY, X(-5), Y(72 - l), 6.5 * k, pants, ink: 1.4)
            c.line(X(5), legY, X(5), Y(72 - r), 6.5 * k, shadowed(pants, 0.12), ink: 1.4)
            c.ellipse(X(-5.5), Y(73.5 - l), 4.6 * k, 2.8 * k, shoes, ink: 1.2)
            c.ellipse(X(5.5), Y(73.5 - r), 4.6 * k, 2.8 * k, shoes, ink: 1.2)
        }

        // the body: a soft trapezoid, a collar, a fold
        let body: [(Double, Double)] = [(X(-10), Y(46)), (X(10), Y(46)), (X(12.5), Y(63)), (X(-12.5), Y(63))]
        c.poly(body, shirt, ink: 1.6, shade: Shade(shadow: 0.2, cut: 0.2))
        if !back {
            c.poly([(X(-6), Y(46)), (X(6), Y(46)), (X(0), Y(52))], shirt.lightened(0.35), ink: 0.9)       // the collar
            c.line(X(0), Y(53), X(0), Y(61), 1.0, shadowed(shirt, 0.3))                                  // a fold
            if female { c.poly([(X(-12.5), Y(58)), (X(12.5), Y(58)), (X(15), Y(66)), (X(-15), Y(66))], shirt.lightened(0.12), ink: 1.4, shade: cel) }   // a skirt
        }

        // arms (behind for the back view) and hands
        func arm(_ s: Double, swing: Double, raised: Bool) {
            let sx = X(s * 11), sy = Y(48)
            let hx = raised ? X(s * 19) : X(s * 13 + swing * 2), hy = raised ? Y(38) : Y(60 - abs(swing))
            c.line(sx, sy, hx, hy, 5.2 * k, s > 0 ? shadowed(shirt, 0.12) : shirt, ink: 1.4)
            c.ellipse(hx, hy + 1, 2.8 * k, 2.8 * k, skin, ink: 1.2)
        }
        if side {
            arm(1, swing: act ? 0 : walk * 2, raised: act)
        } else {
            arm(-1, swing: walk, raised: false)
            arm(1, swing: -walk, raised: act)
        }

        // the head: big, round, with a soft chin
        let hy = Y(28)
        c.ellipse(X(side ? 1 : 0), hy, 15.5 * k, 15 * k, skin, ink: 1.8, shade: Shade(shadow: 0.13, light: 0.06, cut: 0.45, glint: -0.9))
        if !back {
            if side {
                // the face in profile: one big eye, a blush, a small mouth
                eye(&c, X(8.5), hy + 4.5 * k, k, iris, side: true)
                c.ellipse(X(9), hy + 9 * k, 3 * k, 1.6 * k, RGBA(255, 120, 150, 110))
                c.line(X(12.5), hy + 11 * k, X(14), hy + 11 * k, 1.1, RGBA(170, 70, 80))
            } else {
                eye(&c, X(-6.8), hy + 4.5 * k, k, iris, side: false)
                eye(&c, X(6.8), hy + 4.5 * k, k, iris, side: false)
                // blush and mouth
                c.ellipse(X(-10.5), hy + 10 * k, 3.2 * k, 1.5 * k, RGBA(255, 120, 150, 120))
                c.ellipse(X(10.5), hy + 10 * k, 3.2 * k, 1.5 * k, RGBA(255, 120, 150, 120))
                if act { c.ellipse(X(0), hy + 11.5 * k, 2.0 * k, 1.7 * k, RGBA(170, 60, 75), ink: 0.8) }
                else { c.curve([(X(-2), hy + 11.4 * k), (X(0), hy + 12.4 * k), (X(2), hy + 11.4 * k)], 1.1, RGBA(170, 70, 80)) }
            }
        }

        // front hair: a crown and bangs in locks, with a highlight band (the "angel ring")
        if back {
            c.ellipse(X(0), hy - 1, 16.5 * k, 16 * k, hair, ink: 1.6, shade: Shade(shadow: 0.24, cut: 0.3))
            c.curve([(X(-9), hy - 6 * k), (X(0), hy - 9 * k), (X(9), hy - 6 * k)], 2.0, hairLight)
        } else {
            let crown: [(Double, Double)] = side
                ? [(X(-16.5), hy + 9 * k), (X(-16), hy - 9 * k), (X(-6), hy - 16.5 * k), (X(8), hy - 15.5 * k), (X(16), hy - 7 * k), (X(14.5), hy - 3.5 * k),
                   (X(11.5), hy - 7.5 * k), (X(8.5), hy - 3.5 * k), (X(5), hy - 8 * k), (X(1.5), hy - 3 * k), (X(-2), hy - 2 * k), (X(-4), hy + 4 * k), (X(-8), hy + 11 * k)]
                : [(X(-16.5), hy + 5 * k), (X(-16), hy - 9 * k), (X(-7), hy - 16.5 * k), (X(7), hy - 16.5 * k), (X(16), hy - 9 * k), (X(16.5), hy + 5 * k),
                   (X(13), hy - 3 * k), (X(10), hy - 8.5 * k), (X(7), hy - 3.5 * k), (X(3.5), hy - 9 * k), (X(0), hy - 4 * k), (X(-3.5), hy - 9 * k), (X(-7), hy - 3.5 * k), (X(-10), hy - 8.5 * k), (X(-13), hy - 3 * k)]
            c.poly(crown, hair, ink: 1.6, shade: Shade(shadow: 0.22, light: 0.0, cut: 0.35))
            c.curve(side ? [(X(-10), hy - 9 * k), (X(-1), hy - 13 * k), (X(8), hy - 11 * k)] : [(X(-10), hy - 9.5 * k), (X(0), hy - 12.5 * k), (X(10), hy - 9.5 * k)], 2.2, hairLight)
            // side locks framing the face
            if !side {
                let len: Double = style == 2 ? 12 : (female ? 14 : 6)
                for s in [-1.0, 1.0] { c.poly([(X(s * 16.5), hy - 3 * k), (X(s * 14), hy - 1 * k), (X(s * 15), hy + len * k), (X(s * 17.5), hy + (len - 3) * k)], hair, ink: 1.3) }
            }
        }
        // styles: spikes, an ahoge, a ribbon
        if style == 1 && !female {
            for i in 0..<4 { let x = -9.0 + Double(i) * 6; c.poly([(X(x - 3), hy - 14 * k), (X(x + 1), hy - 23 * k), (X(x + 3.5), hy - 13 * k)], hair, ink: 1.3, shade: cel) }
        }
        if style == 3 {
            c.curve([(X(1), hy - 15 * k), (X(3), hy - 22 * k), (X(7), hy - 23 * k), (X(5), hy - 19 * k)], 2.0, hair)
            if female && !back {
                let rb = RGBA(255, 92, 128)
                c.poly([(X(8), hy - 15 * k), (X(14), hy - 20 * k), (X(14), hy - 11 * k)], rb, ink: 1.2)
                c.poly([(X(8), hy - 15 * k), (X(2), hy - 20 * k), (X(3), hy - 11 * k)], rb, ink: 1.2)
                c.ellipse(X(8), hy - 15 * k, 2 * k, 2 * k, RGBA(255, 210, 90), ink: 0.9)
            }
        }

        // something in the hand
        if !held.isEmpty {
            let hx = side ? (act ? X(19) : X(13 + walk * 2)) : (act ? X(19) : X(13))
            let hy2 = act ? Y(38) : Y(60)
            heldItem(&c, held, hx, hy2, k)
        }
        return c.image()
    }

    /// The iris colour: cool or warm with the hair, always clear and bright.
    static func irisColor(_ hair: RGBA) -> RGBA {
        let warm = Int(hair.r) > Int(hair.b) + 30
        return warm ? RGBA(214, 120, 52) : RGBA(70, 120, 230)
    }

    /// A big anime eye: lashes above, a tall iris darker at the top, a pupil, two highlights.
    static func eye(_ c: inout Canvas, _ x: Double, _ y: Double, _ k: Double, _ iris: RGBA, side: Bool) {
        let w = (side ? 3.6 : 4.6) * k, h = 6.0 * k
        c.ellipse(x, y, w, h, .white)
        c.ellipse(x, y + 0.6 * k, w * 0.82, h * 0.86, iris, shade: Shade(shadow: 0.0, light: 0.3, cut: 2, glint: 0.2))
        c.paint(x - w, y - h, x + w, y, inside: { px, py in let u = (px - x) / (w * 0.82), v = (py - y - 0.6 * k) / (h * 0.86); return u * u + v * v <= 1 && py < y - 1 * k },
                color: { _, _ in shadowed(iris, 0.35) })                                                // the shade under the lid
        c.ellipse(x, y + 1.2 * k, w * 0.4, h * 0.45, RGBA(30, 24, 48))                               // the pupil
        c.ellipse(x - w * 0.35, y - h * 0.35, w * 0.32, w * 0.32, .white)                             // highlights
        c.ellipse(x + w * 0.3, y + h * 0.35, w * 0.16, w * 0.16, RGBA(255, 255, 255, 220))
        // the upper lashes: a thick ink arc with a flick at the outer corner
        c.curve([(x - w - 0.6, y - h * 0.45), (x - w * 0.4, y - h - 0.5), (x + w * 0.4, y - h - 0.5), (x + w + 0.6, y - h * 0.45)], 1.6 * k, AnimeArt.ink)
        c.line(x + w + 0.4, y - h * 0.45, x + w + 1.8 * k, y - h * 0.65, 1.1 * k, AnimeArt.ink)
        c.line(x - w * 0.4, y + h + 0.3, x + w * 0.4, y + h + 0.3, 0.9, RGBA(120, 80, 90))          // the lower lid
    }

    static func heldItem(_ c: inout Canvas, _ kind: String, _ x: Double, _ y: Double, _ k: Double) {
        let steel = RGBA(214, 222, 236), wood = RGBA(150, 100, 60)
        switch kind {
        case "sword":
            c.line(x, y, x + 2 * k, y - 22 * k, 3.2 * k, steel, ink: 1.2)
            c.line(x - 4 * k, y - 2 * k, x + 4 * k, y - 2.5 * k, 2.2 * k, RGBA(230, 190, 70), ink: 1)
        case "staff":
            c.line(x, y + 8 * k, x + 1 * k, y - 22 * k, 2.6 * k, wood, ink: 1.1)
            c.ellipse(x + 1 * k, y - 24 * k, 3.6 * k, 3.6 * k, RGBA(140, 230, 255), ink: 1.1, shade: Shade())
        case "axe":
            c.line(x, y + 4 * k, x + 2 * k, y - 14 * k, 2.4 * k, wood, ink: 1)
            c.poly([(x + 2 * k, y - 15 * k), (x + 9 * k, y - 17 * k), (x + 9 * k, y - 8 * k), (x + 2 * k, y - 10 * k)], steel, ink: 1.1, shade: Shade())
        case "pick", "pickaxe":
            c.line(x, y + 4 * k, x + 1 * k, y - 14 * k, 2.4 * k, wood, ink: 1)
            c.curve([(x - 8 * k, y - 11 * k), (x + 1 * k, y - 16 * k), (x + 10 * k, y - 11 * k)], 2.6 * k, steel)
        case "hoe":
            c.line(x, y + 4 * k, x + 1 * k, y - 15 * k, 2.4 * k, wood, ink: 1)
            c.rect(x + 1 * k, y - 16 * k, 6 * k, 3 * k, steel, ink: 1)
        case "bow":
            c.curve([(x + 2 * k, y - 14 * k), (x + 7 * k, y - 4 * k), (x + 2 * k, y + 6 * k)], 2.2 * k, wood)
            c.line(x + 2 * k, y - 14 * k, x + 2 * k, y + 6 * k, 0.8, .white)
        case "torch":
            c.line(x, y + 4 * k, x + 1 * k, y - 10 * k, 2.4 * k, wood, ink: 1)
            flame(&c, x + 1 * k, y - 13 * k, 4 * k)
        case "gun", "rifle":
            c.rect(x - 2 * k, y - 4 * k, 14 * k, 4 * k, RGBA(70, 74, 86), ink: 1.1, radius: 1)
        default:
            c.ellipse(x, y - 3 * k, 3.4 * k, 3.4 * k, RGBA(240, 200, 90), ink: 1.1, shade: Shade())
        }
    }

    static func flame(_ c: inout Canvas, _ x: Double, _ y: Double, _ r: Double) {
        c.poly([(x - r, y + r), (x - r * 0.6, y - r * 0.4), (x, y - r * 2.2), (x + r * 0.6, y - r * 0.4), (x + r, y + r)], RGBA(255, 140, 40), ink: 1.0)
        c.poly([(x - r * 0.5, y + r * 0.8), (x, y - r * 1.1), (x + r * 0.5, y + r * 0.8)], RGBA(255, 230, 120))
    }

    // MARK: tiles

    /// The anime tile atlas: the same 16 x 16 grid of cells as the pixel atlas, each cell twice the size.
    public static let atlas: Bitmap = {
        var img = Bitmap(16 * cell, 16 * cell)
        for t in Content.shared.tiles {
            guard let t = t else { continue }
            let tile = AnimeArt.tile(t)
            img.blit(tile, sx: 0, sy: 0, sw: cell, sh: cell, dx: (t.id % 16) * cell, dy: (t.id / 16) * cell, blend: false)
        }
        return img
    }()

    /// One tile painted (64 x 64): ground fills the cell from (0, 0) to (32, 32); a standing thing stands on the
    /// cell's bottom half like the pixel art's (its foot at y 32 + 32).
    public static func tile(_ t: TileDef) -> Bitmap {
        let c1 = pastel(RGBA(hex: t.c1))
        let c2 = t.c2.isEmpty ? shadowed(c1, 0.2) : pastel(RGBA(hex: t.c2))
        let c3 = t.c3.isEmpty ? c1.lightened(0.25) : pastel(RGBA(hex: t.c3))
        var c = Canvas(cell, cell)
        var r = RNG(seed: t.id &* 977)
        let kind = t.artKind
        if t.layer == 0 || (t.layer == 1 && kind != "cliff") {
            // ground: a flat cel base, soft painted detail, never an ink line (so tiles join seamlessly)
            let g = 32.0
            switch kind {
            case "grass":
                c.rect(0, 0, g, g, c1)
                for _ in 0..<5 { c.ellipse(r.range(2, g - 2), r.range(2, g - 2), r.range(2.5, 4.5), r.range(1.5, 2.6), shadowed(c1, 0.06)) }
                for _ in 0..<9 {
                    let x = r.range(1, g - 1), y = r.range(4, g - 1), hgt = r.range(2.5, 5)
                    c.curve([(x, y), (x + r.range(-1, 1), y - hgt * 0.6), (x + r.range(-1.5, 1.5), y - hgt)], 0.9, r.unit() < 0.5 ? shadowed(c1, 0.22) : c1.lightened(0.18))
                }
                if r.unit() < 0.6 { c.ellipse(r.range(4, 28), r.range(4, 28), 1.1, 1.1, c3) }
            case "water":
                c.rect(0, 0, g, g, c1)
                for (yy, xx) in [(7.0, 4.0), (17, 15), (26, 6)] { c.curve([(xx, yy), (xx + 4, yy - 1.2), (xx + 8, yy), (xx + 12, yy - 1)], 1.1, RGBA(255, 255, 255, 170)) }
                c.ellipse(24, 10, 1.0, 1.0, .white)
            case "planks":
                c.rect(0, 0, g, g, c1)
                for i in 0..<4 { let y = Double(i) * 8; c.rect(0, y + 7, g, 1, shadowed(c1, 0.3)); c.curve([(2, y + 3), (12, y + 3.6), (22, y + 2.8)], 0.6, shadowed(c1, 0.15)) }
                for i in 0..<4 { c.rect(Double((i * 11 + 5) % 30), Double(i) * 8, 1, 7, shadowed(c1, 0.25)) }
            case "bricks", "cobble":
                c.rect(0, 0, g, g, shadowed(c1, 0.25))
                for row in 0..<3 {
                    let y = Double(row) * 10.7, off = row % 2 == 0 ? 0.0 : 6.5
                    var x = -off
                    while x < g { c.rect(x + 0.6, y + 0.6, 12, 9.4, c1, radius: 2.2, shade: Shade(shadow: 0.12, light: 0.12, cut: 0.6, glint: -0.5)); x += 13 }
                }
            case "rows":
                c.rect(0, 0, g, g, c1)
                for y in [3.0, 11, 19, 27] { c.rect(0, y, g, 3, shadowed(c1, 0.22), radius: 1.4); c.rect(0, y - 1, g, 1, c1.lightened(0.15)) }
            case "bridge":
                c.rect(0, 0, g, g, c1)
                for x in [0.0, 8, 16, 24] { c.rect(x, 0, 1.2, g, shadowed(c1, 0.3)) }
                c.rect(0, 0, g, 2, c2, radius: 1); c.rect(0, g - 2, g, 2, c2, radius: 1)
            case "ice":
                c.rect(0, 0, g, g, c1)
                c.line(4, 10, 14, 6, 1.0, .white); c.line(18, 24, 26, 18, 1.0, RGBA(255, 255, 255, 180))
            case "asphalt", "highway":
                c.rect(0, 0, g, g, c1)
                for _ in 0..<14 { c.ellipse(r.range(0, g), r.range(0, g), 0.6, 0.6, shadowed(c1, 0.15)) }
                c.rect(14.5, 3, 3, 9, c3, radius: 1); c.rect(14.5, 20, 3, 9, c3, radius: 1)
                if kind == "highway" { c.rect(0, 0, g, 1.6, c3); c.rect(0, g - 1.6, g, 1.6, c3) }
            case "rail":
                c.rect(0, 0, g, g, c1)
                for x in [2.0, 12, 22] { c.rect(x, 0, 6, g, c3, radius: 1.2, shade: Shade()) }
                c.rect(0, 8, g, 3, c2, shade: Shade(shadow: 0.15)); c.rect(0, 21, g, 3, c2, shade: Shade(shadow: 0.15))
            case "runway":
                c.rect(0, 0, g, g, c1)
                c.rect(0, 14, 8, 4, c3); c.rect(16, 14, 8, 4, c3); c.rect(0, 0, g, 1.6, c3); c.rect(0, g - 1.6, g, 1.6, c3)
            case "parking":
                c.rect(0, 0, g, g, c1); c.rect(0, 0, 1.6, 14, c3); c.rect(16, 0, 1.6, 14, c3)
            case "quay":
                c.rect(0, 0, g, g, c1)
                c.rect(0, 15, g, 1, shadowed(c1, 0.25)); c.rect(0, 28, g, 4, c3)
            default:
                // sand, dirt, snow, stone, mud...: the base with soft dabs of its second and third colours
                c.rect(0, 0, g, g, c1)
                for _ in 0..<4 { c.ellipse(r.range(2, g - 2), r.range(2, g - 2), r.range(3, 5), r.range(1.8, 3), shadowed(c1, 0.05)) }
                for _ in 0..<10 { c.ellipse(r.range(1, g - 1), r.range(1, g - 1), r.range(0.7, 1.6), r.range(0.5, 1.1), r.unit() < 0.7 ? c2 : c3) }
            }
            return c.image()
        }
        // standing things: drawn in the cell's lower part like the pixel art (base at bx..bx+32, foot at by+32)
        let bx = 16.0, by = 32.0
        switch kind {
        case "cliff":
            c.rect(bx, by - 16, 32, 48, shadowed(c2, 0.05), ink: 1.4, radius: 3)
            c.rect(bx, by - 16, 32, 18, c1, ink: 1.4, radius: 3, shade: Shade(shadow: 0.1))
            for _ in 0..<4 { let x = bx + r.range(4, 28), y = by + r.range(6, 28); c.line(x, y, x + r.range(-4, 4), y + r.range(3, 6), 1.0, shadowed(c2, 0.3)) }
        case "tree", "leaves":
            c.ellipse(bx + 16, by + 30, 13, 3.5, RGBA(0, 0, 0, 55))
            c.rect(bx + 13, by + 12, 6, 19, c3, ink: 1.5, radius: 2, shade: Shade(shadow: 0.25))
            // foliage: three cel-shaded puffs, darker below, a light band above
            for (dx, dy, rr) in [(-6.0, 0.0, 10.5), (7.0, 0.5, 10.0), (0.5, -8.0, 11.5)] {
                c.ellipse(bx + 16 + dx, by + dy, rr, rr * 0.92, c1, ink: 1.6)
            }
            for (dx, dy, rr) in [(-6.0, 0.0, 10.5), (7.0, 0.5, 10.0), (0.5, -8.0, 11.5)] {
                c.ellipse(bx + 16 + dx, by + dy, rr - 0.2, rr * 0.92 - 0.2, c1, shade: Shade(shadow: 0.24, light: 0.2, cut: 0.15, glint: -0.45))
            }
            c.curve([(bx + 6, by - 12), (bx + 12, by - 17), (bx + 19, by - 16)], 1.4, c1.lightened(0.32))
        case "pine":
            c.ellipse(bx + 16, by + 30, 11, 3, RGBA(0, 0, 0, 55))
            c.rect(bx + 14, by + 20, 5, 11, c3, ink: 1.3, radius: 1.5)
            for i in 0..<3 {
                let top = by - 22 + Double(i) * 12, half = 7.5 + Double(i) * 3.5
                c.poly([(bx + 16, top), (bx + 16 + half, top + 16), (bx + 16 - half, top + 16)], i == 2 ? c2 : c1, ink: 1.5, shade: Shade(shadow: 0.24, light: 0.18, cut: 0.1, glint: -0.6))
            }
        case "deadtree":
            c.line(bx + 16, by + 30, bx + 16, by - 6, 5, c1, ink: 1.4)
            c.line(bx + 16, by + 4, bx + 7, by - 4, 3, c1, ink: 1.2); c.line(bx + 16, by, bx + 25, by - 8, 3, c1, ink: 1.2)
        case "cactus":
            c.rect(bx + 12, by + 2, 8, 29, c1, ink: 1.4, radius: 4, shade: Shade())
            c.rect(bx + 4, by + 8, 6, 12, c1, ink: 1.3, radius: 3); c.rect(bx + 22, by + 4, 6, 12, c1, ink: 1.3, radius: 3)
        case "bush", "berrybush":
            c.ellipse(bx + 16, by + 30, 11, 3, RGBA(0, 0, 0, 50))
            c.ellipse(bx + 16, by + 20, 12, 10, c1, ink: 1.5, shade: Shade(shadow: 0.24, light: 0.18))
            if kind == "berrybush" { for p in [(10.0, 17.0), (19, 14), (16, 23), (23, 21)] { c.ellipse(bx + p.0, by + p.1, 1.8, 1.8, c3, ink: 0.8) } }
        case "rock", "ore":
            c.ellipse(bx + 16, by + 30, 11, 3, RGBA(0, 0, 0, 50))
            c.poly([(bx + 5, by + 29), (bx + 7, by + 16), (bx + 15, by + 11), (bx + 25, by + 14), (bx + 28, by + 28)], c1, ink: 1.5, shade: Shade(shadow: 0.26, light: 0.2))
            if kind == "ore" { for p in [(12.0, 20.0), (19, 17), (16, 25)] { c.ellipse(bx + p.0, by + p.1, 1.8, 1.8, c3, ink: 0.8) } }
        case "wall":
            // a block: the top face light, the front face with its courses
            c.rect(bx, by - 12, 32, 44, c2, ink: 1.5, radius: 1.5)
            c.rect(bx, by - 12, 32, 15, c1.lightened(0.12), ink: 1.2, radius: 1.5)
            for y in [by + 9, by + 19] { c.rect(bx + 1, y, 30, 1, shadowed(c2, 0.3)) }
            c.rect(bx + 1, by + 5, 30, 1.6, RGBA(255, 255, 255, 60))
        case "door":
            c.rect(bx + 4, by - 8, 24, 40, c2, ink: 1.5, radius: 3)
            c.rect(bx + 6, by - 6, 20, 37, c1, radius: 2, shade: Shade(shadow: 0.15))
            c.ellipse(bx + 22, by + 14, 1.8, 1.8, RGBA(240, 200, 80), ink: 0.8)
        case "fence", "gate":
            c.rect(bx, by + 12, 32, 3, c1, ink: 1.2); c.rect(bx, by + 21, 32, 3, c1, ink: 1.2)
            for x in [2.0, 14, 26] { c.rect(bx + x, by + 6, 4, 24, c2, ink: 1.2, radius: 1.5) }
        case "crop":
            let stage = Double(t.stage)
            for x in [5.0, 14, 23] {
                c.line(bx + x, by + 30, bx + x, by + 26 - stage * 7, 1.8, c1)
                if stage >= 1 { c.ellipse(bx + x + 2, by + 26 - stage * 6, 2.4, 1.3, c1.lightened(0.15)) }
                if stage >= 2 { c.ellipse(bx + x, by + 10, 2.6, 4.2, c3, ink: 0.9, shade: Shade()) }
            }
        case "flower":
            for (px, py) in [(10.0, 22.0), (20, 18), (24, 27)] {
                c.line(bx + px, by + py + 2, bx + px, by + py + 8, 1.1, RGBA(90, 170, 90))
                for a in 0..<5 { let ang = Double(a) / 5 * 2 * .pi; c.ellipse(bx + px + cos(ang) * 2.3, by + py + sin(ang) * 2.3, 1.7, 1.7, c1, ink: 0.6) }
                c.ellipse(bx + px, by + py, 1.2, 1.2, RGBA(255, 220, 90))
            }
        case "tuft":
            for i in 0..<5 { let x = bx + 8 + Double(i) * 4; c.curve([(x, by + 30), (x + 1, by + 24), (x + 3, by + 20)], 1.2, i % 2 == 0 ? c1 : c1.lightened(0.2)) }
        case "pebbles":
            for (px, py, rr) in [(10.0, 26.0, 2.6), (19, 28, 2.0), (24, 24, 1.6)] { c.ellipse(bx + px, by + py, rr, rr * 0.8, c1, ink: 0.8, shade: Shade()) }
        case "sapling":
            c.line(bx + 16, by + 30, bx + 16, by + 18, 1.6, c3)
            c.ellipse(bx + 13, by + 18, 3.4, 2.2, c1, ink: 0.9); c.ellipse(bx + 19, by + 16, 3.4, 2.2, c1, ink: 0.9)
        case "mushroom":
            c.rect(bx + 14, by + 22, 4, 8, RGBA(245, 235, 220), ink: 1)
            c.ellipse(bx + 16, by + 21, 7, 4.5, c1, ink: 1.2, shade: Shade())
            c.ellipse(bx + 13.5, by + 19.5, 1.2, 1.2, .white); c.ellipse(bx + 18, by + 20, 1, 1, .white)
        case "lily":
            c.ellipse(bx + 16, by + 24, 7, 4, c1, ink: 1, shade: Shade()); c.ellipse(bx + 18, by + 22, 1.8, 1.8, RGBA(255, 170, 200))
        case "campfire", "torch", "lamp", "lantern", "moonlantern", "furnace":
            if kind == "campfire" {
                c.line(bx + 7, by + 28, bx + 25, by + 24, 3, RGBA(130, 85, 50), ink: 1); c.line(bx + 7, by + 24, bx + 25, by + 28, 3, RGBA(120, 78, 46), ink: 1)
                flame(&c, bx + 16, by + 20, 5.5)
            } else if kind == "furnace" {
                c.rect(bx + 3, by + 2, 26, 29, c1, ink: 1.5, radius: 3, shade: Shade())
                c.rect(bx + 9, by + 14, 14, 10, RGBA(60, 40, 40), ink: 1, radius: 2); flame(&c, bx + 16, by + 20, 3.5)
            } else {
                let h: Double = kind == "torch" ? 18 : 34
                c.line(bx + 16, by + 31, bx + 16, by + 31 - h, 3, c2, ink: 1.1)
                if kind == "torch" { flame(&c, bx + 16, by + 31 - h - 3, 4) }
                else { c.rect(bx + 10, by + 31 - h - 9, 12, 10, RGBA(255, 236, 150), ink: 1.3, radius: 3); c.ellipse(bx + 16, by + 31 - h - 4, 7, 7, RGBA(255, 240, 170, 70)) }
            }
        case "chest", "crate", "barrel", "table", "desk", "workbench", "bookshelf", "chair", "bed", "kitchen", "machine", "server", "stall":
            // furniture and boxes: a rounded block, a light top, a few lines of its own
            c.ellipse(bx + 16, by + 30, 13, 3, RGBA(0, 0, 0, 45))
            let tall = ["bookshelf", "server", "machine"].contains(kind)
            let top = tall ? by - 6 : by + 8
            c.rect(bx + 3, top, 26, by + 30 - top, c2, ink: 1.5, radius: 3)
            c.rect(bx + 3, top, 26, 7, c1.lightened(0.1), ink: 1.1, radius: 3)
            switch kind {
            case "chest": c.rect(bx + 3, top + 9, 26, 2, c3); c.rect(bx + 14, top + 8, 4, 5, RGBA(240, 200, 80), ink: 0.8, radius: 1)
            case "bookshelf": for row in 0..<3 { for b in 0..<5 { c.rect(bx + 5 + Double(b) * 4.6, top + 9 + Double(row) * 9, 3.6, 7, [RGBA(220, 90, 90), RGBA(90, 140, 220), RGBA(240, 200, 90), RGBA(110, 190, 120), RGBA(200, 120, 200)][(b + row) % 5], radius: 0.8) } }
            case "bed": c.rect(bx + 5, top + 2, 10, 5, .white, ink: 0.8, radius: 2); c.rect(bx + 3, top + 8, 26, 14, c1.lightened(0.2), radius: 3)
            case "server", "machine": for i in 0..<4 { c.rect(bx + 7, top + 10 + Double(i) * 7, 18, 3, RGBA(80, 230, 160)) }
            default: break
            }
        case "stairs":
            for i in 0..<4 { c.rect(bx + 2, by + 4 + Double(i) * 7, 28, 7, i % 2 == 0 ? c1 : c2, ink: 1, radius: 1) }
        case "well":
            c.ellipse(bx + 16, by + 22, 12, 8, c1, ink: 1.5, shade: Shade()); c.ellipse(bx + 16, by + 21, 8, 5, RGBA(60, 90, 140))
            c.line(bx + 5, by + 20, bx + 5, by - 2, 2.4, RGBA(130, 90, 55), ink: 1); c.line(bx + 27, by + 20, bx + 27, by - 2, 2.4, RGBA(130, 90, 55), ink: 1)
            c.poly([(bx + 2, by - 2), (bx + 16, by - 10), (bx + 30, by - 2)], RGBA(190, 80, 70), ink: 1.2, shade: Shade())
        case "tent":
            c.poly([(bx + 2, by + 30), (bx + 16, by + 2), (bx + 30, by + 30)], c1, ink: 1.5, shade: Shade(shadow: 0.25))
            c.poly([(bx + 12, by + 30), (bx + 16, by + 16), (bx + 20, by + 30)], shadowed(c1, 0.45))
        default:
            // not painted yet: the pixel tile, smoothed and inked
            var px = Bitmap(PixelArt.cell, PixelArt.cell)
            PixelArt.drawTile(&px, 0, 0, t)
            return px.anime()
        }
        return c.image()
    }

    // MARK: chunks

    /// The chunk image in the anime style (1056 x 1072): the same layout as `PixelArt.bakeChunk`, twice the size.
    public static func bakeChunk(layers: [[UInt8]]) -> Bitmap {
        let at = atlas, cl = cell
        var img = Bitmap((MP.chunkPx + 16) * 2, (MP.chunkPx + 24) * 2)
        let g = layers[0], st = layers[1], ob = layers[2], de = layers[3]
        let cliff = Content.shared.tid("cliff")
        for i in 0..<MP.chunkArea {
            let x = ((i % 32) * 16 + 8) * 2, y = ((i / 32) * 16 + 24) * 2
            img.blit(at, sx: (Int(g[i]) % 16) * cl, sy: (Int(g[i]) / 16) * cl, sw: 32, sh: 32, dx: x, dy: y, blend: false)
            if st[i] != 0 && st[i] != cliff {
                img.blit(at, sx: (Int(st[i]) % 16) * cl, sy: (Int(st[i]) / 16) * cl, sw: 32, sh: 32, dx: x, dy: y, blend: false)
            }
        }
        for i in 0..<MP.chunkArea {
            let x = ((i % 32) * 16) * 2, y = ((i / 32) * 16 + 8) * 2
            for id in [de[i], st[i] == cliff ? cliff : 0, ob[i]] where id != 0 {
                img.blit(at, sx: (Int(id) % 16) * cl, sy: (Int(id) / 16) * cl, sw: cl, sh: cl, dx: x, dy: y, blend: true)
            }
        }
        return img
    }

    /// A storey in the anime style (see `PixelArt.bakeStorey`).
    public static func bakeStorey(layers: [[UInt8]], below: [[[UInt8]]]) -> Bitmap {
        var img = below.first.map { bakeChunk(layers: $0) } ?? Bitmap((MP.chunkPx + 16) * 2, (MP.chunkPx + 24) * 2)
        func dim(_ f: Double) { for i in 0..<(img.w * img.h) { let o = i * 4; img.px[o] = UInt8(Double(img.px[o]) * f); img.px[o + 1] = UInt8(Double(img.px[o + 1]) * f); img.px[o + 2] = UInt8(Double(img.px[o + 2]) * min(1, f * 1.1)) } }
        let at = atlas, cl = cell
        func lay(_ l: [[UInt8]]) {
            let g = l[0], st = l[1], ob = l[2], de = l[3]
            for i in 0..<MP.chunkArea where g[i] != 0 {
                let x = ((i % 32) * 16 + 8) * 2, y = ((i / 32) * 16 + 24) * 2
                img.blit(at, sx: (Int(g[i]) % 16) * cl, sy: (Int(g[i]) / 16) * cl, sw: 32, sh: 32, dx: x, dy: y, blend: false)
                if st[i] != 0 { img.blit(at, sx: (Int(st[i]) % 16) * cl, sy: (Int(st[i]) / 16) * cl, sw: 32, sh: 32, dx: x, dy: y, blend: false) }
            }
            for i in 0..<MP.chunkArea where g[i] != 0 {
                let x = ((i % 32) * 16) * 2, y = ((i / 32) * 16 + 8) * 2
                for id in [de[i], ob[i]] where id != 0 { img.blit(at, sx: (Int(id) % 16) * cl, sy: (Int(id) / 16) * cl, sw: cl, sh: cl, dx: x, dy: y, blend: true) }
            }
        }
        dim(0.55)
        for l in below.dropFirst() { lay(l); dim(0.8) }
        lay(layers)
        return img
    }

    /// Ground for the 3D view in the anime style (1024 x 1024: the painted 32 x 32 ground of every tile).
    public static func bakeGround(layers: [[UInt8]]) -> Bitmap {
        let at = atlas, cl = cell
        var img = Bitmap(MP.chunkPx * 2, MP.chunkPx * 2)
        let g = layers[0], st = layers[1]
        let cliff = Content.shared.tid("cliff")
        for i in 0..<MP.chunkArea {
            let x = (i % 32) * 32, y = (i / 32) * 32
            img.blit(at, sx: (Int(g[i]) % 16) * cl, sy: (Int(g[i]) / 16) * cl, sw: 32, sh: 32, dx: x, dy: y, blend: false)
            if st[i] != 0 && st[i] != cliff {
                img.blit(at, sx: (Int(st[i]) % 16) * cl, sy: (Int(st[i]) / 16) * cl, sw: 32, sh: 32, dx: x, dy: y, blend: false)
            }
        }
        return img
    }
}
