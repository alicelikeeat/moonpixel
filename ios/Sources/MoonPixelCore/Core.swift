import Foundation

/// Shared constants and deterministic helpers.
public enum MP {
    public static let tile = 16
    public static let chunk = 32
    public static let chunkArea = 1024
    public static let chunkPx = 512
    public static let daySeconds = 1200.0
    /// One in-game year is one day/night cycle.
    public static let year = 1200.0
    public static let lGround = 0, lStruct = 1, lObject = 2, lDecor = 3

    /// Deterministic 32-bit hash of (seed, x, y).
    @inline(__always) public static func h2(_ s: Int, _ x: Int, _ y: Int) -> UInt32 {
        var h = UInt32(truncatingIfNeeded: s) ^ (UInt32(truncatingIfNeeded: x) &* 0x27d4eb2d)
        h = (h ^ (h >> 15)) &* 0x2c1b3c6d
        h ^= UInt32(truncatingIfNeeded: y) &* 0x165667b1
        h = (h ^ (h >> 12)) &* 0x297a2d39
        return h ^ (h >> 15)
    }

    @inline(__always) public static func h01(_ s: Int, _ x: Int, _ y: Int) -> Double {
        Double(h2(s, x, y) & 0xffffff) / 16777216.0
    }

    @inline(__always) public static func chunkKey(_ cx: Int, _ cy: Int) -> Int64 {
        (Int64(cy) << 32) | Int64(UInt32(truncatingIfNeeded: cx))
    }

    public static func keyCX(_ k: Int64) -> Int { Int(Int32(truncatingIfNeeded: k)) }
    public static func keyCY(_ k: Int64) -> Int { Int(k >> 32) }
}

/// 2D point in world pixels.
public struct Vec2: Equatable, Codable, Hashable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static let zero = Vec2(0, 0)
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, k: Double) -> Vec2 { Vec2(a.x * k, a.y * k) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public var normalized: Vec2 { let l = length; return l > 1e-9 ? Vec2(x / l, y / l) : .zero }
    public func distance(to o: Vec2) -> Double { (self - o).length }
    public var tile: TilePos { TilePos(Int((x / 16).rounded(.down)), Int((y / 16).rounded(.down))) }
}

/// Integer tile coordinate.
public struct TilePos: Equatable, Hashable, Codable {
    public var x: Int, y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public static func + (a: TilePos, b: TilePos) -> TilePos { TilePos(a.x + b.x, a.y + b.y) }
    public static func - (a: TilePos, b: TilePos) -> TilePos { TilePos(a.x - b.x, a.y - b.y) }
    public var center: Vec2 { Vec2(Double(x * 16 + 8), Double(y * 16 + 8)) }
    public var lengthSquared: Int { x * x + y * y }
    public static let none = TilePos(Int.max, 0)
    public var isNone: Bool { x == Int.max }
}

/// Small deterministic RNG (SplitMix64).
public struct RNG: Codable {
    public var state: UInt64
    public init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// 0 ..< 1
    public mutating func unit() -> Double { Double(next() >> 11) / 9007199254740992.0 }
    public mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    /// inclusive
    public mutating func int(_ a: Int, _ b: Int) -> Int { a + Int(next() % UInt64(b - a + 1)) }
    public mutating func index(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
}

/// Seeded 2D simplex noise with fractal octaves. Output roughly -1...1.
public struct Noise {
    private var perm = [UInt8](repeating: 0, count: 512)
    public let frequency: Double
    public let octaves: Int
    private let ox: Double, oy: Double      // per-seed offset: the lattice origin is not special

    public init(seed: Int, frequency: Double, octaves: Int) {
        self.frequency = frequency
        self.octaves = max(1, octaves)
        var p = (0..<256).map { UInt8($0) }
        var r = RNG(seed: seed)
        for i in stride(from: 255, to: 0, by: -1) { p.swapAt(i, r.index(i + 1)) }
        for i in 0..<512 { perm[i] = p[i & 255] }
        ox = r.range(100, 900) + 0.37
        oy = r.range(100, 900) + 0.71
    }

    private static let grad: [(Double, Double)] = [(1, 1), (-1, 1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)]

