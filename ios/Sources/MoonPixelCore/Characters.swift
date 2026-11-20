import Foundation

// Character models: ten figures of our own, on top of the everyday villager.
//
// The look follows two broad traditions rather than any one game: the toon adventure style (clear shapes,
// a cap or a helm that reads from far off, a belt, gear you can tell at a glance) and the soft round "little
// creature" style (a body that is almost one round shape, a tiny face low on it, stubby arms, blush). Every
// design here is original.
//
// Five are of the land (villagers may be born with them; the traveller may wear them). Five are of the sea
// floor only: the people of the sea-floor nations, who walk their underlands.

public struct CharacterModel: Equatable {
    public let key: String, en: String, zh: String
    /// Only the sea-floor nations' people wear it.
    public let sea: Bool
    /// A round little creature (its own body, not a person's).
    public let round: Bool
    /// What it is, in a few words.
    public let blurbEn: String, blurbZh: String
}

public enum CharacterModels {
    public static let all: [CharacterModel] = [
        CharacterModel(key: "wayfarer", en: "Wayfarer", zh: "旅者", sea: false, round: false, blurbEn: "a long pointed cap, a belted tunic", blurbZh: "长尖帽、束腰短衣"),
        CharacterModel(key: "sage", en: "Lantern sage", zh: "提灯贤者", sea: false, round: false, blurbEn: "a wide-brimmed tall hat, a beard", blurbZh: "宽檐高帽、长胡子"),
        CharacterModel(key: "knight", en: "Lake knight", zh: "湖骑士", sea: false, round: false, blurbEn: "a plumed helm, a breastplate", blurbZh: "羽饰头盔、胸甲"),
        CharacterModel(key: "tinker", en: "Tinker", zh: "机巧匠", sea: false, round: false, blurbEn: "goggles, a leather apron", blurbZh: "护目镜、皮围裙"),
        CharacterModel(key: "puffling", en: "Puffling", zh: "团子", sea: false, round: true, blurbEn: "a round little creature with a sprout on top", blurbZh: "头顶小芽的圆滚滚小生物"),
        CharacterModel(key: "merfolk", en: "Merfolk", zh: "人鱼", sea: true, round: false, blurbEn: "a fish's tail, fin ears", blurbZh: "鱼尾、鳍耳"),
        CharacterModel(key: "diver", en: "Pearl diver", zh: "珍珠潜者", sea: true, round: false, blurbEn: "a bubble helmet, flippers", blurbZh: "泡泡头盔、脚蹼"),
        CharacterModel(key: "coral_priest", en: "Coral priest", zh: "珊瑚祭司", sea: true, round: false, blurbEn: "a crown of coral, a long robe", blurbZh: "珊瑚冠、长袍"),
        CharacterModel(key: "kelpling", en: "Kelpling", zh: "海带团子", sea: true, round: true, blurbEn: "a round little creature with kelp hair", blurbZh: "长着海带头发的圆滚滚小生物"),
        CharacterModel(key: "shell_guard", en: "Shell guard", zh: "贝甲卫", sea: true, round: false, blurbEn: "scallop-shell armour, a trident", blurbZh: "扇贝壳甲、三叉戟"),
    ]
    public static let land = all.filter { !$0.sea }
    public static let seaOnly = all.filter { $0.sea }
    public static func of(_ key: String?) -> CharacterModel? { key.flatMap { k in all.first { $0.key == k } } }

    /// A villager of the land: about one in three is born with one of the land models.
    public static func landPick(_ h: UInt32) -> String? { h % 100 < 34 ? land[Int((h >> 8) % UInt32(land.count))].key : nil }
    /// One of the sea floor's people.
    public static func seaPick(_ h: UInt32) -> String { seaOnly[Int(h % UInt32(seaOnly.count))].key }

