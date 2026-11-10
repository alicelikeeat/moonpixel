class_name PlayerController
extends RefCounted
## Player logic: movement, evasion, attacks/combos/charge, interaction, item
## use, stats and progression. Driven by an InputState once per logic tick, so
## it is fully testable without a scene. Animation is derived from `state` by
## the view layer (action logic and presentation are separate).

signal ui_request(kind: String, data: Dictionary)

const WALK := 72.0
const RUN_MULT := 1.6
const EVADE := {
	"roll": {"time": 0.38, "speed": 190.0, "stamina": 20.0, "iframe_from": 0.04, "iframe_to": 0.30, "cd": 0.15},
	"dash": {"time": 0.14, "speed": 340.0, "stamina": 12.0, "iframe_from": 9.0, "iframe_to": 0.0, "cd": 0.6},
}
const HOTBAR := 8
const BAG_SIZE := 32


class InputState:
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	var attack_pressed := false
	var attack_held := false
	var roll_pressed := false
	var dash_pressed := false
	var run_held := false
	var interact_pressed := false
	var use_pressed := false
	var hotbar := -1

	func clear_edges() -> void:
		attack_pressed = false
		roll_pressed = false
		dash_pressed = false
		interact_pressed = false
		use_pressed = false
		hotbar = -1


var content: ContentRegistry
var world: WorldService
var entities: EntityService
var combat: CombatService
var inv: InventoryService
var terrain: TerrainOps
var bus: EventBus
var entity: Entity
var bag: Inventory
var equip: Inventory            # slot 0 armor, slot 1 trinket
var hotbar_index := 0
var stamina := 100.0
var max_stamina := 100.0
var mana := 50.0
var max_mana := 50.0
var xp := 0
var level := 1
var spawn_point := Vector2.ZERO
var state := "idle"
var evade_kind := ""
var evade_t := 0.0
var evade_dir := Vector2.DOWN
var evade_cd := 0.0
var hold_t := 0.0
var charge_t := 0.0
var queued_attack := false
var noclip := false
var deaths := 0
var on_altar: Callable = Callable()
var on_sleep: Callable = Callable()


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_combat: CombatService,
		p_inv: InventoryService, p_terrain: TerrainOps, p_bus: EventBus) -> void:
	content = p_content; world = p_world; entities = p_entities; combat = p_combat
	inv = p_inv; terrain = p_terrain; bus = p_bus
	bag = Inventory.new(BAG_SIZE, content)
	equip = Inventory.new(2, content)
	equip.accept[0] = "armor"
	equip.accept[1] = "trinket"
	entity = Entity.new()
	entity.kind = "player"
	entity.def_id = "player"
	entity.def = {"behavior": "player"}
	entity.team = Entity.TEAM_PLAYER
	entity.radius = 5.0
	entity.max_hp = 100.0
	entity.hp = 100.0
	combat.player_defense = defense
	combat.on_harvest = _on_harvest


func spawn_at(pos: Vector2) -> void:
	entity.pos = pos
	entity.prev_pos = pos
	spawn_point = pos
	if not entities.entities.has(entity.id) or entity.id == 0:
		entities.add(entity)


func give_starting_kit() -> void:
	inv.give(bag, "tool_stone", 1)
	inv.give(bag, "sword_wood", 1)
	inv.give(bag, "berry", 4)
	if bool(world.rule("god_build")):
		for it in ["tool_iron", "hoe", "sword_iron", "bow_hunter", "staff_ember", "wheat_seeds"]:
			inv.give(bag, it, 20 if content.max_stack(it) > 1 else 1)
		inv.give(bag, "arrow", 99)


# --- derived stats ---------------------------------------------------------------
func held_item() -> String:
	var s = bag.slots[hotbar_index]
	return "" if s == null else str(s[0])


func weapon() -> Dictionary:
	var it := held_item()
	if it != "" and content.items[it].has("weapon"):
		return content.items[it]["weapon"]
	return {"class": "hand", "damage": 3, "skill": "unarmed", "tier": 0}


func attack_power() -> float:
	return float(weapon()["damage"]) * (1.0 + 0.03 * (level - 1))


func defense() -> float:
	var s = equip.slots[0]
	return float(content.items[s[0]]["armor"]["defense"]) if s != null else 0.0


func trinket(k: String) -> float:
	var s = equip.slots[1]
	return float(content.items[s[0]]["trinket"].get(k, 0.0)) if s != null else 0.0


func xp_needed() -> int:
	return int(40.0 * pow(level, 1.5))


func add_xp(n: int) -> void:
	xp += n
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		entity.max_hp += 10.0
		entity.hp = entity.max_hp
		max_stamina += 4.0
		bus.toast.emit(Loc.t("level_up") + " Lv." + str(level))
		bus.fx.emit("levelup", entity.pos, {})
		bus.sfx.emit("levelup", entity.pos)


