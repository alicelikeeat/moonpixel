import Foundation

/// Transactional world storage.
///
/// Layout inside a world folder:
///   objects/ab/<hash>-<size>.bin   immutable content-addressed blobs (chunks, the index, the meta)
///   gen/g<N>.json                  one manifest per committed generation: which blob holds what
///   HEAD                           the number of the current generation (replaced atomically)
///
/// A commit writes new blobs, then the manifest of generation N+1, verifies both, and only then
/// replaces HEAD. A failure or a crash at any point leaves HEAD on the last complete generation,
/// so a reopened world is always either the whole old state or the whole new one - never a mix.
/// Unchanged chunks are shared between generations (no copying). The generation before HEAD is
/// kept for a while; garbage collection removes everything else and is safe to repeat or interrupt.
public enum SaveFault: String, Codable, CaseIterable {
    case objectWrite, indexWrite, manifestWrite, headSwitch, cleanup
}

public struct SaveError: Error, CustomStringConvertible {
    public let step: SaveFault
    public let detail: String
    public var description: String { "\(step.rawValue): \(detail)" }
}

public struct StoreEntry: Codable, Equatable {
    public var o: String        // blob name
    public var s: Int           // size in bytes
    public var t: Double        // when this content was written (seconds since 1970)
}

public struct Manifest: Codable, Equatable {
    public var gen: Int
    public var format: Int
    public var prev: Int?
    public var created: Double
    public var chunks: [String: StoreEntry]
    public var index: StoreEntry?
    public var meta: StoreEntry?
}

/// Everything one commit needs, taken on the main thread from a consistent moment.
/// Writing it touches only the file system and this value, so it can run on a background queue.
public struct SaveBatch {
    public let base: Manifest?
    public let changes: [String: Data?]          // key -> new content, or nil = deleted
    public let index: Data
    public let meta: Data
    public let stamp: Double
    let pendingMarks: [String: Int]               // which pending versions this batch carries
}

public final class WorldStore {
    public let dir: URL
    /// Generation that HEAD points at (0 when nothing was ever committed).
    public private(set) var head: Manifest?
    /// Generations kept alive besides HEAD (for a short-term fallback).
    public private(set) var recoveredFrom: Int?
    /// Faults to inject, for tests: `failAt` throws before the step, `crashAfter` throws right after it.
    public var failAt: Set<SaveFault> = []
    public var crashAfter: Set<SaveFault> = []
    public static let format = 3

    /// Changes not yet committed. Reads see these first.
    private var pending: [String: Data?] = [:]
    private var pendingVersion: [String: Int] = [:]
    private var version = 0
    private let lock = NSLock()

    var objects: URL { dir.appendingPathComponent("objects", isDirectory: true) }
    var gens: URL { dir.appendingPathComponent("gen", isDirectory: true) }
    var headURL: URL { dir.appendingPathComponent("HEAD") }

    public init(directory: URL) {
        dir = directory
        let fm = FileManager.default
        try? fm.createDirectory(at: objects, withIntermediateDirectories: true)
        try? fm.createDirectory(at: gens, withIntermediateDirectories: true)
        head = recover()
    }

    // MARK: keys
    public static func key(_ depth: Int, _ chunk: Int64) -> String { "\(depth):\(MP.keyCX(chunk)):\(MP.keyCY(chunk))" }
    static func parse(_ key: String) -> (Int, Int64)? {
        let p = key.split(separator: ":")
        guard p.count == 3, let d = Int(p[0]), let x = Int(p[1]), let y = Int(p[2]) else { return nil }
        return (d, MP.chunkKey(x, y))
    }

    // MARK: reading the current view (committed + pending)
    public func read(_ key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        if let p = pending[key] { return p }
        guard let e = head?.chunks[key] else { return nil }
        return try? Data(contentsOf: blobURL(e.o))
    }

    public func size(_ key: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        if let p = pending[key] { return p?.count ?? 0 }
        return head?.chunks[key]?.s ?? 0
    }

    public func stamp(_ key: String) -> Double {
        lock.lock(); defer { lock.unlock() }
        if pending[key] != nil { return Date().timeIntervalSince1970 }
        return head?.chunks[key]?.t ?? 0
    }

