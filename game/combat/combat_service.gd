class_name CombatService
extends RefCounted
## CombatService: one data-driven skill runner shared by the player, enemies
## and the boss, plus damage resolution, projectiles and status effects.
## No per-skill code paths: behaviour comes from content/skills/skills.json.

const HITSTUN := 0.22
const PLAYER_MERCY := 0.45

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var bus: EventBus
var rng := RandomNumberGenerator.new()
var on_harvest: Callable = Callable()       # (actor, skill) tool swings hit terrain
var on_death: Callable = Callable()         # (entity, killer)
var player_defense: Callable = Callable()   # () -> float


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_bus: EventBus) -> void:
	content = p_content
	world = p_world
	entities = p_entities
	bus = p_bus


static func hostile(a: Entity, b: Entity) -> bool:
	if a == b or b.kind == "npc" or a.kind == "npc":
		return false
	if a.team == b.team:
		return false
	# monsters and wildlife ignore each other
	return a.team == Entity.TEAM_PLAYER or b.team == Entity.TEAM_PLAYER


func cooldown_left(e: Entity, skill_id: String) -> float:
	return maxf(0.0, float(e.cooldowns.get(skill_id, 0.0)) - world.time_real)


func skill_ready(e: Entity, skill_id: String) -> bool:
	return e.skill_phase == Entity.PH_NONE and e.stun <= 0.0 and e.stagger <= 0.0 and cooldown_left(e, skill_id) <= 0.0


## Begin a skill. `power` is the attacker's base damage (weapon or actor def).
func start_skill(e: Entity, skill_id: String, dir: Vector2, power: float) -> bool:
	if not content.skills.has(skill_id) or not skill_ready(e, skill_id):
		return false
	var s: Dictionary = content.skills[skill_id]
	e.skill = s
	e.skill_phase = Entity.PH_WINDUP
	e.skill_t = 0.0
	e.skill_dir = dir.normalized() if dir.length_squared() > 0.0001 else e.facing
	e.facing = e.skill_dir
	e.skill_power = power
	e.cooldowns[skill_id] = world.time_real + float(s.get("cooldown", 0.0)) + float(s["windup"]) + float(s["active"])
	bus.sfx.emit(str(s.get("sfx", "")), e.pos)
	return true


func cancel_skill(e: Entity) -> void:
	e.skill = {}
	e.skill_phase = Entity.PH_NONE
	e.skill_t = 0.0


## Advance the running skill of an entity by dt.
func update_skill(e: Entity, dt: float) -> void:
	if e.skill_phase == Entity.PH_NONE:
		return
	var s := e.skill
	e.skill_t += dt
	match e.skill_phase:
		Entity.PH_WINDUP:
			if e.skill_t >= float(s["windup"]):
				e.skill_t -= float(s["windup"])
				e.skill_phase = Entity.PH_ACTIVE
				_fire(e, s)
		Entity.PH_ACTIVE:
			var lunge := float(s.get("lunge", 0.0))
			if lunge > 0.0:
				e.pos = world.move(e.pos, e.skill_dir * lunge * dt / maxf(float(s["active"]), 0.01), e.radius)
			if e.skill_t >= float(s["active"]):
				e.skill_t -= float(s["active"])
				e.skill_phase = Entity.PH_RECOVERY
		Entity.PH_RECOVERY:
			if e.skill_t >= float(s["recovery"]):
				e.skill_phase = Entity.PH_NONE
				e.skill_t = 0.0
				e.ai["last_skill"] = str(s["id"])
				e.ai["last_skill_end"] = world.time_real


func shape_center(e: Entity, s: Dictionary) -> Vector2:
	var sh: Dictionary = s["shape"]
	return e.pos + e.skill_dir * float(sh.get("offset", 0.0))


## Pure geometry test, used by hit resolution, AI range checks and tests.
static func shape_hits(origin: Vector2, dir: Vector2, shape: Dictionary, target: Vector2, target_r: float) -> bool:
	match str(shape["type"]):
		"arc":
			var to := target - origin
			var d := to.length()
			if d > float(shape["range"]) + target_r:
				return false
			if d < 0.001:
				return true
			var half := deg_to_rad(float(shape["angle"])) * 0.5
			# widen the cone by the target's angular size
			var extra := asin(clampf(target_r / d, 0.0, 1.0))
			return absf(dir.angle_to(to)) <= half + extra
		"circle":
			var c := origin + dir * float(shape.get("offset", 0.0))
			return c.distance_to(target) <= float(shape["radius"]) + target_r
	return false


