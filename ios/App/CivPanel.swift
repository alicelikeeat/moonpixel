import SwiftUI
import MoonPixelCore

// The nations of the known world (Civ.swift): a list that grows with history (searched, sorted and
// starred, never a row of tabs), and for each nation its people, food, money, research, arms and
// neighbours, each with the reason behind it. A regional nation can be taken in hand: rations,
// building, ordering machines, crewing them and sending forces are then the player's to decide.

enum CivSort: String, CaseIterable { case people, power, food, tech, name }

struct CivWorldSection: View {
    @EnvironmentObject var model: GameModel
    @State private var query = ""
    @State private var sort = CivSort.people
    @State private var showGone = false
    @State private var nearOnly = false
    @State private var favourites: Set<Int> = Set((UserDefaults.standard.array(forKey: "civFavourites") as? [Int]) ?? [])

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let c = model.society.civ
            VStack(alignment: .leading, spacing: 8) {
                summary(c)
                controls
                if c.activePolities().isEmpty {
                    Text(L("现在没有在位的国家：都已流亡或成为历史。你仍可以无国籍旅行，或在城镇里建国。", "No nation stands now: every one is in exile or history. You can travel without a nation, or found one in a town."))
                        .font(.system(size: 12, design: .rounded)).opacity(0.8).accessibilityIdentifier("civ-none")
                }
                // every nation known, however many: a lazy list draws only the rows on screen
                LazyVStack(alignment: .leading, spacing: 8) { ForEach(rows(c), id: \.id) { p in row(p, c) } }
            }
        }
    }

    private func summary(_ c: Civ) -> some View {
        let active = c.activePolities().count, total = c.polities.count
        let wars = c.relations.values.filter { $0.state == 1 }.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("已知世界", "The known world")).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(L("已知地区人口 \(model.society.knownPopulation) · 国家 \(active) 个在位 / 共 \(total) 个 · 战争 \(wars) 处 · 已知地区 \(c.regions.count) 块",
                   "Known population \(model.society.knownPopulation) · nations \(active) standing / \(total) in all · wars \(wars) · regions known \(c.regions.count)"))
                .font(.system(size: 11, design: .rounded)).opacity(0.85).accessibilityIdentifier("civ-summary")
            Text(String(format: L("附近画出的人物 %d（画面上限，不是人口上限）· 附近城镇居民 %d", "Drawn nearby %d (a drawing limit, not a population limit) · residents of nearby towns %d"),
                        model.scene?.agentNodes.count ?? 0, model.society.agents.count))
                .font(.system(size: 10, design: .rounded)).opacity(0.7).accessibilityIdentifier("civ-counts")
            Text(L("未探索地区的人口不计入；走得越远，认识的国家越多。", "Lands not yet found are not counted: the further you walk, the more nations you know."))
                .font(.system(size: 10, design: .rounded)).opacity(0.6)
        }
    }

    private var controls: some View {
        // one row that scrolls sideways when the screen is narrow (nothing laid over anything)
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
            TextField(L("搜索国家", "Search nations"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 12, design: .rounded)).padding(.horizontal, 10).frame(height: 32)
                .background(Color.white.opacity(0.12), in: Capsule()).frame(maxWidth: 180).accessibilityIdentifier("civ-search")
            ForEach(CivSort.allCases, id: \.self) { s in
                Chip(title: label(s), icon: sort == s ? "checkmark" : "arrow.up.arrow.down", tint: sort == s ? Color.white.opacity(0.3) : Color.white.opacity(0.12), id: "civ-sort-\(s.rawValue)") { sort = s }
            }
            Chip(title: showGone ? L("隐藏已亡", "Hide fallen") : L("显示已亡", "Show fallen"), icon: "clock.arrow.circlepath", id: "civ-gone") { showGone.toggle() }
            Chip(title: nearOnly ? L("全部已发现", "All found") : L("只看附近", "Nearby"), icon: "location.fill", id: "civ-near") { nearOnly.toggle() }
        } }
    }

    /// A nation's overall strength in one number: people, soldiers, knowledge and cities.
    static func composite(_ p: CivPolity) -> Int { p.pop + p.detailPop + p.soldiers * 3 + p.techs.count * 25 + p.cityCount * 40 }

    private func label(_ s: CivSort) -> String {
        switch s {
        case .people: return L("人口", "People")
        case .power: return L("军力", "Power")
        case .food: return L("粮食", "Food")
        case .tech: return L("科技", "Tech")
        case .name: return L("名称", "Name")
        }
    }

    private func rows(_ c: Civ) -> [CivPolity] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = c.polities.values.filter { showGone || $0.status != .history }
        if nearOnly, let t = model.society.explorer {
            // nations with a city within three regions of where you are (and the towns about you)
            let (rx, ry) = Civ.regionOf(tile: t, size: c.cfg.regionTiles)
            let near = Set(c.cities.values.filter { abs($0.rx - rx) <= 3 && abs($0.ry - ry) <= 3 }.map { $0.nation })
            list = list.filter { near.contains($0.id) }
        }
        if !q.isEmpty { list = list.filter { $0.nameEn.lowercased().contains(q) || $0.nameZh.contains(q) || $0.short.lowercased().contains(q) } }
        func pop(_ p: CivPolity) -> Int { p.pop + p.detailPop }
        list.sort { a, b in
            let fa = favourites.contains(a.id), fb = favourites.contains(b.id)
            if fa != fb { return fa }
            switch sort {
            case .people: return pop(a) != pop(b) ? pop(a) > pop(b) : a.id < b.id
            case .power: return a.power != b.power ? a.power > b.power : a.id < b.id
            case .food: return a.foodDays != b.foodDays ? a.foodDays < b.foodDays : a.id < b.id
            case .tech: return a.techs.count != b.techs.count ? a.techs.count > b.techs.count : a.id < b.id
            case .name: return a.name(zh: GameModel.zh) < b.name(zh: GameModel.zh)
            }
        }
        return list
    }

    private func row(_ p: CivPolity, _ c: Civ) -> some View {
        let fav = favourites.contains(p.id)
        return HStack(spacing: 8) {
            CivEmblem(polity: p, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(p.name(zh: GameModel.zh)).font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(statusText(p)).font(.system(size: 9, weight: .semibold, design: .rounded)).padding(.horizontal, 5).padding(.vertical, 1).background(Color.white.opacity(0.18), in: Capsule())
                    if model.civCommand == p.id { Text(L("执政中", "in your hands")).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.yellow) }
                }
                HStack(spacing: 6) {
                    Text(L("综合国力", "Strength")).font(.system(size: 10, design: .rounded)).opacity(0.7)
                    Text("\(CivWorldSection.composite(p))").font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                    let allies = c.relations.values.filter { $0.pact && ($0.a == p.id || $0.b == p.id) }.compactMap { c.polities[$0.a == p.id ? $0.b : $0.a] }
                    ForEach(allies.prefix(3), id: \.id) { a in
                        Text(L("盟友 ", "Ally ") + a.name(zh: GameModel.zh)).font(.system(size: 9, weight: .bold, design: .rounded)).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Color(hex: a.color).opacity(0.35), in: Capsule())
                    }
                }
                Text(L("人口 \(p.pop + p.detailPop) · 城市 \(p.cityCount) · 存粮 \(days(p.foodDays)) · 科技 \(p.techs.count) · 兵员 \(p.soldiers) · 交战 \(c.wars(of: p.id).count)",
                       "people \(p.pop + p.detailPop) · cities \(p.cityCount) · food \(days(p.foodDays)) · tech \(p.techs.count) · under arms \(p.soldiers) · wars \(c.wars(of: p.id).count)"))
                    .font(.system(size: 10, design: .rounded)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button { toggleFavourite(p.id) } label: { Image(systemName: fav ? "star.fill" : "star").foregroundStyle(fav ? .yellow : .white).frame(width: 32, height: 32) }
                .buttonStyle(PressStyle()).accessibilityIdentifier("civ-fav-\(p.id)")
            Button { model.civDetail = p.id } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                .buttonStyle(PressStyle()).accessibilityIdentifier("civ-open-\(p.id)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(hex: p.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain).accessibilityIdentifier("civ-row")
    }

    private func toggleFavourite(_ id: Int) {
        if favourites.contains(id) { favourites.remove(id) } else { favourites.insert(id) }
        UserDefaults.standard.set(Array(favourites).sorted(), forKey: "civFavourites")
    }
}

