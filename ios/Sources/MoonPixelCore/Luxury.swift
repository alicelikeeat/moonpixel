import Foundation

// The well-off part of a growing town: a villa quarter and luxury cars.
//
// Once a district has 300 people it begins a villa quarter (at the edge, the next villas beside the first):
// each villa stands in a fenced garden of lawn, flower beds and trees, with a swimming pool, a paved drive and
// a two-storey house of limestone and glass with a balcony; each has a luxury car of its own on the drive,
// which its owners drive about the town like any resident's car. With eight villas the town opens a luxury car
// showroom beside them: a glass hall with six cars on show (they never leave it). Every car is a real vehicle,
// bought with the district's goods; its model and paint are its own.

/// The models of car. An ordinary resident's car is a saloon; the rest are luxury cars.
public enum CarModel: String, CaseIterable {
    case saloon, sports, supercar, limousine, suv
    public static let luxury: [CarModel] = [.sports, .supercar, .limousine, .suv]
    public func name(zh: Bool) -> String {
        switch self {
        case .saloon: return zh ? "轿车" : "Saloon"
        case .sports: return zh ? "跑车" : "Sports car"
        case .supercar: return zh ? "超级跑车" : "Supercar"
        case .limousine: return zh ? "豪华轿车" : "Limousine"
        case .suv: return zh ? "豪华SUV" : "Luxury SUV"
        }
    }
    /// The paints this model comes in.
    public var paints: [String] {
        switch self {
        case .saloon: return ["#d84038"]
        case .sports: return ["#e8242c", "#f2c418", "#1c56d8", "#f4f4f2"]
        case .supercar: return ["#ff7a12", "#7ad02a", "#c8102e", "#e8e8ec", "#1a1a20"]
        case .limousine: return ["#121216", "#f2f0ea", "#3a3a44"]
        case .suv: return ["#1c1c22", "#d8d8dc", "#24365a", "#5a4632"]
        }
    }
}

extension Vehicle {
    /// The car's model (a saloon when none is set, and for anything that is not a car).
    public var carModel: CarModel { model.flatMap(CarModel.init(rawValue:)) ?? .saloon }
}

extension Society {
    /// The villa or showroom a district should build next, or nil: villas from 300 people (one per 120 more,
    /// 24 at most), a showroom once there are eight villas.
    func luxuryToBuild(_ d: District) -> String? {
        let pop = d.population
        guard pop >= 300 else { return nil }
        // a public swimming pool from 400 people, another for every 1500 more
        let pools = d.buildings.filter { $0.kind == "pool" && $0.state != .burnt }.count
        if pop >= 400 && pools < 1 + (pop - 400) / 1500 { return "pool" }
        let villas = d.buildings.filter { $0.kind == "villa" && $0.state != .burnt }.count
        if villas >= 8 && !d.buildings.contains(where: { $0.kind == "showroom" && $0.state != .burnt }) { return "showroom" }
        let want = min(24, 1 + (pop - 300) / 120)
        // only when its homes are filling up, like any other housing
        guard villas < want, d.homes == 0 || Double(pop) / Double(d.homes) > 0.8 else { return nil }
        return "villa"
    }

    /// A luxury car bought by a district (its goods: what the store lacks is bought in), of a model and paint
    /// chosen for it, standing at `t`. Nil when it cannot be paid for or there is no room there.
    @discardableResult func buyLuxuryCar(_ d: District, at t: TilePos, heading: Double, pick: Int, showcase: Bool = false) -> Vehicle? {
        buyShortfall(d, VehicleKind.car.spec.build, keep: 0)
        guard let v = buildVehicle(.car, at: t, heading: heading, payer: .district(d.id), nation: d.nation) else { return nil }
        let m = CarModel.luxury[pick % CarModel.luxury.count]
        v.model = m.rawValue
        v.paint = m.paints[(pick / CarModel.luxury.count) % m.paints.count]
        v.showcase = showcase ? true : nil
        v.name = m.name(zh: false) + " \(v.id)"
        if showcase { v.halted = "on show" }
        return v
    }

