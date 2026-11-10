class_name OpenWorld
extends RefCounted
## Unbounded world: chunks are generated on demand at any coordinate, kept in
## a cache whose size comes from the MemoryBudget, and evicted least recently
## used first. Modified chunks are written to disk before eviction, so the
## world can grow without limit while memory stays bounded.
##
## The world also grows by itself: survey() explores outwards from points of
## interest (settlements, expeditions, the player) and records one byte per
## chunk in a region map, which is what the map screen draws.
##
## Main-thread only.

signal tile_changed(x: int, y: int, layer: int, old_id: int, new_id: int)
signal chunk_changed(cx: int, cy: int)
signal props_changed()

const REGION := 64                      # survey regions are 64x64 chunks
const YEAR := MP.DAY_SECONDS            # one in-game year = one day/night cycle

var seed: int
var content: ContentRegistry
var gen: InfiniteGenerator
var budget: MemoryBudget
var cache: Dictionary = {}              # chunk key -> ChunkData
var pins: Dictionary = {}               # chunk key -> pin count
var regions: Dictionary = {}            # Vector2i -> PackedByteArray(REGION*REGION), 0 unknown else biome+1
var surveyed := 0
var generated := 0
var evicted := 0
var time := 0.3 * MP.DAY_SECONDS
var dir := ""                           # save directory ("" = memory only)
var saved: Dictionary = {}              # chunk key -> true
var next_prop_id := 1
var _clock := 0
var _ring: Dictionary = {}              # survey cursor per centre
var _timer_acc := 0.0


func _init(p_seed: int, p_content: ContentRegistry, p_budget: MemoryBudget) -> void:
	seed = p_seed
	content = p_content
	budget = p_budget
	gen = InfiniteGenerator.new(seed, content)


func open_dir(p_dir: String) -> void:
	dir = p_dir
	DirAccess.make_dir_recursive_absolute(dir.path_join("chunks"))
	var d := DirAccess.open(dir.path_join("chunks"))
	if d != null:
		for f in d.get_files():
			if f.ends_with(".bin"):
				var parts := f.get_basename().split("_")
				if parts.size() == 3:
					saved[MP.chunk_key(int(parts[1]), int(parts[2]))] = true


func _path(cx: int, cy: int) -> String:
	return dir.path_join("chunks").path_join("c_%d_%d.bin" % [cx, cy])


# --- time ---------------------------------------------------------------------
func year() -> int:
	return int(time / YEAR)


func hour() -> float:
	return fposmod(time, MP.DAY_SECONDS) / MP.DAY_SECONDS * 24.0


func is_night() -> bool:
	var h := hour()
	return h < 5.5 or h >= 20.5


func daylight() -> float:
	var h := hour()
	if h < 4.5 or h >= 21.0:
		return 0.0
	if h < 7.0:
		return (h - 4.5) / 2.5
	if h < 18.5:
		return 1.0
	return 1.0 - (h - 18.5) / 2.5


func advance(dt: float) -> void:
	time += dt
	_timer_acc += dt
	if _timer_acc >= 2.0:
		_timer_acc = 0.0
		for k in cache:
			var c: ChunkData = cache[k]
			if c.timers.size() > 0:
				process_timers(c)


# --- chunks -------------------------------------------------------------------
func get_chunk(cx: int, cy: int) -> ChunkData:
	var k := MP.chunk_key(cx, cy)
	var c: ChunkData = cache.get(k)
	if c == null:
		if saved.has(k):
			c = ChunkData.from_bytes(FileAccess.get_file_as_bytes(_path(cx, cy)))
			if c != null:
				c.dirty = false
		if c == null:
			c = gen.generate(cx, cy)
			generated += 1
		cache[k] = c
		_mark(cx, cy)
		if c.timers.size() > 0:
			process_timers(c)
	_clock += 1
	c.last_used = _clock
	return c


func loaded(cx: int, cy: int) -> bool:
	return cache.has(MP.chunk_key(cx, cy))


func pin(cx: int, cy: int) -> void:
	var k := MP.chunk_key(cx, cy)
	pins[k] = int(pins.get(k, 0)) + 1
	get_chunk(cx, cy)


func unpin(cx: int, cy: int) -> void:
	var k := MP.chunk_key(cx, cy)
	var n := int(pins.get(k, 0)) - 1
	if n <= 0:
		pins.erase(k)
	else:
		pins[k] = n


