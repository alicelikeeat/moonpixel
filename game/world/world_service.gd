class_name WorldService
extends RefCounted
## WorldService: seed, rules, world clock, flags, discovery and tile access in
## world coordinates. World (tile/pixel) coordinates are completely separate
## from screen coordinates; only the rendering layer knows about cameras.
##
## Main-thread only. Tile writes go through set_tile() so that persistence,
## timers and events stay consistent; other modules never mutate ChunkData
## layers directly.

var config: WorldConfig
var content: ContentRegistry
var plan: WorldPlan
var chunks: ChunkService
var bus: EventBus
var time: float = MP.DAY_SECONDS * 0.30
var time_real := 0.0                 # unscaled session clock (cooldowns, AI timers); not saved
var flags: Dictionary = {}
var discovered: Dictionary = {}
var explored := PackedByteArray()
var next_prop_id := 1
var tile_damage: Dictionary = {}       # transient: Vector3i(x,y,layer) -> accumulated hits
var event_state: Dictionary = {}       # region events (falling star)
var _timer_acc := 0.0


func setup(p_config: WorldConfig, p_content: ContentRegistry, p_plan: WorldPlan, p_chunks: ChunkService, p_bus: EventBus) -> void:
	config = p_config
	content = p_content
	plan = p_plan
	chunks = p_chunks
	bus = p_bus
	var n := config.chunks_per_side()
	explored.resize((n * n + 7) / 8)


func rule(k: String):
	return config.rule(k)


func in_bounds(wx: int, wy: int) -> bool:
	return wx >= 0 and wy >= 0 and wx < config.size and wy < config.size


# --- time -----------------------------------------------------------------
func day() -> int:
	return int(time / MP.DAY_SECONDS)


func time_of_day() -> float:
	return fposmod(time, MP.DAY_SECONDS) / MP.DAY_SECONDS


func hour() -> float:
	return time_of_day() * 24.0


func is_night() -> bool:
	var h := hour()
	return h < 5.5 or h >= 20.0


func daylight() -> float:
	## 0 = deep night, 1 = full day, smooth dawn/dusk.
	var h := hour()
	if h < 4.5 or h >= 21.0:
		return 0.0
	if h < 7.0:
		return (h - 4.5) / 2.5
	if h < 18.5:
		return 1.0
	return 1.0 - (h - 18.5) / 2.5


func advance(dt: float) -> void:
	time += dt * float(rule("time_scale"))
	time_real += dt
	_timer_acc += dt
	if _timer_acc >= 1.0:
		_timer_acc = 0.0
		for k in chunks.cache:
			var c: ChunkData = chunks.cache[k]
			if c.timers.size() > 0:
				process_timers(c)


## Deterministic weather: a pure function of (seed, time), so it needs no
## saved state and is identical after reload.
func weather_at(biome_group: String) -> String:
	var freq := float(rule("weather_frequency"))
	if freq <= 0.0:
		return "clear"
	var epoch := int(time / (300.0 / freq))
	var r := MP.h01(config.seed + 501, epoch, 0)
	if r < 0.58:
		return "clear"
	if r < 0.68:
		return "fog"
	match biome_group:
		"snow": return "snow"
		"desert": return "storm"
	return "rain"


func biome_group_at(wx: int, wy: int) -> String:
	return str(content.biomes[chunks.generator.biome_at(wx, wy)]["group"])


# --- flags / discovery ------------------------------------------------------
func set_flag(k: String, v) -> void:
	if flags.get(k) == v:
		return
	flags[k] = v
	bus.flag_changed.emit(k, v)


func flag(k: String) -> bool:
	return bool(flags.get(k, false))


func mark_explored(cx: int, cy: int) -> void:
	var n := config.chunks_per_side()
	if cx < 0 or cy < 0 or cx >= n or cy >= n:
		return
	var b := cy * n + cx
	explored[b >> 3] = explored[b >> 3] | (1 << (b & 7))


func is_explored(cx: int, cy: int) -> bool:
	var n := config.chunks_per_side()
	if cx < 0 or cy < 0 or cx >= n or cy >= n:
		return false
	var b := cy * n + cx
	return (explored[b >> 3] & (1 << (b & 7))) != 0


