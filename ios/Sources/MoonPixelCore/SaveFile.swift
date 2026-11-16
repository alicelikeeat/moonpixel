import Foundation

/// A save kept in one file (a city of metro mode, a battle of command mode), written so that at every
/// moment either the whole old version or the whole new one is in place, never neither.
///
/// Writing: the data is checked (it must decode), written to `<name>.tmp` and flushed to disk; the
/// current file is copied to `<name>.prev` (if that copy fails nothing else happens); only then is the
/// new file renamed over the old one, which the file system does in one step. A process killed at any
/// point leaves the old file, or the new one, plus at most a stray temporary file that loading ignores.
///
/// Loading: the file if it reads; if it does not, it is first moved aside as `<name>.unreadable-<time>`
/// (so it is never overwritten) and the previous version is offered instead. If even moving it aside
/// fails, the save is locked: nothing may be written over it until the player has dealt with it.
public final class SaveFile {
    public enum Stage: Hashable { case write, sync, backup, swap, aside }

    public let url: URL
    /// Test hook: these stages fail with an error, as a full disk or a killed process would.
    public var failAt: Set<Stage> = []
    /// An unreadable file is still in place: writing would destroy it.
    public private(set) var locked = false

    public init(url: URL) { self.url = url }

    var tmp: URL { url.appendingPathExtension("tmp") }
    public var previous: URL { url.deletingPathExtension().appendingPathExtension("prev").appendingPathExtension(url.pathExtension) }

    public struct Failure: Error, CustomStringConvertible {
        public let stage: String
        public let detail: String
        public var description: String { "\(stage): \(detail)" }
    }

    func check(_ s: Stage) throws { if failAt.contains(s) { throw Failure(stage: "\(s)", detail: "injected") } }

    /// Write a new version. `verify` must accept the data (normally: it decodes) or nothing is written.
    public func write(_ data: Data, verify: (Data) -> Bool) throws {
        guard !locked else { throw Failure(stage: "locked", detail: "an unreadable save is still in place") }
        guard verify(data) else { throw Failure(stage: "verify", detail: "the new save does not read back") }
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 1. the new version, complete and on disk, beside the old one
        try check(.write)
        _ = try? fm.removeItem(at: tmp)
        guard fm.createFile(atPath: tmp.path, contents: data) else { throw Failure(stage: "write", detail: tmp.lastPathComponent) }
        try check(.sync)
        let h = try FileHandle(forWritingTo: tmp)
        try h.synchronize()
        try h.close()
        // 2. the old version is kept as the previous one (copied, so the current file stays in place meanwhile)
        if fm.fileExists(atPath: url.path) {
            try check(.backup)
            let p = previous.appendingPathExtension("tmp")
            _ = try? fm.removeItem(at: p)
            try fm.copyItem(at: url, to: p)
            guard rename(p.path, previous.path) == 0 else { throw Failure(stage: "backup", detail: "rename \(errno)") }
        }
        // 3. one step: the new file takes the old one's place
        try check(.swap)
        guard rename(tmp.path, url.path) == 0 else { throw Failure(stage: "swap", detail: "rename \(errno)") }
    }

    /// Remove the save and its previous version (a finished battle, a city given up).
    public func discard() {
        for u in [url, previous, tmp] { _ = try? FileManager.default.removeItem(at: u) }
    }

    public enum Source: Equatable { case fresh, current, previous }

    public struct Loaded<T> {
        public var value: T?
        public var source: Source
        /// Where an unreadable file was put (it is kept, never deleted).
        public var keptAside: URL?
        /// An unreadable file could not be moved aside: the save is locked.
        public var locked: Bool
    }

    /// Read the save, falling back to the previous version. Stray temporary files are never read.
    public func load<T>(now: Date = Date(), _ decode: (Data) throws -> T) -> Loaded<T> {
        let fm = FileManager.default
        _ = try? fm.removeItem(at: tmp)
        locked = false
        func read(_ u: URL) -> T? { (try? Data(contentsOf: u)).flatMap { try? decode($0) } }
        if let v = read(url) { return Loaded(value: v, source: .current, keptAside: nil, locked: false) }
        var aside: URL?
        if fm.fileExists(atPath: url.path) {
            let to = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(now.timeIntervalSince1970))").appendingPathExtension(url.pathExtension)
            if !failAt.contains(.aside), (try? fm.moveItem(at: url, to: to)) != nil { aside = to } else { locked = true }
        }
        if let v = read(previous) { return Loaded(value: v, source: .previous, keptAside: aside, locked: locked) }
        return Loaded(value: nil, source: .fresh, keptAside: aside, locked: locked)
    }
}