    /// Chunk keys stored for one depth, in the current view.
    public func chunks(depth: Int) -> [Int64] {
        lock.lock(); defer { lock.unlock() }
        var set = Set<Int64>()
        for k in (head?.chunks ?? [:]).keys { if let (d, c) = WorldStore.parse(k), d == depth { set.insert(c) } }
        for (k, v) in pending { if let (d, c) = WorldStore.parse(k), d == depth { if v == nil { set.remove(c) } else { set.insert(c) } } }
        return set.sorted()
    }

    public var hasPending: Bool { lock.lock(); defer { lock.unlock() }; return !pending.isEmpty }
    public var headGen: Int { head?.gen ?? 0 }

    /// Bytes of everything the current view refers to (shared blobs counted once).
    public var viewBytes: Int {
        lock.lock(); defer { lock.unlock() }
        var seen = Set<String>()
        var n = 0
        for (k, e) in head?.chunks ?? [:] where pending[k] == nil { if seen.insert(e.o).inserted { n += e.s } }
        for (_, v) in pending { n += v?.count ?? 0 }
        n += (head?.index?.s ?? 0) + (head?.meta?.s ?? 0)
        return n
    }

    // MARK: changing the current view (nothing is durable until a commit)
    public func stage(_ key: String, _ data: Data) {
        lock.lock(); defer { lock.unlock() }
        version += 1
        pending[key] = data
        pendingVersion[key] = version
    }

    public func remove(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        let inHead = head?.chunks[key] != nil
        version += 1
        if inHead { pending[key] = .some(nil); pendingVersion[key] = version }
        else { pending[key] = nil; pendingVersion[key] = nil }
    }

    public func removeAll(depth: Int) {
        for c in chunks(depth: depth) { remove(WorldStore.key(depth, c)) }
    }

    // MARK: committing
    public func beginCommit(index: Data, meta: Data) -> SaveBatch {
        lock.lock(); defer { lock.unlock() }
        return SaveBatch(base: head, changes: pending, index: index, meta: meta, stamp: Date().timeIntervalSince1970, pendingMarks: pendingVersion)
    }

    /// Pure file work: blobs, manifest, verification, HEAD. Safe on a background queue
    /// (one commit at a time per store). Returns the new manifest; throws without touching HEAD on failure.
    public func write(_ b: SaveBatch) throws -> Manifest {
        var m = Manifest(gen: (b.base?.gen ?? 0) + 1, format: WorldStore.format, prev: b.base?.gen, created: b.stamp,
                         chunks: b.base?.chunks ?? [:], index: nil, meta: nil)
        // 1. blobs for every changed chunk
        for (k, v) in b.changes.sorted(by: { $0.key < $1.key }) {
            guard let data = v else { m.chunks[k] = nil; continue }
            m.chunks[k] = StoreEntry(o: try putBlob(data, step: .objectWrite), s: data.count, t: b.stamp)
        }
        try check(.objectWrite, after: true)
        // 2. index and meta
        m.index = StoreEntry(o: try putBlob(b.index, step: .indexWrite), s: b.index.count, t: b.stamp)
        m.meta = StoreEntry(o: try putBlob(b.meta, step: .indexWrite), s: b.meta.count, t: b.stamp)
        try check(.indexWrite, after: true)
        // 3. manifest of the new generation, then read it back and check every blob it names
        try check(.manifestWrite, after: false)
        // written under a pending name: a manifest only gets its real name once HEAD points at it,
        // so one left behind by an interrupted commit can never be mistaken for a saved generation
        let mURL = gens.appendingPathComponent("g\(m.gen).pending.json")
        do { try atomicWrite(JSONEncoder().encode(m), to: mURL) } catch { throw SaveError(step: .manifestWrite, detail: "\(error)") }
        guard let back = loadManifest(m.gen, pending: true), back == m, verify(back) else { throw SaveError(step: .manifestWrite, detail: "verification failed") }
        try check(.manifestWrite, after: true)
        // 4. the switch: from here on the new generation is the world
        try check(.headSwitch, after: false)
        do { try atomicWrite(Data("\(m.gen)".utf8), to: headURL) } catch { throw SaveError(step: .headSwitch, detail: "\(error)") }
        try check(.headSwitch, after: true)
        // the manifest takes its real name; if this fails, opening the world finishes it
        try? FileManager.default.moveItem(at: mURL, to: gens.appendingPathComponent("g\(m.gen).json"))
        return m
    }