# --- tick -------------------------------------------------------------------------
func tick(dt: float, inp: InputState) -> void:
	var e := entity
	if not e.alive:
		state = "dead"
		return
	if inp.hotbar >= 0 and inp.hotbar < HOTBAR and e.skill_phase == Entity.PH_NONE:
		hotbar_index = inp.hotbar
	evade_cd = maxf(0.0, evade_cd - dt)
	mana = minf(max_mana, mana + (1.5 + trinket("mana_regen")) * dt)
	if e.stun > 0.0:
		state = "hurt"
		hold_t = 0.0
		charge_t = 0.0
		queued_attack = false
		return
	if evade_kind != "":
		_tick_evade(dt)
		return
	var busy := e.skill_phase != Entity.PH_NONE
	if not busy and not (inp.run_held and inp.move != Vector2.ZERO):
		stamina = minf(max_stamina, stamina + 22.0 * dt)
	var aim := inp.aim
	if aim.length_squared() < 0.01:
		aim = _auto_aim(inp.move)
	# evasion can cancel anything except the damaging frames of a skill
	if (inp.roll_pressed or inp.dash_pressed) and e.skill_phase != Entity.PH_ACTIVE:
		var kind := "roll" if inp.roll_pressed else "dash"
		if evade_cd <= 0.0 and stamina >= float(EVADE[kind]["stamina"]):
			combat.cancel_skill(e)
			stamina -= float(EVADE[kind]["stamina"])
			evade_kind = kind
			evade_t = 0.0
			evade_dir = inp.move.normalized() if inp.move.length_squared() > 0.01 else e.facing
			e.facing = evade_dir
			state = kind
			hold_t = 0.0
			charge_t = 0.0
			bus.sfx.emit("roll", e.pos)
			_tick_evade(0.0)
			return
	if busy:
		state = "attack"
		e.move_dir = Vector2.ZERO
		if inp.attack_pressed:
			queued_attack = true
		if e.skill_phase == Entity.PH_RECOVERY and queued_attack and e.skill.has("combo_next") \
				and e.skill_t >= float(e.skill["recovery"]) * 0.3:
			var next := str(e.skill["combo_next"])
			combat.cancel_skill(e)
			queued_attack = false
			_try_skill(next, aim)
		return
	if inp.interact_pressed:
		interact()
	if inp.use_pressed:
		use_held(aim)
	# attacks
	if inp.attack_pressed or queued_attack:
		queued_attack = false
		var sid := str(weapon()["skill"])
		var last := str(e.ai.get("last_skill", ""))
		if last != "" and content.skills[last].has("combo_next") \
				and world.time_real - float(e.ai.get("last_skill_end", -10.0)) <= float(content.skills[last].get("combo_window", 0.4)):
			sid = str(content.skills[last]["combo_next"])
		if _try_skill(sid, aim):
			hold_t = 0.0
			charge_t = 0.0
			state = "attack"
			return
	var charging := false
	if inp.attack_held and weapon().has("charge"):
		hold_t += dt
		if hold_t > 0.25:
			charge_t = hold_t - 0.25
			charging = true
	else:
		if charge_t > 0.0 and weapon().has("charge"):
			var cs: Dictionary = content.skills[weapon()["charge"]]
			if charge_t >= float(cs.get("charge_time", 0.6)):
				hold_t = 0.0
				charge_t = 0.0
				if _try_skill(str(cs["id"]), aim):
					state = "attack"
					return
		hold_t = 0.0
		charge_t = 0.0
	# movement
	var mv := inp.move
	if mv.length_squared() > 1.0:
		mv = mv.normalized()
	var speed := WALK * e.speed_mult() * (1.0 + trinket("speed"))
	var running := inp.run_held and stamina > 1.0 and mv != Vector2.ZERO and not charging
	if running:
		speed *= RUN_MULT
		stamina = maxf(0.0, stamina - 11.0 * dt)
	if charging:
		speed *= 0.45
	var t := MP.tile_of(e.pos)
	speed *= world.walk_speed(t.x, t.y)
	if mv != Vector2.ZERO:
		if noclip:
			e.pos += mv * speed * 2.0 * dt
		else:
			e.pos = world.move(e.pos, mv * speed * dt, e.radius)
		var lim := float(world.config.size * MP.TILE)
		e.pos.x = clampf(e.pos.x, 4.0, lim - 4.0)
		e.pos.y = clampf(e.pos.y, 4.0, lim - 4.0)
		e.move_dir = mv
		e.facing = aim if (charging or inp.aim.length_squared() > 0.01) and aim != Vector2.ZERO else mv.normalized()
		state = "charge" if charging else ("run" if running else "walk")
	else:
		e.move_dir = Vector2.ZERO
		if aim != Vector2.ZERO and (charging or inp.aim.length_squared() > 0.01):
			e.facing = aim
		state = "charge" if charging else "idle"