## Keep the cache inside the memory budget. Returns the number of chunks dropped.
func maintain() -> int:
	var limit := budget.max_chunks
	if budget.pressure() > 1.0:
		limit = maxi(pins.size() + 64, int(cache.size() * 0.7))
	if cache.size() <= limit:
		return 0
	var list: Array = []
	for k in cache:
		if not pins.has(k):
			list.append(cache[k])
	list.sort_custom(func(a, b): return a.last_used < b.last_used)
	var removed := 0
	var target := int(limit * 0.9)
	for c in list:
		if cache.size() <= target:
			break
		if c.dirty and not _write(c):
			continue
		cache.erase(c.key())
		removed += 1
	evicted += removed
	return removed


func _write(c: ChunkData) -> bool:
	if dir == "":
		return not c.modified       # memory-only worlds can only drop pristine chunks
	if not SaveService.atomic_write(_path(c.cx, c.cy), c.to_bytes()):
		return false
	c.dirty = false
	saved[c.key()] = true
	return true


func save_all() -> int:
	var n := 0
	for k in cache:
		var c: ChunkData = cache[k]
		if c.dirty and _write(c):
			n += 1
	return n


# --- survey (self-expanding map) -------------------------------------------------
func _mark(cx: int, cy: int) -> bool:
	var rk := Vector2i(floori(float(cx) / REGION), floori(float(cy) / REGION))
	var r = regions.get(rk)
	if r == null:
		r = PackedByteArray()
		r.resize(REGION * REGION)
		regions[rk] = r
	var i := posmod(cy, REGION) * REGION + posmod(cx, REGION)
	if r[i] != 0:
		return false
	r[i] = gen.biome_at(cx * MP.CHUNK + 16, cy * MP.CHUNK + 16) + 1
	regions[rk] = r
	surveyed += 1
	return true


func known(cx: int, cy: int) -> int:
	var r = regions.get(Vector2i(floori(float(cx) / REGION), floori(float(cy) / REGION)))
	if r == null:
		return 0
	return r[posmod(cy, REGION) * REGION + posmod(cx, REGION)]


## Explore up to `count` new chunks in growing rings around a chunk position.
## Costs one climate sample per chunk; no terrain is generated or kept.
func survey(center: Vector2i, count: int, max_radius: int = 4096) -> int:
	var r := int(_ring.get(center, 0))
	var done := 0
	while done < count and r <= max_radius:
		var any_unknown := false
		for dy in range(-r, r + 1):
			var step := 1 if absi(dy) == r else maxi(1, 2 * r)
			var dx := -r
			while dx <= r:
				if known(center.x + dx, center.y + dy) == 0:
					if done < count:
						_mark(center.x + dx, center.y + dy)
						done += 1
					else:
						any_unknown = true
				dx += step
		if any_unknown:
			break
		r += 1
	_ring[center] = r
	return done


# --- tiles ----------------------------------------------------------------------
func tile(layer: int, wx: int, wy: int) -> int:
	return get_chunk(wx >> 5, wy >> 5).layers[layer][(wy & 31) * MP.CHUNK + (wx & 31)]


func blocked(wx: int, wy: int) -> bool:
	var c := get_chunk(wx >> 5, wy >> 5)
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


func is_land(wx: int, wy: int) -> bool:
	var g := tile(MP.L_GROUND, wx, wy)
	return content.t_water[g] == 0 and content.t_solid[tile(MP.L_STRUCT, wx, wy)] == 0


func set_tile(layer: int, wx: int, wy: int, id: int) -> void:
	var c := get_chunk(wx >> 5, wy >> 5)
	var i := (wy & 31) * MP.CHUNK + (wx & 31)
	var old: int = c.layers[layer][i]
	if old == id:
		return
	c.layers[layer][i] = id
	c.touch()
	for n in range(c.timers.size() - 1, -1, -1):
		if c.timers[n]["i"] == i and c.timers[n]["l"] == layer:
			c.timers.remove_at(n)
	if id != 0 and content.tiles[id].has("grow"):
		var gr: Dictionary = content.tiles[id]["grow"]
		c.timers.append({"i": i, "l": layer, "to": content.tid(gr["to"]), "due": time + float(gr["time"]), "expect": id})
	tile_changed.emit(wx, wy, layer, old, id)
	chunk_changed.emit(c.cx, c.cy)


func schedule(wx: int, wy: int, layer: int, to_id: int, delay: float, expect: int) -> void:
	var c := get_chunk(wx >> 5, wy >> 5)
	c.timers.append({"i": (wy & 31) * MP.CHUNK + (wx & 31), "l": layer, "to": to_id, "due": time + delay, "expect": expect})
	c.touch()


