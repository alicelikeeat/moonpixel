import XCTest
@testable import MoonPixelCore

/// A stretch of the world for the transport tests: grass, a belt of forest, a deep river, two cities.
///
///   x   0 ......... 36 | 40 forest 55 | ... 74 river 81 ... | 90 ......... 169
///   West city (district A) around x 15        East city (district B) around x 130
///   y 0 ... 139 (the river and the forest run the whole height, so there is no way round)
///
/// Everything is painted on the world's own layers at `o`, far from the villages.
struct TransportScene {
    let s: Society
    let o: TilePos
    var a: District!
    var b: District!

    static let w = 170, h = 140
    static let forest = 40..<56, river = 74..<82

    init(seed: Int = 21) {
        s = makeSociety(seed, villages: 2, per: 10)
        o = TilePos(4000, 4000)
        let grass = s.content.tid("grass"), deep = s.content.tid("deep_water"), oak = s.content.tid("tree_oak")
        for y in 0..<TransportScene.h { for x in 0..<TransportScene.w {
            let t = TilePos(o.x + x, o.y + y)
            s.world.setTile(0, t.x, t.y, TransportScene.river.contains(x) ? deep : grass)
            for l in 1...3 { s.world.setTile(l, t.x, t.y, 0) }
            if TransportScene.forest.contains(x) { s.world.setTile(2, t.x, t.y, oak) }
        } }
        // the river runs on far beyond the scene, so there is no way round it on land
        for y in -420..<0 { for x in TransportScene.river { s.world.setTile(0, o.x + x, o.y + y, deep); for l in 1...3 { s.world.setTile(l, o.x + x, o.y + y, 0) } } }
        for y in TransportScene.h..<(TransportScene.h + 420) { for x in TransportScene.river { s.world.setTile(0, o.x + x, o.y + y, deep); for l in 1...3 { s.world.setTile(l, o.x + x, o.y + y, 0) } } }
        s.realm.player.body = Body(at: t(15, 70).center, z: 0, depth: 0)
        s.realm.player.god = true
    }

    func t(_ x: Int, _ y: Int) -> TilePos { TilePos(o.x + x, o.y + y) }

    /// Lay a way at once (paid by the payer: the materials are given to it first).
    @discardableResult func lay(_ k: WayKind, _ from: TilePos, _ to: TilePos, payer: Payer = .pack, bridge: BridgeKind? = nil) -> WayPlan {
        let p = s.planWay(k, from: from, to: to, bridge: bridge)
        XCTAssertTrue(p.ok, "plan \(k) \(from)->\(to): \(p.reason)")
        give(p.cost, payer)
        let id = s.startWay(p, payer: payer)
        XCTAssertNotNil(id)
        if let id = id { s.finishSite(id) }
        return p
    }

    func give(_ goods: [String: Double], _ payer: Payer) {
        guard let h = s.holding(payer) else { return }
        for (k, v) in goods { h.change(k, v) }
    }

    /// The two cities: a district each, with a street along y 60 inside each, fuel and parts in store.
    mutating func cities(withLinks: Bool = false) {
        a = s.foundDistrict(name: "West", at: t(15, 60), nation: 1, money: 100_000, store: ["fuel": 5000, "parts": 500, "stone": 2000, "planks": 800, "iron": 600, "food": 4000, "moonsteel": 100])
        b = s.foundDistrict(name: "East", at: t(130, 60), nation: 1, money: 100_000, store: ["fuel": 5000, "parts": 500, "stone": 2000, "planks": 800, "iron": 600, "food": 100, "moonsteel": 100])
        a.autoBuild = false; b.autoBuild = false
        lay(.street, t(2, 60), t(36, 60), payer: .district(a.id))
        lay(.street, t(90, 60), t(165, 60), payer: .district(b.id))
        if withLinks { lay(.street, t(36, 60), t(90, 60), payer: .district(a.id)) }
    }

    /// Step the transport world (lifts, vehicles, lines, commuters) for `seconds` of game time.
    func run(_ seconds: Double, dt: Double = 1.0 / 30, until: (() -> Bool)? = nil) {
        var t = 0.0
        while t < seconds {
            if s.realm.liftBox != nil { s.liftsStep(dt) }
            s.transportTick(dt)
            s.world.time += dt
            t += dt
            if until?() == true { return }
        }
    }
}

extension TransportScene {
    static func hsrScene() -> (TransportScene, Stop, Stop) {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        sc.lay(.hsr, sc.t(4, 66), sc.t(160, 66), payer: .district(sc.a.id))
        for (k, x) in [(0, 6), (1, 150)] { _ = k; sc.lay(.platform, sc.t(x, 67), sc.t(x + 6, 67), payer: .district(sc.a.id)) }
        let a = s.addStop(.station, at: sc.t(8, 66), name: "West HSR", nation: 1, district: sc.a.id)!
        let b = s.addStop(.station, at: sc.t(152, 66), name: "East HSR", nation: 1, district: sc.b.id)!
        // the grid powers the trains
        let p = CityKind.byKey["power"]!
        var pb = CityBuilding(); pb.id = 999; pb.kind = "power"; pb.x = sc.t(20, 80).x; pb.y = sc.t(20, 80).y; pb.w = p.w; pb.d = p.d; pb.state = .open
        pb.floors = [{ var f = CityFloor(); f.jobs = p.jobsPerFloor; return f }()]
        sc.a.buildings.append(pb); sc.a.staffing[999] = 1
        // people in the west city to staff it from day to day
        let flats = s.placeCityBuilding(sc.a, kind: "flats", at: sc.t(50, 90))!           // beside the (life-sized) power station
        let fi = sc.a.buildings.firstIndex { $0.id == flats }!
        for k in sc.a.buildings[fi].floors.indices { sc.a.buildings[fi].floors[k].residents = 12; sc.a.buildings[fi].floors[k].food = 200 }
        sc.a.ledger.imported = sc.a.population
        s.refreshServices(sc.a)
        XCTAssertGreaterThan(sc.a.spareGrid, 0)
        return (sc, a, b)
    }