func statusText(_ p: CivPolity) -> String {
    switch p.status {
    case .active: return L("在位", "standing")
    case .exile: return L("流亡", "in exile")
    case .history: return p.mergedInto != nil ? L("已并入", "merged") : L("历史", "history")
    }
}

func days(_ d: Double) -> String { d >= 99 ? "99+" + L("天", "d") : String(format: "%.0f", d) + L("天", "d") }

/// A nation's mark: its colour, a shape of its own and its short name, so that nations with close colours are still told apart.
struct CivEmblem: View {
    let polity: CivPolity
    let size: CGFloat
    static let shapes = ["shield.fill", "circle.fill", "diamond.fill", "flag.fill", "star.fill", "building.columns.fill", "water.waves", "moon.fill"]
    var body: some View {
        ZStack {
            Image(systemName: CivEmblem.shapes[polity.shape % CivEmblem.shapes.count]).font(.system(size: size * 0.9)).foregroundStyle(Color(hex: polity.color))
            Text(polity.short).font(.system(size: size * 0.32, weight: .heavy, design: .rounded)).foregroundStyle(.white).shadow(radius: 1)
        }
        .frame(width: size, height: size)
    }
}

/// One nation in full. Every figure says where it comes from.
struct CivNationSheet: View {
    @EnvironmentObject var model: GameModel
    let id: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let c = model.society.civ
            if let p = c.polities[id] {
                GlassSheet(title: p.name(zh: GameModel.zh), subtitle: statusText(p) + " · " + L("建国于第 \(Int(p.founded / MP.daySeconds)) 天（\(origin(p.origin))）", "founded day \(Int(p.founded / MP.daySeconds)) (\(origin(p.origin)))"), close: { model.civDetail = nil }) {
                    VStack(alignment: .leading, spacing: 10) {
                        head(p, c)
                        CivPeopleCard(c: c, nation: id)
                        CivFoodCard(c: c, nation: id)
                        research(p)
                        CivArmsCard(c: c, nation: id, commanding: model.civCommand == id)
                        TowerList(c: c, nation: id)
                        neighbours(p, c)
                        news(p, c)
                    }
                }
            }
        }
    }

    private func origin(_ o: String) -> String {
        switch o {
        case "city_state": return L("独立城邦", "a city-state")
        case "rebellion": return L("地方起义", "a rising")
        case "player": return L("玩家建国", "founded by you")
        case "restart": return L("新移民", "new settlers")
        case "colony": return L("殖民地独立", "a colony gone free")
        case "refugees": return L("难民定居", "refugees who settled")
        default: return L("初始国家", "one of the first")
        }
    }

    private func head(_ p: CivPolity, _ c: Civ) -> some View {
        HStack(spacing: 10) {
            CivEmblem(polity: p, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("国库 \(Int(p.treasury)) · 厌战 \(Int(p.fatigue * 100))% · 首都 \(p.capital.flatMap { c.cities[$0]?.name(zh: GameModel.zh) } ?? "—") · 偏好 \(p.leaning)",
                       "treasury \(Int(p.treasury)) · war-weariness \(Int(p.fatigue * 100))% · capital \(p.capital.flatMap { c.cities[$0]?.name(zh: GameModel.zh) } ?? "—") · leaning \(p.leaning)"))
                    .font(.system(size: 11, design: .rounded))
                if p.status == .active && !p.detailed {
                    Chip(title: model.civCommand == p.id ? L("交还电脑", "Hand back") : L("执政此国", "Take charge"), icon: model.civCommand == p.id ? "hand.raised.slash" : "crown.fill", id: "civ-command") {
                        model.takeCharge(model.civCommand == p.id ? nil : p.id)
                    }
                }
            }
        }
    }

    private func research(_ p: CivPolity) -> some View {
        let t = p.studying.flatMap { CivTech.byKey[$0] }
        let done = p.studying.map { Int(p.progress[$0] ?? 0) } ?? 0
        let era = p.techs.compactMap { CivTech.byKey[$0]?.era }.max() ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("科研", "Research")).font(.system(size: 13, weight: .bold, design: .rounded))
            Text(L("时代：\(CivTech.eraNames[era].1) · 已掌握 \(p.techs.count) 项 · 今日 \(String(format: "%.1f", p.researchToday)) 点",
                   "age: \(CivTech.eraNames[era].0) · \(p.techs.count) known · \(String(format: "%.1f", p.researchToday)) points today")).font(.system(size: 11, design: .rounded))
            if let t = t {
                Text(L("正在研究 \(t.zh)（\(done)/\(Int(t.cost))）", "studying \(t.en) (\(done)/\(Int(t.cost)))")).font(.system(size: 11, design: .rounded)).opacity(0.85)
            } else {
                Text(L("暂无可研究项目：需要学校、研究院或实验室", "nothing open to study: it needs a school, an institute or a laboratory")).font(.system(size: 11, design: .rounded)).opacity(0.7)
            }
        }
    }

    private func neighbours(_ p: CivPolity, _ c: Civ) -> some View {
        let rels = c.relations.values.filter { $0.a == p.id || $0.b == p.id }.sorted { $0.a + $0.b < $1.a + $1.b }
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("外交（只列出相邻、贸易、交战或有旧怨的国家）", "Neighbours (only those it borders, trades with, fights or has a quarrel with)")).font(.system(size: 13, weight: .bold, design: .rounded))
            if rels.isEmpty { Text(L("尚无往来", "no contacts yet")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
            ForEach(rels, id: \.a) { r in
                let other = r.a == p.id ? r.b : r.a
                let name = c.polities[other]?.name(zh: GameModel.zh) ?? "#\(other)"
                let state = [L("和平", "peace"), L("交战", "war"), L("停战", "truce")][r.state]
                Text("\(name) · \(state) · " + L("好感 \(Int(r.value * 100))", "regard \(Int(r.value * 100))") + (r.pact ? L(" · 同盟", " · allied") : "") + (r.claim ? L(" · 领土争议", " · land claim") : ""))
                    .font(.system(size: 11, design: .rounded))
            }
        }
    }

    private func news(_ p: CivPolity, _ c: Civ) -> some View {
        let mine = c.news.filter { $0.nations.contains(p.id) }.suffix(6)
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("近事", "Lately")).font(.system(size: 13, weight: .bold, design: .rounded))
            ForEach(Array(mine.enumerated()), id: \.offset) { _, n in
                Text(L("第\(Int(n.t / MP.daySeconds))天 ", "day \(Int(n.t / MP.daySeconds)) ") + CivText.line(n)).font(.system(size: 10, design: .rounded)).opacity(0.85)
            }
        }
    }
}