    /// A villa: a fenced garden (lawn, flower beds, trees at the corners), a pool, a paved drive to the gate, and
    /// a two-storey house of limestone with glass on the north side (a balcony on the upper floor, stairs up);
    /// its luxury car on the drive.
    func raiseVilla(_ b: CityBuilding, _ d: District) {
        let fence = content.tid("fence"), gate = content.tid("fence_gate"), grass = content.tid("grass")
        let stoneF = content.tid("stone_floor"), woodF = content.tid("wood_floor")
        let wall = content.tid("wall_limestone"), glass = content.tid("wall_glass"), door = content.tid("door_wood")
        let pool = content.tid("shallow_water")
        let flowers = [content.tid("flower_red"), content.tid("flower_yellow"), content.tid("flower_blue")]
        // the house: x 2..9, y 1..5 of the lot; the pool: x 10..12, y 6..8; the drive: x 2..3 from the house to the gate
        let hx0 = 2, hx1 = 9, hy0 = 1, hy1 = 5
        let gateX = b.entrance.x - b.x
        for y in 0..<b.d { for x in 0..<b.w {
            let t = TilePos(b.x + x, b.y + y)
            world.setTile(1, t.x, t.y, 0); world.setTile(3, t.x, t.y, 0)
            if let o = content.tile(world.tile(2, t.x, t.y)), o.natural { world.setTile(2, t.x, t.y, 0) }
            let edge = x == 0 || y == 0 || x == b.w - 1 || y == b.d - 1
            let house = x >= hx0 && x <= hx1 && y >= hy0 && y <= hy1
            let inPool = x >= 10 && x <= 12 && y >= 6 && y <= 8
            let drive = (x == gateX || x == gateX - 1) && y > hy1 && !edge
            world.setTile(0, t.x, t.y, house ? woodF : (inPool ? pool : (drive ? stoneF : grass)))
            if edge {
                world.setTile(2, t.x, t.y, t == b.entrance ? gate : fence)
            } else if house {
                let hEdge = x == hx0 || x == hx1 || y == hy0 || y == hy1
                if hEdge {
                    let glazed = (y == hy1 && x != hx0 && x != hx1 && x % 2 == 0) || (y == hy0 && x > hx0 && x < hx1 && x % 3 == 0)
                    world.setTile(2, t.x, t.y, (y == hy1 && x == gateX - 1) ? door : (glazed ? glass : wall))
                } else { world.setTile(2, t.x, t.y, 0) }
            } else if !drive && !inPool && (y == b.d - 2 || x == 1 || x == b.w - 2) && (x + y) % 2 == 0 {
                world.setTile(3, t.x, t.y, flowers[(x + y * 3) % 3])                  // flower beds along the fence
            } else {
                world.setTile(2, t.x, t.y, 0)
            }
        } }
        // trees at the garden's corners, a sun lounger (a table) and a lantern by the pool
        for (x, y) in [(1, b.d - 2), (b.w - 2, b.d - 2), (b.w - 2, 1)] where world.tile(2, b.x + x, b.y + y) == 0 { world.setTile(2, b.x + x, b.y + y, content.tid("tree_oak")) }
        world.setTile(2, b.x + 11, b.y + 9, content.tid("table"))
        world.setTile(2, b.x + 13 - 1, b.y + 5, content.tid("lantern_post"))
        // furniture: a bed, a bookshelf, a table and chairs, a kitchen
        world.setTile(2, b.x + hx0 + 1, b.y + hy0 + 1, content.tid("kitchen"))
        world.setTile(2, b.x + hx0 + 3, b.y + hy0 + 2, content.tid("table"))
        world.setTile(2, b.x + hx0 + 4, b.y + hy0 + 2, content.tid("chair"))
        world.setTile(2, b.x + hx1 - 1, b.y + hy0 + 1, content.tid("bookshelf"))
        // the upper floor: the same rooms over the house, glass to the garden, a balcony over the drive side
        if b.floors.count >= 2 {
            let up = storeyWorld(1)
            for y in hy0...(hy1 + 1) { for x in hx0...hx1 {
                let t = TilePos(b.x + x, b.y + y)
                if y == hy1 + 1 {
                    // the balcony: a floor on the wall below, a railing (fence) along its edge
                    up.setTile(0, t.x, t.y, stoneF); up.setTile(2, t.x, t.y, fence)
                    continue
                }
                up.setTile(0, t.x, t.y, woodF)
                let hEdge = x == hx0 || x == hx1 || y == hy0 || y == hy1
                up.setTile(2, t.x, t.y, hEdge ? ((y == hy1 && x > hx0 && x < hx1) ? glass : wall) : 0)
            } }
            up.setTile(2, b.x + hx0 + 1, b.y + hy0 + 1, content.tid("bed"))
            up.setTile(2, b.x + hx0 + 3, b.y + hy0 + 1, content.tid("bed"))
            up.setTile(2, b.x + hx1 - 1, b.y + hy0 + 1, content.tid("flower_pot"))
            // a door out to the balcony, and the stairs
            up.setTile(2, b.x + hx0 + 3, b.y + hy1, door)
            let st = TilePos(b.x + hx1 - 1, b.y + hy1 - 1)
            world.setTile(2, st.x, st.y, content.tid("stairs_up"))
            linkUp(at: st, from: world)
        }
        keepClear(b.front); keepClear(b.entrance)
        // its luxury car, on the drive in front of the house
        if !realm.transport.vehicles.contains(where: { $0.owner == .district(d.id) && $0.model != nil && $0.showcase != true && $0.tile.x >= b.x && $0.tile.x < b.x + b.w && $0.tile.y >= b.y && $0.tile.y < b.y + b.d }) {
            let n = d.buildings.filter { $0.kind == "villa" }.count
            buyLuxuryCar(d, at: TilePos(b.x + gateX, b.y + hy1 + 2), heading: .pi / 2, pick: n * 7 + b.id)
        }
    }

