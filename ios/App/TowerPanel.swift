import SwiftUI
import MoonPixelCore

// Towers of the known world, floor by floor. The floor list is lazy: a thousand-floor tower makes rows
// only for the floors on screen. Jump to any floor by number. Every floor says what it is for, how far
// built, who lives there, how much of their food got up to them, whether water reaches it and how near
// it is to what it can carry. Protecting a tower (so the planner never builds on it) is a command.

struct TowerList: View {
    @EnvironmentObject var model: GameModel
    let c: Civ
    let nation: Int
    var body: some View {
        let ts = c.towerIndex.towers.values.filter { $0.nation == nation }.sorted { $0.id < $1.id }
        return VStack(alignment: .leading, spacing: 3) {
            Text(L("塔楼", "Towers")).font(.system(size: 13, weight: .bold, design: .rounded))
            if ts.isEmpty { Text(L("尚无塔楼：城市在缺床位、高层缺粮或需要防御时会自行规划", "No towers yet: cities plan them when they lack beds, cannot get food upstairs or need defence")).font(.system(size: 10, design: .rounded)).opacity(0.7) }
            ForEach(ts, id: \.id) { t in
                let used = t.floors.filter { $0.stage == .inUse }.count
                Button { model.towerDetail = t.id } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "building.2.fill")
                        Text(GameModel.zh ? t.nameZh : t.nameEn).font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text(L("\(t.floors.count) 层（\(used) 层使用中）· 住户 \(t.floors.reduce(0) { $0 + $1.people.total }) · 电梯 \(t.lifts) 组", "\(t.floors.count) floors (\(used) in use) · \(t.floors.reduce(0) { $0 + $1.people.total }) inside · \(t.lifts) lift banks"))
                            .font(.system(size: 10, design: .rounded)).opacity(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 32)
                }.buttonStyle(PressStyle()).accessibilityIdentifier("tower-\(t.id)")
            }
        }
    }
}

