import Foundation

// Modern transport in the open world: streets, highways, railways, runways, quays and the bridges and
// tunnels that carry them. Everything here is in the world itself: a street is a row of street tiles,
// a bridge is a deck over real water (or over a real road), a tunnel goes under real rock. Vehicles,
// lines and freight (Vehicle.swift, Lines.swift) move on what is built here and nowhere else.
//
// Building is planned first (a preview: the tiles, the trees that will be felled, the wood they give,
// the bridges and tunnels needed and what it all costs), paid for once, and then built tile by tile on
// a work site: trees are felled (their wood goes to whoever pays), the ground is laid, a bridge span is
// raised. A tile on a road, railway, runway or a building's entrance is kept clear for good: nothing is
// planted there again.
//
// Levels: 0 is the ground (a street, a level crossing, the water under a bridge), 1 a bridge deck,
// -1 a tunnel. A bridge deck connects only along its own line and to the ground at both ends, so a
// highway over a street and a ship under a bridge never meet the traffic on the other level.

public enum TravelMode: String, Codable, CaseIterable { case road, rail, air, water, foot }

public enum WayKind: String, Codable, CaseIterable {
    case street, highway, rail, hsr, runway, taxiway, apron, quay, parking, platform, foot
    public var tileKey: String {
        switch self {
        case .street: return "road_asphalt"
        case .highway: return "highway"
        case .rail: return "rail"
        case .hsr: return "rail_hsr"
        case .runway: return "runway"
        case .taxiway: return "taxiway"
        case .apron: return "apron"
        case .quay: return "quay"
        case .parking: return "parking"
        case .platform: return "platform"
        case .foot: return "path"
        }
    }
    public var mode: TravelMode {
        switch self {
        case .street, .highway, .parking: return .road
        case .rail, .hsr: return .rail
        case .runway, .taxiway, .apron: return .air
        case .quay, .platform, .foot: return .foot
        }
    }
    /// Speed limit, tiles a second (a tile is about 2 m in the 3D view, so 14 tiles/s is about 100 km/h).
    public var limit: Double {
        switch self {
        case .street: return 7
        case .highway: return 16
        case .rail: return 16
        case .hsr: return 40
        case .runway: return 45
        case .taxiway: return 6
        case .apron, .parking: return 3
        case .quay, .platform, .foot: return 2
        }
    }
    /// Vehicles a tile holds before traffic slows (congestion).
    public var capacity: Double { self == .highway ? 3 : (self == .street ? 1.2 : 1) }
    /// What one tile costs to build (bridges and tunnels have their own costs on top).
    public var cost: [String: Double] {
        switch self {
        case .street: return ["stone": 2]
        case .highway: return ["stone": 4, "parts": 0.5]
        case .rail: return ["stone": 1, "planks": 1, "iron": 1]
        case .hsr: return ["stone": 2, "iron": 2, "parts": 1]
        case .runway: return ["stone": 6]
        case .taxiway, .apron, .parking: return ["stone": 3]
        case .quay: return ["stone": 4, "planks": 2]
        case .platform: return ["stone": 3, "planks": 1]
        case .foot: return ["stone": 0.5]
        }
    }
    public var upkeep: Double { self == .hsr ? 0.08 : (self == .highway ? 0.05 : 0.02) }    // parts per tile per day
    public func name(zh: Bool) -> String {
        let n: [WayKind: (String, String)] = [.street: ("Street", "街道"), .highway: ("Highway", "高速公路"), .rail: ("Railway", "铁路"), .hsr: ("High-speed rail", "高铁"),
            .runway: ("Runway", "跑道"), .taxiway: ("Taxiway", "滑行道"), .apron: ("Stand", "停机位"), .quay: ("Quay", "码头"), .parking: ("Car park", "停车场"),
            .platform: ("Platform", "站台"), .foot: ("Footpath", "人行道")]
        return zh ? n[self]!.1 : n[self]!.0
    }
}

public enum BridgeKind: String, Codable, CaseIterable {
    case foot, road, rail, viaduct, opening
    public func name(zh: Bool) -> String {
        let n: [BridgeKind: (String, String)] = [.foot: ("Footbridge", "人行桥"), .road: ("Road bridge", "公路桥"), .rail: ("Rail bridge", "铁路桥"),
            .viaduct: ("Viaduct", "高架桥"), .opening: ("Opening bridge", "开启桥")]
        return zh ? n[self]!.1 : n[self]!.0
    }
}

/// An opening bridge's cycle: traffic is stopped and the deck checked empty before it rises.
public enum SpanState: String, Codable { case closed, stopping, raising, open, lowering }

public struct Bridge: Codable, Equatable {
    public var id = 0
    public var kind = BridgeKind.road
    public var deck = WayKind.street
    /// The span, in order from one end to the other (the abutments are the ground tiles just beyond).
    public var cells: [TilePos] = []
    /// Height of the deck above the water or ground below, tiles; clearance is what a ship or a lorry has.
    public var deckZ = 3.0
    public var clearance: Double { kind == .opening && state == .open ? 1e9 : deckZ - 0.5 }
    public var state = SpanState.closed
    public var stateT = 0.0
    public var nation = 0
    public var hp = 1.0
    /// The span's direction (one tile step along it), so a one-tile span still has ends in line with it.
    public var ax = 1, ay = 0
    public init() {}
    /// The ground tiles just beyond an end of the span (where a ramp starts): one for each end, both for a one-tile span.
    public func ramps(_ end: TilePos) -> [TilePos] {
        var out: [TilePos] = []
        if end == cells.first { out.append(TilePos(end.x - ax, end.y - ay)) }
        if end == cells.last { out.append(TilePos(end.x + ax, end.y + ay)) }
        return out
    }
    public var allRamps: [TilePos] { cells.isEmpty ? [] : ramps(cells.first!) + (cells.count > 1 ? ramps(cells.last!) : []) }
    /// Traffic may be on it (an opening bridge only when lowered; while traffic is being stopped those on it may drive off).
    public var carries: Bool { hp > 0 && (kind != .opening || state == .closed || state == .stopping) }
}

public struct Tunnel: Codable, Equatable {
    public var id = 0
    public var deck = WayKind.street
    public var cells: [TilePos] = []
    public var nation = 0
    public init() {}
}

/// A lock on a waterway: a ship waits for the chamber to fill or empty before passing.
public struct WaterLock: Codable, Equatable {
    public var id = 0
    public var cell = TilePos(0, 0)
    public var cycle = 40.0                // seconds to fill or empty
    public var busyUntil = 0.0
    public var passed = 0
    public init() {}
}

