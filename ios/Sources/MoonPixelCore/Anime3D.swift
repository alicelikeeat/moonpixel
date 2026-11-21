import Foundation

// The anime look in 3D: people as real models, not pictures on cards.
//
// The figure is built like the 2D anime drawings (AnimeTurn.swift) but in the round: a large head, a pointed
// chin, big eyes painted onto the curve of the face (white, a deep iris lighter below, a pupil, two catchlights,
// a lash line with a flick), hair as a cap with pointed locks over the brow, side locks along the cheeks, an
// ahoge, and by the person's style long hair, twin tails or a bun; slim limbs, puffed sleeves, a bow at the
// collar, a frilled skirt and knee socks for a girl. The angel costume adds wings and a halo; the hero figure
// has longer legs and a smaller head. Every part is cel shaded (two flat tones) and, in the app, outlined in
// ink by the inverted hull; the painted face is left without outlines.

extension Figure3D {
    /// Proportions in sixteenths of a tile (feet at 0, the top of the head about 24: as tall as the plain figure).
    struct AnimeBody {
        var headY: Float, headR: SIMD3<Float>
        var neckY: Float, shoulderY: Float, shoulderX: Float, chestY: Float, chestR: SIMD3<Float>
        var waistY: Float, hipY: Float, legX: Float, kneeY: Float
        var eyeX: Float, eyeY: Float, eyeW: Float, eyeH: Float

        static let moe = AnimeBody(headY: 19.5, headR: [4.9, 4.7, 4.5], neckY: 14.6, shoulderY: 13.6, shoulderX: 3.5, chestY: 12.2, chestR: [3.2, 2.4, 2.2],
                                   waistY: 10.2, hipY: 8.4, legX: 1.45, kneeY: 4.4, eyeX: 1.85, eyeY: -0.75, eyeW: 1.25, eyeH: 1.6)
        static let hero = AnimeBody(headY: 21.2, headR: [3.6, 3.9, 3.6], neckY: 17.0, shoulderY: 16.2, shoulderX: 4.3, chestY: 14.4, chestR: [3.8, 2.9, 2.5],
                                    waistY: 11.6, hipY: 10.2, legX: 1.7, kneeY: 5.2, eyeX: 1.35, eyeY: -0.35, eyeW: 0.85, eyeH: 0.85)
    }

    /// A person in the anime look, modelled. frame: 0 standing, 1 and 2 the steps of a walk, 3 working or
    /// striking. A character model (a knight, a merfolk...) keeps its own figure, cel shaded.
    public static func anime(_ look: Look, frame: Int, held: String, child: Bool, female: Bool, kind: AnimeArt.Figure = AnimeArt.figure) -> Mesh3D {
        if let cm = CharacterModels.of(look.model) {
            var m = cm.round ? roundling(cm, frame: frame, child: child) : human(look, frame: frame, held: held, child: child, female: female)
            m.cel = true
            return m
        }
        var m = Mesh3D(detail: Figure3D.detail)
        m.cel = true
        let angel = kind == .angel && !child
        let b = kind == .hero && !child ? AnimeBody.hero : AnimeBody.moe
        let k: Float = (child ? 0.7 : 1) * personScale
        let u = k / 16
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * u }
        func R(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * u }
        let skin = AnimeArt.pastel(RGBA(hex: look.skin)).lightened(0.04)
        let hair = AnimeArt.pastel(RGBA(hex: look.hair)).lightened(0.06)
        let cloth = angel ? RGBA(250, 246, 236) : AnimeArt.pastel(RGBA(hex: look.shirt))
        let lower = angel ? RGBA(244, 238, 226) : AnimeArt.pastel(RGBA(hex: look.pants))
        let shoes = angel ? RGBA(236, 196, 90) : AnimeArt.pastel(RGBA(hex: look.shoes))
        let gold = RGBA(240, 200, 90)
        // the accent: a ribbon colour that sets off the clothes (red on cool clothes, blue on warm ones)
        let accent = angel ? gold : (Int(cloth.b) > Int(cloth.r) ? RGBA(230, 70, 90) : RGBA(70, 110, 220))
        let sw: Float = frame == 1 ? 1.8 : (frame == 2 ? -1.8 : 0)
        let acting = frame == 3

