class_name NpcService
extends RefCounted
## NPC records (identity, position, schedule, trade stock, relationship) and
## their in-world entities. Records persist in the world index; an entity only
## exists while the NPC's chunk is active. Off-screen NPCs advance by schedule
## at low frequency instead of being simulated every tick.

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var inv: InventoryService
var bus: EventBus
var records: Dictionary = {}      # npc id -> {x,y,rel,stock:{item:[price,count]},talked}
var quests: QuestService = null
var _grid: AStarGrid2D = null
var _grid_origin := Vector2i.ZERO
var _grid_dirty := true
var _slow_acc := 0.0
var rng := RandomNumberGenerator.new()


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_inv: InventoryService, p_bus: EventBus) -> void:
	content = p_content; world = p_world; entities = p_entities; inv = p_inv; bus = p_bus
	bus.tile_changed.connect(_on_tile_changed)


func _anchor_px(name: String) -> Vector2:
	var t := world.plan.site_anchor("village", name)
	return MP.tile_center(t)


func init_new_world() -> void:
	records.clear()
	for id in content.npc_order:
		var def: Dictionary = content.npcs[id]
		var p := _anchor_px(str(def["work"]))
		var stock := {}
		if def.has("trade"):
			for s in def["trade"]["sells"]:
				stock[s[0]] = [int(s[1]), int(s[2])]
		records[id] = {"x": p.x, "y": p.y, "rel": 0, "stock": stock, "talked": false}


func _on_tile_changed(x: int, y: int, _layer: int, _old: int, _new: int, _by: bool) -> void:
	var v = world.plan.site_by_id.get("village")
	if v != null and x >= v["x"] - 8 and y >= v["y"] - 8 and x < v["x"] + v["w"] + 8 and y < v["y"] + v["h"] + 8:
		_grid_dirty = true


func _ensure_grid() -> void:
	if _grid != null and not _grid_dirty:
		return
	var v: Dictionary = world.plan.site_by_id["village"]
	_grid_origin = Vector2i(v["x"] - 8, v["y"] - 8)
	var size := Vector2i(v["w"] + 16, v["h"] + 16)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, size)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for y in size.y:
		for x in size.x:
			if world.blocked(_grid_origin.x + x, _grid_origin.y + y):
				_grid.set_point_solid(Vector2i(x, y), true)
	_grid_dirty = false


func schedule_target(id: String) -> Vector2:
	var def: Dictionary = content.npcs[id]
	var h := world.hour()
	var at := "work"
	for s in def["schedule"]:
		var from := float(s["from"])
		var to := float(s["to"])
		var inside := (h >= from and h < to) if from < to else (h >= from or h < to)
		if inside:
			at = str(s["at"])
			break
	return _anchor_px(str(def[at]))


func entity_of(id: String) -> Entity:
	for a in entities.actors:
		if a.kind == "npc" and a.data.get("npc") == id:
			return a
	return null


func _spawn_entity(id: String) -> Entity:
	var def: Dictionary = content.npcs[id]
	var rec: Dictionary = records[id]
	var e := Entity.new()
	e.kind = "npc"
	e.def_id = id
	e.def = def
	e.team = Entity.TEAM_PLAYER
	e.radius = 5.0
	e.max_hp = 1.0
	e.pos = Vector2(rec["x"], rec["y"])
	e.data = {"npc": id}
	return entities.add(e)


func tick(dt: float) -> void:
	if not world.plan.site_by_id.has("village") or records.is_empty():
		return
	# materialise / dematerialise with chunk activity
	for id in records:
		var rec: Dictionary = records[id]
		var key := MP.chunk_key(floori(float(rec["x"]) / MP.CHUNK_PX), floori(float(rec["y"]) / MP.CHUNK_PX))
		var e := entity_of(id)
		if entities.active_chunks.has(key):
			if e == null:
				e = _spawn_entity(id)
			_walk(e, id, dt)
			rec["x"] = e.pos.x
			rec["y"] = e.pos.y
		elif e != null:
			e.remove = true
	# low frequency progression for off-screen NPCs
	_slow_acc += dt
	if _slow_acc >= 5.0:
		_slow_acc = 0.0
		for id in records:
			if entity_of(id) == null:
				var t := schedule_target(id)
				records[id]["x"] = t.x
				records[id]["y"] = t.y


func _walk(e: Entity, id: String, dt: float) -> void:
	var target := schedule_target(id)
	if e.ai.get("talking_until", 0.0) > world.time_real:
		e.move_dir = Vector2.ZERO
		return
	if e.pos.distance_to(target) < 10.0:
		# idle near the anchor with small random steps
		var t := float(e.ai.get("idle_t", 0.0)) - dt
		if t <= 0.0:
			t = rng.randf_range(2.0, 5.0)
			e.facing = Vector2.from_angle(rng.randf() * TAU)
		e.ai["idle_t"] = t
		e.move_dir = Vector2.ZERO
		e.ai.erase("path")
		return
	_ensure_grid()
	if not e.ai.has("path") or e.ai.get("path_to") != target:
		var a := MP.tile_of(e.pos) - _grid_origin
		var b := MP.tile_of(target) - _grid_origin
		var path: Array = []
		if _grid.is_in_boundsv(a) and _grid.is_in_boundsv(b):
			_grid.set_point_solid(a, false)
			_grid.set_point_solid(b, false)
			for p in _grid.get_id_path(a, b):
				path.append(MP.tile_center(p + _grid_origin))
		if path.is_empty():
			# unreachable (player walled it in): relocate instead of getting stuck forever
			e.pos = target
			return
		e.ai["path"] = path
		e.ai["path_to"] = target
		e.ai["path_i"] = 0
	var path: Array = e.ai["path"]
	var i := int(e.ai["path_i"])
	if i >= path.size():
		e.ai.erase("path")
		return
	var wp: Vector2 = path[i]
	var to := wp - e.pos
	if to.length() < 3.0:
		e.ai["path_i"] = i + 1
		return
	var dir := to.normalized()
	var before := e.pos
	e.pos = world.move(e.pos, dir * 38.0 * dt, e.radius)
	if e.pos.distance_to(before) < 0.1:
		e.ai["blocked_t"] = float(e.ai.get("blocked_t", 0.0)) + dt
		if float(e.ai["blocked_t"]) > 1.0:
			e.ai.erase("path")
			e.ai["blocked_t"] = 0.0
			_grid_dirty = true
	e.move_dir = dir
	e.facing = dir