func discover(site_id: String) -> bool:
	if discovered.has(site_id):
		return false
	discovered[site_id] = true
	bus.site_discovered.emit(site_id)
	return true


func site_name(site: Dictionary) -> String:
	var t: String = site["type"]
	return Loc.t("site_" + t)


# --- tiles ----------------------------------------------------------------
func tile(layer: int, wx: int, wy: int) -> int:
	if wx < 0 or wy < 0:
		return 0
	var c := chunks.get_chunk(wx >> 5, wy >> 5)
	if c == null:
		return 0
	return c.layers[layer][(wy & 31) * MP.CHUNK + (wx & 31)]


func blocked(wx: int, wy: int) -> bool:
	if wx < 0 or wy < 0:
		return true
	var c := chunks.get_chunk(wx >> 5, wy >> 5)
	if c == null:
		return true
	var i := (wy & 31) * MP.CHUNK + (wx & 31)
	var o: int = c.layers[2][i]
	if o != 0 and content.t_solid[o] != 0:
		return true
	var s: int = c.layers[1][i]
	if s != 0:
		if content.t_solid[s] != 0:
			return true
		if content.t_bridge[s] != 0:
			return false
	return content.t_solid[c.layers[0][i]] != 0


func walk_speed(wx: int, wy: int) -> float:
	var c := chunks.get_chunk(wx >> 5, wy >> 5)
	if c == null:
		return 1.0
	var i := (wy & 31) * MP.CHUNK + (wx & 31)
	var s: int = c.layers[1][i]
	if s != 0:
		return content.t_walk[s]
	return content.t_walk[c.layers[0][i]]


## Low level tile write. Returns false outside the world.
func set_tile(layer: int, wx: int, wy: int, id: int, by_player: bool = false) -> bool:
	if not in_bounds(wx, wy):
		return false
	var c := chunks.get_chunk(wx >> 5, wy >> 5)
	var i := (wy & 31) * MP.CHUNK + (wx & 31)
	var old: int = c.layers[layer][i]
	if old == id:
		return true
	c.layers[layer][i] = id
	c.touch()
	tile_damage.erase(Vector3i(wx, wy, layer))
	# timers bound to the previous tile are void
	for n in range(c.timers.size() - 1, -1, -1):
		if c.timers[n]["i"] == i and c.timers[n]["l"] == layer:
			c.timers.remove_at(n)
	if layer == MP.L_OBJECT and c.containers.has(i):
		var def = content.tiles[id] if id != 0 else null
		if def == null or not def.has("container"):
			c.containers.erase(i)
	if id != 0:
		var t: Dictionary = content.tiles[id]
		if t.has("grow"):
			c.timers.append({"i": i, "l": layer, "to": content.tid(t["grow"]["to"]), "due": time + float(t["grow"]["time"]), "expect": id})
	bus.tile_changed.emit(wx, wy, layer, old, id, by_player)
	bus.chunk_changed.emit(c.cx, c.cy)
	return true


func schedule(wx: int, wy: int, layer: int, to_id: int, delay: float, expect: int) -> void:
	var c := chunks.get_chunk(wx >> 5, wy >> 5)
	if c == null:
		return
	c.timers.append({"i": (wy & 31) * MP.CHUNK + (wx & 31), "l": layer, "to": to_id, "due": time + delay, "expect": expect})
	c.touch()