    /// The colours the sea floor's people wear (skin tinted by the water, hair like kelp and coral).
    static let seaSkins = ["#bfe4e0", "#d6ecf2", "#e8d6c8", "#a8d8d0", "#f2d4c4"]
    static let seaHairs = ["#2f8f7a", "#3a6ac8", "#e07a8a", "#6ad0c8", "#f0e0b0", "#7a4ab8"]
    static let seaCloth = ["#3ab0b8", "#f0a0a8", "#f4e6c0", "#5a8ae8", "#2a7a90", "#e8c050"]
    static let landSkins = ["#f2c8a4", "#e0b088", "#c48a64", "#f6d8c0", "#a87050"]
    static let landHairs = ["#5a3a22", "#2a2a30", "#c89048", "#e8d8a0", "#a04a30", "#e0e0e8"]
    static let landCloth = ["#5a8ae8", "#4a9a5a", "#c84a4a", "#d8a040", "#8a5ac8", "#e8e0d0"]

    /// A person of an underland: of the sea floor or of the underground, made from a number.
    public static func resident(_ h: UInt32, sea: Bool) -> (look: Look, female: Bool, child: Bool) {
        var l = Look()
        let pick = { (list: [String], salt: UInt32) -> String in list[Int((h &* 2_654_435_761 &+ salt) >> 7 % 977) % list.count] }
        l.skin = pick(sea ? seaSkins : landSkins, 1)
        l.hair = pick(sea ? seaHairs : landHairs, 2)
        l.shirt = pick(sea ? seaCloth : landCloth, 3)
        l.pants = pick(sea ? seaCloth : landCloth, 4)
        l.style = Int(h % 4)
        l.model = sea ? seaPick(h >> 3) : (h % 100 < 60 ? land[Int((h >> 5) % UInt32(land.count))].key : nil)
        return (l, (h >> 11) % 2 == 0, (h >> 13) % 5 == 0)
    }
}

// MARK: - 2D (the anime figure and the pixel figure)

