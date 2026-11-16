import SwiftUI
import MoonPixelCore

extension GameModel {
    /// Begin a battle of command mode: the traveller's nation (or the first) against another of the
    /// three, on generated land far from the villages. The world is left as it is and waits.
    func startCommand() {
        guard command == nil, let w = world, let s = society else { return }
        let nations = s.realm.nations
        let mine = nations.first { $0.id == s.realm.player.nation } ?? nations.first
        let foe = nations.first { $0.id != mine?.id }
        let a = (mine?.name(zh: GameModel.zh) ?? L("蔚蓝", "Azure"), mine?.color ?? "#4a8af0")
        let b = (foe?.name(zh: GameModel.zh) ?? L("绯红", "Crimson"), foe?.color ?? "#e8504a")
        commandCount += 1
        let session = SkirmishSession(sim: Skirmish(seed: w.seed &+ commandCount &* 977, worldSeed: w.seed, player: a, enemy: b))
        session.onExit = { [weak self] in self?.command = nil }
        session.refresh()
        command = session
    }
}

extension GameModel {
    var metroFile: URL { saveDir.appendingPathComponent("metro.json") }

    /// Open this world's city (or found one): it is kept in the world's folder and goes with the world.
    func startMetro(fresh: Bool = false) {
        guard metro == nil, let w = world else { return }
        var city: Metro?
        if !fresh, let data = try? Data(contentsOf: metroFile) { city = try? JSONDecoder().decode(Metro.self, from: data) }
        if city == nil && !fresh && FileManager.default.fileExists(atPath: metroFile.path) {
            // a city that cannot be read is kept aside, never overwritten
            try? FileManager.default.moveItem(at: metroFile, to: saveDir.appendingPathComponent("metro.unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            showToast(L("城市存档无法读取，已另存并新建城市", "The city could not be read; it was kept aside and a new one founded"))
        }
        let c = city ?? Metro(seed: w.seed &+ 4049, worldSeed: w.seed, name: worldName.isEmpty ? L("新月城", "Moonhaven") : worldName + L("市", " City"))
        let session = MetroSession(city: c, file: metroFile)
        session.onExit = { [weak self] in self?.metro = nil }
        session.refresh()
        metro = session
    }
}
