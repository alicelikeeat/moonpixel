import SwiftUI
import MoonPixelCore

/// 出行 / Travel: vehicles to get into here, where to go, the route with its changes, and waiting for the line.
struct TravelPanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("出行", "Travel"), subtitle: L("驾驶、乘车、换乘", "Drive, ride, change"), close: { model.showTravel = false }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("附近的车辆", "Vehicles here")).font(.system(size: 13, weight: .bold, design: .rounded))
                    if model.vehiclesHere.isEmpty { Text(L("附近没有车辆", "No vehicles near")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
                    ForEach(model.vehiclesHere) { r in
                        HStack {
                            Text(r.text).font(.system(size: 11, design: .rounded)).lineLimit(1)
                            Spacer()
                            if r.canDrive { Chip(title: L("驾驶", "Drive"), icon: "steeringwheel", id: "board-drive-\(r.id)") { model.board(r.id, drive: true) } }
                            if r.canRide { Chip(title: L("乘坐", "Ride"), icon: "person.fill", id: "board-ride-\(r.id)") { model.board(r.id, drive: false) } }
                        }
                    }
                    Chip(title: L("用背包材料造一辆车", "Build a car from the pack"), icon: "car.fill", id: "build-car") { model.buildCarHere() }
                    // ships, built on the nearest water: from a ferry to an aircraft carrier
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 6) {
                        ForEach(Society.playerShips, id: \.self) { k in
                            Chip(title: L("造", "Build ") + k.name(zh: GameModel.zh), icon: k == .carrier ? "airplane.circle" : "ferry.fill", id: "build-ship-\(k.rawValue)") { model.buildShipHere(k) }
                        }
                    }
                    Divider().opacity(0.3)
                    // flying: a charter from the nearest airport to another city's
                    Text(L("坐飞机去别的城市", "Fly to another city")).font(.system(size: 13, weight: .bold, design: .rounded))
                    if model.flights.isEmpty { Text(L("还没有别的机场：城市长到 150 人会自己修机场", "No other airport yet: towns build one at 150 people")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
                    ForEach(model.flights) { a in
                        HStack(spacing: 6) {
                            Text(a.text).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                            Spacer(minLength: 4)
                            Chip(title: L("乘机", "Fly there"), icon: "airplane.departure", id: "fly-\(a.id)") { model.flyTo(a.id, pilot: false) }
                            Chip(title: L("驾驶", "Pilot"), icon: "airplane", id: "pilot-\(a.id)") { model.flyTo(a.id, pilot: true) }
                        }
                    }
                    Divider().opacity(0.3)
                    // the air network: airports, the nations' airfields, UFO airports and the sky cities
                    Text(L("航空网络（飞机 · 飞碟）", "Air network (planes · saucers)")).font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(model.airHere.map { L("你在：", "You are at: ") + $0.name } ?? L("你不在机场附近：走到机场、UFO 机场或天空城空港 64 格内即可起飞（也可以先用瞬移中心过去）", "Not at an airport: go within 64 tiles of an airport, a UFO airport or a sky city's airport to take off (or teleport there first)"))
                        .font(.system(size: 11, design: .rounded)).opacity(0.8).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("air-here")
                    ForEach(model.airHubs, id: \.id) { h in
                        HStack(spacing: 6) {
                            Image(systemName: h.kind == .ufo ? "circle.circle.fill" : (h.kind == .sky ? "cloud.fill" : "airplane")).frame(width: 18)
                            Text(h.name).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                            Spacer(minLength: 4)
                            if h.runway && (model.airHere?.runway ?? false) { Chip(title: L("飞机", "Plane"), icon: "airplane.departure", id: "air-plane-\(h.id)") { model.airFly(h, by: .plane) } }
                            if model.airHere != nil { Chip(title: L("飞碟", "Saucer"), icon: "circle.circle", id: "air-ufo-\(h.id)") { model.airFly(h, by: .ufo) } }
                        }
                    }
                    Divider().opacity(0.3)
                    Text(L("目的地", "Where to")).font(.system(size: 13, weight: .bold, design: .rounded))
                    if model.destinations.isEmpty { Text(L("还没有车站", "No stops yet")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], alignment: .leading, spacing: 6) {
                        ForEach(model.destinations) { st in
                            Chip(title: st.text, icon: model.tripTo == st.id ? "mappin.circle.fill" : "mappin", id: "dest-\(st.id)") { model.planTrip(to: st.id) }
                        }
                    }
                    if let p = model.trip {
                        Divider().opacity(0.3)
                        Text(L("路线", "Route")).font(.system(size: 13, weight: .bold, design: .rounded))
                        ForEach(Array(model.tripText(p).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .rounded))
                        }
                        .accessibilityIdentifier("trip-plan")
                        if p.ok { Chip(title: L("在第一站等车", "Wait at the first stop"), icon: "clock", id: "trip-wait") { model.waitForTrip() } }
                    }
                }
            }
        }
    }
}

/// 交通管理 / Transport: districts and their services, lines, vehicles, bottlenecks, and building ways.
struct TransportPanel: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        GlassSheet(title: L("交通管理", "Transport"), subtitle: L("线路、班次、拥堵、瓶颈", "Lines, timetables, congestion, bottlenecks"), close: { model.showTransport = false }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("修建", "Build")).font(.system(size: 13, weight: .bold, design: .rounded))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], alignment: .leading, spacing: 6) {
                        ForEach([WayKind.street, .highway, .rail, .hsr, .runway, .taxiway, .apron, .quay, .platform, .parking], id: \.self) { k in
                            Chip(title: k.name(zh: GameModel.zh) + (model.wayKindPick == k ? " ●" : ""), icon: icon(k), id: "way-\(k.rawValue)") {
                                model.wayKindPick = k; model.wayStart = nil; model.wayPreview = nil
                            }
                        }
                    }
                    HStack {
                        Chip(title: model.wayStart == nil ? L("在此设起点", "Start here") : L("在此设终点并预览", "End here and preview"), icon: "point.topleft.down.curvedto.point.bottomright.up", id: "way-mark") { model.markWay() }
                        if model.wayStart != nil { Chip(title: L("取消", "Cancel"), icon: "xmark", id: "way-cancel") { model.wayStart = nil; model.wayPreview = nil } }
                    }
                    if let p = model.wayPreview {
                        ForEach(Array(model.previewText(p).enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 11, design: .rounded)) }
                            .accessibilityIdentifier("way-preview")
                        if p.ok { Chip(title: L("确认开工（从背包付）", "Build it (paid from the pack)"), icon: "hammer.fill", id: "way-confirm") { model.confirmWay() } }
                    }
                    Divider().opacity(0.3)
                    Text(L("网络", "Network")).font(.system(size: 13, weight: .bold, design: .rounded))
                    if model.transportLines.isEmpty { Text(L("还没有交通网络", "No network yet")).font(.system(size: 11, design: .rounded)).opacity(0.7) }
                    ForEach(Array(model.transportLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("transport-lines")
                    Chip(title: L("刷新", "Refresh"), icon: "arrow.clockwise", id: "transport-refresh") { model.refreshTransport() }
                }
            }
        }
    }

    private func icon(_ k: WayKind) -> String {
        switch k.mode {
        case .road: return "road.lanes"
        case .rail: return "tram.fill"
        case .air: return "airplane"
        case .water: return "ferry.fill"
        case .foot: return k == .quay ? "ferry.fill" : "figure.walk"
        }
    }
}
