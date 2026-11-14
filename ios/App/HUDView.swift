import SwiftUI
import PhotosUI
import MoonPixelCore

/// The in-game interface, built from system Liquid Glass.
struct HUDView: View {
    @EnvironmentObject var model: GameModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var pending: PhotoPick = .none      // what the open picker is for
    @State private var toastVisible = false

    var body: some View {
        ZStack {
            if model.showMap { mapOverlay }
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation(.snappy) { model.showDetails.toggle(); model.refreshHUD() } } label: {
                            Text(model.status).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).fixedSize()
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(PressStyle()).glass(Capsule())
                        Text(model.playerLine).font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 5).glass(Capsule()).allowsHitTesting(false)
                        if model.showDetails { details }
                    }
                    Spacer(minLength: 0)
                    if toastVisible {
                        Text(model.toast).font(.system(size: 13, weight: .medium, design: .rounded)).lineLimit(2)
                            .padding(.horizontal, 14).padding(.vertical, 9).glass(Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 8) {
                        speedBar
                        noticeStack
                        if let info = model.selected { agentCard(info) }
                    }
                }
                if model.lawSavePending { savePendingBar }
                Spacer(minLength: 0)
                if model.watch != .none { watchBar }
                if model.pendingPlan != nil || !model.buildMode.isEmpty { buildBar }
                tabBar
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .foregroundStyle(.white)
        .overlay { if model.showRealm { RealmPanel() } }
        .overlay { if model.showLaws { LawsPanel() } }
        .overlay { if model.showArsenal { ArsenalPanel() } }
        .overlay { if model.showBuild { BuildPanel() } }
        .overlay { if model.showCraft { CraftPanel() } }
        .overlay { if model.showCities { CitiesPanel() } }
        .overlay { if model.showChronicle { ChroniclePanel() } }
        .overlay { if model.showWar { WarPanel() } }
        .overlay { if model.showCheats { CheatPanel() } }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .any(of: [.images, .videos]))
        .onChange(of: model.pick) { _, v in
            guard v != .none else { return }
            pending = v            // remember the purpose until a photo actually arrives
            model.pick = .none
            pickerItem = nil
            showPicker = true
        }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            let purpose = pending
            Task {
                // photos, GIFs and videos all arrive here
                let media = await MediaLoader.load(item)
                await MainActor.run {
                    switch media {
                    case .failed: model.showToast(L("无法读取所选内容", "Could not read the selection"))
                    case .still(let img):
                        switch purpose {
                        case .asset: model.importAsset(img)
                        case .villager(let id): model.applyPhoto(img, target: id)
                        default: model.applyPhoto(img, target: 0)
                        }
                    case .motion(let frames):
                        switch purpose {
                        case .asset: if let img = frames[0].uiImage { model.importAsset(img) }
                        case .villager(let id): model.applyMotion(frames, target: id)
                        default: model.applyMotion(frames, target: 0)
                        }
                    }
                    pending = .none
                    pickerItem = nil
                }
            }
        }
        .onChange(of: model.toastID) { _, _ in
            withAnimation(.snappy) { toastVisible = true }
            let id = model.toastID
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { if model.toastID == id { withAnimation(.easeOut) { toastVisible = false } } }
        }
    }

    /// Clickable news of war: tap one to look at where it happened.
    private var noticeStack: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(model.notices) { n in
                Button { model.look(at: n.pos); model.notices.removeAll { $0.id == n.id } } label: {
                    Label(n.text, systemImage: "scope").font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 330, alignment: .trailing)
                        .background(Color.red.opacity(0.28), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("notice")
            }
        }
    }

    private var savePendingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(L("世界法则已执行，但保存失败；在保存成功前世界暂停，不能修改", "A world law ran but could not be saved; the world is paused until it is"))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(2)
            Button { model.retryLawSave() } label: {
                Label(L("重试保存", "Retry save"), systemImage: "arrow.clockwise").font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).frame(height: 34).background(Color.white.opacity(0.22), in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("retry-save")
        }
        .padding(.horizontal, 14).padding(.vertical, 8).glass(Capsule())
    }

    /// While watching, it is always clear that the camera is not the character.
    private var watchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
            Text(model.watchLabel).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
            Button { model.scene?.zoomBy(-0.25) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 32, height: 32) }.buttonStyle(PressStyle())
            Button { model.scene?.zoomBy(0.25) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 32, height: 32) }.buttonStyle(PressStyle())
            Button { model.stopWatching() } label: {
                Label(L("回到角色", "Back to me"), systemImage: "person.fill").font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).frame(height: 32).background(Color.white.opacity(0.22), in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("stop-watching")
        }
        .padding(.horizontal, 14).padding(.vertical, 6).glass(Capsule())
    }

    private var buildBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.buildMode == "demolish" ? "hammer.fill" : "square.grid.3x3.fill")
            Text(model.pendingPlan != nil ? model.previewText : (model.buildMode == "demolish" ? L("拆除：点击建筑格", "Demolish: tap a built tile") : L("点按或拖动选择位置", "Tap or drag to choose where")))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
            if model.pendingPlan != nil {
                Button { model.confirmBuild() } label: {
                    Label(L("确认", "Confirm"), systemImage: "checkmark").font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).frame(height: 32).background(Color.green.opacity(0.45), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("build-confirm")
            }
            Button { model.stopBuilding() } label: {
                Label(L("结束", "Done"), systemImage: "xmark").font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).frame(height: 32).background(Color.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("build-done")
        }
        .padding(.horizontal, 14).padding(.vertical, 6).glass(Capsule())
    }

    private var speedBar: some View {
        HStack(spacing: 2) {
            if model.speedIndex > 1 && model.actualSpeed < GameModel.speeds[model.speedIndex] * 0.8 {
                Text(String(format: L("实际 %.0f×", "real %.0f×"), model.actualSpeed)).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.orange).padding(.horizontal, 4)
            }
            ForEach(0..<GameModel.speeds.count, id: \.self) { i in
                Button { model.speedIndex = i } label: {
                    Group {
                        if i == 0 { Image(systemName: "pause.fill") } else { Text("\(Int(GameModel.speeds[i]))×") }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 40, height: 34)
                    .background(model.speedIndex == i ? Color.white.opacity(0.22) : .clear, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(4).glass(Capsule())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = model.playerPortrait {
                HStack(spacing: 8) {
                    Image(uiImage: p).interpolation(.none).resizable().scaledToFit().frame(width: 40, height: 40)
                        .padding(3).background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(L("你的像素形象（由照片生成）", "Your pixel character (from your photo)")).font(.system(size: 11, design: .rounded)).opacity(0.85)
                }
            }
            Text(model.statsText).font(.system(size: 13, design: .rounded))
            Text(model.techText).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.9, blue: 0.6))
            bar(model.techProgress, Color(red: 1, green: 0.8, blue: 0.3))
            Text(model.mapSizeText).font(.system(size: 11, design: .rounded)).foregroundStyle(Color(red: 0.75, green: 0.92, blue: 1))
            bar(model.mapSizeFraction, model.mapSizeFraction > 0.9 ? .red : .cyan)
            Text(model.memoryText).font(.system(size: 10, design: .rounded)).opacity(0.75)
            HStack(spacing: 6) {
                pill(L("立即清理内存", "Free memory now"), "sparkles") { model.cleanMemory(announce: true) }
                pill(model.autoClean ? L("自动清理：开", "Auto clean: on") : L("自动清理：关", "Auto clean: off"), "arrow.triangle.2.circlepath") { model.autoClean.toggle() }
            }
            ForEach(model.logLines, id: \.self) { Text($0).font(.system(size: 11, design: .rounded)).opacity(0.85) }
            Text(L("导入图片请确保你有权使用；素材只保存在本机。", "Only import pictures you may use; they stay on this device."))
                .font(.system(size: 9)).opacity(0.5)
        }
        .padding(14).frame(maxWidth: 380, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
    }

    private func bar(_ v: Double, _ c: Color) -> some View {
        Capsule().fill(Color.white.opacity(0.15)).frame(width: 320, height: 4)
            .overlay(alignment: .leading) { Capsule().fill(c).frame(width: 320 * max(0.01, min(1, v)), height: 4) }
    }

    private func pill(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func agentCard(_ info: Society.TalkInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let p = model.selectedPortrait {
                    Image(uiImage: p).interpolation(.none).resizable().scaledToFit().frame(width: 44, height: 44)
                        .padding(3).background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("\(info.name)  \(info.female ? "♀" : "♂") \(info.age)").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button { model.deselect() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28).background(Color.white.opacity(0.14), in: Circle()) }
                    .buttonStyle(PressStyle())
            }
            Text("\(info.settlement) · \(info.job)").font(.system(size: 12, design: .rounded)).opacity(0.85)
            HStack(spacing: 10) {
                meter(L("心情", "Mood"), info.mood, .green)
                meter(L("饥饿", "Hunger"), info.hunger, .orange)
                meter(L("精力", "Energy"), info.energy, .cyan)
            }
            Text("「\(info.line)」").font(.system(size: 13, weight: .medium, design: .rounded)).padding(.vertical, 2)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(info.family.prefix(3), id: \.self) { Text($0).font(.system(size: 11, design: .rounded)) }
            if info.pregnant { Text(L("怀孕中", "Expecting")).font(.system(size: 11, design: .rounded)).foregroundStyle(.pink) }
            ForEach(info.thoughts, id: \.self) { Text("· " + $0).font(.system(size: 11, design: .rounded)).opacity(0.8) }
            Text("\(info.settlement): \(info.stock)").font(.system(size: 10, design: .rounded)).opacity(0.6)
            HStack(spacing: 6) {
                pill(L("交谈", "Talk"), "bubble.left.fill") { model.talk() }
                pill(L("送食物", "Feed"), "fork.knife") { model.feed() }
            }
            HStack(spacing: 6) {
                pill(model.following ? L("停止跟随", "Unfollow") : L("跟随", "Follow"), "figure.walk") { model.following.toggle() }
                pill(L("照片/GIF/视频换装", "Photo / GIF / video"), "camera.fill") { model.pick = .villager(model.selectedID) }
            }
            HStack(spacing: 6) {
                pill(L("送花", "Flower"), "camera.macro") { model.gift("flower") }
                pill(L("约会", "Date"), "heart.fill") { model.date() }
                pill(L("求婚", "Propose"), "sparkles") { model.propose() }
                pill(L("掷骰", "Dice"), "dice.fill") { model.dice() }
            }
        }
        .padding(14).frame(width: 356, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func meter(_ title: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title) \(Int(v * 100))%").font(.system(size: 10, design: .rounded)).opacity(0.8)
            Capsule().fill(Color.white.opacity(0.15)).frame(width: 78, height: 4)
                .overlay(alignment: .leading) { Capsule().fill(c).frame(width: 78 * max(0.04, min(1, v)), height: 4) }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            tab(L("地图", "Map"), "map.fill") { model.toggleMap() }
            tab(L("建造", "Build"), "square.grid.3x3.fill") { model.showBuild = true }
            tab(L("制造", "Craft"), "hammer.fill") { model.showCraft = true }
            tab(L("城市", "Cities"), "building.columns.fill") { model.showCities = true }
            tab(L("战争", "War"), "shield.lefthalf.filled") { model.showWar = true }
            tab(L("纪事", "History"), "book.closed.fill") { model.showChronicle = true }
            tab(L("三国", "Nations"), "flag.2.crossed.fill") { model.showRealm = true; model.refreshRealm() }
            tab(L("能力", "Powers"), "bolt.fill") { model.showArsenal = true }
            tab(weaponName, weaponIcon) { model.cycleWeapon() }
            tab("", "plus.magnifyingglass") { model.scene?.zoomBy(0.5) }
            tab("", "minus.magnifyingglass") { model.scene?.zoomBy(-0.5) }
            Menu {
                Button { model.showLaws = true } label: { Label(L("法则", "Laws"), systemImage: "flame.fill") }
                Button { model.showCheats = true } label: { Label(L("作弊", "Cheats"), systemImage: "wand.and.rays") }
                Button { model.nextVillage() } label: { Label(L("村落", "Village"), systemImage: "house.fill") }
                Button { model.pick = .player } label: { Label(L("形象", "Photo"), systemImage: "person.crop.circle.badge.plus") }
                Button { model.pick = .asset } label: { Label(L("素材", "Import"), systemImage: "photo.badge.plus") }
                Button { model.cleanMemory(announce: true) } label: { Label(L("清理", "Clean"), systemImage: "sparkles") }
                Button { model.save(announce: true) } label: { Label(L("保存", "Save"), systemImage: "square.and.arrow.down.fill") }
                Button { model.exitToMenu() } label: { Label(L("世界", "Worlds"), systemImage: "globe.asia.australia.fill") }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "ellipsis.circle.fill").font(.system(size: 17, weight: .medium))
                    Text(L("更多", "More")).font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .frame(minWidth: 52, minHeight: 44)
            }
            .accessibilityIdentifier("more")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .glass(Capsule())
    }

    private var weaponName: String {
        if let p = Power.byKey[model.activePower] { return p.name(zh: GameModel.zh) }
        switch GameModel.weapons[model.weaponIndex] {
        case "sword": return L("剑", "Sword")
        case "bow": return L("弓", "Bow")
        case "staff": return L("法杖", "Staff")
        case "axe": return L("斧", "Axe")
        case "pick": return L("镐", "Pick")
        default: return L("空手", "Hands")
        }
    }

    private var weaponIcon: String {
        if !model.activePower.isEmpty { return "bolt.circle.fill" }
        switch GameModel.weapons[model.weaponIndex] {
        case "bow": return "scope"
        case "staff": return "wand.and.stars"
        case "sword": return "shield.lefthalf.filled"
        case "axe": return "hammer.fill"
        case "pick": return "wrench.adjustable.fill"
        default: return "hand.raised.fill"
        }
    }

    private func tab(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                if !title.isEmpty { Text(title).font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 62) }
            }
            .frame(minWidth: title.isEmpty ? 40 : 52, minHeight: 44)
        }
        .buttonStyle(PressStyle())
    }

    private var mapOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { model.toggleMap() }
            HStack(alignment: .center, spacing: 10) {
                mapCanvas
                mapControls
            }
            .padding(.vertical, 14).padding(.leading, 58).padding(.trailing, 20)
        }
    }

    private var mapCanvas: some View {
        let side = 330.0 * model.mapZoom
        return ScrollView([.horizontal, .vertical]) {
            if let img = model.mapImage {
                Image(uiImage: img).interpolation(.none).resizable().frame(width: side, height: side)
                    .onTapGesture(coordinateSpace: .local) { p in model.pickMap(Double(p.x) / side, Double(p.y) / side) }
                    .accessibilityIdentifier("map-image")
            }
        }
        .frame(width: 340, height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(6).glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var mapControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.mapCaption).font(.system(size: 11, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(L("放大后点击地图上的任意位置，再按“瞬移到这里”。紫色方块是迷宫。", "Zoom in, tap anywhere on the map, then press Teleport. Purple squares are mazes."))
                .font(.system(size: 10, design: .rounded)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                pill("1×", "minus.magnifyingglass") { model.mapZoom = 1 }
                pill("2×", "magnifyingglass") { model.mapZoom = 2 }
                pill("4×", "plus.magnifyingglass") { model.mapZoom = 4 }
            }
            pill(L("最近的迷宫", "Nearest maze"), "square.grid.3x3.fill") { model.pickNearestMaze() }
            if model.mapPick != nil {
                Button { model.teleportToPick() } label: {
                    Label(L("瞬移到这里", "Teleport here"), systemImage: "location.fill").font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 16).frame(height: 44).background(Color(red: 0.45, green: 0.4, blue: 0.95), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("teleport")
            }
            pill(L("关闭地图", "Close map"), "xmark") { model.toggleMap() }
        }
        .padding(14).frame(width: 300, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
