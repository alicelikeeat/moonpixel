class_name ActorAI
extends RefCounted
## State machine AI for enemies and wildlife.
## Behaviours (content `behavior`): melee | ranged | patrol | elite | boss for
## monsters, flee | defend for animals. Phase switching (elite/boss) and
## poise/stagger are generic and data driven.

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var combat: CombatService
var bus: EventBus
var rng := RandomNumberGenerator.new()
var boss_arena := Rect2()        # px rect; boss never leaves it


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_combat: CombatService, p_bus: EventBus) -> void:
	content = p_content
	world = p_world
	entities = p_entities
	combat = p_combat
	bus = p_bus


func _speed(e: Entity) -> float:
	var sp := float(e.def.get("speed", 40.0)) * e.speed_mult()
	if e.phase > 0:
		var phases: Array = e.def.get("phases", [])
		if e.phase - 1 < phases.size():
			sp *= float(phases[e.phase - 1].get("speed_mult", 1.0))
	var t := MP.tile_of(e.pos)
	return sp * world.walk_speed(t.x, t.y)


## Steering with a simple wall-slide escape: if progress stalls, sidestep.
func _move_toward(e: Entity, target: Vector2, speed: float, dt: float) -> void:
	var to := target - e.pos
	if to.length_squared() < 1.0:
		e.move_dir = Vector2.ZERO
		return
	var dir := to.normalized()
	var side_t := float(e.ai.get("side_t", 0.0))
	if side_t > 0.0:
		e.ai["side_t"] = side_t - dt
		dir = (dir + dir.orthogonal() * float(e.ai.get("side", 1.0)) * 1.6).normalized()
	var before := e.pos
	e.pos = world.move(e.pos, dir * speed * dt, e.radius)
	var moved := e.pos.distance_to(before)
	if moved < speed * dt * 0.35:
		e.ai["stuck"] = float(e.ai.get("stuck", 0.0)) + dt
		if float(e.ai["stuck"]) > 0.25 and side_t <= 0.0:
			e.ai["side_t"] = 0.6
			e.ai["side"] = 1.0 if rng.randf() < 0.5 else -1.0
			e.ai["stuck"] = 0.0
	else:
		e.ai["stuck"] = 0.0
	e.move_dir = dir
	e.facing = dir


func _skills(e: Entity) -> Array:
	if e.phase > 0:
		var phases: Array = e.def.get("phases", [])
		if e.phase - 1 < phases.size() and phases[e.phase - 1].has("skills"):
			return phases[e.phase - 1]["skills"]
	return e.def.get("skills", [])


func _skill_reach(s: Dictionary) -> float:
	var sh: Dictionary = s["shape"]
	match str(sh["type"]):
		"arc": return float(sh["range"]) + float(s.get("lunge", 0.0)) * 0.7
		"circle": return float(sh["radius"]) * 0.8 + float(sh.get("offset", 0.0)) + float(s.get("lunge", 0.0)) * 0.7
		"projectile": return float(sh["speed"]) * float(sh.get("life", 1.0)) * 0.7
	return 9999.0


func _check_phase(e: Entity) -> void:
	var phases: Array = e.def.get("phases", [])
	while e.phase < phases.size() and e.hp / e.max_hp <= float(phases[e.phase]["below"]):
		e.phase += 1
		bus.fx.emit(str(phases[e.phase - 1].get("fx", "enrage")), e.pos, {})
		if e.def.get("behavior", "") == "boss":
			bus.boss_state.emit("phase", e)


