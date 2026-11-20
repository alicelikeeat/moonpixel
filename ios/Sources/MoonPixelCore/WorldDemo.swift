import Foundation

// The battle of the twin ports, made in the player's own world and played on its clock.
//
// In a world with oceans the nearest strait (a landform the world made: a neck of land between two seas) becomes
// the small nation's: its west port and east port stand on the neck, with the high platform between them; a great
// power is set on the land over the northern sea, with its carrier at sea, transports, and a sky carrier with
// frames. The player is set down at the east port. Then, hour by hour of game time: the envoy goes and is answered
// (as the player chose), the carrier sails, a fighter flies, tanks come ashore, the shifter runs east, the giantess
// guards the port or carries its people west, the sky carrier drops its frames, and the war for the port is fought
// and settled. The ports become towns as the player comes near; the machines and the giantess stand by them.

public struct WorldDemoState: Codable, Equatable {
    public var stage = 0
    public var next = 0.0
    public var refuse = true
    public var drop = "eastPort", giant = "guardEast"
    public var great = 0, small = 0
    public var capital = 0, west = 0, east = 0
    public var platform: Int64 = 0, offSea: Int64 = 0
    public var carrierForce = 0, transportForce = 0, skyForce = 0, shifter = 0, giantID = 0
    public var frames: [Int] = []
    public var envoy: Int?
    public var done = false
    /// Where the player is set down to watch (the east port).
    public var watch = TilePos(0, 0)
    public var log: [String] = []
}

extension Society {
    /// The strait nearest a place, within a few landform cells.
    func nearestStrait(to t: TilePos) -> Landform? {
        let C = Generator.landformCell
        let i0 = Int((Double(t.x) / C).rounded(.down)), j0 = Int((Double(t.y) / C).rounded(.down))
        var best: (Double, Landform)?
        for j in (j0 - 3)...(j0 + 3) { for i in (i0 - 3)...(i0 + 3) {
            guard let f = world.gen.landform(near: (Double(i) + 0.5) * C, (Double(j) + 0.5) * C), f.kind == .strait else { continue }
            let d = (f.x - Double(t.x)) * (f.x - Double(t.x)) + (f.y - Double(t.y)) * (f.y - Double(t.y))
            if best == nil || d < best!.0 { best = (d, f) }
        } }
        return best?.1
    }

    /// Set the battle up in this world. Returns nil and the place to watch from, or the reason it cannot be done:
    /// "needs_oceans" (an old world), "running", "no_strait", "no_shore".
    public func startWorldDemo(refuse: Bool, drop: TwinPorts.Drop, giant: TwinPorts.Giant) -> (error: String?, watch: TilePos?) {
        guard world.gen.oceans else { return ("needs_oceans", nil) }
        if let d = realm.worldDemo, !d.done { return ("running", nil) }
        let me = explorer ?? TilePos(0, 0)
        guard let f = nearestStrait(to: me) else { return ("no_strait", nil) }
        let c = civ
        c.envoys = true
        let ca = cos(f.angle), sa = sin(f.angle)
        func at(_ u: Double, _ v: Double) -> TilePos { TilePos(Int(f.x + (u * ca - v * sa) * f.radius), Int(f.y + (u * sa + v * ca) * f.radius)) }
        func region(_ t: TilePos) -> Int64 { let (rx, ry) = Civ.regionOf(tile: t, size: c.cfg.regionTiles); return MP.chunkKey(rx, ry) }
        let westT = at(-0.6, 0), eastT = at(0.6, 0), platT = at(0, 0)
        c.discover(around: platT, radius: 7, gen: world.gen)
        // the great power: the first land over the northern sea, else the nearest land outside the strait
        var home: Int64?
        for k in stride(from: 1.4, through: 4.5, by: 0.2) {
            let key = region(at(0, k))
            c.discover(around: at(0, k), radius: 1, gen: world.gen)
            if let r = c.regions[key], c.isLand(r), r.land >= 0.5 { home = key; break }
        }
        if home == nil {
            home = c.regions.values.filter { c.isLand($0) && $0.land >= 0.5 && $0.form != "strait" }.min { a, b in
                let da = abs(a.rx * c.cfg.regionTiles - platT.x) + abs(a.ry * c.cfg.regionTiles - platT.y)
                let db = abs(b.rx * c.cfg.regionTiles - platT.x) + abs(b.ry * c.cfg.regionTiles - platT.y)
                return da != db ? da < db : a.key < b.key }?.key
        }
        guard let homeKey = home else { return ("no_shore", nil) }
        // the sea for the carrier: the northern sea off the strait
        var sea = region(at(0.3, 0.7))
        if !(c.regions[sea].map(c.isSea) ?? false), let s = c.regions.values.filter({ c.isSea($0) }).min(by: { abs($0.rx - MP.keyCX(homeKey)) + abs($0.ry - MP.keyCY(homeKey)) < abs($1.rx - MP.keyCX(homeKey)) + abs($1.ry - MP.keyCY(homeKey)) }) { sea = s.key }
        let offSea = region(at(0.6, 0.7))
        // the two nations, and their cities (a city already there passes to them)
        let great = c.newPolity(origin: "first", near: homeKey), small = c.newPolity(origin: "first", near: region(eastT))
        func cityAt(_ key: Int64, _ n: Int, adults: Int) -> CivCity {
            if let id = c.regions[key]?.city, let old = c.cities[id] { c.transfer(old, to: n); if old.pop < adults { old.people.add(CivPeople(adults: adults - old.pop)); c.totals.newly += adults - old.pop } ; return old }
            let k = c.newCity(at: key, nation: n, people: CivPeople(adults: adults, children: adults / 3), firstCount: true)
            return k
        }
        let capital = cityAt(homeKey, great, adults: 3000)
        capital.facilities = ["farm": 800, "house": 900, "well": 4, "shipyard": 2, "airfield": 1, "plant": 6, "fusion_plant": 4]
        capital.stock["grain", default: 0] += 1e6; c.totals.add(\.found, "grain", 1e6)
        let west = cityAt(region(westT), small, adults: 120), east = cityAt(region(eastT), small, adults: 160)
        for k in [west, east] { k.facilities = ["farm": 60, "house": 50, "well": 2, "barracks": 1]; k.stock["grain", default: 0] += 2e4; c.totals.add(\.found, "grain", 2e4) }
        c.polities[great]!.capital = capital.id; c.polities[small]!.capital = east.id
        c.polities[great]!.techs += ["deep_yard", "naval_eng", "carrier_ops", "frame", "lift"]
        c.polities[great]!.treasury = 5000; c.polities[small]!.treasury = 800
        c.polities[great]!.ai = false; c.polities[small]!.ai = false
        c.polities[great]!.fatigue = -10; c.polities[small]!.fatigue = -10
        // the high platform between the ports: a pass that is the small nation's
        let plat = region(platT)
        if var r = c.regions[plat] { r.mountain = max(r.mountain, 0.45); r.land = max(r.land, 0.6); r.legal = small; r.control = small; r.claim = west.id; c.regions[plat] = r }
        c.refreshTerritory()
        let tp = TwinPorts(civ: c, great: great, small: small, capital: capital, west: west, east: east, platform: plat, offSea: offSea)
        tp.setupForces(carrierAt: sea, home: homeKey)
        var st = WorldDemoState()
        st.refuse = refuse; st.drop = drop.rawValue; st.giant = giant.rawValue
        st.great = great; st.small = small; st.capital = capital.id; st.west = west.id; st.east = east.id
        st.platform = plat; st.offSea = offSea
        st.carrierForce = tp.carrierForce; st.transportForce = tp.transportForce; st.skyForce = tp.skyForce
        st.shifter = tp.shifter; st.giantID = tp.giant; st.frames = tp.frames
        st.next = world.time
        st.watch = eastT
        st.log.append("set up at the strait (\(Int(f.x)), \(Int(f.y)))")
        realm.worldDemo = st
        c.record("demo_started", nations: [great, small], region: region(eastT))
        return (nil, eastT)
    }