        // legs: slim, a knee bent in a step; knee socks for a girl in the moe look, shoes rounded at the toe
        for (x, swing) in [(-b.legX, sw), (b.legX, -sw)] {
            let hip = P(x, b.hipY, 0), knee = P(x * 1.05, b.kneeY, swing * 0.55 + 0.3), ankle = P(x * 1.05, 1.3, swing)
            let sock = female && kind != .hero ? RGBA(250, 250, 252) : lower
            m.frustum(hip, knee, 1.35 * u, 1.05 * u, female && kind != .hero ? skin : lower, seg: 8)
            m.frustum(knee, ankle, 1.05 * u, 0.8 * u, sock, seg: 8)
            if female && kind != .hero { m.frustum(knee + P(0, 0.9, 0), knee - P(0, 0.2, 0), 1.12 * u, 1.1 * u, sock, seg: 8) }   // the sock's top
            m.ellipsoid(P(x * 1.05, 0.85, swing + 0.55), R(1.2, 0.85, 2.0), shoes, seg: 8, rings: 4)
        }
        // the body: hips, a slim waist, the chest; a skirt with a frilled hem for a girl, a jacket hem for a boy
        m.ellipsoid(P(0, b.hipY + 0.4, 0), R(b.chestR.x * 0.95, 1.6, b.chestR.z * 0.95), lower, seg: 12, rings: 5)
        m.frustum(P(0, b.hipY + 0.6, 0), P(0, b.chestY - 0.6, 0), b.chestR.x * 0.78 * u, b.chestR.x * 0.95 * u, cloth, seg: 12, caps: false)
        m.ellipsoid(P(0, b.chestY, 0), b.chestR * u, cloth, seg: 12, rings: 6)
        if female || angel {
            let hemY = max(2.6, b.hipY - (kind == .hero ? 3.4 : 2.8) - (angel ? 2.6 : 0))
            let top = b.waistY + 0.3, rTop = b.chestR.x * 0.82, rHem = b.chestR.x * (angel ? 1.45 : 1.6)
            m.frustum(P(0, top, 0), P(0, hemY, 0), rTop * u, rHem * u, angel ? cloth : lower, seg: 16)
            // the frill: a ring of soft scallops round the hem
            let frill = angel ? gold : RGBA(252, 250, 246)
            for i in 0..<14 {
                let a = Float(i) / 14 * 2 * .pi
                m.ellipsoid(P(sin(a) * rHem, hemY + 0.15, cos(a) * rHem), R(0.95, 0.55, 0.95), frill, seg: 6, rings: 3)
            }
        } else {
            // a short jacket hem over the hips
            m.frustum(P(0, b.waistY + 0.2, 0), P(0, b.hipY - 0.6, 0), b.chestR.x * 0.85 * u, b.chestR.x * 1.08 * u, cloth.darkened(0.06), seg: 12)
        }
        // the collar and its bow (a gold clasp for an angel)
        m.frustum(P(0, b.neckY - 0.2, 0), P(0, b.neckY + 1.2, 0), 1.0 * u, 0.95 * u, skin, seg: 8)
        m.ellipsoid(P(0, b.shoulderY + 0.4, 0.2), R(b.chestR.x * 0.95, 0.7, b.chestR.z * 0.95), angel ? gold : RGBA(252, 250, 246), seg: 12, rings: 3)
        let bowAt = P(0, b.shoulderY - 0.2, b.chestR.z + 0.2)
        for s: Float in [-1, 1] { m.ellipsoid(bowAt + P(s * 1.0, 0.1, 0), R(1.0, 0.65, 0.4), accent, seg: 8, rings: 4) }
        m.ellipsoid(bowAt, R(0.45, 0.5, 0.45), accent.darkened(0.12), seg: 6, rings: 3)
        if !female && !angel { m.frustum(bowAt, bowAt + P(0, -3.0, 0.15), 0.45 * u, 0.6 * u, accent, seg: 6) }   // a tie
        // arms: a puffed sleeve, a slim arm, a small hand (the right one raised to work or strike)
        for side: Float in [-1, 1] {
            let raised = acting && side > 0
            let swing: Float = side < 0 ? -sw : sw
            let shoulder = P(side * b.shoulderX, b.shoulderY, 0)
            let elbow = raised ? P(side * (b.shoulderX + 1.0), b.shoulderY + 3.0, 0.5) : P(side * (b.shoulderX + 0.5), b.shoulderY - 3.2, swing * 0.45)
            let hand = raised ? P(side * (b.shoulderX + 0.8), b.shoulderY + 6.2, 0.5) : P(side * (b.shoulderX + 0.7), b.shoulderY - 6.2, swing)
            m.ellipsoid(shoulder, R(1.55, 1.45, 1.55), cloth.lightened(0.04), seg: 8, rings: 4)
            m.frustum(shoulder, elbow, 0.85 * u, 0.72 * u, kind == .hero ? cloth : skin, seg: 8)
            m.frustum(elbow, hand, 0.72 * u, 0.6 * u, kind == .hero ? cloth.darkened(0.05) : skin, seg: 8)
            m.ellipsoid(hand, R(0.75, 0.85, 0.75), skin, seg: 8, rings: 4)
        }
        // the angel's wings (feathers fanned out behind the shoulders) and her halo
        if angel {
            for side: Float in [-1, 1] {
                for f in 0..<5 {
                    let t = Float(f) / 4
                    let root = P(side * 1.2, b.shoulderY - 0.5, -b.chestR.z - 0.4)
                    let tip = root + P(side * (3.5 + 3.0 * t), 4.5 - 5.5 * t, -1.6 - 0.6 * t)
                    m.ellipsoid((root + tip) * 0.5, R(abs(tip.x - root.x) / u * 0.55 + 0.9, 1.0, 0.45), RGBA(252, 252, 255).darkened(Double(t) * 0.06), seg: 8, rings: 4)
                }
            }
            for i in 0..<16 {
                let a = Float(i) / 16 * 2 * .pi
                m.ellipsoid(P(sin(a) * 3.2, b.headY + b.headR.y + 3.6, cos(a) * 3.2 - 0.6), R(0.55, 0.32, 0.55), gold, seg: 6, rings: 3)
            }
        }

