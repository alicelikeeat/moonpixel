import Foundation

// One unit, one id, whoever is at the controls (world warfare task book, sections 4 and 5).
//
// The player takes the controls of a machine of the world (a carrier, a frame, a shifter, a sky carrier, an
// aircraft): it is the same unit, with the same id, the same damage, stores and crew, and the same order and
// way it was on. While the player has it, the computer gives it (and the force it is in) no new orders; the
// player sends it where they want, changes a shifter's form, drops a frame from a sky carrier, or switches
// from a carrier to one of its aircraft and back. When they let go, the computer carries on from where the
// unit is, with whatever order it has: nothing is restarted, copied or lost.

extension Civ {
    /// The unit the player is at the controls of, if any.
    public var pilotedUnit: Int? { units.values.filter { $0.pilot == true }.map { $0.id }.min() }

    /// Is the player at the controls of a unit in this force?
    public func piloted(_ f: CivForce) -> Bool { f.units.contains { units[$0]?.pilot == true } }

    /// Take the controls of a unit of `nation`. Nil when done, or why not.
    @discardableResult public func takeControl(_ uid: Int, nation: Int) -> String? {
        guard var u = units[uid] else { return "no_unit" }
        guard u.nation == nation else { return "not_ours" }
        if drops.contains(where: { $0.unit == uid }) { return "falling" }
        if u.force == nil { return "in_depot" }
        for k in units.keys.sorted() where units[k]?.pilot == true && k != uid { units[k]!.pilot = nil }
        u.pilot = true
        units[uid] = u
        return nil
    }

    /// Let go: the computer carries on with the unit as it is.
    public func releaseControl() {
        for k in units.keys.sorted() where units[k]?.pilot == true { units[k]!.pilot = nil }
    }

    /// Send the unit the player is flying or driving to a region (to fight there when `attack`). An aircraft
    /// on a deck takes off for it; one in the air turns to it. Nil when on its way, or why not.
    @discardableResult public func pilotGo(to k: Int64, attack: Bool = true) -> String? {
        guard let uid = pilotedUnit, var u = units[uid], let f = u.force.flatMap({ forces[$0] }) else { return "no_pilot" }
        if shifting(u) { return "shifting" }
        if u.def.carrierBased || u.def.layer == .lowAir, u.def.hangar == 0 {
            switch u.air {
            case .parked:
                guard u.fuel > 0 || u.def.fuelCap == 0 else { return "no_fuel" }
                let reach = Int(u.def.endurance * u.def.speed / 24 / 2)
                guard dist(k, f.region) <= reach else { return "out_of_reach" }
                u.air = .airborne; u.at = f.region; u.target = k; u.aloft = u.def.endurance
                u.fuel = max(0, u.fuel - u.def.fuelCap * 0.5)
                units[uid] = u
                fight("launch", u.kind, "", [u.nation], f.region)
                return nil
            case .airborne:
                u.target = k; units[uid] = u; return nil
            default: return "busy"
            }
        }
        return send(f.id, to: k, attack: attack) ? nil : "no_way"
    }

    /// From a carrier (or sky carrier) the player is on, take the controls of one of its aircraft on deck.
    @discardableResult public func switchToAircraft() -> Int? {
        guard let uid = pilotedUnit, let u = units[uid], u.def.hangar > 0, let f = u.force.flatMap({ forces[$0] }) else { return nil }
        guard let a = f.units.compactMap({ units[$0] }).filter({ ($0.def.carrierBased || $0.def.layer == .lowAir) && $0.def.hangar == 0 && $0.air == .parked }).min(by: { $0.id < $1.id }) else { return nil }
        units[uid]!.pilot = nil
        units[a.id]!.pilot = true
        return a.id
    }

    /// From an aircraft, back to the carrier it belongs to (wherever the carrier is now).
    @discardableResult public func switchToCarrier() -> Int? {
        guard let uid = pilotedUnit, let u = units[uid], let f = u.force.flatMap({ forces[$0] }) else { return nil }
        guard let c = f.units.compactMap({ units[$0] }).first(where: { $0.def.hangar > 0 }) else { return nil }
        units[uid]!.pilot = nil
        units[c.id]!.pilot = true
        return c.id
    }

    /// What the panel says about a unit: whose it is, where, doing what, and when it gets there.
    public func unitLine(_ uid: Int, zh: Bool) -> String {
        guard let u = units[uid] else { return "" }
        let def = u.def
        let owner = polities[u.nation]?.name(zh: zh) ?? "#\(u.nation)"
        let f = u.force.flatMap { forces[$0] }
        let at = f.map { "(\(MP.keyCX($0.region)), \(MP.keyCY($0.region)))" } ?? (zh ? "库中" : "in depot")
        var task: String
        if drops.contains(where: { $0.unit == uid }) { task = zh ? "空投中" : "falling" }
        else if shifting(u) { task = zh ? "变形中" : "changing form" }
        else if u.air == .airborne { task = zh ? "飞行任务" : "on a mission" }
        else if u.air == .returning { task = zh ? "返航" : "coming back" }
        else if u.air == .parked { task = zh ? "在机库待命" : "on deck" }
        else if let f = f, !f.path.isEmpty {
            let days = (Double(f.path.count) - f.progress) / max(0.1, f.units.compactMap { units[$0] }.map { formSpeed($0) }.min() ?? 1)
            task = zh ? String(format: "行进中，约 %.1f 天后抵达", days) : String(format: "on the way, about %.1f days to go", days)
        } else { task = zh ? "驻留" : "holding" }
        var extra = ""
        if def.hangar > 0, let f = f {
            let aboard = f.units.compactMap { units[$0] }.filter { ($0.def.carrierBased || $0.def.layer == .lowAir || ["frame", "shifter"].contains($0.kind)) && $0.def.hangar == 0 }
            extra = zh ? " · 机库 \(aboard.count) 架" : " · \(aboard.count) in the hangar"
        }
        if u.kind == "shifter" { extra += zh ? (u.form == "vehicle" ? " · 车辆形态" : " · 人形形态") : (u.form == "vehicle" ? " · vehicle form" : " · humanoid form") }
        let hp = Int(100 * u.hp / max(1, def.hp))
        return "\(zh ? def.zh : def.en) #\(u.id) · \(owner) · \(at) · \(task) · \(zh ? "完好" : "condition") \(hp)%\(extra)" + (u.pilot == true ? (zh ? " · 你在驾驶" : " · you are at the controls") : "")
    }

    /// The special units of a nation (carriers, frames, shifters, sky carriers), in id order.
    public func specialUnits(of n: Int) -> [Int] {
        units.values.filter { $0.nation == n && ["carrier", "frame", "shifter", "sky_carrier"].contains($0.kind) }.map { $0.id }.sorted()
    }
}