# --- dialogue ----------------------------------------------------------------------
## Returns {"name", "text", "options": [{"id", "label"}]}
func dialogue(id: String) -> Dictionary:
	var def: Dictionary = content.npcs[id]
	var rec: Dictionary = records[id]
	rec["talked"] = true
	var e := entity_of(id)
	if e != null:
		e.ai["talking_until"] = world.time_real + 4.0
	var lines: Dictionary = def["lines"]
	var text := MP.loc(lines["after_boss"]) if world.flag("boss_defeated") else MP.loc(lines["greet"])
	var options: Array = []
	if quests != null:
		for q in quests.turnins_for(id):
			options.append({"id": "turnin:" + q, "label": Loc.t("turn_in") + " — " + MP.loc(content.quests[q]["name"])})
		for q in quests.offers_for(id):
			options.append({"id": "accept:" + q, "label": Loc.t("accept") + " — " + MP.loc(content.quests[q]["name"])})
	if def.has("trade"):
		options.append({"id": "trade", "label": Loc.t("trade")})
	options.append({"id": "chat", "label": Loc.t("talk")})
	options.append({"id": "bye", "label": Loc.t("bye")})
	return {"name": MP.loc(def["name"]), "text": text, "options": options}


func chat_line(id: String) -> String:
	var chat: Array = content.npcs[id]["lines"]["chat"]
	return MP.loc(chat[rng.randi() % chat.size()])


# --- trade -------------------------------------------------------------------------
func price_buy(id: String, item: String) -> int:
	var rec: Dictionary = records[id]
	if not rec["stock"].has(item):
		return -1
	var base := float(rec["stock"][item][0])
	return maxi(1, int(round(base * (1.0 - minf(0.2, 0.02 * float(rec["rel"]))))))


func price_sell(id: String, item: String) -> int:
	var def: Dictionary = content.npcs[id]
	if not def.has("trade") or item == "coin":
		return 0
	return maxi(1, int(float(content.items[item].get("value", 1)) * float(def["trade"]["buy_mult"])))


## Player buys from NPC. One transaction: coins out, goods in.
func buy(id: String, item: String, n: int, bag: Inventory) -> bool:
	var rec: Dictionary = records[id]
	if n <= 0 or not rec["stock"].has(item) or int(rec["stock"][item][1]) < n:
		return false
	var cost := price_buy(id, item) * n
	if not inv.commit(inv.begin().remove(bag, "coin", cost).add(bag, item, n)):
		return false
	rec["stock"][item][1] = int(rec["stock"][item][1]) - n
	bus.item_gained.emit(item, n, "trade")
	bus.sfx.emit("coin", Vector2.ZERO)
	return true


func sell(id: String, item: String, n: int, bag: Inventory) -> bool:
	var value := price_sell(id, item) * n
	if n <= 0 or value <= 0:
		return false
	if not inv.commit(inv.begin().remove(bag, item, n).add(bag, "coin", value)):
		return false
	var rec: Dictionary = records[id]
	if rec["stock"].has(item):
		rec["stock"][item][1] = int(rec["stock"][item][1]) + n
	bus.sfx.emit("coin", Vector2.ZERO)
	return true


func add_stock(id: String, item: String, price: int, count: int) -> void:
	if not records.has(id):
		return
	var st: Dictionary = records[id]["stock"]
	if st.has(item):
		st[item][1] = int(st[item][1]) + count
	else:
		st[item] = [price, count]


func add_relationship(id: String, delta: int) -> void:
	if records.has(id):
		records[id]["rel"] = int(records[id]["rel"]) + delta


func to_dict() -> Dictionary:
	return records.duplicate(true)


func from_dict(d: Dictionary) -> void:
	init_new_world()
	for id in d:
		if records.has(id) and d[id] is Dictionary:
			var src: Dictionary = d[id]
			var rec: Dictionary = records[id]
			rec["x"] = float(src.get("x", rec["x"]))
			rec["y"] = float(src.get("y", rec["y"]))
			rec["rel"] = int(src.get("rel", 0))
			rec["talked"] = bool(src.get("talked", false))
			var st = src.get("stock", {})
			if st is Dictionary:
				for item in st:
					if content.items.has(item) and st[item] is Array and st[item].size() == 2:
						rec["stock"][item] = [int(st[item][0]), int(st[item][1])]