/// People: how many, how old, how hungry, and what changed yesterday (born, died by cause, came, left).
struct CivPeopleCard: View {
    let c: Civ
    let nation: Int
    var body: some View {
        let cities = c.cities(of: nation).filter { $0.detail == nil }
        var p = CivPeople()
        var y = CivLedger()
        for city in cities {
            p.add(city.people)
            y.births += city.yesterday.births; y.migIn += city.yesterday.migIn; y.migOut += city.yesterday.migOut
            y.enlisted += city.yesterday.enlisted; y.discharged += city.yesterday.discharged; y.newly += city.yesterday.newly
            for (k, v) in city.yesterday.deaths { y.deaths[k, default: 0] += v }
        }
        let causes = y.deaths.keys.sorted().map { "\(cause($0)) \(y.deaths[$0]!)" }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(L("人口", "People")).font(.system(size: 13, weight: .bold, design: .rounded))
            Text(L("儿童 \(p.band(0)) · 成年 \(p.band(1)) · 老人 \(p.band(2))", "children \(p.band(0)) · adults \(p.band(1)) · elders \(p.band(2))")).font(.system(size: 11, design: .rounded))
            Text((0..<6).map { (GameModel.zh ? CivHunger.names[$0].1 : CivHunger.names[$0].0) + " \(p.state($0))" }.joined(separator: " · ")).font(.system(size: 10, design: .rounded)).opacity(0.85)
            Text(L("昨日：出生 \(y.births) · 死亡 \(y.deathTotal)（\(causes)） · 迁入 \(y.migIn) · 迁出 \(y.migOut) · 入伍 \(y.enlisted) · 退伍 \(y.discharged) · 新纳入统计 \(y.newly)",
                   "yesterday: born \(y.births) · died \(y.deathTotal) (\(causes)) · came \(y.migIn) · left \(y.migOut) · enlisted \(y.enlisted) · discharged \(y.discharged) · newly counted \(y.newly)"))
                .font(.system(size: 10, design: .rounded)).opacity(0.85).accessibilityIdentifier("civ-ledger")
        }
    }
    private func cause(_ k: String) -> String {
        switch k {
        case "old": return L("老死", "age")
        case "illness": return L("病", "illness")
        case "hunger": return L("饥饿", "hunger")
        case "battle": return L("战死", "battle")
        case "journey": return L("途中", "journey")
        case "accident": return L("事故", "accident")
        default: return k
        }
    }
}

