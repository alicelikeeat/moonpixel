import XCTest
@testable import MoonPixelCore

extension ElevatorTests {
    /// Walk up to the doors and the car comes and waits open; step in with one press, choose a floor, and
    /// step out there with one press, onto the landing in front of the doors.
    func testTheCarComesToYouWaitsOpenAndLetsYouOutWithOnePress() {
        let (s, e, _) = building()
        // the car is up on storey 4
        e.call(4, at: s.world.time)
        run(s, e, 20)
        XCTAssertTrue(e.open(at: 4) || (e.docked && e.at == 4))
        // the traveller walks up to the ground landing
        let door = e.stops[0].door
        s.realm.player.body = Body(at: door.center, z: e.stops[0].z, depth: 0)
        func tick(_ secs: Double) { var t = 0.0; while t < secs { s.playerLiftAssist(); s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30; t += 1.0 / 30 } }
        XCTAssertNotNil(s.playerLanding(), "standing at the lift")
        tick(25)
        XCTAssertTrue(e.open(at: 0), "called down to you and open")
        tick(15)
        XCTAssertTrue(e.open(at: 0), "and it waits with its doors open while you stand at them")
        // in with one press
        XCTAssertEqual(s.playerEnterLift(), .entered)
        XCTAssertEqual(s.realm.player.body?.platform, e.id)
        XCTAssertTrue(e.playerAboard)
        tick(8)
        XCTAssertTrue(e.open(at: 0), "inside, the doors wait until a floor is chosen")
        // up to storey 3
        s.playerRideLift(to: 3)
        var t = 0.0
        while t < 40 && !e.open(at: 3) { s.playerLiftAssist(); s.liftStep(e, 1.0 / 30, powered: true); s.world.time += 1.0 / 30; t += 1.0 / 30 }
        XCTAssertTrue(e.open(at: 3), "arrived and open")
        tick(12)
        XCTAssertTrue(e.open(at: 3), "the doors stay open until you are out")
        // out with one press, onto the landing of storey 3
        guard let out = s.playerExitLift() else { return XCTFail("could not step out") }
        XCTAssertEqual(out.depth, OpenWorld.storeyBase + 3)
        XCTAssertNil(s.realm.player.body?.platform)
        XCTAssertFalse(e.playerAboard)
        XCTAssertEqual(out.pos.tile, e.stops[3].door, "in front of the doors")
        XCTAssertNotNil(WorldGround(s).floor(out.depth, out.pos.tile), "on the floor there")
        XCTAssertNil(s.playerExitLift(), "already out")
    }

    /// Between floors there is no stepping out; it lets you out at the next stop.
    func testNoSteppingOutBetweenFloors() {
        let (s, e, _) = building()
        var b = Body(at: Vec2(e.minX + 16, e.minY + 16), z: e.z, depth: 0)
        b.platform = e.id; b.state = .riding; s.realm.player.body = b; e.playerAboard = true
        s.playerRideLift(to: 5)
        run(s, e, 2)
        XCTAssertFalse(e.docked, "under way")
        XCTAssertNil(s.playerExitLift())
        XCTAssertEqual(s.realm.player.body?.platform, e.id, "still inside")
    }
}

extension Anime3DPreviewTests {
    /// MP_PREVIEW: a house with its new doorway, a lift beside it and the lit landings (docs/lift-landings.png).
    func testPreviewLiftLandings() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let s = makeSociety(6)
        let town = s.settlements.values.sorted { $0.id < $1.id }[0]
        let o = s.world.findSite(from: town.center, minR: 14, maxR: 60, salt: 3, avoid: [], avoidDist: 0)
        let levels = 4
        s.raiseHouse(at: o, storeys: levels, w: 7, d: 7)
        let sx = o.x + 8, sy = o.y + 2
        for lv in 1..<levels { let w = s.storeyWorld(lv); for y in (sy - 1)...(sy + 2) { w.setTile(0, o.x + 7, y, s.content.tid("wood_floor")) } }
        for yy in sy..<(sy + 2) { for xx in sx..<(sx + 2) { for l in 1...3 { s.world.setTile(l, xx, yy, 0) } } }
        let plan = s.planLift(x: sx, y: sy, levels: Array(0..<levels), landingSide: TilePos(-1, 0))
        for (k, v) in plan.cost { s.carry(k, v) }
        guard let id = s.buildLift(plan, x: sx, y: sy, town: town.id, tower: nil, planID: 501), let e = s.lift(id) else { return XCTFail("lift") }
        e.z = e.stops[2].z
        let cx0 = OpenWorld.floorDiv(o.x, 32), cy0 = OpenWorld.floorDiv(o.y, 32)
        var parts: [(Mesh3D, Tex?, Bool, SIMD3<Float>, Float)] = []
        let input = ChunkInput3D(world: s.world, cx: cx0, cy: cy0)
        let mesh = Mesher3D.build(input, gen: s.world.gen, anime: true)
        parts.append((mesh.ground, Tex(b: AnimeArt.bakeGround(layers: input.layers, relief: mesh.relief)), false, .zero, 0))
        parts.append((mesh.solid, Tex(b: Palette3D.bitmap.animeGraded()), false, .zero, 0))
        let pal = Tex(b: Palette3D.bitmap.animeGraded())
        let base = SIMD3<Float>(Float(-cx0 * 32), 0, Float(-cy0 * 32))
        parts.append((Figure3D.liftCar(w: 2, d: 2).inked(width: 0.03), pal, false, base + SIMD3(Float(e.x), Float(e.z), Float(e.y)), 0))
        let mid = SIMD2<Float>(Float(e.x) + 1, Float(e.y) + 1)
        for st in e.stops {
            // turned like the 3D view does it (the landing's +x towards the shaft)
            let c = SIMD2<Float>(Float(st.door.x) + 0.5, Float(st.door.y) + 0.5), d = mid - c
            let a = -atan2(d.y, d.x)
            var m = Mesh3D()
            let l = Figure3D.liftLanding()
            m.add(Mesh3D(), at: .zero)
            for i in l.positions.indices {
                let p = l.positions[i] - SIMD3(0.5, 0, 0.5)
                let r = SIMD3<Float>(p.x * cos(a) + p.z * sin(a), p.y, -p.x * sin(a) + p.z * cos(a))
                m.positions.append(r + SIMD3(0.5, 0, 0.5)); m.normals.append(l.normals[i]); m.uvs.append(l.uvs[i])
            }
            m.indices = l.indices
            parts.append((m.inked(width: 0.02), pal, false, base + SIMD3(Float(st.door.x), Float(st.z), Float(st.door.y)), 0))
        }
        let ground = Float(Terrain3D.level(elevation: s.world.gen.elevation(o.x, o.y))) * Terrain3D.step
        let centre = base + SIMD3(Float(o.x) + 5, ground + 2.5, Float(o.y) + 5)
        var sheet = Bitmap(1600, 700, fill: .white)
        let a = render(parts, size: (800, 700), yaw: 0.9, pitch: 0.38, scale: 40, centre: centre)
        let b = render(parts, size: (800, 700), yaw: -0.35, pitch: 0.3, scale: 52, centre: centre + SIMD3(1, 0, 2))
        sheet.blit(a, sx: 0, sy: 0, sw: 800, sh: 700, dx: 0, dy: 0, blend: false)
        sheet.blit(b, sx: 0, sy: 0, sw: 800, sh: 700, dx: 800, dy: 0, blend: false)
        var data = Data("\(sheet.w) \(sheet.h)\n".utf8); data.append(contentsOf: sheet.px)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("lift-a.rgba"))
    }
}
