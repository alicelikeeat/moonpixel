import SwiftUI
import MoonPixelCore

/// The display while the traveller is in a vehicle. Driving: the instruments of that kind of vehicle and its
/// controls (wheel, throttle, brake, reverse; a stick and flight assist in a plane; rudder and astern on a ship;
/// traction and brake on a train), the autopilot switch and the way out. Riding: where it is going, and the
/// way out when it stands. Every control only sets what the traveller asks of the vehicle: the core moves it.
struct DriveHUD: View {
    @EnvironmentObject var model: GameModel
    let d: DriveState

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                gauges.padding(10).glass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if d.driving {
                        pill(d.auto ? L("自动驾驶", "Autopilot") : L("手动", "Manual"), icon: d.auto ? "steeringwheel.badge.checkmark" : "steeringwheel", id: "drive-auto") { model.toggleAutopilot() }
                    }
                    pill(model.cockpit ? L("驾驶舱", "Cockpit") : L("车外", "Behind"), icon: "camera.rotate", id: "drive-camera") {
                        model.cockpit.toggle()
                        if model.render3D { model.viewMode = model.cockpit ? .first : .third }
                    }
                    if d.canLeave { pill(L("下车", "Get out"), icon: "figure.walk.departure", id: "drive-exit") { model.leaveVehicle() } }
                }
            }
            Spacer()
            if d.driving && !d.auto { controls }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .bottomLeading) {
            // what the vehicle itself reports, for assistive technology and UI tests
            Text(diag).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1).allowsHitTesting(false).accessibilityIdentifier("drive-state")
        }
    }

    private var diag: String {
        guard let s = model.society, let v = s.playerVehicle else { return "none" }
        return "\(v.kind.rawValue) id \(v.id) ctl \(v.control.rawValue) driving \(v.playerDriving) asked \(String(format: "%.2f", model.driveInput.throttle)) in \(String(format: "%.2f/%.2f", v.input.throttle, v.input.brake)) v \(String(format: "%.2f", v.speed)) fuel \(String(format: "%.0f", v.fuel)) halt \(v.halted ?? "-") tile \(v.tile.x),\(v.tile.y) way \(s.wayKind(at: v.tile)?.rawValue ?? "none") time \(String(format: "%.1f", s.world.time))"
    }

    private var gauges: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(d.kind.name(zh: GameModel.zh) + " · " + d.name).font(.system(size: 12, weight: .bold, design: .rounded))
            Text(String(format: "%.0f km/h", d.kmh)).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("drive-speed").accessibilityLabel(String(format: "%.0f km/h", d.kmh))
            Text(String(format: L("限速 %.0f · 档位 %@", "Limit %.0f · gear %@"), d.limitKmh, d.gear)).font(.system(size: 10, design: .rounded)).monospacedDigit()
            ProgressView(value: max(0, min(1, d.fuel))).frame(width: 140).tint(d.fuel < 0.15 ? Color.red : Color.green)
            Text(d.energy).font(.system(size: 10, design: .rounded)).monospacedDigit()
            switch d.kind.mode {
            case .air:
                Text(String(format: L("高度 %.0f m · 升降 %+.1f m/s · 航向 %03.0f°", "Alt %.0f m · climb %+.1f m/s · hdg %03.0f°"), d.altitude, d.climb, d.headingDeg))
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().accessibilityIdentifier("drive-altitude")
                Text(phaseText).font(.system(size: 10, design: .rounded))
            case .water:
                Text(String(format: L("舵 %+.0f%% · %@", "Rudder %+.0f%% · %@"), d.steer * 100, d.berthed ? L("已靠泊", "berthed") : L("航行", "under way")))
                    .font(.system(size: 11, design: .rounded)).monospacedDigit()
            case .rail:
                Text(L("信号 ", "Signal ") + d.signal).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(d.signal == L("红灯", "Red") ? Color.red : Color.green)
            default: EmptyView()
            }
            if !d.next.isEmpty { Text(d.next).font(.system(size: 10, design: .rounded)) }
            if d.seats > 4 { Text(String(format: L("乘客 %d / %d · 货物 %.0f", "Aboard %d / %d · goods %.0f"), d.riders, d.seats, d.cargo)).font(.system(size: 10, design: .rounded)).monospacedDigit() }
            if !d.halted.isEmpty { Text(d.halted).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.orange).accessibilityIdentifier("drive-halted") }
        }
        .foregroundStyle(.white)
    }

    private var phaseText: String {
        switch d.phase {
        case "taxi", "taxiIn": return L("滑行", "Taxiing")
        case "lineup": return L("对准跑道", "Lining up")
        case "roll": return L("起飞滑跑", "Take-off roll")
        case "air": return d.flight == .air ? L("飞行", "Flying") : ""
        case "final": return L("进近 · 下滑道", "Final approach")
        case "landed": return L("落地减速", "Landing roll")
        default: return d.flight == .crashed ? L("坠毁", "Crashed") : (d.flight == .air ? L("飞行", "Flying") : L("地面", "On the ground"))
        }
    }

    // MARK: controls

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 14) {
            // the wheel (rudder, bank)
            if d.kind.mode != .rail {
                HStack(spacing: 8) {
                    hold("arrow.turn.up.left", L("左", "Left"), id: "drive-left") { model.driveInput.steer = $0 ? -1 : 0 }
                    hold("arrow.turn.up.right", L("右", "Right"), id: "drive-right") { model.driveInput.steer = $0 ? 1 : 0 }
                }
            }
            if d.kind.mode == .air {
                VStack(spacing: 8) {
                    hold("arrow.up", L("拉杆", "Nose up"), id: "drive-pitch-up") { model.driveInput.pitch = $0 ? 0.6 : 0 }
                    hold("arrow.down", L("推杆", "Nose down"), id: "drive-pitch-down") { model.driveInput.pitch = $0 ? -0.6 : 0 }
                }
                pill(d.assist ? L("辅助开", "Assist on") : L("辅助关", "Assist off"), icon: "airplane", id: "drive-assist") { model.driveInput.assist.toggle() }
            }
            Spacer()
            if d.kind.mode == .road || d.kind.mode == .water || d.kind.mode == .air {
                pill(model.driveInput.reverse ? (d.kind.mode == .water ? L("倒车（后退）", "Astern") : L("倒挡", "Reverse")) : L("前进", "Forward"),
                     icon: "arrow.uturn.backward", id: "drive-reverse") { model.driveInput.reverse.toggle() }
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    step("minus", L("减油门", "Less throttle"), id: "drive-throttle-down") { model.driveInput.throttle = max(0, model.driveInput.throttle - 0.25) }
                    Text(String(format: "%.0f%%", model.driveInput.throttle * 100)).font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit().frame(width: 40)
                    step("plus", L("加油门", "More throttle"), id: "drive-throttle-up") { model.driveInput.throttle = min(1, model.driveInput.throttle + 0.25); model.driveInput.brake = 0 }
                }
                Text(d.kind.mode == .rail ? L("牵引", "Traction") : L("油门", "Throttle")).font(.system(size: 10, design: .rounded))
                Slider(value: Binding(get: { model.driveInput.throttle }, set: { model.driveInput.throttle = $0; if $0 > 0 { model.driveInput.brake = 0 } }), in: 0...1)
                    .frame(width: 150).accessibilityIdentifier("drive-throttle")
            }
            hold("stop.circle.fill", L("刹车", "Brake"), id: "drive-brake", big: true) { model.driveInput.brake = $0 ? 1 : 0; if $0 { model.driveInput.throttle = 0 } }
        }
        .padding(10).glass(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A button that acts while held (pressed: true; let go: false).
    private func hold(_ icon: String, _ label: String, id: String, big: Bool = false, _ set: @escaping (Bool) -> Void) -> some View {
        Image(systemName: icon).font(.system(size: big ? 26 : 20, weight: .semibold))
            .frame(width: big ? 64 : 50, height: big ? 64 : 50)
            .glass(Circle())
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in set(true) }.onEnded { _ in set(false) })
            .accessibilityElement().accessibilityIdentifier(id).accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .accessibilityAction { set(true); DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { set(false) } }
    }

    private func step(_ icon: String, _ label: String, id: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Image(systemName: icon).font(.system(size: 16, weight: .bold)).frame(width: 38, height: 34) }
            .buttonStyle(PressStyle()).glass(Capsule())
            .accessibilityIdentifier(id).accessibilityLabel(label)
    }

    private func pill(_ title: String, icon: String, id: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 12).padding(.vertical, 8) }
            .buttonStyle(PressStyle()).glass(Capsule())
            .accessibilityIdentifier(id)
    }
}