/// Food: in store, on the road, made and eaten yesterday, how many days it lasts and why it is short.
struct CivFoodCard: View {
    @EnvironmentObject var model: GameModel
    let c: Civ
    let nation: Int
    var body: some View {
        let cities = c.cities(of: nation).filter { $0.detail == nil }
        let onRoad = c.trips.values.filter { t in cities.contains { $0.id == t.to } }.reduce(0.0) { acc, t in acc + t.cargo.reduce(0.0) { $0 + $1.value * (CivFood.byKey[$1.key]?.nutrition ?? 0) } }
        return VStack(alignment: .leading, spacing: 3) {
            Text(L("粮食（按当前人口估算，非保证）", "Food (estimated at today's numbers; not a promise)")).font(.system(size: 13, weight: .bold, design: .rounded))
            ForEach(cities, id: \.id) { city in cityLine(city) }
            if onRoad > 0 { Text(L("在途粮食 \(Int(onRoad)) 份", "on the road: \(Int(onRoad)) days' rations")).font(.system(size: 10, design: .rounded)).opacity(0.8) }
        }
    }

    private func cityLine(_ city: CivCity) -> some View {
        let made = city.yesterday.made.keys.filter { CivFood.isFood($0) }.reduce(0.0) { $0 + city.yesterday.made[$1]! * (CivFood.byKey[$1]?.nutrition ?? 0) }
        let eaten = city.yesterday.eaten.keys.reduce(0.0) { $0 + city.yesterday.eaten[$1]! * (CivFood.byKey[$1]?.nutrition ?? 0) }
        let warn = city.foodDays < 5 ? Color.red : (city.foodDays < 15 ? Color.orange : Color.white)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(city.name(zh: GameModel.zh)).font(.system(size: 11, weight: .semibold, design: .rounded))
                Text(L("人口 \(city.pop) · 可供 \(days(city.foodDays)) · 产 \(Int(made)) / 耗 \(Int(eaten)) · \(rationName(city.ration))",
                       "\(city.pop) people · lasts \(days(city.foodDays)) · made \(Int(made)) / eaten \(Int(eaten)) · \(rationName(city.ration))"))
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(warn)
            }
            if !reasons(city).isEmpty { Text(L("短缺原因：", "short because: ") + reasons(city)).font(.system(size: 9, design: .rounded)).foregroundStyle(.orange) }
            if model.civCommand == nation { CivCityControls(c: c, city: city) }
        }
    }

    private func rationName(_ r: CivRation) -> String { GameModel.zh ? r.label.1 : r.label.0 }

    private func reasons(_ city: CivCity) -> String {
        var out: [String] = []
        if city.besieged { out.append(L("被围，外粮进不来、城外田地难收", "besieged: nothing gets in, the fields outside cannot be worked")) }
        if city.has("farm") == 0 { out.append(L("没有农田", "no fields")) }
        if city.thirst > 0.1 { out.append(L("缺水", "short of water")) }
        if city.crowding > 1.1 { out.append(L("过度拥挤", "overcrowded")) }
        if city.people.hungerIndex > 0.3 { out.append(L("饥饿降低了劳作", "hunger slows the work")) }
        return city.foodDays < 15 ? out.joined(separator: "，") : ""
    }
}

