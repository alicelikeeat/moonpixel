class_name QuestService
extends RefCounted
## Data driven quests bound to world objects. Progress comes exclusively from
## EventBus events; completion applies world effects (tiles, flags, trade
## stock, map reveal), so quests always feed back into the world.
##
## States: locked -> available -> active -> ready -> done

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var inv: InventoryService
var bus: EventBus
var npcs: NpcService
var player: PlayerController
var states: Dictionary = {}       # quest id -> {"state": String, "progress": Array[int]}


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_inv: InventoryService,
		p_bus: EventBus, p_npcs: NpcService, p_player: PlayerController) -> void:
	content = p_content; world = p_world; entities = p_entities; inv = p_inv; bus = p_bus; npcs = p_npcs; player = p_player
	for id in content.quest_order:
		states[id] = {"state": "locked", "progress": _zero(id)}
	bus.item_gained.connect(_on_item)
	bus.tile_changed.connect(_on_tile)
	bus.tile_harvested.connect(_on_harvest)
	bus.entity_died.connect(_on_died)
	bus.site_discovered.connect(_on_discovered)
	bus.container_opened.connect(_on_container)
	bus.flag_changed.connect(_on_flag)


func _zero(id: String) -> Array:
	var a: Array = []
	a.resize(content.quests[id]["objectives"].size())
	a.fill(0)
	return a


func state(id: String) -> String:
	return str(states[id]["state"])


func active_ids() -> Array:
	var out: Array = []
	for id in content.quest_order:
		var s := state(id)
		if s == "active" or s == "ready":
			out.append(id)
	return out


func _prereqs_done(q: Dictionary) -> bool:
	for p in q["prereq"]:
		if state(p) != "done":
			return false
	return true


## Re-evaluates availability; call after loading and whenever something completes.
func refresh() -> void:
	for id in content.quest_order:
		var q: Dictionary = content.quests[id]
		var st: Dictionary = states[id]
		if st["state"] == "locked" and _prereqs_done(q):
			if q["giver"] == "auto":
				_activate(id)
			elif q["giver"] == "event":
				st["state"] = "available"
			else:
				st["state"] = "available"
		if st["state"] == "active":
			_check(id)


func _activate(id: String) -> void:
	states[id]["state"] = "active"
	states[id]["progress"] = _zero(id)
	bus.quest_changed.emit(id, "active")
	bus.toast.emit(Loc.t("quest_new") + MP.loc(content.quests[id]["name"]))
	# objectives that may already be satisfied by the current world state
	var q: Dictionary = content.quests[id]
	for i in q["objectives"].size():
		var o: Dictionary = q["objectives"][i]
		if o["type"] == "discover" and world.discovered.has(_site_id(str(o["site"]))):
			states[id]["progress"][i] = 1
		if o.has("or_flag") and world.flag(str(o["or_flag"])):
			states[id]["progress"][i] = int(o.get("count", 1))
	_check(id)


func offers_for(npc: String) -> Array:
	var out: Array = []
	for id in content.quest_order:
		if content.quests[id]["giver"] == npc and state(id) == "available":
			out.append(id)
	return out


func turnins_for(npc: String) -> Array:
	var out: Array = []
	for id in content.quest_order:
		if content.quests[id]["giver"] == npc and (state(id) == "ready" or (state(id) == "active" and _deliverable(id))):
			out.append(id)
	return out


func accept(id: String) -> bool:
	if state(id) != "available":
		return false
	_activate(id)
	return true


func objective_count(id: String, i: int) -> int:
	var o: Dictionary = content.quests[id]["objectives"][i]
	if o["type"] == "deliver":
		return mini(player.bag.count(str(o["item"])), int(o["count"]))
	return int(states[id]["progress"][i])


func _objectives_met(id: String) -> bool:
	var q: Dictionary = content.quests[id]
	for i in q["objectives"].size():
		if objective_count(id, i) < int(q["objectives"][i].get("count", 1)):
			return false
	return true


func _deliverable(id: String) -> bool:
	return _objectives_met(id)


func _check(id: String) -> void:
	if state(id) != "active" or not _objectives_met(id):
		return
	var q: Dictionary = content.quests[id]
	if q["giver"] == "auto" or q["giver"] == "event":
		complete(id)
	else:
		var has_deliver := false
		for o in q["objectives"]:
			if o["type"] == "deliver":
				has_deliver = true
		if not has_deliver:
			states[id]["state"] = "ready"
			bus.quest_changed.emit(id, "ready")
			bus.toast.emit(Loc.t("quest_ready") + MP.loc(content.npcs[q["giver"]]["name"]))


## Turn in at the giver NPC (or auto). Deliveries, rewards and world effects
## are applied together; delivery items are removed in one transaction.
func complete(id: String) -> bool:
	var s := state(id)
	if s != "active" and s != "ready":
		return false
	if not _objectives_met(id):
		return false
	var q: Dictionary = content.quests[id]
	var txn := inv.begin()
	for o in q["objectives"]:
		if o["type"] == "deliver":
			txn.remove(player.bag, str(o["item"]), int(o["count"]))
	if not inv.commit(txn):
		return false
	for r in q["rewards"].get("items", []):
		var left := inv.give_partial(player.bag, str(r[0]), int(r[1]), "quest")
		if left > 0:
			entities.spawn_drop(str(r[0]), left, player.entity.pos)
	player.add_xp(int(q["rewards"].get("xp", 0)))
	for e in q.get("effects", []):
		_apply_effect(e)
	if bool(q.get("repeatable", false)):
		states[id]["state"] = "available"
		states[id]["progress"] = _zero(id)
		states[id]["times"] = int(states[id].get("times", 0)) + 1
	else:
		states[id]["state"] = "done"
	bus.quest_changed.emit(id, "done")
	bus.toast.emit(Loc.t("quest_done") + MP.loc(q["name"]))
	bus.sfx.emit("quest", Vector2.ZERO)
	refresh()
	return true


