import Foundation

public struct GrowTimer: Codable {
    public var i: Int, l: Int, to: UInt8, due: Double, expect: UInt8
}

public struct Prop: Codable {
    public var id: Int, key: String, x: Double, y: Double
}

/// One 32x32 chunk: four tile layers plus timers and free-positioned props.
public final class Chunk {
    public let cx: Int, cy: Int
    public var layers: [[UInt8]]
    public var timers: [GrowTimer] = []
    public var props: [Prop] = []
    public var modified = false
    public var dirty = false
    public var revision = 0
    public var lastUsed = 0

    public init(cx: Int, cy: Int) {
        self.cx = cx; self.cy = cy
        layers = Array(repeating: [UInt8](repeating: 0, count: MP.chunkArea), count: 4)
    }

    public var key: Int64 { MP.chunkKey(cx, cy) }
    public func touch() { modified = true; dirty = true; revision += 1 }

    struct Saved: Codable {
        var v: Int, cx: Int, cy: Int, l0: Data, l1: Data, l2: Data, l3: Data, timers: [GrowTimer], props: [Prop], revision: Int
    }

    public func encoded() -> Data {
        let s = Saved(v: 1, cx: cx, cy: cy, l0: Data(layers[0]), l1: Data(layers[1]), l2: Data(layers[2]), l3: Data(layers[3]),
                      timers: timers, props: props, revision: revision)
        return (try? JSONEncoder().encode(s)) ?? Data()
    }

    /// nil when the data is truncated, corrupt or from an unknown format.
    public static func decode(_ data: Data) -> Chunk? {
        guard let s = try? JSONDecoder().decode(Saved.self, from: data), s.v == 1,
              s.l0.count == MP.chunkArea, s.l1.count == MP.chunkArea, s.l2.count == MP.chunkArea, s.l3.count == MP.chunkArea else { return nil }
        let c = Chunk(cx: s.cx, cy: s.cy)
        c.layers = [[UInt8](s.l0), [UInt8](s.l1), [UInt8](s.l2), [UInt8](s.l3)]
        c.timers = s.timers
        c.props = s.props
        c.revision = s.revision
        c.modified = true
        return c
    }
}

/// Unbounded deterministic terrain: every tile is a pure function of (seed, x, y).
public final class Generator {
    public let seed: Int
    /// Climate shifts chosen when the world was created (see WorldRecipe).
    public var tempBias = 0.0, moistBias = 0.0, elevBias = 0.0
    public var depth = 0
    let content = Content.shared
    let nElev, nTemp, nMoist, nRiver, nForest, nDetail: Noise
    var ground = [UInt8](), alt = [UInt8](), altCh = [Double](), density = [Double]()
    var trees = [[(UInt8, Double)]](), objects = [[(UInt8, Double)]](), decor = [[(UInt8, Double)]]()
    let tDeep, tWater, tShallow, tIce, tSand, tMud, tSnow, tCliff, tReeds, tLily: UInt8

    public init(seed: Int) {
        self.seed = seed
        nElev = Noise(seed: seed + 1, frequency: 0.0035, octaves: 4)
        nTemp = Noise(seed: seed + 2, frequency: 0.0005, octaves: 2)
        nMoist = Noise(seed: seed + 3, frequency: 0.002, octaves: 3)
        nRiver = Noise(seed: seed + 4, frequency: 0.005, octaves: 2)
        nForest = Noise(seed: seed + 5, frequency: 0.035, octaves: 2)
        nDetail = Noise(seed: seed + 6, frequency: 0.09, octaves: 1)
        let c = Content.shared
        tDeep = c.tid("deep_water"); tWater = c.tid("water"); tShallow = c.tid("shallow_water"); tIce = c.tid("ice")
        tSand = c.tid("sand"); tMud = c.tid("mud"); tSnow = c.tid("snow"); tCliff = c.tid("cliff"); tReeds = c.tid("reeds"); tLily = c.tid("lily_pad")
        func cum(_ l: [(String, Double)]) -> [(UInt8, Double)] {
            var acc = 0.0
            return l.map { acc += $0.1; return (c.tid($0.0), acc) }
        }
        for b in c.biomes {
            ground.append(c.tid(b.ground)); alt.append(c.tid(b.alt)); altCh.append(b.altChance); density.append(b.treeDensity)
            trees.append(cum(b.trees)); objects.append(cum(b.objects)); decor.append(cum(b.decor))
        }
    }

