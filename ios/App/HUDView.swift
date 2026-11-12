import SwiftUI
import PhotosUI
import MoonPixelCore

/// The in-game interface, built from system Liquid Glass.
struct HUDView: View {
    @EnvironmentObject var model: GameModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var toastVisible = false

    var body: some View {
        ZStack {
            if model.showMap { mapOverlay }
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation(.snappy) { model.showDetails.toggle(); model.refreshHUD() } } label: {
                            Text(model.status).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain).glass(Capsule())
                        if model.showDetails { details }
                    }
                    Spacer(minLength: 0)
                    if toastVisible {
                        Text(model.toast).font(.system(size: 13, weight: .medium, design: .rounded)).lineLimit(2)
                            .padding(.horizontal, 14).padding(.vertical, 9).glass(Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 8) {
                        speedBar
                        if let info = model.selected { agentCard(info) }
                    }
                }
                Spacer(minLength: 0)
                tabBar
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .foregroundStyle(.white)
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: model.photoTarget) { _, v in if v != nil { showPicker = true } }
        .onChange(of: model.importingAsset) { _, v in if v { showPicker = true } }
        .onChange(of: showPicker) { _, open in if !open && pickerItem == nil { model.photoTarget = nil; model.importingAsset = false } }
        .onChange(of: pickerItem) { _, item in
            guard let item = item else { return }
            let target = model.photoTarget
            let asAsset = model.importingAsset
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data = data, let img = UIImage(data: data) {
                        if asAsset { model.importAsset(img) } else { model.applyPhoto(img, target: target ?? 0) }
                    } else { model.showToast(L("无法读取图片", "Could not read the picture")) }
                    model.photoTarget = nil; model.importingAsset = false; pickerItem = nil
                }
            }
        }
        .onChange(of: model.toastID) { _, _ in
            withAnimation(.snappy) { toastVisible = true }
            let id = model.toastID
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { if model.toastID == id { withAnimation(.easeOut) { toastVisible = false } } }
        }
    }

    private var speedBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<GameModel.speeds.count, id: \.self) { i in
                Button { model.speedIndex = i } label: {
                    Group {
                        if i == 0 { Image(systemName: "pause.fill") } else { Text("\(Int(GameModel.speeds[i]))×") }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 40, height: 34)
                    .background(model.speedIndex == i ? Color.white.opacity(0.22) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).glass(Capsule())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.statsText).font(.system(size: 13, design: .rounded))
            Text(model.memoryText).font(.system(size: 11, design: .rounded)).foregroundStyle(Color(red: 0.75, green: 0.92, blue: 1))
            HStack(spacing: 6) {
                pill(L("立即清理内存", "Free memory now"), "sparkles") { model.cleanMemory(announce: true) }
                pill(model.autoClean ? L("自动清理：开", "Auto clean: on") : L("自动清理：关", "Auto clean: off"), "arrow.triangle.2.circlepath") { model.autoClean.toggle() }
            }
            ForEach(model.logLines, id: \.self) { Text($0).font(.system(size: 11, design: .rounded)).opacity(0.85) }
            Text(L("导入图片请确保你有权使用；素材只保存在本机。", "Only import pictures you may use; they stay on this device."))
                .font(.system(size: 9)).opacity(0.5)
        }
        .padding(14).frame(maxWidth: 360, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
    }

    private func pill(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func agentCard(_ info: Society.TalkInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(info.name)  \(info.female ? "♀" : "♂") \(info.age)").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button { model.deselect() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 28, height: 28).background(Color.white.opacity(0.14), in: Circle()) }
                    .buttonStyle(.plain)
            }
            Text("\(info.settlement) · \(info.job)").font(.system(size: 12, design: .rounded)).opacity(0.85)
            HStack(spacing: 10) {
                meter(L("心情", "Mood"), info.mood, .green)
                meter(L("饥饿", "Hunger"), info.hunger, .orange)
                meter(L("精力", "Energy"), info.energy, .cyan)
            }
            Text("「\(info.line)」").font(.system(size: 13, weight: .medium, design: .rounded)).padding(.vertical, 2)
            ForEach(info.family.prefix(3), id: \.self) { Text($0).font(.system(size: 11, design: .rounded)) }
            if info.pregnant { Text(L("怀孕中", "Expecting")).font(.system(size: 11, design: .rounded)).foregroundStyle(.pink) }
            ForEach(info.thoughts, id: \.self) { Text("· " + $0).font(.system(size: 11, design: .rounded)).opacity(0.8) }
            Text("\(info.settlement): \(info.stock)").font(.system(size: 10, design: .rounded)).opacity(0.6)
            HStack(spacing: 6) {
                pill(L("交谈", "Talk"), "bubble.left.fill") { model.talk() }
                pill(L("送食物", "Feed"), "fork.knife") { model.feed() }
                pill(L("跟随", "Follow"), "figure.walk") { model.following.toggle() }
                pill(L("照片", "Photo"), "camera.fill") { model.photoTarget = model.selectedID }
            }
        }
        .padding(14).frame(width: 300, alignment: .leading)
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

    private var tabBar: some View {
        HStack(spacing: 2) {
            tab(L("地图", "Map"), "map.fill") { model.toggleMap() }
            tab(L("村落", "Village"), "house.fill") { model.nextVillage() }
            tab(weaponName, weaponIcon) { model.cycleWeapon() }
            tab(L("照片", "Photo"), "person.crop.circle.badge.plus") { model.photoTarget = 0 }
            tab(L("素材", "Import"), "photo.badge.plus") { model.importingAsset = true }
            tab(L("清理", "Clean"), "sparkles") { model.cleanMemory(announce: true) }
            tab(L("保存", "Save"), "square.and.arrow.down.fill") { model.save(announce: true) }
            tab("", "plus.magnifyingglass") { model.scene?.zoomBy(0.5) }
            tab("", "minus.magnifyingglass") { model.scene?.zoomBy(-0.5) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .glass(Capsule())
    }

    private var weaponName: String {
        switch GameModel.weapons[model.weaponIndex] {
        case "sword": return L("剑", "Sword")
        case "bow": return L("弓", "Bow")
        case "staff": return L("法杖", "Staff")
        default: return L("空手", "Hands")
        }
    }

    private var weaponIcon: String {
        switch GameModel.weapons[model.weaponIndex] {
        case "bow": return "scope"
        case "staff": return "wand.and.stars"
        case "sword": return "shield.lefthalf.filled"
        default: return "hand.raised.fill"
        }
    }

    private func tab(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                if !title.isEmpty { Text(title).font(.system(size: 10, weight: .medium, design: .rounded)) }
            }
            .frame(minWidth: title.isEmpty ? 40 : 52, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private var mapOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { model.toggleMap() }
            VStack(spacing: 10) {
                if let img = model.mapImage {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(8).glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                Text(model.mapCaption).font(.system(size: 12, design: .rounded)).padding(.horizontal, 14).padding(.vertical, 8).glass(Capsule())
            }
            .padding(.vertical, 60).padding(.horizontal, 40)
            .allowsHitTesting(false)
        }
    }
}
