import Foundation

// The anime figures, turned to any angle (not only front, back and the two sides).
//
// The figure is modelled in its own space and painted from wherever the camera stands:
// * body space: x across the body (to the viewer's right when the figure looks at the viewer), y down the
//   picture (the 64 x 80 plan's units, feet at 76), z forward (the way the figure looks);
// * the figure is turned by `yaw` about the upright axis (0: looking at the viewer, 90°: looking to the
//   screen's right, 180°: the back), then projected straight onto the picture; what is nearer the viewer is
//   painted later (the parts are sorted by depth each time);
// * limbs are tapered strokes between turned joints; skirts, bodices and sleeves are solids of revolution whose
//   outline does not change with the turn, with their details (buttons, folds, bows, filigree) laid on the
//   surface at an angle round it: they slide round, shrink as they turn away and are hidden behind;
// * the head is a real sphere painted pixel by pixel: every pixel finds the point of the sphere it shows,
//   turns it back into the head's own angles and asks whether that point is skin or hair (a hairline that is
//   high over the brow with a fringe of pointed locks, at the ears on the sides and low at the nape), with
//   strand lines and a broken ring of gloss that turn with the head; eyes, brows, blush, nose and mouth are laid
//   on the sphere and foreshorten towards the edge.
// Pictures are made in 16 turns (22.5° apart): `turnStep` says which one a camera sees.

extension AnimeArt {
    public static let turnSteps = 16

    /// The drawing name of a turn step ("t0" ... "t15"; 0 faces the viewer, 4 looks to the screen's right).
    public static func turnDir(_ step: Int) -> String { "t\(((step % turnSteps) + turnSteps) % turnSteps)" }

    /// The turn step a camera sees: `facing` is where the person looks on the ground (x east, y south),
    /// `toward` the camera's forward direction on the ground, `right` the screen's right on the ground.
    public static func turnStep(facing f: Vec2, toward fwd: Vec2, right: Vec2) -> Int {
        let fl = max(1e-9, (f.x * f.x + f.y * f.y).squareRoot())
        let fx = f.x / fl, fy = f.y / fl
        let towardCamera = -(fx * fwd.x + fy * fwd.y), across = fx * right.x + fy * right.y
        let a = atan2(across, towardCamera)                        // 0: at the camera; +90°: to the right
        let s = Int((a / (2 * .pi) * Double(turnSteps)).rounded())
        return ((s % turnSteps) + turnSteps) % turnSteps
    }

    /// The turn step seen from above in 2D (the camera looks down with the north at the top).
    public static func turnStep(facing f: Vec2) -> Int { turnStep(facing: f, toward: Vec2(0, -1), right: Vec2(1, 0)) }

    /// A turn step from a drawing name ("t5"), or the nearest for the old names ("down", "up", "side").
    static func turnIndex(_ dir: String) -> Int? {
        if dir.hasPrefix("t"), let n = Int(dir.dropFirst()) { return ((n % turnSteps) + turnSteps) % turnSteps }
        return nil
    }

    /// The old four drawings for a turn step (for figures only drawn that way): the drawing and whether it is
    /// mirrored (the side drawing looks to the right).
    static func cardinal(_ step: Int) -> (dir: String, mirrored: Bool) {
        let a = Double(step) / Double(turnSteps) * 360
        if a <= 45 || a >= 315 { return ("down", false) }
        if a >= 135 && a <= 225 { return ("up", false) }
        return ("side", a > 180)
    }

    static func mirrored(_ b: Bitmap) -> Bitmap {
        var o = b
        for y in 0..<b.h { for x in 0..<b.w { o.set(b.w - 1 - x, y, b.get(x, y)) } }
        return o
    }
}

/// The proportions a turned figure is built on.
struct TurnBody {
    var headY: Double, headRX: Double, headRY: Double
    var shoulderY: Double, shoulderX: Double
    var chestTop: Double, chestR: Double, waistY: Double
    var hemY: Double, hemR: Double, skirt: Bool
    var legX: Double, legTop: Double, ankleY: Double, footY: Double, legW: Double
    var armW: Double, handY: Double, handX: Double
    var hero: Bool

    static func moe(female: Bool) -> TurnBody {
        TurnBody(headY: 26, headRX: 15, headRY: 14.2, shoulderY: 45, shoulderX: 8.5, chestTop: 43, chestR: 8.5, waistY: 50,
                 hemY: female ? 63 : 60, hemR: female ? 13 : 10, skirt: female, legX: 4, legTop: 61, ankleY: 72, footY: 73.6, legW: 4.6,
                 armW: 3.4, handY: 56, handX: 11, hero: false)
    }
    static func hero(female: Bool) -> TurnBody {
        TurnBody(headY: 20, headRX: 8.6, headRY: 10, shoulderY: 34, shoulderX: 8.8, chestTop: 33, chestR: 8.6, waistY: 51,
                 hemY: female ? 61 : 55, hemR: female ? 10.5 : 7.8, skirt: female, legX: 4, legTop: 53, ankleY: 71, footY: 74.5, legW: 6.2,
                 armW: 4.2, handY: 52, handX: 10.5, hero: true)
    }
}