/// What a nation in the player's hands can do in a city: rations, building and ordering machines.
struct CivCityControls: View {
    @EnvironmentObject var model: GameModel
    let c: Civ
    let city: CivCity
    var body: some View {
        let nation = city.nation
        let p = c.polities[nation]
        let facilities = CivFacility.all.filter { f in f.tech == nil || (p?.knows(f.tech!) ?? false) }
        let machines = CivUnitDef.all.filter { d in d.tech.allSatisfy { p?.knows($0) ?? false } && city.has(d.facility) > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(CivRation.allCases, id: \.self) { r in
                    Chip(title: GameModel.zh ? r.label.1 : r.label.0, icon: city.ration == r ? "checkmark" : (city.rationNext == r ? "clock" : "fork.knife"), tint: city.ration == r ? Color.white.opacity(0.3) : Color.white.opacity(0.1), id: "ration-\(city.id)-\(r.rawValue)") {
                        model.civDo(nation, .ration(city: city.id, policy: r))
                    }
                }
            }
            Menu {
                ForEach(facilities, id: \.key) { f in
                    Button((GameModel.zh ? f.zh : f.en) + " · " + f.cost.keys.sorted().map { "\(CivItem.name($0, zh: GameModel.zh)) \(Int(f.cost[$0]!))" }.joined(separator: " ")) {
                        model.civDo(nation, .build(city: city.id, facility: f.key))
                    }
                }
            } label: { Label(L("建造设施（在建 \(city.builds.count)）", "Build (\(city.builds.count) going up)"), systemImage: "hammer.fill").font(.system(size: 11, weight: .medium, design: .rounded)).padding(.horizontal, 10).frame(height: 32).background(Color.white.opacity(0.14), in: Capsule()) }
                .accessibilityIdentifier("civ-build-\(city.id)")
            if !machines.isEmpty {
                Menu {
                    ForEach(machines, id: \.key) { d in
                        Button((GameModel.zh ? d.zh : d.en) + L("（\(d.stages.count) 段，乘员 \(d.crew)）", " (\(d.stages.count) stages, crew \(d.crew))")) {
                            model.civDo(nation, .order(city: city.id, kind: d.key))
                        }
                    }
                } label: { Label(L("订造装备", "Order machines"), systemImage: "gearshape.2.fill").font(.system(size: 11, weight: .medium, design: .rounded)).padding(.horizontal, 10).frame(height: 32).background(Color.white.opacity(0.14), in: Capsule()) }
                    .accessibilityIdentifier("civ-order-\(city.id)")
            }
            Text(city.stock.keys.filter { !CivFood.isFood($0) && city.stock[$0]! >= 1 }.sorted().map { "\(CivItem.name($0, zh: GameModel.zh)) \(Int(city.stock[$0]!))" }.joined(separator: " · "))
                .font(.system(size: 9, design: .rounded)).opacity(0.7)
        }
        .padding(.leading, 8)
    }
}

