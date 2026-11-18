import Foundation
import MoonPixelCore

/// What the driving (or passenger) display shows, read from the vehicle each frame: nothing here moves it.
struct DriveState: Equatable {
    var id = 0
    var kind = VehicleKind.car
    var name = ""
    var driving = false
    var auto = false
    var kmh = 0.0                 // a tile is 2 m: tiles/s x 7.2
    var limitKmh = 0.0
    var fuel = 0.0                // 0...1 of the tank (electric: grid)
    var energy = ""
    var gear = "D"
    var throttle = 0.0, brake = 0.0, steer = 0.0, pitch = 0.0
    var altitude = 0.0, climb = 0.0, headingDeg = 0.0
    var phase = ""
    var assist = true
    var signal = ""
    var next = ""
    var halted = ""
    var riders = 0, seats = 0, cargo = 0.0
    var canLeave = false
    var berthed = false
    var flight = Flight.ground
}

struct VehicleRow: Identifiable, Equatable { var id: Int; var text: String; var canDrive: Bool; var canRide: Bool }
struct StopRow: Identifiable, Equatable { var id: Int; var text: String }

extension GameModel {
    // MARK: in a vehicle

    /// Read the vehicle the traveller is in into the display (or clear it).
    func refreshDrive() {
        guard let s = society, let v = s.playerVehicle else {
            if drive != nil { drive = nil; driveInput = Controls() }
            var near = false
            if let s = society, let b = s.realm.player.body {
                let p = b.pos
                near = !s.vehiclesNear(p).isEmpty || s.net.stops.contains { st in st.tile.center.distance(to: p) < 6 * 16 }
            }
            if nearTransport != near { nearTransport = near }
            return
        }
        var d = DriveState()
        d.id = v.id; d.kind = v.kind; d.name = v.name
        d.driving = v.playerDriving; d.auto = v.control == .auto
        d.kmh = abs(v.speed) * 7.2
        topKmh = max(topKmh, d.kmh)
        let k = v.level == 1 ? s.bridge(at: v.tile)?.deck : s.wayKind(at: v.tile)
        d.limitKmh = min(v.spec.maxSpeed, k?.limit ?? v.spec.maxSpeed) * 7.2
        switch v.spec.energy {
        case .electric:
            let ok = s.gridPower(for: v)
            d.fuel = ok ? 1 : 0; d.energy = ok ? L("电网供电", "Grid power") : L("无电", "No power")
        default:
            d.fuel = v.spec.tank > 0 ? v.fuel / v.spec.tank : 0
            d.energy = String(format: L("燃料 %.0f / %.0f", "Fuel %.0f / %.0f"), v.fuel, v.spec.tank)
        }
        d.gear = v.input.reverse ? "R" : (abs(v.speed) < 0.05 && v.input.throttle == 0 ? "N" : "D")
        d.throttle = v.input.throttle; d.brake = v.input.brake; d.steer = v.input.steer; d.pitch = v.input.pitch
        d.altitude = v.z * 2; d.climb = v.vz * 2
        d.headingDeg = (v.heading * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if d.headingDeg < 0 { d.headingDeg += 360 }
        d.phase = v.task.phase ?? ""
        d.assist = v.input.assist
        d.flight = v.flight
        if v.kind.mode == .rail { d.signal = v.halted == "red signal" ? L("红灯", "Red") : L("绿灯", "Green") }
        if let lid = v.task.line, let l = s.net.line(lid), v.task.at < l.stops.count, let st = s.net.stop(l.stops[v.task.at]) {
            d.next = (v.task.standing ? L("停靠 ", "At ") : L("下一站 ", "Next ")) + st.name
        }
        d.halted = v.halted.map { haltText($0) } ?? ""
        d.riders = v.riders.count; d.seats = v.spec.seats; d.cargo = v.load
        d.canLeave = v.stopped && v.flight != .air
        d.berthed = v.berthed
        if drive != d { drive = d }
    }

    func haltText(_ h: String) -> String {
        switch h {
        case "no way": return L("无路可走，等待道路", "No way: waiting for a road")
        case "bridge gone": return L("桥已不在", "The bridge is gone")
        case "no fuel": return L("没有燃料", "Out of fuel")
        case "no power": return L("断电，无牵引", "No power: no traction")
        case "red signal": return L("红灯：列车保护制动", "Red signal: train protection braking")
        case "broken down": return L("故障，需要构件维修", "Broken down: needs parts")
        case "border closed": return L("边境关闭", "Border closed")
        default: return h.hasPrefix("line suspended") ? L("线路停运：战争", "Line suspended: war") : h
        }
    }

    func board(_ id: Int, drive: Bool) {
        guard let s = society else { return }
        if let why = s.board(id, drive: drive) { showToast(L("上不了车：", "Cannot board: ") + boardText(why)); return }
        driveInput = Controls()
        topKmh = 0
        if drive { driveInput.brake = 1 }
        showTravel = false
        refreshDrive()
        showToast(drive ? L("你在驾驶座上", "You are at the controls") : L("你上了车", "You are aboard"))
    }

    func boardText(_ w: String) -> String {
        switch w {
        case "it is moving": return L("它在行驶", "it is moving")
        case "too far": return L("太远", "too far")
        case "full": return L("满员", "full")
        case "not yours to drive": return L("不属于你的国家", "it belongs to another nation")
        case "not at a berth": return L("船未靠泊", "the ship is not at a berth")
        default: return w
        }
    }

    func leaveVehicle() {
        guard let s = society else { return }
        if let why = s.leaveVehicle() { showToast(L("现在下不了车：", "Cannot get out now: ") + (why == "it is moving" ? L("还在行驶", "still moving") : why)); return }
        driveInput = Controls()
        if let b = s.realm.player.body { scene?.player = b.pos }
        refreshDrive()
    }

    /// Take the controls, or hand them to the autopilot: nothing else about the vehicle changes.
    func toggleAutopilot() {
        guard let s = society, let v = s.playerVehicle, v.playerDriving else { return }
        if v.control == .manual {
            if v.task.line == nil && v.task.goal == nil, let to = tripTo, let st = s.net.stop(to) { v.task.goal = st.node }
            s.handOver(v, to: .auto)
            showToast(v.task.goal != nil || v.task.line != nil ? L("自动驾驶接管", "Autopilot has it") : L("自动驾驶：没有目的地，原地停车", "Autopilot: no destination, holding"))
        } else {
            s.handOver(v, to: .manual)
            driveInput = v.input
            showToast(L("你接管了驾驶", "You have control"))
        }
        refreshDrive()
    }

    // MARK: travelling

    func refreshTravel() {
        guard let s = society, let b = s.realm.player.body else { return }
        vehiclesHere = s.vehiclesNear(b.pos, reach: 4).prefix(8).map { v in
            let mine = v.nation == 0 || v.nation == s.realm.player.nation || s.realm.player.god == true
            return VehicleRow(id: v.id, text: v.kind.name(zh: GameModel.zh) + " · " + v.name + String(format: L(" · %.0f 米", " · %.0f m"), v.pos.distance(to: b.pos) / 8)
                              + (v.stopped ? "" : L(" · 行驶中", " · moving")), canDrive: mine && v.stopped && !v.playerDriving, canRide: v.stopped && v.seatsFree > 0)
        }
        destinations = s.net.stops.sorted { $0.tile.distance2(b.pos.tile) < $1.tile.distance2(b.pos.tile) }.prefix(40).map {
            StopRow(id: $0.id, text: $0.kind.name(zh: GameModel.zh) + " · " + $0.name + String(format: L(" · %.0f 米", " · %.0f m"), $0.tile.center.distance(to: b.pos) / 8))
        }
    }

    /// Plan a trip from here to a stop: walking, lines, changes and the time it takes.
    func planTrip(to stop: Int) {
        guard let s = society, let b = s.realm.player.body, let st = s.net.stop(stop) else { return }
        tripTo = stop
        trip = s.planTrip(from: b.pos.tile, to: st.tile, nation: s.realm.player.nation)
    }

    func tripText(_ p: TripPlan) -> [String] {
        guard let s = society else { return [] }
        guard p.ok else { return [L("没有线路可到：", "No line goes there: ") + p.reason] }
        var out: [String] = []
        for lg in p.legs {
            let mins = Int((lg.seconds / Society.hour * 60).rounded())
            if let lid = lg.line, let l = s.net.line(lid) {
                out.append(String(format: L("乘 %@（%@）从 %@ 到 %@ · 约 %d 分钟", "%@ (%@) from %@ to %@ · about %d min"), l.name, l.kind.name(zh: GameModel.zh),
                                  s.net.stop(lg.from ?? 0)?.name ?? "?", s.net.stop(lg.to ?? 0)?.name ?? "?", mins))
            } else {
                out.append(String(format: L("步行%@ · 约 %d 分钟", "Walk%@ · about %d min"), lg.to.flatMap { s.net.stop($0)?.name }.map { L("到 ", " to ") + $0 } ?? L("到目的地", " to the end"), mins))
            }
        }
        out.append(String(format: L("共约 %d 分钟，换乘 %d 次", "About %d min in all, %d change(s)"), Int((p.seconds / Society.hour * 60).rounded()), p.transfers))
        return out
    }

    /// Wait at the first stop of the planned trip (the traveller must be at it): the vehicle stops and they walk in.
    func waitForTrip() {
        guard let s = society, let p = trip, p.ok, let first = p.legs.first(where: { $0.line != nil }), let from = first.from, let to = first.to,
              let st = s.net.stop(from), let b = s.realm.player.body else { return }
        guard st.tile.center.distance(to: b.pos) <= 6 * 16 else {
            showToast(String(format: L("先步行到 %@", "Walk to %@ first"), st.name)); return
        }
        if s.waitAt(from, for: to, who: .player) { showToast(String(format: L("在 %@ 等车，车停稳后上车", "Waiting at %@: board when it stops"), st.name)) }
        else { showToast(L("这条线去不了（停运或边境关闭）", "That line cannot take you (suspended or border closed)")) }
    }

    // MARK: the network

    func refreshTransport() {
        guard let s = society else { return }
        let n = s.net
        var out: [String] = []
        for d in n.districts.sorted(by: { $0.id < $1.id }) {
            let sv = d.services
            func pct(_ k: String) -> String { String(format: "%.0f%%", (sv[k]?.ratio ?? 0) * 100) }
            out.append(String(format: L("都市 %@：%d 人 · 住房 %d · 岗位 %d · 资金 %.0f · 粮 %.0f · 电 %@ 水 %@ 污 %@ 垃圾 %@ 医 %@ 学 %@", "District %@: %d people · %d homes · %d jobs · money %.0f · food %.0f · power %@ water %@ sewage %@ refuse %@ health %@ school %@"),
                              d.name, d.population, d.homes, d.jobs, d.money, d.store["food"] ?? 0, pct("power"), pct("water"), pct("sewage"), pct("garbage"), pct("health"), pct("education")))
        }
        for l in n.lines.sorted(by: { $0.id < $1.id }) {
            let vs = l.vehicles.compactMap { n.vehicle($0) }
            let load = vs.reduce(0) { $0 + $1.riders.count }, seats = vs.reduce(0) { $0 + $1.spec.seats }
            out.append(String(format: L("线路 %@（%@）· %d 辆 · 班次 %.0f 秒 · %@ · 平均晚点 %.0f 秒 · 运送 %d 人 %.0f 货%@", "Line %@ (%@) · %d vehicles · every %.0f s · %@ · mean delay %.0f s · %d riders %.0f goods%@"),
                              l.name, l.kind.name(zh: GameModel.zh), vs.count, l.headway, l.freight ? L("货运", "freight") : String(format: L("载客 %d/%d", "aboard %d/%d"), load, seats),
                              l.meanDelay, l.riders, l.carried, l.suspended.map { L(" · 停运：", " · suspended: ") + $0 } ?? ""))
        }
        for v in n.vehicles.sorted(by: { $0.id < $1.id }).prefix(40) {
            out.append(String(format: "%@ · %.0f km/h · %@%@", v.name, abs(v.speed) * 7.2, v.spec.energy == .electric ? L("电力", "electric") : String(format: L("燃料 %.0f", "fuel %.0f"), v.fuel),
                              v.halted.map { " · " + haltText($0) } ?? ""))
        }
        let bn = s.bottlenecks()
        out.append(bn.isEmpty ? L("没有发现瓶颈", "No bottlenecks found") : L("瓶颈：", "Bottlenecks: ") + bn.prefix(8).joined(separator: "; "))
        let st = n.stats
        out.append(String(format: L("累计：行程 %d · 拒载 %d · 货物送达 %.0f · 事故 %d · 搁浅 %d · 燃料 %.0f · 电 %.0f · 票款 %.0f", "So far: trips %d · refused %d · goods delivered %.0f · crashes %d · groundings %d · fuel %.0f · power %.0f · fares %.0f"),
                          st.trips, st.tripsRefused, st.delivered, st.crashes, st.groundings, st.fuelBurnt, st.powerUsed, st.fares))
        transportLines = out
    }

    /// Building a way: the start here, then the end where the traveller stands, then a preview to confirm.
    func markWay() {
        guard let s = society, let b = s.realm.player.body else { return }
        let here = b.pos.tile
        if let a = wayStart {
            wayPreview = s.planWay(wayKindPick, from: a, to: here)
        } else {
            wayStart = here; wayPreview = nil
            showToast(L("起点已标记：走到终点后再点一次", "Start marked: walk to the end and tap again"))
        }
    }

    func previewText(_ p: WayPlan) -> [String] {
        guard p.ok else { return [L("修不了：", "Cannot build: ") + (p.reason == "no way" ? L("没有可修的路线（建筑或障碍）", "no line can be built (buildings or obstacles)") : p.reason)] }
        var out = [String(format: L("%@ %d 格 · 砍伐 %d 处（得木材 %.0f、石料 %.0f）", "%@ %d tiles · %d felled (wood %.0f, stone %.0f)"), p.kind.name(zh: GameModel.zh), p.cells.count, p.fell.count, p.wood, p.stone)]
        if !p.spans.isEmpty { out.append(String(format: L("桥 %d 座（共 %d 格）", "%d bridge(s), %d tiles"), p.spans.count, p.spans.reduce(0) { $0 + $1.count })) }
        if !p.tunnels.isEmpty { out.append(String(format: L("隧道 %d 条", "%d tunnel(s)"), p.tunnels.count)) }
        out.append(L("费用：", "Cost: ") + p.cost.sorted { $0.key < $1.key }.map { String(format: "%@ %.0f", Recipe.goodName($0.key, zh: GameModel.zh), $0.value) }.joined(separator: " · "))
        return out
    }

    func confirmWay() {
        guard let s = society, let p = wayPreview, p.ok else { return }
        guard let id = s.startWay(p, payer: .pack, nation: s.realm.player.nation) else { showToast(L("背包里的材料不够", "Not enough materials in the pack")); return }
        showToast(String(format: L("开工：%d 格，施工中（工地 %d）", "Work started: %d tiles (site %d)"), p.cells.count, id))
        wayStart = nil; wayPreview = nil
        refreshHUD()
    }

    /// A car from the pack's materials, on the road where the traveller stands.
    func refuelHere() {
        guard let s = society else { return }
        let (n, from) = s.refuelHere()
        if n <= 0 { showToast(L("没有燃油：用快捷栏旁的“一键物资”，或开到城区附近再加油", "No fuel: use Materials in one go, or drive near a district")); return }
        showToast(String(format: L("加了 %.0f 燃油（%@）", "Filled %.0f fuel (%@)"), n, from == "own" ? L("背包", "pack") : from))
        refreshDrive()
    }

    func buildCarHere() {
        guard let s = society, let b = s.realm.player.body else { return }
        if let v = s.buildVehicle(.car, at: b.pos.tile, payer: .pack, nation: s.realm.player.nation) {
            showToast(v.fuel > 0 ? String(format: L("造了一辆车（燃料 %.0f）", "Built a car (fuel %.0f)"), v.fuel)
                                 : L("造了一辆车，但背包里没有燃油：上车后点“加油”", "Built a car, but there is no fuel in the pack: get in and tap Refuel"))
            refreshTravel()
        } else { showToast(L("这里造不了车：需要在路上，并要铁 4、构件 3", "No car here: it needs a road and 4 iron, 3 parts")) }
    }

    /// Bring this world's metro-mode city into the open world (once): its streets, buildings, people, money and
    /// services become a district on the same land. A copy of the save is kept first.
    func importMetroCity() {
        guard let s = society, metro == nil else { return }
        let got = SaveFile(url: metroFile).load { try JSONDecoder().decode(Metro.self, from: $0) }
        guard let m = got.value else { showToast(L("这个世界还没有都市", "This world has no metro city yet")); return }
        if s.realm.transport.importedMetros.contains(m.seed) { showToast(L("都市已在开放世界中", "The city is already in the open world")); return }
        store?.pinBackup("before-metro-import")
        let nation = s.realm.metroLink?.nation ?? s.realm.player.nation
        guard let d = s.importMetro(m, nation: nation) else { return }
        showToast(String(format: L("%@ 已并入开放世界：%d 人，%d 座建筑，资金 %.0f", "%@ is in the open world: %d people, %d buildings, money %.0f"), d.name, d.population, d.buildings.count, d.money))
        save(announce: false)
    }

    // MARK: building up, materials, the time of day, the art style

    /// One block under the feet: up a storey, standing on the new floor (stone first, then planks, wood, parts).
    func pillarUp() {
        guard let s = society, !worldLocked else { return }
        guard let good = ["stone", "planks", "wood", "parts", "iron"].first(where: { s.carried($0) >= 1 }) else {
            showToast(L("背包里没有可以搭的方块（石料、木板、木材、构件）", "Nothing in the pack to build with (stone, planks, wood, parts)")); return
        }
        if let why = s.pillarUp(with: good) {
            let text: [String: String] = ["ceiling": L("头顶已有楼板或墙", "There is a floor or a wall above"), "underground": L("地下不能往上搭", "Not underground"),
                                          "not standing": L("在车里或电梯里不能搭", "Not in a vehicle or a lift"), "something here": L("脚下有东西", "Something is in the way")]
            showToast(text[why] ?? why); return
        }
        if let b = s.realm.player.body { switchLayer(to: b.pos) }
        showToast(String(format: L("搭了一块%@，现在在第 %d 层", "Placed %@: now on storey %d"), Recipe.goodName(good, zh: GameModel.zh), (s.realm.player.body?.depth ?? 100) - OpenWorld.storeyBase))
        refreshHUD()
    }

    /// Fill the pack with building materials (as much as it carries). Marks the save like the other cheats.
    func supplyPack() {
        guard let s = society, !worldLocked else { return }
        let got = s.supplyPack()
        if got.isEmpty { showToast(L("背包已满", "The pack is full")); return }
        showToast(L("物资已装入背包（此存档已标记为使用过作弊）：", "Materials packed (this save is marked as cheated): ")
                  + got.sorted { $0.key < $1.key }.map { String(format: "%@ %.0f", Recipe.goodName($0.key, zh: GameModel.zh), $0.value) }.joined(separator: " · "))
        refreshHUD()
    }

    /// Forward to the next time it is this hour.
    func setTime(_ hour: Double) {
        guard let s = society, !worldLocked else { return }
        s.advanceTo(hour: hour)
        refreshHUD()
        showToast(L("时间：", "Time: ") + s.world.clockText)
    }
}

