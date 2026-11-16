import XCTest
@testable import MoonPixelCore

/// The single-file save under every way it can go wrong: each step failing, the process dying between
/// steps, a damaged file, and a damaged file that cannot even be moved aside.
final class SaveFileTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("savefile-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func city(_ day: Int) -> Data { Data("{\"day\":\(day)}".utf8) }
    func day(_ d: Data) throws -> Int {
        guard let o = try JSONSerialization.jsonObject(with: d) as? [String: Int], let v = o["day"] else { throw SaveFile.Failure(stage: "decode", detail: "") }
        return v
    }
    func ok(_ d: Data) -> Bool { (try? day(d)) != nil }

    func testWritesAndKeepsThePreviousVersion() throws {
        let f = SaveFile(url: dir.appendingPathComponent("metro.json"))
        XCTAssertEqual(f.load(day).source, .fresh)
        try f.write(city(1), verify: ok)
        try f.write(city(2), verify: ok)
        let l = f.load(day)
        XCTAssertEqual(l.value, 2); XCTAssertEqual(l.source, .current)
        XCTAssertEqual(try day(Data(contentsOf: f.previous)), 1, "the version before is kept")
        XCTAssertThrowsError(try f.write(Data("garbage".utf8), verify: ok), "what does not read back is never written")
        XCTAssertEqual(f.load(day).value, 2)
    }

    func testAFailureAtAnyStepLeavesTheOldSaveWhole() throws {
        for stage in [SaveFile.Stage.write, .sync, .backup, .swap] {
            let f = SaveFile(url: dir.appendingPathComponent("s-\(stage).json"))
            try f.write(city(1), verify: ok)
            f.failAt = [stage]
            XCTAssertThrowsError(try f.write(city(2), verify: ok), "\(stage)")
            f.failAt = []
            let l = f.load(day)
            XCTAssertEqual(l.value, 1, "after a failed \(stage) the old save is still there and whole")
            XCTAssertEqual(l.source, .current)
            try f.write(city(3), verify: ok)
            XCTAssertEqual(f.load(day).value, 3, "and the next save works")
        }
    }

    func testKilledAfterTheNewFileWasWrittenButBeforeTheSwap() throws {
        let f = SaveFile(url: dir.appendingPathComponent("metro.json"))
        try f.write(city(1), verify: ok)
        // the process died with the new version in the temporary file
        try city(2).write(to: f.url.appendingPathExtension("tmp"))
        let l = f.load(day)
        XCTAssertEqual(l.value, 1, "the temporary file is never taken for the save")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.appendingPathExtension("tmp").path), "and it is cleared away")
    }

    func testADamagedSaveIsKeptAsideAndThePreviousOneOffered() throws {
        let f = SaveFile(url: dir.appendingPathComponent("metro.json"))
        try f.write(city(1), verify: ok)
        try f.write(city(2), verify: ok)
        try Data("{\"day\":".utf8).write(to: f.url)                       // cut short
        let l = f.load(now: Date(timeIntervalSince1970: 1000), day)
        XCTAssertEqual(l.value, 1); XCTAssertEqual(l.source, .previous)
        XCTAssertEqual(l.keptAside?.lastPathComponent, "metro.unreadable-1000.json")
        XCTAssertEqual(try Data(contentsOf: l.keptAside!), Data("{\"day\":".utf8), "the damaged file is kept as it was")
        XCTAssertFalse(l.locked)
        try f.write(city(5), verify: ok)
        XCTAssertEqual(f.load(day).value, 5)
    }

    func testADamagedSaveThatCannotBeMovedAsideLocksWriting() throws {
        let f = SaveFile(url: dir.appendingPathComponent("metro.json"))
        try Data("not json".utf8).write(to: f.url)
        f.failAt = [.aside]
        let l = f.load(day)
        XCTAssertNil(l.value); XCTAssertTrue(l.locked); XCTAssertTrue(f.locked)
        XCTAssertThrowsError(try f.write(city(1), verify: ok), "nothing may be written over a file that could not be kept")
        XCTAssertEqual(try Data(contentsOf: f.url), Data("not json".utf8))
        f.failAt = []
        XCTAssertEqual(f.load(day).source, .fresh, "once it can be moved aside, a new save may begin")
        XCTAssertFalse(f.locked)
        try f.write(city(1), verify: ok)
    }

    func testARealCityRoundTrips() throws {
        let m = Metro(seed: 2, worldSeed: 7); m.layOutDemo(); for _ in 0..<20 { m.step() }
        let f = SaveFile(url: dir.appendingPathComponent("metro.json"))
        let data = try JSONEncoder().encode(m)
        try f.write(data) { (try? JSONDecoder().decode(Metro.self, from: $0)) != nil }
        let back = f.load { try JSONDecoder().decode(Metro.self, from: $0) }
        XCTAssertEqual(back.value?.summary, m.summary)
    }
}
