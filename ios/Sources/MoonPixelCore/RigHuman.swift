import Foundation

// The people's skeleton (named as the Unreal mannequin's bones) and their clips: idle, walk, run, work, strike,
// wave, sit. The clips are written as poses over time, then sampled into keys (what the runtime blends and the
// exporter writes), so a clip made by hand, captured or imported later is the same kind of thing.

public enum HumanBone: Int, CaseIterable {
    case root, pelvis, spine_01, spine_02, spine_03, neck_01, head
    case clavicle_l, upperarm_l, lowerarm_l, hand_l
    case clavicle_r, upperarm_r, lowerarm_r, hand_r
    case thigh_l, calf_l, foot_l
    case thigh_r, calf_r, foot_r

    public var name: String { String(describing: self) }

    var parent: HumanBone? {
        switch self {
        case .root: return nil
        case .pelvis: return .root
        case .spine_01: return .pelvis
        case .spine_02: return .spine_01
        case .spine_03: return .spine_02
        case .neck_01: return .spine_03
        case .head: return .neck_01
        case .clavicle_l, .clavicle_r: return .spine_03
        case .upperarm_l: return .clavicle_l
        case .lowerarm_l: return .upperarm_l
        case .hand_l: return .lowerarm_l
        case .upperarm_r: return .clavicle_r
        case .lowerarm_r: return .upperarm_r
        case .hand_r: return .lowerarm_r
        case .thigh_l, .thigh_r: return .pelvis
        case .calf_l: return .thigh_l
        case .foot_l: return .calf_l
        case .calf_r: return .thigh_r
        case .foot_r: return .calf_r
        }
    }

    static func thigh(_ left: Bool) -> UInt8 { UInt8((left ? thigh_l : thigh_r).rawValue) }
    static func calf(_ left: Bool) -> UInt8 { UInt8((left ? calf_l : calf_r).rawValue) }
    static func foot(_ left: Bool) -> UInt8 { UInt8((left ? foot_l : foot_r).rawValue) }
    static func upperarm(_ left: Bool) -> UInt8 { UInt8((left ? upperarm_l : upperarm_r).rawValue) }
    static func lowerarm(_ left: Bool) -> UInt8 { UInt8((left ? lowerarm_l : lowerarm_r).rawValue) }
    static func hand(_ left: Bool) -> UInt8 { UInt8((left ? hand_l : hand_r).rawValue) }
}

extension Mesh3D {
    /// The bone the next faces are bound to (a `HumanBone` raw value in a person's model).
    mutating func bind(_ b: HumanBone) { bone = UInt8(b.rawValue) }
}

extension Skeleton {
    /// A person's skeleton from where its joints are in the bind pose (model space).
    public static func human(_ at: [HumanBone: SIMD3<Float>]) -> Skeleton {
        var s = Skeleton()
        for b in HumanBone.allCases {
            let p = at[b] ?? .zero
            let parentAt = b.parent.map { at[$0] ?? .zero } ?? .zero
            s.joints.append(Joint(name: b.name, parent: b.parent?.rawValue, rest: p - parentAt))
        }
        return s
    }
}

extension Figure3D {
    /// The joints of an anime person in the bind pose (standing, arms down), where the model's parts hang
    /// from them.
    static func animeJoints(kind: AnimeArt.Figure, child: Bool) -> [HumanBone: SIMD3<Float>] {
        let b = kind == .hero && !child ? AnimeBody.hero : AnimeBody.moe
        let u = (child ? 0.7 : 1) * personScale / 16
        func P(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(x, y, z) * u }
        var j: [HumanBone: SIMD3<Float>] = [.root: .zero]
        j[.pelvis] = P(0, b.hipY + 0.4, 0)
        j[.spine_01] = P(0, b.hipY + 1.4, 0)
        j[.spine_02] = P(0, b.waistY, 0)
        j[.spine_03] = P(0, b.chestY - 0.4, 0)
        j[.neck_01] = P(0, b.neckY - 0.2, 0)
        j[.head] = P(0, b.neckY + 1.2, 0)
        for (left, s) in [(true, Float(1)), (false, Float(-1))] {
            j[left ? .clavicle_l : .clavicle_r] = P(s * b.shoulderX * 0.35, b.shoulderY - 0.2, 0)
            j[left ? .upperarm_l : .upperarm_r] = P(s * b.shoulderX, b.shoulderY, 0)
            j[left ? .lowerarm_l : .lowerarm_r] = P(s * (b.shoulderX + 0.5), b.shoulderY - 3.2, 0)
            j[left ? .hand_l : .hand_r] = P(s * (b.shoulderX + 0.7), b.shoulderY - 6.2, 0)
            j[left ? .thigh_l : .thigh_r] = P(s * b.legX, b.hipY, 0)
            j[left ? .calf_l : .calf_r] = P(s * b.legX * 1.05, b.kneeY, 0.3)
            j[left ? .foot_l : .foot_r] = P(s * b.legX * 1.05, 1.3, 0)
        }
        return j
    }