/// Arms: what is being built (and what it waits for), what waits in depots, and every force in the field
/// with its people, food, fuel, ammunition, power and damaged parts.
struct CivArmsCard: View {
    @EnvironmentObject var model: GameModel
    let c: Civ
    let nation: Int
    let commanding: Bool
    var body: some View {
        let projects = c.projects.values.filter { $0.nation == nation }.sorted { $0.id < $1.id }
        let depot = c.units.values.filter { $0.nation == nation && $0.depot != nil }.sorted { $0.id < $1.id }
        let forces = c.forces.values.filter { $0.nation == nation }.sorted { $0.id < $1.id }
        return VStack(alignment: .leading, spacing: 3) {
            Text(L("军工与部队", "Industry and forces")).font(.system(size: 13, weight: .bold, design: .rounded))
            ForEach(projects, id: \.id) { p in
                let d = CivUnitDef.byKey[p.kind]
                HStack(spacing: 6) {
                    Text(L("建造 \(d?.zh ?? p.kind)：第 \(p.stage + 1)/\(d?.stages.count ?? 1) 段 \(Int(p.hours))/\(Int(d?.hours ?? 0)) 小时", "building \(d?.en ?? p.kind): stage \(p.stage + 1)/\(d?.stages.count ?? 1), \(Int(p.hours))/\(Int(d?.hours ?? 0)) h") + (p.waiting.isEmpty ? "" : L(" · 等待：", " · waiting for ") + waiting(p.waiting)))
                        .font(.system(size: 10, design: .rounded))
                    if commanding { Chip(title: L("取消（返还 50%）", "Cancel (50% back)"), icon: "xmark", id: "civ-cancel-\(p.id)") { model.civDo(nation, .cancel(project: p.id)) } }
                }
            }
            ForEach(depot, id: \.id) { u in
                HStack(spacing: 6) {
                    Text(L("库存：\(u.def.zh)（未配乘员、未加注）", "in depot: \(u.def.en) (no crew, empty tanks)")).font(.system(size: 10, design: .rounded))
                    if commanding { Chip(title: L("配员出库", "Crew and deploy"), icon: "person.3.fill", id: "civ-deploy-\(u.id)") { model.civDo(nation, .deploy(unit: u.id, force: nil)) } }
                }
            }
            ForEach(forces, id: \.id) { f in forceLine(f) }
            if projects.isEmpty && depot.isEmpty && forces.isEmpty { Text(L("没有军队", "no forces")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
        }
    }

    private func waiting(_ w: String) -> String {
        switch w {
        case "materials": return L("材料", "materials")
        case "energy": return L("电力", "power")
        case "facility": return L("厂房", "a works")
        default: return w
        }
    }

    private func forceLine(_ f: CivForce) -> some View {
        let ms = f.units.compactMap { c.units[$0] }
        let kinds = Dictionary(grouping: ms, by: { $0.kind }).keys.sorted().map { k in "\(GameModel.zh ? CivUnitDef.byKey[k]!.zh : CivUnitDef.byKey[k]!.en)×\(ms.filter { $0.kind == k }.count)" }.joined(separator: " ")
        let food = f.food.keys.sorted().reduce(0.0) { $0 + f.food[$1]! * (CivFood.byKey[$1]?.nutrition ?? 0) }
        let broken = ms.flatMap { u in u.parts.keys.sorted().filter { u.parts[$0]! <= 0 }.map { "\(u.kind):\($0)" } }
        let airborne = ms.filter { $0.air == .airborne || $0.air == .returning }.count
        let targets = c.cities.values.filter { t in t.detail == nil && (c.atWar(t.nation, f.nation) || t.nation == f.nation) }.sorted { $0.id < $1.id }
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(kinds) · " + L("层：\(f.layer.label.1) · 区域 \(MP.keyCX(f.region)),\(MP.keyCY(f.region)) · 人员 \(f.crew.total)（饥饿 \(Int(f.crew.hungerIndex * 100))%） · 口粮 \(Int(food)) · 士气 \(Int(f.morale * 100))%",
                                   "layer \(f.layer.label.0) · region \(MP.keyCX(f.region)),\(MP.keyCY(f.region)) · \(f.crew.total) people (hunger \(Int(f.crew.hungerIndex * 100))%) · food \(Int(food)) · morale \(Int(f.morale * 100))%"))
                .font(.system(size: 10, design: .rounded))
            Text(L("燃料 \(Int(ms.reduce(0) { $0 + $1.fuel })) · 弹药 \(Int(ms.reduce(0) { $0 + $1.ammo })) · 能量 \(Int(ms.reduce(0) { $0 + $1.energy })) · 在空 \(airborne)", "fuel \(Int(ms.reduce(0) { $0 + $1.fuel })) · ammo \(Int(ms.reduce(0) { $0 + $1.ammo })) · energy \(Int(ms.reduce(0) { $0 + $1.energy })) · airborne \(airborne)")
                 + (broken.isEmpty ? "" : L(" · 损坏：", " · knocked out: ") + broken.joined(separator: ", ")))
                .font(.system(size: 9, design: .rounded)).opacity(0.8)
            if commanding {
                Menu {
                    ForEach(targets, id: \.id) { t in
                        Button((t.nation == f.nation ? L("前往 ", "Go to ") : L("进攻 ", "Attack ")) + t.name(zh: GameModel.zh)) {
                            model.civDo(nation, .send(force: f.id, region: t.regionKey, attack: t.nation != f.nation))
                        }
                    }
                } label: { Label(L("调动", "Send"), systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(.system(size: 11, weight: .medium, design: .rounded)).padding(.horizontal, 10).frame(height: 30).background(Color.white.opacity(0.14), in: Capsule()) }
                    .accessibilityIdentifier("civ-send-\(f.id)")
            }
        }
    }
}