/// A tile being built: felled, then laid. One work site is one paid plan.
public struct WorkCell: Codable, Equatable {
    public var t: TilePos
    public var kind: WayKind
    public var bridge: Int?                // span of this bridge (laid as a deck)
    public var tunnel: Int?
    public var done = false
}

public struct WorkSite: Codable, Equatable {
    public var id = 0
    public var cells: [WorkCell] = []
    public var rate = 40.0                 // tiles an hour
    public var progress = 0.0
    /// Where the wood and stone from clearing go (a district's store, a town's, or the traveller's pack).
    public var payer = Payer.pack
    public var wood = 0.0, stone = 0.0     // gained so far
    public var owner = 0                   // nation
    public var by: String = "player"       // "player" or "district:<id>"
    public var finished: Double?
    public init() {}
}

public enum Payer: Codable, Equatable { case pack, town(Int), district(Int) }

/// One goods movement, for the books: every hand-over of goods writes one of these.
public struct Transfer: Codable, Equatable {
    public var t = 0.0
    public var key = "", amount = 0.0
    public var from = "", to = ""
    public var note = ""
}

/// The preview of a way: what will be built, felled, bridged and paid.
public struct WayPlan: Equatable {
    public var kind = WayKind.street
    public var cells: [TilePos] = []
    public var fell: [TilePos] = []        // trees, bushes, rocks taken away
    public var wood = 0.0, stone = 0.0     // what clearing gives
    public var spans: [[TilePos]] = []     // water (or other ways) crossed by a bridge
    public var tunnels: [[TilePos]] = []
    public var cost: [String: Double] = [:]
    public var ok = false
    public var reason = ""
    public var bridgeKind = BridgeKind.road
    public init() {}
}

public final class TransportState: Codable {
    public var nextID = 1
    public var bridges: [Bridge] = []
    public var tunnels: [Tunnel] = []
    public var locks: [WaterLock] = []
    /// Tiles kept clear (ways, entrances, runway margins): nothing is planted there.
    var corridorList: [Int64] = []
    /// Rail tiles a street crosses on the level.
    public var crossings: Set<Int64> = []
    public var sites: [WorkSite] = []
    public var vehicles: [Vehicle] = []
    public var stops: [Stop] = []
    public var lines: [Line] = []
    public var shipments: [Shipment] = []
    public var districts: [District] = []
    public var commuters: [Commuter] = []
    /// Imported metro cities (their seeds): a city is brought into the world once.
    public var importedMetros: [Int] = []
    public var ledger: [Transfer] = []
    public var revision = 0
    public var day = -1
    public var stats = TransportStats()
    // transient
    var corridor: Set<Int64> = []
    var bridgeAt: [Int64: Int] = [:]       // tile -> bridge id
    var tunnelAt: [Int64: Int] = [:]
    var indexed = -1

    enum CodingKeys: String, CodingKey { case nextID, bridges, tunnels, locks, corridorList, crossings, sites, vehicles, stops, lines, shipments, districts, commuters, importedMetros, ledger, revision, day, stats }
    public init() {}
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(nextID, forKey: .nextID); try c.encode(bridges, forKey: .bridges); try c.encode(tunnels, forKey: .tunnels); try c.encode(locks, forKey: .locks)
        try c.encode(corridor.sorted(), forKey: .corridorList); try c.encode(crossings.sorted(), forKey: .crossings); try c.encode(sites, forKey: .sites); try c.encode(vehicles, forKey: .vehicles)
        try c.encode(stops, forKey: .stops); try c.encode(lines, forKey: .lines); try c.encode(shipments, forKey: .shipments); try c.encode(districts, forKey: .districts)
        try c.encode(commuters, forKey: .commuters); try c.encode(importedMetros, forKey: .importedMetros); try c.encode(ledger, forKey: .ledger)
        try c.encode(revision, forKey: .revision); try c.encode(day, forKey: .day); try c.encode(stats, forKey: .stats)
    }
    public required init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        nextID = try c.decode(Int.self, forKey: .nextID); bridges = try c.decode([Bridge].self, forKey: .bridges); tunnels = try c.decode([Tunnel].self, forKey: .tunnels)
        locks = try c.decode([WaterLock].self, forKey: .locks); corridorList = try c.decode([Int64].self, forKey: .corridorList); crossings = Set(try c.decodeIfPresent([Int64].self, forKey: .crossings) ?? []); sites = try c.decode([WorkSite].self, forKey: .sites)
        vehicles = try c.decode([Vehicle].self, forKey: .vehicles); stops = try c.decode([Stop].self, forKey: .stops); lines = try c.decode([Line].self, forKey: .lines)
        shipments = try c.decode([Shipment].self, forKey: .shipments); districts = try c.decode([District].self, forKey: .districts)
        commuters = try c.decode([Commuter].self, forKey: .commuters); importedMetros = try c.decode([Int].self, forKey: .importedMetros)
        ledger = try c.decode([Transfer].self, forKey: .ledger); revision = try c.decode(Int.self, forKey: .revision); day = try c.decode(Int.self, forKey: .day)
        stats = try c.decode(TransportStats.self, forKey: .stats)
        corridor = Set(corridorList)
    }
    public func take() -> Int { defer { nextID += 1 }; return nextID }
    public func bridge(_ id: Int) -> Bridge? { bridges.first { $0.id == id } }
    public func vehicle(_ id: Int) -> Vehicle? { vehicles.first { $0.id == id } }
    public func stop(_ id: Int) -> Stop? { stops.first { $0.id == id } }
    public func line(_ id: Int) -> Line? { lines.first { $0.id == id } }
    public func district(_ id: Int) -> District? { districts.first { $0.id == id } }
    public func commuter(_ id: Int) -> Commuter? { commuters.first { $0.id == id } }
    func reindex() {
        bridgeAt = [:]; tunnelAt = [:]
        for b in bridges { for t in b.cells { bridgeAt[MP.chunkKey(t.x, t.y)] = b.id } }
        for u in tunnels { for t in u.cells { tunnelAt[MP.chunkKey(t.x, t.y)] = u.id } }
        indexed = revision
    }
}

public struct TransportStats: Codable, Equatable {
    public var built = 0, felled = 0, woodFromClearing = 0.0, bridges = 0, tunnels = 0
    public var trips = 0, tripsRefused = 0, delivered = 0.0, crashes = 0, groundings = 0
    public var fuelBurnt = 0.0, powerUsed = 0.0, fares = 0.0, upkeep = 0.0
    public init() {}
}

