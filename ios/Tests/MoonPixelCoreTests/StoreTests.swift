import XCTest
@testable import MoonPixelCore

final class StoreTests: XCTestCase {
    func dir(_ name: String) -> URL { tempDir("store-" + name) }
    func k(_ x: Int) -> String { WorldStore.key(0, MP.chunkKey(x, 0)) }
    func d(_ s: String) -> Data { Data(s.utf8) }

    /// A store with generation 1 holding A=a1, C=c1 and index "i1".
    func base(_ name: String) -> (URL, WorldStore) {
        let u = dir(name)
        let s = WorldStore(directory: u)
        s.stage(k(1), d("a1")); s.stage(k(3), d("c1"))
        XCTAssertNoThrow(try s.commit(index: d("i1"), meta: d("m1")))
        return (u, s)
    }

    /// The change every fault test tries to commit: A=a2, B new, C deleted, index "i2".
    func change(_ s: WorldStore) { s.stage(k(1), d("a2")); s.stage(k(2), d("b2")); s.remove(k(3)) }

    func state(_ s: WorldStore) -> String {
        let a = s.read(k(1)).map { String(decoding: $0, as: UTF8.self) } ?? "-"
        let b = s.read(k(2)).map { String(decoding: $0, as: UTF8.self) } ?? "-"
        let c = s.read(k(3)).map { String(decoding: $0, as: UTF8.self) } ?? "-"
        let i = s.readIndex().map { String(decoding: $0, as: UTF8.self) } ?? "-"
        return "\(a) \(b) \(c) \(i)"
    }
    let old = "a1 - c1 i1", new = "a2 b2 - i2"

    func testCommitReopenAndShareUnchangedChunks() throws {
        let (u, s) = base("basic")
        XCTAssertEqual(s.headGen, 1)
        XCTAssertEqual(state(WorldStore(directory: u)), old, "a reopened store sees the committed generation")
        let blobs = s.diskBytes()
        s.stage(k(1), d("a2"))
        try s.commit(index: d("i2"), meta: d("m1"))
        let r = WorldStore(directory: u)
        XCTAssertEqual(r.headGen, 2)
        XCTAssertEqual(state(r), "a2 - c1 i2")
        XCTAssertEqual(r.head?.chunks[k(3)]?.o, s.head?.chunks[k(3)]?.o)
        // only the changed chunk and the new index were written; C and the meta are shared
        XCTAssertEqual(s.diskBytes() - blobs, 2 + 2, "no copy of unchanged content")
        XCTAssertFalse(s.hasPending)
    }

    func testEveryFailureLeavesTheWholeOldStateAndRetryGivesTheWholeNewOne() throws {
        for fault in [SaveFault.objectWrite, .indexWrite, .manifestWrite, .headSwitch] {
            for crash in [false, true] {
                let (u, s) = base("fault-\(fault.rawValue)-\(crash)")
                change(s)
                if crash { s.crashAfter = [fault] } else { s.failAt = [fault] }
                XCTAssertThrowsError(try s.commit(index: d("i2"), meta: d("m2")), "\(fault) \(crash)")
                // the "restarted" app opens what is on disk
                let reopened = WorldStore(directory: u)
                let expect = crash && fault == .headSwitch ? new : old
                XCTAssertEqual(state(reopened), expect, "\(fault) crash=\(crash): whole old or whole new, never a mix")
                XCTAssertEqual(reopened.headGen, expect == new ? 2 : 1)
                // the running app still has its changes and can try again
                s.failAt = []; s.crashAfter = []
                XCTAssertTrue(state(s).hasPrefix("a2 b2 -"), "nothing pending was lost")
                XCTAssertNoThrow(try s.commit(index: d("i2"), meta: d("m2")))
                XCTAssertEqual(state(WorldStore(directory: u)), new, "\(fault): retry commits the whole change")
            }
        }
    }

    func testCleanupFailureNeverInvalidatesTheNewGeneration() throws {
        let (u, s) = base("cleanup")
        change(s)
        try s.commit(index: d("i2"), meta: d("m2"))
        s.failAt = [.cleanup]
        XCTAssertThrowsError(try s.collectGarbage())
        XCTAssertEqual(state(WorldStore(directory: u)), new)
        s.failAt = []; s.crashAfter = [.cleanup]
        XCTAssertThrowsError(try s.collectGarbage())
        XCTAssertEqual(state(WorldStore(directory: u)), new, "an interrupted cleanup is harmless")
        s.crashAfter = []
        XCTAssertNoThrow(try s.collectGarbage()); XCTAssertNoThrow(try s.collectGarbage())
        XCTAssertEqual(state(WorldStore(directory: u)), new, "and can be repeated")
    }

    func testDamagedHeadOrMissingBlobFallsBackToTheLastCompleteGeneration() throws {
        let (u, s) = base("fallback")
        change(s)
        try s.commit(index: d("i2"), meta: d("m2"))
        // a blob of generation 2 disappears (e.g. half-written storage)
        let blob = s.blobURL(s.head!.chunks[k(2)]!.o)
        try FileManager.default.removeItem(at: blob)
        let r = WorldStore(directory: u)
        XCTAssertEqual(state(r), old, "generation 2 is incomplete, so generation 1 is used")
        XCTAssertEqual(r.recoveredFrom, 2)
        // garbage in HEAD: the newest complete generation is used
        try Data("nonsense".utf8).write(to: u.appendingPathComponent("HEAD"))
        XCTAssertEqual(state(WorldStore(directory: u)), old)
        // a manifest written by a commit that never switched HEAD is not taken for the save
        let v = dir("unswitched")
        let t = WorldStore(directory: v)
        t.stage(k(1), d("a1")); try t.commit(index: d("i1"), meta: d("m1"))
        t.stage(k(1), d("a9")); t.failAt = [.headSwitch]
        XCTAssertThrowsError(try t.commit(index: d("i9"), meta: d("m9")))
        try Data("nonsense".utf8).write(to: v.appendingPathComponent("HEAD"))
        XCTAssertEqual(WorldStore(directory: v).read(k(1)), d("a1"), "generation 2 was never committed, even with HEAD unreadable")
    }

