import Foundation

// Export of rigs as glTF 2.0 binaries (.glb): the open standard Unreal (Interchange), Blender, Unity and Godot
// all import, with the skin (joints and their inverse bind matrices), every clip as an animation, and the
// colours as an embedded picture (the palette, or a person's strip of swatches) sampled without smoothing.
// glTF's conventions: y up, metres, a figure facing +z, right-handed (Unreal turns it into its own on import).

public enum GLTF {
    /// A rig as a .glb, scaled to metres; `texture` is what its texture coordinates point into (the palette when
    /// none is given).
    public static func glb(_ rig: Rig, name: String, texture: Bitmap? = nil) -> Data {
        var bin = Data()
        var views: [[String: Any]] = [], accessors: [[String: Any]] = []
        func align() { while bin.count % 4 != 0 { bin.append(0) } }
        func view(_ d: Data, target: Int? = nil) -> Int {
            align()
            var v: [String: Any] = ["buffer": 0, "byteOffset": bin.count, "byteLength": d.count]
            if let t = target { v["target"] = t }
            bin.append(d)
            views.append(v)
            return views.count - 1
        }
        func accessor(_ d: Data, type: String, component: Int, count: Int, normalized: Bool = false, target: Int? = nil, minMax: ([Float], [Float])? = nil) -> Int {
            var a: [String: Any] = ["bufferView": view(d, target: target), "componentType": component, "count": count, "type": type]
            if normalized { a["normalized"] = true }
            if let (lo, hi) = minMax { a["min"] = lo; a["max"] = hi }
            accessors.append(a)
            return accessors.count - 1
        }
        func floats(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }
        let k = rig.metres
        let m = rig.mesh
        let FLOAT = 5126, UBYTE = 5121, UINT = 5125, ARRAY = 34962, ELEMENTS = 34963

        // the mesh
        let pos = m.positions.flatMap { [$0.x * k, $0.y * k, $0.z * k] }
        var lo: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude], hi: [Float] = [-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        for p in m.positions { for c in 0..<3 { lo[c] = min(lo[c], p[c] * k); hi[c] = max(hi[c], p[c] * k) } }
        let aPos = accessor(floats(pos), type: "VEC3", component: FLOAT, count: m.positions.count, target: ARRAY, minMax: (lo, hi))
        let aNor = accessor(floats(m.normals.flatMap { n -> [Float] in let l = max(1e-9, (n * n).sum().squareRoot()); return [n.x / l, n.y / l, n.z / l] }), type: "VEC3", component: FLOAT, count: m.normals.count, target: ARRAY)
        let aUV = accessor(floats(m.uvs.flatMap { [$0.x, $0.y] }), type: "VEC2", component: FLOAT, count: m.uvs.count, target: ARRAY)
        let bones = m.bones ?? [UInt8](repeating: 0, count: m.positions.count)
        let aJoi = accessor(Data(bones.flatMap { [$0, 0, 0, 0] }), type: "VEC4", component: UBYTE, count: bones.count, target: ARRAY)
        let aWei = accessor(floats(bones.flatMap { _ in [Float(1), 0, 0, 0] }), type: "VEC4", component: FLOAT, count: bones.count, target: ARRAY)
        let aIdx = accessor(m.indices.withUnsafeBufferPointer { Data(buffer: $0) }, type: "SCALAR", component: UINT, count: m.indices.count, target: ELEMENTS)

        // the skeleton: joint nodes after the mesh's node, their inverse bind matrices (column-major)
        let sk = rig.skeleton
        let bind = sk.bindPositions
        let ibm = bind.flatMap { p -> [Float] in [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p.x * k, -p.y * k, -p.z * k, 1] }
        let aIBM = accessor(floats(ibm), type: "MAT4", component: FLOAT, count: bind.count)
        var nodes: [[String: Any]] = [["name": name, "mesh": 0, "skin": 0]]
        for (i, j) in sk.joints.enumerated() {
            var n: [String: Any] = ["name": j.name, "translation": [j.rest.x * k, j.rest.y * k, j.rest.z * k]]
            let kids = sk.joints.indices.filter { sk.joints[$0].parent == i }.map { $0 + 1 }
            if !kids.isEmpty { n["children"] = kids }
            nodes.append(n)
        }
        let roots = sk.joints.indices.filter { sk.joints[$0].parent == nil }.map { $0 + 1 }

        // the clips
        var animations: [[String: Any]] = []
        for c in rig.clips where !c.times.isEmpty {
            let aT = accessor(floats(c.times), type: "SCALAR", component: FLOAT, count: c.times.count, minMax: ([c.times.first!], [c.times.last!]))
            var samplers: [[String: Any]] = [], channels: [[String: Any]] = []
            for j in sk.joints.indices {
                let rot = c.keys.flatMap { keys -> [Float] in let q = (j < keys.count ? keys[j] : .identity).normalized; return [q.x, q.y, q.z, q.w] }
                samplers.append(["input": aT, "output": accessor(floats(rot), type: "VEC4", component: FLOAT, count: c.keys.count), "interpolation": "LINEAR"])
                channels.append(["sampler": samplers.count - 1, "target": ["node": j + 1, "path": "rotation"]])
            }
            for r in sk.joints.indices where sk.joints[r].parent == nil {
                let tr = c.rootMoves.flatMap { mv -> [Float] in let p = sk.joints[r].rest + mv; return [p.x * k, p.y * k, p.z * k] }
                samplers.append(["input": aT, "output": accessor(floats(tr), type: "VEC3", component: FLOAT, count: c.rootMoves.count), "interpolation": "LINEAR"])
                channels.append(["sampler": samplers.count - 1, "target": ["node": r + 1, "path": "translation"]])
            }
            animations.append(["name": c.name, "samplers": samplers, "channels": channels])
        }

        // the colours: a picture, sampled exactly (the coordinates are the middles of its pixels)
        let png = PNG.encode(texture ?? Palette3D.bitmap.animeGraded())
        let imgView = view(png)

        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "MoonPixel"],
            "extensionsUsed": ["KHR_materials_unlit"],
            "scene": 0,
            "scenes": [["name": name, "nodes": [0] + roots]],
            "nodes": nodes,
            "meshes": [["name": name, "primitives": [[
                "attributes": ["POSITION": aPos, "NORMAL": aNor, "TEXCOORD_0": aUV, "JOINTS_0": aJoi, "WEIGHTS_0": aWei],
                "indices": aIdx, "material": 0, "mode": 4,
            ]]]],
            "skins": [["name": name + "_skeleton", "joints": Array(1...sk.joints.count), "inverseBindMatrices": aIBM, "skeleton": roots.first ?? 1]],
            "animations": animations,
            "materials": [["name": name + "_colours",
                           "pbrMetallicRoughness": ["baseColorTexture": ["index": 0], "metallicFactor": 0, "roughnessFactor": 1],
                           "extensions": ["KHR_materials_unlit": [String: Any]()]]],
            "textures": [["sampler": 0, "source": 0]],
            "samplers": [["magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071]],
            "images": [["bufferView": imgView, "mimeType": "image/png"]],
            "accessors": accessors,
            "bufferViews": views,
            "buffers": [["byteLength": bin.count]],
        ]
        align()
        var js = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
        while js.count % 4 != 0 { js.append(0x20) }
        var out = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        u32(0x46546C67); u32(2); u32(12 + 8 + js.count + 8 + bin.count)
        u32(js.count); u32(0x4E4F534A); out.append(js)
        u32(bin.count); u32(0x004E4942); out.append(bin)
        return out
    }
}

