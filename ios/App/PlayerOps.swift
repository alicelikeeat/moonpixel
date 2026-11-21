import Foundation
import MoonPixelCore

/// The traveller's body, backpack and elevators, as the interface uses them. Every change goes through the
/// core's commands (`Society.inventory`, the elevator's calls): nothing here edits the pack or a car itself.
extension GameModel {
    // MARK: backpack

    /// A fresh command id: one more than any carried out so far (the core does each id once).
    func nextInvID() -> Int { (society.inv.done.max() ?? 0) + 1 }

    @discardableResult func invoke(_ op: InvOp) -> InvResult {
        guard society != nil, !worldLocked else { return InvResult() }
        let r = society.inventory(nextInvID(), op, at: society.realm.player.body)
        let name = { (k: String) in GameModel.zh ? Items.def(k).zh : Items.def(k).en }
        switch op {
        case .eat(let k, _):
            showToast(r.ok ? String(format: L("吃了 %@ %.1f", "Ate %@ %.1f"), name(k), r.amount) : (r.reason == "full" ? L("现在不饿", "Not hungry now") : L("没有可吃的", "Nothing to eat")))
        case .equip(let k):
            showToast(r.ok ? String(format: L("装备了%@", "Equipped %@"), name(k)) : L("无法装备", "Cannot equip that"))
        case .unequip:
            if r.ok { showToast(L("已卸下", "Taken off")) }
        case .drop(let k, _):
            showToast(r.ok ? String(format: L("放下了 %@ %.0f（装进旁边的物资箱，点箱子可取回）", "Put down %@ %.0f (in the supply box beside you: tap it to take it back)"), name(k), r.amount) : L("这里放不下东西（悬空、墙里或电梯中）", "Nothing can be put down here (air, a wall or a moving car)"))
        case .pickUp:
            showToast(r.ok ? String(format: L("拾取 %.0f%@", "Picked up %.0f%@"), r.amount, r.reason == "pack full" ? L("（背包满，剩下的留在原地）", " (pack full: the rest stays)") : "") : L("够不着或背包已满", "Out of reach, or the pack is full"))
        case .openBox:
            let what = r.ok ? String(format: L("打开物资箱：拿到 %.0f 件%@", "Opened the supply box: took %.0f%@"), r.amount, r.reason == "pack full" ? L("（背包满，剩下的还在箱里）", " (pack full: the rest stays in the box)") : "")
                            : (r.reason == "pack full" ? L("背包满了：先扩容或放下点东西", "The pack is full: make it bigger or put something down") : L("够不着这个物资箱", "That supply box is out of reach"))
            showToast(what)
        case .deposit(_, _, _), .withdraw(_, _, _):
            showToast(r.ok ? String(format: L("搬运 %.0f%@", "Moved %.0f%@"), r.amount, r.reason == "only part" ? L("（只放得下这么多）", " (only that much fitted)") : "") : L("搬不了：", "Cannot move: ") + r.reason)
        case .bind: break
        }
        refreshHUD()
        return r
    }

    /// Make the pack the next size bigger, from its own materials.
    func upgradePack() {
        guard society != nil, !worldLocked else { return }
        if let why = society.upgradePack() {
            if why == "largest" { showToast(L("背包已经是最大了", "The pack is as big as it gets")); return }
            let k = String(why.dropFirst(5))
            showToast(String(format: L("材料不够：还需要%@", "Not enough: more %@ needed"), GameModel.zh ? Items.def(k).zh : Items.def(k).en))
        } else {
            let lv = society.realm.player.packLevel ?? 0
            showToast(String(format: L("背包升级为「%@」：负重上限 %.0f", "The pack is now a %@: it carries up to %.0f"), GameModel.zh ? PackTune.names[lv].1 : PackTune.names[lv].0, society.invCfg.capacity))
        }
        refreshHUD()
    }

    /// A hotbar place: food is eaten, a tool or weapon is taken in hand, anything else is shown.
    func useHotbar(_ i: Int) {
        guard society != nil, i < society.inv.hotbar.count else { return }
        let k = society.inv.hotbar[i]
        guard !k.isEmpty else { showBackpack = true; return }
        let d = Items.def(k)
        if d.nutrition > 0 { invoke(.eat(k, 1)) }
        else if d.equip != nil { invoke(.equip(k)) }
        else { showToast(String(format: L("%@：%.0f", "%@: %.0f"), GameModel.zh ? d.zh : d.en, society.carried(k))) }
    }

    /// Stacks lying within reach of the traveller.
    func droppedNearby() -> [Dropped] {
        guard society != nil, let b = society.realm.player.body else { return [] }
        return society.inv.dropped.filter { $0.depth == b.depth && Vec2($0.x, $0.y).distance(to: b.pos) <= society.invCfg.reach }
    }

    // MARK: elevators

    /// The elevator the body is in, or the one whose landing it stands at on this layer.
    func liftHere() -> (lift: Elevator, stop: Int?)? {
        guard society != nil, let b = society.realm.player.body else { return nil }
        for e in society.realm.lifts {
            if b.platform == e.id { return (e, e.at) }
            if let k = e.stops.firstIndex(where: { $0.depth == b.depth && $0.door.center.distance(to: b.pos) <= 40 }) { return (e, k) }
        }
        return nil
    }

    /// Board the saucer resting beside you.
    func boardUfo() {
        guard society != nil else { return }
        if society.boardUfo() { showToast(L("登上了飞碟：它会按航线起飞绕场，随时可以跳伞", "Aboard the saucer: it takes off on its round; you can jump with a parachute at any time")) }
        else { showToast(L("附近没有停在机坪上的飞碟", "No saucer resting on a pad nearby")) }
        refreshHeight()
    }