    /// (elevation, temperature, moisture)
    public func climate(_ wx: Int, _ wy: Int) -> (Double, Double, Double) {
        let x = Double(wx), y = Double(wy)
        return (0.5 + elevBias + 0.62 * nElev.get(x, y), min(1, max(0, 0.5 + tempBias + 1.0 * nTemp.get(x, y))), min(1, max(0, 0.5 + moistBias + 0.85 * nMoist.get(x, y))))
    }

    public func biome(_ wx: Int, _ wy: Int) -> Int {
        let c = climate(wx, wy)
        return Biome.classify(c.0, c.1, c.2)
    }

    public func isRiver(_ wx: Int, _ wy: Int, _ e: Double) -> Bool {
        e >= Biome.sea && e < Biome.mountainLevel && abs(nRiver.get(Double(wx), Double(wy))) < 0.012
    }

    /// The underground: rock everywhere, tunnels and caverns cut by noise, lakes
    /// in the low places, ore in the walls, and now and then a ruin with a chest.
    func generateCave(_ cx: Int, _ cy: Int) -> Chunk {
        let c = Chunk(cx: cx, cy: cy)
        let ct = Content.shared
        let floor = ct.tid("cave_floor"), wall = ct.tid("cave_wall"), lake = ct.tid("cave_water")
        let ores: [(UInt8, Double)] = [(ct.tid("ore_iron"), 0.05), (ct.tid("ore_copper"), 0.08), (ct.tid("ore_moon"), 0.09), (ct.tid("ore_gold"), 0.10)]
        var g = [UInt8](repeating: floor, count: MP.chunkArea), st = [UInt8](repeating: 0, count: MP.chunkArea), ob = st, de = st
        for ty in 0..<32 { for tx in 0..<32 {
            let wx = cx * 32 + tx, wy = cy * 32 + ty
            let x = Double(wx), y = Double(wy)
            let tunnel = abs(nForest.get(x * 0.5, y * 0.5)), cavern = nMoist.get(x * 6, y * 6), wet = nRiver.get(x * 2, y * 2)
            let open = tunnel < 0.16 || cavern > 0.22
            let i = ty * 32 + tx
            if !open {
                let r = Double(MP.h2(seed &+ 31, wx, wy) & 0xffff) / 65536.0
                ob[i] = ores.first { r < $0.1 }?.0 ?? wall
            } else if cavern > 0.3 && wet > 0.25 {
                g[i] = lake
            } else if MP.h01(seed &+ 5, wx, wy) < 0.012 { de[i] = ct.tid("mushroom") }
        } }
        // one ruin in every 3x3 block of chunks
        let rx = Int((Double(cx) / 3).rounded(.down)), ry = Int((Double(cy) / 3).rounded(.down))
        let h = MP.h2(seed &+ 555, rx, ry)
        if rx * 3 + Int(h % 3) == cx && ry * 3 + Int((h >> 8) % 3) == cy {
            let rwall = ct.tid("ruin_wall"), rfloor = ct.tid("ruin_floor")
            for y in 10...20 { for x in 10...20 {
                let i = y * 32 + x
                let edge = x == 10 || x == 20 || y == 10 || y == 20
                g[i] = rfloor; de[i] = 0
                ob[i] = edge && !(x == 15 && (y == 10 || y == 20)) ? rwall : 0
            } }
            ob[15 * 32 + 15] = ct.tid("chest")
            for (x, y) in [(15, 9), (15, 8), (15, 21), (15, 22)] { ob[y * 32 + x] = 0; g[y * 32 + x] = floor }
        }
        c.layers = [g, st, ob, de]
        return c
    }

    public func isUnderRuin(_ cx: Int, _ cy: Int) -> Bool {
        let rx = Int((Double(cx) / 3).rounded(.down)), ry = Int((Double(cy) / 3).rounded(.down))
        let h = MP.h2(seed &+ 555, rx, ry)
        return rx * 3 + Int(h % 3) == cx && ry * 3 + Int((h >> 8) % 3) == cy
    }