func update(e: Entity, player: Entity, dt: float) -> void:
	if not e.alive:
		e.state_t += dt
		if e.state_t > 0.6:
			e.remove = true
		return
	e.state_t += dt
	_check_phase(e)
	if e.stagger > 0.0:
		e.state = "stagger"
		e.move_dir = Vector2.ZERO
		return
	if e.stun > 0.0:
		e.state = "hurt"
		e.move_dir = Vector2.ZERO
		return
	if e.skill_phase != Entity.PH_NONE:
		e.state = "attack"
		e.move_dir = Vector2.ZERO
		return
	match str(e.def.get("behavior", "melee")):
		"flee": _animal_flee(e, player, dt)
		"defend":
			if bool(e.ai.get("angry", false)):
				_hostile(e, player, dt, "melee")
			else:
				_wander(e, dt, 48.0)
		"ranged": _hostile(e, player, dt, "ranged")
		"patrol": _hostile(e, player, dt, "patrol")
		_: _hostile(e, player, dt, "melee")


func _can_see(e: Entity, player: Entity) -> bool:
	if player == null or not player.alive or not bool(world.rule("combat")):
		return false
	var sight := float(e.def.get("sight", 100.0))
	if bool(e.ai.get("angry", false)):
		sight *= 1.6
	var d := e.pos.distance_to(player.pos)
	if d > sight:
		return false
	return d < 40.0 or world.line_clear(e.pos, player.pos)


func _hostile(e: Entity, player: Entity, dt: float, mode: String) -> void:
	var boss := str(e.def.get("behavior", "")) == "boss"
	var leash := float(e.def.get("leash", 240.0))
	var sees := _can_see(e, player)
	var chasing := bool(e.ai.get("chasing", false))
	if sees:
		chasing = true
		e.ai["lost_t"] = 0.0
	elif chasing:
		e.ai["lost_t"] = float(e.ai.get("lost_t", 0.0)) + dt
		if float(e.ai["lost_t"]) > 3.0:
			chasing = false
	if chasing and (player == null or not player.alive or e.pos.distance_to(e.home) > leash):
		chasing = false
		e.ai["angry"] = false
	e.ai["chasing"] = chasing
	if not chasing:
		# leash / idle behaviour; out-of-combat regeneration
		if e.hp < e.max_hp and not boss:
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.1 * dt)
		if e.pos.distance_to(e.home) > 24.0 and mode != "patrol":
			e.state = "return"
			_move_toward(e, e.home, _speed(e), dt)
		elif mode == "patrol":
			_patrol(e, dt)
		else:
			_wander(e, dt, 40.0)
		return
	var to := player.pos - e.pos
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	e.facing = dir
	# pause between attacks so fights have readable rhythm
	var rest := 0.35 if not boss else 0.6
	var resting := world.time_real - float(e.ai.get("last_skill_end", -10.0)) < rest
	if not resting:
		var options: Array = []
		for sid in _skills(e):
			var s: Dictionary = content.skills[sid]
			if combat.cooldown_left(e, sid) > 0.0:
				continue
			var stype := str(s["shape"]["type"])
			if stype == "summon":
				if entities.count_kind("enemy") < 6:
					options.append(sid)
				continue
			if dist - player.radius <= _skill_reach(s):
				if stype != "projectile" or world.line_clear(e.pos, player.pos):
					options.append(sid)
		if options.size() > 0:
			var pick: String = options[rng.randi() % options.size()]
			if combat.start_skill(e, pick, dir, float(e.def.get("damage", 5.0))):
				e.state = "attack"
				e.move_dir = Vector2.ZERO
				return
	e.state = "chase"
	var sp := _speed(e)
	if mode == "ranged":
		var pref := float(e.def.get("prefer_range", 90.0))
		if dist < pref * 0.6:
			_move_toward(e, e.pos - dir * 32.0, sp, dt)
			e.facing = dir
		elif dist > pref * 1.15 or not world.line_clear(e.pos, player.pos):
			_move_toward(e, player.pos, sp, dt)
		else:
			# strafe
			var side := 1.0 if (e.id % 2) == 0 else -1.0
			_move_toward(e, e.pos + dir.orthogonal() * side * 24.0, sp * 0.5, dt)
			e.facing = dir
	else:
		if dist > e.radius + player.radius + 4.0:
			_move_toward(e, player.pos, sp, dt)
		else:
			e.move_dir = Vector2.ZERO
	if boss and boss_arena.size.x > 0.0:
		e.pos.x = clampf(e.pos.x, boss_arena.position.x + e.radius, boss_arena.end.x - e.radius)
		e.pos.y = clampf(e.pos.y, boss_arena.position.y + e.radius, boss_arena.end.y - e.radius)