/// News of the civilisation layer in words.
enum CivText {
    static let lines: [String: (String, String)] = [
        "city_state": ("%@ stands as a city-state at %@", "%@ 以城邦之姿立于 %@"),
        "city_founded": ("%@ was founded for %@", "%@ 建城，归属 %@"),
        "war": ("%@ declared war on %@", "%@ 向 %@ 宣战"), "truce": ("%@ and %@ agreed a truce", "%@ 与 %@ 休战"),
        "captured": ("%@ took %@ from %@", "%@ 夺取了 %@（原属 %@）"),
        "exile": ("%@ has lost its last city and lives on in exile", "%@ 失去最后一座城，流亡中"),
        "history": ("%@ has passed into history", "%@ 成为历史"),
        "restored": ("%@ rose again at %@", "%@ 在 %@ 复国"), "seceded": ("%@ broke away from %@", "%@ 脱离 %@ 独立"),
        "federated": ("%@ joined %@ in one federation", "%@ 与 %@ 合为一邦"), "submitted": ("%@ submitted to %@", "%@ 归附 %@"),
        "pact": ("%@ and %@ stand together", "%@ 与 %@ 结盟"), "tech": ("%@ learned %@", "%@ 掌握了 %@"),
        "built_unit": ("A %@ was completed at %@", "%@ 在 %@ 建成"), "convoy_lost": ("A convoy from %@ was lost", "来自 %@ 的车队失踪"),
        "refugees_left": ("%@ people fled %@ for %@", "%@ 人逃离 %@，前往 %@"), "migrants_left": ("%@ people left %@ for %@", "%@ 人离开 %@，迁往 %@"),
    ]
    /// News carries both languages side by side (en, zh, en, zh ...); pick one of each pair.
    static func line(_ n: CivNews) -> String {
        guard let t = lines[n.key] else { return n.key }
        let zh = GameModel.zh
        var args: [String] = []
        var i = 0
        while i < n.args.count {
            if let _ = Int(n.args[i]) { args.append(n.args[i]); i += 1; continue }
            args.append(zh && i + 1 < n.args.count ? n.args[i + 1] : n.args[i]); i += 2
        }
        var out = zh ? t.1 : t.0
        for a in args { if let r = out.range(of: "%@") { out.replaceSubrange(r, with: a) } }
        return out
    }
}