/// PNG pictures (stored without compression: small pictures, no dependencies).
public enum PNG {
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    public static func encode(_ b: Bitmap) -> Data {
        var raw = Data(capacity: (b.w * 4 + 1) * b.h)
        for y in 0..<b.h { raw.append(0); raw.append(contentsOf: b.px[(y * b.w * 4)..<((y + 1) * b.w * 4)]) }
        // zlib, stored blocks
        var z = Data([0x78, 0x01])
        var i = 0
        repeat {
            let n = min(65535, raw.count - i)
            let last: UInt8 = i + n >= raw.count ? 1 : 0
            z.append(last)
            z.append(UInt8(n & 0xFF)); z.append(UInt8(n >> 8))
            z.append(UInt8(~n & 0xFF)); z.append(UInt8((~n >> 8) & 0xFF))
            z.append(raw[raw.startIndex.advanced(by: i)..<raw.startIndex.advanced(by: i + n)])
            i += n
        } while i < raw.count
        var a: UInt32 = 1, s: UInt32 = 0
        for v in raw { a = (a + UInt32(v)) % 65521; s = (s + a) % 65521 }
        for v in [s >> 8, s, a >> 8, a] { z.append(UInt8(v & 0xFF)) }

        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        func chunk(_ type: String, _ body: Data) {
            var len = UInt32(body.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            var tb = Data(type.utf8); tb.append(body)
            out.append(tb)
            var c = crc(tb).bigEndian
            withUnsafeBytes(of: &c) { out.append(contentsOf: $0) }
        }
        var ihdr = Data()
        for v in [UInt32(b.w), UInt32(b.h)] { var x = v.bigEndian; withUnsafeBytes(of: &x) { ihdr.append(contentsOf: $0) } }
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])                 // 8-bit RGBA
        chunk("IHDR", ihdr)
        chunk("IDAT", z)
        chunk("IEND", Data())
        return out
    }
}
