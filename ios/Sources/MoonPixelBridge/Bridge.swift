import Foundation
import MoonPixelCore

// The core as a C library for the PC front end (Unreal): see bridge/include/moonpixel.h for the contract.
// Every function here is a thin translation: handles in and out, plain C structures, no game logic.

final class WorldHandle {
    let society: Society
    init(_ s: Society) { society = s }
}

final class MeshHandle {
    let mesh: Mesh3D
    init(_ m: Mesh3D) { mesh = m }
}

/// The C layout of `MPPerson` (moonpixel.h); kept in step by `mp_abi` and the bridge's own test.
struct MPPerson {
    var id: Int32 = 0
    var x: Float = 0, z: Float = 0
    var facing_x: Float = 0, facing_z: Float = 1
    var flags: Int32 = 0
    var skin: UInt32 = 0, hair: UInt32 = 0, shirt: UInt32 = 0, pants: UInt32 = 0, shoes: UInt32 = 0
    var style: Int32 = 0
    var model: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var held: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

let MP_MOVING: Int32 = 1, MP_SLEEPING: Int32 = 2, MP_WORKING: Int32 = 4, MP_FEMALE: Int32 = 8, MP_CHILD: Int32 = 16, MP_ELDER: Int32 = 32
let jobTool = ["woodcutter": "axe", "miner": "pick", "farmer": "hoe", "builder": "hammer", "forager": "basket", "soldier": "sword"]

private let versionString: UnsafeMutablePointer<CChar> = strdup("3.4.0")!

func world(_ p: OpaquePointer?) -> WorldHandle? { p.map { Unmanaged<WorldHandle>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() } }
func meshOf(_ p: OpaquePointer?) -> MeshHandle? { p.map { Unmanaged<MeshHandle>.fromOpaque(UnsafeRawPointer($0)).takeUnretainedValue() } }

func hex(_ s: String) -> UInt32 { let c = RGBA(hex: s); return UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b) }
func hexString(_ v: UInt32) -> String { String(format: "#%06x", v & 0xFFFFFF) }

/// Copy a string into a fixed C character array (cut to fit, always ended).
func fill<T>(_ field: inout T, _ s: String) {
    withUnsafeMutableBytes(of: &field) { raw in
        let n = raw.count
        let bytes = Array(s.utf8.prefix(n - 1))
        for i in 0..<n { raw[i] = i < bytes.count ? bytes[i] : 0 }
    }
}
func read<T>(_ field: T) -> String {
    var f = field
    return withUnsafeBytes(of: &f) { raw in
        let b = raw.prefix { $0 != 0 }
        return String(decoding: b, as: UTF8.self)
    }
}

@_cdecl("mp_version") public func mp_version() -> UnsafePointer<CChar> { UnsafePointer(versionString) }
@_cdecl("mp_abi") public func mp_abi() -> Int32 { 1 }

@_cdecl("mp_world_create") public func mp_world_create(_ seed: Int64, _ villages: Int32, _ per: Int32) -> OpaquePointer? {
    let w = OpenWorld(seed: Int(seed), budget: MemoryBudget(overrideMB: 1024))
    let s = Society(world: w, seed: Int(seed))
    s.bootstrap(origin: TilePos(0, 0), villages: Int(max(0, villages)), per: Int(max(0, per)))
    return OpaquePointer(Unmanaged.passRetained(WorldHandle(s)).toOpaque())
}

@_cdecl("mp_world_destroy") public func mp_world_destroy(_ p: OpaquePointer?) {
    guard let p = p else { return }
    Unmanaged<WorldHandle>.fromOpaque(UnsafeRawPointer(p)).release()
}

@_cdecl("mp_world_tick") public func mp_world_tick(_ p: OpaquePointer?, _ seconds: Double) {
    guard let h = world(p), seconds > 0 else { return }
    var left = seconds
    while left > 1e-9 { let dt = min(0.5, left); h.society.tick(dt); left -= dt }
}

@_cdecl("mp_world_time") public func mp_world_time(_ p: OpaquePointer?) -> Double { world(p)?.society.world.time ?? 0 }
@_cdecl("mp_world_population") public func mp_world_population(_ p: OpaquePointer?) -> Int32 { Int32(world(p)?.society.agents.count ?? 0) }

@_cdecl("mp_people_near") public func mp_people_near(_ p: OpaquePointer?, _ x: Float, _ z: Float, _ hw: Float, _ hh: Float,
                                                    _ out: UnsafeMutableRawPointer?, _ max: Int32) -> Int32 {
    guard let h = world(p), let out = out, max > 0 else { return 0 }
    let s = h.society
    let now = s.world.time
    let centre = Vec2(Double(x) * 16, Double(z) * 16)
    let shown = s.crowdSplit(center: centre, halfW: Double(hw) * 16, halfH: Double(hh) * 16, limit: Int(max)).shown
    let dst = out.bindMemory(to: MPPerson.self, capacity: Int(max))
    var n = 0
    for a in shown.prefix(Int(max)) {
        var r = MPPerson()
        r.id = Int32(truncatingIfNeeded: a.id)
        r.x = Float(a.pos.x / 16); r.z = Float(a.pos.y / 16)
        r.facing_x = Float(a.facing.x); r.facing_z = Float(a.facing.y)
        let st = a.stage(now)
        let working = a.task.map { $0.stage == 1 && ["chop", "mine", "build", "forage", "reap", "sow", "plant"].contains($0.act) } ?? false
        r.flags = (a.moving ? MP_MOVING : 0) | (a.sleeping ? MP_SLEEPING : 0) | (working ? MP_WORKING : 0) | (a.female ? MP_FEMALE : 0)
            | (st == "child" ? MP_CHILD : 0) | (st == "elder" ? MP_ELDER : 0)
        r.skin = hex(a.look.skin); r.hair = hex(st == "elder" && a.look.face.isEmpty ? "#e0e0e8" : a.look.hair)
        r.shirt = hex(a.look.shirt); r.pants = hex(a.look.pants); r.shoes = hex(a.look.shoes)
        r.style = Int32(a.look.style)
        fill(&r.model, a.look.model ?? "")
        fill(&r.held, st == "elder" ? "cane" : (jobTool[a.job] ?? ""))
        dst[n] = r
        n += 1
    }
    return Int32(n)
}

