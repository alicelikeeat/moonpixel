import SwiftUI
import MoonPixelCore

/// The battle of the twin ports (the task book's final demonstration), played on its fixed seeds with the
/// player's choices: the envoy's answer (seed), where the sky carrier drops its frames, and what the giantess
/// does. It runs on a world of its own (your world is not touched) and shows the chronicle, the war report with
/// the reckoning behind it, both nations' cards and what the platform did to the road between the ports.
struct WarDemoView: View {
    @EnvironmentObject var model: GameModel
    @State private var answer = 1                  // 0 accepted, 1 refused (the port falls), 2 refused (the port holds)
    @State private var drop = TwinPorts.Drop.eastPort
    @State private var giant = TwinPorts.Giant.carryWest
    @State private var lines: [String] = []
    @State private var report: (head: String, details: [String])?
    @State private var facts: [String] = []

    var body: some View {
        GlassSheet(title: L("双港之战", "The twin ports"), subtitle: L("固定种子演示：劝降、拒降、航母、登陆、机甲投送、女巨人、十倍规则", "A fixed-seed demonstration: envoy, refusal, carrier, landing, frame drop, giantess, the tenfold rule"), close: { model.showWarDemo = false }) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $answer) {
                    Text(L("接受归附", "Accepted")).tag(0)
                    Text(L("拒降（种子 8）", "Refused (seed 8)")).tag(1)
                    Text(L("拒降（种子 1）", "Refused (seed 1)")).tag(2)
                }.pickerStyle(.segmented).accessibilityIdentifier("demo-answer")
                if answer != 0 {
                    Picker("", selection: $drop) {
                        Text(L("机甲投送东港", "Frames on the east port")).tag(TwinPorts.Drop.eastPort)
                        Text(L("机甲投送高台", "Frames on the platform")).tag(TwinPorts.Drop.platform)
                    }.pickerStyle(.segmented)
                    Picker("", selection: $giant) {
                        Text(L("女巨人转移居民", "Giantess carries people west")).tag(TwinPorts.Giant.carryWest)
                        Text(L("女巨人留守东港", "Giantess guards the east port")).tag(TwinPorts.Giant.guardEast)
                    }.pickerStyle(.segmented)
                }
                Chip(title: L("开始演示", "Play it"), icon: "play.fill", id: "demo-play") { play() }
                if let r = report {
                    Text(r.head).font(.system(size: 13, weight: .bold, design: .rounded))
                    ForEach(Array(r.details.enumerated()), id: \.offset) { _, d in Text(d).font(.system(size: 10, design: .rounded)).opacity(0.85) }
                }
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in Text(f).font(.system(size: 11, design: .rounded)) }
                if !lines.isEmpty { Text(L("事件记录", "Chronicle")).font(.system(size: 12, weight: .bold, design: .rounded)) }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in Text(l).font(.system(size: 10, design: .monospaced)).opacity(0.85) }
            }
        }
    }

    private func play() {
        let zh = GameModel.zh
        let seed = answer == 0 ? 2 : (answer == 1 ? 8 : 1)
        let t = TwinPorts(seed: seed)
        let refused = t.envoy()
        if refused {
            t.opening(giant: giant)
            t.skyDrop(drop)
            t.finish()
        } else {
            t.c.advance(to: t.c.time + 3 * MP.daySeconds)
        }
        report = t.c.targetWars.last.map { t.c.warLines($0, zh: zh) }
        facts = t.c.nationFacts(t.small, zh: zh) + t.c.nationFacts(t.great, zh: zh)
            + [t.c.landRoute(for: t.small, from: t.west.regionKey, to: t.east.regionKey) == nil
               ? L("双港之间的道路被切断（高台失守）", "The road between the ports is cut (the platform is held)")
               : L("双港之间的道路畅通", "The road between the ports is open")]
        lines = t.c.chronicleLines(zh: zh, last: 60).filter { !$0.contains("· tech ·") }
    }
}
