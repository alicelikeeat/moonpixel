import SwiftUI
import MoonPixelCore

struct MenuView: View {
    @EnvironmentObject var model: GameModel
    @State private var seedText = String(Int.random(in: 1..<100000))
    @State private var budgetChoice = 0
    private let budgets = [0, 128, 256, 512, 1024, 2048]

    var body: some View {
        let mem = MemoryBudget.deviceMemory()
        let auto = MemoryBudget()
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.24), Color(red: 0.10, green: 0.20, blue: 0.36), Color(red: 0.20, green: 0.16, blue: 0.38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Circle().fill(Color(red: 0.25, green: 0.8, blue: 0.7).opacity(0.45)).frame(width: 280).blur(radius: 60).offset(x: 260, y: -90)
            Circle().fill(Color(red: 0.3, green: 0.55, blue: 0.95).opacity(0.55)).frame(width: 320).blur(radius: 70).offset(x: -280, y: 100)
            Circle().fill(Color(red: 0.96, green: 0.92, blue: 0.70)).frame(width: 46).offset(x: -330, y: -130)
            VStack(spacing: 12) {
                Text("MoonPixel").font(.system(size: 36, weight: .bold, design: .rounded))
                Text(L("世界由游戏生成，未来由居民和你决定。", "A self-growing world of autonomous villagers."))
                    .font(.system(size: 14, design: .rounded)).opacity(0.9)
                Text(String(format: L("设备内存 %d MB（可用 %d MB）· 自动预算 %d MB", "Device memory %d MB (free %d MB) · auto budget %d MB"), mem.physicalMB, mem.availableMB, auto.budgetMB))
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Color(red: 0.75, green: 0.92, blue: 1))
                HStack(spacing: 10) {
                    Text(L("内存预算", "Memory budget")).font(.system(size: 13, design: .rounded))
                    Picker("", selection: $budgetChoice) {
                        ForEach(budgets, id: \.self) { b in Text(b == 0 ? L("自动", "Auto") : "\(b) MB").tag(b) }
                    }
                    .pickerStyle(.menu).tint(.white)
                    Text(L("种子", "Seed")).font(.system(size: 13, design: .rounded))
                    TextField("", text: $seedText).keyboardType(.numberPad).frame(width: 90)
                        .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.14), in: Capsule())
                }
                HStack(spacing: 12) {
                    if model.hasSave {
                        Button { model.start(seed: 0, overrideMB: budgetChoice, load: true) } label: {
                            Label(L("继续", "Continue"), systemImage: "play.fill").font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(width: 170, height: 48)
                        }
                        .buttonStyle(.plain).glass(Capsule())
                    }
                    Button { model.start(seed: Int(seedText) ?? abs(seedText.hashValue % 100000), overrideMB: budgetChoice, load: false) } label: {
                        Label(L("新世界", "New world"), systemImage: "sparkles").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: 170, height: 48)
                    }
                    .buttonStyle(.plain).glass(Capsule())
                }
                if model.hasSave {
                    Text(L("新世界会覆盖现有存档", "A new world replaces the current save")).font(.system(size: 10, design: .rounded)).opacity(0.55)
                }
            }
            .padding(.horizontal, 30).padding(.vertical, 22)
            .glass(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .foregroundStyle(.white)
    }
}
