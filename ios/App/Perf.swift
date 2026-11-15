import Foundation
import QuartzCore
import SpriteKit
import MoonPixelCore

/// Rolling performance figures: no unbounded logs, a fixed window of recent samples.
final class PerfStats {
    private var frames = [Double](repeating: 0, count: 600)     // last 600 frame times (about 10 s at 60 fps)
    private var fi = 0, fcount = 0
    private(set) var longFrames = 0                               // frames over 33 ms since the world opened
    private(set) var totalFrames = 0
    private(set) var phases: [String: Double] = [:]               // smoothed milliseconds per phase
    private(set) var peaks: [String: Double] = [:]                // worst milliseconds per phase in the window
    private var peakT = CACurrentMediaTime()
    private(set) var lastSavePrepare = 0.0, lastSaveTotal = 0.0
    private(set) var saves = 0

    func frame(_ dt: Double) {
        frames[fi] = dt; fi = (fi + 1) % frames.count; fcount = min(frames.count, fcount + 1)
        totalFrames += 1
        if dt > 1.0 / 30 { longFrames += 1 }
        if CACurrentMediaTime() - peakT > 10 { peaks = [:]; peakT = CACurrentMediaTime() }
    }

    func phase(_ name: String, _ seconds: Double) {
        let ms = seconds * 1000
        phases[name] = (phases[name] ?? ms) * 0.9 + ms * 0.1
        peaks[name] = max(peaks[name] ?? 0, ms)
    }

    /// Measure a block and record it under `name`.
    @discardableResult func time<T>(_ name: String, _ f: () -> T) -> T {
        let t = CACurrentMediaTime()
        let r = f()
        phase(name, CACurrentMediaTime() - t)
        return r
    }

    func noteSave(prepare: Double, total: Double) {
        lastSavePrepare = prepare * 1000; lastSaveTotal = total * 1000; saves += 1
        phase("save-main", prepare)
    }

    /// p50 / p95 / p99 of the recent frame times, in milliseconds.
    func percentiles() -> (p50: Double, p95: Double, p99: Double) {
        guard fcount > 0 else { return (0, 0, 0) }
        let s = frames.prefix(fcount).sorted()
        func at(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * q))] * 1000 }
        return (at(0.5), at(0.95), at(0.99))
    }

    func reset() { fi = 0; fcount = 0; longFrames = 0; totalFrames = 0; phases = [:]; peaks = [:] }
}

/// One reading of everything the diagnostics panel and the perf log show.
struct PerfReport: Codable {
    var p50 = 0.0, p95 = 0.0, p99 = 0.0
    var frames = 0, longFrames = 0
    var phases: [String: Double] = [:], peaks: [String: Double] = [:]
    var nodes = 0, chunkNodes = 0, actorNodes = 0, legionNodes = 0
    var chunkTextureMB = 0.0, chunkTextures = 0, textureEvictions = 0
    var bakesApplied = 0, bakesStale = 0, bakesDeduped = 0, bakesPending = 0
    var memoryMB = 0
    var speedWanted = 0.0, speedReal = 0.0, simDropped = 0.0, simSteps = 0
    var heavyDeferred = 0
    var agents = 0, towns = 0
    var lastSaveMainMs = 0.0, lastSaveTotalMs = 0.0
    var device = ""

    var lines: [String] {
        func f(_ v: Double) -> String { String(format: "%.1f", v) }
        let order = ["sim", "chunks", "actors", "soldiers", "roofs", "legions", "bake", "texture", "save-main"]
        var out = ["frame p50 \(f(p50))  p95 \(f(p95))  p99 \(f(p99)) ms  long \(longFrames)/\(frames)"]
        out.append(order.compactMap { k in phases[k].map { "\(k) \(f($0))/\(f(peaks[k] ?? 0))" } }.joined(separator: "  "))
        out.append("nodes \(nodes)  chunks \(chunkNodes)  actors \(actorNodes)  armies \(legionNodes)")
        out.append("chunk tex \(chunkTextures) · \(f(chunkTextureMB)) MB  evicted \(textureEvictions)  mem \(memoryMB) MB")
        out.append("bakes \(bakesApplied) ok  \(bakesStale) stale  \(bakesDeduped) merged  \(bakesPending) waiting")
        out.append("speed \(f(speedReal))/\(f(speedWanted))×  dropped \(f(simDropped)) s  steps \(simSteps)  towns waiting \(heavyDeferred)")
        out.append("people \(agents)  towns \(towns)  save \(f(lastSaveMainMs)) ms main / \(f(lastSaveTotalMs)) ms total")
        return out
    }
}

extension GameScene {
    func perfReport() -> PerfReport {
        var r = PerfReport()
        guard let m = model else { return r }
        let p = m.perf.percentiles()
        r.p50 = p.p50; r.p95 = p.p95; r.p99 = p.p99
        r.frames = m.perf.totalFrames; r.longFrames = m.perf.longFrames
        r.phases = m.perf.phases; r.peaks = m.perf.peaks
        var n = 0
        func count(_ x: SKNode) { n += 1; for c in x.children { count(c) } }
        count(self)
        r.nodes = n; r.chunkNodes = chunkNodes.count; r.actorNodes = agentNodes.count; r.legionNodes = legionNodes.count
        r.chunkTextureMB = Double(chunkTex.bytes) / 1_048_576; r.chunkTextures = chunkTex.count; r.textureEvictions = chunkTex.evictions
        r.bakesApplied = bakes.applied; r.bakesStale = bakes.stale; r.bakesDeduped = bakes.deduped; r.bakesPending = bakes.pending
        r.memoryMB = MemoryBudget.usedMB()
        r.speedWanted = GameModel.speeds[m.speedIndex]; r.speedReal = m.actualSpeed
        r.simDropped = simClock.dropped; r.simSteps = simClock.steps
        r.heavyDeferred = m.society?.heavyDeferred ?? 0
        r.agents = m.society?.agents.count ?? 0; r.towns = m.society?.livingSettlements ?? 0
        r.lastSaveMainMs = m.perf.lastSavePrepare; r.lastSaveTotalMs = m.perf.lastSaveTotal
        #if targetEnvironment(simulator)
        r.device = "simulator"
        #else
        r.device = "device"
        #endif
        return r
    }
}
