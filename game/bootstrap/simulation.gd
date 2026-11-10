class_name Simulation
extends RefCounted
## Fixed-step world simulation (MP.SIM_DT). Rendering is decoupled: views
## interpolate between prev_pos and pos. Entities are updated in distance
## tiers; far chunks are dormant.

var ctx: GameContext
var input := PlayerController.InputState.new()
var tick_i := 0
var last_chunk := Vector2i(-9999, -9999)
var boss_id := 0
var _slow := 0.0


func _init(p_ctx: GameContext) -> void:
	ctx = p_ctx
	ctx.combat.on_death = _on_death
	ctx.player.on_altar = summon_boss
	ctx.bus.player_respawned.connect(_on_respawn)


func tick(dt: float = MP.SIM_DT) -> void:
	tick_i += 1
	var world := ctx.world
	var ents := ctx.entities
	var combat := ctx.combat
	world.advance(dt)
	for e in ents.actors:
		e.prev_pos = e.pos
	var p := ctx.player.entity
	ctx.player.tick(dt, input)
	input.clear_edges()
	combat.update_statuses(p, dt)
	combat.update_skill(p, dt)
	combat.integrate(p, dt)
	var pc := Vector2i(floori(p.pos.x / MP.CHUNK_PX), floori(p.pos.y / MP.CHUNK_PX))
	if pc != last_chunk:
		last_chunk = pc
		ents.set_active_area(pc)
	for e in ents.actors.duplicate():
		if e.kind == "player" or e.kind == "npc" or e.remove:
			continue
		var tier := ents.tier_of(e, p.pos)
		e.acc_dt += dt
		if tier == 1 and (tick_i + e.id) % 3 != 0:
			continue
		if tier == 2 and (tick_i + e.id) % 10 != 0:
			continue
		var step: float = e.acc_dt
		e.acc_dt = 0.0
		combat.update_statuses(e, step)
		ctx.ai.update(e, p, step)
		combat.update_skill(e, step)
		combat.integrate(e, step)
	ctx.npcs.tick(dt)
	combat.update_projectiles(dt)
	_update_drops(dt)
	_slow += dt
	if _slow >= 0.5:
		_slow = 0.0
		_discover()
		_check_boss()
	ctx.ecology.tick(dt, p.pos, ctx.quests.state("q_star") == "available")
	ents.sweep()


func _update_drops(dt: float) -> void:
	var p := ctx.player.entity
	for d in ctx.entities.drops:
		if d.remove:
			continue
		d.prev_pos = d.pos
		var data: Dictionary = d.data
		data["age"] = float(data["age"]) + dt
		if float(data["age"]) > EntityService.DROP_LIFETIME:
			d.remove = true
			continue
		if not p.alive or float(data["age"]) < 0.35:
			continue
		var dist: float = d.pos.distance_to(p.pos)
		if dist < 34.0:
			if not ctx.player.bag.can_add(str(data["item"]), 1):
				continue
			d.pos = d.pos.move_toward(p.pos, 170.0 * dt)
			if dist < 10.0:
				var left := ctx.inventory.give_partial(ctx.player.bag, str(data["item"]), int(data["count"]), "pickup")
				if left != int(data["count"]):
					ctx.bus.sfx.emit("pickup", p.pos)
				data["count"] = left
				if left <= 0:
					d.remove = true


func _discover() -> void:
	var t := MP.tile_of(ctx.player.entity.pos)
	for s in ctx.world.plan.sites:
		if ctx.world.discovered.has(s["id"]):
			continue
		if t.x >= s["x"] - 5 and t.y >= s["y"] - 5 and t.x < s["x"] + s["w"] + 5 and t.y < s["y"] + s["h"] + 5:
			if ctx.world.discover(str(s["id"])) and s["type"] != "spawn":
				ctx.bus.toast.emit(Loc.t("discovered") + ctx.world.site_name(s))
				ctx.bus.sfx.emit("discover", ctx.player.entity.pos)