    /// A luxury car showroom: a hall walled in glass on a polished floor, a reception desk, and six luxury cars
    /// on show in two rows (each model, in its paints).
    func raiseShowroom(_ b: CityBuilding, _ d: District) {
        let glass = content.tid("wall_glass"), steel = content.tid("spire_steel"), door = content.tid("door_wood")
        let floor = content.tid("stone_floor")
        for y in 0..<b.d { for x in 0..<b.w {
            let t = TilePos(b.x + x, b.y + y)
            world.setTile(1, t.x, t.y, 0); world.setTile(3, t.x, t.y, 0)
            world.setTile(0, t.x, t.y, floor)
            let edge = x == 0 || y == 0 || x == b.w - 1 || y == b.d - 1
            let corner = (x == 0 || x == b.w - 1) && (y == 0 || y == b.d - 1)
            if edge { world.setTile(2, t.x, t.y, t == b.entrance ? door : (corner || x % 6 == 0 ? steel : glass)) }
            else { world.setTile(2, t.x, t.y, 0) }
        } }
        world.setTile(2, b.x + b.w / 2 - 2, b.y + b.d - 3, content.tid("desk"))
        world.setTile(2, b.x + 1, b.y + 1, content.tid("flower_pot")); world.setTile(2, b.x + b.w - 2, b.y + 1, content.tid("flower_pot"))
        keepClear(b.front); keepClear(b.entrance)
        let shown = realm.transport.vehicles.filter { $0.showcase == true && $0.owner == .district(d.id) && $0.tile.x >= b.x && $0.tile.x < b.x + b.w && $0.tile.y >= b.y && $0.tile.y < b.y + b.d }.count
        guard shown < 6 else { return }
        var k = 0
        for row in 0..<2 { for col in 0..<3 {
            defer { k += 1 }
            guard k >= shown else { continue }
            let t = TilePos(b.x + 3 + col * 5, b.y + 3 + row * 4)
            buyLuxuryCar(d, at: t, heading: row == 0 ? 0.35 : -0.35, pick: k + 4 * row, showcase: true)
        } }
    }
}

