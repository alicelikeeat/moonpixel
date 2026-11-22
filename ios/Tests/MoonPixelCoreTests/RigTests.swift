import XCTest
import Foundation
@testable import MoonPixelCore

/// People as rigs: a skeleton named as Unreal's mannequin, every vertex on a bone, clips that move the
/// limbs the right way, and a glTF binary any engine reads.
final class RigTests: XCTestCase {
    func rig(_ kind: AnimeArt.Figure = .moe, female: Bool = true, child: Bool = false, held: String = "") -> Rig {
        var l = Look(); l.hair = "#f0a0c0"; l.shirt = "#5a8ae8"; l.style = 3
        return Figure3D.animeRig(l, held: held, child: child, female: female, kind: kind)!
    }
    func centre(_ m: Mesh3D, bone: HumanBone) -> SIMD3<Float> {
        var s = SIMD3<Float>(0, 0, 0), n: Float = 0
        for (i, b) in (m.bones ?? []).enumerated() where Int(b) == bone.rawValue { s += m.positions[i]; n += 1 }
        return n > 0 ? s / n : s
    }

    func testTheSkeletonIsTheMannequinsAndEveryVertexIsOnABone() {
        let r = rig()
        let names = r.skeleton.joints.map { $0.name }
        for n in ["root", "pelvis", "spine_01", "spine_03", "neck_01", "head", "upperarm_l", "lowerarm_r", "hand_l", "thigh_r", "calf_l", "foot_r"] { XCTAssertTrue(names.contains(n), n) }
        for (i, j) in r.skeleton.joints.enumerated() { if let p = j.parent { XCTAssertLessThan(p, i, "parents first") } }
        XCTAssertEqual(r.mesh.bones?.count, r.mesh.positions.count)
        // the parts are on the bones they hang from
        XCTAssertGreaterThan(centre(r.mesh, bone: .head).y, centre(r.mesh, bone: .spine_03).y)
        XCTAssertGreaterThan(centre(r.mesh, bone: .thigh_l).x, 0, "the figure's left is +x")
        XCTAssertLessThan(centre(r.mesh, bone: .foot_r).y, centre(r.mesh, bone: .calf_r).y)
        XCTAssertGreaterThan(r.mesh.bones!.filter { Int($0) == HumanBone.hand_l.rawValue }.count, 0)
        // in the bind pose the skin is the model
        let bind = r.posed([Quat](repeating: .identity, count: r.skeleton.joints.count))
        for (a, b) in zip(bind.positions, r.mesh.positions) { XCTAssertLessThan(((a - b) * (a - b)).sum(), 1e-10) }
        XCTAssertEqual(r.clips.map { $0.name }, HumanClips.names)
        let h = r.mesh.positions.map { $0.y }.max()! * r.metres
        XCTAssertEqual(h, 1.7 * 26 / 24, accuracy: 0.25, "an adult in metres (the ahoge a little over)")
    }

    func testTheClipsMoveTheLimbsTheRightWay() {
        let r = rig()
        let stand = r.mesh
        // the walk: a quarter of the way through the left leg is forward, three quarters back
        let a = r.posed("walk", at: 0.25), b = r.posed("walk", at: 0.75)
        XCTAssertGreaterThan(centre(a, bone: .foot_l).z, centre(stand, bone: .foot_l).z + 0.02, "left foot forward")
        XCTAssertLessThan(centre(b, bone: .foot_l).z, centre(stand, bone: .foot_l).z - 0.02, "then back")
        XCTAssertLessThan(centre(a, bone: .hand_l).z, centre(b, bone: .hand_l).z, "the left arm swings against the left leg")
        // the feet stay on the ground (not through it, not far over it)
        for t in stride(from: Float(0), to: 1, by: 0.1) {
            let m = r.posed("walk", at: t)
            XCTAssertGreaterThan(m.positions.map { $0.y }.min()!, -0.05, "t \(t)")
        }
        // work raises the tool hand over the head; wave raises the left hand out to the side
        let w = r.posed("work", at: 0.6 * 1.1)
        XCTAssertGreaterThan(centre(w, bone: .hand_l).y, centre(stand, bone: .head).y)
        let v = r.posed("wave", at: 0)
        XCTAssertGreaterThan(centre(v, bone: .hand_l).y, centre(stand, bone: .spine_03).y)
        XCTAssertGreaterThan(centre(v, bone: .hand_l).x, centre(stand, bone: .hand_l).x)
        // sitting lowers the hips and brings the knees forward
        let s = r.posed("sit", at: 0)
        XCTAssertLessThan(centre(s, bone: .pelvis).y, centre(stand, bone: .pelvis).y - 0.1)
        XCTAssertGreaterThan(centre(s, bone: .thigh_l).z, centre(stand, bone: .thigh_l).z + 0.05)
        // a loop ends where it starts
        for c in r.clips where c.loops {
            let p0 = c.sample(0), p1 = c.sample(c.duration * 0.9999)
            for (x, y) in zip(p0.rot, p1.rot) { XCTAssertEqual(abs(x.x * y.x + x.y * y.y + x.z * y.z + x.w * y.w), 1, accuracy: 0.01, c.name) }
        }
        // a quaternion turns as it should
        let q = Quat(axis: [0, 1, 0], angle: .pi / 2)
        let v1 = q.rotate([1, 0, 0])
        XCTAssertEqual(v1.z, -1, accuracy: 1e-5)
    }

