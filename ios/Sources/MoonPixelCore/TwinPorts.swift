import Foundation

// The chronicle, held passes, and the battle of the twin ports (world warfare task book, final demonstration).
//
// * The chronicle: every event of the wars (envoys, answers, wars, stages, contests, captures, drops, rescues,
//   truces), in order, with the nations, the place and the ids involved. The same world and the same orders
//   give the same chronicle: a war can be replayed and checked from it.
// * A pass with no town is held by an enemy force standing in it (with troops that can hold ground) while no
//   force of the owner is there; it is given back the moment they leave. Held, it closes the owner's roads.
// * The battle of the twin ports: a small nation on a strait with an east port and a west port joined by a
//   road over a high platform; a great power over the sea with a carrier, fighters, tanks on transports and a
//   sky carrier with frames. Its envoy arrives; the answer depends on the seed (one seed for each). Refused, the
//   carrier comes, the fighters fly, tanks land at the east port as far as the quay takes them; the small
//   nation's shifter runs from the west port to the east; the giantess guards the east port or carries its
//   people west. Then the sky carrier drops its frames on the east port or on the platform. The east port
//   falls (and the next contest is reckoned again with the tanks ashore) or holds (withdrawal, truce, and the
//   small nation keeps its way to the sea).

public struct CivEvent: Codable, Equatable {
    public var t = 0.0
    public var kind = ""
    public var nations: [Int] = []
    public var region: Int64?
    public var ids: [Int] = []
    public var note = ""
}

extension Civ {
    func record(_ kind: String, nations: [Int], region: Int64? = nil, ids: [Int] = [], note: String = "") {
        chronicle.append(CivEvent(t: time, kind: kind, nations: nations, region: region, ids: ids, note: note))
        if chronicle.count > 4000 { chronicle.removeFirst(chronicle.count - 4000) }
    }

    /// The chronicle in lines, for the war report and the history panel.
    public func chronicleLines(zh: Bool, last n: Int = 40) -> [String] {
        chronicle.suffix(n).map { e in
            let who = e.nations.compactMap { polities[$0]?.name(zh: zh) }.joined(separator: " / ")
            return String(format: zh ? "第 %.1f 天 · %@ · %@ %@" : "day %.1f · %@ · %@ %@", e.t / MP.daySeconds, e.kind, who, e.note)
        }
    }

    /// Every hour: passes without a town are held by an enemy standing in them, and given back when it leaves.
    func holdPasses() {
        var held: [Int64: Int] = [:]
        for f in forces.values.sorted(by: { $0.id < $1.id }) where f.layer == .ground {
            guard let r = regions[f.region], r.city == nil, r.mountain >= cfg.passMountain, let owner = r.legal, owner != f.nation, atWar(owner, f.nation) else { continue }
            guard f.units.contains(where: { units[$0].map { cfg.war.occupiers.contains($0.kind) && !shifting($0) } ?? false }) else { continue }
            if forces.values.contains(where: { $0.region == f.region && $0.nation == owner && $0.layer == .ground && !$0.units.isEmpty }) { continue }
            if held[f.region] == nil { held[f.region] = f.nation }
        }
        for (k, n) in held where heldPasses[k] != n { record("pass_held", nations: [n, regions[k]?.legal ?? 0], region: k) }
        for (k, n) in heldPasses where held[k] == nil { record("pass_freed", nations: [regions[k]?.legal ?? 0, n], region: k) }
        heldPasses = held
    }
}

/// The battle of the twin ports, set up and played the same way every time for the same seed and choices.
public final class TwinPorts {
    public enum Drop: String { case eastPort, platform }
    public enum Giant: String { case guardEast, carryWest }

    public let c: Civ
    public let great: Int, small: Int
    public let east: CivCity, west: CivCity, capital: CivCity
    public let platform: Int64
    /// The open sea off the east port, where the carrier goes.
    public let offSea: Int64
    public var carrierForce = 0, transportForce = 0, skyForce = 0, shifter = 0, giant = 0
    public var frames: [Int] = []

    /// The battle on a world that already has the place and both nations (the forces are set up apart).
    public init(civ: Civ, great: Int, small: Int, capital: CivCity, west: CivCity, east: CivCity, platform: Int64, offSea: Int64) {
        self.c = civ; self.great = great; self.small = small; self.capital = capital; self.west = west; self.east = east
        self.platform = platform; self.offSea = offSea
    }

