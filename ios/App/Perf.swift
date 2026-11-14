import Foundation
import QuartzCore

/// Rolling performance figures: no unbounded logs, a fixed window of recent samples.
final class PerfStats {
    private var frames = [Double](repeating: 0, count: 600)     // last 600 frame times (about 10 s at 60 fps)
    private var fi = 0, fcount = 0
    private(set) var longFrames = 0                               // frames over 33 ms since the world opened
    private(set) var phases: [String: Double] = [:]               // smoothed milliseconds per phase
    private(set) var lastSavePrepare = 0.0, lastSaveTotal = 0.0
    private(set) var saves = 0

    func frame(_ dt: Double) {
        frames[fi] = dt; fi = (fi + 1) % frames.count; fcount = min(frames.count, fcount + 1)
        if dt > 1.0 / 30 { longFrames += 1 }
    }

    func phase(_ name: String, _ seconds: Double) {
        let ms = seconds * 1000
        phases[name] = (phases[name] ?? ms) * 0.9 + ms * 0.1
    }

    /// Measure a block and record it under `name`.
    @discardableResult func time<T>(_ name: String, _ f: () -> T) -> T {
        let t = CACurrentMediaTime()
        let r = f()
        phase(name, CACurrentMediaTime() - t)
        return r
    }

    func noteSave(prepare: Double, total: Double) { lastSavePrepare = prepare * 1000; lastSaveTotal = total * 1000; saves += 1 }

    /// p50 / p95 / p99 of the recent frame times, in milliseconds.
    func percentiles() -> (p50: Double, p95: Double, p99: Double) {
        guard fcount > 0 else { return (0, 0, 0) }
        let s = frames.prefix(fcount).sorted()
        func at(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * q))] * 1000 }
        return (at(0.5), at(0.95), at(0.99))
    }

    func reset() { fi = 0; fcount = 0; longFrames = 0; phases = [:] }
}
