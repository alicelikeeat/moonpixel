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
    @State private var speedOpen = false             // the speed bar opened out (it folds back to the current speed)
    @State private var tabsOpen = false              // the tab bar grown longer with the shortcuts
    @State private var longPressed = false           // a long press just acted: the tap that ends it does nothing

    var body: some View {
        ZStack(alignment: .top) {                         // whatever grows, the top row (clock, speed) stays on screen
            if model.showMap { mapOverlay }
            // driving: the vehicle's own controls take the bottom of the screen (walking controls and tabs step aside)
            if !model.showMap && !(model.drive?.driving ?? false) { PlayControls() }
            if !model.showMap, let d = model.drive { DriveHUD(d: d) }
            // the map takes the whole screen: the HUD steps away so nothing lies over it
            if !model.showMap { VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation(.snappy) { model.showDetails.toggle(); model.refreshHUD() } } label: {
                            Text(model.status).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).fixedSize()
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(PressStyle()).glass(Capsule())
                        Text(model.playerLine).font(.system(size: 10, weight: .medium, design: .rounded)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 5).glass(Capsule()).allowsHitTesting(false)
                        // a long details sheet scrolls inside the room above the tabs instead of pushing them off the screen
                        if model.showDetails {
                            ScrollView(.vertical, showsIndicators: false) { details }
                                .frame(maxHeight: max(140, UIScreen.main.bounds.height - 210))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    Spacer(minLength: 0)
                    // the last message, kept for assistive technology and UI tests after the toast has faded
                    Text(model.toast).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)
                        .accessibilityIdentifier("last-toast").allowsHitTesting(false)
                    if toastVisible {
                        Text(model.toast).font(.system(size: 13, weight: .medium, design: .rounded)).lineLimit(2).minimumScaleFactor(0.8)
                            .padding(.horizontal, 14).padding(.vertical, 9).glass(Capsule())
                            .layoutPriority(-1)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 8) {
                        speedBar
                        // the card of someone selected takes the place of the notices: both never fit together
                        // a person's card can be long (thoughts, family, actions): it scrolls inside a capped height,
                        // so it never makes the HUD taller than a landscape phone and shifts the top row off screen
                        if let info = model.selected {
                            ScrollView(.vertical, showsIndicators: false) { agentCard(info) }
                                .frame(width: 356).frame(maxHeight: 230)
                                .accessibilityIdentifier("agent-card")
                        } else { noticeStack }
                    }
                }
                if model.lawSavePending { savePendingBar }
                if model.exitBlocked != nil { exitBlockedBar }
                Spacer(minLength: 0)
                if model.watch != .none { watchBar }
                if model.pendingPlan != nil || !model.buildMode.isEmpty { buildBar }
                if !(model.drive?.driving ?? false) { tabBar }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)       // if it ever overflows, the top stays on screen
            }
        }
        .foregroundStyle(.white)
        .overlay(alignment: .bottomLeading) {
            if model.showPerf && !model.perfLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.perfLines.enumerated()), id: \.offset) { _, l in Text(l) }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white)
                .padding(8).glass(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.leading, 10).padding(.bottom, 92)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine).accessibilityIdentifier("perf-panel")
            }
        }
        // the top row stays at the top of the screen: anything taller than the screen grows downwards,
        // it never pushes the clock, speed and zoom buttons up off the screen
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay { if model.showBackpack { BackpackPanel() } }
        .overlay { if let id = model.liftPanel { LiftPanel(id: id) } }
        .overlay { if model.showTravel { TravelPanel() } }
        .overlay { if model.showTransport { TransportPanel() } }
        .overlay { if model.showRealm { RealmPanel() } }
        .overlay { if let id = model.civDetail { CivNationSheet(id: id) } }
        .overlay { if let id = model.towerDetail { TowerSheet(id: id) } }
        .overlay { if model.showLaws { LawsPanel() } }
        .overlay { if model.showArsenal { ArsenalPanel() } }
        .overlay { if model.showBuild { BuildPanel() } }
        .overlay { if model.showCraft { CraftPanel() } }
        .overlay { if model.showCities { CitiesPanel() } }
        .overlay { if model.showChronicle { ChroniclePanel() } }
        .overlay { if model.showWar { WarPanel() } }
        .overlay { if model.showMore { MorePanel() } }
        .overlay { if model.showCheats { CheatPanel() } }
        .overlay { if model.showDiagnostics { DiagnosticsPanel() } }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if model.toastID == id { withAnimation(.easeOut) { toastVisible = false } } }
        }
    }

    /// Clickable news of war: tap one to look at where it happened.
    private var noticeStack: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // at most three, newest last: a long war must not push the top of the HUD off a phone screen
            ForEach(Array(model.notices.suffix(3))) { n in
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

    /// Leaving was refused because the save failed: the world is still here, paused, and can be saved again.
    private var exitBlockedBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("保存失败，没有离开这个世界", "Saving failed, so the world was not closed")).font(.system(size: 12, weight: .bold, design: .rounded))
                Text(model.exitBlocked ?? "").font(.system(size: 10, design: .rounded)).opacity(0.85).lineLimit(3)
            }
            Button { model.retryExit() } label: {
                Label(L("重试保存并离开", "Retry and leave"), systemImage: "arrow.clockwise").font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).frame(minHeight: 44).background(Color.white.opacity(0.22), in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("retry-exit")
            Button { model.stayAfterFailedExit() } label: {
                Text(L("继续游戏", "Keep playing")).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12).frame(minHeight: 44).background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("stay")
        }
        .padding(.horizontal, 14).padding(.vertical, 8).glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exit-blocked")
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

    /// The game's speed: folded, one capsule with the current speed (tap to open, long press to pause or go
    /// on); opened, every speed in a row that grows out of it. Choosing one folds it back.
    private var speedBar: some View {
        HStack(spacing: 2) {
            if model.speedIndex > 1 && model.actualSpeed < GameModel.speeds[model.speedIndex] * 0.8 {
                Text(String(format: L("实际 %.0f×", "real %.0f×"), model.actualSpeed)).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.orange).padding(.horizontal, 4)
            }
            if speedOpen {
                ForEach(0..<GameModel.speeds.count, id: \.self) { i in
                    Button {
                        model.speedIndex = i
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { speedOpen = false }
                    } label: {
                        speedLabel(i)
                            .frame(width: 40, height: 34)
                            .background(model.speedIndex == i ? Color.white.opacity(0.22) : .clear, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .transition(.scale(scale: 0.4, anchor: .trailing).combined(with: .opacity))
                }
            } else {
                Button {
                    if longPressed { longPressed = false; return }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.75)) { speedOpen = true }
                    let opened = Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if speedOpen && Date().timeIntervalSince(opened) >= 4.9 { withAnimation(.snappy) { speedOpen = false } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        speedLabel(model.speedIndex)
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)).opacity(0.6)
                    }
                    .frame(height: 34).padding(.horizontal, 10)
                }
                .buttonStyle(PressStyle())
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    longPressed = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.speedIndex = model.speedIndex == 0 ? 1 : 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { longPressed = false }
                })
                .accessibilityIdentifier("speed")
                .accessibilityLabel(L("速度 ", "Speed ") + (model.speedIndex == 0 ? L("暂停", "paused") : "\(Int(GameModel.speeds[model.speedIndex]))x"))
            }
        }
        .padding(4).glass(Capsule())
    }

    @ViewBuilder private func speedLabel(_ i: Int) -> some View {
        Group {
            if i == 0 { Image(systemName: "pause.fill") } else { Text("\(Int(GameModel.speeds[i]))×") }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
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

    /// The tabs. Six at hand; the chevron (or a long press on More) makes the bar grow longer with shortcuts to
    /// the other panels. A long press on a tab does its second thing: the map opens in detail, Build opens
    /// crafting, Nations the cities, Powers the war, the weapon the arsenal.
    private var tabBar: some View {
        let room = max(320, min(UIScreen.main.bounds.width - 300, 760))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                tab(L("地图", "Map"), "map.fill", long: { model.toggleMap(); model.setMapZoom(8) }) { model.toggleMap() }
                tab(L("建造", "Build"), "square.grid.3x3.fill", long: { model.showCraft = true }) { model.showBuild = true }
                tab(L("国度", "Nations"), "flag.2.crossed.fill", long: { model.showCities = true }) { model.showRealm = true; model.refreshRealm() }
                tab(L("能力", "Powers"), "bolt.fill", long: { model.showWar = true }) { model.showArsenal = true }
                tab(weaponName, weaponIcon, long: { model.showArsenal = true }) { model.cycleWeapon() }
                tab(L("更多", "More"), "ellipsis.circle.fill", long: { withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { tabsOpen.toggle() } }) { model.showMore = true }
                    .accessibilityIdentifier("more")
                if tabsOpen {
                    Divider().frame(height: 30).overlay(Color.white.opacity(0.3)).padding(.horizontal, 3)
                    Group {
                        tab(L("城市", "Cities"), "building.columns.fill") { model.showCities = true }.accessibilityIdentifier("quick-cities")
                        tab(L("战争", "War"), "shield.lefthalf.filled") { model.showWar = true }.accessibilityIdentifier("quick-war")
                        tab(L("纪事", "History"), "book.closed.fill") { model.showChronicle = true }.accessibilityIdentifier("quick-history")
                        tab(L("制造", "Craft"), "hammer.fill") { model.showCraft = true }.accessibilityIdentifier("quick-craft")
                        tab(L("交通", "Transport"), "tram.fill") { model.showTransport = true }.accessibilityIdentifier("quick-transport")
                        tab(L("背包", "Pack"), "backpack.fill") { model.showBackpack = true }.accessibilityIdentifier("quick-pack")
                        tab(L("法则", "Laws"), "flame.fill") { model.showLaws = true }.accessibilityIdentifier("quick-laws")
                        tab(L("保存", "Save"), "square.and.arrow.down.fill") { model.save(announce: true) }.accessibilityIdentifier("quick-save")
                    }
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { tabsOpen.toggle() }
                } label: {
                    Image(systemName: tabsOpen ? "chevron.left.2" : "chevron.right.2").font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 44).opacity(0.8)
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("expand-tabs")
                .accessibilityLabel(tabsOpen ? L("收起", "Fewer") : L("展开更多按键", "More buttons"))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
        .fixedSize(horizontal: !tabsOpen, vertical: false)
        .frame(maxWidth: tabsOpen ? room : nil)
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

    private func tab(_ title: String, _ icon: String, long: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        Button {
            if longPressed { longPressed = false; return }
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
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            guard let long = long else { return }
            longPressed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            long()
            // if the finger lifts outside the button no tap comes to clear it
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { longPressed = false }
        })
    }

    /// The map, over the whole screen (the HUD is away while it is open): a title bar with the close button,
    /// the map as large as the screen allows, and its controls beside it (below it on a tall screen).
    private var mapOverlay: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            GeometryReader { g in
                let wide = g.size.width > g.size.height * 1.15
                let panelW = min(300, max(230, g.size.width * 0.32))
                let headerH: Double = 40
                let box = wide ? max(160, min(g.size.height - headerH - 14, g.size.width - panelW - 34))
                               : max(160, min(g.size.width - 20, (g.size.height - headerH) * 0.55))
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Label(L("世界地图", "World map"), systemImage: "map.fill").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text(model.mapCaption).font(.system(size: 10, design: .rounded)).opacity(0.7).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        // closes the map; named like the tab that opened it
                        Button { model.toggleMap() } label: {
                            Label(L("地图", "Map"), systemImage: "xmark").labelStyle(.iconOnly)
                                .font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.18), in: Circle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(L("地图", "Map"))
                    }
                    .frame(height: headerH)
                    if wide {
                        HStack(alignment: .top, spacing: 12) {
                            mapCanvas(box: box)
                            ScrollView(.vertical, showsIndicators: false) { mapControls(width: panelW) }
                                .frame(width: panelW).frame(maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 10) {
                            mapCanvas(box: box)
                            ScrollView(.vertical, showsIndicators: false) { mapControls(width: g.size.width - 20) }
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
                .frame(width: g.size.width, height: g.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func mapCanvas(box: Double) -> some View {
        let side = (box - 10) * model.mapZoom
        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    if let img = model.mapImage {
                        // smooth when shrunk, crisp when enlarged
                        Image(uiImage: img).interpolation(model.mapZoom >= 2 ? .none : .high).resizable().frame(width: side, height: side)
                            .onTapGesture(count: 2, coordinateSpace: .local) { p in      // a double tap: go there at once
                                model.pickMap(Double(p.x) / side, Double(p.y) / side); model.teleportToPick()
                            }
                            .onTapGesture(count: 1, coordinateSpace: .local) { p in model.pickMap(Double(p.x) / side, Double(p.y) / side) }
                            .accessibilityIdentifier("map-image")
                    }
                    ForEach(Array(model.mapMarkers.enumerated()), id: \.offset) { _, m in marker(m, side: side) }
                    if let p = model.mapPick {
                        let f = model.worldMap.fraction(p)
                        Image(systemName: "scope").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            .shadow(color: .black, radius: 2).position(x: f.0 * side, y: f.1 * side).allowsHitTesting(false)
                    }
                }
                .frame(width: side, height: side)
            }
            .onAppear { proxy.scrollTo("map-me", anchor: .center) }
            .onChange(of: model.mapZoom) { _, _ in DispatchQueue.main.async { proxy.scrollTo("map-me", anchor: .center) } }
        }
        .frame(width: box, height: box)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(6).glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// A place on the map: a dot in its colour and its name (towns by name only when enlarged, so the
    /// whole-world view stays readable). A tap on a place's name goes there.
    @ViewBuilder private func marker(_ m: MapMarker, side: Double) -> some View {
        let col = Color(uiColor: UIColor(hex: m.color))
        let at = CGPoint(x: m.fx * side, y: m.fy * side)
        switch m.kind {
        case .player:
            ZStack {
                Circle().fill(Color.cyan.opacity(0.35)).frame(width: 18, height: 18)
                Circle().fill(Color.cyan).frame(width: 9, height: 9).overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .position(at).allowsHitTesting(false).id("map-me")
        case .maze:
            EmptyView()
        case .ufo:
            Image(systemName: "circle.circle.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cyan).shadow(color: .black, radius: 1).position(at).allowsHitTesting(false)
        case .building:
            // on the detailed map: the building's name at its door; a tap goes there
            if model.mapZoom >= 8 {
                Button { model.teleport(to: m.tile, name: m.name) } label: {
                    Text(m.name).font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 3).padding(.vertical, 1).background(Color(uiColor: UIColor(hex: m.color)).opacity(0.85), in: Capsule())
                }
                .buttonStyle(.plain).fixedSize().position(x: at.x, y: at.y - 6)
                .accessibilityIdentifier("map-building-" + m.name)
            }
        case .underCity:
            // the way down to an underground city: a purple stairway mark, its name once enlarged
            Image(systemName: "arrow.down.square.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(col).shadow(color: .black, radius: 1).position(at).allowsHitTesting(false)
            if model.mapZoom >= 4 {
                Text(m.name).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 3).background(Color.black.opacity(0.45), in: Capsule()).fixedSize()
                    .position(x: at.x, y: at.y - 10).allowsHitTesting(false)
            }
        case .volcano:
            Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.orange).shadow(color: .black, radius: 1).position(at).allowsHitTesting(false)
        case .monument:
            // a capital's landmark: a gold column; its name once the map is enlarged, a tap goes there
            Image(systemName: "building.columns.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(col).shadow(color: .black, radius: 1).position(at).allowsHitTesting(false)
            if model.mapZoom >= 2 {
                Button { model.teleport(to: m.tile, name: m.name) } label: {
                    Text(m.name).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 4).padding(.vertical, 1).background(col.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain).fixedSize().position(x: at.x, y: at.y - 11)
                .accessibilityIdentifier("map-monument-" + m.name)
            }
        case .army:
            Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(col).shadow(color: .black, radius: 1).position(at).allowsHitTesting(false)
        case .airport:
            if model.mapZoom >= 2 { Image(systemName: "airplane").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 1).position(at).allowsHitTesting(false) }
        default:
            let big = m.kind == .capital || m.kind == .city
            Circle().fill(col).frame(width: big ? 9 : 7, height: big ? 9 : 7).overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1.5))
                .position(at).allowsHitTesting(false)
            if big || model.mapZoom >= 2 {
                Button { model.teleport(to: m.tile, name: m.name) } label: {
                    Text((m.kind == .capital ? "★ " : "") + m.name).font(.system(size: big ? 11 : 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.black.opacity(0.45), in: Capsule())
                }
                .buttonStyle(.plain).fixedSize()
                .position(x: at.x, y: at.y - 13)
                .accessibilityIdentifier("map-place-" + m.name)
            }
        }
    }

    /// A small button that shares a row with others (wraps instead of running off the panel).
    private func gridPill(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private func mapControls(width: Double) -> some View {
        let grid = [GridItem(.adaptive(minimum: 96), spacing: 6)]
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("点一下选中格子，双击直接瞬移；点地名立刻前往。", "Tap to pick a tile, double-tap to go there at once; tap a name to go to that place."))
                .font(.system(size: 10, design: .rounded)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
            Text(model.mapCaption).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)      // for tests and voice-over
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], alignment: .leading, spacing: 6) {
                gridPill("1×", "minus.magnifyingglass") { model.setMapZoom(1) }
                gridPill("2×", "magnifyingglass") { model.setMapZoom(2) }
                gridPill("4×", "plus.magnifyingglass") { model.setMapZoom(4) }
                gridPill(L("8× 详细", "8× detail"), "building.2") { model.setMapZoom(8) }
            }
            if model.mapPick != nil {
                Text(model.mapPickText).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("map-pick-text")
                Button { model.teleportToPick() } label: {
                    Label(L("瞬移到这里", "Teleport here"), systemImage: "location.fill").font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 40).background(Color(red: 0.45, green: 0.4, blue: 0.95), in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("teleport")
            }
            // quick travel: the nearest places by name
            let me = model.scene?.player.tile ?? TilePos(0, 0)
            let near = model.mapMarkers.filter { [.capital, .town, .city, .district].contains($0.kind) }
                .sorted { $0.tile.distance2(me) < $1.tile.distance2(me) }.prefix(4)
            if !near.isEmpty {
                Text(L("快速前往", "Go to")).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.7)
                LazyVGrid(columns: grid, alignment: .leading, spacing: 6) {
                    ForEach(Array(near.enumerated()), id: \.offset) { _, m in
                        gridPill((m.kind == .capital ? "★" : "") + m.name, "mappin") { model.teleport(to: m.tile, name: m.name) }
                    }
                }
            }
            Text(L("找地方", "Find")).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.7)
            LazyVGrid(columns: grid, alignment: .leading, spacing: 6) {
                gridPill(L("地下城", "Underground city"), "arrow.down.to.line") { model.pickNearestUnderCity() }
                gridPill(L("UFO机场", "UFO port"), "circle.circle.fill") { model.pickNearestUfoPort() }
                gridPill(L("火山", "Volcano"), "flame.fill") { model.pickNearestVolcano() }
            }
        }
        .padding(14).frame(width: width, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

}
