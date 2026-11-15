import Foundation

// MARK: - fixed simulation step

/// Separates the three clocks: the real clock (frames), the game clock (real time x speed) and the
/// simulation clock, which only ever advances in fixed steps. The same game time always gives the same
/// sequence of steps, however the frames fall; what cannot be caught up is dropped and counted, never
/// run as one huge step.
public struct SimClock: Equatable {
    public var step: Double
    /// Most game time that may wait to be simulated; anything beyond it is dropped.
    public var maxBacklog: Double
    public private(set) var backlog = 0.0
    /// Game time that was asked for but dropped because the device could not keep up.
    public private(set) var dropped = 0.0
    public private(set) var simulated = 0.0
    public private(set) var steps = 0

    public init(step: Double = 0.25, maxBacklog: Double = 4) { self.step = step; self.maxBacklog = maxBacklog }

    /// Real seconds passed at `speed`: the game clock moves on.
    public mutating func add(real dt: Double, speed: Double) {
        guard dt > 0, speed > 0 else { return }
        backlog += dt * speed
        if backlog > maxBacklog { dropped += backlog - maxBacklog; backlog = maxBacklog }
    }

    /// Take one fixed step if one is due.
    public mutating func take() -> Bool {
        guard backlog >= step - 1e-9 else { return false }
        backlog -= step; simulated += step; steps += 1
        return true
    }

    /// Run as many due steps as `allowed` says (normally a frame-time budget); returns how many ran.
    @discardableResult public mutating func run(_ allowed: () -> Bool, _ body: (Double) -> Void) -> Int {
        var n = 0
        while backlog >= step - 1e-9 && allowed() { _ = take(); body(step); n += 1 }
        return n
    }

    /// Nothing waits any more (a pause, a law, a world switch).
    public mutating func clear() { backlog = 0 }
}

// MARK: - chunk bitmap baking off the main thread

/// Everything a baked bitmap belongs to. A result is only used if every field still matches.
public struct BakeKey: Hashable {
    public var world: Int        // which open world (changes when another world is opened)
    public var epoch: Int        // map epoch inside the world (Genesis wipes the map)
    public var depth: Int        // surface or underground
    public var chunk: Int64
    public var revision: Int     // the chunk's change counter
    public init(world: Int, epoch: Int, depth: Int, chunk: Int64, revision: Int) {
        self.world = world; self.epoch = epoch; self.depth = depth; self.chunk = chunk; self.revision = revision
    }
    /// Same place, regardless of revision.
    public var slot: BakeSlot { BakeSlot(world: world, epoch: epoch, depth: depth, chunk: chunk) }
}

public struct BakeSlot: Hashable { public var world: Int, epoch: Int, depth: Int, chunk: Int64 }

/// An immutable copy of what is drawn for one chunk: taken on the main thread, baked anywhere.
public struct ChunkSnapshot {
    public let layers: [[UInt8]]
    public init(_ c: Chunk) { layers = c.layers }
    public init(layers: [[UInt8]]) { self.layers = layers }
}

/// Book-keeping for background baking: which chunks are wanted, in what order, which are in flight,
/// and whether a finished result is still current. It does no baking itself, so it is easy to test;
/// the scene feeds it and a background queue does the work.
public final class BakeQueue {
    public private(set) var wanted: [BakeSlot: (key: BakeKey, priority: Double)] = [:]
    public private(set) var inFlight: [BakeSlot: BakeKey] = [:]
    public private(set) var stale = 0, applied = 0, requested = 0, deduped = 0
    public var maxInFlight: Int
    public init(maxInFlight: Int = 2) { self.maxInFlight = maxInFlight }

    /// Ask for a chunk (lower priority value = sooner). Asking again only updates key and priority.
    public func want(_ key: BakeKey, priority: Double) {
        if let f = inFlight[key.slot], f == key { deduped += 1; return }           // that exact revision is being baked
        if wanted[key.slot] != nil { deduped += 1 } else { requested += 1 }
        wanted[key.slot] = (key, priority)
    }

