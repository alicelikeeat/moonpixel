import SwiftUI
import MoonPixelCore

/// 瞬移中心 / Teleport centre: every place the traveller knows, by kind, with a search; saved places and the
/// last places; and any tile on any layer by its coordinates. Works from anywhere (in a vehicle, on a saucer,
/// underground, upstairs or in the sky).
struct TeleportPanel: View {
    @EnvironmentObject var model: GameModel
    @State private var group: TeleportTarget.Group? = nil
    @State private var query = ""
    @State private var saveName = ""
    @State private var coordX = ""
    @State private var coordY = ""
    @State private var coordLayer = 0

    private static let layers: [(String, Int)] = [(L("地面", "Surface"), 0), (L("地下", "Underground"), 1), (L("天空", "Sky"), SkyTune.depth)]

    var body: some View {
        GlassSheet(title: L("瞬移中心", "Teleport centre"), subtitle: L("任何地方、任何一层，一点即达", "Anywhere, on any layer, in one tap"), close: { model.showTeleport = false }) {
            let s = model.society!
            let me = model.scene?.player.tile ?? TilePos(0, 0)
            let all = s.teleportTargets(from: me, zh: GameModel.zh)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // save where you stand
                    HStack(spacing: 6) {
                        TextField(L("给当前位置起个名字", "Name this place"), text: $saveName)
                            .textFieldStyle(.plain).font(.system(size: 12, design: .rounded)).padding(.horizontal, 10).frame(height: 32)
                            .background(Color.white.opacity(0.12), in: Capsule()).accessibilityIdentifier("tp-save-name")
                        Chip(title: L("收藏当前位置", "Save this place"), icon: "star.fill", id: "tp-save") {
                            let n = saveName.trimmingCharacters(in: .whitespaces)
                            s.saveWaypoint(n.isEmpty ? String(format: "%@ (%d, %d)", Society.layerName(model.depth, zh: GameModel.zh), me.x, me.y) : n)
                            saveName = ""
                            model.showToast(L("已收藏", "Saved"))
                        }
                    }
                    // any tile, by its coordinates, on any layer
                    HStack(spacing: 6) {
                        TextField("x", text: $coordX).keyboardType(.numbersAndPunctuation).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8).frame(width: 74, height: 32).background(Color.white.opacity(0.12), in: Capsule()).accessibilityIdentifier("tp-x")
                        TextField("y", text: $coordY).keyboardType(.numbersAndPunctuation).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8).frame(width: 74, height: 32).background(Color.white.opacity(0.12), in: Capsule()).accessibilityIdentifier("tp-y")
                        // (plain buttons: a system segmented picker did not take taps in these panels)
                        HStack(spacing: 2) {
                            ForEach(0..<TeleportPanel.layers.count, id: \.self) { i in
                                Button { coordLayer = i } label: {
                                    Text(TeleportPanel.layers[i].0).font(.system(size: 11, weight: coordLayer == i ? .bold : .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                                        .frame(maxWidth: .infinity).frame(height: 28)
                                        .background(coordLayer == i ? Color.white.opacity(0.32) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle()).accessibilityIdentifier("tp-layer-\(i)")
                            }
                        }
                        .padding(2).background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous)).frame(maxWidth: 220)
                        Chip(title: L("前往坐标", "Go"), icon: "scope", id: "tp-coords") {
                            guard let x = Int(coordX.trimmingCharacters(in: .whitespaces)), let y = Int(coordY.trimmingCharacters(in: .whitespaces)) else { model.showToast(L("请输入整数坐标", "Enter whole-number coordinates")); return }
                            let l = TeleportPanel.layers[coordLayer]
                            model.teleportAny(TeleportTarget(group: .recent, name: String(format: "(%d, %d)", x, y), tile: TilePos(x, y), depth: l.1, detail: ""))
                        }
                    }
                    Text(String(format: L("你在 (%d, %d) · %@", "You are at (%d, %d) · %@"), me.x, me.y, Society.layerName(model.depth, zh: GameModel.zh)))
                        .font(.system(size: 10, design: .rounded)).opacity(0.7)
                    // kinds
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                        groupChip(nil, L("全部", "All"), "square.grid.2x2")
                        ForEach(TeleportTarget.Group.allCases, id: \.self) { g in
                            if all.contains(where: { $0.group == g }) { groupChip(g, TeleportPanel.title(g), TeleportPanel.icon(g)) }
                        }
                    } }
                    TextField(L("搜索地名", "Search places"), text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12, design: .rounded)).padding(.horizontal, 10).frame(height: 32)
                        .background(Color.white.opacity(0.12), in: Capsule()).accessibilityIdentifier("tp-search")
                    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
                    let shown = all.filter { (group == nil || $0.group == group) && (q.isEmpty || $0.name.lowercased().contains(q) || $0.detail.lowercased().contains(q)) }
                    if shown.isEmpty { Text(L("没有符合的地方", "No place matches")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(shown.prefix(200).enumerated()), id: \.offset) { i, t in
                            HStack(spacing: 8) {
                                Image(systemName: TeleportPanel.icon(t.group)).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                                    Text(TeleportPanel.title(t.group) + " · " + t.detail).font(.system(size: 10, design: .rounded)).opacity(0.7).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if t.group == .saved, let k = (s.realm.waypoints ?? []).firstIndex(where: { $0.name == t.name && $0.x == t.tile.x && $0.y == t.tile.y }) {
                                    Button { s.removeWaypoint(at: k); model.objectWillChange.send() } label: { Image(systemName: "trash").frame(width: 30, height: 30) }.buttonStyle(PressStyle())
                                }
                                Button { model.teleportAny(t) } label: {
                                    Image(systemName: "sparkles").font(.system(size: 14, weight: .bold)).frame(width: 40, height: 32)
                                        .background(Color(red: 0.55, green: 0.35, blue: 0.95), in: Capsule())
                                }
                                .buttonStyle(PressStyle()).accessibilityIdentifier("tp-go-\(i)")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func groupChip(_ g: TeleportTarget.Group?, _ title: String, _ icon: String) -> some View {
        Chip(title: title, icon: icon, tint: group == g ? Color.white.opacity(0.32) : Color.white.opacity(0.12), id: "tp-group-\(g?.rawValue ?? "all")") { group = g }
    }

    static func title(_ g: TeleportTarget.Group) -> String {
        switch g {
        case .saved: return L("收藏", "Saved")
        case .recent: return L("最近", "Recent")
        case .city: return L("城市", "Cities")
        case .under: return L("地下", "Underground")
        case .sea: return L("海底", "Sea floor")
        case .sky: return L("天空城", "Sky cities")
        case .air: return L("机场与 UFO", "Airports & UFO")
        case .landmark: return L("地标", "Landmarks")
        }
    }

    static func icon(_ g: TeleportTarget.Group) -> String {
        switch g {
        case .saved: return "star.fill"
        case .recent: return "clock.arrow.circlepath"
        case .city: return "building.2.fill"
        case .under: return "arrow.down.to.line"
        case .sea: return "water.waves"
        case .sky: return "cloud.fill"
        case .air: return "airplane"
        case .landmark: return "flag.fill"
        }
    }
}