func _wander(e: Entity, dt: float, radius: float) -> void:
	var t := float(e.ai.get("wander_t", 0.0)) - dt
	if t <= 0.0:
		t = rng.randf_range(1.5, 4.0)
		if rng.randf() < 0.55:
			var ang := rng.randf() * TAU
			e.ai["wander_to"] = e.home + Vector2(cos(ang), sin(ang)) * rng.randf_range(8.0, radius)
		else:
			e.ai.erase("wander_to")
	e.ai["wander_t"] = t
	if e.ai.has("wander_to"):
		var target: Vector2 = e.ai["wander_to"]
		if e.pos.distance_to(target) > 3.0:
			e.state = "walk"
			_move_toward(e, target, _speed(e) * 0.45, dt)
			return
		e.ai.erase("wander_to")
	e.state = "idle"
	e.move_dir = Vector2.ZERO


func _patrol(e: Entity, dt: float) -> void:
	if not e.ai.has("route"):
		var pr := float(e.def.get("patrol_radius", 64.0))
		var route: Array = []
		for i in 4:
			var ang := TAU * (float(i) / 4.0) + MP.h01(e.id, i, 3) * 1.2
			var p := e.home + Vector2(cos(ang), sin(ang)) * pr * (0.5 + 0.5 * MP.h01(e.id, i, 5))
			route.append(MP.tile_center(world.find_free_near(MP.tile_of(p), 3)))
		e.ai["route"] = route
		e.ai["route_i"] = 0
	var route: Array = e.ai["route"]
	var target: Vector2 = route[int(e.ai["route_i"]) % route.size()]
	var wait := float(e.ai.get("wait", 0.0))
	if wait > 0.0:
		e.ai["wait"] = wait - dt
		e.state = "idle"
		e.move_dir = Vector2.ZERO
		return
	e.state = "patrol"
	if e.pos.distance_to(target) < 6.0 or float(e.ai.get("stuck_total", 0.0)) > 3.0:
		e.ai["route_i"] = int(e.ai["route_i"]) + 1
		e.ai["wait"] = 1.0
		e.ai["stuck_total"] = 0.0
		return
	var before := e.pos
	_move_toward(e, target, _speed(e) * 0.5, dt)
	if e.pos.distance_to(before) < 0.2:
		e.ai["stuck_total"] = float(e.ai.get("stuck_total", 0.0)) + dt


func _animal_flee(e: Entity, player: Entity, dt: float) -> void:
	var active := str(e.def.get("active", "any"))
	var night := world.is_night()
	var awake := active == "any" or (active == "night") == night
	var threat := player != null and player.alive and e.pos.distance_to(player.pos) < float(e.def.get("sight", 70.0))
	if bool(e.ai.get("angry", false)):
		threat = threat or float(e.ai.get("flee_t", 0.0)) > 0.0
	if threat or float(e.ai.get("flee_t", 0.0)) > 0.0:
		if threat:
			e.ai["flee_t"] = 1.5
		else:
			e.ai["flee_t"] = float(e.ai["flee_t"]) - dt
		var away := (e.pos - player.pos).normalized() if player != null else Vector2.RIGHT
		e.state = "flee"
		_move_toward(e, e.pos + away * 48.0, _speed(e), dt)
		# migrate home so the animal does not run back into the player
		if e.pos.distance_to(e.home) > 96.0:
			e.home = e.pos
		return
	if not awake:
		e.state = "sleep"
		e.move_dir = Vector2.ZERO
		return
	_wander(e, dt, 56.0)