extension AnimeArt {
    /// A figure turned to `step` of 16 (moe, angel or hero clothes by `kind`), on the 64 x 80 plan.
    static func turned(_ look: Look, step: Int, frame: Int, held: String, child: Bool, female: Bool, kind: Figure) -> Bitmap {
        let angel = kind == .angel && !child
        let b = kind == .hero ? TurnBody.hero(female: female) : TurnBody.moe(female: female)
        var c = Canvas(charW, charH, scale: figureScale)
        let yaw = Double(step) / Double(turnSteps) * 2 * .pi
        let C = cos(yaw), S = sin(yaw)
        let skin = pastel(RGBA(hex: look.skin)).lightened(0.04), hair = pastel(RGBA(hex: look.hair)).lightened(0.06)
        let cloth = angel ? RGBA(250, 246, 236) : pastel(RGBA(hex: look.shirt))
        let pants = angel ? RGBA(78, 70, 78) : pastel(RGBA(hex: look.pants))
        let shoes = angel ? RGBA(226, 190, 96) : (b.hero ? pastel(RGBA(hex: look.shoes)).darkened(0.15) : pastel(RGBA(hex: look.shoes)))
        let gold = RGBA(222, 178, 70), goldDeep = RGBA(160, 112, 36)
        let white = RGBA(250, 250, 255), frill = RGBA(244, 246, 255), leather = RGBA(74, 58, 52), metal = RGBA(214, 206, 180)
        let hairInk = shadowed(hair, 0.5).darkened(0.15), skinInk = RGBA(176, 112, 104), clothInk = shadowed(cloth, 0.55)
        let iris = angel ? RGBA(236, 184, 60) : irisColor(hair).lightened(0.05)
        let style = look.style % 4
        let walk = frame == 1 ? 1.0 : (frame == 2 ? -1.0 : 0)
        let bob = frame == 1 || frame == 2 ? -1.2 : 0
        let act = frame == 3
        let k: Double = child ? (b.hero ? 0.78 : 0.84) : 1
        let cx = 32.0, foot = 76.0
        let long = female || style == 2

        // projection: body space to the picture
        func X(_ x: Double, _ z: Double) -> Double { cx + (x * C + z * S) * k }
        func D(_ x: Double, _ z: Double) -> Double { -x * S + z * C }
        func Y(_ v: Double) -> Double { foot - (76 - v) * k + (v < b.legTop + 1 ? bob : 0) }
        /// A point on a ring round the upright axis: `phi` round from the front (positive to the figure's
        /// left as the viewer sees it at yaw 0), radius r.
        func ring(_ phi: Double, _ r: Double) -> (x: Double, z: Double) { (r * sin(phi), r * cos(phi)) }
        /// How much a point at angle phi round the body faces the viewer (1: straight at them, < 0: hidden).
        func facing(_ phi: Double) -> Double { cos(phi + yaw) }
        func ringX(_ phi: Double, _ r: Double) -> Double { cx + r * sin(phi + yaw) * k }

        var items: [(depth: Double, draw: (inout Canvas) -> Void)] = []
        func add(_ d: Double, _ f: @escaping (inout Canvas) -> Void) { items.append((d, f)) }

        // the ground shadow (always first)
        c.ellipse(cx, foot - 1, 12 * k, 2.8 * k, RGBA(0, 0, 0, 55))

        // MARK: wings (an angel's): two feathered wings from the shoulder blades, spread out and back
        if angel {
            for s in [-1.0, 1.0] {
                func W(_ u: Double, _ v: Double) -> (Double, Double) {
                    // u: out along the wing, v: the plan's height; the wing sweeps back as it goes out
                    let x = s * (3 + u * 0.62), z = -4 - u * 0.4
                    return (X(x, z), Y(v))
                }
                let outline: [(Double, Double)] = [W(0, 46), W(6, 38), W(13, 31), W(21, 27), W(26, 29), W(25, 35), W(22, 42), W(19, 49), W(15, 55), W(10, 59), W(5, 56), W(1, 51)]
                let depth = D(s * 12, -9)
                add(depth) { c in
                    c.inkColor = RGBA(186, 174, 158)
                    soft(&c, outline, RGBA(252, 250, 244), ink: 0.9, light: 0.18, shadow: 0.2, rim: false)
                    c.inkColor = nil
                    // long flight feathers fanning to the lower edge, with pale quills
                    for i in 0..<6 {
                        let t = Double(i) / 5
                        let a = W(4 + t * 17, 42 - t * 10), e = W(7 + t * 17, 57 - t * 25)
                        c.line(a.0, a.1, e.0, e.1, 0.45 * k, RGBA(226, 212, 184))
                        c.ellipse(e.0, e.1, 1.6 * k, 1.1 * k, RGBA(240, 234, 222))
                    }
                    // gold coverts along the top like scales
                    for i in 0..<5 {
                        let t = Double(i) / 4
                        let p = W(3 + t * 18, 41 - t * 12)
                        c.ellipse(p.0, p.1, 1.6 * k, 1.2 * k, i % 2 == 0 ? gold : goldDeep.lightened(0.2))
                    }
                }
            }
        }

        // MARK: long hair behind (a sheet down the back, seen from behind or round the sides)
        if long {
            let low = b.hero ? b.headY + 30 : b.headY + 34
            let top = b.headY - 6, r0 = b.headRX + 0.6, r1 = b.headRX * 0.8
            let poly = sweep(ys: stride(from: top, through: low, by: 2).map { $0 }, radius: { y in r0 + (r1 - r0) * (y - top) / (low - top) },
                             phi0: .pi / 2, phi1: 3 * .pi / 2, yaw: yaw, cx: cx, k: k, Y: Y)
            add(D(0, -b.headRX) - 2) { c in
                c.inkColor = hairInk
                soft(&c, poly, shadowed(hair, 0.12), ink: 1.1, rim: false)
                c.inkColor = nil
                // strands running down it, where they face the viewer
                for i in 0..<9 {
                    let phi = .pi / 2 + Double(i + 1) / 10 * .pi
                    guard facing(phi) > 0.05 else { continue }
                    c.curve([(ringX(phi, r0), Y(top + 4)), (ringX(phi, (r0 + r1) / 2), Y((top + low) / 2)), (ringX(phi, r1), Y(low - 2))], 0.45 * k, hairInk.lightened(0.1))
                }
            }
        }
        // twin tails tied high at the back of the sides (style 1)
        if style == 1 {
            for s in [-1.0, 1.0] {
                let phi = s * 1.9
                let base = ring(phi, b.headRX * 0.95)
                let sway = walk * 0.8
                let pts: [(Double, Double, Double)] = [(0, b.headY - 12, 0), (s * 6, b.headY - 6, -2), (s * 9, b.headY + 12, -3), (s * 6 + sway, b.headY + 30, -4), (s * 3, b.headY + 18, -2), (s * 1, b.headY - 2, -1)]
                let poly = pts.map { (X(base.x + $0.0, base.z + $0.2), Y($0.1)) }
                add(D(base.x + s * 6, base.z - 3)) { c in
                    c.inkColor = hairInk
                    soft(&c, poly, hair, ink: 1.1, rim: s > 0)
                    c.inkColor = nil
                    for t in [0.3, 0.6] { c.curve([(X(base.x + s * (2 + 5 * t), base.z - 2), Y(b.headY + 30 * t - 4)), (X(base.x + s * (4 + 3 * t), base.z - 3), Y(b.headY + 30 * t + 4))], 0.7, hairInk) }
                }
            }
        }

        // MARK: the angel's train (the robe sweeping behind to the ground)
        if angel {
            let poly = sweep(ys: stride(from: b.waistY - 2, through: foot, by: 2).map { $0 }, radius: { y in 8 + (y - b.waistY + 2) / (foot - b.waistY + 2) * 9 },
                             phi0: .pi * 0.55, phi1: .pi * 1.45, yaw: yaw, cx: cx, k: k, Y: Y, back: { y in (y - b.waistY) * 0.35 })
            add(D(0, -12)) { c in
                c.inkColor = RGBA(206, 196, 176)
                soft(&c, poly, RGBA(244, 238, 226, 235), ink: 0.8, light: 0.1, shadow: 0.16, rim: false)
                c.inkColor = nil
            }
        }

        // MARK: legs and shoes
        for s in [-1.0, 1.0] {
            let swing = (s < 0 ? walk : -walk) * 3.2
            let lift = (frame == 1 && s < 0) || (frame == 2 && s > 0) ? 1.4 : 0
            let hipX = s * b.legX, kneeZ = swing * 0.5, ankZ = swing
            let hip = (X(hipX, 0), Y(b.legTop)), ank = (X(hipX, ankZ), Y(b.ankleY - lift))
            let knee = (X(hipX, kneeZ), Y((b.legTop + b.ankleY) / 2 - lift / 2))
            let depth = D(hipX, ankZ)
            let far = depth < 0
            add(depth) { c in
                let col = far ? shadowed(pants, 0.12) : pants
                c.inkColor = shadowed(pants, 0.5)
                if b.hero {
                    c.line(hip.0, hip.1, knee.0, knee.1, b.legW * k, col, ink: 1.0)
                    c.line(knee.0, knee.1, ank.0, ank.1, (b.legW - 1.4) * k, col, ink: 1.0)
                    c.line(knee.0 - 1.2 * k, knee.1 - 0.5, knee.0 + 1 * k, knee.1, 0.8, shadowed(pants, 0.4))
                } else {
                    c.line(hip.0, hip.1, ank.0, ank.1, b.legW * k, col, ink: 1.0)
                }
                // the shoe: longer along the foot, so it grows as the figure turns side-on
                let fz = ankZ + 1.6, fx = hipX
                let sx = X(fx, fz), sy = Y(b.footY - lift)
                let rx = ((2.6 * C) * (2.6 * C) + (4.4 * S) * (4.4 * S)).squareRoot() * k + 1.2 * k
                let shoeCol = far ? shadowed(shoes, 0.1) : shoes
                c.inkColor = shadowed(shoes, 0.5)
                if b.hero {
                    // a boot: a shaft to mid-shin and the foot
                    c.line(ank.0, ank.1 - 4 * k, ank.0, sy - 1, 4.6 * k, shoeCol, ink: 1.0)
                    c.rect(ank.0 - 2.4 * k, ank.1 - 4.8 * k, 4.8 * k, 1.5, shoeCol.lightened(0.2))
                }
                c.ellipse(sx, sy, rx, 2.6 * k, shoeCol, ink: 1.0, shade: Shade(shadow: 0.15, light: 0.25))
                c.inkColor = nil
                c.ellipse(sx - 1, sy - 0.9, min(1.4 * k, rx * 0.4), 0.7 * k, RGBA(255, 255, 255, 160))
                if !b.hero {
                    c.line(sx - rx * 0.6, sy - 1.3, sx + rx * 0.6, sy - 1.3, 0.55 * k, shadowed(shoes, 0.4))       // the strap
                    c.ellipse(sx + rx * 0.35 * (S >= 0 ? 1 : -1), sy - 1.3, 0.55 * k, 0.45 * k, RGBA(240, 200, 90))
                }
                if female && !b.hero {
                    // the lace band at the top of the stocking
                    let ty = Y(64.2)
                    c.line(hip.0 - 2.1 * k, ty, hip.0 + 2.1 * k, ty, 0.9 * k, frill)
                    for i in 0..<4 { c.ellipse(hip.0 - 1.6 * k + Double(i) * 1.07 * k, ty + 0.7, 0.42 * k, 0.42 * k, frill) }
                }
            }
        }

        // MARK: the body: a skirt or coat tail, the bodice or jacket, the sash or belt, and their details
        let bodyDepth = 0.0
        add(bodyDepth) { c in
            c.inkColor = clothInk
            if b.skirt || !b.hero {
                // a bell (its outline is the same from every side)
                let top = b.waistY - 2, topR = b.hero ? 8.0 : (female ? 8 : 9)
                soft(&c, [(cx - topR * k, Y(top)), (cx + topR * k, Y(top)), (cx + b.hemR * k, Y(b.hemY)), (cx - b.hemR * k, Y(b.hemY))], b.hero ? shadowed(cloth, 0.08) : cloth, ink: 1.1)
                // the frilled hem: scallops round the near half, a little lower in front (the hem is a circle seen from above)
                if female && !b.hero {
                    var phi = -Double.pi
                    while phi < .pi {
                        let f = facing(phi)
                        if f > -0.15 { c.ellipse(ringX(phi, b.hemR - 0.4), Y(b.hemY + 0.6) + f * 0.9 * k, 1.6 * k, 1.3 * k, frill, ink: 0.6) }
                        phi += 0.38
                    }
                    var p2 = -Double.pi
                    while p2 < .pi {
                        let f = facing(p2)
                        if f > 0 { c.ellipse(ringX(p2, b.hemR - 1.2), Y(b.hemY + 2) + f * 0.9 * k, 0.7 * k, 0.6 * k, frill.darkened(0.06)) }
                        p2 += 0.2
                    }
                }
                // folds from the waist to the hem, a lighter crest beside each
                c.inkColor = nil
                let n = female ? 10 : 6
                for i in 0..<n {
                    let phi = Double(i) / Double(n) * 2 * .pi
                    let f = facing(phi)
                    guard f > 0.12 else { continue }
                    let x0 = ringX(phi, topR * 0.8), x1 = ringX(phi, b.hemR * 0.95)
                    c.curve([(x0, Y(top + 3)), ((x0 + x1) / 2, Y((top + b.hemY) / 2)), (x1, Y(b.hemY - 0.8))], 0.5 * k, shadowed(cloth, 0.32))
                    c.curve([(x0 + 0.9 * f, Y(top + 3.5)), ((x0 + x1) / 2 + 1.0 * f, Y((top + b.hemY) / 2)), (x1 + 1.1 * f, Y(b.hemY - 1.4))], 0.45 * k, cloth.lightened(0.18))
                }
            }
            // the bodice or the jacket: a short upright cylinder
            c.inkColor = clothInk
            let torsoBot = b.hero ? b.hemY : b.waistY + 1
            let botR = b.hero ? b.chestR - 1 : b.chestR - 0.5
            soft(&c, [(cx - b.chestR * k, Y(b.chestTop)), (cx + b.chestR * k, Y(b.chestTop)), (cx + botR * k, Y(torsoBot)), (cx - botR * k, Y(torsoBot))], cloth.lightened(0.05), ink: b.hero ? 1.3 : 1.1)
            c.inkColor = nil
            // the sash or the belt round the waist
            let sashY = b.hero ? Y(b.waistY) : Y(b.waistY - 0.4)
            c.rect(cx - (b.chestR - 0.3) * k, sashY, 2 * (b.chestR - 0.3) * k, (b.hero ? 2.6 : 1.5) * k, b.hero ? leather : shadowed(cloth, 0.28))
            // the buckle (hero) or the bow behind (moe)
            let front = facing(0), back = facing(.pi)
            if b.hero && front > 0.1 {
                let bx = ringX(0, b.chestR - 0.5)
                c.rect(bx - 1.5 * k * front, sashY - 0.4, 3 * k * front, 3.2 * k, metal, ink: 0.7)
            }
            if !b.hero && back > 0.15 {
                let bx = ringX(.pi, b.chestR), w = 5 * back
                let sash = shadowed(cloth, 0.28).lightened(0.1)
                c.poly([(bx, Y(50.3)), (bx - w * k, Y(47.8)), (bx - w * k, Y(53))], sash, ink: 0.5, shade: Shade(shadow: 0.2))
                c.poly([(bx, Y(50.3)), (bx + w * k, Y(47.8)), (bx + w * k, Y(53))], sash, ink: 0.5, shade: Shade(shadow: 0.2))
                c.line(bx - 1 * back, Y(51), bx - 3 * back, Y(57), 1.2 * k, sash); c.line(bx + 1 * back, Y(51), bx + 3 * back, Y(57), 1.2 * k, sash)
            }
            if b.hero {
                // the inner layer and lapels down the front; a seam down the back
                if front > 0.2 {
                    let fx = ringX(0, b.chestR), w = 3.2 * front
                    c.poly([(fx - w * k, Y(b.chestTop)), (fx + w * k, Y(b.chestTop)), (fx + w * 0.75 * k, Y(b.waistY + 1)), (fx - w * 0.75 * k, Y(b.waistY + 1))], shadowed(cloth, 0.45))
                    c.line(fx - w * k, Y(b.chestTop), fx - w * 0.7 * k, Y(b.waistY + 1), 1.0, AnimeArt.ink)
                    c.line(fx + w * k, Y(b.chestTop), fx + w * 0.7 * k, Y(b.waistY + 1), 1.0, AnimeArt.ink)
                    c.poly([(fx - 6 * front * k, Y(b.chestTop)), (fx - 1 * front * k, Y(b.chestTop)), (fx - 3.6 * front * k, Y(b.chestTop + 6))], cloth.lightened(0.18), ink: 0.8)
                    c.poly([(fx + 6 * front * k, Y(b.chestTop)), (fx + 1 * front * k, Y(b.chestTop)), (fx + 3.6 * front * k, Y(b.chestTop + 6))], cloth.lightened(0.12), ink: 0.8)
                }
                if back > 0.2 { let x = ringX(.pi, b.chestR); c.line(x, Y(b.chestTop + 2), x, Y(b.hemY - 1), 0.9, shadowed(cloth, 0.35)) }
            } else if front > 0.2 {
                // the collar, two small buttons, and a bow (or a tie) at the throat
                let fx = ringX(0, b.chestR), f = front
                c.poly([(fx - 6 * f * k, Y(43)), (fx + 6 * f * k, Y(43)), (fx, Y(48))], white, ink: 0.7)
                for y in [48.6, 50.6] where !female || y > 49 { c.ellipse(fx, Y(y), 0.65 * k * max(0.5, f), 0.65 * k, white) }
                if female {
                    let bow = RGBA(255, 112, 150)
                    c.poly([(fx, Y(46)), (fx - 4.5 * f * k, Y(43.5)), (fx - 4.5 * f * k, Y(48.5))], bow, ink: 0.8, shade: Shade(shadow: 0.2))
                    c.poly([(fx, Y(46)), (fx + 4.5 * f * k, Y(43.5)), (fx + 4.5 * f * k, Y(48.5))], bow, ink: 0.8, shade: Shade(shadow: 0.2))
                    c.ellipse(fx, Y(46), 1.3 * k * max(0.5, f), 1.3 * k, bow.lightened(0.2), ink: 0.6)
                } else {
                    c.rect(fx - 1 * f * k, Y(44), 2 * f * k, 6 * k, shadowed(cloth, 0.35))
                }
            }
            if angel && front > 0.15 {
                // gold filigree down the front of the robe, and a jewel at the waist
                let fx = ringX(0, b.chestR), f = front
                c.curve([(fx, Y(43.5)), (fx + 0.3 * f, Y(50)), (ringX(0, b.hemR), Y(b.hemY))], 0.5 * k, gold)
                for sgn in [-1.0, 1.0] {
                    c.curve([(fx, Y(51)), (fx + sgn * 3 * f * k, Y(53.5)), (fx + sgn * 5.5 * f * k, Y(52.5)), (fx + sgn * 6 * f * k, Y(55))], 0.4 * k, gold)
                    c.curve([(ringX(sgn * 0.2, 2), Y(56)), (ringX(sgn * 0.4, 6), Y(59)), (ringX(sgn * 0.6, b.hemR - 1), Y(b.hemY - 0.5))], 0.4 * k, gold)
                }
                c.ellipse(fx, Y(50.2), 1.0 * k * max(0.4, f), 1.2 * k, RGBA(200, 226, 255), ink: 0.4)
            }
            // shoulder pieces on a soldier's or traveller's coat
            if b.hero && !female && (style == 0 || style == 1) {
                for s in [-1.0, 1.0] where D(s * b.shoulderX, 0) > -3 {
                    let px = X(s * (b.shoulderX + 1), 0)
                    c.inkColor = clothInk
                    soft(&c, [(px - 3 * k, Y(b.chestTop)), (px + 3 * k, Y(b.chestTop - 1.5)), (px + 3.2 * k, Y(b.chestTop + 3)), (px - 2.8 * k, Y(b.chestTop + 5))], shadowed(cloth, 0.2), ink: 1.0)
                    c.inkColor = nil
                }
            }
        }

        // MARK: arms: puffed sleeves (moe) or coat sleeves (hero), hands or gloves; swinging forward and back
        for s in [-1.0, 1.0] {
            let swing = (s < 0 ? -walk : walk) * 3.5
            let raised = act && s > 0
            let sh = (x: s * b.shoulderX, z: 0.0)
            let hand: (x: Double, y: Double, z: Double) = raised ? (s * (b.handX + 2), b.hero ? 25 : 34, 5) : (s * b.handX, b.handY - abs(swing) * 0.4, swing)
            let elbow: (x: Double, y: Double, z: Double) = raised ? (s * (b.handX + 1), b.hero ? 32 : 40, 3) : (s * (b.shoulderX + 1.2), (b.shoulderY + hand.y) / 2, swing * 0.4)
            let depth = D(hand.x, hand.z) * 0.5 + D(sh.x, sh.z) * 0.5
            add(depth + (depth < 0 ? -0.1 : 0.1)) { c in
                let far = depth < 0
                let sleeve = far ? shadowed(cloth, 0.12) : cloth
                let sx = X(sh.x, sh.z), sy = Y(b.shoulderY)
                let ex = X(elbow.x, elbow.z), ey = Y(elbow.y), hx = X(hand.x, hand.z), hy = Y(hand.y)
                c.inkColor = clothInk
                if b.hero {
                    c.line(sx, sy, ex, ey, 4.4 * k, sleeve, ink: 1.1)
                    c.line(ex, ey, hx, hy, 3.8 * k, sleeve, ink: 1.1)
                    c.ellipse(hx, hy + 0.5, 2.3 * k, 2.4 * k, leather, ink: 1.0)
                } else {
                    c.ellipse(sx, sy, 3.8 * k, 3.2 * k, sleeve.lightened(0.08), ink: 1.0, shade: Shade(shadow: 0.18, light: 0.2))
                    let glove = angel ? RGBA(70, 60, 70) : (female ? white : skin)
                    c.inkColor = RGBA(180, 184, 206)
                    c.line(sx, sy + 2, ex, ey, b.armW * k, glove, ink: 0.9)
                    c.line(ex, ey, hx, hy, b.armW * k, glove, ink: 0.9)
                    c.ellipse(hx, hy + 0.5, 2.2 * k, 2.2 * k, glove, ink: 0.8)
                    c.inkColor = nil
                    c.curve([(sx - 1.6 * k, sy - 0.6 * k), (sx, sy + 0.8 * k), (sx + 1.6 * k, sy - 0.4 * k)], 0.45 * k, shadowed(cloth, 0.3))
                    if angel {
                        let cx0 = sx + (ex - sx) * 0.5, cy0 = sy + (ey - sy) * 0.5
                        c.ellipse(cx0, cy0, 2.0 * k, 1.0 * k, gold, ink: 0.4)
                    } else if female {
                        let mx = sx + (ex - sx) * 0.75, my = sy + (ey - sy) * 0.75
                        for i in -1...1 { c.ellipse(mx + Double(i) * 1.1 * k, my, 0.75 * k, 0.65 * k, frill.darkened(0.05)) }
                    }
                }
                c.inkColor = nil
                if raised || (s > 0 && !held.isEmpty) {
                    if !held.isEmpty {
                        if b.hero { heroItem(&c, held, hx, hy, k * 0.9) } else { heldItem(&c, held, hx, hy, k * 0.9) }
                    }
                }
            }
        }

        // paint the body back to front
        for it in items.sorted(by: { $0.depth < $1.depth }) { it.draw(&c) }
        items.removeAll()

        // MARK: the head
        let hy = Y(b.headY)
        let rx = b.headRX * k, ry = b.headRY * k
        // the neck (and a choker on a moe girl)
        c.inkColor = skinInk
        if b.hero { c.rect(cx - 2.2 * k, Y(b.headY + 8), 4.4 * k, 5.5 * k, shadowed(skin, 0.18)) }
        if !b.hero && female && facing(0) > -0.2 { c.rect(cx - 5 * k, Y(39.5), 10 * k, 1.8 * k, RGBA(70, 90, 170), ink: 0.5) }

        // the hairline, by the angle round the head (0: the middle of the brow) in units of the head's height
        // below its centre: the fringe's pointed locks over the brow, the ears at the sides, low at the nape
        let locks = b.hero ? 7.0 : 9.0
        func hairline(_ phi: Double) -> Double {
            var p = phi.truncatingRemainder(dividingBy: 2 * .pi)
            if p > .pi { p -= 2 * .pi }; if p < -.pi { p += 2 * .pi }
            let a = abs(p)
            // the base line: high on the brow, down past the ears, low behind
            let front = b.hero ? -0.74 : -0.66, sides = b.hero ? 0.05 : 0.12, back = b.hero ? 0.75 : 0.95
            var h = a < .pi / 2 ? front + (sides - front) * pow(a / (.pi / 2), 2.2) : sides + (back - sides) * ((a - .pi / 2) / (.pi / 2))
            // the fringe: pointed locks hanging over the brow (never down to the eyes)
            if a < 1.25 {
                let t = (p / 1.25 + 1) / 2 * locks
                let tri = 1 - abs((t - t.rounded(.down)) * 2 - 1)            // 0 between locks, 1 at a tip
                let reach = (b.hero ? 0.3 : 0.3) * (1 - pow(a / 1.25, 3))
                h += tri * reach
            }
            // (the locks end above the brows: the eyes are never covered)
            return a < 1.25 ? min(h, b.hero ? -0.46 : -0.4) : h
        }

        // ears (behind the hair at the sides, shown when that side is turned towards the viewer)
        func ear(_ s: Double) {
            let phi = s * .pi / 2
            let f = facing(phi)
            guard f > -0.35 else { return }
            let ex = ringX(phi, b.headRX * 0.98), ey = hy + 3 * k * (b.hero ? 0.4 : 1)
            c.inkColor = skinInk
            let er = b.hero ? 0.7 : 1.0
            c.ellipse(ex, ey, (0.8 + 1.0 * abs(sin(phi + yaw))) * er * k, (b.hero ? 2.0 : 3.0) * k, skin, ink: 0.7)
        }
        // what is behind the head comes first: the far ear and the far side lock
        let lockLen: Double = b.hero ? (long ? 14 : 0) : (long ? 26 : 12)
        func sideLock(_ s: Double) {
            guard lockLen > 0 else { return }
            let phi = s * 1.35
            let top = ring(phi, b.headRX + 0.3), bot = ring(phi * 1.05, b.headRX - 1.2)
            let x0 = X(top.x, top.z), x1 = X(bot.x, bot.z)
            let y0 = hy - 4 * k, y1 = hy + lockLen * k
            c.inkColor = hairInk
            soft(&c, [(x0 - 1.8 * k, y0), (x0 + 1.8 * k, y0), (x1 + 1.4 * k, y1 - 3), (x1, y1 + 2), (x1 - 1.6 * k, y1 - 4)], hair, ink: 0.9, rim: s > 0)
            c.inkColor = nil
            c.curve([(x0, y0 + 3), ((x0 + x1) / 2, (y0 + y1) / 2), (x1, y1)], 0.5, hairInk)
        }
        for s in [-1.0, 1.0] where facing(s * .pi / 2) < 0 { ear(s) }
        for s in [-1.0, 1.0] where facing(s * 1.35) < 0 { sideLock(s) }

        // the sphere: every pixel is skin or hair by where on the head it lies
        let gloss = hair.lightened(0.42)
        let warm = mix(skin, RGBA(236, 156, 150), 0.55)
        c.inkColor = hairInk
        c.ellipse(cx, hy, rx, ry, hair, ink: 1.2)
        c.paint(cx - rx, hy - ry, cx + rx, hy + ry, inside: { px, py in let u = (px - cx) / rx, v = (py - hy) / ry; return u * u + v * v <= 1 },
                color: { px, py in
                    let u = (px - cx) / rx, v = (py - hy) / ry
                    let d = max(0, 1 - u * u - v * v).squareRoot()
                    // the point's angle round the head in the head's own frame
                    let phi = atan2(u, d) - yaw
                    let hl = hairline(phi)
                    if v > hl {
                        // skin: the warm shade toward the lower edge; the brow's light; the fringe's soft shadow
                        let r = (u * u + v * v).squareRoot()
                        var col = skin
                        let t = max(0, min(1, (u * 0.45 + v * 0.65 + r * 0.7 - 0.95) / 0.45))
                        if t > 0.01 { col = mix(col, warm, t * 0.47) }
                        if v - hl < 0.1 { col = mix(col, RGBA(150, 90, 110), 0.18) }
                        if v - hl < 0.025 { return hairInk }
                        return col
                    }
                    // hair: strand lines that turn with the head, and a broken ring of gloss near the crown
                    var col = hair
                    let strands = (phi / (2 * .pi) * 28).truncatingRemainder(dividingBy: 1)
                    if abs(strands) < 0.08 && v > -0.92 { col = hairInk.lightened(0.12) }
                    let ringBand = abs(v + (b.hero ? 0.62 : 0.7)) < 0.07
                    let broken = abs((phi / (2 * .pi) * 10).truncatingRemainder(dividingBy: 1)) < 0.62
                    if ringBand && broken && d > 0.25 { col = gloss }
                    // light from the upper left, shadow toward the lower right
                    if u + v > 0.9 { col = shadowed(col, 0.16) } else if u + v < -0.9 { col = col.lightened(0.12) }
                    return col
                })

        // the face's features, laid on the sphere: eyes, brows, blush, nose and mouth
        func onFace(_ phi: Double, _ v: Double) -> (x: Double, y: Double, f: Double) {
            // v in units of the head's height below its centre
            let rh = (max(0, 1 - v * v)).squareRoot()
            return (cx + rx * rh * sin(phi + yaw), hy + ry * v, cos(phi + yaw) * rh)
        }
        let eyeV = b.hero ? 0.06 : 0.28, eyePhi = b.hero ? 0.44 : 0.44
        for s in [-1.0, 1.0] {
            let e = onFace(s * eyePhi, eyeV)
            guard e.f > 0.18 else { continue }
            let squash = pow(min(1, e.f / 0.9), 0.85)
            if b.hero { turnHeroEye(&c, e.x, e.y, k, iris, squash: squash) }
            else { turnMoeEye(&c, e.x, e.y, k, iris, hairInk, squash: squash, outward: s) }
            if b.hero {
                let b0 = onFace(s * 0.62, -0.36), b1 = onFace(s * 0.2, -0.4)
                if b0.f > 0 && b1.f > 0 { c.line(b0.x, b0.y, b1.x, b1.y, 1.0, shadowed(hair, 0.3)) }
            }
        }
        if !b.hero || female {
            for s in [-1.0, 1.0] {
                let bl = onFace(s * 0.72, b.hero ? 0.4 : 0.63)
                guard bl.f > 0.15 else { continue }
                c.ellipse(bl.x, bl.y, 3.2 * k * bl.f * (b.hero ? 0.55 : 1), (b.hero ? 0.9 : 1.6) * k, RGBA(255, 130, 160, 110))
                if !b.hero { for i in 0..<3 { let x = bl.x + (Double(i) - 1) * 1.6 * k * bl.f; c.line(x - 0.5, bl.y + 0.6 * k, x + 0.5, bl.y - 0.6 * k, 0.5, RGBA(245, 130, 160, 150)) } }
            }
        }
        // the nose: a hint in front, the tip against the sky side-on
        let nose = onFace(0, b.hero ? 0.3 : 0.58)
        if nose.f > 0.2 {
            if abs(S) > 0.55 {
                let tip = nose.x + (S > 0 ? 1 : -1) * 1.2 * k
                c.line(nose.x, nose.y - 1.2 * k, tip, nose.y + 0.2 * k, 0.6 * k, skinInk)
            } else {
                c.ellipse(nose.x + 0.4, nose.y, 0.4 * k, 0.3 * k, RGBA(220, 140, 140, 150))
            }
        }
        // the mouth
        let mouth = onFace(0, b.hero ? 0.62 : 0.75)
        if mouth.f > 0.15 {
            let w = 1.2 * k * max(0.35, mouth.f)
            if act {
                c.ellipse(mouth.x, mouth.y, 1.5 * k * max(0.4, mouth.f), 1.3 * k, RGBA(200, 90, 100), ink: 0.5)
                c.ellipse(mouth.x, mouth.y + 0.6 * k, 0.8 * k * max(0.4, mouth.f), 0.5 * k, RGBA(255, 150, 160))
            } else {
                c.curve([(mouth.x - w, mouth.y), (mouth.x, mouth.y + 0.6 * k), (mouth.x + w, mouth.y)], 0.8, RGBA(200, 100, 110))
            }
        }

        // what is in front of the head: the near ear and the near side lock, the ahoge, ornaments
        for s in [-1.0, 1.0] where facing(s * .pi / 2) >= 0 { ear(s) }
        // (the ear shows below the hair at the sides: the hair's edge over it again)
        for s in [-1.0, 1.0] where facing(s * 1.35) >= 0 { sideLock(s) }
        // a ponytail (hero style 3), seen beside the head from the sides and behind
        if b.hero && style == 3 && facing(.pi) > -0.6 {
            let base = ring(.pi, b.headRX)
            let pts: [(Double, Double, Double)] = [(0, -8, 0), (2, -6, -6), (1, 8, -9), (0, 22, -7), (-1, 6, -4)]
            c.inkColor = hairInk
            soft(&c, pts.map { (X(base.x + $0.0, base.z + $0.2), Y(b.headY + $0.1)) }, hair, ink: 1.1)
        }
        // the ahoge
        let crown = ring(0, 0)
        c.curve([(X(crown.x + 1, crown.z), hy - ry * 1.02), (X(crown.x + 3, crown.z + 1), hy - ry * 1.45), (X(crown.x + 7, crown.z + 0.5), hy - ry * 1.52), (X(crown.x + 5.5, crown.z), hy - ry * 1.25)], 1.6, hair)
        c.inkColor = RGBA(150, 150, 180)
        switch angel ? -1 : style {
        case 0 where female && !b.hero:                  // a frilled headband with small flowers
            for i in 0..<13 {
                let phi = -1.5 + Double(i) * 0.25
                let p = onFace(phi, -0.84)
                guard p.f > 0 else { continue }
                c.ellipse(p.x, p.y, 2 * k * max(0.4, p.f), 1.6 * k, frill, ink: 0.6)
                if i % 4 == 2 { c.ellipse(p.x, p.y, 0.6 * k, 0.6 * k, RGBA(255, 214, 90)) }
            }
        case 1:                                          // ribbons where the twin tails are tied
            let rb = RGBA(80, 120, 220)
            for s in [-1.0, 1.0] {
                let p = onFace(s * 1.9, -0.62)
                guard p.f > -0.5 else { continue }
                let w = 4.5 * k * max(0.3, abs(sin(s * 1.9 + yaw)))
                c.poly([(p.x, p.y), (p.x + w, p.y - 3 * k), (p.x + w, p.y + 3 * k)], rb, ink: 0.7, shade: Shade(shadow: 0.2))
                c.poly([(p.x, p.y), (p.x - w, p.y - 3.5 * k), (p.x - w, p.y + 3 * k)], rb, ink: 0.7, shade: Shade(shadow: 0.2))
            }
        case 2:                                          // small curved horns
            c.inkColor = RGBA(30, 28, 40)
            for s in [-1.0, 1.0] {
                let phi = s * 0.6
                let base = onFace(phi, -0.86)
                let tipBody = ring(phi, b.headRX * 0.9)
                let tip = (X(tipBody.x + s * 2, tipBody.z - 1), hy - ry * 1.75)
                let mid = (X(tipBody.x + s * 3, tipBody.z), hy - ry * 1.3)
                let horn = [(base.x - 2 * k, base.y), (base.x + 2 * k, base.y - 0.5), (mid.0 + 1.2 * k, mid.1), (tip.0, tip.1), (mid.0 - 1.2 * k, mid.1)]
                soft(&c, horn, RGBA(70, 66, 82), ink: 0.9, light: 0.35, shadow: 0.35, rim: false)
            }
        case 3 where !b.hero:                            // a flower clip
            let p = onFace(0.6, -0.7)
            if p.f > 0 {
                for i in 0..<5 { let a = Double(i) * 2 * .pi / 5; c.ellipse(p.x + cos(a) * 1.9 * k * max(0.4, p.f), p.y + sin(a) * 1.9 * k, 1.5 * k, 1.5 * k, RGBA(255, 180, 210), ink: 0.5) }
                c.ellipse(p.x, p.y, 1.1 * k, 1.1 * k, RGBA(255, 226, 120))
            }
        default: break
        }
        if angel {
            // the halo above (a ring: the same from every side) and a gold circlet round the brow
            c.inkColor = nil
            let hcy = hy - ry * 1.32
            c.ellipse(cx, hcy, 10.5 * k, 2.9 * k, gold.lightened(0.15))
            c.paint(cx - 9 * k, hcy - 2.2 * k, cx + 9 * k, hcy + 2.2 * k, inside: { px, py in let u = (px - cx) / (8.3 * k), v = (py - hcy) / (1.7 * k); return u * u + v * v <= 1 }, color: { _, _ in RGBA(255, 250, 220, 90) })
            var phi = -Double.pi
            while phi < .pi {
                let p = onFace(phi, -0.8)
                if p.f > 0 { c.ellipse(p.x, p.y, 0.9 * k, 0.8 * k, abs(phi) < 0.15 ? RGBA(200, 226, 255) : gold) }
                phi += 0.16
            }
            _ = goldDeep
        }
        c.inkColor = nil
        return c.image()
    }