// MARK: - drawing the cars

public enum CarArt {
    /// A car seen from above, nose to the right (+x), on a canvas `len` x `wid` tiles at `ppt` pixels a tile:
    /// the body in its paint with a lighter top and a soft shadow, the glasshouse, lights, mirrors, wheels at
    /// the corners, and what makes each model itself (a long bonnet and spoiler, a wedge with intakes and a
    /// stripe, a long cabin with chrome, a tall box with a roof rack).
    public static func top(_ model: CarModel, paint: String, len: Double = 1.0, wid: Double = 0.62, ppt: Double = 32) -> Bitmap {
        let W = Int((len * ppt).rounded()), H = Int((wid * ppt).rounded())
        var c = Canvas(W, H, scale: 1)
        let p = RGBA(hex: paint)
        let dark = RGBA(30, 30, 36), glass = RGBA(70, 96, 128), chrome = RGBA(220, 224, 232)
        let w = Double(W), h = Double(H)
        let ink = p.darkened(0.45)
        c.inkColor = ink
        // wheels peeking out at the corners
        for x in [w * 0.2, w * 0.78] { for y in [h * 0.08, h * 0.92] { c.rect(x - w * 0.07, y - h * 0.07, w * 0.14, h * 0.14, dark, radius: 1) } }
        func body(_ inset: Double, _ nose: Double, _ tail: Double) {
            c.rect(w * tail, h * inset, w * (nose - tail), h * (1 - 2 * inset), p, ink: 1, radius: h * 0.28, shade: Shade(shadow: 0.2, light: 0.22, cut: 0.4, glint: -0.4))
        }
        switch model {
        case .saloon:
            body(0.1, 0.97, 0.03)
            c.rect(w * 0.3, h * 0.2, w * 0.4, h * 0.6, glass, ink: 0.6, radius: 2)
            c.rect(w * 0.38, h * 0.24, w * 0.22, h * 0.52, p.lightened(0.08), radius: 2)          // the roof
        case .sports:
            body(0.08, 0.98, 0.04)
            c.rect(w * 0.38, h * 0.22, w * 0.26, h * 0.56, glass, ink: 0.6, radius: 3)
            c.rect(w * 0.45, h * 0.27, w * 0.12, h * 0.46, p.lightened(0.06), radius: 2)
            c.rect(w * 0.04, h * 0.14, w * 0.06, h * 0.72, p.darkened(0.25), ink: 0.5)            // the spoiler
            for y in [h * 0.36, h * 0.64] { c.line(w * 0.7, y, w * 0.95, y, 0.8, p.lightened(0.25)) }   // bonnet creases
        case .supercar:
            // a wedge: the nose narrower than the tail, intakes on the flanks, a racing stripe
            c.poly([(w * 0.03, h * 0.08), (w * 0.7, h * 0.1), (w * 0.99, h * 0.28), (w * 0.99, h * 0.72), (w * 0.7, h * 0.9), (w * 0.03, h * 0.92)], p, ink: 1, shade: Shade(shadow: 0.22, light: 0.26))
            c.rect(w * 0.05, h * 0.44, w * 0.93, h * 0.12, RGBA(250, 250, 250, 200))
            c.poly([(w * 0.42, h * 0.24), (w * 0.62, h * 0.28), (w * 0.62, h * 0.72), (w * 0.42, h * 0.76)], glass, ink: 0.6)
            for y in [h * 0.12, h * 0.88] { c.rect(w * 0.28, y - h * 0.04, w * 0.12, h * 0.08, dark) }  // side intakes
            c.rect(w * 0.06, h * 0.2, w * 0.05, h * 0.6, dark)                                     // the rear wing
        case .limousine:
            body(0.12, 0.98, 0.02)
            c.rect(w * 0.18, h * 0.22, w * 0.6, h * 0.56, glass, ink: 0.6, radius: 2)
            c.rect(w * 0.24, h * 0.26, w * 0.5, h * 0.48, p.lightened(0.07), radius: 2)
            for y in [h * 0.13, h * 0.87] { c.line(w * 0.05, y, w * 0.95, y, 0.6, chrome) }         // chrome trim
            c.rect(w * 0.94, h * 0.32, w * 0.04, h * 0.36, chrome)                                 // the grille
        case .suv:
            body(0.06, 0.97, 0.03)
            c.rect(w * 0.22, h * 0.16, w * 0.52, h * 0.68, glass, ink: 0.6, radius: 2)
            c.rect(w * 0.26, h * 0.2, w * 0.44, h * 0.6, p.lightened(0.05), radius: 2)
            for y in [h * 0.28, h * 0.72] { c.line(w * 0.28, y, w * 0.68, y, 0.8, RGBA(40, 40, 46)) }   // the roof rails
        }
        // headlights and tail lights, wing mirrors
        c.inkColor = nil
        for y in [h * 0.22, h * 0.78] {
            c.ellipse(w * 0.955, y, w * 0.025, h * 0.07, RGBA(255, 250, 210))
            c.ellipse(w * 0.04, y, w * 0.02, h * 0.07, RGBA(220, 40, 40))
        }
        for y in [h * 0.04, h * 0.96] { c.ellipse(w * 0.62, y, w * 0.03, h * 0.05, p.darkened(0.2)) }
        // a gloss along the body
        c.line(w * 0.12, h * 0.3, w * 0.85, h * 0.3, 0.7, RGBA(255, 255, 255, 90))
        return c.image()
    }
}

