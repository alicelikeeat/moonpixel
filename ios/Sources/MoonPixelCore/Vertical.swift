import Foundation

// Vertical space: buildings that grow up and down with no fixed number of floors.
//
// Coordinates. A cell is (x, y, z) in 64-bit integers: x and y on the ground plane (the same tiles as
// the open world), z up. The open world as it is today is the surface reference layer, z = 0; the
// underground layer is z = -1 ... -16 (a mapping only: nothing in old saves changes). RealityKit draws
// (x, z, y). There is no height limit in the rules; the numbers have one (`Space.limit`, about 10^12
// cells either way), and anything that would cross it is refused, never wrapped round.
//
// Storage. A floor does not store its cells. It names a floor plan (shared, immutable, possibly used by
// hundreds of floors) and keeps only its own differences (copy-on-write): changing one floor never
// changes the floors that share its plan. Empty space is not stored at all. Finding what is at a cell
// goes through an index of towers by 3D chunk (32 x 32 x 16), so only towers near the cell are looked at.

public struct Cell3: Hashable, Codable, Comparable, CustomStringConvertible {
    public var x: Int64, y: Int64, z: Int64
    public init(_ x: Int64, _ y: Int64, _ z: Int64) { self.x = x; self.y = y; self.z = z }
    public static func < (a: Cell3, b: Cell3) -> Bool { (a.z, a.y, a.x) < (b.z, b.y, b.x) }
    public var description: String { "(\(x), \(y), \(z))" }
}

public struct Chunk3: Hashable, Codable, Comparable {
    public var cx: Int64, cy: Int64, cz: Int64
    public static func < (a: Chunk3, b: Chunk3) -> Bool { (a.cz, a.cy, a.cx) < (b.cz, b.cy, b.cx) }
}

public enum Space {
    /// Cells beyond this distance from the origin (on any axis) are refused.
    public static let limit: Int64 = 1 << 40
    public static let chunkW: Int64 = 32, chunkH: Int64 = 16
    public static let undergroundTop: Int64 = -1, undergroundBottom: Int64 = -16

    public static func valid(_ c: Cell3) -> Bool { abs(c.x) <= limit && abs(c.y) <= limit && abs(c.z) <= limit }

    /// a + d, or nil if it would leave the space (no wrap-round, ever).
    public static func add(_ a: Int64, _ d: Int64) -> Int64? {
        let (r, o) = a.addingReportingOverflow(d)
        return o || abs(r) > limit ? nil : r
    }
    public static func offset(_ c: Cell3, _ dx: Int64, _ dy: Int64, _ dz: Int64) -> Cell3? {
        guard let x = add(c.x, dx), let y = add(c.y, dy), let z = add(c.z, dz) else { return nil }
        return Cell3(x, y, z)
    }

    /// Division rounding down for negative numbers too (-1 / 32 is -1, not 0).
    @inline(__always) public static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 { let q = a / b; return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q }
    public static func chunk(_ c: Cell3) -> Chunk3 { Chunk3(cx: floorDiv(c.x, chunkW), cy: floorDiv(c.y, chunkW), cz: floorDiv(c.z, chunkH)) }

    /// Where a cell is drawn, relative to an origin near the camera: the difference is taken in integers
    /// first, so far-away absolute numbers never lose precision in Float. RealityKit order (x, z, y).
    public static func render(_ c: Cell3, origin o: Cell3) -> SIMD3<Float>? {
        let (dx, ox) = c.x.subtractingReportingOverflow(o.x), (dy, oy) = c.y.subtractingReportingOverflow(o.y), (dz, oz) = c.z.subtractingReportingOverflow(o.z)
        guard !ox, !oy, !oz, abs(dx) < 1 << 23, abs(dy) < 1 << 23, abs(dz) < 1 << 23 else { return nil }
        return SIMD3(Float(dx), Float(dz), Float(dy))
    }

