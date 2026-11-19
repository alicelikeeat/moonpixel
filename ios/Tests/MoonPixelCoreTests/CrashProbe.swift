import XCTest
@testable import MoonPixelCore

final class CrashProbe: XCTestCase {
    func testManySeedsStartAndRun() throws {
        guard ProcessInfo.processInfo.environment["MP_PROBE"] != nil else { throw XCTSkip("probe") }
        var gen = RNG(seed: 4); for _ in 0..<40 { let seed = gen.int(1, 99999)
            print("PROBE seed", seed)
            let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
            let s = Society(world: w, seed: seed)
            s.bootstrap(origin: TilePos(0, 0), villages: 4, per: 30)
            for cy in -3...3 { for cx in -3...3 {
                let ch = w.chunk(cx, cy)
                _ = AnimeArt.bakeChunk(layers: ch.layers)
                let inp = ChunkInput3D(world: w, cx: cx, cy: cy)
                let m = Mesher3D.build(inp, gen: w.gen, anime: true)
                _ = AnimeArt.bakeGround(layers: inp.layers, relief: m.relief)
                let u = s.underworld().chunk(cx, cy)
                _ = PixelArt.bakeChunk(layers: ch.layers); _ = PixelArt.bakeChunk(layers: u.layers); _ = AnimeArt.bakeChunk(layers: u.layers)
                _ = PixelArt.bakeGround(layers: inp.layers, relief: m.relief)
            } }
            let home = s.settlements.values.min { $0.id < $1.id }!.center.center
            s.realm.player.body = Body(at: home, z: 0, depth: 0)
            s.realm.player.depth = 0
            for _ in 0..<400 { s.tick(0.5); s.favorHour(); _ = s.faunaTick(0.5, viewer: TilePos(0, 0).center, mazeHere: false) }
            s.favorHour()
            _ = s.ufos(near: .zero, reach: 3000)
            _ = WorldMap().render(s, centre: TilePos(0, 0), reach: 6, ppc: 96, zh: true)
        }
    }
}