    /// The outline of part of a surface of revolution seen from `yaw`: at each height in `ys` the ring between
    /// angles phi0 and phi1 (round from the front) of the given radius, pushed back by `back(y)`. The left
    /// edge top to bottom, then the right edge bottom to top.
    static func sweep(ys: [Double], radius: (Double) -> Double, phi0: Double, phi1: Double, yaw: Double, cx: Double, k: Double,
                      Y: (Double) -> Double, back: (Double) -> Double = { _ in 0 }) -> [(Double, Double)] {
        var left: [(Double, Double)] = [], right: [(Double, Double)] = []
        let C = cos(yaw), S = sin(yaw)
        for y in ys {
            let r = radius(y), z0 = -back(y)
            var lo = Double.infinity, hi = -Double.infinity
            for i in 0...16 {
                let phi = phi0 + (phi1 - phi0) * Double(i) / 16
                let x = r * sin(phi), z = r * cos(phi) + z0
                let sx = x * C + z * S
                lo = min(lo, sx); hi = max(hi, sx)
            }
            left.append((cx + lo * k, Y(y))); right.append((cx + hi * k, Y(y)))
        }
        return left + right.reversed()
    }

    /// The moe eye, narrowed as it turns away (`squash` 1: straight on), its lashes sweeping outward.
    static func turnMoeEye(_ c: inout Canvas, _ x: Double, _ y: Double, _ k: Double, _ iris: RGBA, _ lash: RGBA, squash: Double, outward: Double) {
        let w = 4.6 * k * max(0.3, squash), h = 6.2 * k
        c.inkColor = nil
        c.ellipse(x, y, w, h, RGBA(250, 252, 255))
        c.paint(x - w, y - h, x + w, y + h, inside: { px, py in let u = (px - x) / (w * 0.84), v = (py - y - 0.4 * k) / (h * 0.9); return u * u + v * v <= 1 },
                color: { px, py in
                    let t = (py - (y - h)) / (2 * h)
                    var col = t < 0.5 ? mix(shadowed(iris, 0.55), iris, t * 2) : mix(iris, iris.lightened(0.45), (t - 0.5) * 2)
                    let u = (px - x) / (w * 0.84), v = (py - y - 0.4 * k) / (h * 0.9), r = (u * u + v * v).squareRoot()
                    if r > 0.78 && t > 0.45 { col = mix(col, iris.lightened(0.6), 0.5) }
                    if r > 0.9 { col = shadowed(iris, 0.65) }
                    return col
                })
        c.ellipse(x, y + 0.8 * k, w * 0.32, h * 0.42, shadowed(iris, 0.75))
        c.ellipse(x - w * 0.36, y - h * 0.32, max(0.5, w * 0.34), max(0.5, w * 0.3), .white)
        c.ellipse(x + w * 0.34, y + h * 0.3, max(0.4, w * 0.17), max(0.4, w * 0.17), RGBA(255, 255, 255, 230))
        let o = outward
        // the upper lash line: thin at the inner corner, full over the eye, thickest at the outer corner with
        // a flick (it never reaches across to the other eye)
        let dark = lash.darkened(0.25)
        c.curve([(x - o * w * 0.75, y - h * 0.62), (x - o * w * 0.35, y - h - 0.2), (x + o * w * 0.2, y - h - 0.5)], 0.8 * k, dark)
        c.curve([(x - o * w * 0.1, y - h - 0.5), (x + o * w * 0.55, y - h - 0.4), (x + o * (w + 0.5), y - h * 0.4)], 1.6 * k, dark)
        c.line(x + o * (w + 0.3), y - h * 0.42, x + o * (w + 2.0 * k), y - h * 0.66, 0.9 * k, dark)
        c.curve([(x - w * 0.45, y - h - 2.0 * k), (x, y - h - 2.4 * k), (x + w * 0.45, y - h - 2.0 * k)], 0.45, lash.withAlpha(150))
        c.curve([(x - w * 0.4, y + h + 0.3), (x + o * w * 0.1, y + h + 0.7), (x + o * w * 0.5, y + h + 0.2)], 0.5, lash.lightened(0.25).withAlpha(170))
        c.paint(x - w, y - h, x + w, y - h * 0.45, inside: { px, py in let u = (px - x) / w, v = (py - y) / h; return u * u + v * v <= 1 },
                color: { _, _ in RGBA(120, 110, 170, 60) })
    }

    /// The hero's eye, narrowed as it turns away.
    static func turnHeroEye(_ c: inout Canvas, _ x: Double, _ y: Double, _ k: Double, _ iris: RGBA, squash: Double) {
        let w = 2.6 * k * max(0.3, squash), h = 3.2 * k
        c.inkColor = nil
        c.ellipse(x, y, w, h, RGBA(250, 250, 255))
        c.ellipse(x, y + 0.4, w * 0.75, h * 0.8, iris)
        c.ellipse(x, y + 0.6, w * 0.35, h * 0.4, shadowed(iris, 0.7))
        c.ellipse(x - w * 0.3, y - h * 0.3, max(0.4, w * 0.25), max(0.4, w * 0.25), .white)
        c.line(x - w - 0.4, y - h + 0.2, x + w + 0.4, y - h - 0.2, 1.1 * k, AnimeArt.ink)
    }
}