    /// The layer the open world's tiles are on: the surface is z = 0, the underground z = -1.
    public static func openWorld(tile t: TilePos, depth: Int) -> Cell3 { Cell3(Int64(t.x), Int64(t.y), depth > 0 ? undergroundTop : 0) }
}

// MARK: - floor plans

/// One cell of a floor.
public enum Part: UInt8, Codable { case empty = 0, slab, wall, door, column, stair, shaft, window, bed, field, shelf, machine, battlement, dock }

/// What a room is for.
public enum RoomUse: String, Codable, CaseIterable { case home, farm, store, works, lobby, defence, pump, dock }

public struct Room: Codable, Equatable {
    public var use: RoomUse
    public var cells: [Int]                 // indexes into the plan
    public var entrance: Int                // a door cell
    public var capacity: Int                // beds, plots, shelves or machines
}

/// A floor's layout, shared by every floor that uses it. Never changed once made.
public struct FloorPlan: Codable, Equatable {
    public var key: String
    public var w: Int, d: Int
    public var height: Int                  // cells from this floor's slab to the next one's
    public var parts: [Part]
    public var rooms: [Room]
    public var use: RoomUse                 // what most of it is for
    public func at(_ x: Int, _ y: Int) -> Part { x >= 0 && y >= 0 && x < w && y < d ? parts[y * w + x] : .empty }
    public var columns: Int { parts.filter { $0 == .column }.count }
    public var cores: [Int] { parts.indices.filter { parts[$0] == .stair || parts[$0] == .shaft } }
    public func capacity(_ u: RoomUse) -> Int { rooms.filter { $0.use == u }.reduce(0) { $0 + $1.capacity } }
    /// Dead weight of the floor in load units (slab, walls, fittings).
    public var weight: Double { Double(parts.filter { $0 != .empty }.count) * 1.0 + Double(columns) * 2 }
}

// MARK: - towers

public struct TowerFloor: Codable, Equatable {
    public enum Stage: Int, Codable, Comparable {
        case planned = 0, reserved, structure, fitout, inspection, inUse, damaged, failed
        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }
    public var z: Int64                      // the slab's height
    public var plan: String
    public var diff: [Int: Part] = [:]       // this floor's own changes to the plan
    public var stage = Stage.planned
    public var work = 0.0                    // days of work left on the current stage
    public var people = CivPeople()          // who lives or works here (moved from the city, still its people)
    public var food = 0.0                    // nutrition delivered and not yet eaten
    public var damage = 0.0                  // 0 whole ... 1 wrecked
    public var coverage = 1.0                // share of the day's food that reached it
    public var water = 1.0
    public var builtDay = 0
    public var protected = false             // built or marked by the player: the planner leaves it alone
}

public final class Tower: Codable {
    public var id = 0, city = 0, nation = 0
    public var nameEn = "", nameZh = ""
    public var base: Cell3                   // north-west corner of the lowest floor's slab
    public var w = 0, d = 0
    public var floors: [TowerFloor] = []     // bottom to top
    public var material = 0                  // 0 timber, 1 stone, 2 steel, 3 composite, 4 field-lift
    public var lifts = 0                     // elevator banks
    public var skyLobbyEvery = 0             // 0: no transfer floors (every bank runs the whole height)
    public var style = ""
    public var founded = 0
    public var history: [String] = []        // what was done to it and why
    public var protected = false
    /// Load each floor carries (its own and everything above), and what it can carry: worked out from the
    /// floor that changed downwards only.
    public var load: [Double] = [], strength: [Double] = []
    public var recomputed = 0                // floors whose load was worked out at the last change (for tests and the panel)
    public var liftLoad = 0.0                // yesterday's work for lifts and stairs over what they can do (over 1: not everything got up)
    public init(base: Cell3) { self.base = base }