/// A node of the network: a tile and a level (0 ground, 1 deck, -1 tunnel).
public struct NetNode: Hashable, Codable { public var x: Int, y: Int, l: Int
    public init(_ x: Int, _ y: Int, _ l: Int) { self.x = x; self.y = y; self.l = l }
    public var tile: TilePos { TilePos(x, y) }
    var key: Int64 { (Int64(y) << 34) ^ (Int64(x) << 2) ^ Int64(l + 1) }
}

/// What a vehicle needs of the way under it.
public struct Profile: Equatable {
    public var mode = TravelMode.road
    public var draft = 0.0                 // ships: water depth needed
    public var airDraft = 0.0              // ships and lorries: height needed under a bridge
    public var hsrOnly = false             // a high-speed train runs on high-speed track only
    public init(mode: TravelMode, draft: Double = 0, airDraft: Double = 0, hsrOnly: Bool = false) { self.mode = mode; self.draft = draft; self.airDraft = airDraft; self.hsrOnly = hsrOnly }
}

extension Realm {
    public var transport: TransportState { mutating get { if transportBox == nil { transportBox = TransportState() }; return transportBox! } set { transportBox = newValue } }
}

extension Society {
    public var net: TransportState {
        let t = realm.transport
        if t.indexed != t.revision { t.reindex() }
        return t
    }

    // MARK: reading the network

    public func wayKind(at t: TilePos) -> WayKind? {
        let id = world.tile(1, t.x, t.y)
        guard id != 0 else { return nil }
        return Society.wayByTile[content.tile(id)?.key ?? ""]
    }
    static let wayByTile: [String: WayKind] = {
        var m: [String: WayKind] = [:]
        for k in WayKind.allCases { m[k.tileKey] = k }
        m["cobble_road"] = .street
        return m
    }()

    /// Water depth at a tile (tiles), 0 on land.
    public func waterDepth(_ t: TilePos) -> Double {
        let g = world.tile(0, t.x, t.y)
        switch content.tile(g)?.key ?? "" {
        case "deep_water": return 8
        case "water": return 3
        case "shallow_water": return 0.8
        default: return 0
        }
    }

    /// May a tree be planted here? Never on a way, a bridge, a kept-clear corridor (a road, a railway, a
    /// runway and its margins, a building's door), or anything built.
    public func canPlant(_ t: TilePos) -> Bool {
        world.isLand(t.x, t.y) && world.tile(2, t.x, t.y) == 0 && world.tile(1, t.x, t.y) == 0 && !isCorridor(t) && (realm.transportBox == nil || bridge(at: t) == nil)
    }

    public func isCorridor(_ t: TilePos) -> Bool { realm.transportBox?.corridor.contains(MP.chunkKey(t.x, t.y)) ?? false }
    func keepClear(_ t: TilePos) { realm.transport.corridor.insert(MP.chunkKey(t.x, t.y)) }

    public func bridge(at t: TilePos) -> Bridge? { net.bridgeAt[MP.chunkKey(t.x, t.y)].flatMap { net.bridge($0) } }
    public func tunnel(at t: TilePos) -> Tunnel? { net.tunnelAt[MP.chunkKey(t.x, t.y)].flatMap { id in net.tunnels.first { $0.id == id } } }

    /// Can a vehicle of this profile be on this node? (`why` says what stops it, for messages and AI.)
    public func passable(_ n: NetNode, _ p: Profile) -> Bool {
        let t = n.tile
        switch n.l {
        case 1:
            guard let b = bridge(at: t), b.hp > 0 else { return false }
            if b.kind == .opening && b.state != .closed { return false }
            return deckServes(b.deck, p)
        case -1:
            guard let u = tunnel(at: t) else { return false }
            return deckServes(u.deck, p)
        default:
            if p.mode == .water {
                guard waterDepth(t) >= max(0.5, p.draft) else { return false }
                if let b = bridge(at: t) { return b.clearance >= p.airDraft }
                let s = world.tile(1, t.x, t.y)
                return s == 0 || content.bridge[Int(s)]
            }
            // a bridge cell is a deck, not a road on the water
            if bridge(at: t) != nil && waterDepth(t) > 0 { return false }
            guard let k = wayKind(at: t) else { return p.mode == .foot && world.isLand(t.x, t.y) && !world.blocked(t.x, t.y) }
            if p.mode == .road && k.mode == .rail && realm.transport.crossings.contains(MP.chunkKey(t.x, t.y)) { return true }
            if world.tile(2, t.x, t.y) != 0 && content.solid[Int(world.tile(2, t.x, t.y))] { return false }    // something fell on it
            if let b = bridge(at: t), p.airDraft > b.clearance, b.kind == .viaduct { return false }             // too tall to pass under
            return deckServes(k, p)
        }
    }

    func deckServes(_ k: WayKind, _ p: Profile) -> Bool {
        switch p.mode {
        case .road: return k.mode == .road || k == .apron
        case .rail: return p.hsrOnly ? k == .hsr : (k == .rail || k == .hsr)
        case .air: return k.mode == .air
        case .foot: return true
        case .water: return false
        }
    }