extension Figure3D {
    /// The shape of a car model: its body and cabin as cross-sections along its length (t from the tail 0 to the
    /// nose 1: the bottom and top of the section in tiles, and its width as a share of the car's), its wheels.
    struct CarShape {
        var body: [(t: Float, y0: Float, y1: Float, w: Float)]
        var cabin: [(t: Float, y0: Float, y1: Float, w: Float)]
        var wheelR: Float
        var wheels: [Float]
    }

    static func shape(_ m: CarModel) -> CarShape {
        switch m {
        case .saloon:
            return CarShape(body: [(0, 0.11, 0.36, 0.9), (0.07, 0.09, 0.42, 1), (0.5, 0.09, 0.44, 1), (0.9, 0.09, 0.39, 1), (1, 0.12, 0.31, 0.88)],
                            cabin: [(0.24, 0.42, 0.44, 0.86), (0.33, 0.42, 0.7, 0.78), (0.62, 0.42, 0.7, 0.78), (0.74, 0.42, 0.44, 0.86)], wheelR: 0.13, wheels: [0.2, 0.8])
        case .sports:
            return CarShape(body: [(0, 0.09, 0.32, 0.92), (0.08, 0.08, 0.36, 1.02), (0.5, 0.08, 0.36, 1.02), (0.86, 0.08, 0.29, 1), (1, 0.1, 0.21, 0.84)],
                            cabin: [(0.3, 0.35, 0.37, 0.82), (0.4, 0.35, 0.56, 0.7), (0.57, 0.35, 0.56, 0.7), (0.72, 0.35, 0.37, 0.82)], wheelR: 0.13, wheels: [0.2, 0.8])
        case .supercar:
            return CarShape(body: [(0, 0.07, 0.31, 1), (0.15, 0.06, 0.34, 1.06), (0.55, 0.06, 0.32, 1.04), (0.85, 0.06, 0.23, 0.96), (1, 0.07, 0.15, 0.78)],
                            cabin: [(0.3, 0.31, 0.33, 0.82), (0.41, 0.31, 0.48, 0.66), (0.57, 0.3, 0.46, 0.64), (0.7, 0.3, 0.31, 0.8)], wheelR: 0.135, wheels: [0.2, 0.79])
        case .limousine:
            return CarShape(body: [(0, 0.11, 0.38, 0.9), (0.05, 0.1, 0.45, 1), (0.95, 0.1, 0.45, 1), (1, 0.12, 0.36, 0.88)],
                            cabin: [(0.12, 0.44, 0.46, 0.86), (0.2, 0.44, 0.64, 0.8), (0.74, 0.44, 0.64, 0.8), (0.82, 0.44, 0.46, 0.86)], wheelR: 0.13, wheels: [0.15, 0.85])
        case .suv:
            return CarShape(body: [(0, 0.16, 0.5, 0.95), (0.06, 0.15, 0.6, 1), (0.94, 0.15, 0.6, 1), (1, 0.17, 0.48, 0.93)],
                            cabin: [(0.14, 0.6, 0.62, 0.92), (0.21, 0.6, 0.95, 0.86), (0.82, 0.6, 0.95, 0.86), (0.88, 0.6, 0.62, 0.92)], wheelR: 0.18, wheels: [0.2, 0.8])
        }
    }

