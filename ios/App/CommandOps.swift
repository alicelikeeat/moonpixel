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
        // an unfinished battle is taken up again where it was left
        let store = SaveFile(url: saveDir.appendingPathComponent("battle.json"))
        if CommandLine.arguments.contains("--new-battle") || CommandLine.arguments.contains("--command-auto") { store.discard() }
        let got = store.load { try Skirmish.decode($0) }
        if got.locked {
            showToast(L("对局存档损坏且无法移开，未开始对局", "The battle save is damaged and could not be moved aside; no battle was started"))
            return
        }
        var sim = got.value.flatMap { $0.winner == nil ? $0 : nil }
        if sim != nil { showToast(got.source == .previous ? L("继续上次的对局（载入上一版存档）", "Taking up the last battle (from the previous save)") : L("继续上次的对局", "Taking up the last battle")) }
        else if got.keptAside != nil { showToast(L("对局存档损坏，已另存，开始新对局", "The battle save was damaged; it was kept aside and a new battle started")) }
        if sim == nil {
            // governing a nation that is at war: this battle is fought for that war, with part of its treasury
            // staked as extra moonstone; the result reaches the world once, when the battle ends
            if let n = civCommand, let camp = s.civ.beginCampaign(n), !camp.settled, let me = s.civ.polities[camp.nation], let foe = s.civ.polities[camp.foe] {
                sim = Skirmish(seed: w.seed &+ commandCount &* 977, worldSeed: w.seed, player: (me.name(zh: GameModel.zh), me.color), enemy: (foe.name(zh: GameModel.zh), foe.color), credits: 3000 + camp.stake)
                showToast(String(format: L("世界战役：为 %@ 对 %@ 的战争而战，国库出资 %d", "World campaign: fighting %@'s war on %@, %d from the treasury"), me.name(zh: GameModel.zh), foe.name(zh: GameModel.zh), Int(camp.stake)))
            } else { sim = Skirmish(seed: w.seed &+ commandCount &* 977, worldSeed: w.seed, player: a, enemy: b) }
        }
        let session = SkirmishSession(sim: sim!, store: CommandLine.arguments.contains("--command-auto") ? nil : store)
        session.onExit = { [weak self, weak session] in
            // a finished campaign battle is settled in the world, once
            if let win = session?.sim.winner, let civ = self?.society?.civ, civ.settleCampaign(won: win == 0) {
                self?.showToast(win == 0 ? L("战役胜利：敌国厌战上升，出资加倍返还", "Campaign won: the enemy tires and the stake comes back doubled") : L("战役失利：出资损失，本国厌战上升", "Campaign lost: the stake is gone and the nation tires"))
            }
            self?.command = nil
        }
        session.refresh()
        command = session
    }
}

extension GameModel {
    var metroFile: URL { saveDir.appendingPathComponent("metro.json") }

    /// Open this world's city (or found one): it is kept in the world's folder and goes with the world.
    func startMetro(fresh: Bool = false) {
        guard metro == nil, let w = world else { return }
        let store = SaveFile(url: metroFile)
        var city: Metro?
        if !fresh {
            let got = store.load { try JSONDecoder().decode(Metro.self, from: $0) }
            if got.locked {
                // the unreadable file could not even be moved aside: open nothing rather than risk writing over it
                showToast(L("城市存档损坏且无法移开，未打开城市以免覆盖", "The city save is damaged and could not be moved aside; the city was not opened, so nothing overwrites it"))
                return
            }
            city = got.value
            if let aside = got.keptAside {
                showToast(got.source == .previous
                    ? L("城市存档损坏，已另存为 \(aside.lastPathComponent)，载入上一版", "The city save was damaged; it was kept as \(aside.lastPathComponent) and the previous version loaded")
                    : L("城市存档损坏，已另存为 \(aside.lastPathComponent)，新建城市", "The city save was damaged; it was kept as \(aside.lastPathComponent) and a new city founded"))
            } else if got.source == .previous {
                showToast(L("城市存档缺失，已载入上一版", "The city save was missing; the previous version was loaded"))
            }
        }
        let c = city ?? Metro(seed: w.seed &+ 4049, worldSeed: w.seed, name: worldName.isEmpty ? L("新月城", "Moonhaven") : worldName + L("市", " City"))
        let session = MetroSession(city: c, file: metroFile, store: store)
        session.onExit = { [weak self] in self?.metro = nil }
        session.refresh()
        metro = session
    }
}