    func testGarbageKeepsThePreviousSnapshotUntilAPurge() throws {
        let (u, s) = base("gc")
        let c1 = s.head!.chunks[k(3)]!.o
        change(s)                                   // C deleted
        try s.commit(index: d("i2"), meta: d("m2"))
        try s.collectGarbage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.blobURL(c1).path), "the previous generation still holds C for a while")
        try s.collectGarbage(purge: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.blobURL(c1).path), "after a permanent deletion nothing keeps C")
        XCTAssertEqual(state(WorldStore(directory: u)), new)
        let gens = try FileManager.default.contentsOfDirectory(atPath: u.appendingPathComponent("gen").path)
        XCTAssertEqual(gens, ["g2.json"])
    }

    func testOldLayoutIsImportedAndLeftInPlace() throws {
        let u = dir("legacy")
        let fm = FileManager.default
        try fm.createDirectory(at: u.appendingPathComponent("chunks"), withIntermediateDirectories: true)
        try fm.createDirectory(at: u.appendingPathComponent("chunks_d1"), withIntermediateDirectories: true)
        try d("surface").write(to: u.appendingPathComponent("chunks/c_4_-2.json"))
        try d("below").write(to: u.appendingPathComponent("chunks_d1/c_4_-2.json"))
        try d("{\"old\":1}").write(to: u.appendingPathComponent("index.json"))
        let s = WorldStore(directory: u)
        XCTAssertTrue(s.hasLegacyLayout)
        s.failAt = [.headSwitch]
        XCTAssertThrowsError(try s.importLegacy())
        XCTAssertTrue(WorldStore(directory: u).hasLegacyLayout, "a failed import switches nothing: the old save still opens the old way")
        s.failAt = []
        try s.importLegacy()
        let r = WorldStore(directory: u)
        XCTAssertFalse(r.hasLegacyLayout)
        XCTAssertEqual(r.read(WorldStore.key(0, MP.chunkKey(4, -2))), d("surface"))
        XCTAssertEqual(r.read(WorldStore.key(1, MP.chunkKey(4, -2))), d("below"))
        XCTAssertEqual(r.readIndex(), d("{\"old\":1}"))
        XCTAssertTrue(fm.fileExists(atPath: u.appendingPathComponent("index.json").path), "the original files stay as the backup")
    }

    func testBackgroundCommitKeepsChangesMadeMeanwhile() throws {
        let (u, s) = base("bg")
        s.stage(k(1), d("a2"))
        let batch = s.beginCommit(index: d("i2"), meta: d("m2"))
        s.stage(k(1), d("a3"))                      // the game goes on while the batch is written
        s.stage(k(4), d("x"))
        let m = try s.write(batch)
        s.finishCommit(batch, m)
        XCTAssertEqual(WorldStore(directory: u).read(k(1)), d("a2"), "the batch is exactly the moment it was taken")
        XCTAssertEqual(s.read(k(1)), d("a3")); XCTAssertEqual(s.read(k(4)), d("x"))
        XCTAssertTrue(s.hasPending, "later changes are still waiting for the next commit")
        try s.commit(index: d("i3"), meta: d("m3"))
        XCTAssertEqual(WorldStore(directory: u).read(k(1)), d("a3"))
    }

    /// A whole world: chunks evicted before a save are kept, the map and society commit together,
    /// and a crash between commit and journal removal never runs a law twice.
    func testWorldAndLawsOnTheStore() throws {
        let u = dir("world")
        let s = makeSociety(7, dir: u)
        runYears(s, 0.2)
        let wall = s.content.tid("wall_stone")
        s.world.setTile(2, 9000, 9000, wall)
        s.world.purge()                              // evicted while dirty: only pending in the store
        XCTAssertEqual(s.world.tile(2, 9000, 9000), wall, "read back from the pending change")
        s.world.saveAll()
        try s.world.store!.commit(index: try JSONEncoder().encode(s.snapshot()), meta: Data())
        let w2 = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256)); w2.open(directory: u)
        XCTAssertEqual(w2.tile(2, 9000, 9000), wall)
        // a law, committed, then the app dies before the journal is removed
        let plan = s.planLaw(.thanos, seed: 5)
        XCTAssertTrue(LawJournal.write(plan, u, baseGen: s.world.store!.headGen))
        let run = s.beginLaw(plan); while !run.step(64) {}
        s.world.saveAll()
        try s.world.store!.commit(index: try JSONEncoder().encode(s.snapshot()), meta: Data())
        XCTAssertEqual(LawJournal.recovery(u, store: WorldStore(directory: u)), .alreadyCommitted, "never run twice")
        // the other case: journal written, app dies before the commit
        let plan2 = s.planLaw(.thanos, seed: 6)
        XCTAssertTrue(LawJournal.write(plan2, u, baseGen: s.world.store!.headGen))
        XCTAssertEqual(LawJournal.recovery(u, store: WorldStore(directory: u)), .replay(plan2))
        LawJournal.clear(u)
        XCTAssertEqual(LawJournal.recovery(u, store: WorldStore(directory: u)), .none)
    }
}