    /// Neighbours of a node for this mode (4 ways on land and rails, 8 on water).
    func neighbours(_ n: NetNode, _ p: Profile) -> [NetNode] {
        var out: [NetNode] = []
        let dirs: [(Int, Int)] = p.mode == .water ? [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] : [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let here = n.tile
        let hb = n.l == 1 ? bridge(at: here) : nil
        for (dx, dy) in dirs {
            let t = TilePos(here.x + dx, here.y + dy)
            if p.mode == .water && dx != 0 && dy != 0 {
                // no cutting a corner of land
                if !passable(NetNode(here.x + dx, here.y, 0), p) || !passable(NetNode(here.x, here.y + dy, 0), p) { continue }
            }
            if p.mode == .water { let m = NetNode(t.x, t.y, 0); if passable(m, p) { out.append(m) }; continue }
            switch n.l {
            case 1:
                // along the deck, or down onto the ground at either end
                if let b = hb, b.cells.contains(t) { if passable(NetNode(t.x, t.y, 1), p) { out.append(NetNode(t.x, t.y, 1)) }; continue }
                if let b = hb, b.ramps(here).contains(t) {
                    let g = NetNode(t.x, t.y, 0); if passable(g, p) { out.append(g) }
                }
            case -1:
                if let u = tunnel(at: here), u.cells.contains(t) { out.append(NetNode(t.x, t.y, -1)); continue }
                if let u = tunnel(at: here), let i = u.cells.firstIndex(of: here), i == 0 || i == u.cells.count - 1 {
                    let g = NetNode(t.x, t.y, 0); if passable(g, p) { out.append(g) }
                }
            default:
                let g = NetNode(t.x, t.y, 0)
                if passable(g, p) && !rampSplits(here, t) { out.append(g) }
                // up onto a deck at its end, or into a tunnel mouth
                if let b = bridge(at: t), b.ramps(t).contains(here) {
                    let d = NetNode(t.x, t.y, 1); if passable(d, p) { out.append(d) }
                }
                if let u = tunnel(at: t), (u.cells.first == t || u.cells.last == t) {
                    let d = NetNode(t.x, t.y, -1); if passable(d, p) { out.append(d) }
                }
            }
        }
        return out
    }

    /// A ramp up to a viaduct and the way passing under it are on different levels: no step between them at ground level.
    func rampSplits(_ a: TilePos, _ b: TilePos) -> Bool {
        if let v = bridge(at: b), v.kind == .viaduct, v.ramps(b).contains(a) { return true }
        if let v = bridge(at: a), v.kind == .viaduct, v.ramps(a).contains(b) { return true }
        return false
    }

    /// Seconds to cross a node at its limit (water: a ship's own speed is used later; this is relative).
    func crossTime(_ n: NetNode, _ p: Profile) -> Double {
        if p.mode == .water { return 1 }
        if n.l == 1, let b = bridge(at: n.tile) { return 1 / b.deck.limit }
        if n.l == -1, let u = tunnel(at: n.tile) { return 1 / u.deck.limit }
        let k = wayKind(at: n.tile)
        let lim = k?.limit ?? 1.5
        return 1 / lim
    }

    /// The quickest way between two nodes for this profile (A*), or nil when there is none. Never through
    /// water a road does not cross, a closed opening bridge, a felled tree on the way, or a fallen span.
    public func route(from a: NetNode, to b: NetNode, _ p: Profile, limit: Int = 400_000) -> [NetNode]? {
        guard passable(a, p) || a == b else { return nil }
        guard passable(b, p) else { return nil }
        var best: [Int64: Double] = [a.key: 0]
        var came: [Int64: NetNode] = [:]
        var heap = MinHeap()
        let maxSpeed: Double = p.mode == .water ? 1 : (p.mode == .rail ? 40 : (p.mode == .air ? 45 : 16))
        func h(_ n: NetNode) -> Double { Double(abs(n.x - b.x) + abs(n.y - b.y)) / maxSpeed * (p.mode == .water ? 0.75 : 1) }
        heap.push(h(a), a)
        var seen = 0
        while let (_, n) = heap.pop() {
            if n == b {
                var out = [n]; var k = n
                while let c = came[k.key] { out.append(c); k = c }
                return out.reversed()
            }
            seen += 1
            if seen > limit { return nil }
            let g = best[n.key] ?? .infinity
            for m in neighbours(n, p) {
                let diag = (m.x != n.x && m.y != n.y) ? 1.4142 : 1
                let ng = g + crossTime(m, p) * diag
                if ng < (best[m.key] ?? .infinity) - 1e-12 {
                    best[m.key] = ng; came[m.key] = n
                    heap.push(ng + h(m), m)
                }
            }
        }
        return nil
    }

    // MARK: planning a way

    /// The cheapest line to build a way of this kind from `a` to `b`: along existing ways where they
    /// serve, through clear land, felling trees, bridging water and tunnelling rock as needed. Buildings,
    /// walls and anything else someone built are never crossed (bridges go over ways, never through houses).
    public func planWay(_ kind: WayKind, from a: TilePos, to b: TilePos, bridge bk: BridgeKind? = nil, allowBridges: Bool = true, allowTunnels: Bool = true, limit: Int = 200_000) -> WayPlan {
        var plan = WayPlan(); plan.kind = kind
        plan.bridgeKind = bk ?? (kind.mode == .rail ? .rail : (kind == .foot ? .foot : .road))
        func key(_ t: TilePos) -> Int64 { MP.chunkKey(t.x, t.y) }
        // cost of making this tile part of the way (nil: cannot)
        func stepCost(_ t: TilePos) -> Double? {
            if waterDepth(t) > 0 {
                guard allowBridges, kind != .runway, kind != .taxiway, kind != .apron else { return nil }
                if bridge(at: t) != nil { return nil }
                return waterDepth(t) >= 8 ? 12 : 7
            }
            let s = world.tile(1, t.x, t.y)
            if s != 0 && content.solid[Int(s)] { return allowTunnels && kind.mode != .air ? 9 : nil }        // a cliff: a tunnel
            let o = world.tile(2, t.x, t.y)
            if o != 0 {
                guard let def = content.tile(o) else { return nil }
                if def.built { return nil }                                       // a wall, a house, a machine: never
                if !def.natural && def.solid { return nil }
            }
            if content.tile(world.tile(0, t.x, t.y))?.built == true && wayKind(at: t) == nil { return nil }      // someone's floor
            if let w = wayKind(at: t) {
                if w == kind { return 0.3 }
                if w.mode == kind.mode && kind.mode != .foot { return 0.5 }                          // a junction
                // crossing another way: a level crossing for streets and paths, a viaduct otherwise
                if (kind == .street || kind == .foot) && (w.mode == .rail || w.mode == .road) { return 2 }
                if w.mode == .road || w.mode == .rail { return allowBridges ? 6 : nil }
                return nil
            }
            return o != 0 ? 2.2 : 1
        }
        var best: [Int64: Double] = [key(a): 0]
        var came: [Int64: TilePos] = [:]
        var heap = MinHeap()
        heap.push(Double(abs(a.x - b.x) + abs(a.y - b.y)), NetNode(a.x, a.y, 0))
        var seen = 0
        guard stepCost(a) != nil, stepCost(b) != nil else { plan.reason = "end"; return plan }
        var found = false
        while let (_, n) = heap.pop() {
            let t = n.tile
            if t == b { found = true; break }
            seen += 1
            if seen > limit { break }
            let g = best[key(t)] ?? .infinity
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let m = TilePos(t.x + dx, t.y + dy)
                guard let c = stepCost(m) else { continue }
                // a straight line costs less than a zigzag (fewer turns on rails and runways)
                var turn = 0.0
                if let p = came[key(t)], (p.x - t.x != -dx || p.y - t.y != -dy) { turn = kind.mode == .rail || kind.mode == .air ? 1.5 : 0.25 }
                let ng = g + c + turn
                if ng < (best[key(m)] ?? .infinity) - 1e-9 {
                    best[key(m)] = ng; came[key(m)] = t
                    heap.push(ng + Double(abs(m.x - b.x) + abs(m.y - b.y)), NetNode(m.x, m.y, 0))
                }
            }
        }
        guard found else { plan.reason = seen > limit ? "too far" : "no way"; return plan }
        var cells = [b]; var k = b
        while let c = came[key(k)] { cells.append(c); k = c }
        cells.reverse()
        plan.cells = cells
        return finishPlan(plan)
    }