    public var top: Int64 { floors.last.map { $0.z + 4 } ?? base.z }
    public func floor(at z: Int64) -> Int? {
        // floors are sorted by z: binary search
        var lo = 0, hi = floors.count - 1
        while lo <= hi {
            let m = (lo + hi) / 2
            let f = floors[m], h = Int64(4)
            if z < f.z { hi = m - 1 } else if z >= f.z + h { lo = m + 1 } else { return m }
        }
        return nil
    }
    public func contains(_ c: Cell3) -> Bool { c.x >= base.x && c.y >= base.y && c.x < base.x + Int64(w) && c.y < base.y + Int64(d) && c.z >= base.z && c.z < top }
}

/// Every tower of a world, and a sparse index of which 3D chunks each one touches.
public struct TowerIndex: Codable {
    public var towers: [Int: Tower] = [:]
    public var plans: [String: FloorPlan] = [:]
    public var nextTower = 1
    var byColumn: [Int64: [Int]] = [:]       // 2D chunk of the footprint -> towers (height is checked per tower)

    public init() {}
    enum CodingKeys: String, CodingKey { case towers, plans, nextTower }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        for t in try c.decodeIfPresent([Tower].self, forKey: .towers) ?? [] { towers[t.id] = t }
        for p in try c.decodeIfPresent([FloorPlan].self, forKey: .plans) ?? [] { plans[p.key] = p }
        nextTower = try c.decodeIfPresent(Int.self, forKey: .nextTower) ?? (towers.keys.max() ?? 0) + 1
        reindex()
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(towers.keys.sorted().map { towers[$0]! }, forKey: .towers)
        try c.encode(plans.keys.sorted().map { plans[$0]! }, forKey: .plans)
        try c.encode(nextTower, forKey: .nextTower)
    }

    static func columnKey(_ x: Int64, _ y: Int64) -> Int64 { let cx = Space.floorDiv(x, Space.chunkW), cy = Space.floorDiv(y, Space.chunkW); return (cx &* 0x1_0000_0000) ^ (cy & 0xffff_ffff) }

    mutating func reindex() {
        byColumn = [:]
        for t in towers.values.sorted(by: { $0.id < $1.id }) { index(t) }
    }
    mutating func index(_ t: Tower) {
        var x = t.base.x
        while x < t.base.x + Int64(t.w) {
            var y = t.base.y
            while y < t.base.y + Int64(t.d) { let k = TowerIndex.columnKey(x, y); if !(byColumn[k]?.contains(t.id) ?? false) { byColumn[k, default: []].append(t.id) }; y += Space.chunkW }
            x += Space.chunkW
        }
        let k = TowerIndex.columnKey(t.base.x + Int64(t.w) - 1, t.base.y + Int64(t.d) - 1)
        if !(byColumn[k]?.contains(t.id) ?? false) { byColumn[k, default: []].append(t.id) }
    }

    /// What is at a cell: the tower and floor there, and the part (the floor's own change, else its plan's).
    public func at(_ c: Cell3) -> (tower: Int, floor: Int, part: Part)? {
        guard Space.valid(c) else { return nil }
        for id in byColumn[TowerIndex.columnKey(c.x, c.y)] ?? [] {
            guard let t = towers[id], t.contains(c), let fi = t.floor(at: c.z) else { continue }
            let f = t.floors[fi]
            let i = Int(c.y - t.base.y) * t.w + Int(c.x - t.base.x)
            if c.z != f.z { return (id, fi, .empty) }              // the air of the storey above the slab
            return (id, fi, f.diff[i] ?? plans[f.plan]?.parts[i] ?? .empty)
        }
        return nil
    }

    /// Change one cell of one floor (copy-on-write: the shared plan is untouched).
    public mutating func set(_ c: Cell3, _ p: Part) -> Bool {
        guard let (id, fi, _) = at(c), let t = towers[id], t.floors[fi].z == c.z, !t.floors[fi].protected else { return false }
        let i = Int(c.y - t.base.y) * t.w + Int(c.x - t.base.x)
        t.floors[fi].diff[i] = p
        return true
    }
}