    /// The battle rebuilt from what is saved (the world's own civilisation layer holds every piece of it).
    func demoBattle(_ st: WorldDemoState) -> TwinPorts? {
        let c = civ
        guard let capital = c.cities[st.capital], let west = c.cities[st.west], let east = c.cities[st.east] else { return nil }
        let tp = TwinPorts(civ: c, great: st.great, small: st.small, capital: capital, west: west, east: east, platform: st.platform, offSea: st.offSea)
        tp.carrierForce = st.carrierForce; tp.transportForce = st.transportForce; tp.skyForce = st.skyForce
        tp.shifter = st.shifter; tp.giant = st.giantID; tp.frames = st.frames
        return tp
    }

    /// Every game hour: the next step of the battle, when its time has come.
    func worldDemoHourly() {
        guard var st = realm.worldDemo, !st.done, world.time >= st.next, let tp = demoBattle(st) else { return }
        let c = civ
        let hour = MP.daySeconds / 24
        switch st.stage {
        case 0:
            if let id = c.sendEnvoy(st.great, to: st.small) {
                if let i = c.envoysOut.firstIndex(where: { $0.id == id }) { c.envoysOut[i].forced = st.refuse }
                st.envoy = id; st.stage = 1; st.log.append("the envoy set out")
            } else { st.done = true; st.log.append("no envoy could go") }
        case 1:
            guard let e = c.envoysOut.first(where: { $0.id == st.envoy }), e.state != .travelling else { break }
            if e.state == .refused { st.stage = 2; st.log.append("the envoy was refused: war for the east port") }
            else { st.done = true; st.log.append("the small nation submitted") }
        case 2: tp.openingSail(); st.stage = 3; st.next = world.time + 6 * hour; st.log.append("the carrier sails")
        case 3: tp.openingStrikeAndLand(); st.stage = 4; st.next = world.time + hour; st.log.append("a fighter flies; tanks come ashore")
        case 4:
            tp.openingDefence(giant: TwinPorts.Giant(rawValue: st.giant) ?? .guardEast)
            st.stage = 5; st.next = world.time + 12 * hour; st.log.append("the shifter runs east; the giantess acts")
        case 5:
            tp.skyDrop(TwinPorts.Drop(rawValue: st.drop) ?? .eastPort)
            st.stage = 6; st.log.append("the sky carrier drops its frames")
        default:
            let wars = c.targetWars.filter { $0.attacker == st.great && $0.defender == st.small }
            if !wars.isEmpty && wars.allSatisfy({ $0.ended != nil }) {
                tp.recordOutcome()
                st.done = true
                st.log.append(tp.east.nation == st.small ? "the east port held: the small nation keeps its way to the sea" : "the east port fell")
            }
        }
        realm.worldDemo = st
    }

    /// What the demonstration is doing, in a line, and its report once fought.
    public func worldDemoLines(zh: Bool) -> [String] {
        guard let st = realm.worldDemo else { return [] }
        let c = civ
        var out = [zh ? "世界演示：" + (st.done ? "已结束" : "第 \(st.stage) 步") : "In your world: " + (st.done ? "over" : "step \(st.stage)")]
        out += st.log.suffix(6)
        if let w = c.targetWars.last(where: { $0.attacker == st.great && $0.defender == st.small }) {
            let r = c.warLines(w, zh: zh)
            out.append(r.head); out += r.details
        }
        return out
    }
}