## Event-driven growth/regrowth: applies every timer that is due, chaining
## multi-stage growth from the previous due time so that time spent away
## (unloaded chunk, closed game) is fully accounted for.
func process_timers(c: ChunkData) -> int:
	var applied := 0
	var guard := 0
	var n := 0
	while n < c.timers.size() and guard < 4096:
		guard += 1
		var tm: Dictionary = c.timers[n]
		if float(tm["due"]) > time:
			n += 1
			continue
		c.timers.remove_at(n)
		var i: int = tm["i"]
		var layer: int = tm["l"]
		if c.layers[layer][i] != int(tm["expect"]):
			continue
		if layer == MP.L_OBJECT and int(tm["expect"]) == 0:
			# respawn of a natural resource: only on free, unbuilt ground
			if c.layers[MP.L_STRUCT][i] != 0 or content.tiles[c.layers[0][i]].get("built", 0) == 1 or content.t_solid[c.layers[0][i]] != 0:
				continue
		var old: int = c.layers[layer][i]
		var to: int = tm["to"]
		c.layers[layer][i] = to
		c.touch()
		applied += 1
		if to != 0 and content.tiles[to].has("grow"):
			var gr: Dictionary = content.tiles[to]["grow"]
			c.timers.append({"i": i, "l": layer, "to": content.tid(gr["to"]), "due": float(tm["due"]) + float(gr["time"]), "expect": to})
		bus.tile_changed.emit(c.cx * MP.CHUNK + (i % MP.CHUNK), c.cy * MP.CHUNK + (i / MP.CHUNK), layer, old, to, false)
	if applied > 0:
		bus.chunk_changed.emit(c.cx, c.cy)
	return applied


func container_at(wx: int, wy: int) -> Array:
	var c := chunks.get_chunk(wx >> 5, wy >> 5)
	var i := (wy & 31) * MP.CHUNK + (wx & 31)
	var o: int = c.layers[2][i]
	if o == 0 or not content.tiles[o].has("container"):
		return []
	var cap := int(content.tiles[o]["container"])
	if not c.containers.has(i):
		c.containers[i] = []
	var slots: Array = c.containers[i]
	while slots.size() < cap:
		slots.append(null)
	return slots


func touch_tile_chunk(wx: int, wy: int) -> void:
	chunks.mark_modified(wx >> 5, wy >> 5)


# --- movement -----------------------------------------------------------------
func box_blocked(x: float, y: float, r: float) -> bool:
	var x0 := floori((x - r) / MP.TILE)
	var x1 := floori((x + r) / MP.TILE)
	var y0 := floori((y - r) / MP.TILE)
	var y1 := floori((y + r) / MP.TILE)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if blocked(tx, ty):
				return true
	return false


## Axis separated slide movement against the tile grid.
func move(pos: Vector2, delta: Vector2, r: float) -> Vector2:
	var steps := maxi(1, ceili(maxf(absf(delta.x), absf(delta.y)) / 6.0))
	var d := delta / steps
	for s in steps:
		if d.x != 0.0 and not box_blocked(pos.x + d.x, pos.y, r):
			pos.x += d.x
		if d.y != 0.0 and not box_blocked(pos.x, pos.y + d.y, r):
			pos.y += d.y
	return pos


## Nearest non-blocked tile centre around a tile (spiral search).
func find_free_near(t: Vector2i, max_r: int = 12) -> Vector2i:
	for r in range(0, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if not blocked(t.x + dx, t.y + dy):
					return Vector2i(t.x + dx, t.y + dy)
	return t


func line_clear(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := maxi(1, int(d.length() / 8.0))
	for i in range(1, n):
		var p := a + d * (float(i) / n)
		var tx := floori(p.x / MP.TILE)
		var ty := floori(p.y / MP.TILE)
		var o := tile(MP.L_OBJECT, tx, ty)
		if (o != 0 and content.t_solid[o] != 0 and content.tiles[o].get("tall", 0) == 1) or content.t_solid[tile(MP.L_STRUCT, tx, ty)] != 0:
			return false
	return true


# --- persistence --------------------------------------------------------------
func to_dict() -> Dictionary:
	return {"time": time, "flags": flags.duplicate(), "discovered": discovered.keys(),
		"explored": Marshalls.raw_to_base64(explored), "next_prop_id": next_prop_id, "event": event_state.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	time = float(d.get("time", time))
	flags = d.get("flags", {})
	discovered.clear()
	for s in d.get("discovered", []):
		discovered[str(s)] = true
	var ex := Marshalls.base64_to_raw(str(d.get("explored", "")))
	if ex.size() == explored.size():
		explored = ex
	next_prop_id = int(d.get("next_prop_id", 1))
	event_state = d.get("event", {})