func _on_death(e: Entity, killer) -> void:
	if e.kind == "player":
		_despawn_boss()
		return
	var center := e.pos
	var mult := float(ctx.world.rule("resources"))
	for d in e.def.get("drops", []):
		if ctx.rng.randf() <= float(d[1]):
			var n := ctx.rng.randi_range(int(d[2]), int(d[3]))
			if float(d[1]) < 1.0 or int(d[3]) > 1:
				n = maxi(1, int(round(n * mult)))
			ctx.entities.spawn_drop(str(d[0]), n, center, 8.0)
	if killer == ctx.player.entity or (killer == null and int(e.ai.get("target", 0)) == ctx.player.entity.id):
		ctx.player.add_xp(int(e.def.get("xp", 0)))
	if e.def.get("behavior", "") == "boss":
		boss_id = 0
		# persistent world change, independent of quest state
		ctx.world.set_flag("boss_defeated", true)
		var altar := ctx.world.plan.site_anchor("dungeon", "altar")
		if ctx.world.tile(MP.L_OBJECT, altar.x, altar.y) == ctx.content.tid("altar"):
			ctx.world.set_tile(MP.L_OBJECT, altar.x, altar.y, ctx.content.tid("altar_pure"))
		for m in ctx.entities.actors:
			if m.kind == "enemy" and m.alive and (m.site == "dungeon" or bool(m.data.get("transient", false))):
				ctx.combat.kill(m, null)
		ctx.bus.boss_state.emit("defeated", e)
		ctx.bus.toast.emit(Loc.t("boss_defeated"))
		ctx.bus.sfx.emit("victory", e.pos)


## Altar interaction: wake the boss inside its arena.
func summon_boss(_altar_tile: Vector2i) -> bool:
	if ctx.world.flag("boss_defeated") or boss_id != 0 or not bool(ctx.world.rule("combat")) or not bool(ctx.world.rule("monsters")):
		return false
	var plan := ctx.world.plan
	var pos := MP.tile_center(plan.site_anchor("dungeon", "boss"))
	var e := ctx.entities.spawn_actor("moon_warden", pos, "dungeon")
	e.data["transient"] = true      # the boss resets instead of sleeping
	e.ai["angry"] = true
	e.ai["chasing"] = true
	var a := plan.site_anchor("dungeon", "arena_min")
	var b := plan.site_anchor("dungeon", "arena_max")
	ctx.ai.boss_arena = Rect2(a.x * MP.TILE, a.y * MP.TILE, (b.x - a.x + 1) * MP.TILE, (b.y - a.y + 1) * MP.TILE)
	boss_id = e.id
	ctx.bus.boss_state.emit("spawn", e)
	ctx.bus.toast.emit(Loc.t("boss_appears"))
	ctx.bus.sfx.emit("boss", pos)
	return true


func boss() -> Entity:
	return ctx.entities.get_entity(boss_id) if boss_id != 0 else null


func _despawn_boss() -> void:
	var b := boss()
	if b != null:
		for m in ctx.entities.actors:
			if m.kind == "enemy" and bool(m.data.get("transient", false)):
				m.remove = true
		ctx.bus.boss_state.emit("reset", b)
	boss_id = 0


func _check_boss() -> void:
	if boss_id == 0:
		return
	var b := boss()
	if b == null or b.remove:
		boss_id = 0
		ctx.bus.boss_state.emit("reset", null)
		return
	# leaving the ruins resets the fight
	if not ctx.ai.boss_arena.grow(MP.TILE * 14.0).has_point(ctx.player.entity.pos):
		_despawn_boss()


func _on_respawn() -> void:
	last_chunk = Vector2i(-9999, -9999)
	for e in ctx.entities.actors:
		e.ai["chasing"] = false
		e.ai["angry"] = false


## Apply rule changes made at runtime (world rule editor).
func apply_rules() -> void:
	if not bool(ctx.world.rule("monsters")):
		for e in ctx.entities.actors:
			if e.kind == "enemy":
				e.remove = true
		boss_id = 0
	ctx.entities.sweep()