    /// The spans, tunnels, felling and cost of a plan whose tiles are chosen.
    func finishPlan(_ p: WayPlan) -> WayPlan {
        var plan = p
        let kind = plan.kind, cells = plan.cells
        // spans: runs of water, and runs crossing another way (a viaduct), and rock (a tunnel)
        var run: [TilePos] = [], runKind = 0             // 1 water, 2 over a way, 3 rock
        func flush() {
            if runKind == 1 || runKind == 2 { plan.spans.append(run) }
            if runKind == 3 { plan.tunnels.append(run) }
            run = []; runKind = 0
        }
        for t in cells {
            var rk = 0
            if waterDepth(t) > 0 { rk = 1 }
            else if let w = wayKind(at: t), w != kind, !((kind == .street || kind == .foot) && (w.mode == .rail || w.mode == .road)) { rk = 2 }
            else if world.tile(1, t.x, t.y) != 0 && content.solid[Int(world.tile(1, t.x, t.y))] { rk = 3 }
            if rk != runKind { flush() }
            if rk != 0 { run.append(t); runKind = rk }
        }
        flush()
        // what is felled, and what it gives
        for t in cells where waterDepth(t) == 0 {
            let o = world.tile(2, t.x, t.y)
            if o != 0, let def = content.tile(o), def.natural {
                plan.fell.append(t)
                if def.big { plan.wood += 4 } else if def.artKind == "rock" || def.artKind == "ore" { plan.stone += 2 } else { plan.wood += 1 }
            }
        }
        // a runway needs its margins clear too
        if kind == .runway { for t in cells { for m in [TilePos(t.x + 1, t.y), TilePos(t.x - 1, t.y), TilePos(t.x, t.y + 1), TilePos(t.x, t.y - 1)] where !cells.contains(m) && !plan.fell.contains(m) {
            let o = world.tile(2, m.x, m.y)
            if o != 0, let def = content.tile(o), def.natural { plan.fell.append(m); plan.wood += def.big ? 4 : 1 }
        } } }
        var cost: [String: Double] = [:]
        let spanTiles = Set(plan.spans.flatMap { $0 }), tunnelTiles = Set(plan.tunnels.flatMap { $0 })
        for t in cells where !spanTiles.contains(t) && !tunnelTiles.contains(t) && wayKind(at: t) != kind {
            for (g, v) in kind.cost { cost[g, default: 0] += v }
        }
        for s in plan.spans { for (g, v) in bridgeCost(plan.bridgeKind, deck: kind, tiles: s.count) { cost[g, default: 0] += v } }
        for u in plan.tunnels { cost["stone", default: 0] += 2 * Double(u.count); cost["parts", default: 0] += 2 * Double(u.count) }
        plan.cost = cost.filter { $0.value > 0 }
        plan.ok = true
        return plan
    }

    /// A straight way along one axis from `a` to `b`, or a refusal saying where it cannot go: every tile must
    /// be dry land with nothing built on it (trees and rocks are felled, an existing way of the same kind is kept).
    public func planStraightWay(_ kind: WayKind, from a: TilePos, to b: TilePos) -> WayPlan {
        var plan = WayPlan(); plan.kind = kind
        plan.bridgeKind = kind.mode == .rail ? .rail : (kind == .foot ? .foot : .road)
        guard a.x == b.x || a.y == b.y else { plan.reason = "not straight"; return plan }
        let n = max(abs(b.x - a.x), abs(b.y - a.y))
        let dx = (b.x - a.x).signum(), dy = (b.y - a.y).signum()
        var cells: [TilePos] = []
        for k in 0...n {
            let t = TilePos(a.x + dx * k, a.y + dy * k)
            if waterDepth(t) > 0 { plan.reason = "water at \(t.x),\(t.y)"; return plan }
            let s1 = world.tile(1, t.x, t.y)
            if s1 != 0 && content.solid[Int(s1)] { plan.reason = "rock at \(t.x),\(t.y)"; return plan }
            if let w = wayKind(at: t), w != kind { plan.reason = "another way at \(t.x),\(t.y)"; return plan }
            if bridge(at: t) != nil { plan.reason = "a bridge at \(t.x),\(t.y)"; return plan }
            if let o = content.tile(world.tile(2, t.x, t.y)), !o.natural { plan.reason = "something built at \(t.x),\(t.y)"; return plan }
            if content.tile(world.tile(0, t.x, t.y))?.built == true && wayKind(at: t) == nil { plan.reason = "a floor at \(t.x),\(t.y)"; return plan }
            cells.append(t)
        }
        plan.cells = cells
        return finishPlan(plan)
    }

    public func bridgeCost(_ k: BridgeKind, deck: WayKind, tiles n: Int) -> [String: Double] {
        let d = Double(n)
        switch k {
        case .foot: return ["planks": 3 * d, "stone": 1 * d]
        case .road, .viaduct: return ["stone": 3 * d, "iron": 2 * d, "parts": 2 * d]
        case .rail: return ["stone": 3 * d, "iron": 3 * d, "parts": 2 * d]
        case .opening: return ["stone": 3 * d, "iron": 3 * d, "parts": 2 * d + 6, "tools": 2]
        }
    }

    /// The holding a payer stands for.
    public func holding(_ p: Payer) -> Holding? {
        switch p {
        case .pack: return pack
        case .town(let id): return settlements[id]?.holding
        case .district(let id): return net.district(id)?.holding
        }
    }

