import Foundation

// How a person moves in the solid world: walking, jumping, falling, landing, riding a moving floor.
//
// Units: x and y are the simulation's own (16 per tile, the same as `Vec2` everywhere else); z is height
// in tiles (one tile up = 1.0), the same units the 3D view uses. A layer (`depth`) is the floor a body
// stands on or falls above: 0 the ground, 100 + n storey n (1 is the underground, which has no storeys).
// The body never stores a floor's height: it is read from the world every step, so building or taking
// down a floor under someone's feet is noticed at once.
//
// Steps are fixed (`MotionConfig.substep`); a frame of any length is cut into them, so how high a jump
// goes never depends on the frame rate. A falling body can never pass a floor in one step (the fall speed
// is capped well below a storey per step), and only the storey it is passing is looked at, so a fall from
// the 900th storey costs the same per step as a fall from the first.

public enum BodyState: String, Codable, Equatable { case standing, walking, rising, falling, riding }

public struct Body: Codable, Equatable {
    public var x = 0.0, y = 0.0, z = 0.0
    public var vx = 0.0, vy = 0.0, vz = 0.0
    public var state = BodyState.standing
    public var depth = 0
    /// The moving floor (an elevator car) carrying the body, if any.
    public var platform: Int?
    /// Jump pressed this long ago and not yet used (a short input buffer).
    public var buffer = 0.0
    /// Seconds since the feet last touched something (a short grace for a jump just after a ledge).
    public var sinceGround = 0.0
    /// Landings so far (each one settles its damage once).
    public var landings = 0
    /// Time not yet stepped (less than one substep): only whole steps are ever taken.
    public var acc = 0.0
    /// The vehicle the body is in (v2.7): then `lx`, `ly` are where it stands inside (tiles forward and to
    /// the right of the vehicle's middle), `z` is above the vehicle's floor, and the world position follows it.
    public var vehicle: Int?
    public var lx: Double?, ly: Double?, lz: Double?
    /// The seat taken (0: the driver's); nil while standing.
    public var seat: Int?
    /// A parachute open: the fall is slow and steerable, and the landing does no harm.
    public var chute: Bool?
    public init() {}
    public init(at p: Vec2, z: Double, depth: Int) { x = p.x; y = p.y; self.z = z; self.depth = depth }
    public var pos: Vec2 { get { Vec2(x, y) } set { x = newValue.x; y = newValue.y } }
    public var grounded: Bool { state == .standing || state == .walking || state == .riding }
    public var airborne: Bool { state == .rising || state == .falling }
}

public struct MotionConfig: Codable, Equatable {
    public var gravity = 22.0              // tiles / s^2
    public var jumpSpeed = 7.0             // tiles / s: about 1.1 tiles high on open ground
    public var height = 1.5                // head above feet, tiles (a storey is 2 tiles: indoors a small hop)
    public var airControl = 4.0            // how fast the air speed turns towards the stick (1/s)
    public var maxFall = 28.0              // tiles / s: never more than 0.25 tiles a step
    public var safeImpact = 10.5           // tiles / s of landing speed before it hurts (a drop of ~2.5 tiles: one storey is safe, two are not)
    public var damagePerImpact2 = 0.9      // hp per (tiles/s)^2 beyond the safe speed
    public var buffer = 0.12, coyote = 0.10 // seconds
    public var stepUp = 0.55               // tiles: a kerb or a stair step is walked up, a wall is not
    public var slab = 0.25                 // thickness of a storey's floor, tiles
    public var substep = 1.0 / 120
    public var maxFrame = 0.25             // a frame longer than this is cut short (the body waits, it does not teleport)
    public init() {}
}

/// A floor that moves: an elevator car, as the elevator system reports it for this step.
public struct Platform: Equatable {
    public var id: Int
    /// Inside of the car, in simulation units.
    public var minX: Double, minY: Double, maxX: Double, maxY: Double
    public var floorZ: Double
    public var vz: Double
    /// The car stands still at a landing with its doors open: one may walk out onto `stopDepth`.
    public var open: Bool
    public var stopDepth: Int?
    public init(id: Int, minX: Double, minY: Double, maxX: Double, maxY: Double, floorZ: Double, vz: Double, open: Bool, stopDepth: Int?) {
        self.id = id; self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY; self.floorZ = floorZ; self.vz = vz; self.open = open; self.stopDepth = stopDepth
    }
    public func contains(_ x: Double, _ y: Double) -> Bool { x >= minX && x <= maxX && y >= minY && y <= maxY }
}