func charge_ratio() -> float:
	if charge_t <= 0.0 or not weapon().has("charge"):
		return 0.0
	return clampf(charge_t / float(content.skills[weapon()["charge"]].get("charge_time", 0.6)), 0.0, 1.0)


func _tick_evade(dt: float) -> void:
	var ev: Dictionary = EVADE[evade_kind]
	evade_t += dt
	var e := entity
	if evade_t >= float(ev["iframe_from"]) and evade_t <= float(ev["iframe_to"]):
		e.iframes = maxf(e.iframes, 0.05)
	e.pos = world.move(e.pos, evade_dir * float(ev["speed"]) * dt, e.radius) if not noclip else e.pos + evade_dir * float(ev["speed"]) * dt
	e.move_dir = evade_dir
	state = evade_kind
	if evade_t >= float(ev["time"]):
		evade_cd = float(ev["cd"])
		evade_kind = ""
		state = "idle"


func _auto_aim(move: Vector2) -> Vector2:
	var best: Entity = null
	var best_d := 96.0 * 96.0
	for t in entities.actors:
		if t.alive and t.team == Entity.TEAM_HOSTILE:
			var d: float = t.pos.distance_squared_to(entity.pos)
			if d < best_d:
				best_d = d
				best = t
	if best != null:
		return (best.pos - entity.pos).normalized()
	return move.normalized() if move.length_squared() > 0.01 else entity.facing


func _try_skill(sid: String, aim: Vector2) -> bool:
	var s: Dictionary = content.skills[sid]
	var e := entity
	if not combat.skill_ready(e, sid):
		return false
	var free := bool(world.rule("god_build"))
	if not free:
		if stamina < float(s.get("stamina", 0.0)) or mana < float(s.get("mana", 0.0)):
			return false
		if s.has("ammo") and bag.count(str(s["ammo"])) < 1:
			bus.toast.emit(Loc.t("no_ammo"))
			return false
	if not combat.start_skill(e, sid, aim if aim != Vector2.ZERO else e.facing, attack_power()):
		return false
	if not free:
		stamina -= float(s.get("stamina", 0.0))
		mana -= float(s.get("mana", 0.0))
		if s.has("ammo"):
			inv.take(bag, str(s["ammo"]), 1)
	return true


func _on_harvest(actor: Entity, _skill: Dictionary) -> void:
	if actor != entity:
		return
	var w := weapon()
	var tier := int(w.get("tier", 0))
	for dist in [12.0, 22.0]:
		var t := MP.tile_of(entity.pos + entity.skill_dir * dist)
		if terrain.hittable_layer(t.x, t.y) >= 0:
			var res := terrain.hit_tile(t.x, t.y, tier, 1.0)
			if res["error"] != "":
				bus.toast.emit(Loc.t(res["error"]))
			return
	if int(w.get("till", 0)) == 1:
		var t := MP.tile_of(entity.pos + entity.skill_dir * 14.0)
		terrain.till(t.x, t.y)


# --- interaction ------------------------------------------------------------------
func interaction_target() -> Dictionary:
	var e := entity
	var best: Entity = null
	var best_d := 28.0 * 28.0
	for a in entities.actors:
		if a.kind == "npc":
			var d: float = a.pos.distance_squared_to(e.pos)
			if d < best_d:
				best_d = d
				best = a
	if best != null:
		return {"kind": "talk", "npc": str(best.data.get("npc", "")), "pos": best.pos}
	var base := MP.tile_of(e.pos)
	var front := MP.tile_of(e.pos + e.facing * 14.0)
	var cands: Array = [front, base]
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		cands.append(base + d)
	for t in cands:
		var o := world.tile(MP.L_OBJECT, t.x, t.y)
		if o == 0:
			continue
		var def: Dictionary = content.tiles[o]
		var pos := MP.tile_center(t)
		if def.has("harvest"):
			return {"kind": "harvest", "x": t.x, "y": t.y, "pos": pos}
		if def.has("container"):
			return {"kind": "chest", "x": t.x, "y": t.y, "pos": pos}
		if def.has("station"):
			return {"kind": "craft", "x": t.x, "y": t.y, "pos": pos}
		if def.has("bed"):
			return {"kind": "bed", "x": t.x, "y": t.y, "pos": pos}
		if def.has("altar"):
			return {"kind": "altar", "x": t.x, "y": t.y, "pos": pos}
	return {}