## Growth and regrowth catch up from their due times, so plants keep growing
## while a chunk is evicted or the game is closed.
func process_timers(c: ChunkData) -> void:
	var n := 0
	var changed := false
	var guard := 0
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
		var old: int = c.layers[layer][i]
		var to: int = tm["to"]
		c.layers[layer][i] = to
		c.touch()
		changed = true
		if to != 0 and content.tiles[to].has("grow"):
			var gr: Dictionary = content.tiles[to]["grow"]
			c.timers.append({"i": i, "l": layer, "to": content.tid(gr["to"]), "due": float(tm["due"]) + float(gr["time"]), "expect": to})
		tile_changed.emit(c.cx * MP.CHUNK + (i % MP.CHUNK), c.cy * MP.CHUNK + (i / MP.CHUNK), layer, old, to)
	if changed:
		chunk_changed.emit(c.cx, c.cy)


# --- free-positioned objects (imported assets, decorations) ------------------------
func add_prop(key: String, pos: Vector2) -> int:
	var c := get_chunk(floori(pos.x / MP.CHUNK_PX), floori(pos.y / MP.CHUNK_PX))
	var id := next_prop_id
	next_prop_id += 1
	c.props.append({"id": id, "key": key, "x": pos.x, "y": pos.y, "rot": 0, "z": 0})
	c.touch()
	props_changed.emit()
	return id


func remove_prop_near(pos: Vector2, radius: float = 14.0) -> bool:
	var cc := Vector2i(floori(pos.x / MP.CHUNK_PX), floori(pos.y / MP.CHUNK_PX))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := get_chunk(cc.x + dx, cc.y + dy)
			for i in c.props.size():
				if Vector2(c.props[i]["x"], c.props[i]["y"]).distance_to(pos) <= radius:
					c.props.remove_at(i)
					c.touch()
					props_changed.emit()
					return true
	return false


func find_free_near(t: Vector2i, max_r: int = 12) -> Vector2i:
	for r in range(0, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and not blocked(t.x + dx, t.y + dy):
					return Vector2i(t.x + dx, t.y + dy)
	return t


## Nearest land spot suitable for a camp, searching outwards from a tile.
func find_site(from: Vector2i, min_r: int, max_r: int, salt: int, avoid: Array, avoid_dist: float) -> Vector2i:
	for k in 200:
		var ang := MP.h01(seed + salt, k, 1) * TAU
		var rad := lerpf(min_r, max_r, MP.h01(seed + salt, k, 2))
		var p := from + Vector2i(int(cos(ang) * rad), int(sin(ang) * rad))
		var c := gen.climate(p.x, p.y)
		var b := WorldPlan.classify(c.x, c.y, c.z)
		if b == WorldPlan.B_OCEAN or b == WorldPlan.B_MOUNTAIN or b == WorldPlan.B_CANYON:
			continue
		var ok := true
		for a in avoid:
			if Vector2(p - a).length() < avoid_dist:
				ok = false
				break
		if not ok:
			continue
		# the core of the site must be dry land
		var land := 0
		for dy in range(-10, 11, 5):
			for dx in range(-10, 11, 5):
				var cc := gen.climate(p.x + dx, p.y + dy)
				if cc.x >= InfiniteGenerator.SEA + 0.01 and cc.x < InfiniteGenerator.MOUNTAIN and not gen.is_river(p.x + dx, p.y + dy, cc.x):
					land += 1
		if land >= 23:
			return p
	return Vector2i(0x7fffffff, 0)


func to_dict() -> Dictionary:
	var reg := {}
	for rk in regions:
		reg["%d,%d" % [rk.x, rk.y]] = Marshalls.raw_to_base64(regions[rk].compress(FileAccess.COMPRESSION_DEFLATE))
	return {"seed": seed, "time": time, "regions": reg, "surveyed": surveyed, "next_prop_id": next_prop_id}


func from_dict(d: Dictionary) -> void:
	time = float(d.get("time", time))
	next_prop_id = int(d.get("next_prop_id", 1))
	regions.clear()
	surveyed = 0
	var reg = d.get("regions", {})
	if reg is Dictionary:
		for k in reg:
			var parts := str(k).split(",")
			var raw := Marshalls.base64_to_raw(str(reg[k])).decompress(REGION * REGION, FileAccess.COMPRESSION_DEFLATE)
			if parts.size() == 2 and raw.size() == REGION * REGION:
				regions[Vector2i(int(parts[0]), int(parts[1]))] = raw
				for v in raw:
					if v != 0:
						surveyed += 1