extension GameModel {
    /// Govern a regional nation (or hand it back to the computer). Only one at a time.
    func takeCharge(_ id: Int?) {
        let c = society.civ
        if let old = civCommand { c.polities[old]?.ai = true }
        civCommand = id
        if let id = id { c.polities[id]?.ai = false; showToast(L("你执掌了 \(c.polities[id]?.name(zh: GameModel.zh) ?? "")：配给、建设、军工与调兵由你决定", "\(c.polities[id]?.name(zh: GameModel.zh) ?? "") is in your hands: rations, building, arms and orders are yours")) }
    }
}

extension GameModel {
    /// Everything the panel does to the world goes through a command: checked, then done or refused with a reason.
    @discardableResult func civDo(_ nation: Int, _ action: WorldCommand.Action) -> CommandResult {
        let r = society.civ.execute(WorldCommand(id: UUID().uuidString, issuer: nation, action))
        if !r.ok {
            let why: String
            switch r.reason {
            case "cannot_build": why = L("材料不足或条件不符", "Not enough materials, or the place is wrong for it")
            case "cannot_order": why = L("无法下单：缺少科技或厂房", "Cannot order that here: a technology or a works is missing")
            case "cannot_deploy": why = L("城里没有足够的成年人，或没有机库与机场", "Not enough adults in the city, or no deck or airfield")
            case "no_way": why = L("此部队无法到达（地形、水深或通道宽度不允许）", "This force cannot get there (terrain, water depth or a pass too narrow)")
            case "stale": why = L("情况已经变化，请重新查看", "Things have changed; look again")
            case "not_yours": why = L("这不归你指挥", "That is not yours to command")
            default: why = L("无法执行", "That cannot be done")
            }
            showToast(why)
        }
        return r
    }
}