        // the head: a round skull, a pointed chin, small ears hidden in the hair
        let hy = b.headY, hr = b.headR
        let hc = P(0, hy, 0)
        // (the face in its own clear colour, as an anime face is painted: the outline gives it its shape)
        m.unshaded = true
        m.ellipsoid(hc, hr * u, skin.lightened(0.05), seg: 18, rings: 12)
        m.ellipsoid(P(0, hy - hr.y * 0.62, hr.z * 0.28), R(hr.x * 0.5, hr.y * 0.45, hr.z * 0.5), skin.lightened(0.05), seg: 10, rings: 5)
        m.unshaded = false
        // the hair: a cap over the crown and the back of the head
        m.ellipsoid(P(0, hy + 0.25, -0.3), R(hr.x + 0.45, hr.y + 0.4, hr.z + 0.45), hair, seg: 18, rings: 10, from: 0.5, to: 1)
        m.ellipsoid(P(0, hy - 0.4, -0.95), R(hr.x + 0.35, hr.y + 0.2, hr.z + 0.1), hair, seg: 16, rings: 9)
        /// A point on the face's surface (x, y relative to the head's middle), lifted `lift` above it.
        func onHead(_ x: Float, _ y: Float, lift: Float = 0) -> SIMD3<Float> {
            let q = 1 - (x / hr.x) * (x / hr.x) - (y / hr.y) * (y / hr.y)
            return P(x, hy + y, hr.z * max(0, q).squareRoot() + lift)
        }
        // the fringe: pointed locks from the crown down over the brow, never over the eyes
        let fringe = 7
        for i in 0..<fringe {
            let t = Float(i) / Float(fringe - 1) * 2 - 1           // -1 ... 1 across the brow
            let x = t * hr.x * 0.78
            let root = onHead(x * 0.8, hr.y * 0.78, lift: 0.5)
            let tipY = b.eyeY + b.eyeH + 0.5 + abs(t) * 0.2 - (i % 2 == 0 ? 0.6 : 0)
            let tip = onHead(x * 1.05 + t * 0.4, tipY, lift: 0.35)
            m.frustum(root, tip, 1.5 * u, 0.12 * u, hair, seg: 6)
        }
        // the side locks, down along the cheeks
        for s: Float in [-1, 1] {
            let top = P(s * hr.x * 0.95, hy + hr.y * 0.2, hr.z * 0.35)
            let tip = P(s * hr.x * 0.9, hy - hr.y * (female ? 1.05 : 0.7), hr.z * 0.42)
            m.frustum(top, tip, 1.3 * u, 0.2 * u, hair, seg: 6)
        }
        // the ahoge: one lock standing up and curling over
        let ah0 = P(0, hy + hr.y + 0.2, 0.4), ah1 = ah0 + P(0.6, 2.0, 0.4), ah2 = ah1 + P(1.1, 0.4, 0.5)
        m.frustum(ah0, ah1, 0.45 * u, 0.32 * u, hair, seg: 5)
        m.frustum(ah1, ah2, 0.32 * u, 0.08 * u, hair, seg: 5)
        // by style: long hair down the back, twin tails with ribbons, or a bun
        let longHair = female || look.style % 3 == 1
        if longHair {
            m.ellipsoid(P(0, hy - hr.y * 0.95, -hr.z * 0.62), R(hr.x * 0.92, hr.y * 1.3, 1.7), hair, seg: 14, rings: 8)
            for i in 0..<5 {
                let x = (Float(i) - 2) * hr.x * 0.34
                m.frustum(P(x, hy - hr.y * 1.6, -hr.z * 0.62), P(x * 1.1, hy - hr.y * 2.25, -hr.z * 0.55), 1.0 * u, 0.1 * u, hair, seg: 5)
            }
        }
        if female && look.style % 4 == 3 {
            for s: Float in [-1, 1] {
                let root = P(s * hr.x * 0.9, hy + hr.y * 0.45, -hr.z * 0.3)
                let mid = root + P(s * 2.0, -3.5, -0.6), end = mid + P(s * 0.4, -5.5, 0)
                m.frustum(root, mid, 1.25 * u, 1.45 * u, hair, seg: 8)
                m.frustum(mid, end, 1.45 * u, 0.15 * u, hair, seg: 8)
                for d: Float in [-1, 1] { m.ellipsoid(root + P(0, 0.6, d * 0.9), R(0.6, 0.75, 0.9), accent, seg: 6, rings: 3) }
            }
        } else if look.style % 3 == 2 {
            m.ellipsoid(P(0, hy + hr.y * 0.75, -hr.z * 0.65), R(1.9, 1.7, 1.9), hair, seg: 10, rings: 5)
        }
        // what the right hand holds
        holdItem(&m, held: held, acting: acting, sw: sw, k: k, handY: b.shoulderY - 13.6)