/// What the body asks of the world. `Society` answers from its layers; tests answer from a small model.
public protocol MotionGround {
    /// Top of the floor of this layer at this tile, or nil where there is none (open air on a storey).
    func floor(_ depth: Int, _ t: TilePos) -> Double?
    /// Height a floor of this layer would have at this tile (where a fall passes from this layer to the next one down).
    func nominal(_ depth: Int, _ t: TilePos) -> Double
    /// A wall or anything solid stands on this tile of this layer.
    func blocked(_ depth: Int, _ t: TilePos) -> Bool
    /// The layer under / over this one (nil: none).
    func below(_ depth: Int) -> Int?
    func above(_ depth: Int) -> Int?
}

public struct MotionStep: Equatable {
    public var landed = false
    /// Damage from the landing of this step (settled once, here, and never again for that fall).
    public var damage = 0.0
    public var impact = 0.0
    public var depthChanged = false
    /// Highest point the feet reached during this advance (over every substep, not just at its end).
    public var peak = -Double.infinity
    public var leftPlatform: Int?
    public var boarded: Int?
    public init() {}
}

public enum Motion {
    /// Advance a body by `dt` seconds of real time with this stick (`wish`, simulation units per second)
    /// and jump button (`jump`: pressed this frame). Returns what happened, summed over the substeps.
    public static func advance(_ b: inout Body, dt: Double, wish: Vec2, jump: Bool, ground g: MotionGround,
                               platforms: [Platform] = [], cfg: MotionConfig = MotionConfig()) -> MotionStep {
        var out = MotionStep()
        if jump { b.buffer = cfg.buffer + b.acc }
        b.acc += min(dt, cfg.maxFrame)
        while b.acc >= cfg.substep - 1e-12 {
            b.acc -= cfg.substep
            let r = step(&b, h: cfg.substep, wish: wish, ground: g, platforms: platforms, cfg: cfg)
            if r.landed { out.landed = true; out.damage += r.damage; out.impact = max(out.impact, r.impact) }
            if r.depthChanged { out.depthChanged = true }
            out.peak = max(out.peak, b.z)
            if let p = r.leftPlatform { out.leftPlatform = p }
            if let p = r.boarded { out.boarded = p }
        }
        return out
    }

    static func tile(_ x: Double, _ y: Double) -> TilePos { TilePos(Int((x / 16).rounded(.down)), Int((y / 16).rounded(.down))) }

