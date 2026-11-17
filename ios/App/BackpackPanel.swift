import SwiftUI
import MoonPixelCore

/// Jump, act, the hotbar, the cross in first person and where you are in height. These are SwiftUI
/// buttons: a touch that starts on one never reaches the 3D view, so it never turns the camera.
struct PlayControls: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        ZStack {
            if model.render3D && model.viewMode == .first && model.watch == .none {
                Image(systemName: "plus").font(.system(size: 18, weight: .light)).foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black, radius: 1).allowsHitTesting(false).accessibilityHidden(true)
            }
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(spacing: 10) {
                        if model.nearLift != nil {
                            round("arrow.up.arrow.down", L("电梯", "Elevator"), id: "lift-open") { model.liftPanel = model.nearLift }
                        }
                        if model.render3D && model.viewMode == .first {
                            round("hand.point.up.left.fill", L("动作", "Act"), id: "act") {
                                if let p = model.solid?.pickCentre() { model.scene?.tapWorld(p, agent: nil) } else { model.showToast(L("准星处够不着", "Nothing within reach at the cross")) }
                            }
                        }
                        round("arrow.up.circle.fill", L("跳跃", "Jump"), id: "jump", big: true) { model.jumpQueued = true }
                    }
                    .padding(.trailing, 14).padding(.bottom, 86)
                }
            }
            VStack(spacing: 6) {
                Spacer()
                if !model.heightLine.isEmpty {
                    Text(model.heightLine).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 4).glass(Capsule()).allowsHitTesting(false)
                        .accessibilityIdentifier("height-line")
                }
                hotbar.padding(.bottom, 64)
            }
            // the camera, for assistive technology and UI tests
            Text(model.cameraLine).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)
                .accessibilityIdentifier("camera-state").allowsHitTesting(false)
            Text("save running \(model.saveRunning) exit \(model.exitRequested) blocked \(model.exitBlocked != nil)").font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)
                .accessibilityIdentifier("save-state").allowsHitTesting(false)
        }
    }

    private var hotbar: some View {
        HStack(spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let key = model.society?.inv.hotbar[i] ?? ""
                Button { model.useHotbar(i) } label: {
                    VStack(spacing: 1) {
                        Text(key.isEmpty ? "·" : String((GameModel.zh ? Items.def(key).zh : Items.def(key).en).prefix(2)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text(key.isEmpty ? "" : String(format: "%.0f", model.society?.carried(key) ?? 0) + (model.society?.inv.equipped.values.contains(key) == true ? "•" : ""))
                            .font(.system(size: 8, design: .rounded)).monospacedDigit().opacity(0.8)
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(PressStyle()).glass(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("hotbar-\(i)")
                .accessibilityLabel(key.isEmpty ? L("空快捷栏", "Empty slot") : (GameModel.zh ? Items.def(key).zh : Items.def(key).en))
            }
            Button { model.showBackpack = true } label: { Image(systemName: "backpack.fill").frame(width: 34, height: 34) }
                .buttonStyle(PressStyle()).glass(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("backpack").accessibilityLabel(L("背包", "Backpack"))
        }
    }

    private func round(_ icon: String, _ label: String, id: String, big: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: big ? 26 : 20, weight: .semibold)).frame(width: big ? 64 : 50, height: big ? 64 : 50)
        }
        .buttonStyle(PressStyle()).glass(Circle())
        .accessibilityIdentifier(id).accessibilityLabel(label)
    }
}

/// Everything carried, from the one pack: kinds, search, use, equip, drop, hotbar, things lying near.
struct BackpackPanel: View {
    @EnvironmentObject var model: GameModel
    @State private var kind: ItemKind?
    @State private var search = ""
    @State private var picked: String?

    var body: some View {
        GlassSheet(title: L("背包", "Backpack"), subtitle: subtitle, close: { model.showBackpack = false }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField(L("搜索", "Search"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 160).accessibilityIdentifier("pack-search")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            filter(nil, L("全部", "All"))
                            ForEach(ItemKind.allCases, id: \.self) { k in filter(k, kindName(k)) }
                        }
                    }
                }
                equipment
                let stacks = model.society?.packStacks(zh: GameModel.zh, filter: kind, search: search) ?? []
                if stacks.isEmpty { Text(L("这里什么都没有", "Nothing here")).font(.system(size: 12, design: .rounded)).opacity(0.7) }
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(stacks.enumerated()), id: \.offset) { _, st in
                        Button { picked = picked == st.key ? nil : st.key } label: {
                            HStack {
                                Text(st.name).font(.system(size: 13, weight: .medium, design: .rounded))
                                Spacer()
                                Text(String(format: "%.1f", st.amount)).font(.system(size: 12, design: .rounded)).monospacedDigit()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(picked == st.key ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PressStyle()).accessibilityIdentifier("pack-\(st.key)")
                        if picked == st.key { actions(st.key) }
                    }
                }
                let near = model.droppedNearby()
                if !near.isEmpty {
                    Text(L("地上的东西", "Lying here")).font(.system(size: 12, weight: .semibold, design: .rounded))
                    ForEach(near, id: \.id) { d in
                        Chip(title: (GameModel.zh ? Items.def(d.key).zh : Items.def(d.key).en) + String(format: " %.0f", d.amount), icon: "arrow.down.to.line", id: "pick-\(d.id)") { model.invoke(.pickUp(d.id)) }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        guard let s = model.society else { return "" }
        return String(format: L("负重 %.0f / %.0f · 饥饿 %.0f%%", "Load %.0f / %.0f · hunger %.0f%%"), s.packWeight(), s.invCfg.capacity, s.inv.hunger * 100)
    }

    private var equipment: some View {
        HStack(spacing: 6) {
            ForEach(["hand", "body"], id: \.self) { slot in
                let k = model.society?.inv.equipped[slot]
                Chip(title: (slot == "hand" ? L("手：", "Hand: ") : L("身：", "Body: ")) + (k.map { GameModel.zh ? Items.def($0).zh : Items.def($0).en } ?? L("空", "empty")),
                     icon: slot == "hand" ? "hand.raised.fill" : "shield.fill", id: "slot-\(slot)") { if k != nil { model.invoke(.unequip(slot)) } }
            }
        }
    }

    private func actions(_ key: String) -> some View {
        let d = Items.def(key)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if d.nutrition > 0 { Chip(title: L("吃一份", "Eat one"), icon: "fork.knife", id: "eat-\(key)") { model.invoke(.eat(key, 1)) } }
                if d.equip != nil { Chip(title: L("装备", "Equip"), icon: "hand.raised.fill", id: "equip-\(key)") { model.invoke(.equip(key)) } }
                Chip(title: L("放下 1", "Drop 1"), icon: "arrow.down.to.line", id: "drop1-\(key)") { model.invoke(.drop(key, 1)) }
                Chip(title: L("放下一半", "Drop half"), icon: "square.split.2x1", id: "drophalf-\(key)") { model.invoke(.drop(key, max(1, ((model.society?.carried(key) ?? 0) / 2).rounded(.down)))) }
                Menu {
                    ForEach(0..<8, id: \.self) { i in Button(String(format: L("放到第 %d 格", "To slot %d"), i + 1)) { model.invoke(.bind(i, key)) } }
                } label: { Label(L("快捷栏", "Hotbar"), systemImage: "rectangle.grid.1x2.fill").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                    .accessibilityIdentifier("bind-\(key)")
            }
            .padding(.leading, 10)
        }
    }

    private func filter(_ k: ItemKind?, _ title: String) -> some View {
        Button { kind = k } label: {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(kind == k ? 0.22 : 0.07), in: Capsule())
        }.buttonStyle(PressStyle())
    }

    private func kindName(_ k: ItemKind) -> String {
        switch k {
        case .food: return L("食物", "Food")
        case .material: return L("材料", "Materials")
        case .tool: return L("工具", "Tools")
        case .weapon: return L("武器", "Weapons")
        case .armour: return L("防具", "Armour")
        case .part: return L("构件", "Parts")
        case .machine: return L("器械", "Machines")
        }
    }
}

