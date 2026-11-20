import Foundation

// The nations of the sea floor (new worlds with oceans).
//
// * Out in the deep sea, one chunk in every 16 x 16 holds a city of people who breathe the water: a seabed
//   plaza ringed by coral walls with four gates, a pearl dome at its heart, coral houses round it, kelp
//   gardens, living coral, pearl lamps along its ways and shells on the floor (Generator.carveSeaCity).
// * Each has a nation of its own in the civilisation layer. They refuse war: no one may declare war on them
//   and they declare none; no envoy goes to or from them. They hold no land, and their cities are not
//   shown as towns on the land (they are already there, under the waves).

extension Generator {
    public static let seaCitySpacing = 16
    /// A city on the sea floor: one chunk in every 16 x 16, out in deep sea (oceans only).
    public func isSeaCity(_ cx: Int, _ cy: Int) -> Bool {
        guard oceans else { return false }
        let n = Generator.seaCitySpacing
        let rx = Int((Double(cx) / Double(n)).rounded(.down)), ry = Int((Double(cy) / Double(n)).rounded(.down))
        let h = MP.h2(seed &+ 4242, rx, ry)
        guard rx * n + 2 + Int(h % UInt32(n - 4)) == cx && ry * n + 2 + Int((h >> 8) % UInt32(n - 4)) == cy else { return false }
        // deep sea all round its middle
        for (dx, dy) in [(16, 16), (2, 2), (30, 2), (2, 30), (30, 30)] where climate(cx * 32 + dx, cy * 32 + dy).0 >= Biome.sea - 0.1 { return false }
        return true
    }

    func carveSeaCity(_ cx: Int, _ cy: Int, _ g: inout [UInt8], _ st: inout [UInt8], _ ob: inout [UInt8], _ de: inout [UInt8]) {
        let c = Content.shared
        let seabed = c.tid("seabed"), coralWall = c.tid("coral_wall"), dome = c.tid("pearl_dome"), coral = c.tid("coral")
        let kelp = c.tid("kelp"), lamp = c.tid("pearl_lamp"), shell = c.tid("shell"), deep = c.tid("deep_water")
        var r = RNG(seed: Int(MP.h2(seed &+ 4243, cx, cy)))
        for y in 0..<32 { for x in 0..<32 {
            let i = y * 32 + x
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5, d = (dx * dx + dy * dy).squareRoot()
            st[i] = 0; de[i] = 0; ob[i] = 0
            g[i] = d <= 14.5 ? seabed : deep
            // the ring wall of coral, with a gate at each point of the compass
            let gate = (abs(x - 15) <= 1 || abs(x - 16) <= 1) && (y < 4 || y > 27) || (abs(y - 15) <= 1 || abs(y - 16) <= 1) && (x < 4 || x > 27)
            if abs(d - 14) < 0.7 && !gate { ob[i] = coralWall }
            // the pearl dome at the heart, its door to the south
            if abs(d - 3.5) < 0.6 && !(y > 16 && abs(Double(x) - 15.5) < 1.2) { ob[i] = dome }
            // shells strewn on the plaza
            if d <= 13 && ob[i] == 0 && r.unit() < 0.03 { de[i] = shell }
        } }
        ob[16 * 32 + 15] = lamp                                         // light in the dome
        // inside the dome the floor is dry, and a stairway leads down to the nation's underland
        for y in 13...19 { for x in 13...19 { let dx = Double(x) - 15.5, dy = Double(y) - 15.5; if (dx * dx + dy * dy).squareRoot() < 3 { g[y * 32 + x] = c.tid("sand"); de[y * 32 + x] = 0 } } }
        ob[16 * 32 + 16] = c.tid("stairs_down")
        // coral houses round the dome: small rings of coral wall, each with a door towards the centre
        for (hx, hy) in [(7, 7), (21, 7), (7, 21), (21, 21), (15, 6), (15, 24)] {
            for y in hy..<(hy + 4) { for x in hx..<(hx + 4) {
                let i = y * 32 + x
                let edge = x == hx || x == hx + 3 || y == hy || y == hy + 3
                ob[i] = edge ? coralWall : 0
                if !edge { de[i] = 0 }
            } }
            let doorX = hx + (hx < 15 ? 3 : 0), doorY = hy + 1
            ob[doorY * 32 + doorX] = 0
            ob[(hy + 1) * 32 + hx + 1] = lamp
        }
        // kelp gardens between the houses, living coral by the wall, pearl lamps along the ways
        for (gx, gy) in [(4, 13), (25, 13), (13, 25), (17, 4)] { for y in gy..<(gy + 3) { for x in gx..<(gx + 3) where ob[y * 32 + x] == 0 { de[y * 32 + x] = kelp } } }
        for _ in 0..<14 {
            let a = r.unit() * 2 * .pi, rr = 11.5 + r.unit() * 1.5
            let x = Int(15.5 + cos(a) * rr), y = Int(15.5 + sin(a) * rr)
            if x >= 0, y >= 0, x < 32, y < 32, ob[y * 32 + x] == 0 { ob[y * 32 + x] = coral }
        }
        for k in [6, 10, 21, 25] { ob[15 * 32 + k] = lamp; ob[k * 32 + 16] = lamp }
    }
}

extension Civ {
    /// Found the nation of the sea-floor city in a region, once (when the region is first known).
    func foundSea(_ key: Int64, gen: Generator) {
        guard let r = regions[key], r.seaCity == nil, gen.oceans else { return }
        let per = cfg.regionTiles / 32
        var at: (Int, Int)?
        for cy in (r.ry * per)..<((r.ry + 1) * per) { for cx in (r.rx * per)..<((r.rx + 1) * per) where at == nil && gen.isSeaCity(cx, cy) { at = (cx, cy) } }
        guard let (cx, cy) = at else { return }
        let n = newPolity(origin: "undersea", near: key)
        polities[n]!.undersea = true
        polities[n]!.leaning = "agri"
        var h = RNG(seed: gen.seed &* 211 &+ cx &* 5 &+ cy &* 17)
        let adults = 50 + h.index(70)
        let c = newCity(at: key, nation: n, people: CivPeople(adults: adults, children: adults / 3, elders: adults / 5), firstCount: true, sea: true)
        c.facilities = ["farm": max(4, adults / 3), "fishery": 3, "house": adults / 4 + 2, "well": 2]
        c.stock = ["grain": Double(adults) * 15, "fish": Double(adults) * 4]
        for (k, v) in c.stock where CivFood.isFood(k) { totals.add(\.found, k, v) }
        c.cropDue = Double(day) + 3; c.cropPlots = c.has("farm")
        c.underAt = (cx, cy)
        c.dug = 40                                                       // the dome's own underland, to begin with
        polities[n]!.capital = c.id
        say("sea_nation", [polities[n]!.nameEn, polities[n]!.nameZh], [n], region: key)
    }

    /// The cities on the sea floor.
    public func seaCities() -> [CivCity] { cities.values.filter { $0.sea == true }.sorted { $0.id < $1.id } }
}