    func testAGLTFBinaryWithTheSkinTheClipsAndTheColours() throws {
        let r = rig(held: "sword")
        let d = GLTF.glb(r, name: "moe_girl")
        func u32(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
        XCTAssertEqual(u32(0), 0x46546C67, "glTF")
        XCTAssertEqual(u32(4), 2)
        XCTAssertEqual(u32(8), d.count)
        let jl = u32(12)
        let json = try JSONSerialization.jsonObject(with: d.subdata(in: 20..<(20 + jl))) as! [String: Any]
        let binLen = u32(20 + jl)
        XCTAssertEqual(20 + jl + 8 + binLen, d.count)
        let skins = json["skins"] as! [[String: Any]]
        XCTAssertEqual((skins[0]["joints"] as! [Int]).count, r.skeleton.joints.count)
        XCTAssertEqual((json["animations"] as! [[String: Any]]).count, HumanClips.names.count)
        let views = json["bufferViews"] as! [[String: Any]]
        for v in views { XCTAssertLessThanOrEqual((v["byteOffset"] as! Int) + (v["byteLength"] as! Int), binLen); XCTAssertEqual((v["byteOffset"] as! Int) % 4, 0) }
        let nodes = json["nodes"] as! [[String: Any]]
        XCTAssertEqual(nodes.count, r.skeleton.joints.count + 1)
        XCTAssertEqual(nodes[1]["name"] as? String, "root")
        // the picture is a PNG
        let img = (json["images"] as! [[String: Any]])[0]
        let iv = views[img["bufferView"] as! Int]
        let at = 20 + jl + 8 + (iv["byteOffset"] as! Int)
        XCTAssertEqual(Array(d[at..<(at + 4)]), [0x89, 0x50, 0x4E, 0x47])
        if let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] {
            try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent("moe_girl.glb"))
            for (kind, female, child, name) in [(AnimeArt.Figure.moe, false, false, "moe_boy"), (.hero, false, false, "hero_man"), (.angel, true, false, "angel"), (.moe, true, true, "moe_child")] {
                try GLTF.glb(rig(kind, female: female, child: child), name: name).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".glb"))
            }
        }
    }
}

extension Anime3DPreviewTests {
    /// A sheet of a rigged person through each clip (MP_PREVIEW).
    func testPreviewRigClips() throws {
        guard let dir = ProcessInfo.processInfo.environment["MP_PREVIEW"] else { throw XCTSkip("set MP_PREVIEW") }
        let pal = Tex(b: Palette3D.bitmap.animeGraded())
        var l = Look(); l.hair = "#f0a0c0"; l.shirt = "#5a8ae8"; l.style = 3
        let cols = 6
        var sheet = Bitmap(cols * 140, HumanClips.names.count * 260, fill: RGBA(255, 255, 255))
        for (kind, female, file) in [(AnimeArt.Figure.moe, true, "rig_moe"), (.hero, false, "rig_hero")] {
            let r = Figure3D.animeRig(l, held: "sword", child: false, female: female, kind: kind)!
            for (row, c) in r.clips.enumerated() {
                for k in 0..<cols {
                    let m = r.posed(c.name, at: c.duration * Float(k) / Float(cols))
                    let img = render([(m, pal, false, SIMD3<Float>(0, 0, 0), Float(0))], size: (140, 260), yaw: 0.9, pitch: 0.15, scale: 230, centre: SIMD3(0, 0.45, 0))
                    sheet.blit(img, sx: 0, sy: 0, sw: 140, sh: 260, dx: k * 140, dy: row * 260, blend: false)
                }
            }
            var d = Data("\(sheet.w) \(sheet.h)\n".utf8); d.append(contentsOf: sheet.px)
            try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file + ".rgba"))
        }
    }
}
