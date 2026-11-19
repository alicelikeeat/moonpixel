import SwiftUI
import MoonPixelCore

/// Full-screen glass sheet used by the nations panel and the world-laws panel.
struct GlassSheet<Content: View>: View {
    let title: String
    let subtitle: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title).font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(subtitle).font(.system(size: 11, design: .rounded)).opacity(0.75).lineLimit(1)
                    Spacer(minLength: 4)
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 34).background(Color.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("close-panel")
                }
                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.leading, 58).padding(.trailing, 20).padding(.vertical, 10)      // clear of the Dynamic Island in landscape
        }
        .foregroundStyle(.white)
    }
}

struct Chip: View {
    let title: String
    let icon: String
    var tint: Color = Color.white.opacity(0.14)
    var id: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1).fixedSize()
                .padding(.horizontal, 11).frame(height: 36).background(tint, in: Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier(id.isEmpty ? title : id)
    }
}

struct Meter: View {
    let value: Double
    let color: Color
    var body: some View {
        Capsule().fill(Color.white.opacity(0.15)).frame(width: 120, height: 4)
            .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 120 * max(0.02, min(1, value)), height: 4) }
    }
}

/// The nations around the player's towns (cards: land, people, relations, pressure, fatigue and what the
/// player can do about them), then every nation of the known world (CivWorldSection: as many as there are).
struct RealmPanel: View {
    @EnvironmentObject var model: GameModel
    @State private var world = false