    /// The forces of both sides: the great power's carrier with fighters (at sea), transports with tanks and
    /// infantry and a sky carrier with frames (at home); the small nation's garrisons, its shifter at the west
    /// port and the giantess at the east port.
    public func setupForces(carrierAt sea: Int64, home: Int64) {
        carrierForce = force(great, at: sea, layer: .sea, ["carrier", "fighter", "fighter", "fighter", "fighter"])
        for u in c.forces[carrierForce]!.units where c.units[u]?.kind == "fighter" { c.units[u]!.air = .parked }
        transportForce = force(great, at: home, layer: .ground, Array(repeating: "armour", count: 30) + Array(repeating: "infantry", count: 30))
        skyForce = force(great, at: home, layer: .highAir, ["sky_carrier"])
        for _ in 0..<2 { let f = force(great, at: home, layer: .ground, ["frame"]); let id = c.forces[f]!.units[0]; frames.append(id); _ = c.board(id, carrier: skyForce) }
        _ = force(small, at: east.regionKey, layer: .ground, Array(repeating: "infantry", count: 6))
        _ = force(small, at: west.regionKey, layer: .ground, Array(repeating: "infantry", count: 3))
        let sf = force(small, at: west.regionKey, layer: .ground, ["shifter"])
        shifter = c.forces[sf]!.units[0]
        giant = c.raiseGiant(nation: small, at: east.regionKey, en: "Aurelia", zh: "奥蕾莉亚")
    }

    /// The place: a strait two regions wide between the great power's coast (west of x = 0) and the small
    /// nation's land (x = 6...12), with seas north and south; the small nation's west port at x = 6, its east
    /// port at x = 12 on the far sea, and a high platform (a pass) at x = 9 on the road between them.
    public convenience init(seed: Int) {
        let c = Civ(seed: seed)
        c.envoys = true
        func put(_ x: Int, _ y: Int, _ tweak: (inout CivRegion) -> Void = { _ in }) {
            var r = CivRegion(); r.rx = x; r.ry = y; r.land = 1; r.fertility = 0.7; r.forest = 0.3
            tweak(&r); c.regions[r.key] = r
        }
        for x in -4...16 { for y in -3...3 { put(x, y) { $0.land = 0; $0.water = 1; $0.deep = 0.8; $0.fertility = 0 } } }
        for x in -4...0 { for y in -2...2 { put(x, y) } }                       // the great power's coast
        for x in 6...12 { put(x, 0) }                                            // the small nation's strip of land
        put(9, 0) { $0.mountain = 0.45 }                                         // the high platform between the ports
        put(7, 1); put(11, -1)                                                  // a little hinterland
        let great = c.newPolity(origin: "first", near: nil), small = c.newPolity(origin: "first", near: nil)
        let capital = c.newCity(at: MP.chunkKey(-2, 0), nation: great, people: CivPeople(adults: 3000, children: 900, elders: 400), firstCount: true)
        capital.facilities = ["farm": 800, "house": 900, "well": 4, "shipyard": 2, "airfield": 1, "plant": 6, "fusion_plant": 4]      // power for the sky carrier
        capital.stock = ["grain": 1e6]; c.totals.add(\.found, "grain", 1e6)
        let yard = c.newCity(at: MP.chunkKey(0, 1), nation: great, people: CivPeople(adults: 400), firstCount: true)
        yard.facilities = ["shipyard": 1, "farm": 120, "house": 120, "well": 1]
        let west = c.newCity(at: MP.chunkKey(6, 0), nation: small, people: CivPeople(adults: 120, children: 40), firstCount: true)
        let east = c.newCity(at: MP.chunkKey(12, 0), nation: small, people: CivPeople(adults: 160, children: 50), firstCount: true)
        for k in [west, east] { k.facilities = ["farm": 60, "house": 50, "well": 2, "barracks": 1]; k.stock = ["grain": 2e4]; c.totals.add(\.found, "grain", 2e4) }
        c.polities[great]!.capital = capital.id; c.polities[small]!.capital = east.id
        c.polities[great]!.techs += ["deep_yard", "naval_eng", "carrier_ops", "frame", "lift"]
        c.polities[great]!.treasury = 5000; c.polities[small]!.treasury = 800
        c.polities[great]!.ai = false; c.polities[small]!.ai = false        // the demonstration gives the orders
        c.polities[great]!.fatigue = -10; c.polities[small]!.fatigue = -10
        c.cfg.claimRadius = 3                                                  // the platform is the small nation's, between its ports
        c.refreshTerritory()
        self.init(civ: c, great: great, small: small, capital: capital, west: west, east: east, platform: MP.chunkKey(9, 0), offSea: MP.chunkKey(13, 0))
        setupForces(carrierAt: MP.chunkKey(1, 0), home: MP.chunkKey(-2, 0))
    }

