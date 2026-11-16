import Foundation

// Commands. Everything a player (or a panel, or a test) does to the civilisation layer is a command:
// received, checked, given what it needs (reserved), then carried out or refused, with a result that
// says why. The panels never change the world themselves.
//
// * A command has an id chosen by whoever sends it. The same id twice is the same command: the second
//   time it is not carried out again, the first result is returned (no double charge, no second
//   building, no second convoy). The ids remembered go with the save.
// * A command may name the step it is meant for (it waits until then, and runs in id order among the
//   others of that step) and the revision of the city it was decided on (if the city has changed since,
//   it is refused as stale rather than applied to something the sender did not see).
// * Reservations: materials promised to a machine's next stage are held aside (`CivCity.reserved`), so
//   nothing else spends them; cancelling, losing the city or finishing releases them.

public struct WorldCommand: Codable, Equatable {
    public enum Action: Codable, Equatable {
        case build(city: Int, facility: String)
        case order(city: Int, kind: String)
        case cancel(project: Int)
        case deploy(unit: Int, force: Int?)
        case retire(unit: Int)
        case send(force: Int, region: Int64, attack: Bool)
        case ration(city: Int, policy: CivRation)
        case ship(from: Int, to: Int, goods: [String: Double])
        case foundNation(city: Int, people: Int, region: Int64)
        case declare(on: Int)
        case peace(with: Int)
    }
    public var id: String
    public var issuer: Int                       // the nation it is given for
    public var step: Int?                        // the hour it is meant for; nil: at once
    public var expect: Int?                      // the revision of the city it was decided on
    public var action: Action
    public init(id: String, issuer: Int, step: Int? = nil, expect: Int? = nil, _ action: Action) {
        self.id = id; self.issuer = issuer; self.step = step; self.expect = expect; self.action = action
    }
}

public struct CommandResult: Codable, Equatable {
    public var id: String
    public var ok: Bool
    public var reason: String?                   // why it was refused (a key the panel puts into words)
    public var ref: Int?                         // what it made: project, trip, force, nation
    public var step: Int
    public var repeated = false                  // this id was seen before; nothing was done again
}

extension Civ {
    /// The hour the layer is at (commands name these).
    public var step: Int { Int((time - hourAcc) / (MP.daySeconds / 24)) }

    /// Give a command. Carried out now, or queued for its step; a repeated id returns the first result.
    @discardableResult public func execute(_ cmd: WorldCommand) -> CommandResult {
        if var done = commandResults[cmd.id] { done.repeated = true; return done }
        if let s = cmd.step, s > step {
            if !pendingCommands.contains(where: { $0.id == cmd.id }) { pendingCommands.append(cmd) }
            return CommandResult(id: cmd.id, ok: true, reason: "queued", ref: nil, step: s)
        }
        let r = apply(cmd)
        remember(r)
        return r
    }

    /// Commands whose step has come, in (step, id) order. Called at the start of every hour.
    func runPending() {
        let now = step
        let due = pendingCommands.filter { ($0.step ?? 0) <= now }.sorted { ($0.step ?? 0, $0.id) < ($1.step ?? 0, $1.id) }
        guard !due.isEmpty else { return }
        pendingCommands.removeAll { ($0.step ?? 0) <= now }
        for c in due where commandResults[c.id] == nil { remember(apply(c)) }
    }

    func remember(_ r: CommandResult) {
        commandResults[r.id] = r
        commandOrder.append(r.id)
        // the window of remembered ids is long but not endless; it is saved with the world
        if commandOrder.count > Civ.commandMemory {
            for old in commandOrder.prefix(commandOrder.count - Civ.commandMemory) { commandResults[old] = nil }
            commandOrder.removeFirst(commandOrder.count - Civ.commandMemory)
        }
    }
    static let commandMemory = 4096