/// An elevator's panel: its landings (only those it really stops at), a search by number, where the car
/// is, its state and load. Inside, a landing sends the car there; at a landing, it calls the car.
struct LiftPanel: View {
    @EnvironmentObject var model: GameModel
    let id: Int
    @State private var number = ""

    var body: some View {
        GlassSheet(title: L("外置电梯", "Outside elevator"), subtitle: status, close: { model.liftPanel = nil }) {
            VStack(alignment: .leading, spacing: 8) {
                if let e = model.society?.lift(id) {
                    TextField(L("输入层号", "Storey number"), text: $number).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
                        .accessibilityIdentifier("lift-number")
                    let inside = model.society?.realm.player.body?.platform == id
                    let here = model.liftHere()?.stop
                    let shown = e.stops.indices.filter { number.isEmpty || "\(e.stops[$0].level)".hasPrefix(number) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86))], spacing: 6) {
                        ForEach(shown.reversed(), id: \.self) { k in
                            Chip(title: model.stopName(e.stops[k]) + (e.at == k ? " ●" : ""), icon: inside ? "arrow.right.circle.fill" : "bell.fill", id: "lift-stop-\(e.stops[k].level)") {
                                // inside: go there; outside: call the car to where you stand
                                model.callLift(id, to: inside ? k : (here ?? k))
                            }
                        }
                    }
                    if !inside { Text(L("在电梯口：按任一层呼叫电梯到这里；进入轿厢后再选目的层。", "At a landing: any button calls the car here; choose where to go once inside.")).font(.system(size: 10, design: .rounded)).opacity(0.7) }
                } else {
                    Text(L("电梯已不在", "The elevator is gone")).font(.system(size: 12, design: .rounded))
                }
            }
        }
    }

    private var status: String {
        guard let e = model.society?.lift(id) else { return "" }
        let st: String
        switch e.state {
        case .idle: st = L("空闲", "Idle")
        case .closing: st = L("关门", "Closing")
        case .moving: st = L("运行中", "Moving")
        case .opening: st = L("开门", "Opening")
        case .open: st = L("门已开", "Doors open")
        case .overload: st = L("超载：请减少乘客或货物", "Overloaded: fewer people or goods")
        case .noPower: st = L("停电：已在楼层停靠", "No power: stopped at a landing")
        case .trapped: st = L("停电：困在两层之间，可走楼梯救援", "No power: held between landings")
        }
        return String(format: L("%@ · 高 %.1f m · 载重 %.0f / %.0f", "%@ · %.1f m up · load %.0f / %.0f"), st, e.z * 2, e.load, model.society?.liftCfg.capacity ?? 0)
    }
}