    @discardableResult func force(_ n: Int, at k: Int64, layer: CivLayer, _ kinds: [String]) -> Int {
        let f = CivForce(); f.id = c.nextForce; c.nextForce += 1; f.nation = n; f.region = k; f.layer = layer
        for kind in kinds {
            var u = CivUnit(); u.id = c.nextUnit; c.nextUnit += 1; u.kind = kind; u.nation = n; u.force = f.id; u.hp = u.def.hp
            u.fuel = u.def.fuelCap > 0 ? u.def.fuelCap : 1e6; u.energy = 1e6; u.ammo = 100
            for p in u.def.parts { u.parts[p] = 1 }
            c.units[u.id] = u; f.units.append(u.id)
            f.crew.add(CivPeople(adults: u.def.crew)); c.totals.newly += u.def.crew
        }
        f.food = ["ration": 1e5]; c.totals.add(\.found, "ration", 1e5)
        c.forces[f.id] = f
        return f.id
    }

    func hours(_ n: Int) { for _ in 0..<n { c.advance(to: c.time + MP.daySeconds / 24) } }

    /// The envoy goes and is answered. Returns true when the small nation refused.
    @discardableResult public func envoy() -> Bool {
        guard let id = c.sendEnvoy(great, to: small), let i = c.envoysOut.firstIndex(where: { $0.id == id }) else { return false }
        c.envoysOut[i].target = east.id; c.envoysOut[i].targetKind = "port"          // the battle is for the east port
        let e = c.envoysOut[i]
        c.advance(to: e.arrives + MP.daySeconds / 24)
        return c.envoysOut.first { $0.id == id }?.state == .refused
    }

    /// The opening of the war: the carrier off the east port, fighters up, tanks shipped to the east port; the
    /// shifter runs east as a vehicle; the giantess guards the east port or carries its people west.
    public func opening(giant choice: Giant) {
        openingSail(); hours(6)
        openingStrikeAndLand(); hours(1)
        openingDefence(giant: choice); hours(12)
    }

    /// The carrier sails to the open sea off the east port.
    public func openingSail() { _ = c.send(carrierForce, to: offSea) }

    /// A fighter flies from the carrier to the east port; the tanks are put ashore there (the quay decides how
    /// many land); the shifter changes into its vehicle form.
    public func openingStrikeAndLand() {
        if let jet = c.forces[carrierForce]?.units.first(where: { c.units[$0]?.kind == "fighter" && c.units[$0]?.air == .parked }),
           let carrier = c.forces[carrierForce]!.units.first(where: { c.units[$0]?.kind == "carrier" }) {
            c.takeControl(carrier, nation: great)
            if c.switchToAircraft() == jet { c.pilotGo(to: east.regionKey) }
            c.releaseControl()
        }
        c.forces[transportForce]!.region = east.regionKey; c.forces[transportForce]!.path = []
        c.record("landing", nations: [great, small], region: east.regionKey, ids: [transportForce])
        c.shift(shifter, to: "vehicle")
    }

    /// The shifter runs east over the platform; the giantess guards the east port or carries its people west.
    public func openingDefence(giant choice: Giant) {
        if let f = c.units[shifter]?.force { _ = c.send(f, to: east.regionKey) }
        switch choice {
        case .guardEast: c.giantGuard(giant)
        case .carryWest: c.giantRescue(giant, people: 60); c.giantGo(giant, to: west.regionKey)
        }
        c.record("giantess_" + choice.rawValue, nations: [small], region: east.regionKey, ids: [giant])
    }

    /// The sky carrier comes and drops its frames on the east port or on the platform.
    public func skyDrop(_ to: Drop) {
        let k = to == .eastPort ? east.regionKey : platform
        c.forces[skyForce]!.region = k
        for f in frames { c.drop(f) }
        c.record("sky_drop_" + to.rawValue, nations: [great, small], region: k, ids: frames)
    }

    /// Play on until the war for the east port is settled (or `days` pass).
    public func finish(days: Int = 20) {
        for _ in 0..<(days * 24) {
            if !c.targetWars.isEmpty && c.targetWars.allSatisfy({ $0.ended != nil }) { break }
            hours(1)
        }
        recordOutcome()
    }

    /// Once the war for the east port is over: the small nation kept its way to the sea, or lost the port.
    public func recordOutcome() {
        guard let w = c.targetWars.last(where: { $0.attacker == great && $0.defender == small }), w.stage == .truce else { return }
        if east.nation == small { c.record("kept_the_sea", nations: [small, great], region: east.regionKey, note: "the small nation keeps its way to the sea") }
        else { c.record("port_lost", nations: [small, great], region: east.regionKey, note: "the east port fell") }
    }
}