    var body: some View {
        GlassSheet(title: L("国度", "Nations"), subtitle: model.eraLine, close: { model.showRealm = false }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Chip(title: L("附近", "Nearby"), icon: "house.and.flag.fill", tint: world ? Color.white.opacity(0.12) : Color.white.opacity(0.32), id: "realm-tab-near") { world = false }
                    Chip(title: L("已知世界", "Known world"), icon: "globe.asia.australia.fill", tint: world ? Color.white.opacity(0.32) : Color.white.opacity(0.12), id: "realm-tab-world") { world = true }
                }
                if world { CivWorldSection() } else { nearby }
            }
        }
    }

    /// The nations around the player's own towns, and what the player can do among them.
    private var nearby: some View {
            VStack(alignment: .leading, spacing: 10) {
                // the cards wrap onto as many rows as they need: nothing is cut off or laid over anything
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                    ForEach(model.nationCards) { c in card(c) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("各国关系", "Relations")).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.8)
                    ForEach(model.relationLines, id: \.self) { Text($0).font(.system(size: 12, design: .rounded)).fixedSize(horizontal: false, vertical: true) }
                }
                Text(model.playerLine).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color(red: 0.75, green: 0.92, blue: 1))
                    .fixedSize(horizontal: false, vertical: true)
                cemeteries
                actions
                Text(L("捐赠、战斗、修路拆桥、补给站和接纳难民都会真实改变粮食、补给、兵力和国家关系。斧砍树得木，镐采石得石，镐和斧可拆毁道路、桥梁和补给站。",
                       "Giving, fighting, building or breaking roads, bridges and depots, and sheltering refugees really change food, supply, armies and relations. The axe gives wood, the pick gives stone; both can break roads, bridges and depots."))
                    .font(.system(size: 10, design: .rounded)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
            }
    }

    /// The graves of nations that have passed away, with their records, and the way there.
    @ViewBuilder private var cemeteries: some View {
        let graves = model.society?.cemeteries ?? []
        if !graves.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("国家公墓", "National cemeteries"), systemImage: "building.columns").font(.system(size: 13, weight: .bold, design: .rounded))
                ForEach(graves, id: \.id) { m in
                    if let r = m.grave {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: r.color)).frame(width: 9, height: 9)
                                Text(r.lines(zh: GameModel.zh)[0]).font(.system(size: 13, weight: .bold, design: .rounded))
                                Spacer(minLength: 4)
                                Chip(title: L("前往", "Go"), icon: "location.fill", id: "grave-\(r.nation)") {
                                    model.showRealm = false
                                    model.teleport(to: TilePos(m.x + m.w / 2, m.y + m.d + 1), name: m.title(zh: GameModel.zh))
                                }
                            }
                            ForEach(Array(r.lines(zh: GameModel.zh).dropFirst().enumerated()), id: \.offset) { _, l in
                                Text(l).font(.system(size: 11, design: .rounded)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    /// A small coloured label on a card.
    private func tag(_ text: String, _ color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let i = icon { Image(systemName: i).font(.system(size: 8, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.32), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
    }

    private func card(_ c: NationCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // name, then its labels (they wrap): yours, allied with..., at war with..., in exile
            HStack(spacing: 6) {
                Circle().fill(Color(hex: c.color)).frame(width: 12, height: 12)
                Text(c.name).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            let tags = LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 4, alignment: .leading)], alignment: .leading, spacing: 4) {
                if c.joined { tag(L("你的国家", "Yours"), .white, icon: "person.fill") }
                if c.landless { tag(L("流亡中", "In exile"), .gray, icon: "figure.walk") }
                ForEach(Array(c.allies.enumerated()), id: \.offset) { _, a in tag(L("盟友 ", "Ally ") + a.name, Color(hex: a.color), icon: "link") }
                ForEach(Array(c.foes.enumerated()), id: \.offset) { _, f in tag(L("交战 ", "War ") + f, .red, icon: "flame.fill") }
            }
            if c.joined || c.landless || !c.allies.isEmpty || !c.foes.isEmpty { tags }
            // the overall strength, large, with its share of the world
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L("综合国力", "Strength")).font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.8)
                Text("\(c.composite)").font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(String(format: L("占世界 %d%%", "%d%% of the world"), Int(c.share * 100))).font(.system(size: 10, design: .rounded)).opacity(0.7)
            }
            Capsule().fill(Color.white.opacity(0.15)).frame(height: 5)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(Color(hex: c.color)).frame(width: g.size.width * max(0.02, min(1, c.share))) } }
            // the figures in two columns
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(0..<((c.facts.count + 1) / 2), id: \.self) { r in
                    GridRow {
                        ForEach(0..<2, id: \.self) { k in
                            let i = r * 2 + k
                            if i < c.facts.count {
                                HStack(spacing: 4) {
                                    Text(c.facts[i].0).font(.system(size: 10, design: .rounded)).opacity(0.65)
                                    Text(c.facts[i].1).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                            } else { Color.clear.frame(height: 1) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(String(format: L("压力 %d%%", "Pressure %d%%"), Int(c.pressure * 100))).font(.system(size: 10, design: .rounded)).frame(width: 74, alignment: .leading); Meter(value: c.pressure, color: .orange) }
                HStack(spacing: 6) { Text(String(format: L("疲劳 %d%%", "Fatigue %d%%"), Int(c.fatigue * 100))).font(.system(size: 10, design: .rounded)).frame(width: 74, alignment: .leading); Meter(value: c.fatigue, color: .red) }
            }
            Chip(title: c.joined ? L("退出", "Leave") : L("加入", "Join"), icon: c.joined ? "figure.walk.departure" : "flag.fill", id: "join-\(c.id)") {
                model.joinNation(c.joined ? 0 : c.id)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: c.color).opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: c.color).opacity(c.joined ? 0.8 : 0.25), lineWidth: c.joined ? 2 : 1))
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            Chip(title: L("捐粮 20", "Give food 20"), icon: "fork.knife", id: "give-food") { model.donate("food") }
            Chip(title: L("捐木 20", "Give wood 20"), icon: "tree.fill", id: "give-wood") { model.donate("wood") }
            Chip(title: L("捐石 20", "Give stone 20"), icon: "mountain.2.fill", id: "give-stone") { model.donate("stone") }
            Chip(title: L("接纳难民", "Shelter refugees"), icon: "house.and.flag.fill", id: "refugees") { model.acceptRefugees() }
            build("road", L("修路（石 1）", "Road (1 stone)"), "road.lanes")
            build("bridge", L("架桥（木 3）", "Bridge (3 wood)"), "water.waves")
            build("depot", L("补给站（木 8 石 4）", "Depot (8 wood, 4 stone)"), "shippingbox.fill")
            if !model.buildMode.isEmpty { Chip(title: L("停止建造", "Stop building"), icon: "xmark", id: "build-off") { model.buildMode = "" } }
        }
    }

    private func build(_ kind: String, _ title: String, _ icon: String) -> some View {
        Chip(title: title, icon: icon, tint: model.buildMode == kind ? Color.white.opacity(0.34) : Color.white.opacity(0.14), id: "build-" + kind) {
            model.buildMode = kind
            model.showRealm = false
            model.showToast(L("建造模式：点击身边的地面放置", "Build mode: tap the ground near you"))
        }
    }
}