func _fire(e: Entity, s: Dictionary) -> void:
	var sh: Dictionary = s["shape"]
	var type := str(sh["type"])
	if s.has("fx"):
		bus.fx.emit(str(s["fx"]), shape_center(e, s), {"dir": e.skill_dir, "shape": sh})
	match type:
		"projectile":
			var count := int(sh.get("count", 1))
			var spread := deg_to_rad(float(sh.get("spread", 0.0)))
			for i in count:
				var a := 0.0
				if count > 1:
					a = -spread * 0.5 + spread * (float(i) / float(count if spread >= TAU - 0.01 else count - 1))
				_spawn_projectile(e, s, e.skill_dir.rotated(a))
		"summon":
			for i in int(sh.get("count", 1)):
				var ang := rng.randf() * TAU
				var p := e.pos + Vector2(cos(ang), sin(ang)) * float(sh.get("radius", 40.0))
				var t := world.find_free_near(MP.tile_of(p), 4)
				var m := entities.spawn_actor(str(sh["def"]), MP.tile_center(t), e.site)
				m.data["transient"] = true
				m.ai["angry"] = true
				bus.fx.emit("summon", m.pos, {})
		_:
			for t in entities.actors.duplicate():
				if not t.alive or not hostile(e, t):
					continue
				if shape_hits(e.pos, e.skill_dir, sh, t.pos, t.radius):
					apply_hit(e, t, s, e.skill_power, (t.pos - e.pos).normalized() if t.pos != e.pos else e.skill_dir)
			if int(s.get("harvest", 0)) == 1 and on_harvest.is_valid():
				on_harvest.call(e, s)


func _spawn_projectile(owner: Entity, s: Dictionary, dir: Vector2) -> void:
	var sh: Dictionary = s["shape"]
	var p := Entity.new()
	p.kind = "projectile"
	p.def_id = str(sh.get("sprite", "arrow"))
	p.pos = owner.pos + dir * (owner.radius + 4.0)
	p.facing = dir
	p.radius = float(sh.get("radius", 3.0))
	p.team = owner.team
	p.data = {"owner": owner.id, "skill": s["id"], "power": owner.skill_power, "speed": float(sh["speed"]),
		"life": float(sh.get("life", 1.5)), "pierce": int(sh.get("pierce", 0)), "hit": {}}
	entities.add(p)


func update_projectiles(dt: float) -> void:
	for p in entities.projectiles.duplicate():
		if p.remove:
			continue
		p.prev_pos = p.pos
		var d: Dictionary = p.data
		d["life"] = float(d["life"]) - dt
		var step: Vector2 = p.facing * float(d["speed"]) * dt
		var n := maxi(1, ceili(step.length() / 6.0))
		var dead := float(d["life"]) <= 0.0
		for i in n:
			if dead:
				break
			p.pos += step / n
			var tl := MP.tile_of(p.pos)
			if _shot_blocked(tl.x, tl.y):
				bus.fx.emit("spark", p.pos, {})
				dead = true
				break
			for t in entities.actors:
				if not t.alive or t.kind == "npc" or d["hit"].has(t.id):
					continue
				if t.team == p.team or (t.team != Entity.TEAM_PLAYER and p.team != Entity.TEAM_PLAYER):
					continue
				if t.pos.distance_squared_to(p.pos) <= (t.radius + p.radius) * (t.radius + p.radius):
					d["hit"][t.id] = true
					var owner := entities.get_entity(int(d["owner"]))
					_hit_from(owner, p.team, t, content.skills[d["skill"]], float(d["power"]), p.facing)
					if int(d["pierce"]) <= 0:
						dead = true
						break
					d["pierce"] = int(d["pierce"]) - 1
		if dead:
			p.remove = true


func _shot_blocked(tx: int, ty: int) -> bool:
	if not world.in_bounds(tx, ty):
		return true
	var o := world.tile(MP.L_OBJECT, tx, ty)
	if o != 0 and content.t_solid[o] != 0:
		var t: Dictionary = content.tiles[o]
		if t.get("tall", 0) == 1 or t.get("big", 0) == 1:
			return true
	return content.t_solid[world.tile(MP.L_STRUCT, tx, ty)] != 0


func apply_hit(attacker: Entity, target: Entity, s: Dictionary, power: float, dir: Vector2) -> float:
	return _hit_from(attacker, attacker.team, target, s, power, dir)


## Damage formula (documented in docs/gameplay/combat.md):
##   raw   = power * skill.dmg * attacker_phase_mult
##   final = max(1, raw - defense) * difficulty(if target is player) * stagger_bonus
func compute_damage(attacker: Entity, target: Entity, s: Dictionary, power: float) -> float:
	var raw := power * float(s.get("dmg", 1.0))
	if attacker != null and attacker.phase > 0:
		var phases: Array = attacker.def.get("phases", [])
		if attacker.phase - 1 < phases.size():
			raw *= float(phases[attacker.phase - 1].get("damage_mult", 1.0))
	var defense := float(target.def.get("defense", 0.0))
	if target.kind == "player" and player_defense.is_valid():
		defense = float(player_defense.call())
	var final := maxf(1.0, raw - defense)
	if target.kind == "player":
		final *= float(world.rule("difficulty"))
	if target.stagger > 0.0:
		final *= float(target.def.get("stagger_bonus", 1.25))
	return final