struct TowerSheet: View {
    @EnvironmentObject var model: GameModel
    let id: Int
    @State private var jump = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let c = model.society.civ
            if let t = c.towerIndex.towers[id] {
                GlassSheet(title: GameModel.zh ? t.nameZh : t.nameEn, subtitle: header(t), close: { model.towerDetail = nil }) {
                    VStack(alignment: .leading, spacing: 8) {
                        controls(t, c)
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    TextField(L("跳到第几层", "Go to floor"), text: $jump).keyboardType(.numberPad)
                                        .textFieldStyle(.plain).font(.system(size: 12, design: .rounded)).padding(.horizontal, 10).frame(width: 120, height: 32)
                                        .background(Color.white.opacity(0.12), in: Capsule()).accessibilityIdentifier("tower-jump")
                                    Chip(title: L("跳转", "Go"), icon: "arrow.up.and.down", id: "tower-go") { if let n = Int(jump), n >= 1, n <= t.floors.count { withAnimation { proxy.scrollTo(n - 1, anchor: .center) } } }
                                    Chip(title: L("顶层", "Top"), icon: "arrow.up.to.line", id: "tower-top") { withAnimation { proxy.scrollTo(t.floors.count - 1, anchor: .top) } }
                                    Chip(title: L("底层", "Ground"), icon: "arrow.down.to.line", id: "tower-bottom") { withAnimation { proxy.scrollTo(0, anchor: .bottom) } }
                                }
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 2) {
                                        ForEach((0..<t.floors.count).reversed(), id: \.self) { i in floorRow(t, c, i).id(i) }
                                    }
                                }
                                .frame(height: 260)
                                .accessibilityIdentifier("tower-floors")
                            }
                        }
                        history(t)
                    }
                }
            }
        }
    }

    private func header(_ t: Tower) -> String {
        let m = TowerRules.materialNames[min(4, t.material)]
        return L("\(t.floors.count) 层 · \(m.1) · 电梯 \(t.lifts) 组", "\(t.floors.count) floors · \(m.0) · \(t.lifts) lift banks")
            + (t.skyLobbyEvery > 0 ? L(" · 每 \(t.skyLobbyEvery) 层设转换层", " · sky lobby every \(t.skyLobbyEvery)") : "")
            + L(" · 运力负荷 \(Int(t.liftLoad * 100))%", " · lift load \(Int(t.liftLoad * 100))%")
            + (t.protected ? L(" · 受保护", " · protected") : "")
    }

    private func controls(_ t: Tower, _ c: Civ) -> some View {
        HStack(spacing: 6) {
            Chip(title: t.protected ? L("取消保护", "Unprotect") : L("保护（规划不改动）", "Protect (planner leaves it)"), icon: t.protected ? "lock.open" : "lock.fill", id: "tower-protect") {
                model.civDo(t.nation, .protectTower(tower: t.id, on: !t.protected))
            }
            if let city = c.cities[t.city], let note = city.planNote {
                Text(L("规划备注：", "Planner: ") + note).font(.system(size: 10, design: .rounded)).opacity(0.75).lineLimit(2)
            }
        }
    }

    private func use(_ c: Civ, _ f: TowerFloor) -> (String, Color) {
        switch c.towerIndex.plans[f.plan]?.use ?? .lobby {
        case .home: return (L("住宅", "homes"), Color(red: 0.55, green: 0.75, blue: 1))
        case .farm: return (L("垂直农场", "farm"), Color(red: 0.5, green: 0.9, blue: 0.5))
        case .store: return (L("仓储", "stores"), Color(red: 0.9, green: 0.8, blue: 0.5))
        case .works: return (L("工业", "works"), Color(red: 0.95, green: 0.6, blue: 0.4))
        case .lobby: return (L("大堂", "lobby"), Color.white)
        case .defence: return (L("防御", "defence"), Color(red: 1, green: 0.45, blue: 0.45))
        case .pump: return (L("水泵", "pumps"), Color(red: 0.4, green: 0.8, blue: 0.95))
        case .dock: return (L("停泊", "dock"), Color(red: 0.75, green: 0.6, blue: 1))
        }
    }

    private func stage(_ s: TowerFloor.Stage) -> String {
        switch s {
        case .planned: return L("规划中", "planned")
        case .reserved: return L("已备料", "materials in")
        case .structure: return L("主体施工", "structure")
        case .fitout: return L("装修", "fit-out")
        case .inspection: return L("验收", "inspection")
        case .inUse: return L("使用中", "in use")
        case .damaged: return L("受损已疏散", "damaged, evacuated")
        case .failed: return L("失效", "failed")
        }
    }

    private func floorRow(_ t: Tower, _ c: Civ, _ i: Int) -> some View {
        let f = t.floors[i]
        let (u, col) = use(c, f)
        let ratio = i < t.load.count && t.strength[i].isFinite && t.strength[i] > 0 ? t.load[i] / t.strength[i] : 0
        return HStack(spacing: 6) {
            Text("\(i + 1)").font(.system(size: 10, weight: .bold, design: .monospaced)).frame(width: 40, alignment: .trailing)
            RoundedRectangle(cornerRadius: 3).fill(col.opacity(f.stage == .inUse ? 0.9 : 0.35)).frame(width: 14, height: 14)
            Text(u + " · " + stage(f.stage)).font(.system(size: 10, design: .rounded)).frame(width: 150, alignment: .leading)
            Text(L("住户 \(f.people.total)", "\(f.people.total) in")).font(.system(size: 10, design: .rounded)).frame(width: 60, alignment: .leading)
            Text(L("送粮 \(Int(f.coverage * 100))%", "fed \(Int(f.coverage * 100))%")).font(.system(size: 10, design: .rounded)).foregroundStyle(f.coverage < 0.95 && f.people.total > 0 ? Color.orange : Color.white).frame(width: 70, alignment: .leading)
            Text(f.water < 1 ? L("缺水", "dry") : L("有水", "water")).font(.system(size: 10, design: .rounded)).foregroundStyle(f.water < 1 ? Color.orange : Color.white).frame(width: 40, alignment: .leading)
            Text(L("承重 \(Int(ratio * 100))%", "load \(Int(ratio * 100))%")).font(.system(size: 10, design: .rounded)).foregroundStyle(ratio > 0.9 ? Color.red : Color.white)
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
    }

    private func history(_ t: Tower) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("建造与改建记录", "What was done and why")).font(.system(size: 12, weight: .bold, design: .rounded))
            ForEach(Array(t.history.suffix(6).enumerated()), id: \.offset) { _, h in Text(h).font(.system(size: 10, design: .rounded)).opacity(0.8) }
        }
    }
}