    /// A car of a model in its paint, centred on the origin, nose along +x, wheels on y = 0, the size of the
    /// car's spec: a body lofted through rounded cross-sections from tail to nose, a glass cabin with a painted
    /// roof over it, round wheels (tyre, rim, spokes), round head and tail lights, and each model's own parts
    /// (a spoiler, a rear wing and intakes, chrome and a grille, roof rails).
    public static func car(_ model: CarModel, paint: String) -> Mesh3D {
        var m = Mesh3D()
        let sp = VehicleKind.car.spec
        // drawn with a car's proportions (about two and a half times as long as it is wide); the space it takes
        // on the road (its spec) is unchanged. A limousine is drawn longer, an SUV broader.
        let L = Float(sp.length) * (model == .limousine ? 1.25 : 1)
        let W = Float(sp.length) * (model == .suv ? 0.52 : 0.46), hl = L / 2, hw = W / 2
        let p = RGBA(hex: paint), glass = RGBA(84, 124, 162), dark = RGBA(30, 30, 36), chrome = RGBA(218, 222, 230)
        let sh = shape(model)
        func x(_ t: Float) -> Float { -hl + t * L }
        // the body
        let body = sh.body.map { s in (x: x(s.t), ring: Mesh3D.roundedSection(w: W * s.w, y0: s.y0, y1: s.y1, r: 0.05, rt: 0.09)) }
        m.loft(body, p)
        // the cabin: glass all round, then the roof over its flat middle
        let cabin = sh.cabin.map { s in (x: x(s.t), ring: Mesh3D.roundedSection(w: W * s.w, y0: s.y0, y1: s.y1, r: 0.02, rt: 0.06)) }
        m.loft(cabin, glass)
        if sh.cabin.count >= 4 {
            let a = sh.cabin[1], b = sh.cabin[sh.cabin.count - 2]
            let roof = [(x: x(a.t) + 0.015, ring: Mesh3D.roundedSection(w: W * a.w * 0.96, y0: a.y1 - 0.012, y1: a.y1 + 0.02, r: 0.01, rt: 0.03)),
                        (x: x(b.t) - 0.015, ring: Mesh3D.roundedSection(w: W * b.w * 0.96, y0: b.y1 - 0.012, y1: b.y1 + 0.02, r: 0.01, rt: 0.03))]
            m.loft(roof, p.lightened(0.04))
        }
        // wheels, just inside the body's sides
        for t in sh.wheels { for z in [-hw + 0.04, hw - 0.04] { m.wheel(SIMD3(x(t), sh.wheelR, z), radius: sh.wheelR, width: 0.08) } }
        // head lights at the nose, tail lights at the back (round, a little proud of the body)
        let nose = sh.body.last!, tail = sh.body.first!
        for z in [-W * nose.w * 0.32, W * nose.w * 0.32] {
            m.ellipsoid(SIMD3(hl - 0.01, nose.y0 + (nose.y1 - nose.y0) * 0.6, z), SIMD3(0.02, 0.028, 0.05), RGBA(255, 250, 214), seg: 8, rings: 4)
        }
        for z in [-W * tail.w * 0.34, W * tail.w * 0.34] {
            m.ellipsoid(SIMD3(-hl + 0.01, tail.y0 + (tail.y1 - tail.y0) * 0.65, z), SIMD3(0.02, 0.025, 0.06), RGBA(214, 36, 40), seg: 8, rings: 4)
        }
        // wing mirrors
        if let front = sh.cabin.last { for s: Float in [-1, 1] { m.ellipsoid(SIMD3(x(front.t) - 0.04, front.y0 + 0.03, s * (W * 0.5 + 0.03)), SIMD3(0.03, 0.02, 0.025), p, seg: 6, rings: 3) } }
        switch model {
        case .sports:
            m.roundedBox(-hl + 0.01, 0.38, -hw + 0.05, -hl + 0.09, 0.42, hw - 0.05, r: 0.012, p.darkened(0.3))      // the spoiler
            for z in [-hw + 0.12, hw - 0.12] { m.frustum(SIMD3(-hl + 0.05, 0.3, z), SIMD3(-hl + 0.05, 0.39, z), 0.012, 0.012, dark, seg: 5) }
        case .supercar:
            m.roundedBox(-hl, 0.42, -hw - 0.01, -hl + 0.1, 0.46, hw + 0.01, r: 0.012, dark)                          // the rear wing
            for z in [-hw + 0.14, hw - 0.14] { m.frustum(SIMD3(-hl + 0.05, 0.3, z), SIMD3(-hl + 0.05, 0.43, z), 0.012, 0.012, dark, seg: 5) }
            for z in [-hw * 1.06, hw * 1.06] { m.roundedBox(-hl * 0.3, 0.13, z - 0.015, -hl * 0.02, 0.25, z + 0.015, r: 0.01, dark) }   // side intakes
            m.roundedBox(-hl, 0.33, -0.05, hl * 0.9, 0.345, 0.05, r: 0.004, RGBA(246, 246, 246))                 // the stripe
        case .limousine:
            m.roundedBox(hl - 0.02, 0.17, -hw * 0.6, hl + 0.015, 0.38, hw * 0.6, r: 0.01, chrome)                  // the grille
            for z in [-hw - 0.005, hw + 0.005] { m.roundedBox(-hl + 0.04, 0.27, z - 0.006, hl - 0.04, 0.29, z + 0.006, r: 0.003, chrome) }
        case .suv:
            m.roundedBox(hl - 0.02, 0.22, -hw * 0.66, hl + 0.015, 0.48, hw * 0.66, r: 0.012, chrome)
            for z in [-hw * 0.7, hw * 0.7] { m.roundedBox(x(0.24), 0.965, z - 0.012, x(0.8), 0.99, z + 0.012, r: 0.005, dark) }   // roof rails
            m.roundedBox(-hl - 0.03, 0.18, -hw * 0.7, -hl + 0.01, 0.26, hw * 0.7, r: 0.01, dark)                   // the rear step
        case .saloon:
            m.roundedBox(hl - 0.015, 0.16, -hw * 0.5, hl + 0.01, 0.27, hw * 0.5, r: 0.01, dark)                    // the grille
        }
        return m
    }
}