    /// Pay for a plan and open its work site. Nothing is built yet: the site is worked hour by hour.
    /// Returns the site id, or nil (and nothing taken) when the plan cannot be paid or is not valid.
    @discardableResult public func startWay(_ plan: WayPlan, payer: Payer, nation: Int = 0, by: String = "player", rate: Double = 40) -> Int? {
        guard plan.ok, let h = holding(payer) else { return nil }
        if Goods.take(plan.cost, from: h) != nil { return nil }
        let tr = realm.transport
        record(plan.cost.map { ($0.key, $0.value) }, from: h.name, to: "works", note: "build \(plan.kind.rawValue)")
        var site = WorkSite(); site.id = tr.take(); site.payer = payer; site.owner = nation; site.by = by; site.rate = rate
        var spanOf: [TilePos: Int] = [:], tunnelOf: [TilePos: Int] = [:]
        for s in plan.spans {
            var b = Bridge(); b.id = tr.take(); b.kind = plan.bridgeKind; b.deck = plan.kind; b.cells = s; b.nation = nation; b.hp = 0     // raised as it is built
            // its direction: from the way's own order of tiles
            if let i = plan.cells.firstIndex(of: s[0]) {
                let next = s.count > 1 ? s[1] : (i + 1 < plan.cells.count ? plan.cells[i + 1] : s[0])
                let prev = i > 0 ? plan.cells[i - 1] : s[0]
                let d = s.count > 1 ? TilePos(next.x - s[0].x, next.y - s[0].y) : TilePos(s[0].x - prev.x, s[0].y - prev.y)
                b.ax = d.x; b.ay = d.y
            }
            let overWay = s.allSatisfy { waterDepth($0) == 0 }
            if overWay { b.kind = .viaduct; b.deckZ = 3.5 } else { b.deckZ = plan.bridgeKind == .opening ? 2 : (plan.kind.mode == .rail ? 5 : 4) }
            tr.bridges.append(b)
            for t in s { spanOf[t] = b.id }
        }
        for u in plan.tunnels {
            var x = Tunnel(); x.id = tr.take(); x.deck = plan.kind; x.cells = u; x.nation = nation
            tr.tunnels.append(x)
            for t in u { tunnelOf[t] = x.id }
        }
        site.cells = plan.cells.map { WorkCell(t: $0, kind: plan.kind, bridge: spanOf[$0], tunnel: tunnelOf[$0]) }
        // runway margins are felled with it (they are not paved)
        if plan.kind == .runway { for t in plan.fell where !plan.cells.contains(t) { var c = WorkCell(t: t, kind: plan.kind); c.done = false; c.bridge = -1; site.cells.append(c) } }
        tr.sites.append(site)
        tr.revision += 1
        return site.id
    }

    /// Work every open site for `hours`: fell, then lay, tile by tile, in order along the line.
    public func workSites(hours: Double) {
        let tr = realm.transport
        for si in tr.sites.indices where tr.sites[si].finished == nil {
            tr.sites[si].progress += tr.sites[si].rate * hours
            while tr.sites[si].progress >= 1, let ci = tr.sites[si].cells.firstIndex(where: { !$0.done }) {
                tr.sites[si].progress -= 1
                buildCell(&tr.sites[si], ci)
            }
            if !tr.sites[si].cells.contains(where: { !$0.done }) {
                tr.sites[si].finished = world.time
                tr.sites[si].progress = 0
                tr.stats.built += 1
            }
        }
        tr.revision += 1
    }

    /// Build a whole site at once (tests, and the player's own small jobs).
    public func finishSite(_ id: Int) {
        guard let i = realm.transport.sites.firstIndex(where: { $0.id == id }) else { return }
        let tr = realm.transport
        while let ci = tr.sites[i].cells.firstIndex(where: { !$0.done }) { buildCell(&tr.sites[i], ci) }
        tr.sites[i].finished = world.time
        tr.stats.built += 1
        tr.revision += 1
    }

    func buildCell(_ s: inout WorkSite, _ ci: Int) {
        let tr = realm.transport
        let c = s.cells[ci]
        let t = c.t
        // fell what stands there (the wood and stone go to the payer)
        let o = world.tile(2, t.x, t.y)
        if o != 0, let def = content.tile(o), def.natural {
            let wood = def.big ? 4.0 : (def.artKind == "rock" || def.artKind == "ore" ? 0 : 1)
            let stone = def.artKind == "rock" || def.artKind == "ore" ? 2.0 : 0
            world.setTile(2, t.x, t.y, 0)
            if let h = holding(s.payer) {
                if wood > 0 { h.change("wood", wood); record([("wood", wood)], from: "felled", to: h.name, note: "clearing") }
                if stone > 0 { h.change("stone", stone); record([("stone", stone)], from: "felled", to: h.name, note: "clearing") }
            }
            s.wood += wood; s.stone += stone
            tr.stats.felled += 1; tr.stats.woodFromClearing += wood
        }
        world.setTile(3, t.x, t.y, 0)
        keepClear(t)
        if c.bridge == -1 { s.cells[ci].done = true; return }                 // a margin: felled only
        if let bid = c.bridge, let bi = tr.bridges.firstIndex(where: { $0.id == bid }) {
            // a span: a deck tile over water; over a way the deck is the bridge itself (the way stays below)
            if waterDepth(t) > 0 {
                let deckTile = tr.bridges[bi].kind == .opening ? "bridge_lift" : (c.kind.mode == .rail ? "bridge_rail" : (c.kind == .foot ? "bridge_foot" : "bridge_road"))
                world.setTile(1, t.x, t.y, content.tid(deckTile))
            }
            if tr.bridges[bi].cells.last == t || !s.cells.contains(where: { !$0.done && $0.bridge == bid && $0.t != t }) { tr.bridges[bi].hp = 1; tr.stats.bridges += 1 }
        } else if let uid = c.tunnel {
            _ = uid                                                             // the rock stays: the way runs under it
            if !s.cells.contains(where: { !$0.done && $0.tunnel == uid && $0.t != t }) { tr.stats.tunnels += 1 }
        } else if let old = wayKind(at: t) {
            if old.mode == .rail && (c.kind.mode == .road || c.kind == .foot) || old.mode == .road && c.kind.mode == .rail {
                // a level crossing: the rails stay, a street may cross them
                if old.mode == .road { world.setTile(1, t.x, t.y, content.tid(c.kind.tileKey)) }
                tr.crossings.insert(MP.chunkKey(t.x, t.y))
            } else if old.mode == .road && c.kind.mode == .road && c.kind.limit > old.limit {
                world.setTile(1, t.x, t.y, content.tid(c.kind.tileKey))                        // an upgrade
            }
        } else {
            world.setTile(1, t.x, t.y, content.tid(c.kind.tileKey))
        }
        s.cells[ci].done = true
    }