func _hit_from(attacker: Entity, _team: int, target: Entity, s: Dictionary, power: float, dir: Vector2) -> float:
	if not target.alive:
		return 0.0
	if target.kind == "player" and not bool(world.rule("combat")):
		return 0.0
	if target.iframes > 0.0:
		bus.fx.emit("dodge", target.pos, {})
		return 0.0
	if float(s.get("dmg", 1.0)) <= 0.0:
		return 0.0
	var dmg := compute_damage(attacker, target, s, power)
	target.hp -= dmg
	target.hit_flash = 0.15
	var tough: bool = target.max_poise > 0.0 and (target.def.get("behavior", "") == "elite" or target.def.get("behavior", "") == "boss")
	var kb := float(s.get("knockback", 0.0))
	if tough and target.stagger <= 0.0:
		kb *= 0.25
	target.vel += dir * kb
	if target.max_poise > 0.0 and target.stagger <= 0.0:
		target.poise -= float(s.get("poise", 0.0))
		if target.poise <= 0.0:
			target.poise = target.max_poise
			target.stagger = float(target.def.get("stagger_time", 1.0))
			cancel_skill(target)
			bus.fx.emit("stagger", target.pos, {})
			if target.def.get("behavior", "") == "boss":
				bus.boss_state.emit("stagger", target)
	if target.kind == "player":
		target.stun = maxf(target.stun, HITSTUN)
		target.iframes = maxf(target.iframes, PLAYER_MERCY)
		cancel_skill(target)
	elif not tough:
		target.stun = maxf(target.stun, HITSTUN)
		cancel_skill(target)
	if s.has("status"):
		add_status(target, s["status"])
	if target.kind != "player":
		target.ai["angry"] = true
		if attacker != null:
			target.ai["target"] = attacker.id
	bus.entity_damaged.emit(target, dmg, attacker)
	bus.fx.emit("hit", target.pos, {"amount": dmg, "dir": dir})
	bus.sfx.emit("hit", target.pos)
	if target.hp <= 0.0:
		kill(target, attacker)
	return dmg


func add_status(e: Entity, st: Dictionary) -> void:
	for s in e.statuses:
		if s["type"] == st["type"]:
			s["time"] = maxf(float(s["time"]), float(st["time"]))
			s["power"] = st["power"]
			return
	e.statuses.append({"type": st["type"], "time": float(st["time"]), "power": float(st["power"]), "acc": 0.0})
	if st["type"] == "freeze":
		e.stun = maxf(e.stun, float(st["time"]))


func update_statuses(e: Entity, dt: float) -> void:
	if e.iframes > 0.0:
		e.iframes -= dt
	if e.stun > 0.0:
		e.stun -= dt
	if e.stagger > 0.0:
		e.stagger -= dt
	if e.hit_flash > 0.0:
		e.hit_flash -= dt
	if e.statuses.is_empty():
		return
	for i in range(e.statuses.size() - 1, -1, -1):
		var s: Dictionary = e.statuses[i]
		s["time"] = float(s["time"]) - dt
		if s["type"] == "burn" or s["type"] == "poison":
			s["acc"] = float(s["acc"]) + dt
			while float(s["acc"]) >= 0.5 and e.alive:
				s["acc"] = float(s["acc"]) - 0.5
				if e.kind == "player" and not bool(world.rule("combat")):
					continue
				var dmg := float(s["power"]) * 0.5
				if e.kind == "player":
					dmg *= float(world.rule("difficulty"))
				e.hp -= dmg
				bus.fx.emit(str(s["type"]), e.pos, {"amount": dmg})
				if e.hp <= 0.0:
					kill(e, null)
		if float(s["time"]) <= 0.0:
			e.statuses.remove_at(i)


func kill(e: Entity, killer: Entity) -> void:
	if not e.alive:
		return
	e.alive = false
	e.hp = 0.0
	cancel_skill(e)
	e.statuses.clear()
	bus.entity_died.emit(e, killer)
	bus.fx.emit("death", e.pos, {"kind": e.kind})
	if e.kind != "player":
		e.state = "dead"
		e.state_t = 0.0
	if on_death.is_valid():
		on_death.call(e, killer)


## Integrate knockback velocity with friction.
func integrate(e: Entity, dt: float) -> void:
	if e.vel.length_squared() > 1.0:
		e.pos = world.move(e.pos, e.vel * dt, e.radius)
		e.vel = e.vel.move_toward(Vector2.ZERO, 900.0 * dt)
	else:
		e.vel = Vector2.ZERO