    public func generate(_ cx: Int, _ cy: Int) -> Chunk {
        if depth > 0 { return generateCave(cx, cy) }
        let c = Chunk(cx: cx, cy: cy)
        var g = [UInt8](repeating: 0, count: MP.chunkArea), st = g, ob = g, de = g
        let bx = cx * 32, by = cy * 32
        let solid = content.solid
        for ty in 0..<32 {
            let wy = by + ty
            for tx in 0..<32 {
                let wx = bx + tx
                let x = Double(wx), y = Double(wy)
                let dn = nDetail.get(x, y)
                let e = 0.5 + elevBias + 0.62 * nElev.get(x, y) + dn * 0.006
                let t = min(1, max(0, 0.5 + tempBias + 1.0 * nTemp.get(x, y) + dn * 0.012))
                let m = min(1, max(0, 0.5 + moistBias + 0.85 * nMoist.get(x, y) + dn * 0.012))
                let fo = nForest.get(x, y)
                let b = Biome.classify(e, t, m)
                let h = MP.h2(seed, wx, wy)
                let r1 = Double(h & 0xffff) / 65536.0
                let r2 = Double((h >> 16) & 0xffff) / 65536.0
                let idx = ty * 32 + tx
                var gr: UInt8 = 0
                var natural = true
                var cliff = false
                if b == Biome.ocean {
                    natural = false
                    if t < 0.27 && e > Biome.sea - 0.035 { gr = tIce }
                    else if e < Biome.sea - 0.05 { gr = tDeep }
                    else if e < Biome.sea - 0.012 { gr = tWater }
                    else { gr = tShallow }
                } else {
                    gr = r2 < altCh[b] ? alt[b] : ground[b]
                    if b == Biome.mountain {
                        if t < 0.36 { gr = tSnow }
                        cliff = e > Biome.mountainLevel + 0.012 && abs(fo) > 0.10
                    } else if b == Biome.canyon {
                        cliff = fo > 0.26
                    } else if b == Biome.wetland && fo < -0.22 {
                        gr = tShallow
                        natural = false
                        if r2 < 0.12 { de[idx] = tLily }
                    }
                    let rv = abs(nRiver.get(x, y))
                    if e < Biome.mountainLevel && rv < 0.022 {
                        cliff = false
                        natural = false
                        if rv < 0.012 {
                            gr = t < 0.27 ? tIce : (rv > 0.008 ? tShallow : tWater)
                            de[idx] = 0
                        } else if t >= 0.30 {
                            gr = b == Biome.wetland ? tMud : tSand
                            if t < 0.7 && r2 < 0.2 { de[idx] = tReeds }
                        }
                    }
                }
                g[idx] = gr
                if cliff {
                    st[idx] = tCliff
                } else if natural && !solid[Int(gr)] {
                    let dens = min(0.30, density[b] * min(2.4, max(0.15, 1.0 + fo * 2.2)))
                    if r1 < dens {
                        let tr = trees[b]
                        if let last = tr.last {
                            let pick = Double((h >> 8) & 0xff) / 256.0 * last.1
                            ob[idx] = tr.first { pick < $0.1 }?.0 ?? last.0
                        }
                    } else {
                        let rr = r1 - dens
                        if let o = objects[b].first(where: { rr < $0.1 }) {
                            ob[idx] = o.0
                        } else if let d = decor[b].first(where: { r2 < $0.1 }) {
                            de[idx] = d.0
                        }
                    }
                }
            }
        }
        if isMaze(cx, cy) { carveMaze(cx, cy, &g, &st, &ob, &de) }
        c.layers = [g, st, ob, de]
        return c
    }

    /// One chunk in every 6x6 block of chunks holds an old maze - if it stands on
    /// land and is not near where the first villages are founded.
    public func isMaze(_ cx: Int, _ cy: Int) -> Bool {
        if depth > 0 { return false }
        let rx = Int((Double(cx) / 6).rounded(.down)), ry = Int((Double(cy) / 6).rounded(.down))
        let h = MP.h2(seed &+ 77, rx, ry)
        if rx * 6 + Int(h % 6) != cx || ry * 6 + Int((h >> 8) % 6) != cy { return false }
        if abs(cx) <= 3 && abs(cy) <= 3 { return false }
        let e = climate(cx * 32 + 16, cy * 32 + 16).0
        return e > Biome.sea + 0.03 && e < Biome.mountainLevel - 0.03
    }