    /// Take a bridge down (by hand, in war, by collapse). Its deck tiles go; traffic on it falls back to the
    /// ground at the nearest end (vehicles stop and re-plan); ships pass freely.
    @discardableResult public func demolishBridge(_ id: Int) -> Bool {
        let tr = realm.transport
        guard let i = tr.bridges.firstIndex(where: { $0.id == id }) else { return false }
        let b = tr.bridges[i]
        for t in b.cells where waterDepth(t) > 0 { world.setTile(1, t.x, t.y, 0) }
        tr.bridges.remove(at: i)
        tr.revision += 1
        for v in tr.vehicles where v.level == 1 && b.cells.contains(v.tile) {
            // it was on the deck: it is stopped where the deck was, at the nearer end, and must find another way
            let end = b.cells.first!.distance2(v.tile) <= b.cells.last!.distance2(v.tile) ? b.cells.first! : b.cells.last!
            v.place(at: end.center, level: 0); v.speed = 0; v.halt("bridge gone")
        }
        for v in tr.vehicles { v.replan = true }
        return true
    }

    // MARK: when the land returns to nature (a law)

    /// Everything of the network on this chunk goes with the land: decks, tunnels, stops (and the lines' calls
    /// there), vehicles (their riders are set down, their goods are written off in the books as taken by the law),
    /// kept-clear corridors, and the district buildings standing there (their residents are booked as gone).
    public func landReturned(cx: Int, cy: Int) {
        let tr = realm.transport
        func inside(_ t: TilePos) -> Bool { t.x >> 5 == cx && t.y >> 5 == cy }
        tr.bridges.removeAll { $0.cells.contains(where: inside) }
        tr.tunnels.removeAll { $0.cells.contains(where: inside) }
        tr.corridor = tr.corridor.filter { !inside(TilePos(MP.keyCX($0), MP.keyCY($0))) }
        tr.crossings = tr.crossings.filter { !inside(TilePos(MP.keyCX($0), MP.keyCY($0))) }
        tr.locks.removeAll { inside($0.cell) }
        // vehicles
        for v in tr.vehicles where inside(v.tile) {
            for (sid, amt) in v.cargo { if let sh = tr.shipments.first(where: { $0.id == sid }) { record([(sh.key, amt)], from: "vehicle \(v.id)", to: "taken by the law", note: "lost shipment \(sid)"); sh.amount -= amt } }
            for r in v.riders { if case .commuter(let id) = r.who, let i = tr.commuters.firstIndex(where: { $0.id == id }) { tr.commuters[i].state = tr.commuters[i].toWork ? .home : .atWork; tr.commuters[i].vehicle = nil } }
            if v.playerAboard, var b = realm.player.body { b.vehicle = nil; b.lx = nil; b.ly = nil; b.lz = nil; b.seat = nil; b.state = .falling; realm.player.body = b }
            for l in tr.lines { l.vehicles.removeAll { $0 == v.id } }
        }
        tr.vehicles.removeAll { inside($0.tile) }
        // stops (and the lines that called there)
        let gone = Set(tr.stops.filter { inside($0.tile) }.map { $0.id })
        for st in tr.stops where gone.contains(st.id) {
            for (sid, amt) in st.yard { if let sh = tr.shipments.first(where: { $0.id == sid }) { record([(sh.key, amt)], from: "yard \(st.name)", to: "taken by the law", note: "lost shipment \(sid)"); sh.amount -= amt } }
            for r in st.waiting { if case .commuter(let id) = r.who, let i = tr.commuters.firstIndex(where: { $0.id == id }) { tr.commuters[i].state = tr.commuters[i].toWork ? .home : .atWork } }
        }
        tr.stops.removeAll { gone.contains($0.id) }
        for l in tr.lines { l.stops.removeAll { gone.contains($0) } }
        for l in tr.lines where l.stops.count < 2 { for vid in l.vehicles { tr.vehicle(vid)?.task = VehicleTask() } }
        tr.lines.removeAll { $0.stops.count < 2 }
        for v in tr.vehicles { if let lid = v.task.line, tr.line(lid) == nil { v.task = VehicleTask() }; v.replan = true }
        for sh in tr.shipments where sh.state != .delivered && sh.amount <= sh.delivered + 1e-9 { sh.state = .delivered; sh.done = world.time }
        // district buildings on that land
        for d in tr.districts {
            for b in d.buildings where inside(TilePos(b.x, b.y)) || inside(TilePos(b.x + b.w - 1, b.y + b.d - 1)) {
                let n = b.residents
                if n > 0 { d.ledger.deaths["law", default: 0] += n }
                tr.commuters.removeAll { ($0.home == d.id && $0.homeB == b.id) || ($0.work == d.id && $0.workB == b.id) }
            }
            d.buildings.removeAll { inside(TilePos($0.x, $0.y)) || inside(TilePos($0.x + $0.w - 1, $0.y + $0.d - 1)) }
        }
        tr.revision += 1
    }

    // MARK: opening bridges

    /// Ask an opening bridge to open for a ship: traffic is stopped first and the deck must be empty.
    public func requestOpening(_ id: Int) {
        guard let i = realm.transport.bridges.firstIndex(where: { $0.id == id }), realm.transport.bridges[i].kind == .opening else { return }
        if realm.transport.bridges[i].state == .closed { realm.transport.bridges[i].state = .stopping; realm.transport.bridges[i].stateT = 0; realm.transport.revision += 1 }
    }

    func bridgesStep(_ dt: Double) {
        let tr = realm.transport
        for i in tr.bridges.indices where tr.bridges[i].kind == .opening {
            var b = tr.bridges[i]
            b.stateT += dt
            switch b.state {
            case .closed: break
            case .stopping:
                // the barriers are down: nothing may come on; it rises only once nothing is on the deck
                let onDeck = tr.vehicles.contains { $0.level == 1 && b.cells.contains($0.tile) }
                let walker = realm.player.body.map { $0.depth == 0 && b.cells.contains(Motion.tile($0.x, $0.y)) && $0.vehicle == nil } ?? false
                if !onDeck && !walker && b.stateT >= 3 { b.state = .raising; b.stateT = 0 }
            case .raising: if b.stateT >= 12 { b.state = .open; b.stateT = 0; tr.revision += 1 }
            case .open:
                // down again once no ship is under it or waiting close by
                let ship = tr.vehicles.contains { v in v.kind.mode == .water && b.cells.contains { c in c.distance2(v.tile) <= 36 } }
                if !ship && b.stateT >= 8 { b.state = .lowering; b.stateT = 0 }
            case .lowering: if b.stateT >= 12 { b.state = .closed; b.stateT = 0; tr.revision += 1 }
            }
            if b.state != tr.bridges[i].state { tr.revision += 1 }
            tr.bridges[i] = b
        }
    }