func interact() -> bool:
	var tg := interaction_target()
	if tg.is_empty():
		return false
	match str(tg["kind"]):
		"talk":
			ui_request.emit("talk", tg)
		"harvest":
			terrain.harvest(tg["x"], tg["y"], bag)
		"chest":
			bus.container_opened.emit(tg["x"], tg["y"])
			ui_request.emit("chest", tg)
		"craft":
			ui_request.emit("craft", tg)
		"bed":
			var free := world.find_free_near(Vector2i(tg["x"], tg["y"]), 3)
			spawn_point = MP.tile_center(free)
			bus.toast.emit(Loc.t("spawn_set"))
			if world.is_night():
				var day_t := world.time_of_day()
				var target := 0.27
				var skip := (target - day_t) if day_t < target else (1.0 - day_t + target)
				world.time += skip * MP.DAY_SECONDS
				entity.hp = entity.max_hp
				bus.toast.emit(Loc.t("sleep"))
				if on_sleep.is_valid():
					on_sleep.call()
		"altar":
			if on_altar.is_valid():
				on_altar.call(Vector2i(tg["x"], tg["y"]))
	return true


## Use the held hotbar item (food, potion, seed).
func use_held(aim: Vector2) -> bool:
	return use_slot(hotbar_index, aim)


func use_slot(i: int, aim: Vector2 = Vector2.ZERO) -> bool:
	var s = bag.slots[i]
	if s == null:
		return false
	var item: String = s[0]
	var def: Dictionary = content.items[item]
	if not def.has("use"):
		return false
	var use: Dictionary = def["use"]
	if use.has("plant"):
		var dir := aim if aim != Vector2.ZERO else entity.facing
		for dist in [14.0, 0.0]:
			var t := MP.tile_of(entity.pos + dir * dist)
			if terrain.plant(item, t.x, t.y, bag):
				return true
		return false
	if not inv.take(bag, item, 1):
		return false
	entity.hp = minf(entity.max_hp, entity.hp + float(use.get("heal", 0.0)))
	stamina = minf(max_stamina, stamina + float(use.get("stamina", 0.0)))
	mana = minf(max_mana, mana + float(use.get("mana", 0.0)))
	if use.has("buff"):
		combat.add_status(entity, use["buff"])
	bus.fx.emit("heal", entity.pos, {})
	bus.sfx.emit("eat", entity.pos)
	return true


# --- death / respawn ---------------------------------------------------------------
func respawn() -> void:
	var e := entity
	deaths += 1
	e.alive = true
	e.hp = e.max_hp
	stamina = max_stamina
	mana = max_mana
	e.stun = 0.0
	e.vel = Vector2.ZERO
	e.statuses.clear()
	e.iframes = 2.0
	combat.cancel_skill(e)
	evade_kind = ""
	hold_t = 0.0
	charge_t = 0.0
	var t := world.find_free_near(MP.tile_of(spawn_point), 8)
	e.pos = MP.tile_center(t)
	e.prev_pos = e.pos
	state = "idle"
	bus.player_respawned.emit()


# --- persistence ------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {"x": entity.pos.x, "y": entity.pos.y, "hp": entity.hp, "max_hp": entity.max_hp, "stamina": stamina,
		"max_stamina": max_stamina, "mana": mana, "xp": xp, "level": level, "sx": spawn_point.x, "sy": spawn_point.y,
		"inventory": bag.to_array(), "equipment": equip.to_array(), "hotbar": hotbar_index, "deaths": deaths,
		"alive": entity.alive}


func from_dict(d: Dictionary) -> void:
	entity.pos = Vector2(float(d.get("x", entity.pos.x)), float(d.get("y", entity.pos.y)))
	entity.prev_pos = entity.pos
	entity.max_hp = float(d.get("max_hp", 100.0))
	entity.hp = clampf(float(d.get("hp", entity.max_hp)), 0.0, entity.max_hp)
	max_stamina = float(d.get("max_stamina", 100.0))
	stamina = float(d.get("stamina", max_stamina))
	mana = float(d.get("mana", max_mana))
	xp = int(d.get("xp", 0))
	level = int(d.get("level", 1))
	spawn_point = Vector2(float(d.get("sx", entity.pos.x)), float(d.get("sy", entity.pos.y)))
	bag.from_array(d.get("inventory", []))
	equip.from_array(d.get("equipment", []))
	hotbar_index = clampi(int(d.get("hotbar", 0)), 0, HOTBAR - 1)
	deaths = int(d.get("deaths", 0))
	entity.alive = bool(d.get("alive", true)) and entity.hp > 0.0
	if not entity.alive:
		# a save taken while dead resumes at the respawn point
		entity.alive = true
		entity.hp = entity.max_hp
		entity.pos = spawn_point
		entity.prev_pos = spawn_point