    private func raw(_ xin: Double, _ yin: Double) -> Double {
        let F2 = 0.3660254037844386, G2 = 0.21132486540518713
        let s = (xin + yin) * F2
        let i = (xin + s).rounded(.down), j = (yin + s).rounded(.down)
        let t = (i + j) * G2
        let x0 = xin - (i - t), y0 = yin - (j - t)
        let i1 = x0 > y0 ? 1 : 0, j1 = x0 > y0 ? 0 : 1
        let x1 = x0 - Double(i1) + G2, y1 = y0 - Double(j1) + G2
        let x2 = x0 - 1 + 2 * G2, y2 = y0 - 1 + 2 * G2
        let ii = Int(truncatingIfNeeded: Int64(i)) & 255, jj = Int(truncatingIfNeeded: Int64(j)) & 255
        func corner(_ x: Double, _ y: Double, _ gi: Int) -> Double {
            var t = 0.5 - x * x - y * y
            if t < 0 { return 0 }
            t *= t
            let g = Noise.grad[gi & 7]
            return t * t * (g.0 * x + g.1 * y)
        }
        let n0 = corner(x0, y0, Int(perm[ii + Int(perm[jj])]))
        let n1 = corner(x1, y1, Int(perm[ii + i1 + Int(perm[jj + j1])]))
        let n2 = corner(x2, y2, Int(perm[ii + 1 + Int(perm[jj + 1])]))
        return 70.0 * (n0 + n1 + n2)
    }

    public func get(_ x: Double, _ y: Double) -> Double {
        var sum = 0.0, amp = 1.0, f = frequency, norm = 0.0
        for _ in 0..<octaves {
            sum += raw(x * f + ox, y * f + oy) * amp
            norm += amp
            amp *= 0.5
            f *= 2.0
        }
        return sum / norm
    }
}

public struct TileDef {
    public let id: Int, key: String, layer: Int
    public let solid: Bool, water: Bool, bridge: Bool, natural: Bool, big: Bool, built: Bool
    public let walk: Double, light: Int
    public let growTo: String, growTime: Double, after: String
    public let artKind: String, c1: String, c2: String, c3: String, stage: Int
    public let nameEn: String, nameZh: String
}

public struct BiomeDef {
    public let index: Int, key: String, group: String, color: String, ground: String, alt: String, altChance: Double
    public let trees: [(String, Double)], treeDensity: Double, objects: [(String, Double)], decor: [(String, Double)]
    public let nameEn: String, nameZh: String
}

/// Read-only game data (tiles, biomes). Numeric tile ids are a save-format contract.
public final class Content {
    public static let shared = Content()
    public private(set) var tiles = [TileDef?](repeating: nil, count: 256)
    public private(set) var ids: [String: UInt8] = [:]
    public private(set) var solid = [Bool](repeating: false, count: 256)
    public private(set) var water = [Bool](repeating: false, count: 256)
    public private(set) var bridge = [Bool](repeating: false, count: 256)
    public let biomes: [BiomeDef]

    private init() {
        for t in ContentData.tiles {
            tiles[t.id] = t
            ids[t.key] = UInt8(t.id)
            solid[t.id] = t.solid
            water[t.id] = t.water
            bridge[t.id] = t.bridge
        }
        biomes = ContentData.biomes.sorted { $0.index < $1.index }
    }

    @inline(__always) public func tid(_ key: String) -> UInt8 { ids[key] ?? 0 }
    @inline(__always) public func tile(_ id: UInt8) -> TileDef? { tiles[Int(id)] }
}

public enum Biome {
    public static let ocean = 0, beach = 1, grass = 2, forest = 3, snow = 4, taiga = 5, desert = 6, canyon = 7, wetland = 8, mountain = 9
    public static let sea = 0.34, mountainLevel = 0.80

    public static func classify(_ e: Double, _ t: Double, _ m: Double) -> Int {
        if e < sea { return ocean }
        if e > mountainLevel { return mountain }
        if t < 0.30 { return m > 0.5 ? taiga : snow }
        if e < sea + 0.015 { return beach }
        if t > 0.70 { return e > 0.66 ? canyon : desert }
        if m > 0.56 && e < 0.60 { return wetland }
        return m > 0.47 ? forest : grass
    }
}