    // MARK: choosing how to cross

    public struct CrossingOption: Equatable {
        public var how: String                 // "detour", "clear", "bridge", "tunnel", "ferry"
        public var cost: Double                // goods, summed
        public var travel: Double              // seconds for a car from end to end
        public var feasible: Bool
        public var plan: WayPlan?
    }

    /// The ways to join two places by road, priced: drive round on what exists, build on clear land
    /// (felling trees), build with bridges, build with tunnels, or a ferry. Cost is goods to build plus
    /// a year of the extra driving time (so a far detour loses to a short bridge).
    public func crossingOptions(from a: TilePos, to b: TilePos) -> [CrossingOption] {
        var out: [CrossingOption] = []
        let car = Profile(mode: .road)
        if let r = route(from: NetNode(a.x, a.y, 0), to: NetNode(b.x, b.y, 0), car) {
            let s = zip(r.dropFirst(), r).reduce(0.0) { $0 + crossTime($1.0, car) }
            out.append(CrossingOption(how: "detour", cost: 0, travel: s, feasible: true, plan: nil))
        } else { out.append(CrossingOption(how: "detour", cost: .infinity, travel: .infinity, feasible: false, plan: nil)) }
        func priced(_ p: WayPlan, _ how: String) -> CrossingOption {
            guard p.ok else { return CrossingOption(how: how, cost: .infinity, travel: .infinity, feasible: false, plan: p) }
            let goods = p.cost.values.reduce(0, +)
            let travel = Double(p.cells.count) / WayKind.street.limit
            return CrossingOption(how: how, cost: goods, travel: travel, feasible: true, plan: p)
        }
        out.append(priced(planWay(.street, from: a, to: b, allowBridges: false, allowTunnels: false), "clear"))
        out.append(priced(planWay(.street, from: a, to: b, allowBridges: true, allowTunnels: false), "bridge"))
        out.append(priced(planWay(.street, from: a, to: b, allowBridges: true, allowTunnels: true), "tunnel"))
        // a ferry: two quays and a boat; it is always possible where water joins the two sides
        let ferryCost = 2 * 3 * (WayKind.quay.cost.values.reduce(0, +)) + 60          // two short quays and the boat's materials
        let water = Profile(mode: .water, draft: 1.5)
        let qa = nearestWater(a, 12), qb = nearestWater(b, 12)
        if let qa = qa, let qb = qb, let r = route(from: NetNode(qa.x, qa.y, 0), to: NetNode(qb.x, qb.y, 0), water, limit: 60_000) {
            out.append(CrossingOption(how: "ferry", cost: ferryCost, travel: Double(r.count) / 6 + 120, feasible: true, plan: nil))
        } else { out.append(CrossingOption(how: "ferry", cost: .infinity, travel: .infinity, feasible: false, plan: nil)) }
        // the "tunnel" plan is only a tunnel if it really used one
        if let i = out.firstIndex(where: { $0.how == "tunnel" }), out[i].plan?.tunnels.isEmpty ?? true { out[i].feasible = false; out[i].cost = .infinity }
        if let i = out.firstIndex(where: { $0.how == "bridge" }), out[i].plan?.spans.isEmpty ?? true, out.first(where: { $0.how == "clear" })?.feasible == true { out[i].feasible = false; out[i].cost = .infinity }
        return out
    }

    /// Which crossing to choose: the lowest of goods plus a year of daily trips' extra time.
    public func chooseCrossing(_ opts: [CrossingOption], tripsPerDay: Double = 40) -> CrossingOption? {
        let feasible = opts.filter { $0.feasible }
        guard let quickest = feasible.map({ $0.travel }).min() else { return nil }
        return feasible.min { a, b in
            let ca = a.cost + (a.travel - quickest) * tripsPerDay * 365 / 600, cb = b.cost + (b.travel - quickest) * tripsPerDay * 365 / 600
            return ca != cb ? ca < cb : a.how < b.how
        }
    }

    func nearestWater(_ t: TilePos, _ r: Int) -> TilePos? {
        var best: (Int, TilePos)?
        for dy in -r...r { for dx in -r...r {
            let p = TilePos(t.x + dx, t.y + dy)
            if waterDepth(p) >= 3, best == nil || dx * dx + dy * dy < best!.0 { best = (dx * dx + dy * dy, p) }
        } }
        return best?.1
    }

    // MARK: the books

    func record(_ goods: [(String, Double)], from: String, to: String, note: String) {
        let tr = realm.transport
        for (k, v) in goods where v != 0 { tr.ledger.append(Transfer(t: world.time, key: k, amount: v, from: from, to: to, note: note)) }
        if tr.ledger.count > 4000 { tr.ledger.removeFirst(tr.ledger.count - 4000) }
    }
}

extension TilePos {
    public func distance2(_ o: TilePos) -> Int { (x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) }
}

/// A small binary heap of (priority, node), lowest first; ties by insertion order (deterministic).
struct MinHeap {
    private var a: [(Double, Int, NetNode)] = []
    private var n = 0
    mutating func push(_ p: Double, _ v: NetNode) {
        n += 1
        a.append((p, n, v))
        var i = a.count - 1
        while i > 0 {
            let par = (i - 1) / 2
            if less(a[i], a[par]) { a.swapAt(i, par); i = par } else { break }
        }
    }
    private func less(_ x: (Double, Int, NetNode), _ y: (Double, Int, NetNode)) -> Bool { x.0 != y.0 ? x.0 < y.0 : x.1 < y.1 }
    mutating func pop() -> (Double, NetNode)? {
        guard !a.isEmpty else { return nil }
        let top = a[0]
        let last = a.removeLast()
        if !a.isEmpty {
            a[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < a.count && less(a[l], a[m]) { m = l }
                if r < a.count && less(a[r], a[m]) { m = r }
                if m == i { break }
                a.swapAt(i, m); i = m
            }
        }
        return (top.0, top.2)
    }
    var isEmpty: Bool { a.isEmpty }
}
