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
    /// The colour of ink lines (nil: the dark plum ink). Soft styles ink each part in a deeper tone of its own colour.
    public var inkColor: RGBA?
    public let w: Int, h: Int
    /// Output pixels per drawing unit: a figure drawn on a 64 x 80 plan with `k` 2 comes out 128 x 160, every
    /// line and highlight at twice the detail (the drawing code is the same; only the output is finer).
    public let k: Int
    static let ss = 3
    var sub: [UInt32]                 // RGBA8 per sub-pixel, 0 = empty

    public init(_ w: Int, _ h: Int, scale: Int = 1) {
        self.w = w; self.h = h; k = max(1, scale)
        sub = [UInt32](repeating: 0, count: w * h * k * k * Canvas.ss * Canvas.ss)
    }

    @inline(__always) static func pack(_ c: RGBA) -> UInt32 { UInt32(c.r) | UInt32(c.g) << 8 | UInt32(c.b) << 16 | UInt32(c.a) << 24 }
    @inline(__always) static func unpack(_ v: UInt32) -> RGBA { RGBA(UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8(v >> 24)) }

    /// Paint every sub-pixel inside the shape (with the colour the colour function gives there; nil leaves it).
    /// Colours with alpha below 255 are mixed over what is there.
    public mutating func paint(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, inside: (Double, Double) -> Bool, color: (Double, Double) -> RGBA?) {
        let s = Double(Canvas.ss * k), sw = w * Canvas.ss * k
        let ax = max(0, Int((x0 * s).rounded(.down))), bx = min(sw - 1, Int((x1 * s).rounded(.up)))
        let ay = max(0, Int((y0 * s).rounded(.down))), by = min(h * Canvas.ss * k - 1, Int((y1 * s).rounded(.up)))
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
            paint(cx - ex, cy - ey, cx + ex, cy + ey, inside: { x, y in let u = (x - cx) / ex, v = (y - cy) / ey; return u * u + v * v <= 1 }, color: { [ic = inkColor ?? AnimeArt.ink] _, _ in ic })
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
        if ink > 0 { paint(x - ink, y - ink, x + rw + ink, y + rh + ink, inside: { inRound($0, $1, ink) }, color: { [ic = inkColor ?? AnimeArt.ink] _, _ in ic }) }
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
            paint(b.0, b.1, b.2, b.3, inside: { inside(grown, $0, $1) }, color: { [ic = inkColor ?? AnimeArt.ink] _, _ in ic })
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
        if ink > 0 { paint(bx0, by0, bx1, by1, inside: { dist($0, $1) <= e }, color: { [ic = inkColor ?? AnimeArt.ink] _, _ in ic }) }
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
        let ow = w * k, oh = h * k
        var out = Bitmap(ow, oh)
        let s = Canvas.ss, sw = ow * s
        for y in 0..<oh { for x in 0..<ow {
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
    /// Figures are drawn on the 64 x 80 plan and come out this many times finer (2: 128 x 160 pixels). The app
    /// shows them at the plan's size, so they are as big as before with twice the detail in every line.
    public static var figureScale = 2

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
    /// A turn step ("t0" ... "t15", see AnimeTurn.swift) gives the figure turned to that angle.
    public static func character(_ look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool) -> Bitmap {
        if let step = turnIndex(dir) {
            // the model figures are drawn in the four views only: the nearest one (mirrored to the left)
            if look.anim == nil && CharacterModels.of(look.model) != nil {
                let v = cardinal(step)
                let pic = character(look, dir: v.dir, frame: frame, held: held, child: child, female: female)
                return v.mirrored ? mirrored(pic) : pic
            }
            return turned(look, step: step, frame: frame, held: held, child: child, female: female, kind: figure)
        }
        if look.anim == nil, let m = CharacterModels.of(look.model) {
            var plain = look; plain.model = nil
            return modelFigure(m, base: { character(plain, dir: dir, frame: frame, held: held, child: child, female: female) }, look: look, dir: dir, frame: frame, held: held, child: child, female: female)
        }
        // by the setting: the soft moe figure or the hero figure (the first chibi figure stays as `chibi`)
        switch figure {
        case .hero: return hero(look, dir: dir, frame: frame, held: held, child: child, female: female)
        case .moe: return moe(look, dir: dir, frame: frame, held: held, child: child, female: female)
        // the celestial costume is for grown-ups; a child keeps the moe clothes
        case .angel: return moe(look, dir: dir, frame: frame, held: held, child: child, female: female, angel: !child)
        }
    }

    /// The round-headed chibi figure (the first anime look).
    public static func chibi(_ look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool) -> Bitmap {
        var c = Canvas(charW, charH, scale: figureScale)
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
            case "basalt":
                c.rect(0, 0, g, g, c1)
                for _ in 0..<6 { c.ellipse(r.range(2, g - 2), r.range(2, g - 2), r.range(2, 4), r.range(1.2, 2.4), shadowed(c1, 0.2)) }
                c.line(r.range(2, 10), r.range(4, 28), r.range(14, 30), r.range(4, 28), 0.7, c2.darkened(0.3))
                if r.unit() < 0.5 { c.ellipse(r.range(4, 28), r.range(4, 28), 0.9, 0.9, c3) }
            case "lava":
                // a glowing pool: bright cores, crusted plates with dark cracks between, a few sparks
                c.rect(0, 0, g, g, c1)
                for _ in 0..<4 { c.ellipse(r.range(3, g - 3), r.range(3, g - 3), r.range(3, 6), r.range(2, 4), c3) }
                for _ in 0..<3 { c.ellipse(r.range(4, g - 4), r.range(4, g - 4), r.range(3, 5), r.range(2.5, 4), c2.darkened(0.35)) }
                for _ in 0..<3 { c.curve([(r.range(0, g), r.range(0, g)), (r.range(0, g), r.range(0, g)), (r.range(0, g), r.range(0, g))], 0.8, c2) }
                c.ellipse(r.range(6, 26), r.range(6, 26), 0.8, 0.8, RGBA(255, 250, 220))
            case "ufo_pad":
                c.rect(0, 0, g, g, c1)
                c.rect(0, 0, g, 1.2, c2); c.rect(0, 0, 1.2, g, c2); c.rect(0, 15.4, g, 1.2, c2); c.rect(15.4, 0, 1.2, g, c2)
                for (x, y) in [(7.0, 7.0), (23, 23)] { c.ellipse(x, y, 2.2, 2.2, c3); c.ellipse(x, y, 1.0, 1.0, .white) }
                c.line(2, 30, 12, 20, 0.6, RGBA(255, 255, 255, 120))
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
            if t.key == "wall_glass" {
                c.rect(bx, by - 12, 32, 44, c2, ink: 1.5, radius: 1.5, shade: Shade(shadow: 0.2))
                c.rect(bx, by - 12, 32, 15, c1.lightened(0.15), ink: 1.2, radius: 1.5)
                for x in [0.0, 10.5, 21] { c.rect(bx + x + 1, by + 4, 9, 26, c1.lightened(0.05), ink: 0.8, radius: 1) }
                c.poly([(bx + 3, by + 26), (bx + 8, by + 6), (bx + 11, by + 6), (bx + 6, by + 26)], RGBA(255, 255, 255, 110))
            } else if t.key == "marble_wall" {
                // white marble: a fluted pilaster each side, a gold band under the cornice and a gold rosette
                c.rect(bx, by - 12, 32, 15, c1.lightened(0.1), ink: 1.2, radius: 1.5)
                c.rect(bx, by + 1, 32, 2.4, c3, ink: 0.6)
                for x in [2.0, 24] { c.rect(bx + x, by + 5, 6, 26, c1, ink: 0.9, radius: 1); for f in [1.5, 3, 4.5] { c.line(bx + x + f, by + 7, bx + x + f, by + 29, 0.4, shadowed(c1, 0.25)) } }
                c.ellipse(bx + 16, by + 16, 3.4, 3.4, c3, ink: 0.7, shade: Shade(shadow: 0.25)); c.ellipse(bx + 16, by + 16, 1.2, 1.2, c1)
            } else if t.key == "wall_concrete" {
                c.rect(bx + 6, by + 8, 20, 13, c3, ink: 1.1, radius: 1, shade: Shade(shadow: 0.25))
                c.rect(bx + 15.4, by + 8, 1.2, 13, c2)
                c.rect(bx + 8, by + 10, 4, 2, RGBA(255, 255, 255, 120))
            } else if t.key == "wall_limestone" {
                c.rect(bx, by - 12, 32, 44, c1, ink: 1.5, radius: 1.5, shade: Shade(shadow: 0.14, light: 0.1))
                c.rect(bx, by - 12, 32, 15, c1.lightened(0.12), ink: 1.2, radius: 1.5)
                for x in [1.0, 25] { c.rect(bx + x, by + 4, 6, 27, c2, ink: 1, radius: 1) }
                c.rect(bx + 10, by + 6, 12, 22, c3, ink: 1.1, radius: 1, shade: Shade(shadow: 0.2))
                c.rect(bx + 10, by + 16, 12, 1.6, c1)
                c.poly([(bx + 12, by + 26), (bx + 15, by + 8), (bx + 17, by + 8), (bx + 14, by + 26)], RGBA(255, 255, 255, 80))
            } else if t.key == "wall_deco" {
                c.rect(bx, by - 12, 32, 44, c1, ink: 1.5, radius: 1.5, shade: Shade(shadow: 0.14, light: 0.1))
                c.rect(bx, by - 12, 32, 15, c1.lightened(0.12), ink: 1.2, radius: 1.5)
                c.rect(bx + 1, by + 4, 30, 2, c3, ink: 0.8); c.rect(bx + 1, by + 28, 30, 2, c3, ink: 0.8)
                c.poly([(bx + 5, by + 9), (bx + 16, by + 20), (bx + 27, by + 9), (bx + 27, by + 13), (bx + 16, by + 24), (bx + 5, by + 13)], c3, ink: 1)
                c.rect(bx + 14, by + 21, 4, 7, c2, ink: 0.8)
            } else if t.key == "wall_brownstone" {
                c.rect(bx, by - 12, 32, 44, c1, ink: 1.5, radius: 1.5, shade: Shade(shadow: 0.2, light: 0.12))
                c.rect(bx, by - 12, 32, 15, c1.lightened(0.14), ink: 1.2, radius: 1.5)
                c.rect(bx + 6, by + 3, 20, 3, RGBA(hex: "#e0d0b0"), ink: 1)
                c.rect(bx + 8, by + 6, 16, 22, c3, ink: 1.1, radius: 1)
                c.rect(bx + 8, by + 16, 16, 1.6, RGBA(hex: "#e0d0b0")); c.rect(bx + 15.4, by + 6, 1.2, 22, RGBA(hex: "#e0d0b0"))
                c.rect(bx + 10, by + 8, 3, 6, RGBA(255, 255, 255, 90))
            } else if t.key == "spire_steel" {
                c.rect(bx, by - 12, 32, 44, c2, ink: 1.5, radius: 1.5, shade: Shade(shadow: 0.25, light: 0.2))
                c.rect(bx, by - 12, 32, 15, c1, ink: 1.2, radius: 1.5)
                for x in [4.0, 12, 20, 28] { c.rect(bx + x, by + 4, 1.4, 27, c3) }
                c.rect(bx + 7, by + 6, 2, 12, RGBA(255, 255, 255, 200))
            }
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
        case "star":
            // a fallen star fragment: a glowing five-point star with a halo
            c.ellipse(bx + 16, by + 20, 11, 11, RGBA(255, 240, 160, 70))
            var pts: [(Double, Double)] = []
            for i in 0..<10 { let ang = Double(i) * .pi / 5 - .pi / 2, rr = i % 2 == 0 ? 9.5 : 4.0; pts.append((bx + 16 + cos(ang) * rr, by + 20 + sin(ang) * rr)) }
            c.poly(pts, RGBA(255, 226, 110), ink: 1.2, shade: Shade(shadow: 0.15, light: 0.25))
            c.ellipse(bx + 13, by + 16, 1.6, 1.6, .white)
        case "anvil":
            c.ellipse(bx + 16, by + 30, 11, 2.5, RGBA(0, 0, 0, 50))
            c.rect(bx + 11, by + 18, 10, 12, RGBA(90, 70, 50), ink: 1.2, radius: 1, shade: Shade())
            c.poly([(bx + 3, by + 12), (bx + 29, by + 12), (bx + 26, by + 19), (bx + 8, by + 19), (bx + 2, by + 15)], c1, ink: 1.4, shade: Shade(shadow: 0.25))
            c.rect(bx + 6, by + 12, 18, 2, c1.lightened(0.3))
        case "campfire_out":
            c.line(bx + 7, by + 28, bx + 25, by + 24, 3, RGBA(70, 60, 55), ink: 1); c.line(bx + 7, by + 24, bx + 25, by + 28, 3, RGBA(60, 52, 48), ink: 1)
            for (x, y) in [(13.0, 22.0), (18, 20), (16, 25)] { c.ellipse(bx + x, by + y, 2, 1.5, RGBA(120, 116, 118)) }
            c.curve([(bx + 16, by + 18), (bx + 14, by + 12), (bx + 18, by + 6)], 1.2, RGBA(200, 200, 210, 140))
        case "well_broken":
            c.ellipse(bx + 16, by + 22, 12, 8, shadowed(c1, 0.2), ink: 1.5, shade: Shade()); c.ellipse(bx + 16, by + 21, 8, 5, RGBA(40, 44, 50))
            c.line(bx + 5, by + 20, bx + 5, by + 6, 2.4, RGBA(110, 80, 55), ink: 1)
            c.line(bx + 27, by + 20, bx + 24, by + 10, 2.4, RGBA(110, 80, 55), ink: 1)
            c.rect(bx + 20, by + 26, 6, 3, shadowed(c1, 0.3), ink: 0.8, radius: 1)
        case "sign":
            c.rect(bx + 14.5, by + 12, 3, 19, RGBA(120, 82, 50), ink: 1.1, radius: 1)
            c.rect(bx + 4, by + 2, 24, 13, c1, ink: 1.4, radius: 2, shade: Shade(shadow: 0.18))
            for y in [6.0, 10] { c.line(bx + 8, by + y, bx + 24, by + y, 1.0, shadowed(c1, 0.45)) }
        case "pillar":
            c.rect(bx + 8, by - 4, 16, 34, c1, ink: 1.4, radius: 1.5, shade: Shade(shadow: 0.22))
            c.rect(bx + 5, by - 7, 22, 5, c1.lightened(0.1), ink: 1.2, radius: 1.5); c.rect(bx + 5, by + 27, 22, 4, shadowed(c1, 0.15), ink: 1.2, radius: 1)
            for x in [12.0, 16, 20] { c.line(bx + x, by - 1, bx + x, by + 26, 0.8, shadowed(c1, 0.3)) }
            c.line(bx + 10, by + 6, bx + 14, by + 12, 1.0, shadowed(c1, 0.5))       // a crack
        case "wing":
            // an angel's wing on a sky house: from the wall beside it (west for an east wing) up and out, the
            // long white flight feathers hanging in a fan, gold coverts along the top
            let s: Double = t.key.hasSuffix("_w") ? -1 : 1
            func W(_ x: Double, _ y: Double) -> (Double, Double) { (bx + 16 + s * (x - 16), by + y) }
            c.inkColor = shadowed(c2, 0.4)
            soft(&c, [W(0, 14), W(6, 2), W(16, -10), W(28, -16), W(32, -12), W(31, -2), W(28, 10), W(23, 22), W(16, 30), W(9, 28), W(3, 22)], c1, ink: 1.2, light: 0.2, shadow: 0.18, rim: false)
            c.inkColor = nil
            for i in 0..<6 {
                let u = Double(i) / 5
                let a = W(6 + u * 20, 4 - u * 12), e = W(8 + u * 21, 28 - u * 26)
                c.line(a.0, a.1, e.0, e.1, 0.7, c2)
                c.ellipse(e.0, e.1, 2.2, 1.5, c1.lightened(0.1), ink: 0.5)
            }
            for i in 0..<5 { let u = Double(i) / 4; let p = W(4 + u * 22, 6 - u * 16); c.ellipse(p.0, p.1, 2.4, 1.7, i % 2 == 0 ? c3 : shadowed(c3, 0.25), ink: 0.5) }
        case "statue":
            c.rect(bx + 6, by + 22, 20, 9, shadowed(c1, 0.15), ink: 1.3, radius: 1.5, shade: Shade())
            c.ellipse(bx + 16, by - 4, 5, 5.5, c1, ink: 1.3, shade: Shade(shadow: 0.25))
            c.poly([(bx + 10, by + 22), (bx + 11, by + 4), (bx + 21, by + 4), (bx + 22, by + 22)], c1, ink: 1.3, shade: Shade(shadow: 0.25))
            c.line(bx + 21, by + 6, bx + 26, by - 6, 2.4, c1, ink: 1)            // a raised arm
        case "altar":
            c.rect(bx + 3, by + 14, 26, 17, c1, ink: 1.4, radius: 2, shade: Shade(shadow: 0.2))
            c.rect(bx + 1, by + 11, 30, 5, c1.lightened(0.12), ink: 1.2, radius: 1.5)
            c.ellipse(bx + 16, by + 8, 4, 3, t.key == "altar_pure" ? RGBA(200, 240, 255) : RGBA(255, 200, 120), ink: 1)
            c.ellipse(bx + 16, by + 6, 7, 7, t.key == "altar_pure" ? RGBA(200, 240, 255, 70) : RGBA(255, 200, 120, 70))
        case "pot":
            c.poly([(bx + 9, by + 18), (bx + 23, by + 18), (bx + 21, by + 30), (bx + 11, by + 30)], RGBA(196, 110, 80), ink: 1.3, shade: Shade())
            c.rect(bx + 8, by + 16, 16, 3, RGBA(210, 126, 92), ink: 1, radius: 1)
            for (x, col) in [(12.0, RGBA(240, 90, 110)), (16, RGBA(250, 210, 80)), (20, RGBA(120, 150, 250))] {
                c.line(bx + 16, by + 16, bx + x, by + 8, 1.0, RGBA(80, 150, 80)); c.ellipse(bx + x, by + 7, 2.4, 2.4, col, ink: 0.8)
            }
        case "scarecrow":
            c.line(bx + 16, by + 31, bx + 16, by + 2, 2.4, RGBA(130, 90, 55), ink: 1)
            c.line(bx + 4, by + 10, bx + 28, by + 10, 2.2, RGBA(130, 90, 55), ink: 1)
            c.poly([(bx + 9, by + 8), (bx + 23, by + 8), (bx + 21, by + 22), (bx + 11, by + 22)], c1, ink: 1.2, shade: Shade())
            c.ellipse(bx + 16, by + 3, 5, 5, RGBA(230, 200, 140), ink: 1.1, shade: Shade())
            c.poly([(bx + 8, by + 0), (bx + 24, by + 0), (bx + 16, by - 7)], RGBA(170, 130, 70), ink: 1.1)
            c.ellipse(bx + 14, by + 3, 0.9, 0.9, AnimeArt.ink); c.ellipse(bx + 18, by + 3, 0.9, 0.9, AnimeArt.ink)
        case "grave":
            c.ellipse(bx + 16, by + 30, 11, 2.5, RGBA(0, 0, 0, 45))
            c.rect(bx + 9, by + 8, 14, 22, c1, ink: 1.4, radius: 6, shade: Shade(shadow: 0.22))
            c.line(bx + 16, by + 12, bx + 16, by + 22, 1.4, shadowed(c1, 0.45)); c.line(bx + 12.5, by + 15, bx + 19.5, by + 15, 1.4, shadowed(c1, 0.45))
            c.ellipse(bx + 9, by + 30, 3, 1.5, RGBA(110, 170, 90))
        case "chimney":
            c.rect(bx + 9, by + 2, 14, 29, c1, ink: 1.4, radius: 1, shade: Shade(shadow: 0.2))
            for y in stride(from: 6.0, to: 30, by: 6) { c.line(bx + 9, by + y, bx + 23, by + y, 0.8, shadowed(c1, 0.35)) }
            c.rect(bx + 7, by - 1, 18, 4, shadowed(c1, 0.1), ink: 1.2, radius: 1)
            for (i, y) in [-6.0, -13, -20].enumerated() { c.ellipse(bx + 16 + Double(i) * 2, by + y, 4 + Double(i), 3 + Double(i) * 0.6, RGBA(220, 220, 228, 150)) }
        case "antenna":
            c.line(bx + 16, by + 31, bx + 16, by - 12, 1.8, c1, ink: 1)
            for (y, w) in [(-6.0, 6.0), (2, 9), (10, 12)] { c.line(bx + 16 - w, by + y, bx + 16 + w, by + y, 1.4, c1, ink: 0.8) }
            c.ellipse(bx + 16, by - 13, 2.2, 2.2, RGBA(255, 80, 80), ink: 0.8); c.ellipse(bx + 16, by - 13, 5, 5, RGBA(255, 80, 80, 60))
        case "ai_core":
            c.rect(bx + 4, by + 6, 24, 25, RGBA(60, 64, 80), ink: 1.4, radius: 4, shade: Shade(shadow: 0.25))
            c.ellipse(bx + 16, by + 17, 7, 7, RGBA(110, 220, 255), ink: 1.1, shade: Shade(shadow: 0.1, light: 0.3))
            c.ellipse(bx + 16, by + 17, 11, 11, RGBA(110, 220, 255, 60))
            for x in [8.0, 24] { c.rect(bx + x - 1, by + 9, 2, 2, RGBA(120, 255, 160)) }
        case "bones":
            for (x0, y0, x1, y1) in [(6.0, 26.0, 22.0, 20.0), (10, 20, 26, 28)] {
                c.line(bx + x0, by + y0, bx + x1, by + y1, 2.4, RGBA(236, 230, 214), ink: 1)
                for (x, y) in [(x0, y0), (x1, y1)] { c.ellipse(bx + x, by + y, 2.2, 2.2, RGBA(236, 230, 214), ink: 0.9) }
            }
            c.ellipse(bx + 22, by + 14, 5, 4.5, RGBA(236, 230, 214), ink: 1.1, shade: Shade())
            c.ellipse(bx + 20.5, by + 14, 1.1, 1.3, AnimeArt.ink); c.ellipse(bx + 23.5, by + 14, 1.1, 1.3, AnimeArt.ink)
        case "shell":
            var fan: [(Double, Double)] = [(bx + 16, by + 28)]
            for i in 0...8 { let ang = .pi + Double(i) * .pi / 8; fan.append((bx + 16 + cos(ang) * 10, by + 26 + sin(ang) * 9)) }
            c.poly(fan, c1, ink: 1.2, shade: Shade(shadow: 0.18))
            for i in 1...7 { let ang = .pi + Double(i) * .pi / 8; c.line(bx + 16, by + 27, bx + 16 + cos(ang) * 9, by + 26 + sin(ang) * 8, 0.8, shadowed(c1, 0.3)) }
        case "citygate", "citygate_open":
            // a stone gatehouse with a wooden gate, open or shut
            c.rect(bx - 4, by - 12, 40, 43, c1, ink: 1.6, radius: 2, shade: Shade(shadow: 0.2))
            for x in stride(from: -4.0, to: 36, by: 8) { c.rect(bx + x + 1, by - 18, 6, 7, c1.lightened(0.08), ink: 1.1, radius: 1) }     // battlements
            c.poly([(bx + 6, by + 31), (bx + 6, by + 6), (bx + 16, by - 2), (bx + 26, by + 6), (bx + 26, by + 31)], RGBA(40, 34, 40), ink: 1.2)
            if kind == "citygate" {
                c.poly([(bx + 6, by + 31), (bx + 6, by + 6), (bx + 16, by - 2), (bx + 26, by + 6), (bx + 26, by + 31)], RGBA(140, 95, 55), ink: 1.2, shade: Shade(shadow: 0.2))
                for x in [11.0, 16, 21] { c.line(bx + x, by + 2, bx + x, by + 31, 0.9, RGBA(100, 66, 38)) }
                c.line(bx + 6, by + 16, bx + 26, by + 16, 1.4, RGBA(80, 80, 90))
            } else {
                c.rect(bx + 7, by + 26, 18, 5, RGBA(150, 140, 120))               // the road through it
            }
        case "lever", "lever_on":
            c.rect(bx + 8, by + 24, 16, 7, RGBA(120, 120, 130), ink: 1.2, radius: 1.5, shade: Shade())
            let on = kind == "lever_on"
            c.line(bx + 16, by + 25, bx + (on ? 24 : 8), by + 10, 2, RGBA(130, 90, 55), ink: 1)
            c.ellipse(bx + (on ? 24 : 8), by + 10, 2.6, 2.6, on ? RGBA(120, 230, 120) : RGBA(230, 90, 90), ink: 1)
        case "plate", "trap":
            c.rect(bx + 5, by + 24, 22, 6, c1, ink: 1.2, radius: 2, shade: Shade(shadow: 0.2))
            if kind == "trap" || t.key == "trap" {
                for x in stride(from: 7.0, to: 27, by: 4) { c.poly([(bx + x, by + 24), (bx + x + 2, by + (t.key == "trap_sprung" ? 12 : 20)), (bx + x + 4, by + 24)], RGBA(200, 200, 210), ink: 0.8) }
            }
        case "wire":
            c.curve([(bx, by + 18), (bx + 8, by + 22), (bx + 16, by + 23), (bx + 24, by + 22), (bx + 32, by + 18)], 1.4, RGBA(60, 60, 70))
            c.rect(bx + 14, by + 20, 4, 6, RGBA(240, 200, 60), ink: 0.8, radius: 1)
        case "banner":
            c.line(bx + 8, by + 31, bx + 8, by - 14, 2.4, RGBA(140, 110, 70), ink: 1)
            c.ellipse(bx + 8, by - 15, 2, 2, RGBA(230, 200, 90), ink: 0.8)
            c.poly([(bx + 9, by - 12), (bx + 28, by - 10), (bx + 25, by - 1), (bx + 28, by + 8), (bx + 9, by + 6)], c1, ink: 1.3, shade: Shade(shadow: 0.22))
            c.ellipse(bx + 17, by - 2, 3.5, 3.5, c3, ink: 0.9)
        case "throne":
            c.rect(bx + 6, by - 8, 20, 26, RGBA(170, 40, 60), ink: 1.4, radius: 4, shade: Shade(shadow: 0.25))
            c.rect(bx + 4, by + 14, 24, 9, RGBA(220, 180, 80), ink: 1.3, radius: 2, shade: Shade())
            c.rect(bx + 6, by + 22, 4, 9, RGBA(200, 160, 70), ink: 1); c.rect(bx + 22, by + 22, 4, 9, RGBA(200, 160, 70), ink: 1)
            for x in [10.0, 16, 22] { c.poly([(bx + x - 2, by - 8), (bx + x, by - 13), (bx + x + 2, by - 8)], RGBA(240, 200, 80), ink: 0.9) }
        case "tower":
            c.rect(bx + 4, by - 26, 24, 57, c1, ink: 1.6, radius: 2, shade: Shade(shadow: 0.22))
            for x in stride(from: 4.0, to: 28, by: 6) { c.rect(bx + x, by - 31, 4, 6, c1.lightened(0.08), ink: 1, radius: 1) }
            for y in [-16.0, -2, 12] { c.rect(bx + 13, by + y, 6, 8, RGBA(40, 36, 48), ink: 1, radius: 3) }
            for y in stride(from: -20.0, to: 30, by: 7) { c.line(bx + 4, by + y, bx + 28, by + y, 0.7, shadowed(c1, 0.3)) }
        case "mill":
            c.rect(bx + 8, by + 6, 16, 25, c1, ink: 1.4, radius: 2, shade: Shade(shadow: 0.2))
            c.poly([(bx + 6, by + 7), (bx + 16, by - 3), (bx + 26, by + 7)], RGBA(170, 80, 60), ink: 1.2, shade: Shade())
            c.rect(bx + 13, by + 22, 6, 9, RGBA(110, 75, 45), ink: 1, radius: 2)
            for i in 0..<4 {
                let ang = Double(i) * .pi / 2 + .pi / 4
                let tip = (bx + 16 + cos(ang) * 17, by + 4 + sin(ang) * 17), mid = (bx + 16 + cos(ang + 0.25) * 15, by + 4 + sin(ang + 0.25) * 15)
                c.poly([(bx + 16, by + 4), tip, mid], RGBA(240, 236, 220), ink: 1)
            }
            c.ellipse(bx + 16, by + 4, 2, 2, RGBA(110, 75, 45), ink: 0.9)
        case "ballista":
            c.ellipse(bx + 9, by + 27, 4, 4, RGBA(110, 75, 45), ink: 1.1); c.ellipse(bx + 23, by + 27, 4, 4, RGBA(110, 75, 45), ink: 1.1)
            c.rect(bx + 4, by + 18, 24, 6, RGBA(140, 95, 55), ink: 1.2, radius: 1.5, shade: Shade())
            c.curve([(bx + 6, by + 6), (bx + 16, by + 14), (bx + 26, by + 6)], 2, RGBA(150, 105, 60))
            c.line(bx + 6, by + 6, bx + 26, by + 6, 0.8, RGBA(230, 230, 230))
            c.line(bx + 16, by + 20, bx + 16, by - 4, 1.6, RGBA(90, 90, 100), ink: 0.8)
            c.poly([(bx + 14, by - 3), (bx + 16, by - 8), (bx + 18, by - 3)], RGBA(200, 200, 210), ink: 0.8)
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

    /// A storey's tiles laid over a picture already made (the sky's backdrop).
    public static func bakeStorey(layers: [[UInt8]], onto base: Bitmap) -> Bitmap {
        var img = base
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
        lay(layers)
        return img
    }

    /// Ground for the 3D view in the anime style (1024 x 1024: the painted 32 x 32 ground of every tile).
    public static func bakeGround(layers: [[UInt8]], relief: [Float]? = nil) -> Bitmap {
        let at = atlas, cl = cell
        var img = Bitmap(MP.chunkPx * 2, MP.chunkPx * 2)
        defer { if let r = relief { img.shadeRelief(r, tilePx: 32) } }
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

// MARK: - the anime look in 3D

extension AnimeArt {
    /// Which drawing of a character a camera sees, and whether it is mirrored: `facing` is where the person
    /// looks on the ground (x east, y south), `toward` the camera's forward direction on the ground and `right`
    /// the screen's right on the ground. Facing the camera: the front ("down"); away: the back ("up"); across
    /// the screen: the side drawing (drawn facing right), mirrored when walking to the left.
    public static func cardView(facing f: Vec2, toward fwd: Vec2, right: Vec2) -> (dir: String, mirrored: Bool) {
        let fl = max(1e-9, (f.x * f.x + f.y * f.y).squareRoot())
        let fx = f.x / fl, fy = f.y / fl
        let towardCamera = -(fx * fwd.x + fy * fwd.y)            // 1: looking straight at the camera
        let across = fx * right.x + fy * right.y                   // 1: walking to the screen's right
        if towardCamera > 0.707 { return ("down", false) }
        if towardCamera < -0.707 { return ("up", false) }
        return ("side", across < 0)
    }

    /// The upright card a character is drawn on in 3D: `height` tiles tall, as wide as the picture's proportion,
    /// its foot at the origin, facing +z (the renderer turns it to the camera). Mirrored: u runs right to left.
    public static func cardMesh(height: Float = 1.9, mirrored: Bool = false) -> Mesh3D {
        var m = Mesh3D()
        let w = height * Float(charW) / Float(charH), hw = w / 2
        // the drawing's feet are a few pixels above its bottom edge: the card sinks by as much
        let sink = height * 2 / Float(charH)
        let (u0, u1): (Float, Float) = mirrored ? (1, 0) : (0, 1)
        let vb: Float = Mesher3D.flipV ? 0 : 1, vt: Float = Mesher3D.flipV ? 1 : 0
        m.quad([-hw, -sink, 0], [hw, -sink, 0], [hw, height - sink, 0], [-hw, height - sink, 0], normal: [0, 0, 1],
               uv: ([u0, vb], [u1, vb], [u1, vt], [u0, vt]))
        return m
    }
}

// MARK: - roofs

extension AnimeArt {
    /// A nation's roof over a building of w x h tiles, painted (twice the pixel size): two slopes meeting at the
    /// ridge, the far slope in light and the near one in a cel shadow, rows of slate, curved clay tiles or
    /// thatch by nation (shingles for anyone else), a ridge cap, the eaves' shadow and an ink line round it.
    public static func roof(nation: Int, w: Int, h: Int) -> Bitmap {
        let pw = Double(w * 32), ph = Double(h * 32 + 12)
        var c = Canvas(w * 32, h * 32 + 12)
        let (base, line, ridge): (RGBA, RGBA, RGBA)
        switch nation {
        case 1: (base, line, ridge) = (RGBA(hex: "#6a80a8"), RGBA(hex: "#3e5076"), RGBA(hex: "#a8c0e0"))
        case 2: (base, line, ridge) = (RGBA(hex: "#d0583e"), RGBA(hex: "#8a3024"), RGBA(hex: "#f29a74"))
        case 3: (base, line, ridge) = (RGBA(hex: "#e0b860"), RGBA(hex: "#9a7430"), RGBA(hex: "#f6dc94"))
        default: (base, line, ridge) = (RGBA(hex: "#946c46"), RGBA(hex: "#5e4128"), RGBA(hex: "#c09a6c"))
        }
        let mid = ph / 2
        let near = shadowed(base, 0.18)
        // the two slopes
        c.rect(0, 0, pw, mid, base.lightened(0.04))
        c.rect(0, mid, pw, ph - mid, near)
        var r = RNG(seed: nation &* 131 &+ w &* 17 &+ h)
        switch nation {
        case 1:
            // slate: offset rows of rectangular slates, a light edge on each
            var y = 2.0, row = 0
            while y < ph - 6 {
                let slope = y < mid ? base.lightened(0.04) : near
                var x = row % 2 == 0 ? 0.0 : -5
                while x < pw { c.rect(x + 0.6, y, 9.4, 7, slope, radius: 1.2); c.rect(x + 0.6, y, 9.4, 1.2, slope.lightened(0.18)); x += 10 }
                c.rect(0, y + 7, pw, 1, line)
                y += 8; row += 1
            }
        case 2:
            // clay: rows of half-round tiles, each with a highlight on its curve
            var y = 3.0
            while y < ph - 6 {
                let slope = y < mid ? base : near
                var x = 0.0
                while x < pw {
                    c.ellipse(x + 4.5, y + 4, 4.6, 4.2, slope, ink: 0.7)
                    c.curve([(x + 1.8, y + 2.6), (x + 4.5, y + 1), (x + 7.2, y + 2.6)], 0.9, ridge)
                    x += 9
                }
                y += 7
            }
        case 3:
            // thatch: bundles of straw strokes, bound in bands
            for _ in 0..<Int(pw * ph / 14) {
                let x = r.range(0, pw), y = r.range(0, ph - 6), len = r.range(5, 10)
                c.line(x, y, x + r.range(-1, 1), y + len, 0.9, r.unit() < 0.5 ? line.lightened(0.15) : ridge)
            }
            var y = 9.0
            while y < ph - 6 { c.rect(0, y, pw, 1.6, line); y += 12 }
        default:
            // wooden shingles: staggered rows, grain lines
            var y = 2.0, row = 0
            while y < ph - 6 {
                var x = row % 2 == 0 ? 0.0 : -4
                while x < pw { c.rect(x + 0.5, y, 7.4, 6, y < mid ? base : near, radius: 1); c.line(x + 3, y + 1, x + 3, y + 5, 0.6, line); x += 8 }
                c.rect(0, y + 6, pw, 1, line)
                y += 7; row += 1
            }
        }
        // the ridge cap with its glint, the eaves' shadow, the outline
        c.rect(0, mid - 2.5, pw, 5, ridge, ink: 1.2, radius: 2)
        c.rect(2, mid - 1.8, pw - 4, 1.2, RGBA(255, 255, 255, 120))
        c.rect(0, ph - 6, pw, 6, shadowed(line, 0.25))
        for (x, y, ww, hh) in [(0.0, 0.0, pw, 2.0), (0, ph - 2, pw, 2), (0, 0, 2, ph), (pw - 2, 0, 2, ph)] { c.rect(x, y, ww, hh, AnimeArt.ink) }
        if nation == 2 {                                               // upturned eaves at the corners
            c.poly([(0, mid - 3), (-0.5, mid - 10), (6, mid - 3)], ridge, ink: 1)
            c.poly([(pw, mid - 3), (pw + 0.5, mid - 10), (pw - 6, mid - 3)], ridge, ink: 1)
        }
        return c.image()
    }
}

// MARK: - the hero look (modern JRPG proportions)

extension AnimeArt {
    /// Is (x, y) inside the polygon?
    static func inside(_ p: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var a = false
        var j = p.count - 1
        for i in 0..<p.count {
            let (xi, yi) = p[i], (xj, yj) = p[j]
            if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi { a.toggle() }
            j = i
        }
        return a
    }

    /// A shape painted with soft light: lit from the upper left, a smooth fall into a cool shadow on the right
    /// and below, and a thin rim of cool light on the far edge (the painterly look of modern JRPG art).
    static func soft(_ c: inout Canvas, _ p: [(Double, Double)], _ col: RGBA, ink: Double = 1.2, light: Double = 0.16, shadow: Double = 0.3, rim: Bool = true) {
        let xs = p.map { $0.0 }, ys = p.map { $0.1 }
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let w = max(1, x1 - x0), h = max(1, y1 - y0)
        let lit = col.lightened(light), dark = shadowed(col, shadow)
        c.paint(x0 - 1, y0 - 1, x1 + 1, y1 + 1, inside: { x, y in inside(p, x, y) }, color: { x, y in
            let u = (x - x0) / w, v = (y - y0) / h
            let t = max(0, min(1, 0.55 * u + 0.45 * v))             // 0 lit corner ... 1 shadow corner
            var c2 = t < 0.5 ? mix(lit, col, t * 2) : mix(col, dark, (t - 0.5) * 2)
            if rim && u > 0.9 { c2 = mix(c2, RGBA(190, 225, 255), (u - 0.9) * 6 * 0.55) }
            return c2
        })
        if ink > 0 { for i in 0..<p.count { let a = p[i], b = p[(i + 1) % p.count]; c.line(a.0, a.1, b.0, b.1, ink, AnimeArt.ink) } }
    }

    static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        let t = max(0, min(1, t))
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(Double(x) + (Double(y) - Double(x)) * t) }
        return RGBA(m(a.r, b.r), m(a.g, b.g), m(a.b, b.b), m(a.a, b.a))
    }

    /// The figure in modern JRPG proportions on the same 64 x 80 canvas (feet at y 76): about three and a half
    /// heads tall, a face with almond eyes, layered hair with a gloss, a jacket over an inner layer, a belt,
    /// gloves and boots, painted with soft light and a rim of cool light. Directions and frames as `character`.
    public static func hero(_ look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool) -> Bitmap {
        var c = Canvas(charW, charH, scale: figureScale)
        let skin = pastel(RGBA(hex: look.skin)), hair = pastel(RGBA(hex: look.hair)), coat = pastel(RGBA(hex: look.shirt))
        let pants = pastel(RGBA(hex: look.pants)), boots = pastel(RGBA(hex: look.shoes)).darkened(0.15)
        let inner = shadowed(coat, 0.45), leather = RGBA(74, 58, 52), metal = RGBA(214, 206, 180)
        let iris = irisColor(hair)
        let style = look.style % 4
        let walk = frame == 1 ? 1.0 : (frame == 2 ? -1.0 : 0)
        let bob = frame == 1 || frame == 2 ? -1.0 : 0
        let act = frame == 3
        let k: Double = child ? 0.78 : 1
        let cx = 32.0, foot = 76.0
        func X(_ v: Double) -> Double { cx + v * k }
        func Y(_ v: Double) -> Double { foot - (76 - v) * k + (v < 56 ? bob : 0) }
        let side = dir == "side", back = dir == "up"

        c.ellipse(X(0), foot - 1, 11 * k, 2.6 * k, RGBA(0, 0, 0, 60))

        // long hair behind the body
        let long = female || style == 2
        if long && !side {
            soft(&c, [(X(-10), Y(18)), (X(10), Y(18)), (X(11.5), Y(back ? 50 : 44)), (X(0), Y(back ? 53 : 46)), (X(-11.5), Y(back ? 50 : 44))], shadowed(hair, 0.1), ink: 1.1, rim: false)
        }
        if style == 3 && !side {                                         // a ponytail behind
            soft(&c, [(X(4), Y(10)), (X(12), Y(12)), (X(15), Y(30)), (X(11), Y(44)), (X(8), Y(28))], hair, ink: 1.1)
        }

        // legs: tapered trousers, knee fold, boots with a cuff and a shine
        func leg(_ x: Double, _ swing: Double, _ shade: Double) {
            let top = Y(54), knee = Y(64), ank = Y(71)
            let p = [(X(x - 3.6), top), (X(x + 3.6), top), (X(x + 2.6 + swing), knee), (X(x + 2.2 + swing * 1.6), ank), (X(x - 2.2 + swing * 1.6), ank), (X(x - 2.8 + swing), knee)]
            soft(&c, p, shade > 0 ? shadowed(pants, shade) : pants, ink: 1.1)
            c.line(X(x - 1.5 + swing), knee - 1, X(x + 1 + swing), knee, 0.8, shadowed(pants, 0.4))
            let bx = X(x + swing * 1.6)
            soft(&c, [(bx - 2.9 * k, ank - 2), (bx + 2.9 * k, ank - 2), (bx + (side ? 5.5 : 3.3) * k, foot - 1), (bx - 3.3 * k, foot - 1)], boots, ink: 1.1)
            c.rect(bx - 2.9 * k, ank - 2.5, 5.8 * k, 1.6, boots.lightened(0.2))
            c.line(bx - 1.5 * k, ank, bx - 1.5 * k, foot - 2.5, 0.7, RGBA(255, 255, 255, 90))
        }
        if side { leg(-1.5, -walk * 2.5, 0.18); leg(1.5, walk * 2.5, 0) }
        else { leg(-4, frame == 1 ? -0.6 : 0, 0); leg(4, frame == 2 ? 0.6 : 0, 0.14) }

        // the torso: jacket over an inner layer, the belt; a longer coat tail for women
        let torso: [(Double, Double)] = side
            ? [(X(-5.5), Y(33)), (X(6), Y(33)), (X(7), Y(46)), (X(6), Y(55)), (X(-6), Y(55)), (X(-6.5), Y(45))]
            : [(X(-9), Y(33)), (X(9), Y(33)), (X(8), Y(44)), (X(7.5), Y(55)), (X(-7.5), Y(55)), (X(-8), Y(44))]
        if female && !side { soft(&c, [(X(-8), Y(50)), (X(8), Y(50)), (X(10.5), Y(61)), (X(-10.5), Y(61))], shadowed(coat, 0.08), ink: 1.1) }
        soft(&c, torso, coat, ink: 1.3)
        if !back && !side {
            c.poly([(X(-3.2), Y(33)), (X(3.2), Y(33)), (X(2.4), Y(52)), (X(-2.4), Y(52))], inner)                 // the inner layer
            c.line(X(-3.2), Y(33), X(-2.2), Y(52), 1.0, AnimeArt.ink); c.line(X(3.2), Y(33), X(2.2), Y(52), 1.0, AnimeArt.ink)
            c.poly([(X(-6), Y(33)), (X(-1), Y(33)), (X(-3.6), Y(39))], coat.lightened(0.18), ink: 0.8)          // lapels
            c.poly([(X(6), Y(33)), (X(1), Y(33)), (X(3.6), Y(39))], coat.lightened(0.12), ink: 0.8)
        }
        if back { c.line(X(0), Y(35), X(0), Y(54), 0.9, shadowed(coat, 0.35)) }
        // the belt and its buckle
        c.rect(side ? X(-6) : X(-7.8), Y(50), (side ? 12.5 : 15.6) * k, 2.6 * k, leather, ink: 0.8)
        if !back { c.rect(side ? X(3) : X(-1.5), Y(49.6), 3 * k, 3.2 * k, metal, ink: 0.7) }
        // shoulder pieces on the spiky and swept styles (a soldier's or a traveller's coat)
        if !female && (style == 0 || style == 1) && !side {
            soft(&c, [(X(-11), Y(33)), (X(-5), Y(31.5)), (X(-4.5), Y(36)), (X(-10.5), Y(38))], shadowed(coat, 0.2), ink: 1.0)
        }

        // arms: sleeves, gloved hands
        func arm(_ s: Double, swing: Double, raised: Bool, shade: Double) {
            let sx = side ? X(s * 1.5) : X(s * 8.6), sy = Y(35)
            let ex = raised ? X(s * 13) : X(s * (side ? 3 : 10) + swing * 1.8), ey = raised ? Y(32) : Y(44)
            let hx = raised ? X(s * 15) : X(s * (side ? 3.5 : 10.5) + swing * 3), hy = raised ? Y(25) : Y(52)
            let col = shade > 0 ? shadowed(coat, shade) : coat
            c.line(sx, sy, ex, ey, 4.4 * k, col, ink: 1.1)
            c.line(ex, ey, hx, hy, 3.8 * k, col, ink: 1.1)
            c.ellipse(hx, hy + 0.5, 2.3 * k, 2.4 * k, leather, ink: 1.0)
        }
        if side { arm(1, swing: act ? 0 : walk * 2, raised: act, shade: 0) }
        else { arm(-1, swing: walk, raised: false, shade: 0); arm(1, swing: -walk, raised: act, shade: 0.12) }

        // the neck and head: an oval face narrowing to the chin
        let hy = Y(20)
        c.rect(X(-2.2), Y(28), 4.4 * k, 5.5 * k, shadowed(skin, 0.18))
        let face: [(Double, Double)] = side
            ? [(X(-5), hy - 9 * k), (X(5), hy - 9.5 * k), (X(8), hy - 3 * k), (X(8.5), hy + 2 * k), (X(7.5), hy + 4.5 * k), (X(6), hy + 7 * k), (X(1.5), hy + 9.5 * k), (X(-4), hy + 7 * k), (X(-6.5), hy)]
            : [(X(-7.5), hy - 9 * k), (X(7.5), hy - 9 * k), (X(8), hy + 1 * k), (X(5.5), hy + 6.5 * k), (X(0), hy + 10 * k), (X(-5.5), hy + 6.5 * k), (X(-8), hy + 1 * k)]
        soft(&c, face, skin, ink: 1.3, light: 0.08, shadow: 0.16, rim: false)
        if !back {
            if side {
                heroEye(&c, X(4.2), hy + 0.6 * k, k, iris, side: true)
                c.line(X(1.5), hy - 3.6 * k, X(6), hy - 4.2 * k, 1.0, shadowed(hair, 0.3))                    // the brow
                c.line(X(8.3), hy + 2.5 * k, X(7.2), hy + 3.4 * k, 0.8, shadowed(skin, 0.35))                  // the nose
                c.line(X(5.3), hy + 6 * k, X(6.6), hy + 5.8 * k, 0.9, RGBA(170, 90, 90))
                c.ellipse(X(-2.5), hy + 1 * k, 1.6 * k, 2.4 * k, shadowed(skin, 0.12), ink: 0.8)              // the ear
            } else {
                heroEye(&c, X(-3.6), hy + 0.6 * k, k, iris, side: false)
                heroEye(&c, X(3.6), hy + 0.6 * k, k, iris, side: false)
                c.line(X(-5.6), hy - 3.4 * k, X(-1.8), hy - 3.9 * k, 1.0, shadowed(hair, 0.3))
                c.line(X(1.8), hy - 3.9 * k, X(5.6), hy - 3.4 * k, 1.0, shadowed(hair, 0.3))
                c.line(X(0.4), hy + 2.5 * k, X(-0.3), hy + 3.8 * k, 0.8, shadowed(skin, 0.35))
                if act { c.ellipse(X(0), hy + 6.2 * k, 1.4 * k, 1.1 * k, RGBA(150, 60, 70), ink: 0.6) }
                else { c.line(X(-1.3), hy + 6.2 * k, X(1.3), hy + 6.2 * k, 0.9, RGBA(170, 90, 90)) }
                if female { c.ellipse(X(-5.2), hy + 4 * k, 1.8 * k, 0.9 * k, RGBA(255, 130, 150, 90)); c.ellipse(X(5.2), hy + 4 * k, 1.8 * k, 0.9 * k, RGBA(255, 130, 150, 90)) }
            }
        }

        // the hair: layered locks, darker at the roots, a gloss streak and a rim of light
        let hl = hair.lightened(0.3)
        if back {
            soft(&c, [(X(-9), hy - 4), (X(-7), hy - 11 * k), (X(0), hy - 13 * k), (X(7), hy - 11 * k), (X(9), hy - 4), (X(8.5), hy + 6 * k), (X(0), hy + 8.5 * k), (X(-8.5), hy + 6 * k)], hair, ink: 1.3)
            for i in -2...2 { let x = Double(i) * 3.4; c.curve([(X(x), hy - 11 * k), (X(x * 1.1), hy - 2 * k), (X(x * 1.2), hy + 6 * k)], 0.8, shadowed(hair, 0.3)) }
        } else {
            // the cap of the hair over the head
            let cap: [(Double, Double)] = side
                ? [(X(-7), hy + 2 * k), (X(-7.5), hy - 7 * k), (X(-2), hy - 12.5 * k), (X(5), hy - 12 * k), (X(9.5), hy - 6 * k), (X(9), hy - 2 * k), (X(4), hy - 5 * k), (X(-2), hy - 3.5 * k), (X(-4), hy + 4 * k)]
                : [(X(-9), hy + 1 * k), (X(-8.5), hy - 8 * k), (X(-3), hy - 12.5 * k), (X(3), hy - 12.5 * k), (X(8.5), hy - 8 * k), (X(9), hy + 1 * k), (X(7.5), hy - 4 * k), (X(-7.5), hy - 4 * k)]
            soft(&c, cap, hair, ink: 1.3)
            // locks over the forehead: by style
            let locks: [(Double, Double, Double)]                // (x at the root, x at the tip, length)
            switch style {
            case 1: locks = [(-6, -8.5, 6), (-2.5, -3.5, 7.5), (1.5, 2.5, 7), (5.5, 8.5, 6)]
            case 2: locks = [(-6, -6.5, 8), (-2, -1, 7), (2.5, 3.5, 7.5), (6, 7, 8)]
            case 3: locks = [(-5.5, -7, 5.5), (-1, 1.5, 6.5), (4, 6.5, 5.5)]
            default: locks = [(-6.5, -4.5, 6), (-3, 1, 7), (1.5, 5.5, 6.5), (5.5, 8, 5)]
            }
            if !side {
                for (x0, x1, len) in locks {
                    soft(&c, [(X(x0 - 2.4), hy - 7 * k), (X(x0 + 2.4), hy - 7 * k), (X(x1), hy - 7 * k + len * k)], hair, ink: 1.0)
                }
                // side locks framing the face (long for long hair)
                let sl: Double = long ? 15 : 8
                for s in [-1.0, 1.0] { soft(&c, [(X(s * 9), hy - 5 * k), (X(s * 7), hy - 4 * k), (X(s * 7.8), hy + sl * k), (X(s * 9.8), hy + (sl - 4) * k)], hair, ink: 1.0, rim: s > 0) }
            } else {
                for (i, len) in [7.0, 8.5, 6.0].enumerated() { let x = 1.0 + Double(i) * 2.8; soft(&c, [(X(x - 2), hy - 7 * k), (X(x + 2.2), hy - 7.5 * k), (X(x + 3), hy - 7 * k + len * k)], hair, ink: 0.9) }
                if long { soft(&c, [(X(-7.5), hy - 2 * k), (X(-3.5), hy - 2 * k), (X(-5), hy + 22 * k), (X(-9), hy + 18 * k)], hair, ink: 1.0, rim: false) }
            }
            // spikes on top for the spiky style
            if style == 1 && !female {
                for (x, h) in [(-6.0, 6.0), (-2.0, 8.5), (2.5, 9.0), (6.5, 6.5)] {
                    soft(&c, [(X(x - 2.6), hy - 10.5 * k), (X(x + 2.4), hy - 11 * k), (X(x + 3), hy - (11 + h) * k)], hair, ink: 1.0)
                }
            }
            // the gloss: a bright streak across the crown, broken between locks
            c.curve(side ? [(X(-4), hy - 9 * k), (X(1), hy - 10.5 * k), (X(5), hy - 9.5 * k)] : [(X(-6), hy - 8.5 * k), (X(-2), hy - 10 * k), (X(2), hy - 10 * k), (X(6), hy - 8.5 * k)], 1.4, hl)
        }
        if style == 3 && female && !back {
            c.ellipse(X(5.5), hy - 10.5 * k, 2.2 * k, 1.6 * k, RGBA(200, 60, 90), ink: 0.8)          // a hair tie
        }

        if !held.isEmpty {
            let hx = act ? X(15) : (side ? X(3.5 + walk * 3) : X(10.5))
            let hy2 = act ? Y(25) : Y(52)
            heroItem(&c, held, hx, hy2, k)
        }
        return c.image()
    }

    /// A smaller, sharper eye: an almond with a heavy upper line, an iris darker above and lighter below with
    /// a ring, the pupil, one bright catchlight.
    static func heroEye(_ c: inout Canvas, _ x: Double, _ y: Double, _ k: Double, _ iris: RGBA, side: Bool) {
        let w = (side ? 2.2 : 2.7) * k, h = 2.4 * k
        let almond: [(Double, Double)] = [(x - w, y + 0.2), (x - w * 0.4, y - h), (x + w * 0.6, y - h * 0.95), (x + w + 0.3, y - 0.2), (x + w * 0.4, y + h * 0.8), (x - w * 0.5, y + h * 0.75)]
        c.poly(almond, RGBA(250, 248, 246))
        c.paint(x - w, y - h, x + w, y + h, inside: { px, py in let u = (px - x) / (w * 0.62), v = (py - y) / (h * 0.95); return u * u + v * v <= 1 && inside(almond, px, py) },
                color: { _, py in mix(shadowed(iris, 0.45), iris.lightened(0.25), (py - (y - h)) / (2 * h)) })
        c.ellipse(x, y + 0.2 * k, w * 0.28, h * 0.42, RGBA(24, 20, 34))
        c.ellipse(x - w * 0.25, y - h * 0.35, 0.9 * k, 0.9 * k, .white)
        c.curve([(x - w - 0.5, y + 0.3), (x - w * 0.4, y - h - 0.3), (x + w * 0.6, y - h * 1.05), (x + w + 0.6, y - 0.3)], 1.4 * k, AnimeArt.ink)
        c.line(x + w + 0.3, y - 0.3, x + w + 1.4 * k, y - 0.9 * k, 0.9 * k, AnimeArt.ink)
    }

    /// What the hero carries: the same things, longer and slimmer to suit the proportions.
    static func heroItem(_ c: inout Canvas, _ kind: String, _ x: Double, _ y: Double, _ k: Double) {
        let steel = RGBA(220, 228, 240), wood = RGBA(140, 96, 60)
        switch kind {
        case "sword":
            c.line(x, y + 2 * k, x + 1.5 * k, y - 26 * k, 2.6 * k, steel, ink: 1.0)
            c.line(x + 0.4, y - 4 * k, x + 1.2 * k, y - 22 * k, 0.6, .white)
            c.line(x - 3.5 * k, y - 1 * k, x + 3.5 * k, y - 1.5 * k, 1.8 * k, RGBA(200, 170, 80), ink: 0.9)
        case "staff":
            c.line(x, y + 10 * k, x + 1 * k, y - 26 * k, 2.0 * k, wood, ink: 1.0)
            c.ellipse(x + 1 * k, y - 28 * k, 3 * k, 3 * k, RGBA(150, 235, 255), ink: 1.0, shade: Shade())
            c.ellipse(x + 1 * k, y - 28 * k, 6 * k, 6 * k, RGBA(150, 235, 255, 60))
        default:
            heldItem(&c, kind, x, y, k * 0.85)
        }
    }
}

// MARK: - the moe look (soft, glossy, coloured line art)

extension AnimeArt {
    /// How people are drawn in the anime look: the soft moe figure (large glossy eyes, flowing hair, frills and
    /// ornaments, coloured line art) or the hero figure (modern JRPG proportions). A setting of the game.
    public enum Figure: String, Codable, CaseIterable { case moe, hero, angel }
    nonisolated(unsafe) public static var figure: Figure = .moe

    /// The soft moe figure on the 64 x 80 canvas (feet at y 76): a large head; big glossy eyes with a gradient
    /// iris, a ring of light, three catchlights and a sparkle, double lashes and blush lines; hair in many fine
    /// locks with strand lines, a broken ring of gloss, long side locks and an ahoge; by the person's style a
    /// frilled flower headband, twin tails with ribbons, small horns or a flower clip; puffed sleeves, a bow or
    /// a choker, a frilled hem, long gloves; soft gradient light; every line in a deeper tone of its own colour.
    public static func moe(_ look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool, angel: Bool = false) -> Bitmap {
        var c = Canvas(charW, charH, scale: figureScale)
        let skin = pastel(RGBA(hex: look.skin)).lightened(0.04), hair = pastel(RGBA(hex: look.hair)).lightened(0.06)
        // the celestial costume: an ivory robe with gold filigree, sheer dark stockings with lace bands, gold heels
        let cloth = angel ? RGBA(250, 246, 236) : pastel(RGBA(hex: look.shirt))
        let pants = angel ? RGBA(78, 70, 78) : pastel(RGBA(hex: look.pants))
        let shoes = angel ? RGBA(226, 190, 96) : pastel(RGBA(hex: look.shoes))
        let gold = RGBA(222, 178, 70), goldDeep = RGBA(160, 112, 36)
        let white = RGBA(250, 250, 255), frill = RGBA(244, 246, 255)
        let hairInk = shadowed(hair, 0.5).darkened(0.15), skinInk = RGBA(176, 112, 104), clothInk = shadowed(cloth, 0.55)
        let iris = angel ? RGBA(236, 184, 60) : irisColor(hair).lightened(0.05)
        let style = look.style % 4
        let walk = frame == 1 ? 1.0 : (frame == 2 ? -1.0 : 0)
        let bob = frame == 1 || frame == 2 ? -1.2 : 0
        let act = frame == 3
        let k: Double = child ? 0.84 : 1
        let cx = 32.0, foot = 76.0
        func X(_ v: Double) -> Double { cx + v * k }
        func Y(_ v: Double) -> Double { foot - (76 - v) * k + (v < 62 ? bob : 0) }
        let side = dir == "side", back = dir == "up"
        let long = female || style == 2
        c.ellipse(X(0), foot - 1, 12 * k, 2.8 * k, RGBA(0, 0, 0, 55))
        // the wings behind (seen from behind they are drawn over the back, further down)
        if angel && !back { angelWings(&c, X: X, Y: Y, k: k, side: side, gold: gold, goldDeep: goldDeep) }
        // the train of the robe, sweeping behind to the ground
        if angel {
            c.inkColor = RGBA(206, 196, 176)
            let tr: [(Double, Double)] = side ? [(X(-3), Y(48)), (X(4), Y(48)), (X(-6), Y(70)), (X(-20), Y(77)), (X(-14), Y(64))]
                                              : [(X(-9), Y(48)), (X(9), Y(48)), (X(17), Y(74)), (X(10), Y(77)), (X(0), Y(75.5)), (X(-10), Y(77)), (X(-17), Y(74))]
            soft(&c, tr, RGBA(244, 238, 226, 235), ink: 0.8, light: 0.1, shadow: 0.16, rim: false)
            // gold thread down its edges
            c.inkColor = nil
            for e in side ? [[(X(-3), Y(50)), (X(-10), Y(66)), (X(-19), Y(76))]] : [[(X(-9), Y(50)), (X(-14), Y(64)), (X(-16.5), Y(74))], [(X(9), Y(50)), (X(14), Y(64)), (X(16.5), Y(74))]] {
                c.curve(e, 0.45 * k, gold)
            }
        }

        if angel { angelHalo(&c, X: X, hy: Y(26), k: k, side: side, gold: gold, goldDeep: goldDeep) }
        // the hair behind: long and flowing, curling at the ends
        c.inkColor = hairInk
        if long {
            if side {
                soft(&c, [(X(-14), Y(22)), (X(-4), Y(20)), (X(-6), Y(56)), (X(-10), Y(62)), (X(-16), Y(54))], shadowed(hair, 0.12), ink: 1.1, rim: false)
            } else {
                soft(&c, [(X(-15), Y(20)), (X(15), Y(20)), (X(17), Y(50)), (X(12), Y(back ? 64 : 58)), (X(0), Y(back ? 62 : 56)), (X(-12), Y(back ? 64 : 58)), (X(-17), Y(50))], shadowed(hair, 0.12), ink: 1.1, rim: false)
            }
        }
        if style == 1 && !side {                     // twin tails, each with a ribbon
            for s in [-1.0, 1.0] {
                soft(&c, [(X(s * 13), Y(14)), (X(s * 24), Y(20)), (X(s * 27), Y(40)), (X(s * 22), Y(56)), (X(s * 18), Y(44)), (X(s * 15), Y(26))], hair, ink: 1.1, rim: s > 0)
                for t in [0.3, 0.6] { c.curve([(X(s * (15 + 8 * t)), Y(20 + 30 * t)), (X(s * (19 + 5 * t)), Y(30 + 26 * t))], 0.8, hairInk) }
            }
        }

        // legs: stockings and little shoes
        c.inkColor = shadowed(pants, 0.5)
        if side {
            c.line(X(-2 - walk * 3), Y(62), X(-2 - walk * 4), Y(72), 4.6 * k, shadowed(pants, 0.12), ink: 1.0)
            c.line(X(2 + walk * 3), Y(62), X(2 + walk * 4), Y(72), 4.6 * k, pants, ink: 1.0)
        } else {
            let l = frame == 1 ? 1.6 : 0, r = frame == 2 ? 1.6 : 0
            c.line(X(-4), Y(62), X(-4), Y(72 - l), 4.6 * k, pants, ink: 1.0)
            c.line(X(4), Y(62), X(4), Y(72 - r), 4.6 * k, shadowed(pants, 0.1), ink: 1.0)
        }
        c.inkColor = shadowed(shoes, 0.5)
        for (x, lift) in side ? [(-1 - walk * 4, 0.0), (4 + walk * 4, 0.0)] : [(-4.5, frame == 1 ? 1.6 : 0), (4.5, frame == 2 ? 1.6 : 0)] {
            c.ellipse(X(x), Y(73.5 - lift), 4 * k, 2.6 * k, shoes, ink: 1.0, shade: Shade(shadow: 0.15, light: 0.25))
            c.ellipse(X(x - 1), Y(72.6 - lift), 1.2 * k, 0.7 * k, RGBA(255, 255, 255, 170))
            // a strap across the instep with a little gold buckle, and the sole's edge
            c.line(X(x - 2.6), Y(72.2 - lift), X(x + 2.6), Y(72.2 - lift), 0.55 * k, shadowed(shoes, 0.4))
            c.ellipse(X(x + (side ? 1.6 : 0)), Y(72.2 - lift), 0.55 * k, 0.45 * k, RGBA(240, 200, 90))
            c.line(X(x - 3.4), Y(75.4 - lift), X(x + 3.4), Y(75.4 - lift), 0.4 * k, shadowed(shoes, 0.55))
        }
        if female {
            // stockings to the thigh, a band of lace at the top (it shows under the hem when walking)
            c.inkColor = nil
            for x in side ? [-2 - walk * 3.4, 2 + walk * 3.4] : [-4.0, 4.0] {
                c.line(X(x - 2.1), Y(64.2), X(x + 2.1), Y(64.2), 0.9 * k, frill)
                for i in 0..<4 { c.ellipse(X(x - 1.6 + Double(i) * 1.07), Y(64.9), 0.42 * k, 0.42 * k, frill) }
                c.line(X(x + 1.2), Y(65.5), X(x + 1.0), Y(70.5), 0.45 * k, RGBA(255, 255, 255, 90))      // the sheen down the shin
            }
        }

        // the dress: a soft bell with a frilled hem; the bodice; a bow or a choker
        c.inkColor = clothInk
        let hem: Double = female ? 63 : 60
        if female {
            soft(&c, side ? [(X(-6), Y(48)), (X(6), Y(48)), (X(11), Y(hem)), (X(-9), Y(hem))] : [(X(-8), Y(48)), (X(8), Y(48)), (X(13), Y(hem)), (X(-13), Y(hem))], cloth, ink: 1.1)
            let w = side ? 10.0 : 13.0
            var x = -w
            while x < w { c.ellipse(X(x + 1.4), Y(hem + 0.6), 1.6 * k, 1.3 * k, frill, ink: 0.6); x += 2.8 }
        } else {
            soft(&c, side ? [(X(-6), Y(48)), (X(6), Y(48)), (X(7), Y(hem)), (X(-6.5), Y(hem))] : [(X(-9), Y(48)), (X(9), Y(48)), (X(10), Y(hem)), (X(-10), Y(hem))], cloth, ink: 1.1)
        }
        // the folds of the skirt: soft lines from the waist, a lighter crest beside each
        c.inkColor = nil
        let folds: [Double] = side ? [-3, 1.5, 5] : (female ? [-8.5, -4, 0.5, 5, 9] : [-5, 0, 5])
        for f in folds {
            let spread = female ? 1.45 : 1.08
            c.curve([(X(f * 0.75), Y(51)), (X(f * 0.95), Y(55)), (X(f * spread), Y(hem - 0.8))], 0.5 * k, shadowed(cloth, 0.32))
            c.curve([(X(f * 0.75 + 0.9), Y(51.5)), (X(f * 0.95 + 1.0), Y(55)), (X(f * spread + 1.1), Y(hem - 1.4))], 0.45 * k, cloth.lightened(0.18))
        }
        if female {
            // a second, finer row of lace under the frill
            let w2 = side ? 9.0 : 12.0
            var x2 = -w2
            while x2 < w2 { c.ellipse(X(x2 + 0.7), Y(hem + 2.0), 0.7 * k, 0.6 * k, frill.darkened(0.06)); x2 += 1.4 }
        }
        c.inkColor = clothInk
        soft(&c, side ? [(X(-5), Y(43)), (X(5.5), Y(43)), (X(6), Y(50)), (X(-5.5), Y(50))] : [(X(-8.5), Y(43)), (X(8.5), Y(43)), (X(8), Y(51)), (X(-8), Y(51))], cloth.lightened(0.05), ink: 1.1)
        // the sash at the waist; seen from behind, its bow
        c.inkColor = nil
        let sash = shadowed(cloth, 0.28)
        c.rect(side ? X(-5.4) : X(-8.2), Y(49.6), (side ? 11.2 : 16.4) * k, 1.5 * k, sash)
        if back {
            c.poly([(X(0), Y(50.3)), (X(-5), Y(47.8)), (X(-5), Y(53))], sash.lightened(0.1), ink: 0.5, shade: Shade(shadow: 0.2))
            c.poly([(X(0), Y(50.3)), (X(5), Y(47.8)), (X(5), Y(53))], sash.lightened(0.1), ink: 0.5, shade: Shade(shadow: 0.2))
            c.line(X(-1), Y(51), X(-3), Y(57), 1.2 * k, sash); c.line(X(1), Y(51), X(3), Y(57), 1.2 * k, sash)
        } else if !side {
            // two small buttons down the bodice, below the collar
            for y in [48.6, 50.6] where !female || y > 49 { c.ellipse(X(0), Y(y), 0.65 * k, 0.65 * k, white); c.ellipse(X(-0.2), Y(y - 0.2), 0.25 * k, 0.25 * k, RGBA(255, 255, 255)) }
        }
        if !back && !side {
            c.poly([(X(-6), Y(43)), (X(6), Y(43)), (X(0), Y(48))], white, ink: 0.7)                      // the collar
            if female {
                let bow = RGBA(255, 112, 150)
                c.poly([(X(0), Y(46)), (X(-4.5), Y(43.5)), (X(-4.5), Y(48.5))], bow, ink: 0.8, shade: Shade(shadow: 0.2))
                c.poly([(X(0), Y(46)), (X(4.5), Y(43.5)), (X(4.5), Y(48.5))], bow, ink: 0.8, shade: Shade(shadow: 0.2))
                c.ellipse(X(0), Y(46), 1.3 * k, 1.3 * k, bow.lightened(0.2), ink: 0.6)
            } else {
                c.rect(X(-1), Y(44), 2 * k, 6 * k, shadowed(cloth, 0.35))                                // a tie
            }
        }

        if angel && !side {
            // gold filigree on the robe: a line down the front, branching scrolls, a jewel at the waist
            c.inkColor = nil
            c.curve([(X(0), Y(43.5)), (X(0.3), Y(50)), (X(0), Y(hem))], 0.5 * k, gold)
            for sgn in [-1.0, 1.0] {
                c.curve([(X(0), Y(51)), (X(sgn * 3), Y(53.5)), (X(sgn * 5.5), Y(52.5)), (X(sgn * 6), Y(55))], 0.4 * k, gold)
                c.curve([(X(sgn * 1.5), Y(56)), (X(sgn * 5), Y(59)), (X(sgn * 8.5), Y(hem - 0.5))], 0.4 * k, gold)
                c.curve([(X(sgn * 2), Y(44)), (X(sgn * 5), Y(46)), (X(sgn * 7.5), Y(44.5))], 0.4 * k, gold)
            }
            c.ellipse(X(0), Y(50.2), 1.0 * k, 1.2 * k, RGBA(200, 226, 255), ink: 0.4)
        }
        // arms: puffed sleeves, long white gloves
        func arm(_ s: Double, swing: Double, raised: Bool) {
            let sx = side ? X(s * 1) : X(s * 8.5), sy = Y(45)
            c.inkColor = clothInk
            c.ellipse(sx, sy, 3.8 * k, 3.2 * k, cloth.lightened(0.08), ink: 1.0, shade: Shade(shadow: 0.18, light: 0.2))
            let hx = raised ? X(s * 15) : X(s * (side ? 2 : 11) + swing * 2.5), hy = raised ? Y(34) : Y(56 - abs(swing))
            c.inkColor = RGBA(180, 184, 206)
            let glove = angel ? RGBA(70, 60, 70) : (female ? white : skin)
            c.line(sx + s * 1.5, sy + 2, hx, hy, 3.4 * k, glove, ink: 0.9)
            c.ellipse(hx, hy + 0.5, 2.2 * k, 2.2 * k, glove, ink: 0.8)
            if angel {
                // a lattice of lace on the dark glove and a gold cuff at the elbow
                c.inkColor = nil
                for t in stride(from: 0.25, through: 0.85, by: 0.2) {
                    let mx = sx + s * 1.5 + (hx - sx - s * 1.5) * t, my = sy + 2 + (hy - sy - 2) * t
                    c.line(mx - 1.3 * k, my - 0.6 * k, mx + 1.3 * k, my + 0.6 * k, 0.3 * k, RGBA(140, 128, 140))
                    c.line(mx - 1.3 * k, my + 0.6 * k, mx + 1.3 * k, my - 0.6 * k, 0.3 * k, RGBA(140, 128, 140))
                }
                let cx0 = sx + (hx - sx) * 0.2, cy0 = sy + (hy - sy) * 0.2
                c.ellipse(cx0, cy0, 2.0 * k, 1.0 * k, gold, ink: 0.4)
                c.ellipse(cx0, cy0, 0.6 * k, 0.6 * k, RGBA(255, 240, 200))
            }
            c.inkColor = nil
            c.curve([(sx - 1.6 * k, sy - 0.6 * k), (sx, sy + 0.8 * k), (sx + 1.6 * k, sy - 0.4 * k)], 0.45 * k, shadowed(cloth, 0.3))   // the puff's gather
            if female && !angel {
                // the glove's lace cuff, a third of the way down
                let mx = sx + (hx - sx) * 0.38, my = sy + (hy - sy) * 0.38
                for i in -1...1 { c.ellipse(mx + Double(i) * 1.1 * k, my, 0.75 * k, 0.65 * k, frill.darkened(0.05)) }
                c.line(sx + s * 1.5 + (hx - sx) * 0.2, sy + 2 + (hy - sy) * 0.2, hx - (hx - sx) * 0.1, hy - (hy - sy) * 0.1, 0.4 * k, RGBA(205, 208, 228))
            }
        }
        if side { arm(1, swing: act ? 0 : walk * 2, raised: act) }
        else { arm(-1, swing: walk, raised: false); arm(1, swing: -walk, raised: act) }

        if angel && back { angelWings(&c, X: X, Y: Y, k: k, side: false, gold: gold, goldDeep: goldDeep) }
        // the head: large and soft, a small chin
        let hy = Y(26)
        c.inkColor = skinInk
        if !back && !side && female { c.rect(X(-5), Y(39.5), 10 * k, 1.8 * k, RGBA(70, 90, 170), ink: 0.5) }          // a choker
        // the face: a soft warm shade growing toward the lower right edge (no hard diagonal cut, no grey)
        let fx = X(side ? 1 : 0), frx = 15 * k, fry = 14.2 * k
        c.ellipse(fx, hy, frx, fry, skin, ink: 1.2)
        let warm = mix(skin, RGBA(236, 156, 150), 0.55)
        c.paint(fx - frx, hy - fry, fx + frx, hy + fry, inside: { px, py in let u = (px - fx) / frx, v = (py - hy) / fry; return u * u + v * v <= 1 },
                color: { px, py in
                    let u = (px - fx) / frx, v = (py - hy) / fry, r = (u * u + v * v).squareRoot()
                    let t = max(0, min(1, (u * 0.45 + v * 0.65 + r * 0.7 - 0.95) / 0.45))
                    return t <= 0.01 ? nil : RGBA(warm.r, warm.g, warm.b, UInt8(t * 120))
                })
        c.ellipse(fx - 6 * k, hy - 5 * k, 5 * k, 3.4 * k, RGBA(255, 255, 255, 40))                 // the light on the brow
        if !back {
            // the fringe's soft shadow on the forehead
            c.inkColor = nil
            c.ellipse(X(side ? 3 : 0), hy - 4.2 * k, (side ? 11 : 13) * k, 3.2 * k, RGBA(150, 90, 110, 46))
            if side {
                c.ellipse(X(-4), hy + 3 * k, 2.4 * k, 3.2 * k, skin, ink: 0.7)                              // the ear
                c.curve([(X(-4.6), hy + 1.4 * k), (X(-3.4), hy + 3 * k), (X(-4.4), hy + 4.6 * k)], 0.4 * k, skinInk)
                c.line(X(13.6), hy + 7.6 * k, X(14.4), hy + 8.6 * k, 0.5 * k, skinInk)                       // the tip of the nose
                moeEye(&c, X(8), hy + 4 * k, k, iris, hairInk, side: true)
                c.ellipse(X(8.5), hy + 8.5 * k, 2.8 * k, 1.3 * k, RGBA(255, 130, 160, 120))
                c.line(X(11.5), hy + 10.5 * k, X(12.8), hy + 10.3 * k, 0.9, RGBA(200, 100, 110))
            } else {
                moeEye(&c, X(-6.2), hy + 4 * k, k, iris, hairInk, side: false)
                moeEye(&c, X(6.2), hy + 4 * k, k, iris, hairInk, side: false)
                for s in [-1.0, 1.0] {
                    c.ellipse(X(s * 9.8), hy + 9 * k, 3.2 * k, 1.6 * k, RGBA(255, 130, 160, 110))
                    for i in 0..<3 { let x = X(s * 9.8) + (Double(i) - 1) * 1.6 * k; c.line(x - 0.5, hy + 9.6 * k, x + 0.5, hy + 8.4 * k, 0.5, RGBA(245, 130, 160, 150)) }
                }
                c.ellipse(X(0.4), hy + 8.3 * k, 0.4 * k, 0.3 * k, RGBA(220, 140, 140, 150))                    // a hint of a nose
                if act {
                    c.ellipse(X(0), hy + 10.6 * k, 1.5 * k, 1.3 * k, RGBA(200, 90, 100), ink: 0.5)
                    c.ellipse(X(0), hy + 11.2 * k, 0.8 * k, 0.5 * k, RGBA(255, 150, 160))                     // the tongue
                } else {
                    c.curve([(X(-1.1), hy + 10.6 * k), (X(0), hy + 11.2 * k), (X(1.1), hy + 10.6 * k)], 0.8, RGBA(200, 100, 110))
                    c.ellipse(X(0.3), hy + 11.6 * k, 0.5 * k, 0.22 * k, RGBA(255, 220, 225, 170))                // a shine on the lower lip
                }
            }
        }

        // the hair in front: fine locks with strand lines and a broken ring of gloss
        c.inkColor = hairInk
        let gloss = hair.lightened(0.42)
        if back {
            soft(&c, [(X(-15.5), hy + 4), (X(-13), hy - 10 * k), (X(0), hy - 16 * k), (X(13), hy - 10 * k), (X(15.5), hy + 4), (X(13), hy + 13 * k), (X(-13), hy + 13 * k)], hair, ink: 1.1)
            for i in -3...3 { let x = Double(i) * 3.6; c.curve([(X(x * 0.6), hy - 14 * k), (X(x), hy - 2 * k), (X(x * 1.1), hy + 12 * k)], 0.7, hairInk) }
            c.curve([(X(-8), hy - 8 * k), (X(0), hy - 11 * k), (X(8), hy - 8 * k)], 1.6, gloss)
        } else {
            let cap: [(Double, Double)] = side
                ? [(X(-15.5), hy + 8 * k), (X(-15), hy - 8 * k), (X(-5), hy - 15.5 * k), (X(7), hy - 14.5 * k), (X(14.5), hy - 7 * k), (X(9), hy - 5 * k), (X(1), hy - 5.5 * k), (X(-3), hy + 1 * k), (X(-6), hy + 9 * k)]
                : [(X(-15.5), hy + 2 * k), (X(-15), hy - 8 * k), (X(-6), hy - 15.5 * k), (X(6), hy - 15.5 * k), (X(15), hy - 8 * k), (X(15.5), hy + 2 * k), (X(12), hy - 7.5 * k), (X(-12), hy - 7.5 * k)]
            soft(&c, cap, hair, ink: 1.1)
            // fine strand lines from the crown over the cap, and a few flyaway hairs at the sides
            c.inkColor = nil
            let crown = (X(side ? 1 : 0), hy - 15 * k)
            for i in 0..<(side ? 6 : 10) {
                let t = (Double(i) + 0.5) / Double(side ? 6 : 10)
                let ex = side ? X(-14 + t * 26) : X(-14 + t * 28)
                let ey = hy - 7.8 * k - sin(t * .pi) * 1.5 * k
                c.curve([crown, ((crown.0 + ex) / 2 + (ex - crown.0) * 0.12, (crown.1 + ey) / 2 - 1.2 * k), (ex, ey)], 0.35 * k, hairInk.lightened(0.12))
            }
            for s in side ? [-1.0] : [-1.0, 1.0] {
                c.curve([(X(s * 14.5), hy - 9 * k), (X(s * 17.5), hy - 11.5 * k), (X(s * 18.5), hy - 9.5 * k)], 0.4 * k, hair.darkened(0.08))
            }
            c.inkColor = hairInk
            // the fringe: many thin pointed locks, with a strand line down each
            // (they end above the brows: the eyes are never covered)
            let tips: [(Double, Double)] = side ? [(-3, 6), (0.5, 7.5), (4, 6)] : [(-12, 7.5), (-8.5, 6), (-5, 7), (-2, 5.5), (1.5, 7), (5, 5.5), (8.5, 6.5), (11.5, 7.5)]
            for (x, len) in tips {
                let top = hy - 8 * k
                soft(&c, [(X(x - 2.6), top), (X(x + 2.6), top), (X(x + 0.5), top + len * k)], hair, ink: 0.8, light: 0.2, shadow: 0.22)
                c.line(X(x + 0.2), top + 1.5, X(x + 0.4), top + len * k * 0.7, 0.5, hairInk)
            }
            // long side locks to the chest
            if !side {
                let sl: Double = long ? 26 : 12
                for s in [-1.0, 1.0] {
                    soft(&c, [(X(s * 15.5), hy - 4 * k), (X(s * 12), hy - 2 * k), (X(s * 12.5), hy + sl * k), (X(s * 14.5), hy + (sl + 3) * k), (X(s * 16.5), hy + (sl - 4) * k)], hair, ink: 0.9, rim: s > 0)
                    c.curve([(X(s * 13.5), hy), (X(s * 13.8), hy + sl * 0.6 * k), (X(s * 14.2), hy + sl * k)], 0.5, hairInk)
                }
            }
            // the gloss: a ring of light broken by the locks
            for (a0, a1) in [(-9.5, -6.0), (-4.0, -0.5), (1.5, 5.0), (7.0, 10.0)] where !side || a0 > -5 {
                c.curve([(X(a0), hy - 10.5 * k + abs(a0) * 0.25), (X((a0 + a1) / 2), hy - 11.6 * k + abs((a0 + a1) / 2) * 0.25), (X(a1), hy - 10.5 * k + abs(a1) * 0.25)], 1.5, gloss)
            }
            // the ahoge
            c.curve([(X(1), hy - 15 * k), (X(3), hy - 21 * k), (X(7), hy - 22 * k), (X(5.5), hy - 18 * k)], 1.6, hair)
        }

        // ornaments by style (an angel wears the crown instead)
        c.inkColor = RGBA(150, 150, 180)
        switch angel ? -1 : style {
        case 0 where female && !back:                    // a frilled headband with small flowers
            for i in 0..<9 { let a = Double.pi * (1.1 + Double(i) * 0.1); c.ellipse(X(cos(a) * 14.5), hy + sin(a) * 14 * k + 1, 2 * k, 1.6 * k, frill, ink: 0.6) }
            for x in [-8.0, 0, 8] { c.ellipse(X(x), hy - 14.2 * k + abs(x) * 0.35, 1.7 * k, 1.7 * k, white, ink: 0.6); c.ellipse(X(x), hy - 14.2 * k + abs(x) * 0.35, 0.6 * k, 0.6 * k, RGBA(255, 214, 90)) }
        case 1 where !side:                              // ribbons where the twin tails are tied
            let rb = RGBA(80, 120, 220)
            for s in [-1.0, 1.0] {
                c.poly([(X(s * 14), hy - 9 * k), (X(s * 18.5), hy - 12 * k), (X(s * 18.5), hy - 6 * k)], rb, ink: 0.7, shade: Shade(shadow: 0.2))
                c.poly([(X(s * 14), hy - 9 * k), (X(s * 10), hy - 12.5 * k), (X(s * 10.5), hy - 6 * k)], rb, ink: 0.7, shade: Shade(shadow: 0.2))
            }
        case 2:                                          // small curved horns
            c.inkColor = RGBA(30, 28, 40)
            for s in [-1.0, 1.0] where !side || s > 0 {
                let horn = [(X(s * 8.5), hy - 12.5 * k), (X(s * 12.5), hy - 13.5 * k), (X(s * 15.5), hy - 20 * k), (X(s * 13.5), hy - 25 * k), (X(s * 12), hy - 19 * k), (X(s * 9.5), hy - 15.5 * k)]
                soft(&c, horn, RGBA(70, 66, 82), ink: 0.9, light: 0.35, shadow: 0.35, rim: false)
                for t in [0.35, 0.6] { c.line(X(s * (10 + 4 * t)), hy - (14 + 7 * t) * k, X(s * (12.5 + 2.5 * t)), hy - (14.5 + 7.5 * t) * k, 0.5, RGBA(150, 146, 170)) }
            }
        case 3 where !back:                              // a flower clip
            let fx = side ? X(6) : X(9), fy = hy - 10 * k
            for i in 0..<5 { let a = Double(i) * 2 * .pi / 5; c.ellipse(fx + cos(a) * 1.9 * k, fy + sin(a) * 1.9 * k, 1.5 * k, 1.5 * k, RGBA(255, 180, 210), ink: 0.5) }
            c.ellipse(fx, fy, 1.1 * k, 1.1 * k, RGBA(255, 226, 120))
        default: break
        }

        if angel { angelCrown(&c, X: X, hy: hy, k: k, side: side, gold: gold, goldDeep: goldDeep, female: female) }
        c.inkColor = nil
        if !held.isEmpty {
            let hx = act ? X(15) : (side ? X(2 + walk * 2.5) : X(11))
            heldItem(&c, held, hx, act ? Y(34) : Y(56), k * 0.9)
        }
        return c.image()
    }

    /// Two great feathered wings from the shoulder blades, spread wide past the hair: a white wing shape lit
    /// from above, rows of long flight feathers with scalloped tips and pale quills fanning to the lower outer
    /// edge, shorter feathers over them, and gold covert feathers like scales along the top. From the side, one.
    static func angelWings(_ c: inout Canvas, X: (Double) -> Double, Y: (Double) -> Double, k: Double, side: Bool, gold: RGBA, goldDeep: RGBA) {
        let feather = RGBA(252, 250, 244), shade = RGBA(216, 208, 196), quill = RGBA(226, 212, 184), line = RGBA(186, 174, 158)
        for s in side ? [-1.0] : [-1.0, 1.0] {
            func P(_ x: Double, _ y: Double) -> (Double, Double) { (X(s * x + (side ? -3 : 0)), Y(y)) }
            // the whole wing first: shoulder, up over the wrist to the high tip, down the outer edge to the long tips
            let outline = [P(6, 45), P(12, 34), P(21, 27), P(29.5, 24), P(31, 33), P(31, 46), P(29, 58), P(25, 68), P(19, 70), P(14, 63), P(9, 54)]
            c.inkColor = line
            soft(&c, outline, feather, ink: 0.7, light: 0.12, shadow: 0.14, rim: false)
            c.inkColor = nil
            // flight feathers: from points along the arm out to the lower outer edge, each a long blade with a
            // shadowed trailing side, a quill and a rounded tip
            let roots = [P(10, 42), P(13, 38), P(16, 35), P(19, 32), P(22, 30), P(25, 28)]
            let tips = [P(16.5, 67), P(20.5, 69), P(24.5, 66.5), P(28, 61), P(30.5, 53), P(31, 44)]
            for i in (0..<roots.count).reversed() {
                let r = roots[i], t = tips[i]
                let dx = t.0 - r.0, dy = t.1 - r.1, len = max(1e-6, (dx * dx + dy * dy).squareRoot())
                let nx = -dy / len, ny = dx / len, wdt = 2.6 * k
                c.inkColor = line
                c.poly([(r.0 + nx * wdt, r.1 + ny * wdt), (t.0 + nx * wdt * 0.7, t.1 + ny * wdt * 0.7), (t.0 + dx / len * 1.4 * k, t.1 + dy / len * 1.4 * k), (t.0 - nx * wdt * 0.7, t.1 - ny * wdt * 0.7), (r.0 - nx * wdt, r.1 - ny * wdt)], feather, ink: 0.5)
                c.inkColor = nil
                c.poly([(r.0, r.1), (t.0, t.1), (t.0 - nx * wdt * 0.7, t.1 - ny * wdt * 0.7), (r.0 - nx * wdt, r.1 - ny * wdt)], RGBA(shade.r, shade.g, shade.b, 140))
                c.line(r.0, r.1, t.0 - dx / len * 1.0 * k, t.1 - dy / len * 1.0 * k, 0.35 * k, quill)
                // fine barbs along the lit side
                for j in 1..<5 {
                    let u = Double(j) / 5
                    let mx = r.0 + dx * u, my = r.1 + dy * u
                    c.line(mx, my, mx + nx * wdt * 0.8 + dx / len * 0.8 * k, my + ny * wdt * 0.8 + dy / len * 0.8 * k, 0.2 * k, RGBA(220, 212, 200))
                }
            }
            // shorter feathers over the middle of the wing, scalloped
            for j in 0..<7 {
                let t = Double(j) / 6
                let cx = X(s * (9 + t * 19) + (side ? -3 : 0)), cy = Y(48 - t * 14 + sin(t * .pi) * 2)
                c.inkColor = line
                c.ellipse(cx, cy, 2.6 * k, 3.8 * k, feather, ink: 0.45, shade: Shade(shadow: 0.1, light: 0.08))
            }
            // gold coverts: three rows of scale-like feathers along the top edge, brightest in the top row
            for row in 0..<3 {
                let m = 7 - row
                for j in 0..<m {
                    let t = Double(j) / Double(max(1, m - 1))
                    let x = 7 + t * (20 - Double(row) * 2.5), y = 43 - t * (14.5 - Double(row)) + Double(row) * 2.6
                    let (px, py) = P(x, y)
                    c.inkColor = goldDeep
                    c.ellipse(px, py, 2.0 * k, 1.5 * k, row == 0 ? gold.lightened(0.18) : (row == 1 ? gold : gold.darkened(0.08)), ink: 0.4, shade: Shade(shadow: 0.24, light: 0.32))
                    c.inkColor = nil
                    c.ellipse(px - s * 0.5 * k, py - 0.5 * k, 0.6 * k, 0.4 * k, RGBA(255, 244, 210, 200))
                }
            }
            c.inkColor = nil
        }
    }

    /// The gold halo, behind the head and above it (drawn first, so the head and hair cover its lower part).
    static func angelHalo(_ c: inout Canvas, X: (Double) -> Double, hy: Double, k: Double, side: Bool, gold: RGBA, goldDeep: RGBA) {
        c.inkColor = nil
        let hx = X(side ? -3 : 0), hcy = hy - 15 * k, ry = 10 * k, rx = side ? ry * 0.36 : ry
        var prev: (Double, Double)?
        for i in 0...56 {
            let a = Double(i) / 56 * 2 * .pi
            let p = (hx + cos(a) * rx, hcy + sin(a) * ry)
            if let q = prev { c.line(q.0, q.1, p.0, p.1, 1.2 * k, goldDeep); c.line(q.0, q.1, p.0, p.1, 0.65 * k, gold.lightened(0.22)) }
            prev = p
        }
        for i in 0..<(side ? 3 : 8) {
            let a = Double(i) / Double(side ? 3 : 8) * 2 * .pi - .pi / 2
            let px = hx + cos(a) * rx, py = hcy + sin(a) * ry
            let ox = cos(a) * (side ? 0.36 : 1), oy = sin(a)
            c.poly([(px - oy * 0.9 * k, py + ox * 0.9 * k), (px + ox * 3.2 * k, py + oy * 3.2 * k), (px + oy * 0.9 * k, py - ox * 0.9 * k)], gold, ink: 0.3)
            c.ellipse(px, py, 0.7 * k, 0.7 * k, gold.lightened(0.3))
        }
    }

    /// A small crown of gold spikes on the head with a pale jewel, and a gold mark on the brow.
    static func angelCrown(_ c: inout Canvas, X: (Double) -> Double, hy: Double, k: Double, side: Bool, gold: RGBA, goldDeep: RGBA, female: Bool) {
        c.inkColor = goldDeep
        // the crown on the head: a band and five spikes, a pale jewel in the middle
        let by = hy - 12.5 * k, w = (side ? 6.0 : 9.0) * k
        let cxm = X(side ? 2 : 0)
        c.rect(cxm - w, by, 2 * w, 1.6 * k, gold, ink: 0.4)
        for i in 0..<5 {
            let t = Double(i) / 4, x = cxm - w + t * 2 * w
            let tall = (i == 2 ? 5.5 : (i == 1 || i == 3 ? 3.8 : 2.6)) * k
            c.poly([(x - 1.0 * k, by), (x, by - tall), (x + 1.0 * k, by)], gold, ink: 0.35, shade: Shade(shadow: 0.25, light: 0.3))
            c.ellipse(x, by - tall, 0.45 * k, 0.45 * k, gold.lightened(0.35))
        }
        c.ellipse(cxm, by + 0.8 * k, 1.0 * k, 1.1 * k, RGBA(196, 226, 255), ink: 0.4)
        if female && !side {
            // a gold mark on the brow
            c.line(cxm, hy - 6.4 * k, cxm, hy - 4.8 * k, 0.4 * k, gold)
        }
    }

    /// A big glossy eye: a pale sclera, the iris dark above and bright below with a ring of light, a tall
    /// pupil, three catchlights and a little star, a heavy upper lash with two flicks, a coloured lower lash and
    /// the crease of the lid above.
    static func moeEye(_ c: inout Canvas, _ x: Double, _ y: Double, _ k: Double, _ iris: RGBA, _ lash: RGBA, side: Bool) {
        let w = (side ? 3.8 : 4.6) * k, h = 6.2 * k
        c.inkColor = nil
        c.ellipse(x, y, w, h, RGBA(250, 252, 255))
        // the iris: vertical gradient, a lighter ring near the bottom
        c.paint(x - w, y - h, x + w, y + h, inside: { px, py in let u = (px - x) / (w * 0.84), v = (py - y - 0.4 * k) / (h * 0.9); return u * u + v * v <= 1 },
                color: { px, py in
                    let t = (py - (y - h)) / (2 * h)
                    var col = t < 0.5 ? mix(shadowed(iris, 0.55), iris, t * 2) : mix(iris, iris.lightened(0.45), (t - 0.5) * 2)
                    let u = (px - x) / (w * 0.84), v = (py - y - 0.4 * k) / (h * 0.9), r = (u * u + v * v).squareRoot()
                    if r > 0.78 && t > 0.45 { col = mix(col, iris.lightened(0.6), 0.5) }
                    return col
                })
        // fine streaks in the iris, from the pupil out, and a darker rim
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi
            let r0 = 0.35, r1 = 0.78
            c.line(x + cos(a) * w * 0.84 * r0, y + 0.4 * k + sin(a) * h * 0.9 * r0, x + cos(a) * w * 0.84 * r1, y + 0.4 * k + sin(a) * h * 0.9 * r1, 0.22 * k, RGBA(255, 255, 255, 46))
        }
        c.paint(x - w, y - h, x + w, y + h, inside: { px, py in let u = (px - x) / (w * 0.84), v = (py - y - 0.4 * k) / (h * 0.9), r = u * u + v * v; return r <= 1 && r > 0.82 },
                color: { _, _ in shadowed(iris, 0.65) })
        c.ellipse(x, y + 0.8 * k, w * 0.32, h * 0.42, shadowed(iris, 0.75))                          // the pupil
        c.ellipse(x - w * 0.36, y - h * 0.32, w * 0.34, w * 0.3, .white)                               // catchlights
        c.ellipse(x + w * 0.34, y + h * 0.3, w * 0.17, w * 0.17, RGBA(255, 255, 255, 230))
        c.ellipse(x + w * 0.05, y + h * 0.55, w * 0.1, w * 0.1, RGBA(255, 255, 255, 200))
        let sx = x + w * 0.4, sy = y - h * 0.15                                                      // a small star
        c.line(sx - 0.9 * k, sy, sx + 0.9 * k, sy, 0.45, .white); c.line(sx, sy - 0.9 * k, sx, sy + 0.9 * k, 0.45, .white)
        // lashes and lids
        c.curve([(x - w - 0.7, y - h * 0.3), (x - w * 0.5, y - h - 0.6), (x + w * 0.5, y - h - 0.6), (x + w + 0.7, y - h * 0.35)], 1.7 * k, lash.darkened(0.25))
        c.line(x + w + 0.5, y - h * 0.35, x + w + 2.2 * k, y - h * 0.62, 1.0 * k, lash.darkened(0.25))
        c.line(x + w + 0.2, y - h * 0.1, x + w + 1.7 * k, y - h * 0.15, 0.8 * k, lash.darkened(0.25))
        c.curve([(x - w * 0.6, y - h - 2.0 * k), (x, y - h - 2.6 * k), (x + w * 0.6, y - h - 2.0 * k)], 0.6, lash)          // the crease
        c.curve([(x - w * 0.55, y + h + 0.3), (x, y + h + 0.8), (x + w * 0.55, y + h + 0.3)], 0.7, lash.lightened(0.15))   // the lower lash
        // the upper lid's shadow on the white of the eye, and three short lower lashes
        c.paint(x - w, y - h, x + w, y - h * 0.45, inside: { px, py in let u = (px - x) / w, v = (py - y) / h; return u * u + v * v <= 1 },
                color: { _, _ in RGBA(120, 110, 170, 60) })
        for i in [-1.0, 0, 1] { c.line(x + i * w * 0.4, y + h + 0.6, x + i * w * 0.48, y + h + 1.6 * k, 0.35 * k, lash.lightened(0.1)) }
    }
}