    /// Back on the main thread after `write` succeeded: the new generation becomes HEAD in memory
    /// and the pending changes it carried are settled (later changes stay pending).
    public func finishCommit(_ b: SaveBatch, _ m: Manifest) {
        lock.lock(); defer { lock.unlock() }
        head = m
        for (k, v) in b.pendingMarks where pendingVersion[k] == v { pending[k] = nil; pendingVersion[k] = nil }
    }

    /// Everything in one call (tests, small worlds, and the synchronous paths).
    @discardableResult public func commit(index: Data, meta: Data) throws -> Manifest {
        let b = beginCommit(index: index, meta: meta)
        let m = try write(b)
        finishCommit(b, m)
        return m
    }

    public func readIndex() -> Data? { head?.index.flatMap { try? Data(contentsOf: blobURL($0.o)) } }
    public func readMeta() -> Data? { head?.meta.flatMap { try? Data(contentsOf: blobURL($0.o)) } }

    // MARK: garbage
    /// Remove manifests other than HEAD (and, unless `purge`, the one before it) and every blob none of
    /// the kept manifests needs. Idempotent; a failure here never affects HEAD.
    /// `purge` is used after a permanent deletion: the older generation would otherwise still hold the
    /// deleted content.
    @discardableResult public func collectGarbage(purge: Bool = false) throws -> Int {
        try check(.cleanup, after: false)
        let fm = FileManager.default
        guard let h = head else { return 0 }
        var keep: [Manifest] = [h]
        if !purge, let p = h.prev, let pm = loadManifest(p) { keep.append(pm) }
        let keepGens = Set(keep.map { $0.gen })
        var live = Set<String>()
        for m in keep { for e in m.chunks.values { live.insert(e.o) }; if let i = m.index { live.insert(i.o) }; if let x = m.meta { live.insert(x.o) } }
        var removed = 0
        for f in (try? fm.contentsOfDirectory(atPath: gens.path)) ?? [] {
            if f.hasPrefix("g"), f.hasSuffix(".json"), !f.hasSuffix(".pending.json"), let n = Int(f.dropFirst().dropLast(5)), keepGens.contains(n) { continue }
            try? fm.removeItem(at: gens.appendingPathComponent(f)); removed += 1
        }
        for sub in (try? fm.contentsOfDirectory(atPath: objects.path)) ?? [] {
            let d = objects.appendingPathComponent(sub)
            for f in (try? fm.contentsOfDirectory(atPath: d.path)) ?? [] where !live.contains(f) {
                try? fm.removeItem(at: d.appendingPathComponent(f)); removed += 1
            }
        }
        try check(.cleanup, after: true)
        return removed
    }

    /// Bytes on disk under objects/ (what the world really occupies).
    public func diskBytes() -> Int {
        let fm = FileManager.default
        var n = 0
        for sub in (try? fm.contentsOfDirectory(atPath: objects.path)) ?? [] {
            let d = objects.appendingPathComponent(sub)
            for f in (try? fm.contentsOfDirectory(atPath: d.path)) ?? [] {
                n += ((try? fm.attributesOfItem(atPath: d.appendingPathComponent(f).path)[.size]) as? NSNumber)?.intValue ?? 0
            }
        }
        return n
    }