func _site_id(s: String) -> String:
	return s


func _apply_effect(e: Dictionary) -> void:
	match str(e["type"]):
		"flag":
			world.set_flag(str(e["key"]), e["value"])
		"set_tiles":
			var site = world.plan.site_by_id.get(str(e["site"]))
			if site == null:
				return
			var from := content.tid(str(e["from"]))
			var to := content.tid(str(e["to"]))
			var layer := int(content.t_layer[from])
			for y in range(site["y"], site["y"] + site["h"]):
				for x in range(site["x"], site["x"] + site["w"]):
					if world.tile(layer, x, y) == from:
						world.set_tile(layer, x, y, to)
		"reveal":
			var site = world.plan.site_by_id.get(str(e["site"]))
			if site == null:
				return
			var r := int(e.get("radius", 2))
			var cc := Vector2i(int(site["ax"]) / MP.CHUNK, int(site["ay"]) / MP.CHUNK)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					world.mark_explored(cc.x + dx, cc.y + dy)
			world.flags["known_" + str(e["site"])] = true
		"stock":
			npcs.add_stock(str(e["npc"]), str(e["item"]), int(e["price"]), int(e["count"]))
		"relationship":
			npcs.add_relationship(str(e["npc"]), int(e["delta"]))


## World position (tile) the quest points to, for HUD marker and map.
func marker(id: String) -> Vector2i:
	var q: Dictionary = content.quests[id]
	var site := str(q["site"])
	if site == "event_star":
		var ev: Dictionary = world.event_state
		if ev.has("star"):
			return Vector2i(int(ev["star"]["x"]), int(ev["star"]["y"]))
		return Vector2i(-1, -1)
	if state(id) == "ready" and content.npcs.has(q["giver"]):
		var rec: Dictionary = npcs.records[q["giver"]]
		return MP.tile_of(Vector2(rec["x"], rec["y"]))
	var s = world.plan.site_by_id.get(site)
	if s == null:
		return Vector2i(-1, -1)
	return Vector2i(s["ax"], s["ay"])


func _bump(type: String, pred: Callable, amount: int = 1) -> void:
	for id in content.quest_order:
		if state(id) != "active":
			continue
		var q: Dictionary = content.quests[id]
		var changed := false
		for i in q["objectives"].size():
			var o: Dictionary = q["objectives"][i]
			if o["type"] == type and int(states[id]["progress"][i]) < int(o.get("count", 1)) and pred.call(o):
				states[id]["progress"][i] = mini(int(o.get("count", 1)), int(states[id]["progress"][i]) + amount)
				changed = true
		if changed:
			bus.quest_changed.emit(id, "progress")
			_check(id)


func _on_item(item: String, count: int, source: String) -> void:
	if source == "refund" or source == "trade":
		return
	_bump("gain", func(o): return o["item"] == item, count)
	for id in content.quest_order:
		if state(id) == "active":
			_check(id)


func _on_tile(_x: int, _y: int, _layer: int, _old: int, new_id: int, by_player: bool) -> void:
	if not by_player or new_id == 0:
		return
	var key := content.tile_key(new_id)
	_bump("place", func(o):
		var pat := str(o["tile"])
		return key == pat or (pat.ends_with("*") and key.begins_with(pat.trim_suffix("*"))))


func _on_harvest(_x: int, _y: int, _tile_key: String, drops: Array) -> void:
	for d in drops:
		_bump("harvest", func(o): return o["item"] == d[0], int(d[1]))


func _in_site(pos: Vector2, site_id: String, pad: int) -> bool:
	var s = world.plan.site_by_id.get(site_id)
	if s == null:
		return false
	var t := MP.tile_of(pos)
	return t.x >= s["x"] - pad and t.y >= s["y"] - pad and t.x < s["x"] + s["w"] + pad and t.y < s["y"] + s["h"] + pad


func _on_died(e: Entity, killer) -> void:
	if e.kind != "enemy":
		return
	_bump("kill", func(o):
		if str(o.get("def", "*")) != "*" and o["def"] != e.def_id:
			return false
		if o.has("site") and e.site != o["site"] and not _in_site(e.pos, str(o["site"]), 6):
			return false
		return true)


func _on_discovered(site_id: String) -> void:
	_bump("discover", func(o): return o["site"] == site_id)


func _on_container(x: int, y: int) -> void:
	_bump("open", func(o): return _in_site(MP.tile_center(Vector2i(x, y)), str(o["site"]), 0))


func _on_flag(key: String, value) -> void:
	if key == "star_event":
		var st: Dictionary = states["q_star"]
		if bool(value) and st["state"] == "available":
			_activate("q_star")
		elif not bool(value) and st["state"] == "active":
			st["state"] = "available"
			bus.quest_changed.emit("q_star", "failed")


func to_dict() -> Dictionary:
	return states.duplicate(true)


func from_dict(d: Dictionary) -> void:
	for id in d:
		if states.has(id) and d[id] is Dictionary:
			var src: Dictionary = d[id]
			var st := str(src.get("state", "locked"))
			if not ["locked", "available", "active", "ready", "done"].has(st):
				st = "locked"
			states[id]["state"] = st
			var prog = src.get("progress", [])
			var mine: Array = states[id]["progress"]
			if prog is Array:
				for i in mini(prog.size(), mine.size()):
					mine[i] = int(prog[i])
			if src.has("times"):
				states[id]["times"] = int(src["times"])
