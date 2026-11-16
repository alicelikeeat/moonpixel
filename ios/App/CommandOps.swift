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
