import Foundation

// Landforms made on purpose (world warfare task book, section 2): in a world with oceans, every cell of the
// world (`cell` tiles a side) holds one landform of the ten kinds, at a place and of a kind fixed by the seed,
// stamped over the land the noise made. Within `clear` tiles of the start there is none (the start area is
// the same as in any world). Each stamp says what height it wants at a place and how strongly; the land is
// blended towards it, so the shape is unmistakable and its edges still meet the land around it.
//
//   strait     双门海峡   two seas, north and south, with a neck of land between them
//   basin      三关盆地   a fertile bowl ringed by high mountains, three valleys through them, one to the sea
//   delta      千汊河洲   a low fan of channels and islands where a river meets the sea
//   islands    群岛跳港   a chain of islands across open sea
//   innerSea   内海环抱   a ring of land round an inner sea with one narrow mouth
//   plateau    高原水塔   a high table land with valleys falling away on every side
//   terraces   瀑布台地   three steps of land down to the sea, joined by ramps
//   longBay    长湾双港   a long peninsula with deep water on both sides
//   atoll      环礁泻湖   a ring of reef around a lagoon, with a deep channel through it
//   blackSoil  背山黑土   a plain of rich soil with mountains behind it and the sea in front

public struct Landform: Equatable {
    public var kind: CivGeoTrait.Kind
    public var x: Double, y: Double           // centre (tiles)
    public var angle: Double                  // turn of the whole shape (radians)
    public var radius: Double
}

extension Generator {
    public static let landformCell = 6144.0, landformClear = 2200.0

    /// The landform of the cell a place is in (nil when the world has no oceans, or near the start).
    public func landform(near x: Double, _ y: Double) -> Landform? {
        guard oceans else { return nil }
        let C = Generator.landformCell
        let i = Int((x / C).rounded(.down)), j = Int((y / C).rounded(.down))
        var h = RNG(seed: seed &* 2_654_435_761 &+ i &* 97_531 &+ j &* 13_579 &+ 4242)
        let kinds = CivGeoTrait.Kind.allCases
        // the first four kinds come twice as often (the task book's first batch)
        let roll = h.index(kinds.count + 4)
        let kind = roll < kinds.count ? kinds[roll] : kinds[roll - kinds.count]
        let cx = (Double(i) + 0.5) * C + (h.unit() - 0.5) * C * 0.3
        let cy = (Double(j) + 0.5) * C + (h.unit() - 0.5) * C * 0.3
        guard (cx * cx + cy * cy).squareRoot() > Generator.landformClear + 1400 else { return nil }
        return Landform(kind: kind, x: cx, y: cy, angle: h.unit() * 2 * .pi, radius: 1300)
    }

    /// The height a landform wants at a place, and how strongly (0 none ... 1 all).
    public func landformShape(_ x: Double, _ y: Double) -> (target: Double, weight: Double)? {
        guard let f = landform(near: x, y) else { return nil }
        let dx = x - f.x, dy = y - f.y
        let d = (dx * dx + dy * dy).squareRoot()
        let R = f.radius
        guard d < R * 1.25 else { return nil }
        // into the shape's own frame: u along it, v across it, in units of its radius
        let ca = cos(f.angle), sa = sin(f.angle)
        let u = (dx * ca + dy * sa) / R, v = (-dx * sa + dy * ca) / R
        let r = d / R
        let edge = Swift.max(0, Swift.min(1, (1.25 - r) / 0.25))          // fades out over the last quarter
        let sea = 0.18, low = 0.42, mid = 0.55, high = 0.72, peak = 1.02
        let target: Double
        switch f.kind {
        case .strait:
            // a neck of land across the middle, a sea each side
            target = abs(v) < 0.16 ? mid : sea
        case .basin:
            let a = atan2(v, u)
            let gate = [0.0, 2.1, -2.1].contains { g in abs(remainder(a - g, 2 * .pi)) < 0.3 }      // valleys a region wide
            if r < 0.42 { target = mid }
            else if r < 0.95 { target = gate ? mid + 0.04 : peak }
            else { target = gate && abs(remainder(a, 2 * .pi)) < 0.3 ? sea : mid }    // the first valley runs to the sea
        case .delta:
            // channels fanning out towards the sea (u > 0), islands between them
            if u > 0.55 { target = sea }
            else {
                let fan = atan2(v, u + 1.2) * 9
                let channel = abs(sin(fan)) < 0.28 || abs(sin((u + 1.4) * 9)) < 0.18
                target = channel ? sea + 0.12 : low
            }
        case .islands:
            // islands along the line every 0.6 radii (about three regions apart), each about a region across
            let cu = (u / 0.6).rounded() * 0.6
            let di = ((u - cu) * (u - cu) + v * v).squareRoot()
            target = di < 0.2 ? mid : sea
        case .innerSea:
            let mouth = u > 0.6 && abs(v) < 0.08
            if r < 0.55 { target = sea } else if r < 0.88 { target = mouth ? sea : mid } else { target = sea }
        case .plateau:
            let a = atan2(v, u)
            let valley = abs(sin(a * 2.5)) < 0.18
            target = r < 0.55 ? (valley && r > 0.3 ? mid : high + 0.04) : (valley ? low : mid)
        case .terraces:
            target = u < -0.3 ? high : (u < 0.25 ? mid : (u < 0.7 ? low : sea))
        case .longBay:
            target = abs(v) < 0.14 && u < 0.85 ? mid : (abs(v) < 0.5 ? sea - 0.1 : sea)
        case .atoll:
            let channel = u > 0 && abs(v) < 0.07
            target = r > 0.62 && r < 0.78 && !channel ? low : (channel ? sea - 0.12 : (r < 0.62 ? sea + 0.08 : sea))
        case .blackSoil:
            target = u < -0.55 ? peak : (u < 0.55 ? mid - 0.02 : sea)
        }
        return (target, 0.92 * edge)
    }

    /// The land's height with the landforms applied (new worlds with oceans; otherwise unchanged).
    @inline(__always) public func shaped(_ e: Double, _ x: Double, _ y: Double) -> Double {
        guard oceans, let s = landformShape(x, y) else { return e }
        return e * (1 - s.weight) + s.target * s.weight
    }

    /// Where a place is in a basin: "inside", "ring", "gate" (a pass through the ring) or nil. The survey uses it
    /// so that, region by region, the ring is impassable and each gate is a pass (rough but passable).
    public func basinPart(_ x: Double, _ y: Double) -> String? {
        guard let f = landform(near: x, y), f.kind == .basin else { return nil }
        let dx = x - f.x, dy = y - f.y
        let r = (dx * dx + dy * dy).squareRoot() / f.radius
        let ca = cos(f.angle), sa = sin(f.angle)
        let u = (dx * ca + dy * sa), v = (-dx * sa + dy * ca)
        let a = atan2(v, u)
        if r < 0.42 { return "inside" }
        if r < 0.95 { return [0.0, 2.1, -2.1].contains { g in abs(remainder(a - g, 2 * .pi)) < 0.12 } ? "gate" : "ring" }
        return nil
    }

    /// Is this place one of a delta's channels (the region counts as river land)?
    public func deltaChannel(_ x: Double, _ y: Double) -> Bool {
        guard let f = landform(near: x, y), f.kind == .delta else { return false }
        let dx = x - f.x, dy = y - f.y
        return (dx * dx + dy * dy).squareRoot() < f.radius
    }
}