extension AnimeArt {
    /// What a character model adds over the figure (or, for the round ones, the whole figure).
    static func modelFigure(_ m: CharacterModel, base: () -> Bitmap, look: Look, dir: String, frame: Int, held: String, child: Bool, female: Bool) -> Bitmap {
        var c = Canvas(charW, charH, scale: figureScale)
        let k: Double = child ? 0.84 : 1
        let walk = frame == 1 ? 1.0 : (frame == 2 ? -1.0 : 0)
        let bob = frame == 1 || frame == 2 ? -1.2 : 0
        func X(_ v: Double) -> Double { 32 + v * k }
        func Y(_ v: Double) -> Double { 76 - (76 - v) * k + (v < 62 ? bob : 0) }
        let side = dir == "side", back = dir == "up"
        let cloth = pastel(RGBA(hex: look.shirt)), hair = pastel(RGBA(hex: look.hair)), skin = pastel(RGBA(hex: look.skin))
        if m.round {
            // a round little creature: one soft body, a tiny face low on it, stubby arms and feet
            let body = m.key == "kelpling" ? RGBA(150, 214, 190) : RGBA(250, 246, 238)
            c.ellipse(X(0), 75, 13 * k, 2.6 * k, RGBA(0, 0, 0, 55))
            for s in [-1.0, 1.0] { c.ellipse(X(s * 6 + (s < 0 ? walk : -walk) * 1.5), Y(73), 4.2 * k, 2.6 * k, body.darkened(0.08), ink: 0.9) }
            c.ellipse(X(0), Y(52), 17 * k, 19 * k, body, ink: 1.1, shade: Shade(shadow: 0.05, light: 0.08, cut: 0.55))
            let armUp = frame == 3
            for s in [-1.0, 1.0] where !(side && s < 0) {
                c.ellipse(X(s * 15.5), Y(armUp && s > 0 ? 44 : 55 - walk * s), 3.6 * k, 4.6 * k, body.darkened(0.04), ink: 0.9)
            }
            if !back {
                let fx = side ? 6.0 : 0
                for s in [-1.0, 1.0] where !(side && s < 0) {
                    c.ellipse(X(fx + s * 5), Y(52), 2.0 * k, 2.4 * k, ink, ink: 0)
                    c.ellipse(X(fx + s * 5 - 0.6), Y(51.2), 0.7 * k, 0.7 * k, .white)
                    c.ellipse(X(fx + s * 8.5), Y(56), 2.6 * k, 1.3 * k, RGBA(250, 150, 160, 170))
                }
                c.curve([(X(fx - 1.5), Y(57)), (X(fx), Y(58.2)), (X(fx + 1.5), Y(57))], 0.9 * k, ink)
            }
            if m.key == "puffling" {
                // a sprout on top: a stem and two leaves
                c.line(X(0), Y(34), X(0.5), Y(27), 1.2 * k, RGBA(90, 160, 70))
                c.ellipse(X(-3.5), Y(26), 4 * k, 2 * k, RGBA(120, 200, 90), ink: 0.8)
                c.ellipse(X(3.8), Y(25), 4 * k, 2 * k, RGBA(140, 214, 100), ink: 0.8)
            } else {
                // kelp hair: wavy fronds falling round the top
                for (i, s) in [-11.0, -5.5, 0, 5.5, 11].enumerated() {
                    let sway = (frame % 2 == 0 ? 1.0 : -1.0) * (i % 2 == 0 ? 1.2 : -1.2)
                    c.curve([(X(s * 0.6), Y(34)), (X(s + sway), Y(30)), (X(s * 1.3 - sway), Y(38)), (X(s * 1.4), Y(46))], 2.2 * k, RGBA(40, 140, 100))
                }
                c.ellipse(X(-6), Y(36), 1.8 * k, 1.8 * k, RGBA(250, 210, 120), ink: 0.6)        // a little shell clip
            }
            if !held.isEmpty { heldItem(&c, held, X(15), Y(54), k) }
            return c.image()
        }
        var img = base()
        let ink0 = 0.9
        switch m.key {
        case "wayfarer":
            // a long pointed cap drooping behind, and a belt with a buckle
            let capC = cloth.darkened(0.08)
            let tip: (Double, Double) = back ? (X(0), Y(42)) : (side ? (X(-17), Y(26)) : (X(15), Y(30)))
            c.poly([(X(-14), Y(17)), (X(14), Y(17)), (X(9), Y(6)), (X(-3), Y(3)), tip], capC, ink: ink0)
            c.rect(X(-14), Y(15.5), 28 * k, 3 * k, capC.darkened(0.15), ink: 0.6, radius: 1.2)
            c.rect(X(-9), Y(47), 18 * k, 2.6 * k, RGBA(110, 74, 46), ink: 0.6, radius: 1)
            if !back { c.rect(X(-1.6), Y(46.6), 3.2 * k, 3.4 * k, RGBA(230, 196, 90), ink: 0.5, radius: 0.6) }
        case "sage":
            // a wide-brimmed tall hat, a long white beard
            let hat = RGBA(70, 80, 150)
            c.poly([(X(-9), Y(14)), (X(9), Y(14)), (X(4), Y(-1)), (X(-1), Y(-3))], hat, ink: ink0)
            c.ellipse(X(0), Y(15), 19 * k, 3.6 * k, hat.darkened(0.1), ink: ink0)
            c.rect(X(-9), Y(11), 18 * k, 2.4 * k, RGBA(220, 190, 90), radius: 1)
            if !back && !female && !child { c.poly([(X(-5), Y(37)), (X(5), Y(37)), (X(2.5), Y(46)), (X(0), Y(48)), (X(-2.5), Y(46))], RGBA(244, 242, 236), ink: 0.7) }
        case "knight":
            // a rounded helm over the top of the head with a plume, and a breastplate
            let steel = RGBA(206, 214, 228), cx = X(side ? -1 : 0), cy = Y(23), rx = 16 * k, ry = 14 * k
            c.paint(cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + 1, inside: { x, y in
                let a = (x - cx) / rx, b = (y - cy) / ry; return a * a + b * b <= 1 && y <= cy - (back ? -6 : 2) * k
            }, color: { _, y in steel.lightened(y < cy - ry * 0.6 ? 0.12 : 0) })
            c.rect(cx - rx, cy - 3 * k, 2 * rx, 2.2 * k, steel.darkened(0.2), radius: 1)
            c.ellipse(X(side ? -4 : 0), Y(6), 3 * k, 6 * k, RGBA(220, 70, 80), ink: 0.7)
            c.rect(X(-9), Y(36), 18 * k, 12 * k, steel.withAlpha(235), ink: 0.7, radius: 4)
            c.line(X(0), Y(37), X(0), Y(47), 0.8 * k, steel.darkened(0.25))
        case "tinker":
            // goggles on the brow, a strap round the head, a leather apron
            let strap = RGBA(90, 64, 44)
            c.rect(X(-15), Y(16.5), 30 * k, 2.4 * k, strap, radius: 1)
            if !back { for s in [-1.0, 1.0] where !(side && s < 0) {
                c.ellipse(X(s * 5.5 + (side ? 3 : 0)), Y(17.5), 4 * k, 3.6 * k, RGBA(110, 90, 70), ink: 0.7)
                c.ellipse(X(s * 5.5 + (side ? 3 : 0)), Y(17.5), 2.8 * k, 2.5 * k, RGBA(250, 190, 90))
                c.ellipse(X(s * 5.5 + (side ? 3 : 0) - 1), Y(16.6), 0.9 * k, 0.8 * k, .white)
            } }
            if !back { c.rect(X(-8), Y(40), 16 * k, 20 * k, RGBA(150, 104, 66, 240), ink: 0.7, radius: 2) }
        case "merfolk":
            // the legs are a fish's tail, with a fin at the end; fins for ears
            let tail = RGBA(70, 180, 190), fin = RGBA(150, 230, 220)
            let sway = walk * 3
            c.poly([(X(-9), Y(50)), (X(9), Y(50)), (X(6 + sway * 0.5), Y(64)), (X(2 + sway), Y(71)), (X(-2 + sway), Y(71)), (X(-6 + sway * 0.5), Y(64))], tail, ink: ink0)
            for i in 0..<4 { c.curve([(X(-6), Y(54 + Double(i) * 4)), (X(0), Y(56 + Double(i) * 4)), (X(6), Y(54 + Double(i) * 4))], 0.6 * k, tail.darkened(0.2)) }
            c.poly([(X(sway), Y(70)), (X(-10 + sway), Y(77)), (X(-2 + sway), Y(74.5)), (X(sway), Y(77.5)), (X(2 + sway), Y(74.5)), (X(10 + sway), Y(77))], fin, ink: 0.7)
            for s in [-1.0, 1.0] where !(side && s > 0) { c.poly([(X(s * 13), Y(24)), (X(s * 19), Y(19)), (X(s * 15), Y(29))], fin, ink: 0.6) }
            if !back { for i in -3...3 { c.ellipse(X(Double(i) * 2.2), Y(42 + abs(Double(i)) * 0.5), 1.1 * k, 1.1 * k, RGBA(252, 248, 240), ink: 0.4) } }   // a string of pearls
        case "diver":
            // a bubble helmet round the head with a brass collar; flippers on the feet
            let bx = X(0), by = Y(24), br = 19 * k
            c.paint(bx - br, by - br, bx + br, by + br, inside: { x, y in let d = ((x - bx) * (x - bx) + (y - by) * (y - by)).squareRoot(); return d <= br }, color: { x, y in
                let d = ((x - bx) * (x - bx) + (y - by) * (y - by)).squareRoot() / br
                return d > 0.9 ? RGBA(170, 225, 250, 200) : RGBA(200, 240, 255, 28)
            })
            c.curve([(X(-14), Y(16)), (X(-9), Y(9)), (X(-2), Y(6.5))], 1.8 * k, RGBA(255, 255, 255, 200))
            c.rect(X(-10), Y(38), 20 * k, 3.2 * k, RGBA(214, 168, 80), ink: 0.7, radius: 1.5)
            for s in [-1.0, 1.0] where !(side && s < 0) { c.ellipse(X(s * 4 + (s < 0 ? walk : -walk) * 2), Y(75.5), 4.6 * k, 2.0 * k, RGBA(250, 140, 60), ink: 0.7) }
        case "coral_priest":
            // a crown of branching coral, and a long robe to the ground
            let coral = RGBA(250, 120, 120)
            c.poly([(X(-9), Y(42)), (X(9), Y(42)), (X(13), Y(76)), (X(-13), Y(76))], RGBA(150, 220, 210, 235), ink: ink0)
            c.line(X(0), Y(44), X(0), Y(75), 0.8 * k, RGBA(90, 170, 160))
            for s in [-1.0, 1.0] {
                c.line(X(s * 4), Y(12), X(s * 7), Y(2), 1.6 * k, coral)
                c.line(X(s * 6), Y(6), X(s * 11), Y(3), 1.3 * k, coral)
                c.line(X(s * 1.5), Y(11), X(s * 2), Y(4), 1.3 * k, coral.lightened(0.1))
                c.ellipse(X(s * 7), Y(2), 1.3 * k, 1.3 * k, coral.lightened(0.2))
            }
        case "shell_guard":
            // scallop shells on the shoulders, a trident in the hand
            let shell = RGBA(250, 214, 170)
            for s in [-1.0, 1.0] where !(side && s < 0) {
                c.ellipse(X(s * 11), Y(43), 5.5 * k, 4 * k, shell, ink: 0.8)
                for r in [-2.0, 0, 2] { c.line(X(s * 11 + r), Y(40), X(s * 11 + r * 1.6), Y(46.5), 0.6 * k, shell.darkened(0.25)) }
            }
            if held.isEmpty {
                let gold = RGBA(230, 190, 80), tx = X(side ? 8 : 15)
                c.line(tx, Y(72), tx, Y(16), 1.4 * k, gold)
                c.line(tx - 4 * k, Y(16), tx + 4 * k, Y(16), 1.2 * k, gold)
                for d in [-4.0, 0, 4] { c.line(tx + d * k, Y(16), tx + d * k, Y(9), 1.1 * k, gold) }
            }
        default: break
        }
        _ = hair; _ = skin
        let over = c.image()
        // laid over the figure with its own transparency (a glass helmet shows the face through it)
        for y in 0..<min(img.h, over.h) { for x in 0..<min(img.w, over.w) {
            let o = over.get(x, y)
            guard o.a > 0 else { continue }
            let b = img.get(x, y)
            if o.a == 255 || b.a == 0 { img.set(x, y, o) } else { var m = b.lerp(o, Double(o.a) / 255); m.a = max(b.a, o.a); img.set(x, y, m) }
        } }
        return img
    }
}

