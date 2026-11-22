import Foundation

// Skeletons, skinning and animation clips: engine-agnostic (no graphics framework), so the same rigs are
// tested here, drawn by RealityKit on the phone, and exported (GLTF.swift) for Unreal on the PC.
//
// A rig is a mesh in its bind pose whose every vertex is bound to a bone, and a skeleton: joints with a parent
// and a rest offset from it (no rest rotation: every joint's axes are the model's axes in the bind pose, so
// an animation's rotations read the same on every joint). Joint names follow the Unreal mannequin's (pelvis,
// spine_01, thigh_l...), so Unreal's retargeting maps our clips onto its skeletons and theirs onto ours.
// Left and right are the figure's own: it faces +z with y up, so its left side is +x.

/// A rotation.
public struct Quat: Equatable {
    public var x: Float, y: Float, z: Float, w: Float
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
    public static let identity = Quat(0, 0, 0, 1)
    public init(axis: SIMD3<Float>, angle: Float) {
        let l = (axis * axis).sum().squareRoot()
        let a = l > 1e-9 ? axis / l : SIMD3<Float>(1, 0, 0)
        let s = sin(angle / 2)
        self.init(a.x * s, a.y * s, a.z * s, cos(angle / 2))
    }
    /// Rotations about x, then y, then z (radians), the order a limb is swung, turned and raised in.
    public static func euler(_ rx: Float, _ ry: Float = 0, _ rz: Float = 0) -> Quat {
        Quat(axis: [0, 0, 1], angle: rz) * Quat(axis: [0, 1, 0], angle: ry) * Quat(axis: [1, 0, 0], angle: rx)
    }
    public static func * (a: Quat, b: Quat) -> Quat {
        Quat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
             a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
             a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }
    public func rotate(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let q = SIMD3(x, y, z)
        let t = 2 * Quat.cross(q, v)
        return v + w * t + Quat.cross(q, t)
    }
    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    public var normalized: Quat { let l = (x * x + y * y + z * z + w * w).squareRoot(); return l > 1e-9 ? Quat(x / l, y / l, z / l, w / l) : .identity }
    /// The shortest way between two rotations, a fraction `t` along it.
    public static func slerp(_ a: Quat, _ b0: Quat, _ t: Float) -> Quat {
        var b = b0
        var d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
        if d < 0 { b = Quat(-b.x, -b.y, -b.z, -b.w); d = -d }
        if d > 0.9995 { return Quat(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t).normalized }
        let th = acos(d), s = sin(th)
        let ka = sin((1 - t) * th) / s, kb = sin(t * th) / s
        return Quat(a.x * ka + b.x * kb, a.y * ka + b.y * kb, a.z * ka + b.z * kb, a.w * ka + b.w * kb)
    }
}

/// A placement: rotate, then move.
public struct Xform {
    public var r: Quat, t: SIMD3<Float>
    public init(r: Quat = .identity, t: SIMD3<Float> = .zero) { self.r = r; self.t = t }
    public func apply(_ p: SIMD3<Float>) -> SIMD3<Float> { r.rotate(p) + t }
    public static func * (a: Xform, b: Xform) -> Xform { Xform(r: a.r * b.r, t: a.apply(b.t)) }
}

public struct Joint {
    public let name: String
    public let parent: Int?
    /// Where it sits in the bind pose, relative to its parent (in the model's units).
    public let rest: SIMD3<Float>
}

public struct Skeleton {
    public var joints: [Joint] = []
    public init() {}
    public func index(_ name: String) -> Int? { joints.firstIndex { $0.name == name } }

    /// Where every joint is in the bind pose (model space).
    public var bindPositions: [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for j in joints { out.append((j.parent.map { out[$0] } ?? .zero) + j.rest) }
        return out
    }