@_cdecl("mp_chunk_mesh") public func mp_chunk_mesh(_ p: OpaquePointer?, _ cx: Int32, _ cy: Int32, _ part: Int32) -> OpaquePointer? {
    guard let h = world(p) else { return nil }
    let w = h.society.world
    let input = ChunkInput3D(world: w, cx: Int(cx), cy: Int(cy))
    let cm = Mesher3D.build(input, gen: w.gen, anime: true)
    let m = part == 0 ? cm.ground : (part == 1 ? cm.solid : cm.sprites)
    guard !m.isEmpty else { return nil }
    var flipped = m
    if Mesher3D.flipV { flipped.uvs = m.uvs.map { SIMD2($0.x, 1 - $0.y) } }      // v from the top, whatever the phone uses
    return OpaquePointer(Unmanaged.passRetained(MeshHandle(flipped)).toOpaque())
}

@_cdecl("mp_chunk_ground_rgba") public func mp_chunk_ground_rgba(_ p: OpaquePointer?, _ cx: Int32, _ cy: Int32, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int32) -> Int32 {
    guard let h = world(p) else { return 0 }
    let w = h.society.world
    let input = ChunkInput3D(world: w, cx: Int(cx), cy: Int(cy))
    let relief = Mesher3D.build(input, gen: w.gen, anime: true).relief
    let b = AnimeArt.bakeGround(layers: input.layers, relief: relief)
    if let out = out, Int(cap) >= b.px.count { b.px.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: b.px.count) } }
    return Int32(b.w)
}

@_cdecl("mp_mesh_counts") public func mp_mesh_counts(_ p: OpaquePointer?, _ v: UnsafeMutablePointer<Int32>?, _ i: UnsafeMutablePointer<Int32>?) {
    let m = meshOf(p)?.mesh
    v?.pointee = Int32(m?.positions.count ?? 0)
    i?.pointee = Int32(m?.indices.count ?? 0)
}

@_cdecl("mp_mesh_copy") public func mp_mesh_copy(_ p: OpaquePointer?, _ pos: UnsafeMutablePointer<Float>?, _ nor: UnsafeMutablePointer<Float>?,
                                                _ uv: UnsafeMutablePointer<Float>?, _ idx: UnsafeMutablePointer<UInt32>?) {
    guard let m = meshOf(p)?.mesh else { return }
    for (i, v) in m.positions.enumerated() { pos?[i * 3] = v.x; pos?[i * 3 + 1] = v.y; pos?[i * 3 + 2] = v.z }
    for (i, v) in m.normals.enumerated() { nor?[i * 3] = v.x; nor?[i * 3 + 1] = v.y; nor?[i * 3 + 2] = v.z }
    for (i, v) in m.uvs.enumerated() { uv?[i * 2] = v.x; uv?[i * 2 + 1] = v.y }
    if let idx = idx { m.indices.withUnsafeBufferPointer { idx.update(from: $0.baseAddress!, count: m.indices.count) } }
}

@_cdecl("mp_mesh_free") public func mp_mesh_free(_ p: OpaquePointer?) {
    guard let p = p else { return }
    Unmanaged<MeshHandle>.fromOpaque(UnsafeRawPointer(p)).release()
}

@_cdecl("mp_palette_rgba") public func mp_palette_rgba(_ out: UnsafeMutablePointer<UInt8>?, _ cap: Int32) -> Int32 {
    let b = Palette3D.bitmap.animeGraded()
    if let out = out, Int(cap) >= b.px.count { b.px.withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: b.px.count) } }
    return Int32(b.w * 65536 + b.h)
}

@_cdecl("mp_person_glb") public func mp_person_glb(_ p: UnsafeRawPointer?, _ out: UnsafeMutablePointer<UInt8>?, _ cap: Int32) -> Int32 {
    guard let p = p else { return 0 }
    let r = p.load(as: MPPerson.self)
    var l = Look()
    l.skin = hexString(r.skin); l.hair = hexString(r.hair); l.shirt = hexString(r.shirt); l.pants = hexString(r.pants); l.shoes = hexString(r.shoes)
    l.style = Int(r.style)
    let model = read(r.model)
    l.model = model.isEmpty ? nil : model
    let child = r.flags & MP_CHILD != 0, female = r.flags & MP_FEMALE != 0
    guard let rig = Figure3D.animeRig(l, held: read(r.held), child: child, female: female, kind: .moe) else { return 0 }
    let d = GLTF.glb(rig, name: "person_\(r.id)")
    if let out = out, Int(cap) >= d.count { d.copyBytes(to: out, count: d.count) }
    return Int32(d.count)
}