    // MARK: recovery
    /// HEAD's generation if it is complete; otherwise the newest complete one.
    func recover() -> Manifest? {
        let fm = FileManager.default
        // no HEAD: nothing was ever committed (a manifest without HEAD was written by an interrupted commit)
        guard let raw = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let pointed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if let n = pointed {
            if let m = loadManifest(n), verify(m) { return m }
            // HEAD was switched but the manifest kept its pending name (interrupted right after the switch)
            if let m = loadManifest(n, pending: true), verify(m) {
                try? FileManager.default.moveItem(at: gens.appendingPathComponent("g\(n).pending.json"), to: gens.appendingPathComponent("g\(n).json"))
                return m
            }
        }
        // HEAD names a generation that is damaged (or HEAD itself is unreadable): fall back to the newest
        // complete generation that HEAD had already reached - never to one that was never switched to.
        let all = ((try? fm.contentsOfDirectory(atPath: gens.path)) ?? []).compactMap { f -> Int? in
            guard f.hasPrefix("g"), f.hasSuffix(".json"), !f.hasSuffix(".pending.json") else { return nil }
            return Int(f.dropFirst().dropLast(5))
        }.sorted(by: >)
        for n in all where n < (pointed ?? Int.max) {
            if let m = loadManifest(n), verify(m) {
                recoveredFrom = pointed
                try? atomicWrite(Data("\(m.gen)".utf8), to: headURL)
                return m
            }
        }
        return nil
    }

    func loadManifest(_ n: Int, pending: Bool = false) -> Manifest? {
        guard let d = try? Data(contentsOf: gens.appendingPathComponent(pending ? "g\(n).pending.json" : "g\(n).json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: d)
    }

    /// Every blob a manifest names is present with the expected size.
    func verify(_ m: Manifest) -> Bool {
        let fm = FileManager.default
        var all = Array(m.chunks.values)
        if let i = m.index { all.append(i) } else { return false }
        if let x = m.meta { all.append(x) }
        for e in all {
            let size = ((try? fm.attributesOfItem(atPath: blobURL(e.o).path)[.size]) as? NSNumber)?.intValue
            if size != e.s { return false }
        }
        return true
    }

    // MARK: files
    func blobURL(_ name: String) -> URL { objects.appendingPathComponent(String(name.prefix(2))).appendingPathComponent(name) }

    static func hash(_ d: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        d.withUnsafeBytes { raw in for b in raw.bindMemory(to: UInt8.self) { h = (h ^ UInt64(b)) &* 0x100000001b3 } }
        return String(format: "%016llx", h)
    }

    /// Write content once under its own name; a blob that already exists is reused as it is.
    func putBlob(_ data: Data, step: SaveFault) throws -> String {
        try check(step, after: false)
        let name = WorldStore.hash(data) + "-\(data.count).bin"
        let url = blobURL(name)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue == data.count { return name }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try atomicWrite(data, to: url)
        } catch { throw SaveError(step: step, detail: "\(error)") }
        guard let back = try? Data(contentsOf: url), back == data else { throw SaveError(step: step, detail: "read-back mismatch") }
        return name
    }

    func atomicWrite(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }

    func check(_ step: SaveFault, after: Bool) throws {
        if after { if crashAfter.contains(step) { throw SaveError(step: step, detail: "interrupted after (test)") } }
        else if failAt.contains(step) { throw SaveError(step: step, detail: "injected failure (test)") }
    }

    // MARK: older saves
    /// Saves from before 1.6 kept plain files: chunks/c_x_y.json, chunks_d1/..., index.json, meta.json.
    public var hasLegacyLayout: Bool {
        let fm = FileManager.default
        return head == nil && (fm.fileExists(atPath: dir.appendingPathComponent("index.json").path) || fm.fileExists(atPath: dir.appendingPathComponent("chunks").path))
    }

    /// Copy an old-layout save into generation 1. The old files are left untouched (they are the backup);
    /// if anything fails, nothing is switched and the old save still opens as before.
    @discardableResult public func importLegacy() throws -> Manifest {
        let fm = FileManager.default
        for (folder, depth) in [("chunks", 0), ("chunks_d1", 1)] {
            let d = dir.appendingPathComponent(folder)
            for f in (try? fm.contentsOfDirectory(atPath: d.path)) ?? [] where f.hasSuffix(".json") {
                let p = f.dropLast(5).split(separator: "_")
                guard p.count == 3, let x = Int(p[1]), let y = Int(p[2]), let data = try? Data(contentsOf: d.appendingPathComponent(f)) else { continue }
                stage(WorldStore.key(depth, MP.chunkKey(x, y)), data)
            }
        }
        let index = (try? Data(contentsOf: dir.appendingPathComponent("index.json"))) ?? Data()
        let meta = (try? Data(contentsOf: dir.appendingPathComponent("meta.json"))) ?? Data()
        return try commit(index: index, meta: meta)
    }
}