        // the face, painted on: no outlines from here on
        m.inkEnd = m.positions.count
        m.unshaded = true
        let iris = angel ? RGBA(236, 184, 60) : AnimeArt.irisColor(hair)
        let lash = RGBA(52, 36, 50)
        /// A painted oval on the face (x, y its middle relative to the head's middle, w, h its half-size).
        func paint(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ c: RGBA, lift: Float, from a0: Float = 0, to a1: Float = 2 * .pi) {
            let rings = 3, seg = 14
            for r in 0..<rings { for i in 0..<seg {
                let ra = Float(r) / Float(rings), rb = Float(r + 1) / Float(rings)
                let ta = a0 + (a1 - a0) * Float(i) / Float(seg), tb = a0 + (a1 - a0) * Float(i + 1) / Float(seg)
                func at(_ rr: Float, _ t: Float) -> SIMD3<Float> { onHead(x + cos(t) * w * rr, y + sin(t) * h * rr, lift: lift) }
                m.face(at(ra, ta), at(rb, ta), at(rb, tb), at(ra, tb), c)
            } }
        }
        for s: Float in [-1, 1] {
            let ex = s * b.eyeX, ey = b.eyeY
            paint(ex, ey, b.eyeW, b.eyeH, RGBA(255, 255, 255), lift: 0.08)
            paint(ex, ey - b.eyeH * 0.06, b.eyeW * 0.84, b.eyeH * 0.86, iris.darkened(0.28), lift: 0.16)
            paint(ex, ey - b.eyeH * 0.32, b.eyeW * 0.66, b.eyeH * 0.5, iris.lightened(0.2), lift: 0.22)
            paint(ex, ey - b.eyeH * 0.02, b.eyeW * 0.38, b.eyeH * 0.48, iris.darkened(0.55), lift: 0.28)
            paint(ex + s * b.eyeW * 0.3, ey + b.eyeH * 0.32, b.eyeW * 0.26, b.eyeH * 0.22, RGBA(255, 255, 255), lift: 0.36)
            paint(ex - s * b.eyeW * 0.3, ey - b.eyeH * 0.45, b.eyeW * 0.12, b.eyeH * 0.1, RGBA(255, 255, 255), lift: 0.36)
            // the lash line over the top of the eye, thickest at the outer corner, with a flick
            paint(ex, ey + b.eyeH * 0.1, b.eyeW * 1.08, b.eyeH * 1.02, lash, lift: 0.3, from: 0.12 * .pi, to: 0.88 * .pi)
            paint(ex + s * b.eyeW * 1.0, ey + b.eyeH * 0.55, b.eyeW * 0.3, b.eyeH * 0.16, lash, lift: 0.32)
            // a brow, thin, under the fringe
            paint(ex + s * 0.1, ey + b.eyeH + 1.0, b.eyeW * 0.8, 0.14, hair.darkened(0.35), lift: 0.12)
            // a blush
            paint(s * (b.eyeX + 0.5), ey - b.eyeH - 0.5, b.eyeW * 0.75, 0.32, RGBA(246, 150, 160), lift: 0.06)
        }
        // a small mouth, a hint of a nose
        paint(0, -hr.y * 0.45, 0.55, 0.18, RGBA(200, 90, 100), lift: 0.08, from: .pi, to: 2 * .pi)
        paint(0, b.eyeY - b.eyeH * 0.9, 0.14, 0.14, skin.darkened(0.18), lift: 0.05)
        m.unshaded = false
        return m
    }
}
