import XCTest
@testable import MoonPixelCore

/// The 3D view's meshes: built from the same world, valid for any renderer, and never a change to the world.
final class SolidTests: XCTestCase {
    /// Every triangle faces the way its normal says (counter-clockwise from outside), has an area,
    /// and every index and coordinate is in range.
    private func check(_ m: Mesh3D, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(m.positions.count, m.normals.count, what, file: file, line: line)
        XCTAssertEqual(m.positions.count, m.uvs.count, what, file: file, line: line)
        XCTAssertEqual(m.indices.count % 3, 0, what, file: file, line: line)
        var bad = 0
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let ia = Int(m.indices[t]), ib = Int(m.indices[t + 1]), ic = Int(m.indices[t + 2])
            guard ia < m.positions.count, ib < m.positions.count, ic < m.positions.count else { bad += 1; continue }
            let a = m.positions[ia], b = m.positions[ib], c = m.positions[ic]
            let u = b - a, v = c - a
            let cr = SIMD3<Float>(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let n = m.normals[ia]
            if cr.x * n.x + cr.y * n.y + cr.z * n.z <= 1e-7 { bad += 1 }
        }
        XCTAssertEqual(bad, 0, "\(what): triangles facing the wrong way or without area", file: file, line: line)
        for uv in m.uvs { XCTAssertTrue(uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1, what, file: file, line: line) }
        for p in m.positions { XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, what, file: file, line: line) }
    }

    func testBoxFacesPointOutwards() {
        var m = Mesh3D()
        m.box(0, 0, 0, 1, 2, 3, RGBA(hex: "#5fa84a"), faces: .all)
        XCTAssertEqual(m.triangles, 12)
        check(m, "box")
        let b = m.bounds
        XCTAssertEqual(b.min, SIMD3<Float>(0, 0, 0)); XCTAssertEqual(b.max, SIMD3<Float>(1, 2, 3))
        // sides are shaded differently, so the box reads as a solid without any lighting
        XCTAssertGreaterThanOrEqual(Set(m.uvs.map { "\($0.x),\($0.y)" }).count, 5)
    }

    func testPaletteKeepsColoursWhicheverWayVRuns() {
        for hex in ["#5fa84a", "#1f4f8f", "#e8c84a", "#000000", "#ffffff", "#b5654a"] {
            let c = RGBA(hex: hex)
            let uv = Palette3D.uv(c)
            let got = Palette3D.color(at: uv), flipped = Palette3D.color(at: SIMD2(uv.x, 1 - uv.y))
            XCTAssertEqual(got, flipped, "the palette is mirrored: v from the top or from the bottom shows the same colour")
            XCTAssertLessThan(got.dist(c), 0.04, "5 bits per channel stay close to \(hex)")
        }
        XCTAssertEqual(Palette3D.bitmap.w, Palette3D.width); XCTAssertEqual(Palette3D.bitmap.h, Palette3D.height)
    }

    func testChunkMeshIsValidDeterministicAndLeavesTheWorldAlone() {
        let w = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256))
        var tris = 0, stepped = 0
        for (cx, cy) in [(0, 0), (1, 0), (-2, 3), (5, -4), (9, 9), (-12, 6)] {
            let before = w.chunk(cx, cy).layers
            let rev = w.revision(cx, cy)
            let input = ChunkInput3D(world: w, cx: cx, cy: cy)
            let a = Mesher3D.build(input, gen: w.gen), b = Mesher3D.build(input, gen: w.gen)
            XCTAssertEqual(a.ground.positions, b.ground.positions); XCTAssertEqual(a.solid.positions, b.solid.positions); XCTAssertEqual(a.solid.uvs, b.solid.uvs)
            check(a.ground, "ground \(cx),\(cy)"); check(a.solid, "solid \(cx),\(cy)")
            XCTAssertFalse(a.ground.isEmpty)
            XCTAssertEqual(w.chunk(cx, cy).layers, before, "meshing reads the chunk and changes nothing")
            XCTAssertEqual(w.revision(cx, cy), rev)
            // the ground covers the whole chunk exactly once (seen from above)
            var area: Float = 0
            for t in stride(from: 0, to: a.ground.indices.count, by: 6) {
                let p = a.ground.positions[Int(a.ground.indices[t])], q = a.ground.positions[Int(a.ground.indices[t + 2])]
                area += abs(q.x - p.x) * abs(q.z - p.z)
            }
            XCTAssertEqual(area, 1024, accuracy: 0.01)
            let lo = a.ground.bounds.min, hi = a.ground.bounds.max
            XCTAssertEqual(lo.x, 0); XCTAssertEqual(hi.x, 32); XCTAssertEqual(lo.z, 0); XCTAssertEqual(hi.z, 32)
            // the heights the mesh reports are the ones characters stand on
            for (tx, ty) in [(0, 0), (13, 7), (31, 31)] {
                let y = Terrain3D.groundY(world: w, at: TilePos(cx * 32 + tx, cy * 32 + ty).center)
                XCTAssertEqual(a.heights[ty * 32 + tx], y)
            }
            if Set(a.heights).count > 1 { stepped += 1 }
            tris += a.ground.triangles + a.solid.triangles
            XCTAssertLessThan(a.ground.triangles + a.solid.triangles, 60_000, "one chunk stays a modest mesh")
        }
        XCTAssertGreaterThan(stepped, 0, "the land is not one flat plane")
        print("SOLID 6 chunks: \(tris) triangles")
    }

    func testNeighbouringChunksMeetWithoutGaps() {
        let w = OpenWorld(seed: 11, budget: MemoryBudget(overrideMB: 256))
        let a = Mesher3D.build(ChunkInput3D(world: w, cx: 0, cy: 0), gen: w.gen)
        let e = Mesher3D.build(ChunkInput3D(world: w, cx: 1, cy: 0), gen: w.gen)
        let s = Mesher3D.build(ChunkInput3D(world: w, cx: 0, cy: 1), gen: w.gen)
        // each chunk knew the height of the row across its border, so a step at the border has its side drawn
        for i in 0..<32 {
            let mine = a.heights[i * 32 + 31], theirs = e.heights[i * 32]
            XCTAssertEqual(Terrain3D.groundY(world: w, at: TilePos(32, i).center), theirs)
            XCTAssertLessThanOrEqual(abs(mine - theirs), 2.0, "no cliff of more than two tiles between neighbours")
            XCTAssertEqual(Terrain3D.groundY(world: w, at: TilePos(i, 32).center), s.heights[i])
        }
    }

    func testWaterLiesBelowItsBanksAndBridgesAreLevel() {
        let c = Content.shared
        let grass = c.tid("grass"), water = c.tid("water"), bridge = c.tid("bridge_wood")
        XCTAssertEqual(Terrain3D.groundY(level: 3, ground: grass, structure: 0, depth: 0), 0.75)
        XCTAssertEqual(Terrain3D.groundY(level: 3, ground: water, structure: 0, depth: 0), 0.75 - Terrain3D.waterDrop)
        XCTAssertEqual(Terrain3D.groundY(level: 3, ground: water, structure: bridge, depth: 0), 0.75, "a bridge deck is level with the bank")
        XCTAssertEqual(Terrain3D.groundY(level: 9, ground: c.tid("cave_floor"), structure: 0, depth: 1), 0, "the underground is one floor")
        XCTAssertEqual(Terrain3D.level(elevation: 0.1), 0); XCTAssertEqual(Terrain3D.level(elevation: 5), Terrain3D.maxLevel)
    }

    func testWallsHideTheSidesBetweenThem() {
        let c = Content.shared
        var layers = Array(repeating: [UInt8](repeating: 0, count: MP.chunkArea), count: 4)
        layers[0] = [UInt8](repeating: c.tid("cave_floor"), count: MP.chunkArea)
        let gen = Generator(seed: 1)
        let empty = Mesher3D.build(ChunkInput3D(cx: 0, cy: 0, depth: 1, layers: layers), gen: gen)
        XCTAssertTrue(empty.solid.isEmpty, "a flat floor has nothing standing on it")
        XCTAssertEqual(empty.ground.triangles, 64, "32 rows, one quad each")
        layers[2][5 * 32 + 5] = c.tid("wall_stone")
        let one = Mesher3D.build(ChunkInput3D(cx: 0, cy: 0, depth: 1, layers: layers), gen: gen).solid
        layers[2][5 * 32 + 6] = c.tid("wall_stone")
        let two = Mesher3D.build(ChunkInput3D(cx: 0, cy: 0, depth: 1, layers: layers), gen: gen).solid
        check(one, "wall"); check(two, "walls")
        XCTAssertEqual(one.triangles, 2 + 4 * 4)                      // a top and four sides of two bands each
        XCTAssertEqual(two.triangles, 2 * 2 + 6 * 4, "the two faces between the walls are not drawn")
        XCTAssertEqual(one.bounds.max.y, 1.5)
    }

    func testEveryTileHasAShapeInsideItsNeighbourhood() {
        let c = Content.shared
        var kinds = Set<String>()
        for t in c.tiles.compactMap({ $0 }) where t.layer >= 2 || t.artKind == "cliff" {
            var layers = Array(repeating: [UInt8](repeating: 0, count: MP.chunkArea), count: 4)
            layers[0] = [UInt8](repeating: c.tid("grass"), count: MP.chunkArea)
            layers[t.layer][10 * 32 + 10] = UInt8(t.id)
            let m = Mesher3D.build(ChunkInput3D(cx: 0, cy: 0, depth: 1, layers: layers), gen: Generator(seed: 1)).solid
            XCTAssertFalse(m.isEmpty, "\(t.key) is drawn")
            check(m, t.key)
            let b = m.bounds
            XCTAssertGreaterThanOrEqual(b.min.x, 9.5, t.key); XCTAssertLessThanOrEqual(b.max.x, 11.5, t.key)
            XCTAssertGreaterThanOrEqual(b.min.z, 9.5, t.key); XCTAssertLessThanOrEqual(b.max.z, 11.5, t.key)
            XCTAssertGreaterThanOrEqual(b.min.y, 0, t.key); XCTAssertLessThanOrEqual(b.max.y, 3, t.key)
            kinds.insert(t.artKind)
        }
        XCTAssertGreaterThan(kinds.count, 50)
        // a gate set in a wall that runs north-south turns with the wall
        var layers = Array(repeating: [UInt8](repeating: 0, count: MP.chunkArea), count: 4)
        layers[0] = [UInt8](repeating: c.tid("grass"), count: MP.chunkArea)
        layers[2][10 * 32 + 10] = c.tid("gate")
        let ew = Mesher3D.build(ChunkInput3D(cx: 0, cy: 0, depth: 1, layers: layers), gen: Generator(seed: 1)).solid.bounds
        layers[2][9 * 32 + 10] = c.tid("wall_stone"); layers[2][11 * 32 + 10] = c.tid("wall_stone")
        layers[2][10 * 32 + 10] = c.tid("gate_open")
        let open = Mesher3D.build(ChunkInput3D(cx: 0, cy: 0, depth: 1, layers: layers), gen: Generator(seed: 1)).solid
        check(open, "gate in a wall")
        XCTAssertEqual(ew.max.x - ew.min.x, 1, accuracy: 0.01)
        XCTAssertLessThan(ew.max.z - ew.min.z, 0.8)
    }

    func testFiguresStandOnTheGroundAndFaceSouth() {
        var look = Look()
        for held in PixelArt.held { for frame in 0..<4 { for child in [false, true] {
            let m = Figure3D.human(look, frame: frame, held: held, child: child, female: frame % 2 == 0)
            check(m, "human \(held) \(frame)")
            let b = m.bounds
            XCTAssertEqual(b.min.y, 0, accuracy: 0.001, "feet on the ground")
            XCTAssertLessThan(b.max.y, child ? 1.6 : 2.3)
            XCTAssertGreaterThan(b.max.y, child ? 0.9 : 1.4)
            XCTAssertLessThan(max(abs(b.min.x), abs(b.max.x)), 0.6)
        } } }
        // the same look gives the same mesh; another shirt gives another
        let a = Figure3D.human(look, frame: 1, held: "sword", child: false, female: false)
        look.shirt = "#e8504a"
        let b = Figure3D.human(look, frame: 1, held: "sword", child: false, female: false)
        XCTAssertEqual(a.positions, b.positions); XCTAssertNotEqual(a.uvs, b.uvs)
        // a face from a photo is laid on the front of the head
        var face = Bitmap(8, 8, fill: RGBA(hex: "#f2c8a4")); face.set(2, 3, RGBA(hex: "#101010"))
        let f = Figure3D.human(look, frame: 0, held: "", child: false, female: false, face: face)
        check(f, "face")
        // (the photo's pixels are plates just in front of the face, in place of the modelled eyes)
        XCTAssertTrue(f.positions.contains { abs($0.z - (3.6 + 0.25) / 16) < 1e-4 }, "the photo's plates on the face")
        XCTAssertNotEqual(f.positions, Figure3D.human(look, frame: 0, held: "", child: false, female: false).positions)
        for sp in Species.all { for frame in 0..<2 {
            let m = Figure3D.animal(sp, frame: frame)
            check(m, sp.key)
            XCTAssertEqual(m.bounds.min.y, 0, accuracy: 0.001, sp.key)
            XCTAssertLessThan(m.bounds.max.y, 1.6, sp.key)
        } }
        check(Figure3D.horse(frame: 1), "horse")
        check(Figure3D.standard(color: RGBA(hex: "#4a8af0")), "standard")
        check(Figure3D.cube(color: .white), "cube"); check(Figure3D.plate(color: .white), "plate")
        for n in 0...3 { for (w, h) in [(3, 3), (5, 4), (9, 12)] {
            let r = Figure3D.roof(nation: n, w: w, h: h)
            check(r, "roof \(n) \(w)x\(h)")
            XCTAssertLessThanOrEqual(r.bounds.min.x, 0); XCTAssertGreaterThanOrEqual(r.bounds.max.x, Float(w), "the roof covers its building")
            XCTAssertLessThanOrEqual(r.bounds.min.z, 0); XCTAssertGreaterThanOrEqual(r.bounds.max.z, Float(h))
        } }
    }

    func testARayFindsTheGroundItPointsAt() {
        // flat ground at 0.5 with a 3-high block at tile (4, 4)
        func h(_ x: Int, _ z: Int) -> Float { x == 4 && z == 4 ? 3 : 0.5 }
        let down = Terrain3D.pick(origin: [10.5, 30, 20.25], direction: [0, -1, 0], height: h)
        XCTAssertEqual(down?.x ?? 0, 10.5 * 16, accuracy: 0.5); XCTAssertEqual(down?.y ?? 0, 20.25 * 16, accuracy: 0.5)
        // a slanted ray from the south, as the camera looks
        let p = Terrain3D.pick(origin: [8.5, 10.5, 18.5], direction: [0, -1, -1], height: h)
        XCTAssertEqual(p?.x ?? 0, 8.5 * 16, accuracy: 0.5); XCTAssertEqual(p?.y ?? 0, 8.5 * 16, accuracy: 1.5)
        // a ray that would pass over tile (4, 4) stops on the block instead of the ground behind it
        let hit = Terrain3D.pick(origin: [4.5, 10.5, 12.5], direction: [0, -1, -1], height: h)
        XCTAssertEqual(hit?.tile, TilePos(4, 4))
        XCTAssertNil(Terrain3D.pick(origin: [0, 5, 0], direction: [0, 1, 0], height: h), "a ray into the sky finds nothing")
        XCTAssertNil(Terrain3D.pick(origin: [0, 5, 0], direction: [0, 0, 0], height: h))
        // from very high the long strides still land on the right tile
        let far = Terrain3D.pick(origin: [100.5, 200, 300.5], direction: [0, -1, 0], height: h)
        XCTAssertEqual(far?.tile, TilePos(100, 300))
    }

    func testGroundPictureMatchesTheFlatPartOfTheChunkPicture() {
        let w = OpenWorld(seed: 7, budget: MemoryBudget(overrideMB: 256))
        var layers = w.chunk(0, 0).layers
        let g = PixelArt.bakeGround(layers: layers)
        XCTAssertEqual(g.w, 512); XCTAssertEqual(g.h, 512)
        // with nothing standing on it, the 2D chunk picture shows exactly this ground (it is offset by 8, 24)
        layers[2] = [UInt8](repeating: 0, count: MP.chunkArea); layers[3] = layers[2]
        let cliff = Content.shared.tid("cliff")
        layers[1] = layers[1].map { $0 == cliff ? 0 : $0 }
        let full = PixelArt.bakeChunk(layers: layers), flat = PixelArt.bakeGround(layers: layers)
        for (x, y) in [(0, 0), (17, 200), (511, 511), (300, 5), (128, 400)] { XCTAssertEqual(flat.get(x, y), full.get(x + 8, y + 24)) }
    }
    /// Not a check: with MP_DUMP3D=<file> set, writes a town as coloured triangles for tools/preview3d.py,
    /// which draws them without any Apple framework (a way to look at the meshes on Linux).
    func testDumpATownForThePreviewTool() throws {
        guard let path = ProcessInfo.processInfo.environment["MP_DUMP3D"] else { throw XCTSkip("set MP_DUMP3D to write a preview") }
        let seed = Int(ProcessInfo.processInfo.environment["MP_SEED"] ?? "7") ?? 7
        let w = OpenWorld(seed: seed, budget: MemoryBudget(overrideMB: 256))
        let s = Society(world: w, seed: seed)
        s.bootstrap(origin: TilePos(0, 0), villages: 4, per: 30)
        let years = Double(ProcessInfo.processInfo.environment["MP_YEARS"] ?? "3") ?? 3
        for _ in 0..<Int(years * MP.year) { s.tick(1.0) }
        let town = s.settlements.values.sorted { $0.buildings.count > $1.buildings.count }[0]
        let ccx = town.center.x >> 5, ccy = town.center.y >> 5
        var out = [Float]()
        func emit(_ m: Mesh3D, _ off: SIMD3<Float>, turn: Float = 0, ground: Bitmap? = nil) {
            let cs = Float(cos(Double(turn))), sn = Float(sin(Double(turn)))
            for t in stride(from: 0, to: m.indices.count, by: 3) {
                var col = RGBA.white
                for k in 0..<3 {
                    let i = Int(m.indices[t + k]), p = m.positions[i]
                    out += [off.x + p.x * cs + p.z * sn, off.y + p.y, off.z - p.x * sn + p.z * cs]
                    if k == 0 {
                        // a ground quad is sampled at the middle of its first tile; everything else is one flat colour
                        if let g = ground {
                            let n = m.positions[Int(m.indices[t - t % 6])]          // south-west corner of the quad
                            col = g.get(min(511, Int(n.x) * 16 + 7), min(511, max(0, (Int(n.z) - 1) * 16 + 7)))
                        } else { col = Palette3D.color(at: m.uvs[i]) }
                    }
                }
                out += [Float(col.r) / 255, Float(col.g) / 255, Float(col.b) / 255]
            }
        }
        for cy in (ccy - 1)...(ccy + 1) { for cx in (ccx - 1)...(ccx + 1) {
            let input = ChunkInput3D(world: w, cx: cx, cy: cy)
            let m = Mesher3D.build(input, gen: w.gen)
            let off = SIMD3<Float>(Float(cx * 32), 0, Float(cy * 32))
            emit(m.ground, off, ground: PixelArt.bakeGround(layers: input.layers)); emit(m.solid, off)
        } }
        let x0 = (ccx - 1) * 32, y0 = (ccy - 1) * 32
        for r in s.roofs(minX: x0, minY: y0, maxX: x0 + 96, maxY: y0 + 96) {
            let y = Terrain3D.groundY(world: w, at: TilePos(r.x, r.y).center) + 1.5
            emit(Figure3D.roof(nation: r.nation, w: r.w, h: r.h), [Float(r.x), y, Float(r.y)])
        }
        for a in s.agents.values {
            let y = Terrain3D.groundY(world: w, at: a.pos)
            emit(Figure3D.human(a.look, frame: a.id % 4, held: a.id % 3 == 0 ? "axe" : "", child: false, female: a.female), [Float(a.pos.x / 16), y, Float(a.pos.y / 16)], turn: Float(atan2(a.facing.x, a.facing.y)))
        }
        var head: [Float] = [Float(town.center.x), Float(town.center.y)]
        head += out
        try head.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: URL(fileURLWithPath: path))
        print("SOLID preview: \(out.count / 12) triangles around \(town.center) -> \(path)")
    }

    /// Building, breaking or felling changes the structure hash (shown at once); growth does not (it can wait);
    /// only changes on a chunk's border change what its neighbours read.
    func testStructureAndEdgeHashesTellUrgentChanges() {
        let solid = Content.shared.solid
        let soft = (1..<solid.count).filter { !solid[$0] }, hard = (1..<solid.count).first { solid[$0] }!
        var l = [[UInt8]](repeating: [UInt8](repeating: 0, count: 1024), count: 4)
        let base = Mesher3D.structureHash(l), edge = Mesher3D.edgeHash(l)
        var grow = l; grow[2][5 * 32 + 5] = UInt8(soft[0]); var grown = grow; grown[2][5 * 32 + 5] = UInt8(soft[1])
        XCTAssertEqual(Mesher3D.structureHash(grow), Mesher3D.structureHash(grown), "a crop growing is not urgent")
        XCTAssertEqual(Mesher3D.structureHash(grow), base)
        var wall = l; wall[1][5 * 32 + 5] = 3
        XCTAssertNotEqual(Mesher3D.structureHash(wall), base, "a wall going up is")
        var tree = l; tree[2][5 * 32 + 5] = UInt8(hard)
        XCTAssertNotEqual(Mesher3D.structureHash(tree), base, "so is something solid appearing or going")
        XCTAssertEqual(Mesher3D.edgeHash(wall), edge, "inside the chunk: the neighbours need not know")
        for t in [0, 31, 31 * 32, 1023, 7 * 32 + 31] {
            var e = l; e[1][t] = 3
            XCTAssertNotEqual(Mesher3D.edgeHash(e), edge, "on the border at \(t): they must")
        }
        l[0][17 * 32] = 9
        XCTAssertNotEqual(Mesher3D.edgeHash(l), edge, "ground on the border counts too")
    }

    func testPickingHitsWhatStandsInFrontOfTheGround() {
        // flat ground; a wall on tile (10, 5) and a tree on (14, 5); the eye looks along +x, slightly down
        func standing(_ x: Int, _ z: Int) -> (Float, Terrain3D.Hit) { z == 5 && x == 10 ? (1.5, .wall) : (z == 5 && x == 14 ? (2.5, .object) : (0, .ground)) }
        let eye = SIMD3<Float>(2.5, 1.2, 5.5)
        let low = Terrain3D.pickThing(origin: eye, direction: SIMD3(1, -0.02, 0), ground: { _, _ in 0 }, standing: standing)
        XCTAssertEqual(low?.1, .wall, "the wall's side is hit, not the ground behind it")
        XCTAssertEqual(low?.0, TilePos(10, 5).center)
        let over = Terrain3D.pickThing(origin: SIMD3(2.5, 3, 5.5), direction: SIMD3(1, -0.08, 0), ground: { _, _ in 0 }, standing: standing)
        XCTAssertEqual(over?.1, .object, "over the wall, the tall tree")
        let down = Terrain3D.pickThing(origin: SIMD3(6.5, 10, 2.5), direction: SIMD3(0, -1, 0), ground: { _, _ in 0 }, standing: standing)
        XCTAssertEqual(down?.1, .ground)
        XCTAssertEqual(down!.0.x, 6.5 * 16, accuracy: 0.5)
    }
}