    /// An anime person as a rig: the model in the bind pose with every vertex on a bone, the skeleton, and
    /// the people's clips. Nil for a character model (its own figure: rigged in its turn).
    public static func animeRig(_ look: Look, held: String, child: Bool, female: Bool, kind: AnimeArt.Figure = AnimeArt.figure,
                                lite: Bool = false, book: SwatchBook? = nil, ink: Float? = 0.025) -> Rig? {
        guard CharacterModels.of(look.model) == nil else { return nil }
        // the model is built bound: every face made while a bone is set goes on it
        var m = Figure3D.anime(look, frame: 0, held: held, child: child, female: female, kind: kind, lite: lite, book: book, rigged: true)
        if let w = ink { m = m.inked(width: w) }
        let sk = Skeleton.human(animeJoints(kind: kind, child: child))
        var r = Rig(mesh: m, skeleton: sk)
        r.metres = 1.7 / adultHeight
        r.clips = HumanClips.all(sk, child: child)
        return r
    }
}

/// The people's clips. Angles in radians about the model's axes: about x a limb swings forward (negative)
/// and back (positive), the spine leans forward (positive); about z an arm is raised out to the side.
public enum HumanClips {
    public static let names = ["idle", "walk", "run", "work", "strike", "wave", "sit"]

    public static func all(_ s: Skeleton, child: Bool) -> [Clip] {
        let n = s.joints.count
        let legLen = (s.bindPositions[HumanBone.thigh_l.rawValue].y - s.bindPositions[HumanBone.foot_l.rawValue].y)
        func q(_ rx: Float, _ ry: Float = 0, _ rz: Float = 0) -> Quat { .euler(rx, ry, rz) }
        typealias B = HumanBone
        func pose(_ d: [B: Quat]) -> [Int: Quat] { Dictionary(uniqueKeysWithValues: d.map { ($0.key.rawValue, $0.value) }) }
        let tau = 2 * Float.pi
        var clips: [Clip] = []

        // idle: breathing, a slow look round, the arms hanging easy
        clips.append(Clip(name: "idle", duration: 3.2, loops: true, joints: n) { t in
            let ph = tau * t / 3.2
            return (pose([.spine_02: q(0.03 * sin(ph)), .spine_03: q(0.02 * sin(ph)),
                          .head: q(0.02 * sin(ph + 1), 0.12 * sin(ph / 2)),
                          .upperarm_l: q(0.04 * sin(ph), 0, 0.08), .upperarm_r: q(0.04 * sin(ph), 0, -0.08),
                          .lowerarm_l: q(-0.12), .lowerarm_r: q(-0.12)]), SIMD3(0, 0.004 * legLen * sin(ph), 0))
        })
        // walk and run: legs in opposite swing, the knee bending as the leg comes through, arms against the legs
        func gait(_ name: String, period: Float, stride: Float, knee: Float, arm: Float, lean: Float, bob: Float) -> Clip {
            Clip(name: name, duration: period, loops: true, joints: n) { t in
                let ph = tau * t / period
                let l = sin(ph), r = sin(ph + .pi)
                func kneeBend(_ p: Float) -> Float { knee * max(0, sin(p - 0.6)) + 0.05 }
                return (pose([.thigh_l: q(-stride * l), .thigh_r: q(-stride * r),
                              .calf_l: q(kneeBend(ph)), .calf_r: q(kneeBend(ph + .pi)),
                              .foot_l: q(-0.2 * max(0, -l)), .foot_r: q(-0.2 * max(0, -r)),
                              .upperarm_l: q(arm * l, 0, 0.1), .upperarm_r: q(arm * r, 0, -0.1),
                              .lowerarm_l: q(-0.3 - arm * 0.5 * max(0, -l)), .lowerarm_r: q(-0.3 - arm * 0.5 * max(0, -r)),
                              .pelvis: q(0, 0.08 * sin(ph)), .spine_01: q(lean, -0.12 * sin(ph)),
                              .head: q(-lean * 0.6)]),
                        SIMD3(0, bob * legLen * abs(cos(ph)), 0))
            }
        }
        clips.append(gait("walk", period: 1.0, stride: 0.42, knee: 0.7, arm: 0.38, lean: 0.04, bob: 0.025))
        clips.append(gait("run", period: 0.62, stride: 0.75, knee: 1.35, arm: 0.8, lean: 0.22, bob: 0.06))
        // work: the tool raised high over the shoulder and brought down, the back bending into it
        clips.append(Clip(name: "work", duration: 1.1, loops: true, joints: n) { t in
            let f = t / 1.1
            let lift = f < 0.6 ? f / 0.6 : 1 - (f - 0.6) / 0.4                         // slow up, fast down
            let up = lift * lift * (3 - 2 * lift)
            return (pose([.upperarm_l: q(-0.5 - 2.6 * up, 0, 0.12), .lowerarm_l: q(-0.35 * up - 0.15),
                          .upperarm_r: q(-0.4 - 2.3 * up, 0, -0.12), .lowerarm_r: q(-0.4 * up - 0.25),
                          .spine_01: q(0.2 - 0.26 * up), .spine_03: q(0.06 - 0.1 * up), .head: q(0.05 * (1 - up) - 0.1 * up),
                          .thigh_l: q(-0.25), .thigh_r: q(0.15), .calf_l: q(0.3), .calf_r: q(0.2)]),
                    SIMD3(0, -0.03 * legLen * (1 - up), 0))
        })
        // strike: a quick cut from high on the left across and down
        clips.append(Clip(name: "strike", duration: 0.55, loops: false, joints: n) { t in
            let f = t / 0.55
            let a = f < 0.35 ? f / 0.35 : 1 - min(1, (f - 0.35) / 0.4)
            return (pose([.upperarm_l: q(-0.5 - 2.2 * a, 0.3 * (1 - a), 0.5 * a), .lowerarm_l: q(-0.6 * a - 0.2),
                          .spine_01: q(0.2 * (1 - a), 0.5 * (1 - a) - 0.25), .thigh_l: q(-0.4), .calf_l: q(0.35), .thigh_r: q(0.25)]),
                    SIMD3(0, -0.02 * legLen, 0))
        })
        // wave: the left arm up and out, the forearm waving
        clips.append(Clip(name: "wave", duration: 1.2, loops: true, joints: n) { t in
            let ph = tau * t / 0.6
            return (pose([.upperarm_l: q(-0.2, 0, 2.5), .lowerarm_l: q(0, 0, 0.35 * sin(ph)), .hand_l: q(0, 0, 0.2 * sin(ph)),
                          .head: q(0, 0.15), .spine_03: q(0, 0, -0.05)]), .zero)
        })
        // sit: thighs forward level, shins down, hands on the knees
        clips.append(Clip(name: "sit", duration: 1, loops: true, joints: n) { _ in
            (pose([.thigh_l: q(-1.5), .thigh_r: q(-1.5), .calf_l: q(1.5), .calf_r: q(1.5),
                   .upperarm_l: q(-0.6), .upperarm_r: q(-0.6), .lowerarm_l: q(-0.5), .lowerarm_r: q(-0.5), .spine_01: q(-0.05)]),
             SIMD3(0, -0.45 * legLen, 0))
        })
        return clips
    }
}
