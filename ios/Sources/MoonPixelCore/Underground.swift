import Foundation

// The nations of the underground (worlds meet them as they explore).
//
// * Under every underground city of the world (Generator.isUnderCity) lives a nation of its own: it grows like
//   any city, studies, trades with its own towns, and digs. It never starts a war with the surface, nor the
//   surface with it (Civ.declare, envoys), and it holds no land up there.
// * It digs outward: every day a city's diggers widen its halls (`dug`, in tiles from its centre). A city that
//   has dug far enough and has people to spare founds a new underground town under a neighbouring region.
// * Under the sea the rock is flooded (Generator.seaAbove): to go on there, a city makes sea glass (from stone,
//   with heat) and walls the water out; it founds a town under the sea only when it has the glass for it.
// * In the detailed world, near the player, the digging is real: the city's hall grows ring by ring, rock is
//   cleared, and wherever the ring meets water a wall of glass is set (Society.digUnderground).

extension Generator {
    /// Is there sea above this place (an ocean world's sea, deep enough)? The rock under it is flooded.
    public func seaAbove(_ wx: Int, _ wy: Int) -> Bool { oceans && climate(wx, wy).0 < Biome.sea - 0.04 }
}

public struct UnderTune {
    public static let digPerDay = 3.0            // tiles a day a city's hall widens (more with more people)
    public static let maxDug = 72.0              // tiles: a hall this wide is a whole town
    public static let townAt = 40.0              // dug this far, a city may found a new town next door
    public static let glassForSea = 120.0        // sea glass a town under the sea needs
}

extension Civ {
    /// Found the nation of the underground city under a region, once (when the region is first known).
    func foundUnder(_ key: Int64, gen: Generator) {
        guard var r = regions[key], r.underCity == nil else { return }
        let per = cfg.regionTiles / 32
        var at: (Int, Int)?
        for cy in (r.ry * per)..<((r.ry + 1) * per) { for cx in (r.rx * per)..<((r.rx + 1) * per) where at == nil && gen.isUnderCity(cx, cy) { at = (cx, cy) } }
        guard let (cx, cy) = at else { return }
        let n = newPolity(origin: "underground", near: key)
        polities[n]!.underground = true
        polities[n]!.leaning = "industry"
        var h = RNG(seed: gen.seed &* 131 &+ cx &* 7 &+ cy &* 13)
        let adults = 40 + h.index(60)
        let c = newCity(at: key, nation: n, people: CivPeople(adults: adults, children: adults / 3, elders: adults / 6), firstCount: true, under: true)
        c.facilities = ["farm": max(3, adults / 3), "house": adults / 4 + 2, "well": 2, "mine": 2]
        c.stock = ["grain": Double(adults) * 15, "stone": 200, "timber": 20]
        for (k, v) in c.stock where CivFood.isFood(k) { totals.add(\.found, k, v) }
        c.cropDue = Double(day) + 3; c.cropPlots = c.has("farm")
        c.underAt = (cx, cy)
        c.dug = 12
        polities[n]!.capital = c.id
        r = regions[key]!
        say("under_nation", [polities[n]!.nameEn, polities[n]!.nameZh], [n], region: key)
    }

    /// Once a day: the underground cities dig, make sea glass, and found new towns next door.
    func undergroundDaily() {
        for c in cities.values.sorted(by: { $0.id < $1.id }) where c.under == true {
            guard let p = polities[c.nation], p.status == .active else { continue }
            // dig: more hands, faster
            let hands = Double(c.people.band(1))
            c.dug = min(UnderTune.maxDug, c.dug + UnderTune.digPerDay * min(3, 0.5 + hands / 60))
            c.stock["stone", default: 0] += 4
            // sea glass: stone and heat (two stone a pane), when the city is under or beside the sea
            let wet = (regions[c.regionKey].map { $0.water >= 0.35 } ?? false) || Civ.four.contains { d in regions[MP.chunkKey(c.rx + d.0, c.ry + d.1)].map { $0.water >= 0.35 } ?? false }
            if wet, (c.stock["stone"] ?? 0) >= 10 { c.stock["stone"]! -= 10; c.stock["sea_glass", default: 0] += 5 }
            // a new town next door, when the hall is wide and the city has people to spare
            guard c.dug >= UnderTune.townAt, c.pop >= 60 else { continue }
            for (dx, dy) in Civ.four {
                let k = MP.chunkKey(c.rx + dx, c.ry + dy)
                guard let r = regions[k], r.underCity == nil else { continue }
                let sea = r.water >= 0.35
                if sea {
                    guard (c.stock["sea_glass"] ?? 0) >= UnderTune.glassForSea else { continue }
                    c.stock["sea_glass"]! -= UnderTune.glassForSea
                }
                var group = c.people.take(16, from: Array(6..<12))
                group.add(c.people.take(4, from: Array(0..<6)))
                let town = newCity(at: k, nation: c.nation, people: group, firstCount: false, under: true)
                town.facilities = ["farm": 4, "house": 5, "well": 1, "mine": 1]
                town.stock = takeFood(from: c, nutrition: Double(group.total) * 20)
                town.dug = 6
                town.underAt = (r.rx * (cfg.regionTiles / 32) + cfg.regionTiles / 64, r.ry * (cfg.regionTiles / 32) + cfg.regionTiles / 64)
                town.sealed = sea
                c.dug = UnderTune.townAt * 0.6
                say(sea ? "under_sea_town" : "under_town", [p.nameEn, p.nameZh, town.nameEn, town.nameZh], [c.nation], region: k)
                break
            }
        }
    }

    /// The underground nations, and their cities.
    public func undergroundCities() -> [CivCity] { cities.values.filter { $0.under == true }.sorted { $0.id < $1.id } }
}

extension Society {
    /// Near the player, underground, the digging is real: each underground city's hall grows ring by ring to
    /// the width its nation has dug; rock is cleared to floor, and where the ring meets water a glass wall holds
    /// the sea out. Each ring is dug once (the city remembers how far its hall has been carved).
    @discardableResult public func digUnderground(around t: TilePos, reach: Int = 160) -> Int {
        guard let c = realm.civBox, c.underNations else { return 0 }
        let u = underworld()
        let ct = Content.shared
        let floor = ct.tid("cave_floor"), glass = ct.tid("wall_glass")
        var changed = 0
        for city in c.undergroundCities() {
            guard let (cx, cy) = city.underAt else { continue }
            let centre = TilePos(cx * 32 + 16, cy * 32 + 16)
            guard abs(centre.x - t.x) <= reach && abs(centre.y - t.y) <= reach else { continue }
            let want = Int(city.dug)
            var r = max(city.carved, 15)                      // the city's own walls stand within 15 tiles
            while r < want {
                r += 1
                let n = Int(Double(r) * 6.3) + 8
                for k in 0..<n {
                    let a = Double(k) / Double(n) * 2 * .pi
                    let x = centre.x + Int((cos(a) * Double(r)).rounded()), y = centre.y + Int((sin(a) * Double(r)).rounded())
                    let g = u.tile(0, x, y), o = u.tile(2, x, y)
                    if ct.water[Int(g)] {
                        // the sea (or a flooded cavern): a glass wall on the hall's edge holds it back
                        if o != glass { u.setTile(2, x, y, glass); changed += 1 }
                    } else if o != 0, let d = ct.tile(o), !d.built {
                        u.setTile(2, x, y, 0); changed += 1          // rock and ore are dug out
                        if g == 0 { u.setTile(0, x, y, floor) }
                    }
                }
            }
            city.carved = r
        }
        return changed
    }
}