    static func step(_ b: inout Body, h: Double, wish: Vec2, ground g: MotionGround, platforms: [Platform], cfg: MotionConfig) -> MotionStep {
        var out = MotionStep()
        b.buffer = max(0, b.buffer - h)
        let car = b.platform.flatMap { id in platforms.first { $0.id == id } }
        if b.platform != nil && car == nil {
            // the car is gone (taken down, or no longer reported): the body is in the air where it was
            b.platform = nil; b.state = .falling; out.leftPlatform = -1
        }

        // --- jump: from the ground, from a car (keeping its speed, once), or just after leaving a ledge
        let canJump = b.grounded || (b.state == .falling && b.sinceGround < cfg.coyote && b.vz <= 0)
        if b.buffer > 0 && canJump {
            b.vz = cfg.jumpSpeed + (car?.vz ?? 0)
            if car != nil { out.leftPlatform = b.platform; b.platform = nil }
            b.state = .rising
            b.buffer = 0
            b.sinceGround = cfg.coyote           // no second jump from the same ledge
        }

        // --- horizontal: full control on a floor, some in the air
        if b.airborne {
            let k = min(1, cfg.airControl * (b.chute == true ? 2 : 1) * h)
            b.vx += (wish.x - b.vx) * k; b.vy += (wish.y - b.vy) * k
        } else { b.vx = wish.x; b.vy = wish.y }
        for axis in 0..<2 {
            let nx = axis == 0 ? b.x + b.vx * h : b.x, ny = axis == 1 ? b.y + b.vy * h : b.y
            if nx == b.x && ny == b.y { continue }
            if let c = car, b.state == .riding {
                if c.contains(nx, ny) { b.x = nx; b.y = ny; continue }
                // out through the open door onto the landing it stands at, if there is floor there level with it
                if c.open, let d = c.stopDepth, let f = g.floor(d, tile(nx, ny)), abs(f - c.floorZ) <= cfg.stepUp, !g.blocked(d, tile(nx, ny)) {
                    b.x = nx; b.y = ny; b.depth = d; b.z = f; b.platform = nil; b.state = .walking
                    out.leftPlatform = c.id; out.depthChanged = true
                }
                continue                                                   // the car's walls (or a closed door)
            }
            let t = tile(nx, ny)
            if t != tile(b.x, b.y) {
                if g.blocked(b.depth, t) { continue }
                if let f = g.floor(b.depth, t), f > b.z + cfg.stepUp { continue }     // a step too high to walk up
                // into a car standing open at this layer
                if let c = platforms.first(where: { $0.contains(nx, ny) && $0.open && $0.stopDepth == b.depth && abs($0.floorZ - b.z) <= cfg.stepUp }), b.grounded {
                    b.x = nx; b.y = ny; b.platform = c.id; b.state = .riding; b.z = c.floorZ; out.boarded = c.id
                    continue
                }
            }
            b.x = nx; b.y = ny
        }

        // --- vertical
        let t = tile(b.x, b.y)
        switch b.state {
        case .riding:
            if let c = car { b.z = c.floorZ; b.vz = c.vz }
            b.sinceGround = 0
        case .standing, .walking:
            if let f = g.floor(b.depth, t), f >= b.z - cfg.stepUp {
                b.z = f; b.vz = 0; b.sinceGround = 0
                b.state = (b.vx == 0 && b.vy == 0) ? .standing : .walking
            } else {
                b.state = .falling; b.vz = 0                             // off the edge, or the floor is gone
            }
        case .rising, .falling:
            b.sinceGround += h
            let from = b.z
            // under a parachute: about 4 m a second down at most
            b.vz = max(b.vz - cfg.gravity * h, b.chute == true ? -Motion.chuteFall : -cfg.maxFall)
            var nz = b.z + b.vz * h
            // the floor of the layer above is a ceiling
            if b.vz > 0, let up = g.above(b.depth), let f = g.floor(up, t), nz + cfg.height > f - cfg.slab {
                nz = max(from, f - cfg.slab - cfg.height); b.vz = 0
            }
            if b.vz <= 0 { b.state = .falling }
            // a car under the feet
            if b.vz <= 0, let c = platforms.first(where: { $0.contains(b.x, b.y) && from >= $0.floorZ - 1e-6 && nz <= $0.floorZ + max(0, $0.vz) * h + 1e-6 }) {
                out = land(&b, at: c.floorZ, surfaceVz: c.vz, cfg: cfg, out)
                b.platform = c.id; b.state = .riding; out.boarded = c.id
                return out
            }
            // the floor of this layer, or (once below where it would be) the layer under it
            if let f = g.floor(b.depth, t), b.vz <= 0, from >= f - 1e-6, nz <= f {
                out = land(&b, at: f, surfaceVz: 0, cfg: cfg, out)
                return out
            }
            b.z = nz
            if g.floor(b.depth, t) == nil, let down = g.below(b.depth), nz < g.nominal(b.depth, t) {
                b.depth = down; out.depthChanged = true
            }
            // the bottom of the world (the ground is always there; this only catches impossible states)
            if b.depth == 0, let f = g.floor(0, t), b.z < f - 4 { out = land(&b, at: f, surfaceVz: 0, cfg: cfg, out) }
        }
        return out
    }

    /// The speed a parachute falls at, tiles a second.
    public static let chuteFall = 2.2