    func carveMaze(_ cx: Int, _ cy: Int, _ g: inout [UInt8], _ st: inout [UInt8], _ ob: inout [UInt8], _ de: inout [UInt8]) {
        let c = Content.shared
        let wall = c.tid("ruin_wall"), floor = c.tid("ruin_floor"), chest = c.tid("chest"), torch = c.tid("torch"), bones = c.tid("bones")
        var r = RNG(seed: Int(MP.h2(seed &+ 991, cx, cy)))
        // 15 x 15 cells on odd coordinates of a 31 x 31 grid; depth-first carving
        var open = [Bool](repeating: false, count: 31 * 31)
        var stack = [(1, 1)]
        open[1 * 31 + 1] = true
        while let cur = stack.last {
            var opts: [(Int, Int)] = []
            for (dx, dy) in [(2, 0), (-2, 0), (0, 2), (0, -2)] {
                let nx = cur.0 + dx, ny = cur.1 + dy
                if nx > 0 && ny > 0 && nx < 30 && ny < 30 && !open[ny * 31 + nx] { opts.append((nx, ny)) }
            }
            if opts.isEmpty { stack.removeLast(); continue }
            let n = opts[r.index(opts.count)]
            open[((cur.1 + n.1) / 2) * 31 + (cur.0 + n.0) / 2] = true
            open[n.1 * 31 + n.0] = true
            stack.append(n)
        }
        for y in 14...16 { for x in 14...16 { open[y * 31 + x] = true } }      // treasure room
        open[30 * 31 + 15] = true; open[29 * 31 + 15] = true                   // south gate
        open[0 * 31 + 15] = true; open[1 * 31 + 15] = true                     // north gate
        for y in 0..<31 { for x in 0..<31 {
            let i = y * 32 + x
            g[i] = floor; st[i] = 0; de[i] = 0
            ob[i] = open[y * 31 + x] ? 0 : wall
            if open[y * 31 + x] && r.unit() < 0.03 { de[i] = bones }
            if open[y * 31 + x] && r.unit() < 0.02 { ob[i] = torch }
        } }
        ob[15 * 32 + 15] = chest
    }
}

/// Asks the device how much memory it has and derives the cache limits.
public struct MemoryBudget {
    public var physicalMB = 0, availableMB = 0, budgetMB = 256, maxChunks = 1024, maxAgents = 300, maxSettlements = 12, overrideMB = 0
    public static let chunkBytes = 12 * 1024, minMB = 96, maxAutoMB = 2048

    public static func deviceMemory() -> (physicalMB: Int, availableMB: Int) {
        let phys = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        var avail = phys / 2
        #if os(iOS)
        let a = Int(os_proc_available_memory() / 1_048_576)
        if a > 0 { avail = a }
        #endif
        return (phys, avail)
    }

    public init(overrideMB: Int = 0) {
        let d = MemoryBudget.deviceMemory()
        physicalMB = d.physicalMB
        availableMB = d.availableMB
        self.overrideMB = overrideMB
        if overrideMB > 0 {
            budgetMB = max(MemoryBudget.minMB, overrideMB)
        } else {
            budgetMB = min(MemoryBudget.maxAutoMB, max(MemoryBudget.minMB, min(availableMB / 3, physicalMB / 6)))
        }
        maxChunks = min(60000, max(256, budgetMB * 1_048_576 * 4 / 10 / MemoryBudget.chunkBytes))
        maxAgents = min(1200, max(150, budgetMB))
        maxSettlements = min(200, max(6, maxChunks / 24))
    }

    /// Resident memory of this process in MB (0 when unknown).
    public static func usedMB() -> Int {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : 0
        #else
        if let s = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8), let pages = Int(s.split(separator: " ").dropFirst().first ?? "") {
            return pages * 4096 / 1_048_576
        }
        return 0
        #endif
    }

    public func pressure() -> Double { Double(MemoryBudget.usedMB()) / Double(max(1, budgetMB)) }
}

/// Unbounded world: on-demand chunks, memory-bounded LRU cache with disk-backed
/// edits, and a self-expanding one-byte-per-chunk survey map.
public final class OpenWorld {
    public static let region = 64
    public let seed: Int
    public let content = Content.shared
    public let gen: Generator
    public var budget: MemoryBudget
    public private(set) var cache: [Int64: Chunk] = [:]
    public private(set) var pins: [Int64: Int] = [:]
    public private(set) var regions: [TilePos: [UInt8]] = [:]
    public private(set) var surveyed = 0, generated = 0, evicted = 0
    public var time = 0.3 * MP.daySeconds
    public var nextPropID = 1
    public var directory: URL?
    var saved: Set<Int64> = []
    /// Size on disk of every saved chunk file (bytes), kept up to date on every write.
    private var fileSizes: [Int64: Int] = [:]
    public private(set) var diskBytes = 0
    /// Hard cap for the saved map. Default 5 GB.
    public var diskLimitBytes = 5 * 1024 * 1024 * 1024
    public private(set) var prunedFiles = 0
    /// Chunk files that could not be written (disk full, folder gone). A save that raises this has failed.
    public private(set) var writeFailures = 0
    var natural: Chunk?
    var naturalKey: Int64 = .min
    var clock = 0
    var ring: [TilePos: Int] = [:]
    var timerAcc = 0.0
    public var onTileChanged: [(Int, Int, Int, UInt8, UInt8) -> Void] = []
    public var onChunkChanged: [(Int, Int) -> Void] = []