extension RGBA {
    func withAlpha(_ a: UInt8) -> RGBA { RGBA(r, g, b, a) }
}

// MARK: - 3D

extension Figure3D {
    /// A round little creature, about knee-high to a person: one soft body, a tiny face, stubby arms and feet.
    static func roundling(_ m: CharacterModel, frame: Int, child: Bool) -> Mesh3D {
        var mesh = Mesh3D(detail: Figure3D.detail)
        let k: Float = (child ? 0.8 : 1) * personScale
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * (k / 16) }
        let u = k / 16
        let body = m.key == "kelpling" ? RGBA(150, 214, 190) : RGBA(250, 246, 238)
        let sw: Float = frame == 1 ? 1.5 : (frame == 2 ? -1.5 : 0)
        let ink = RGBA(hex: "#2a1e24")
        for (x, s) in [(Float(-3), sw), (3, -sw)] { mesh.ellipsoid(P(x, 0.9, s + 0.8), P(2.0, 0.9, 2.4), body.darkened(0.08), seg: 8, rings: 4) }
        mesh.ellipsoid(P(0, 7, 0), P(6.6, 6.4, 6.0), body, seg: 16, rings: 10)
        let up = frame == 3
        for s: Float in [-1, 1] { mesh.ellipsoid(P(s * 6.6, up && s > 0 ? 10 : 6.5, 0.5), P(1.5, 1.9, 1.5), body.darkened(0.04), seg: 8, rings: 4) }
        for s: Float in [-1, 1] {
            mesh.ellipsoid(P(s * 2.2, 7.4, 5.6), P(0.75, 0.95, 0.4), ink, seg: 8, rings: 4)
            mesh.ellipsoid(P(s * 2.0, 7.8, 5.95), P(0.25, 0.25, 0.1), RGBA(255, 255, 255), seg: 6, rings: 3)
            mesh.ellipsoid(P(s * 3.6, 5.8, 5.2), P(1.0, 0.5, 0.3), RGBA(250, 150, 160), seg: 6, rings: 3)
        }
        mesh.frustum(P(-0.6, 5.6, 5.9), P(0.6, 5.6, 5.9), 0.15 * u, 0.15 * u, RGBA(170, 80, 90), seg: 4)
        if m.key == "puffling" {
            mesh.frustum(P(0, 13, 0), P(0.3, 15.5, 0), 0.3 * u, 0.25 * u, RGBA(90, 160, 70), seg: 6)
            mesh.ellipsoid(P(-1.5, 15.6, 0), P(1.7, 0.35, 0.9), RGBA(120, 200, 90), seg: 8, rings: 3)
            mesh.ellipsoid(P(1.6, 16.0, 0), P(1.7, 0.35, 0.9), RGBA(140, 214, 100), seg: 8, rings: 3)
        } else {
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                let x = cos(a) * 4.5, z = sin(a) * 4.0
                mesh.frustum(P(x * 0.5, 13, z * 0.5), P(x * 1.15, 7.5, z * 1.15), 0.8 * u, 0.4 * u, RGBA(40, 140, 100), seg: 6)
            }
            mesh.ellipsoid(P(-3, 11.5, 3.6), P(0.8, 0.8, 0.4), RGBA(250, 210, 120), seg: 6, rings: 3)
        }
        return mesh
    }

    /// What a character model adds to the human figure. `legs` is false for the merfolk (it has a tail instead).
    static func dressModel(_ m: CharacterModel, _ mesh: inout Mesh3D, look: Look, frame: Int, held: String, child: Bool, female: Bool, k: Float) {
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * (k / 16) }
        let u = k / 16
        let cloth = RGBA(hex: look.shirt)
        let sw: Float = frame == 1 ? 2 : (frame == 2 ? -2 : 0)
        switch m.key {
        case "wayfarer":
            mesh.ellipsoid(P(0, 21.3, -0.3), P(4.4, 1.0, 4.2), cloth.darkened(0.15), seg: 12, rings: 3)
            mesh.frustum(P(0, 22, -0.5), P(0, 25.5, -3.5), 4.0 * u, 2.0 * u, cloth.darkened(0.05), seg: 10)
            mesh.frustum(P(0, 25.5, -3.5), P(0, 24.5, -8.5), 2.0 * u, 0.3 * u, cloth.darkened(0.05), seg: 8)
            mesh.ellipsoid(P(0, 9.2, 0), P(3.7, 0.55, 2.5), RGBA(110, 74, 46), seg: 12, rings: 3)
            mesh.ellipsoid(P(0, 9.2, 2.45), P(0.7, 0.6, 0.2), RGBA(230, 196, 90), seg: 6, rings: 3)
        case "sage":
            let hat = RGBA(70, 80, 150)
            mesh.ellipsoid(P(0, 22.6, 0), P(7.2, 0.45, 7.0), hat.darkened(0.1), seg: 16, rings: 3)
            mesh.frustum(P(0, 22.8, 0), P(-0.6, 31, -1.5), 3.9 * u, 0.3 * u, hat, seg: 12)
            mesh.ellipsoid(P(0, 23.6, 0), P(3.95, 0.5, 3.75), RGBA(220, 190, 90), seg: 12, rings: 3)
            if !female && !child { mesh.ellipsoid(P(0, 15.6, 2.9), P(2.1, 2.8, 1.1), RGBA(244, 242, 236), seg: 10, rings: 5) }
        case "knight":
            let steel = RGBA(206, 214, 228)
            mesh.ellipsoid(P(0, 19.9, -0.2), P(4.5, 4.4, 4.2), steel, seg: 14, rings: 6, from: 0.52, to: 1)
            mesh.ellipsoid(P(0, 20.4, 0), P(4.55, 0.4, 4.25), steel.darkened(0.2), seg: 14, rings: 3)
            mesh.ellipsoid(P(0, 25.2, -1.2), P(0.8, 1.5, 3.0), RGBA(220, 70, 80), seg: 8, rings: 4)
            mesh.ellipsoid(P(0, 12.3, 0.35), P(4.2, 3.2, 2.7), steel, seg: 12, rings: 6)
        case "tinker":
            mesh.ellipsoid(P(0, 21, 0), P(4.05, 0.4, 3.85), RGBA(90, 64, 44), seg: 14, rings: 3)
            for s: Float in [-1, 1] {
                mesh.ellipsoid(P(s * 1.6, 21.1, 3.6), P(1.2, 1.1, 0.5), RGBA(110, 90, 70), seg: 8, rings: 4)
                mesh.ellipsoid(P(s * 1.6, 21.1, 3.95), P(0.85, 0.8, 0.25), RGBA(250, 190, 90), seg: 8, rings: 4)
            }
            mesh.ellipsoid(P(0, 9.5, 1.7), P(3.2, 3.8, 1.2), RGBA(150, 104, 66), seg: 10, rings: 5)
        case "merfolk":
            let tail = RGBA(70, 180, 190), fin = RGBA(150, 230, 220)
            mesh.frustum(P(0, 8, 0), P(0, 3.5, 0.6 + sw * 0.3), 3.3 * u, 2.1 * u, tail, seg: 12)
            mesh.frustum(P(0, 3.5, 0.6 + sw * 0.3), P(0, 1.0, 2.6 + sw), 2.1 * u, 0.7 * u, tail, seg: 10)
            mesh.ellipsoid(P(0, 0.7, 4.0 + sw), P(3.2, 0.35, 1.6), fin, seg: 10, rings: 3)
            for s: Float in [-1, 1] { mesh.ellipsoid(P(s * 4.3, 19.6, -0.6), P(0.3, 1.7, 1.3), fin, seg: 6, rings: 3) }
        case "diver":
            let brass = RGBA(214, 168, 80)
            mesh.frustum(P(0, 14.4, 0), P(0, 15.6, 0), 3.3 * u, 3.3 * u, brass, seg: 12)
            for y: Float in [16.0, 23.0] { mesh.ellipsoid(P(0, y, 0), P(5.0 - abs(y - 19.5) * 0.25, 0.35, 4.8 - abs(y - 19.5) * 0.25), RGBA(190, 236, 255), seg: 14, rings: 3) }
            mesh.ellipsoid(P(0, 25.0, 0), P(0.9, 0.7, 0.9), brass, seg: 8, rings: 4)
            for (x, s) in [(Float(-2), sw), (2, -sw)] { mesh.ellipsoid(P(x, 0.4, s + 2.6), P(1.7, 0.3, 3.0), RGBA(250, 140, 60), seg: 8, rings: 3) }
        case "coral_priest":
            let coral = RGBA(250, 120, 120)
            mesh.frustum(P(0, 10, 0), P(0, 0.4, 0), 3.6 * u, 5.8 * u, RGBA(150, 220, 210), seg: 14)
            for s: Float in [-1, 1] {
                mesh.frustum(P(s * 1.8, 22.8, 0), P(s * 3.6, 27.5, -0.5), 0.45 * u, 0.25 * u, coral, seg: 6)
                mesh.frustum(P(s * 3.0, 25.5, -0.3), P(s * 5.6, 27, -0.6), 0.35 * u, 0.2 * u, coral, seg: 6)
                mesh.frustum(P(s * 0.6, 23.2, 0.5), P(s * 1.0, 26.6, 0.6), 0.35 * u, 0.2 * u, coral.lightened(0.1), seg: 6)
                mesh.ellipsoid(P(s * 3.6, 27.6, -0.5), P(0.5, 0.5, 0.5), coral.lightened(0.2), seg: 6, rings: 3)
            }
        case "shell_guard":
            let shell = RGBA(250, 214, 170)
            for s: Float in [-1, 1] { mesh.ellipsoid(P(s * 4.7, 15.0, 0), P(2.3, 1.3, 2.3), shell, seg: 10, rings: 5, from: 0.45, to: 1) }
            if held.isEmpty {
                let gold = RGBA(230, 190, 80)
                mesh.frustum(P(5.4, 0, 1.5), P(5.4, 27, 1.5), 0.28 * u, 0.28 * u, gold, seg: 6)
                mesh.frustum(P(3.6, 27, 1.5), P(7.2, 27, 1.5), 0.25 * u, 0.25 * u, gold, seg: 6)
                for d: Float in [-1.8, 0, 1.8] { mesh.frustum(P(5.4 + d, 27, 1.5), P(5.4 + d, 30, 1.5), 0.22 * u, 0.08 * u, gold, seg: 6) }
            }
        default: break
        }
    }
}