    static func airScene() -> (TransportScene, Stop, Stop) {
        var sc = TransportScene()
        sc.cities()
        let s = sc.s
        for y in 119...121 {
            sc.lay(.runway, sc.t(2, y), sc.t(44, y), payer: .district(sc.a.id))
            sc.lay(.runway, sc.t(112, y), sc.t(168, y), payer: .district(sc.b.id))
        }
        sc.lay(.apron, sc.t(2, 124), sc.t(10, 124), payer: .district(sc.a.id))
        sc.lay(.taxiway, sc.t(2, 122), sc.t(2, 124), payer: .district(sc.a.id))
        let a = s.addStop(.airport, at: sc.t(2, 120), name: "West Field", nation: 1, district: sc.a.id)!
        let b = s.addStop(.airport, at: sc.t(112, 120), name: "East Field", nation: 1, district: sc.b.id)!
        return (sc, a, b)
    }

    static func portScene() -> (TransportScene, Stop, Stop) {
        var sc = TransportScene()
        sc.cities(withLinks: true)
        let s = sc.s
        sc.lay(.quay, sc.t(73, 10), sc.t(73, 16), payer: .district(sc.a.id))
        sc.lay(.quay, sc.t(73, 110), sc.t(73, 116), payer: .district(sc.a.id))
        let a = s.addStop(.port, at: sc.t(74, 13), name: "North Quay", nation: 1, district: sc.a.id)!
        let b = s.addStop(.port, at: sc.t(74, 113), name: "South Quay", nation: 1, district: sc.b.id)!
        return (sc, a, b)
    }
}

extension TransportScene {
    /// East city: a twelve-storey tower with residents, a power station and waterworks.
    static func eastTower(_ sc: TransportScene, residentsPerFloor: Int = 10) -> Int {
        let s = sc.s, b = sc.b!
        b.store["food"] = 0
        XCTAssertNotNil(s.placeCityBuilding(b, kind: "power", at: sc.t(120, 40)))
        XCTAssertNotNil(s.placeCityBuilding(b, kind: "waterworks", at: sc.t(130, 40)))
        XCTAssertNotNil(s.placeCityBuilding(b, kind: "sewage", at: sc.t(140, 40)))
        XCTAssertNotNil(s.placeCityBuilding(b, kind: "depot", at: sc.t(150, 40)))
        let id = s.placeCityBuilding(b, kind: "tower", at: sc.t(104, 49))!
        let bi = b.buildings.firstIndex { $0.id == id }!
        XCTAssertNotNil(b.buildings[bi].lift, "a tall block of flats gets its outside elevator")
        for k in b.buildings[bi].floors.indices { b.buildings[bi].floors[k].residents = residentsPerFloor }
        b.ledger.imported = b.population
        // a first day to staff the services
        b.staffing = Dictionary(uniqueKeysWithValues: b.buildings.map { ($0.id, 1.0) })
        s.refreshServices(b)
        return id
    }

    /// Farm yard -> lorry -> rail yard -> freight train -> rail yard -> lorry -> city yard.
    static func freightNetwork(_ sc: inout TransportScene) -> (farm: Stop, city: Stop, train: Vehicle) {
        sc.cities(withLinks: true)
        let s = sc.s
        sc.lay(.rail, sc.t(4, 66), sc.t(160, 66), payer: .district(sc.a.id))
        let farmYard = s.addStop(.yard, at: sc.t(30, 60), name: "West farm yard", nation: 1, district: sc.a.id)!
        let railW = s.addStop(.yard, at: sc.t(12, 60), name: "West rail yard", nation: 1)!
        let stW = s.addStop(.station, at: sc.t(10, 66), name: "West goods", nation: 1)!
        let stE = s.addStop(.station, at: sc.t(150, 66), name: "East goods", nation: 1)!
        let railE = s.addStop(.yard, at: sc.t(148, 60), name: "East rail yard", nation: 1)!
        let cityYard = s.addStop(.yard, at: sc.t(100, 60), name: "East city yard", nation: 1, district: sc.b.id)!
        let l1 = s.addLine(.truck, stops: [farmYard.id, railW.id], name: "West haul", headway: 60, nation: 1, payer: .district(sc.a.id), freight: true)!
        let l2 = s.addLine(.train, stops: [stW.id, stE.id], name: "Goods train", headway: 120, nation: 1, payer: .district(sc.a.id), freight: true)!
        let l3 = s.addLine(.truck, stops: [railE.id, cityYard.id], name: "East haul", headway: 60, nation: 1, payer: .district(sc.b.id), freight: true)!
        s.assign(s.buildVehicle(.truck, at: sc.t(30, 60), heading: Double.pi, payer: .district(sc.a.id), nation: 1)!, to: l1)
        let train = s.buildVehicle(.train, at: sc.t(10, 66), heading: 0, payer: .district(sc.a.id), nation: 1)!
        s.assign(train, to: l2)
        s.assign(s.buildVehicle(.truck, at: sc.t(148, 60), heading: Double.pi, payer: .district(sc.b.id), nation: 1)!, to: l3)
        return (farmYard, cityYard, train)
    }
}