    func apply(_ cmd: WorldCommand) -> CommandResult {
        let now = step
        func no(_ why: String) -> CommandResult { CommandResult(id: cmd.id, ok: false, reason: why, ref: nil, step: now) }
        func yes(_ ref: Int? = nil) -> CommandResult { CommandResult(id: cmd.id, ok: true, reason: nil, ref: ref, step: now) }
        guard let p = polities[cmd.issuer], p.status == .active else { return no("no_nation") }
        func mine(_ id: Int) -> CivCity? { cities[id].flatMap { $0.nation == cmd.issuer && $0.detail == nil ? $0 : nil } }
        func fresh(_ c: CivCity) -> Bool { cmd.expect == nil || cmd.expect == c.rev }
        switch cmd.action {
        case .build(let id, let f):
            guard let c = mine(id) else { return no("not_yours") }
            guard fresh(c) else { return no("stale") }
            guard build(f, in: c) else { return no("cannot_build") }
            c.rev += 1
            return yes()
        case .order(let id, let kind):
            guard let c = mine(id) else { return no("not_yours") }
            guard fresh(c) else { return no("stale") }
            guard let pid = order(kind, nation: cmd.issuer, city: id) else { return no("cannot_order") }
            c.rev += 1
            return yes(pid)
        case .cancel(let pid):
            guard let pr = projects[pid], pr.nation == cmd.issuer else { return no("not_yours") }
            _ = cancel(project: pid)
            cities[pr.city]?.rev += 1
            return yes(pid)
        case .deploy(let uid, let fid):
            guard units[uid]?.nation == cmd.issuer else { return no("not_yours") }
            guard let f = deploy(uid, joining: fid) else { return no("cannot_deploy") }
            return yes(f)
        case .retire(let uid):
            guard units[uid]?.nation == cmd.issuer else { return no("not_yours") }
            return retire(uid) ? yes(uid) : no("cannot_retire")
        case .send(let fid, let k, let attack):
            guard forces[fid]?.nation == cmd.issuer else { return no("not_yours") }
            return send(fid, to: k, attack: attack) ? yes(fid) : no("no_way")
        case .ration(let id, let r):
            guard let c = mine(id) else { return no("not_yours") }
            setRation(c, r); c.rev += 1
            return yes()
        case .ship(let a, let b, let goods):
            guard let c = mine(a), cities[b] != nil else { return no("not_yours") }
            guard fresh(c) else { return no("stale") }
            guard let t = ship(goods, from: a, to: b) else { return no("cannot_ship") }
            c.rev += 1
            return yes(t)
        case .foundNation(let id, let k, let region):
            guard let c = mine(id) else { return no("not_yours") }
            guard let n = foundNation(from: c.id, people: k, at: region) else { return no("cannot_found") }
            c.rev += 1
            return yes(n)
        case .declare(let o):
            guard polities[o] != nil, o != cmd.issuer else { return no("no_nation") }
            declare(cmd.issuer, on: o)
            return yes(o)
        case .peace(let o):
            guard atWar(cmd.issuer, o) else { return no("not_at_war") }
            makePeace(cmd.issuer, o)
            return yes(o)
        }
    }

    // MARK: - reservations

    /// Hold a stage's materials for a project if the city has them free: nothing else may spend them.
    func reserveNextStage(_ id: Int) {
        guard var p = projects[id], p.held.isEmpty, !p.taken, let d = CivUnitDef.byKey[p.kind], p.stage < d.stages.count, let c = cities[p.city] else { return }
        let need = d.stages[p.stage]
        guard need.allSatisfy({ c.free($0.key) >= $0.value }) else { return }
        for (k, v) in need { c.reserved[k, default: 0] += v }
        p.held = need
        projects[id] = p
    }

    /// Give back what a project holds (cancelled, its city lost, or it has used it).
    func release(_ p: inout CivProject, from c: CivCity?) {
        if let c = c { for (k, v) in p.held { c.reserved[k] = max(0, (c.reserved[k] ?? 0) - v); if c.reserved[k] == 0 { c.reserved[k] = nil } } }
        p.held = [:]
    }
}