    /// 0 is the surface; 1 is the underground layer with its own chunks and files.
    public let depth: Int
    var folder: String { depth == 0 ? "chunks" : "chunks_d\(depth)" }

    public init(seed: Int, budget: MemoryBudget, depth: Int = 0) {
        self.seed = seed
        self.budget = budget
        self.depth = depth
        gen = Generator(seed: seed)
        gen.depth = depth
    }

    public func open(directory dir: URL) {
        directory = dir
        let chunks = dir.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true)
        for f in (try? FileManager.default.contentsOfDirectory(atPath: chunks.path)) ?? [] where f.hasSuffix(".json") {
            let p = f.dropLast(5).split(separator: "_")
            if p.count == 3, let x = Int(p[1]), let y = Int(p[2]) {
                let k = MP.chunkKey(x, y)
                saved.insert(k)
                let size = ((try? FileManager.default.attributesOfItem(atPath: chunks.appendingPathComponent(f).path)[.size]) as? NSNumber)?.intValue ?? 0
                fileSizes[k] = size
                diskBytes += size
            }
        }
    }

    func path(_ cx: Int, _ cy: Int) -> URL? { directory?.appendingPathComponent("\(folder)/c_\(cx)_\(cy).json") }

    // MARK: time
    public var year: Int { Int(time / MP.year) }
    public var hour: Double { time.truncatingRemainder(dividingBy: MP.daySeconds) / MP.daySeconds * 24.0 }
    public var isNight: Bool { let h = hour; return h < 5.5 || h >= 20.5 }
    public var daylight: Double {
        let h = hour
        if h < 4.5 || h >= 21.0 { return 0 }
        if h < 7.0 { return (h - 4.5) / 2.5 }
        if h < 18.5 { return 1 }
        return 1.0 - (h - 18.5) / 2.5
    }

    public func advance(_ dt: Double) {
        time += dt
        timerAcc += dt
        if timerAcc >= 2.0 {
            timerAcc = 0
            for c in cache.values where !c.timers.isEmpty { processTimers(c) }
        }
    }

    // MARK: chunks
    @discardableResult public func chunk(_ cx: Int, _ cy: Int) -> Chunk {
        let k = MP.chunkKey(cx, cy)
        clock += 1
        if let c = cache[k] { c.lastUsed = clock; return c }
        var c: Chunk?
        if saved.contains(k), let url = path(cx, cy), let data = try? Data(contentsOf: url) { c = Chunk.decode(data) }
        if c == nil { c = gen.generate(cx, cy); generated += 1 }
        let ch = c!
        cache[k] = ch
        ch.lastUsed = clock
        mark(cx, cy)
        if !ch.timers.isEmpty { processTimers(ch) }
        return ch
    }

    public func loaded(_ cx: Int, _ cy: Int) -> Bool { cache[MP.chunkKey(cx, cy)] != nil }
    public func pin(_ cx: Int, _ cy: Int) { pins[MP.chunkKey(cx, cy), default: 0] += 1; chunk(cx, cy) }
    public func unpin(_ cx: Int, _ cy: Int) {
        let k = MP.chunkKey(cx, cy)
        if let n = pins[k] { if n <= 1 { pins[k] = nil } else { pins[k] = n - 1 } }
    }

    func write(_ c: Chunk) -> Bool {
        guard let url = path(c.cx, c.cy) else { return !c.modified }
        let data = c.encoded()
        do { try data.write(to: url, options: .atomic) } catch { writeFailures += 1; return false }
        c.dirty = false
        saved.insert(c.key)
        diskBytes += data.count - (fileSizes[c.key] ?? 0)
        fileSizes[c.key] = data.count
        if diskBytes > diskLimitBytes { enforceDiskLimit() }
        return true
    }

    /// Estimated memory used by cached chunk data (bytes).
    public var memoryBytes: Int { cache.count * MemoryBudget.chunkBytes + regions.count * OpenWorld.region * OpenWorld.region }

    /// Keeps the saved map under `diskLimitBytes`: the oldest chunk files that
    /// are not pinned (no living settlement there) and not currently loaded are
    /// removed; those areas return to their natural, regenerated state.
    @discardableResult public func enforceDiskLimit() -> Int {
        guard let dir = directory, diskBytes > diskLimitBytes else { return 0 }
        let target = diskLimitBytes * 9 / 10
        var cands: [(Int64, Date)] = []
        for k in saved where pins[k] == nil && cache[k] == nil {
            guard let url = path(MP.keyCX(k), MP.keyCY(k)) else { continue }
            let date = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date) ?? .distantPast
            cands.append((k, date))
        }
        cands.sort { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var removed = 0
        for (k, _) in cands {
            if diskBytes <= target { break }
            guard let url = path(MP.keyCX(k), MP.keyCY(k)) else { continue }
            try? FileManager.default.removeItem(at: url)
            diskBytes -= fileSizes[k] ?? 0
            fileSizes[k] = nil
            saved.remove(k)
            removed += 1
        }
        _ = dir
        prunedFiles += removed
        return removed
    }

    /// Keep the cache inside the memory budget (least recently used first).
    @discardableResult public func maintain() -> Int {
        var limit = budget.maxChunks
        if budget.pressure() > 1.0 { limit = max(pins.count + 64, cache.count * 7 / 10) }
        if cache.count <= limit { return 0 }
        let list = cache.values.filter { pins[$0.key] == nil }.sorted { $0.lastUsed < $1.lastUsed }
        var removed = 0
        let target = limit * 9 / 10
        for c in list {
            if cache.count <= target { break }
            if c.dirty && !write(c) { continue }
            cache[c.key] = nil
            removed += 1
        }
        evicted += removed
        return removed
    }

    /// One-tap cleanup: drop everything that is neither pinned nor in `keep`.
    @discardableResult public func purge(keep: Set<Int64> = []) -> Int {
        var removed = 0
        for (k, c) in cache where pins[k] == nil && !keep.contains(k) {
            if c.dirty && !write(c) { continue }
            cache[k] = nil
            removed += 1
        }
        evicted += removed
        return removed
    }

    @discardableResult public func saveAll() -> Int {
        var n = 0
        for c in cache.values where c.dirty { if write(c) { n += 1 } }
        return n
    }

    // MARK: survey
    static func floorDiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }
    static func posMod(_ a: Int, _ b: Int) -> Int { ((a % b) + b) % b }

    @discardableResult func mark(_ cx: Int, _ cy: Int) -> Bool {
        let R = OpenWorld.region
        let rk = TilePos(OpenWorld.floorDiv(cx, R), OpenWorld.floorDiv(cy, R))
        var r = regions[rk] ?? [UInt8](repeating: 0, count: R * R)
        let i = OpenWorld.posMod(cy, R) * R + OpenWorld.posMod(cx, R)
        if r[i] != 0 { return false }
        r[i] = UInt8(gen.biome(cx * 32 + 16, cy * 32 + 16) + 1)
        regions[rk] = r
        surveyed += 1
        return true
    }

    public func known(_ cx: Int, _ cy: Int) -> UInt8 {
        let R = OpenWorld.region
        guard let r = regions[TilePos(OpenWorld.floorDiv(cx, R), OpenWorld.floorDiv(cy, R))] else { return 0 }
        return r[OpenWorld.posMod(cy, R) * R + OpenWorld.posMod(cx, R)]
    }

    /// Explore up to `count` new chunks in growing rings; no terrain is generated.
    @discardableResult public func survey(center: TilePos, count: Int, maxRadius: Int = 4096) -> Int {
        var r = ring[center] ?? 0
        var done = 0
        while done < count && r <= maxRadius {
            var unknownLeft = false
            for dy in -r...r {
                let step = abs(dy) == r ? 1 : max(1, 2 * r)
                var dx = -r
                while dx <= r {
                    if known(center.x + dx, center.y + dy) == 0 {
                        if done < count { mark(center.x + dx, center.y + dy); done += 1 } else { unknownLeft = true }
                    }
                    dx += step
                }
            }
            if unknownLeft { break }
            r += 1
        }
        ring[center] = r
        return done
    }

    // MARK: tiles
    @inline(__always) static func idx(_ wx: Int, _ wy: Int) -> Int { (wy & 31) * 32 + (wx & 31) }

    public func tile(_ layer: Int, _ wx: Int, _ wy: Int) -> UInt8 { chunk(wx >> 5, wy >> 5).layers[layer][OpenWorld.idx(wx, wy)] }

    public func blocked(_ wx: Int, _ wy: Int) -> Bool {
        let c = chunk(wx >> 5, wy >> 5)
        let i = OpenWorld.idx(wx, wy)
        let o = Int(c.layers[2][i])
        if o != 0 && content.solid[o] { return true }
        let s = Int(c.layers[1][i])
        if s != 0 {
            if content.solid[s] { return true }
            if content.bridge[s] { return false }
        }
        return content.solid[Int(c.layers[0][i])]
    }

    public func isLand(_ wx: Int, _ wy: Int) -> Bool {
        !content.water[Int(tile(0, wx, wy))] && !content.solid[Int(tile(1, wx, wy))]
    }

    public func setTile(_ layer: Int, _ wx: Int, _ wy: Int, _ id: UInt8) {
        let c = chunk(wx >> 5, wy >> 5)
        let i = OpenWorld.idx(wx, wy)
        let old = c.layers[layer][i]
        if old == id { return }
        c.layers[layer][i] = id
        c.touch()
        c.timers.removeAll { $0.i == i && $0.l == layer }
        if id != 0, let t = content.tile(id), !t.growTo.isEmpty {
            c.timers.append(GrowTimer(i: i, l: layer, to: content.tid(t.growTo), due: time + t.growTime, expect: id))
        }
        for f in onTileChanged { f(wx, wy, layer, old, id) }
        for f in onChunkChanged { f(c.cx, c.cy) }
    }

    public func schedule(_ wx: Int, _ wy: Int, layer: Int, to: UInt8, delay: Double, expect: UInt8) {
        let c = chunk(wx >> 5, wy >> 5)
        c.timers.append(GrowTimer(i: OpenWorld.idx(wx, wy), l: layer, to: to, due: time + delay, expect: expect))
        c.touch()
    }

    /// Growth catches up from due times, so plants keep growing while evicted.
    func processTimers(_ c: Chunk) {
        var n = 0, guardCount = 0, changed = false
        while n < c.timers.count && guardCount < 4096 {
            guardCount += 1
            let tm = c.timers[n]
            if tm.due > time { n += 1; continue }
            c.timers.remove(at: n)
            if c.layers[tm.l][tm.i] != tm.expect { continue }
            let old = c.layers[tm.l][tm.i]
            c.layers[tm.l][tm.i] = tm.to
            c.touch()
            changed = true
            if tm.to != 0, let t = content.tile(tm.to), !t.growTo.isEmpty {
                c.timers.append(GrowTimer(i: tm.i, l: tm.l, to: content.tid(t.growTo), due: tm.due + t.growTime, expect: tm.to))
            }
            for f in onTileChanged { f(c.cx * 32 + tm.i % 32, c.cy * 32 + tm.i / 32, tm.l, old, tm.to) }
        }
        if changed { for f in onChunkChanged { f(c.cx, c.cy) } }
    }

    // MARK: permanent deletion (world laws) - unlike cache cleaning, this destroys saved data
    /// Chunks that exist as files, sorted.
    public var storedChunks: [Int64] { saved.sorted() }
    public func storedSize(_ key: Int64) -> Int { fileSizes[key] ?? 0 }
    /// Decode a stored chunk without putting it in the cache.
    public func peekStored(_ key: Int64) -> Chunk? {
        if let c = cache[key] { return c }
        guard saved.contains(key), let url = path(MP.keyCX(key), MP.keyCY(key)), let data = try? Data(contentsOf: url) else { return nil }
        return Chunk.decode(data)
    }

    /// Forget every change ever made to a chunk: its file is deleted and, if it
    /// is in use, it is regenerated in place. Returns the bytes freed on disk.
    @discardableResult public func revertChunk(_ cx: Int, _ cy: Int) -> Int {
        let k = MP.chunkKey(cx, cy)
        var freed = 0
        if saved.contains(k) {
            if let url = path(cx, cy) { try? FileManager.default.removeItem(at: url) }
            freed = fileSizes[k] ?? 0
            diskBytes -= freed
            fileSizes[k] = nil
            saved.remove(k)
        }
        if cache[k] != nil {
            if pins[k] != nil {
                let fresh = gen.generate(cx, cy)
                fresh.lastUsed = clock
                cache[k] = fresh
            } else { cache[k] = nil }
            for f in onChunkChanged { f(cx, cy) }
        }
        return freed
    }

    /// Put the ground layer of one tile back to what the generator made.
    public func restoreGround(_ wx: Int, _ wy: Int) {
        let cx = wx >> 5, cy = wy >> 5
        let k = MP.chunkKey(cx, cy)
        if naturalKey != k { natural = gen.generate(cx, cy); naturalKey = k }
        if let n = natural { setTile(0, wx, wy, n.layers[0][OpenWorld.idx(wx, wy)]) }
    }

    /// Put one tile back to what the generator made there (all four layers).
    public func restoreNatural(_ wx: Int, _ wy: Int) {
        let cx = wx >> 5, cy = wy >> 5
        let k = MP.chunkKey(cx, cy)
        if naturalKey != k { natural = gen.generate(cx, cy); naturalKey = k }
        guard let n = natural else { return }
        let i = OpenWorld.idx(wx, wy)
        for l in 0..<4 { setTile(l, wx, wy, n.layers[l][i]) }
    }

    /// Delete every chunk file and forget the whole map (used by Genesis).
    @discardableResult public func wipe() -> Int {
        let freed = diskBytes
        for k in saved { if let url = path(MP.keyCX(k), MP.keyCY(k)) { try? FileManager.default.removeItem(at: url) } }
        saved.removeAll(); fileSizes.removeAll(); diskBytes = 0
        cache.removeAll(); pins.removeAll(); regions.removeAll(); ring.removeAll()
        surveyed = 0
        return freed
    }

    @discardableResult public func removeProp(id: Int, cx: Int, cy: Int) -> Bool {
        let c = chunk(cx, cy)
        guard let i = c.props.firstIndex(where: { $0.id == id }) else { return false }
        c.props.remove(at: i)
        c.touch()
        for f in onChunkChanged { f(cx, cy) }
        return true
    }

    // MARK: props
    @discardableResult public func addProp(key: String, at p: Vec2) -> Int {
        let c = chunk(Int((p.x / 512).rounded(.down)), Int((p.y / 512).rounded(.down)))
        let id = nextPropID
        nextPropID += 1
        c.props.append(Prop(id: id, key: key, x: p.x, y: p.y))
        c.touch()
        return id
    }

    public func removeProp(near p: Vec2, radius: Double = 14) -> Bool {
        let cx = Int((p.x / 512).rounded(.down)), cy = Int((p.y / 512).rounded(.down))
        for dy in -1...1 { for dx in -1...1 {
            let c = chunk(cx + dx, cy + dy)
            if let i = c.props.firstIndex(where: { Vec2($0.x, $0.y).distance(to: p) <= radius }) {
                c.props.remove(at: i)
                c.touch()
                return true
            }
        } }
        return false
    }

    public func findFree(near t: TilePos, maxR: Int = 12) -> TilePos {
        for r in 0...maxR { for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
            if !blocked(t.x + dx, t.y + dy) { return TilePos(t.x + dx, t.y + dy) }
        } } }
        return t
    }

    /// Dry-land spot for a camp, searched deterministically around `from`.
    public func findSite(from: TilePos, minR: Double, maxR: Double, salt: Int, avoid: [TilePos], avoidDist: Double) -> TilePos {
        for k in 0..<240 {
            let ang = MP.h01(seed + salt, k, 1) * 2 * Double.pi
            let rad = minR + (maxR - minR) * MP.h01(seed + salt, k, 2)
            let p = TilePos(from.x + Int(cos(ang) * rad), from.y + Int(sin(ang) * rad))
            let b = gen.biome(p.x, p.y)
            if b == Biome.ocean || b == Biome.mountain || b == Biome.canyon { continue }
            // the first two thirds of the attempts insist on green land with timber nearby
            if k < 160 && (b == Biome.desert || b == Biome.snow || b == Biome.beach) { continue }
            if avoid.contains(where: { Double(($0 - p).lengthSquared).squareRoot() < avoidDist }) { continue }
            var mazeNear = false
            for my in -1...1 { for mx in -1...1 where gen.isMaze((p.x >> 5) + mx, (p.y >> 5) + my) { mazeNear = true } }
            if mazeNear { continue }
            // every tile of the village core must be dry, walkable ground:
            // a river through the square would cut the villagers off from each other
            var dry = true
            outer: for dy in -14...14 { for dx in -14...14 {
                let c = gen.climate(p.x + dx, p.y + dy)
                if c.0 < Biome.sea + 0.012 || c.0 > Biome.mountainLevel - 0.01 || abs(gen.nRiver.get(Double(p.x + dx), Double(p.y + dy))) < 0.024 { dry = false; break outer }
            } }
            if dry { return p }
        }
        return .none
    }

    // MARK: persistence
    public struct Snapshot: Codable {
        public var seed: Int, time: Double, nextPropID: Int, regions: [String: Data]
    }

    public func snapshot() -> Snapshot {
        var reg: [String: Data] = [:]
        for (k, v) in regions { reg["\(k.x),\(k.y)"] = Data(v) }
        return Snapshot(seed: seed, time: time, nextPropID: nextPropID, regions: reg)
    }

    public func restore(_ s: Snapshot) {
        time = s.time
        nextPropID = s.nextPropID
        regions.removeAll()
        surveyed = 0
        let R = OpenWorld.region
        for (k, v) in s.regions {
            let p = k.split(separator: ",")
            if p.count == 2, let x = Int(p[0]), let y = Int(p[1]), v.count == R * R {
                regions[TilePos(x, y)] = [UInt8](v)
                surveyed += v.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
            }
        }
    }
}