/// World laws: one tap, real and permanent deletion. Also storage figures and the capacity policy.
struct LawsPanel: View {
    @EnvironmentObject var model: GameModel
    private let danger = Color(red: 0.85, green: 0.25, blue: 0.22)

    var body: some View {
        GlassSheet(title: L("世界法则", "World laws"), subtitle: L("一键执行 · 永久删除 · 无法撤销", "One tap · permanent · cannot be undone"), close: { model.showLaws = false }) {
            VStack(alignment: .leading, spacing: 10) {
                if model.lawBusy {
                    ProgressView(value: model.lawProgress).tint(.white)
                }
                if !model.lawReport.isEmpty {
                    Text(model.lawReport).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.9, blue: 0.6))
                        .accessibilityIdentifier("law-report")
                }
                HStack(alignment: .top, spacing: 8) { thanos; annihilation }
                HStack(alignment: .top, spacing: 8) { genesis; guixu }
                storage
            }
        }
        .onAppear { model.refreshStorage() }
    }

    private func lawCard<Options: View>(_ title: String, _ text: String, _ button: String, _ id: String, _ mode: LawMode, @ViewBuilder options: () -> Options) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(text).font(.system(size: 11, design: .rounded)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
            options()
            Button { model.runLaw(mode) } label: {
                Label(button, systemImage: "trash.fill").font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 12).frame(height: 40).frame(maxWidth: .infinity).background(danger, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(model.lawBusy)
            .accessibilityIdentifier(id)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func option(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium, design: .rounded)).lineLimit(1).fixedSize()
                .padding(.horizontal, 9).frame(height: 30).background(Color.white.opacity(on ? 0.34 : 0.12), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var thanos: some View {
        lawCard(L("灭霸", "Thanos"),
                L("随机选中全部存活居民的一半（向下取整），永久删除。你自己不受影响。之后一段时间内不会有流浪者补充人口。",
                  "Half of all living villagers (rounded down), chosen at random, are deleted for good. You are not affected. No wanderers arrive for a while afterwards."),
                L("永久删除 50% 居民", "Delete 50% of villagers forever"), "law-thanos", .thanos) { EmptyView() }
    }

    private var annihilation: some View {
        lawCard(L("湮灭", "Annihilation"),
                L("按比例随机永久删除居民、建筑、摆件、区块修改和历史记录；或改为按要回收的空间删除。",
                  "A random share of villagers, buildings, placed objects, map changes and history is deleted for good - or as much as it takes to free the chosen space."),
                model.lawSpaceMB > 0 ? String(format: L("永久删除约 %d MB 的世界内容", "Delete about %d MB of world content forever"), model.lawSpaceMB)
                                     : String(format: L("永久删除每类内容的 %d%%", "Delete %d%% of every kind forever"), Int(model.lawRatio * 100)),
                "law-annihilation", .annihilation) {
            HStack(spacing: 4) {
                option("25%", model.lawSpaceMB == 0 && model.lawRatio == 0.25) { model.lawSpaceMB = 0; model.lawRatio = 0.25 }
                option("30%", model.lawSpaceMB == 0 && model.lawRatio == 0.3) { model.lawSpaceMB = 0; model.lawRatio = 0.3 }
                option("50%", model.lawSpaceMB == 0 && model.lawRatio == 0.5) { model.lawSpaceMB = 0; model.lawRatio = 0.5 }
                option("75%", model.lawSpaceMB == 0 && model.lawRatio == 0.75) { model.lawSpaceMB = 0; model.lawRatio = 0.75 }
                option("1 MB", model.lawSpaceMB == 1) { model.lawSpaceMB = 1 }
                option("100 MB", model.lawSpaceMB == 100) { model.lawSpaceMB = 100 }
            }
        }
    }

    private var genesis: some View {
        lawCard(L("创世纪", "Genesis"),
                L("永久删除这个世界的全部居民、城镇、地图和历史，并重新生成一个世界。保留世界名称、你的外观及其素材。",
                  "Every villager, town, map chunk and all history of this world is deleted for good and a new world is generated. The world's name, your look and its assets are kept."),
                L("永久删除整个世界并重新生成", "Delete the whole world and generate a new one"), "law-genesis", .genesis) {
            HStack(spacing: 4) {
                option(L("新种子", "New seed"), model.lawNewSeed) { model.lawNewSeed = true }
                option(L("同一种子", "Same seed"), !model.lawNewSeed) { model.lawNewSeed = false }
            }
        }
    }

    private var guixu: some View {
        lawCard(L("归墟", "Guixu"),
                L("随机选中一片连续区域，永久删除其中所有人工内容（建筑、道路、农田、摆件），恢复自然地形。跨出区域的建筑整栋删除；居民不会被删除，会成为难民迁往别处。",
                  "A random connected region loses everything people made there (buildings, roads, farms, objects) for good and returns to wild land. Buildings crossing the edge go as a whole; residents are not deleted, they leave as refugees."),
                String(format: L("永久抹平随机 %d×%d 区块的人工内容", "Wipe everything built in a random %d×%d chunk region forever"), model.lawRadius * 2 + 1, model.lawRadius * 2 + 1),
                "law-guixu", .guixu) {
            HStack(spacing: 4) {
                option("3×3", model.lawRadius == 1) { model.lawRadius = 1 }
                option("5×5", model.lawRadius == 2) { model.lawRadius = 2 }
                option("9×9", model.lawRadius == 4) { model.lawRadius = 4 }
            }
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("存储", "Storage")).font(.system(size: 14, weight: .bold, design: .rounded))
            ForEach(model.storageLines, id: \.self) { Text($0).font(.system(size: 11, design: .rounded)).opacity(0.9) }
            Text(L("容量策略（清理缓存不会删除世界；后两种会在超过水位时自动、永久地删除内容）",
                   "Capacity policy (clearing caches never deletes the world; the last two delete content automatically and for good above the high-water mark)"))
                .font(.system(size: 10, design: .rounded)).opacity(0.65)
            HStack(spacing: 4) {
                option(L("缓存优先（不删除）", "Cache first (no deletion)"), model.policy.mode == .cacheFirst) { model.setPolicy(.cacheFirst) }
                option(L("自动湮灭", "Auto annihilation"), model.policy.mode == .autoAnnihilation) { model.setPolicy(.autoAnnihilation) }
                option(L("区域轮回", "Region cycle"), model.policy.mode == .regionCycle) { model.setPolicy(.regionCycle) }
            }
            HStack(spacing: 4) {
                Text(L("上限", "Limit")).font(.system(size: 11, design: .rounded)).opacity(0.75)
                option("50 MB", model.limitMB == 50) { model.setLimit(50) }
                option("500 MB", model.limitMB == 500) { model.setLimit(500) }
                option("1 GB", model.limitMB == 1024) { model.setLimit(1024) }
                option("5 GB", model.limitMB == 5120) { model.setLimit(5120) }
                Chip(title: L("仅清理缓存", "Clear caches only"), icon: "sparkles", id: "clear-cache") { model.cleanMemory(announce: true) }
            }
        }
    }
}