    /// Every joint's placement in model space for local rotations by joint (missing: none) and a move of the
    /// root joint.
    public func globals(_ rot: [Quat], rootMove: SIMD3<Float> = .zero) -> [Xform] {
        var out: [Xform] = []
        out.reserveCapacity(joints.count)
        for (i, j) in joints.enumerated() {
            let local = Xform(r: i < rot.count ? rot[i] : .identity, t: j.rest + (j.parent == nil ? rootMove : .zero))
            out.append(j.parent.map { out[$0] * local } ?? local)
        }
        return out
    }

    /// The skinning placement of each joint: from its bind pose to where `globals` put it.
    public func skinning(_ globals: [Xform]) -> [Xform] {
        let bind = bindPositions
        return globals.enumerated().map { i, g in g * Xform(t: -bind[i]) }
    }
}

/// An animation: each joint's rotation at a run of times, and the root's move (a walk's bob).
public struct Clip {
    public let name: String
    public let duration: Float
    public let loops: Bool
    public var times: [Float] = []
    /// keys[k][joint]
    public var keys: [[Quat]] = []
    public var rootMoves: [SIMD3<Float>] = []

    public init(name: String, duration: Float, loops: Bool) { self.name = name; self.duration = duration; self.loops = loops }

    /// Sampled from a pose function at `fps` (t from 0 to the duration).
    public init(name: String, duration: Float, loops: Bool, fps: Float = 30, joints: Int, pose: (Float) -> (rot: [Int: Quat], root: SIMD3<Float>)) {
        self.init(name: name, duration: duration, loops: loops)
        let n = max(2, Int((duration * fps).rounded()) + 1)
        for k in 0..<n {
            let t = duration * Float(k) / Float(n - 1)
            let p = pose(t)
            times.append(t)
            keys.append((0..<joints).map { p.rot[$0] ?? .identity })
            rootMoves.append(p.root)
        }
    }

    /// The pose at a time (wrapped round for a loop, held at the end otherwise).
    public func sample(_ t0: Float) -> (rot: [Quat], root: SIMD3<Float>) {
        guard let last = times.last, !times.isEmpty else { return ([], .zero) }
        var t = t0
        if loops && duration > 0 { t = t.truncatingRemainder(dividingBy: duration); if t < 0 { t += duration } }
        t = max(0, min(last, t))
        var hi = 1
        while hi < times.count - 1 && times[hi] < t { hi += 1 }
        let lo = max(0, hi - 1)
        let span = times[hi] - times[lo]
        let f = span > 1e-6 ? (t - times[lo]) / span : 0
        let rot = zip(keys[lo], keys[hi]).map { Quat.slerp($0, $1, f) }
        return (rot, rootMoves[lo] + (rootMoves[hi] - rootMoves[lo]) * f)
    }
}

/// A skinned model: a mesh in the bind pose, its skeleton, and its clips.
public struct Rig {
    public var mesh: Mesh3D
    public var skeleton: Skeleton
    public var clips: [Clip] = []
    /// Model units to metres (an adult about 1.7 m tall).
    public var metres: Float = 1

    public func clip(_ name: String) -> Clip? { clips.first { $0.name == name } }

    /// The mesh posed by local joint rotations (skinned on the CPU: for previews, tests and the far LOD).
    public func posed(_ rot: [Quat], rootMove: SIMD3<Float> = .zero) -> Mesh3D {
        let skin = skeleton.skinning(skeleton.globals(rot, rootMove: rootMove))
        var m = mesh
        guard let bones = mesh.bones else { return m }
        for i in 0..<m.positions.count {
            let s = skin[Int(bones[i])]
            m.positions[i] = s.apply(mesh.positions[i])
            m.normals[i] = s.r.rotate(mesh.normals[i])
        }
        return m
    }

    /// The mesh at a time of a clip.
    public func posed(_ clip: String, at t: Float) -> Mesh3D {
        guard let c = self.clip(clip) else { return mesh }
        let p = c.sample(t)
        return posed(p.rot, rootMove: p.root)
    }
}