    static func land(_ b: inout Body, at f: Double, surfaceVz: Double, cfg: MotionConfig, _ o: MotionStep) -> MotionStep {
        var out = o
        let impact = b.chute == true ? 0 : max(0, surfaceVz - b.vz)
        b.chute = nil
        out.landed = true; out.impact = impact
        if impact > cfg.safeImpact { out.damage += (impact * impact - cfg.safeImpact * cfg.safeImpact) * cfg.damagePerImpact2 / 10 }
        b.z = f; b.vz = surfaceVz; b.sinceGround = 0
        b.state = (b.vx == 0 && b.vy == 0) ? .standing : .walking
        b.landings += 1
        return out
    }

    /// A body read from a save (or after a reset) that cannot be right: not a number, far outside the
    /// world, inside a wall, or below the floor it is meant to stand on. Returns the corrected body and
    /// why, or nil when it is fine. The place chosen is always the same for the same world: the nearest
    /// free floor at its layer, else the ground beneath it.
    public static func recover(_ b: Body, ground g: MotionGround, free: (Int, TilePos) -> TilePos?) -> (Body, String)? {
        let finite = [b.x, b.y, b.z, b.vx, b.vy, b.vz].allSatisfy { $0.isFinite }
        var r = b
        var why: String?
        if !finite || abs(b.x) > 1.6e7 || abs(b.y) > 1.6e7 {
            why = "position was not a valid place"
            r.x = finite && abs(b.x) <= 1.6e7 ? b.x : 0; r.y = finite && abs(b.y) <= 1.6e7 ? b.y : 0
            r.depth = 0
        }
        let t = tile(r.x, r.y)
        if why == nil, r.platform == nil, g.blocked(r.depth, t) { why = "inside something solid" }
        if why == nil, r.platform == nil, let f = g.floor(r.depth, t), r.z < f - 0.5 { why = "below the floor" }
        guard let reason = why else { return nil }
        let at = free(r.depth, t) ?? free(0, t) ?? t
        if free(r.depth, t) == nil { r.depth = 0 }
        r.x = Double(at.x * 16 + 8); r.y = Double(at.y * 16 + 8)
        r.z = g.floor(r.depth, at) ?? g.nominal(r.depth, at)
        r.vx = 0; r.vy = 0; r.vz = 0; r.state = .standing; r.platform = nil; r.buffer = 0; r.sinceGround = 0
        return (r, reason)
    }
}

// MARK: - the real world as ground

/// The layers of a `Society` as a ground to walk on. Heights are the same ones the 3D view draws.
public struct WorldGround: MotionGround {
    public let society: Society
    public init(_ s: Society) { society = s }
    func layer(_ d: Int) -> OpenWorld { society.layer(d) }
    public func floor(_ d: Int, _ t: TilePos) -> Double? {
        let w = layer(d)
        if d >= OpenWorld.storeyBase && w.tile(0, t.x, t.y) == 0 { return nil }
        return Double(Terrain3D.groundY(world: w, at: t.center))
    }
    public func nominal(_ d: Int, _ t: TilePos) -> Double {
        let w = layer(d)
        let lv = d == 1 ? 0 : Terrain3D.level(elevation: w.gen.elevation(t.x, t.y)) + w.storey * Terrain3D.storeyLevels
        return Double(Float(lv) * Terrain3D.step)
    }
    public func blocked(_ d: Int, _ t: TilePos) -> Bool {
        let w = layer(d)
        // open air is not a wall: one falls through it
        if d >= OpenWorld.storeyBase && w.tile(0, t.x, t.y) == 0 { return w.tile(2, t.x, t.y) != 0 && society.content.solid[Int(w.tile(2, t.x, t.y))] }
        return w.blocked(t.x, t.y)
    }
    public func below(_ d: Int) -> Int? {
        if d == 0 || d == 1 { return nil }
        let n = d - OpenWorld.storeyBase
        return n <= 1 ? 0 : d - 1
    }
    public func above(_ d: Int) -> Int? {
        if d == 1 { return nil }
        return d == 0 ? OpenWorld.storeyBase + 1 : d + 1
    }
}