    /// Jump out with a parachute (from any height).
    func jumpFromUfo() {
        guard society != nil, society.jumpFromUfo() else { return }
        showToast(L("跳伞！用摇杆控制方向，落地不会受伤", "Jump! Steer with the stick; the landing will not hurt"))
        refreshHeight()
    }

    /// Step off the saucer while it rests on its pad.
    func leaveUfo() {
        guard society != nil else { return }
        if society.leaveUfo(), let b = society.realm.player.body { scene?.player = b.pos; showToast(L("走下了飞碟", "Off the saucer")) }
        else { showToast(L("飞碟还在空中：可以跳伞", "The saucer is in the air: jump with the parachute")) }
        refreshHeight()
    }

    /// Step into the lift at the landing (calls it first if it is elsewhere).
    func enterLift() {
        guard society != nil else { return }
        switch society.playerEnterLift() {
        case .entered:
            if let b = society.realm.player.body { scene?.player = b.pos }
            showToast(L("已进入电梯：选择要去的楼层", "In the lift: choose a floor"))
            if let e = society.playerLift { liftPanel = e.id }
        case .called: showToast(L("电梯正在来，门开了就能进", "The lift is on its way; step in when the doors open"))
        case .wait: showToast(L("正在开门…", "Opening the doors…"))
        default: showToast(L("这里不是电梯口", "Not at a lift"))
        }
        refreshHeight()
    }

    /// Step out onto the landing of the floor the car stands at.
    func exitLift() {
        guard society != nil else { return }
        guard let out = society.playerExitLift() else {
            showToast(L("电梯还在两层之间，到站开门后再出", "Between floors: step out when it stops and opens")); return
        }
        liftPanel = nil
        switchLayer(to: out.pos)                     // (the floor it stands at may be another storey than where you got in)
        showToast(L("已出电梯：", "Out of the lift: ") + (out.depth == 0 ? L("地面", "Ground") : String(format: L("第 %d 层", "Storey %d"), out.depth - OpenWorld.storeyBase)))
        refreshHeight()
    }

    /// Call the car to where the traveller stands, or (inside) send it to this landing.
    func callLift(_ id: Int, to stop: Int) {
        guard let e = society?.lift(id) else { return }
        if society.playerLift?.id == id { society.playerRideLift(to: stop) } else { e.call(stop, at: world.time) }
        showToast(String(format: L("已呼叫：%@", "Called: %@"), stopName(e.stops[stop])))
    }

    /// Build an outside elevator against the nearest building of two or more levels (paid from the pack).
    func buildLiftHere() {
        guard let sc = scene, society != nil, !worldLocked else { return }
        guard let site = society.liftSite(near: sc.player) else {
            showToast(L("附近没有两层以上的建筑", "No building of two or more levels nearby")); return
        }
        guard site.plan.ok else { showToast(L("这里装不了电梯：", "No elevator here: ") + site.plan.reason); return }
        let cost = site.plan.cost.sorted { $0.key < $1.key }.map { String(format: "%@ %.0f", Recipe.goodName($0.key, zh: GameModel.zh), $0.value) }.joined(separator: " · ")
        let planID = (society.realm.player.plans?.max() ?? 0) + 1
        guard let id = society.buildLift(site.plan, x: site.x, y: site.y, town: site.town, tower: site.tower, planID: planID) else {
            showToast(L("材料不够：", "Not enough: ") + cost); return
        }
        showToast(String(format: L("外置电梯建好了：%d 个停靠层（%@）", "Outside elevator built: %d landings (%@)"), society.lift(id)?.stops.count ?? 0, cost))
        refreshHUD()
    }

    func stopName(_ s: LiftStop) -> String { s.level == 0 ? L("地面", "Ground") : String(format: L("第 %d 层", "Storey %d"), s.level) }

    /// "Storey 3 · 6.0 m" (and the car's way when riding), for the HUD and 2D.
    func refreshHeight() {
        guard society != nil, let b = society.realm.player.body else { heightLine = ""; nearLift = nil; return }
        var s = b.depth >= OpenWorld.storeyBase ? String(format: L("第 %d 层", "Storey %d"), b.depth - OpenWorld.storeyBase) : (b.depth == 1 ? L("地下", "Underground") : (MP.isBelow(b.depth) ? String(format: L("地下第 %d 层", "Level B%d"), b.depth) : L("地面", "Ground")))
        s += String(format: " · %.1f m", b.z * 2)
        if let id = b.platform, let e = society.lift(id) {
            let above = e.stops.lastIndex { $0.z <= e.z + 1e-6 }.map { e.stops[$0] }
            s = L("电梯中 · ", "In the car · ") + (above.map { stopName($0) } ?? "") + String(format: " · %.1f m", e.z * 2)
            if let t = e.target { s += " → " + stopName(e.stops[t]) }
        } else if b.airborne { s += L(" · 空中", " · in the air") }
        heightLine = s
        nearLift = liftHere()?.lift.id
        inLift = society.playerLift != nil
        atLiftDoor = society.playerLanding() != nil
        let u = society.ridingUfo
        onUfo = u != nil; ufoLanded = u?.landed ?? false
        nearUfo = u == nil && b.depth == 0 && society.landedUfo(near: b.pos) != nil
        chuting = b.chute == true
        if let u = u { heightLine = String(format: L("乘坐飞碟 · 离地 %.0f m", "Aboard the saucer · %.0f m up"), u.z * 2) + (u.landed ? L(" · 停在机坪", " · on the pad") : "") }
        else if chuting { heightLine = String(format: L("跳伞中 · 高 %.0f m", "Parachuting · %.0f m"), b.z * 2) }
    }
}