// MARK: - the people of the underlands

/// Someone walking an underland's roads (not a villager: drawn from where and when, kept nowhere).
public struct UnderFolk {
    public let id: Int
    public let pos: Vec2
    public let facing: Vec2
    public let moving: Bool
    public let look: Look
    public let female: Bool, child: Bool
}

extension Society {
    /// The people of the underlands near a place: two or three on the roads of every chunk within reach,
    /// walking up and down, by the clock (the same people at the same time, wherever you look from).
    public func underFolk(center: Vec2, halfW: Double, halfH: Double, limit: Int = 40) -> [UnderFolk] {
        guard !underlandZones().isEmpty else { return [] }
        let x0 = Int(((center.x - halfW) / 512).rounded(.down)), x1 = Int(((center.x + halfW) / 512).rounded(.down))
        let y0 = Int(((center.y - halfH) / 512).rounded(.down)), y1 = Int(((center.y + halfH) / 512).rounded(.down))
        var out: [UnderFolk] = []
        let t = world.time
        for cy in y0...y1 { for cx in x0...x1 {
            guard let z = underlandZones().first(where: { $0.contains(cx, cy) }) else { continue }
            let n = 2 + Int(MP.h2(world.seed &+ 7070, cx, cy) % 2)
            for i in 0..<n {
                let h = MP.h2(world.seed &+ 7071 &+ i, cx, cy)
                let who = CharacterModels.resident(h, sea: z.sea)
                // a walk along one of the chunk's two roads, there and back, about a minute of world time each way
                let period = 60.0 + Double(h % 40)
                let ph = (t / period + Double(h % 1000) / 1000).truncatingRemainder(dividingBy: 2)
                let f = ph < 1 ? ph : 2 - ph
                let along = 1.5 + f * 29, back = ph >= 1
                let vertical = i % 2 == 0
                let lane = 15.5 + (i % 3 == 2 ? 1 : 0)
                let tx = Double(cx * 32) + (vertical ? lane : along), ty = Double(cy * 32) + (vertical ? along : lane)
                let d: Vec2 = vertical ? Vec2(0, back ? -1 : 1) : Vec2(back ? -1 : 1, 0)
                // a rest at each end of the road
                let resting = f < 0.03 || f > 0.97
                let id = 900_000_000 + Int((MP.h2(world.seed &+ 7072, cx, cy) & 0xffff)) * 8 + i
                out.append(UnderFolk(id: id, pos: Vec2(tx * 16, ty * 16), facing: resting ? Vec2(0, 1) : d, moving: !resting, look: who.look, female: who.female, child: who.child))
                if out.count >= limit { return out }
            }
        } }
        return out
    }
}
