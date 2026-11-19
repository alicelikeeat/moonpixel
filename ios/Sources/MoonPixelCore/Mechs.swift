import Foundation

// Humanoid frames and shifters (world warfare task book, phase 4).
//
// * A humanoid frame is large: it cannot squeeze through a narrow mountain pass that a tank takes, but it
//   wades a shallow strait that no vehicle can cross (Civ.passable). So tanks and frames reach different land.
// * A shifter (先锋变形机甲, an original design) is one machine with two forms: a vehicle, quick on roads and
//   sized like a vehicle; and a humanoid, sized like a frame. Both forms share one id, one hull, one store of
//   energy and the same damage. Changing form takes `shiftHours`; meanwhile it neither moves nor takes a
//   place. It cannot stand up where there is no room (a narrow pass): it says so and stays a vehicle.

extension Civ {
    /// A unit's size as it moves now (a shifter by its form).
    public func formSize(_ u: CivUnit) -> CivSize {
        guard u.kind == "shifter" else { return u.def.size }
        return u.form == "vehicle" ? .vehicle : .large
    }

    /// A unit's speed as it moves now (regions a day).
    public func formSpeed(_ u: CivUnit) -> Double {
        u.kind == "shifter" && u.form == "vehicle" ? u.def.speed * cfg.war.vehicleSpeed : u.def.speed
    }

    /// Is the unit changing form right now?
    public func shifting(_ u: CivUnit) -> Bool { (u.shiftDone ?? 0) > time }

    /// Change a shifter's form. Nil when it has begun (it is done after `shiftHours`); otherwise the reason it
    /// cannot: not a shifter, already changing, already in that form, or no room to stand up here.
    @discardableResult public func shift(_ uid: Int, to form: String) -> String? {
        guard var u = units[uid], u.kind == "shifter" else { return "not_a_shifter" }
        guard form == "vehicle" || form == "robot" else { return "unknown_form" }
        if shifting(u) { return "shifting" }
        if (u.form ?? "robot") == form { return "already" }
        if form == "robot", let f = u.force.flatMap({ forces[$0] }), let r = regions[f.region], r.mountain >= 0.35 {
            return "no_room"                       // a narrow pass: the humanoid form does not fit
        }
        u.form = form
        u.shiftDone = time + cfg.war.shiftHours * MP.daySeconds / 24
        units[uid] = u
        return nil
    }

    /// The reason in words, for the panel.
    public static func shiftReason(_ r: String, zh: Bool) -> String {
        switch r {
        case "no_room": return zh ? "空间不足：山口太窄，无法展开人形" : "no room: the pass is too narrow to stand up"
        case "shifting": return zh ? "正在变形" : "already changing"
        case "already": return zh ? "已是该形态" : "already in that form"
        default: return zh ? "不是变形机甲" : "not a shifter"
        }
    }
}
