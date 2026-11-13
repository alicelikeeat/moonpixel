import SwiftUI
import MoonPixelCore

/// World list: several worlds live side by side, each with its own save.
struct MenuView: View {
    @EnvironmentObject var model: GameModel
    @State private var seedText = String(Int.random(in: 1..<100000))
    @State private var nameText = ""
    @State private var budgetChoice = 0
    @State private var deleting: WorldMeta?
    private let budgets = [0, 128, 256, 512, 1024, 2048]

    var body: some View {
        let mem = MemoryBudget.deviceMemory()
        let auto = MemoryBudget()
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.24), Color(red: 0.10, green: 0.20, blue: 0.36), Color(red: 0.20, green: 0.16, blue: 0.38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(Color(red: 0.25, green: 0.8, blue: 0.7).opacity(0.45)).frame(width: 280).blur(radius: 60).offset(x: 260, y: -90)
            Circle().fill(Color(red: 0.3, green: 0.55, blue: 0.95).opacity(0.55)).frame(width: 320).blur(radius: 70).offset(x: -280, y: 100)
            HStack(alignment: .top, spacing: 14) {
                // --- existing worlds
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("我的世界", "My worlds")).font(.system(size: 17, weight: .bold, design: .rounded))
                        Spacer()
                        Text(String(format: L("共 %@", "%@ in total"), GameModel.sizeText(model.worlds.reduce(0) { $0 + $1.diskBytes })))
                            .font(.system(size: 11, design: .rounded)).opacity(0.7)
                    }
                    if model.worlds.isEmpty {
                        Text(L("还没有世界，在右侧创建一个。", "No worlds yet. Create one on the right."))
                            .font(.system(size: 13, design: .rounded)).opacity(0.75).padding(.vertical, 20)
                    }
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(model.worlds) { w in worldRow(w) }
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glass(RoundedRectangle(cornerRadius: 30, style: .continuous))

                // --- new world
                VStack(spacing: 10) {
                    Text("MoonPixel").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0") + " (" + ((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1") + ")")
                        .font(.system(size: 10, weight: .medium, design: .rounded)).opacity(0.6)
                    Text(L("世界由游戏生成，未来由居民和你决定。", "A self-growing world of autonomous villagers."))
                        .font(.system(size: 12, design: .rounded)).opacity(0.9).multilineTextAlignment(.center)
                    field(L("名称", "Name"), text: $nameText, placeholder: L("世界", "World") + " \(model.worlds.count + 1)", numeric: false)
                    field(L("种子", "Seed"), text: $seedText, placeholder: "", numeric: true)
                    HStack(spacing: 8) {
                        Text(L("内存预算", "Memory")).font(.system(size: 13, design: .rounded))
                        Picker("", selection: $budgetChoice) {
                            ForEach(budgets, id: \.self) { b in Text(b == 0 ? L("自动", "Auto") : "\(b) MB").tag(b) }
                        }
                        .pickerStyle(.menu).tint(.white)
                    }
                    Text(String(format: L("设备 %d MB · 可用 %d MB · 自动预算 %d MB\n每个世界的地图存档上限 5 GB", "Device %d MB · free %d MB · auto budget %d MB\nEach world's map is capped at 5 GB"), mem.physicalMB, mem.availableMB, auto.budgetMB))
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(Color(red: 0.75, green: 0.92, blue: 1)).multilineTextAlignment(.center)
                    Button {
                        model.createWorld(name: nameText, seed: Int(seedText) ?? abs(seedText.hashValue % 100000), overrideMB: budgetChoice)
                        nameText = ""; seedText = String(Int.random(in: 1..<100000))
                    } label: {
                        Label(L("创建新世界", "Create world"), systemImage: "sparkles").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 200, height: 48).background(Color.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("create-world")
                }
                .padding(18).frame(width: 300).frame(maxHeight: .infinity)
                .glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .foregroundStyle(.white)
        .onAppear { model.refreshWorlds() }
        .alert(L("删除这个世界？", "Delete this world?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L("删除", "Delete"), role: .destructive) { if let w = deleting { model.deleteWorld(w.id) }; deleting = nil }
            Button(L("取消", "Cancel"), role: .cancel) { deleting = nil }
        } message: {
            Text(String(format: L("“%@”的所有村民和建筑都会永久消失。", "Everything in \"%@\" will be gone for good."), deleting?.name ?? ""))
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, numeric: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, design: .rounded)).frame(width: 44, alignment: .leading)
            TextField(placeholder, text: text).keyboardType(numeric ? .numberPad : .default).autocorrectionDisabled()
                .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.14), in: Capsule())
        }
    }

    private func worldRow(_ w: WorldMeta) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(w.name).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(String(format: L("第 %d 年 · %d 人 · %@%@", "Year %d · %d people · %@%@"), max(1, w.year), w.population, GameModel.sizeText(w.diskBytes),
                            w.tech.isEmpty ? "" : " · " + w.tech))
                    .font(.system(size: 11, design: .rounded)).opacity(0.8).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.openWorld(w, overrideMB: budgetChoice) } label: {
                Label(L("进入", "Play"), systemImage: "play.fill").font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14).frame(height: 40).background(Color.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(PressStyle())
            Button { deleting = w } label: {
                Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).frame(width: 40, height: 40).background(Color.red.opacity(0.35), in: Circle())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
