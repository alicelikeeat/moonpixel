import SwiftUI
import MoonPixelCore

/// One place for every save of the open world: autosave, the Save button, going to the background,
/// leaving for the world list, world laws and genesis.
///
/// The batch is taken on the main thread from one consistent moment (chunks staged, the society
/// encoded); the files are written on a serial background queue; the result is applied back on the
/// main thread. Saves of the same world never overlap: a save asked for while one is running is
/// folded into the next one, and every caller gets its own answer.
extension GameModel {
    static let saveQueue = DispatchQueue(label: "moonpixel.save", qos: .utility)

    var store: WorldStore? { world?.store }

    /// Ask for a save. `purge` drops the previous generation afterwards (after a permanent deletion).
    /// `force` lets a world law's own final save through while the law is still marked as running.
    func save(announce: Bool, purge: Bool = false, force: Bool = false, then: ((Bool, String?) -> Void)? = nil) {
        if let t = then { saveWaiters.append(t) }
        if purge { savePurgeNext = true }
        if announce { saveAnnounceNext = true }
        // a law half carried out must never be committed: its own save comes when it is done
        if lawBusy && !force {
            let w = saveWaiters; saveWaiters = []
            for f in w { f(false, L("世界法则执行中，稍后保存", "A world law is running; saving after it")) }
            return
        }
        if saveRunning { saveAgain = true; return }
        runSave()
    }

    private func runSave() {
        guard let w = world, let s = society, let sc = scene, let st = w.store else {
            let waiters = saveWaiters; saveWaiters = []
            for f in waiters { f(false, L("没有打开的世界", "No world is open")) }
            return
        }
        saveRunning = true
        saveAgain = false
        let purge = savePurgeNext, announce = saveAnnounceNext
        savePurgeNext = false; saveAnnounceNext = false
        let waiters = saveWaiters
        saveWaiters = []
        let t0 = CACurrentMediaTime()
        w.saveAll()
        s.under?.saveAll()
        let ix = Index(format: GameModel.saveFormat, world: w.snapshot(), society: s.snapshot(), px: sc.player.x, py: sc.player.y, look: playerLook, recipe: recipe)
        let tech = s.techCount > 0 ? s.techName(s.techCount - 1) : ""
        let meta = WorldMeta(id: worldID, name: worldName, seed: w.seed, savedAt: Date(), year: w.year + 1, population: s.agents.count, diskBytes: storeDiskBytes, tech: tech)
        guard let ixData = try? JSONEncoder().encode(ix), let metaData = try? JSONEncoder().encode(meta) else {
            saveRunning = false
            saveFinished(false, L("存档内容无法编码", "The save could not be encoded"), announce: announce, waiters: waiters)
            return
        }
        // injected failures for the UI test (`--fail-saves N`): the next N commits fail at the manifest
        if failSaves > 0 { failSaves -= 1; st.failAt = [.manifestWrite] } else { st.failAt = [] }
        let batch = st.beginCommit(index: ixData, meta: metaData)
        let prepared = CACurrentMediaTime() - t0
        let dir = saveDir
        let token = epoch
        let background = UIApplication.shared.beginBackgroundTask(withName: "save") {}
        GameModel.saveQueue.async {
            let result = Result { try st.write(batch) }
            DispatchQueue.main.async { [weak self] in
                defer { UIApplication.shared.endBackgroundTask(background) }
                guard let self = self else { return }
                let total = CACurrentMediaTime() - t0
                self.perf.noteSave(prepare: prepared, total: total)
                switch result {
                case .success(let m):
                    st.finishCommit(batch, m)
                    self.saveError = nil
                    self.lastSavedGen = m.gen
                    self.lastSavedAt = Date()
                    // cleaning up is not part of the save: if it fails, the new generation stays valid and it is tried again next time
                    GameModel.saveQueue.async {
                        _ = try? st.collectGarbage(purge: purge, current: m)
                        let bytes = st.diskBytes()
                        try? metaData.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
                        DispatchQueue.main.async { [weak self] in if self?.epoch == token { self?.storeDiskBytes = bytes } }
                    }
                    self.saveRunning = false
                    self.saveFinished(true, nil, announce: announce, waiters: waiters)
                case .failure(let e):
                    self.saveRunning = false
                    let step = (e as? SaveError)?.step
                    let what: String
                    switch step {
                    case .objectWrite?: what = L("写入地图区块时失败", "writing map chunks failed")
                    case .indexWrite?: what = L("写入人物与城市数据时失败", "writing people and towns failed")
                    case .manifestWrite?: what = L("写入存档清单时失败", "writing the save manifest failed")
                    case .headSwitch?: what = L("切换到新存档时失败", "switching to the new save failed")
                    default: what = L("保存失败", "saving failed")
                    }
                    let kept = st.headGen > 0
                        ? String(format: L("；最近一次成功的存档（第 %d 次）没有被改动，本次的变化仍保留在内存中，可以重试", "; the last good save (#%d) was not touched and this session's changes are still in memory, so you can retry"), st.headGen)
                        : L("；这个世界还没有成功保存过，变化仍保留在内存中，可以重试", "; this world has never been saved successfully yet; its changes are still in memory, so you can retry")
                    self.saveFinished(false, what + kept, announce: true, waiters: waiters)
                }
                if self.saveAgain || !self.saveWaiters.isEmpty { self.runSave() }
            }
        }
    }

    private func saveFinished(_ ok: Bool, _ message: String?, announce: Bool, waiters: [(Bool, String?) -> Void]) {
        if !ok { saveError = message }
        if announce { showToast(ok ? L("已保存", "Saved") : (message ?? "")) }
        for f in waiters { f(ok, message) }
    }

    /// Leave for the world list - only once everything is safely saved. If saving fails the world
    /// stays open and paused, and the player can retry or keep playing.
    func exitToMenu() {
        if exitRequested { return }
        exitRequested = true
        save(announce: false) { [weak self] ok, message in
            guard let self = self else { return }
            self.exitRequested = false
            if ok { self.releaseWorld() }
            else { self.exitBlocked = message ?? L("保存失败", "Saving failed") }
        }
    }

    func retryExit() { exitBlocked = nil; exitToMenu() }
    func stayAfterFailedExit() { exitBlocked = nil }

    func releaseWorld() {
        scene?.isPaused = true
        scene = nil
        world = nil
        society = nil
        epoch += 1                      // late results of anything still running belong to no world now
        refreshWorlds()
    }

    /// The world is paused while a failed exit or a failed law save waits for the player.
    var savePause: Bool { exitBlocked != nil || lawSavePending }
}