    /// The next jobs to start, best priority first (ties by chunk key so the order is stable).
    public func next() -> [BakeKey] {
        var out: [BakeKey] = []
        let free = maxInFlight - inFlight.count
        guard free > 0 else { return [] }
        let order = wanted.values.filter { inFlight[$0.key.slot] == nil }
            .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.key.chunk < $1.key.chunk }
        for w in order.prefix(free) {
            wanted[w.key.slot] = nil
            inFlight[w.key.slot] = w.key
            out.append(w.key)
        }
        return out
    }

    /// A bake finished. `current` is what the slot should show now; the result is kept only if it matches.
    public func finished(_ key: BakeKey, current: BakeKey?) -> Bool {
        if inFlight[key.slot] == key { inFlight[key.slot] = nil }
        guard let c = current, c == key else { stale += 1; return false }
        applied += 1
        return true
    }

    /// The world, its epoch or the depth changed: nothing waiting is wanted any more.
    public func dropAll() { wanted.removeAll() }
    /// Forget chunks that left the view and were never started.
    public func drop(where f: (BakeSlot) -> Bool) { for k in wanted.keys where f(k) { wanted[k] = nil } }
    public var pending: Int { wanted.count + inFlight.count }
}

// MARK: - byte-budget cache

/// Least-recently-used cache measured in bytes, not entries. Under memory pressure it can be shrunk at once.
public final class ByteLRU<Key: Hashable, Value> {
    private var items: [Key: (value: Value, bytes: Int, used: Int)] = [:]
    private var clock = 0
    public private(set) var bytes = 0, evictions = 0
    public var budget: Int
    public init(budget: Int) { self.budget = budget }

    public var count: Int { items.count }
    public func get(_ k: Key) -> Value? {
        guard var e = items[k] else { return nil }
        clock += 1; e.used = clock; items[k] = e
        return e.value
    }
    public func contains(_ k: Key) -> Bool { items[k] != nil }
    /// Store a value; keys in `keep` (what is on screen right now) are never evicted to make room.
    public func put(_ k: Key, _ v: Value, bytes b: Int, keep: Set<Key> = []) {
        if let old = items[k] { bytes -= old.bytes }
        clock += 1
        items[k] = (v, b, clock)
        bytes += b
        trim(to: budget, keep: keep.union([k]))
    }
    public func remove(_ k: Key) { if let e = items.removeValue(forKey: k) { bytes -= e.bytes } }
    public func trim(to limit: Int, keep: Set<Key> = []) {
        guard bytes > limit else { return }
        for (k, e) in items.sorted(by: { $0.value.used < $1.value.used }) where !keep.contains(k) {
            if bytes <= limit { break }
            items[k] = nil; bytes -= e.bytes; evictions += 1
        }
    }
    public func removeAll() { items.removeAll(); bytes = 0 }
}

// MARK: - spatial index for on-screen queries

/// Agents bucketed by 256-pixel cells. Rebuilt at most once per simulation step, so a frame's
/// on-screen query touches only the cells under the view instead of every resident.
public struct SpatialGrid {
    public static let cell = 256.0
    var cells: [Int64: [Int]] = [:]
    public private(set) var builtAt = -1.0, builtCount = -1, builtSteps = -1
    public init() {}

    static func key(_ x: Double, _ y: Double) -> Int64 { MP.chunkKey(Int((x / cell).rounded(.down)), Int((y / cell).rounded(.down))) }

    mutating func rebuild(_ agents: [Int: Agent], time: Double, steps: Int) {
        cells.removeAll(keepingCapacity: true)
        for (id, a) in agents { cells[SpatialGrid.key(a.pos.x, a.pos.y), default: []].append(id) }
        builtAt = time; builtCount = agents.count; builtSteps = steps
    }

    /// Ids of agents whose cell overlaps the rectangle.
    func ids(minX: Double, minY: Double, maxX: Double, maxY: Double) -> [Int] {
        var out: [Int] = []
        let x0 = Int((minX / SpatialGrid.cell).rounded(.down)), x1 = Int((maxX / SpatialGrid.cell).rounded(.down))
        let y0 = Int((minY / SpatialGrid.cell).rounded(.down)), y1 = Int((maxY / SpatialGrid.cell).rounded(.down))
        if (x1 - x0 + 1) * (y1 - y0 + 1) > 4096 { return cells.values.flatMap { $0 } }
        for cy in y0...y1 { for cx in x0...x1 { if let c = cells[MP.chunkKey(cx, cy)] { out.append(contentsOf: c) } } }
        return out
    }
}
