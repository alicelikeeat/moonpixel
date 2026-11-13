import SwiftUI
import MoonPixelCore

/// Start screen, laid out like a calm chat app: your worlds on the left,
/// and one composer on the right. Describe a world in a sentence, the app
/// analyses it on the device and builds it.
struct MenuView: View {
    @EnvironmentObject var model: GameModel
    @State private var prompt = ""
    @State private var randomSeed = Int.random(in: 1..<100000)
    @State private var budgetChoice = 0
    @State private var deleting: WorldMeta?
    @FocusState private var typing: Bool
    private let budgets = [0, 128, 256, 512, 1024, 2048]
    private let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let ink = Color(red: 0.96, green: 0.95, blue: 0.92)

    private var suggestions: [String] {
        GameModel.zh ? ["冰雪海岛，200 人，工业时代", "沙漠里的三个部落", "森林王国，中世纪，8 个村庄", "未来的 AI 城市，300 人"]
                     : ["Snowy islands, 200 people, industrial age", "Three tribes in the desert", "Medieval forest kingdom, 8 villages", "A future AI city with 300 people"]
    }

    private var recipe: WorldRecipe {
        WorldRecipe.parse(prompt, defaultSeed: prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? randomSeed : nil)
    }

    var body: some View {
        let mem = MemoryBudget.deviceMemory()
        let auto = MemoryBudget()
        let r = recipe
        ZStack {
            Color(red: 0.13, green: 0.13, blue: 0.12).ignoresSafeArea()
            Circle().fill(accent.opacity(0.30)).frame(width: 340).blur(radius: 90).offset(x: 250, y: -150)
            Circle().fill(Color(red: 0.35, green: 0.45, blue: 0.75).opacity(0.25)).frame(width: 320).blur(radius: 90).offset(x: -300, y: 150)
            HStack(alignment: .top, spacing: 12) {
                sidebar
                // --- composer
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill").font(.system(size: 20)).foregroundStyle(accent)
                        Text(L("想创造一个怎样的世界？", "What world shall we make?"))
                            .font(.system(size: 23, weight: .regular, design: .serif))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L("用一句话描述，例如“冰雪海岛，200 人，工业时代”", "Describe it in a sentence, e.g. \"snowy islands, 200 people, industrial age\""), text: $prompt)
                            .font(.system(size: 15, design: .rounded)).autocorrectionDisabled().submitLabel(.go).focused($typing)
                            .onSubmit { create() }
                            .accessibilityIdentifier("world-prompt")
                        HStack(spacing: 8) {
                            Menu {
                                Picker("", selection: $budgetChoice) {
                                    ForEach(budgets, id: \.self) { b in Text(b == 0 ? L("内存：自动", "Memory: auto") : "\(b) MB").tag(b) }
                                }
                            } label: {
                                Label(budgetChoice == 0 ? L("内存 自动", "Memory auto") : "\(budgetChoice) MB", systemImage: "memorychip")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 10).frame(height: 30).background(Color.white.opacity(0.10), in: Capsule())
                            }
                            Button { randomSeed = Int.random(in: 1..<100000); prompt = "" } label: {
                                Label(L("随机", "Surprise me"), systemImage: "dice").font(.system(size: 11, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 10).frame(height: 30).background(Color.white.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(PressStyle())
                            Spacer(minLength: 0)
                            Button { create() } label: {
                                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 40, height: 40).background(accent, in: Circle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("create-world")
                            .accessibilityLabel(L("创建世界", "Create world"))
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
                    .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    // --- what the analysis understood, live
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("分析结果", "Analysis") + " · " + r.suggestedName(zh: GameModel.zh, index: model.worlds.count + 1))
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).opacity(0.6)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(r.summary(zh: GameModel.zh), id: \.self) { t in
                                    Text(t).font(.system(size: 12, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(accent.opacity(0.22), in: Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("analysis")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                                Button { prompt = s; typing = false } label: {
                                    Text(s).font(.system(size: 12, design: .rounded)).lineLimit(1)
                                        .padding(.horizontal, 12).frame(height: 34)
                                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityIdentifier("suggestion-\(i)")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(String(format: L("MoonPixel v%@ (%@) · 设备 %d MB · 可用 %d MB · 自动预算 %d MB · 每个世界地图上限 5 GB · 分析在本机完成",
                                          "MoonPixel v%@ (%@) · device %d MB · free %d MB · auto budget %d MB · 5 GB map cap per world · analysed on device"),
                                (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0",
                                (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1", mem.physicalMB, mem.availableMB, auto.budgetMB))
                        .font(.system(size: 9, design: .rounded)).opacity(0.5).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 6).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .foregroundStyle(ink)
        .onAppear { model.refreshWorlds() }
        .alert(L("删除这个世界？", "Delete this world?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("删除", "Delete"), role: .destructive) { if let w = deleting { model.deleteWorld(w.id) }; deleting = nil }
            Button(L("取消", "Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(String(format: L("“%@”的所有村民和建筑都会永久消失。", "Everything in \"%@\" will be gone for good."), deleting?.name ?? ""))
        }
    }

    private func create() {
        typing = false
        model.createWorld(recipe, overrideMB: budgetChoice)
        prompt = ""
        randomSeed = Int.random(in: 1..<100000)
    }

    /// Existing worlds, like a list of recent conversations.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("我的世界", "My worlds")).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text(GameModel.sizeText(model.worlds.reduce(0) { $0 + $1.diskBytes })).font(.system(size: 10, design: .rounded)).opacity(0.6)
            }
            if model.worlds.isEmpty {
                Text(L("还没有世界。\n在右边说一句话就能创建。", "No worlds yet.\nSay a sentence on the right to make one."))
                    .font(.system(size: 12, design: .rounded)).opacity(0.65).padding(.vertical, 14)
            }
            ScrollView {
                VStack(spacing: 6) { ForEach(model.worlds) { w in worldRow(w) } }
            }
        }
        .padding(14).frame(width: 290).frame(maxHeight: .infinity, alignment: .topLeading)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func worldRow(_ w: WorldMeta) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(w.name).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(String(format: L("第 %d 年 · %d 人 · %@%@", "Year %d · %d people · %@%@"), max(1, w.year), w.population, GameModel.sizeText(w.diskBytes),
                            w.tech.isEmpty ? "" : " · " + w.tech))
                    .font(.system(size: 10, design: .rounded)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 2)
            Button { model.openWorld(w, overrideMB: budgetChoice) } label: {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .semibold)).frame(width: 40, height: 40).background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("Play")
            Button { deleting = w } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .semibold)).frame(width: 36, height: 40).opacity(0.7)
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
