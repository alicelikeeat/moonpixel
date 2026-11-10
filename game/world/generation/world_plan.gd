class_name WorldPlan
extends RefCounted
## Macro world plan ("宏观地理结构" + sites + roads), fully determined by
## (seed, size, generator_version). Built once per world in well under a
## second and then immutable, so chunk generation can read it from any thread
## and chunk load order can never change the result.
##
## Pipeline: 1) continents/climate on a fixed 256x256 macro grid
##           2) lakes + rivers (downhill tracing)
##           3) spawn + structure sites (validated footprints, same landmass)
##           4) roads (A* on the macro grid, bridges resolved per tile)
##           5) accessibility validation (errors => plan.valid == false)

const N := 256
const SEA := 0.34
const MOUNTAIN := 0.80

const B_OCEAN := 0
const B_BEACH := 1
const B_GRASS := 2
const B_FOREST := 3
const B_SNOW := 4
const B_TAIGA := 5
const B_DESERT := 6
const B_CANYON := 7
const B_WETLAND := 8
const B_MOUNTAIN := 9

var seed: int
var size: int
var cell: float
var elev := PackedFloat32Array()
var temp := PackedFloat32Array()
var moist := PackedFloat32Array()
var flags := PackedByteArray()          # bit0 river, bit1 road
var river_cells: Dictionary = {}        # macro cell index -> Array[PackedFloat32Array(ax,ay,bx,by,w)]
var road_cells: Dictionary = {}
var sites: Array = []                   # Array[Dictionary]
var site_by_id: Dictionary = {}
var site_chunks: Dictionary = {}        # chunk key -> Array[int]
var spawn_tile := Vector2i.ZERO
var roads: Array = []                   # Array[PackedVector2Array] tile polylines
var valid := true
var errors: Array = []
var noise_detail := FastNoiseLite.new()
var noise_mid := FastNoiseLite.new()
var noise_forest := FastNoiseLite.new()
var build_ms := 0

var _sat := PackedInt32Array()
var _sat_water := PackedInt32Array()
var _comp := PackedByteArray()
var _content: ContentRegistry


static func classify(e: float, t: float, m: float) -> int:
	if e < SEA:
		return B_OCEAN
	if e > MOUNTAIN:
		return B_MOUNTAIN
	if t < 0.30:
		return B_TAIGA if m > 0.5 else B_SNOW
	if e < SEA + 0.015:
		return B_BEACH
	if t > 0.70:
		return B_CANYON if e > 0.66 else B_DESERT
	if m > 0.56 and e < 0.60:
		return B_WETLAND
	return B_FOREST if m > 0.47 else B_GRASS


func _noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = s & 0x7fffffff
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


func build(p_seed: int, p_size: int, content: ContentRegistry) -> WorldPlan:
	var t0 := Time.get_ticks_msec()
	seed = p_seed
	size = p_size
	cell = float(size) / N
	_content = content
	noise_detail = _noise(seed + 11, 0.09, 1)
	noise_mid = _noise(seed + 12, 0.017, 2)
	noise_forest = _noise(seed + 13, 0.035, 2)
	_macro()
	_rivers()
	_build_sat()
	_place_spawn()
	if valid:
		_flood_component()
		_place_sites()
	if valid:
		_build_roads()
	_index_sites()
	build_ms = Time.get_ticks_msec() - t0
	return self


func _macro() -> void:
	var ne := _noise(seed + 1, 1.0, 4)
	var nc := _noise(seed + 2, 1.0, 2)
	var nt := _noise(seed + 3, 1.0, 2)
	var nm := _noise(seed + 4, 1.0, 3)
	var nl := _noise(seed + 5, 1.0, 1)
	elev.resize(N * N); temp.resize(N * N); moist.resize(N * N); flags.resize(N * N)
	var inv := 1.0 / N
	for j in N:
		var v := (j + 0.5) * inv
		for i in N:
			var u := (i + 0.5) * inv
			var base := clampf(0.5 + 0.62 * ne.get_noise_2d(u * 5.0, v * 5.0), 0.0, 1.0)
			var edge := maxf(absf(2.0 * u - 1.0), absf(2.0 * v - 1.0)) + nc.get_noise_2d(u * 6.0, v * 6.0) * 0.14
			var fall := 1.0 - smoothstep(0.66, 0.97, edge)
			var e := (0.30 + 0.70 * base) * fall
			var ln := nl.get_noise_2d(u * 14.0, v * 14.0)
			if ln > 0.62 and e > SEA and e < 0.62:
				e = lerpf(e, SEA - 0.07, smoothstep(0.62, 0.72, ln))
			var t := clampf((v - 0.12) / 0.76, 0.0, 1.0) + nt.get_noise_2d(u * 4.0, v * 4.0) * 0.10 - maxf(0.0, e - 0.6) * 0.4
			var m := clampf(0.5 + 0.75 * nm.get_noise_2d(u * 6.0, v * 6.0), 0.0, 1.0)
			var k := j * N + i
			elev[k] = e
			temp[k] = clampf(t, 0.0, 1.0)
			moist[k] = m


func cell_center(i: int, j: int, salt: int) -> Vector2:
	var jx := MP.h01(seed + salt, i, j) - 0.5
	var jy := MP.h01(seed + salt + 1, i, j) - 0.5
	return Vector2((i + 0.5 + jx * 0.6) * cell, (j + 0.5 + jy * 0.6) * cell)


func _add_seg(store: Dictionary, k: int, a: Vector2, b: Vector2, w: float) -> void:
	if not store.has(k):
		store[k] = []
	store[k].append(PackedFloat32Array([a.x, a.y, b.x, b.y, w]))


func _rivers() -> void:
	var cands: Array = []
	for j in range(8, N - 8, 6):
		for i in range(8, N - 8, 6):
			var h := MP.h2(seed + 21, i, j)
			var ci := i + (h & 3)
			var cj := j + ((h >> 2) & 3)
			var e := elev[cj * N + ci]
			if e > 0.60 and e < MOUNTAIN + 0.08:
				cands.append([h, ci, cj])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var count := 0
	for cnd in cands:
		if count >= 16:
			break
		var path: Array = []
		var visited := {}
		var ci: int = cnd[1]
		var cj: int = cnd[2]
		var ok := false
		for step in 900:
			var k := cj * N + ci
			if flags[k] & 1:
				path.append(Vector2i(ci, cj))
				ok = true
				break
			path.append(Vector2i(ci, cj))
			visited[k] = true
			if elev[k] < SEA:
				ok = true
				break
			var best := -1
			var best_e := 9.0
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ni: int = ci + d[0]
				var nj: int = cj + d[1]
				if ni < 1 or nj < 1 or ni >= N - 1 or nj >= N - 1:
					continue
				var nk := nj * N + ni
				if visited.has(nk):
					continue
				var ne := elev[nk] + MP.h01(seed + 22, ni, nj) * 0.006
				if ne < best_e:
					best_e = ne
					best = nk
			if best < 0:
				break
			ci = best % N
			cj = best / N
		if not ok or path.size() < 8:
			continue
		count += 1
		var n := path.size()
		for p in n - 1:
			var a: Vector2i = path[p]
			var b: Vector2i = path[p + 1]
			var w := 1.1 + 1.5 * float(p) / float(n)
			flags[a.y * N + a.x] |= 1
			_add_seg(river_cells, a.y * N + a.x, cell_center(a.x, a.y, 31), cell_center(b.x, b.y, 31), w)


func _blocked(k: int) -> bool:
	var e := elev[k]
	return e < SEA + 0.012 or e > MOUNTAIN - 0.02 or (flags[k] & 1) != 0


func _build_sat() -> void:
	_sat.resize((N + 1) * (N + 1))
	_sat.fill(0)
	_sat_water.resize((N + 1) * (N + 1))
	_sat_water.fill(0)
	for j in N:
		var row := 0
		var row_w := 0
		for i in N:
			if _blocked(j * N + i):
				row += 1
			if elev[j * N + i] < SEA + 0.012:
				row_w += 1
			_sat[(j + 1) * (N + 1) + i + 1] = _sat[j * (N + 1) + i + 1] + row
			_sat_water[(j + 1) * (N + 1) + i + 1] = _sat_water[j * (N + 1) + i + 1] + row_w


## True when the tile rect (plus margin) only covers buildable macro cells.
func rect_clear(tx: int, ty: int, w: int, h: int, margin: int, strict: bool = true) -> bool:
	var x0 := tx - margin
	var y0 := ty - margin
	var x1 := tx + w + margin
	var y1 := ty + h + margin
	if x0 < 16 or y0 < 16 or x1 > size - 16 or y1 > size - 16:
		return false
	var i0 := clampi(int(floor(x0 / cell)), 0, N - 1)
	var j0 := clampi(int(floor(y0 / cell)), 0, N - 1)
	var i1 := clampi(int(floor((x1 - 0.001) / cell)) + 1, 1, N)
	var j1 := clampi(int(floor((y1 - 0.001) / cell)) + 1, 1, N)
	var sat := _sat if strict else _sat_water
	var s := sat[j1 * (N + 1) + i1] - sat[j0 * (N + 1) + i1] - sat[j1 * (N + 1) + i0] + sat[j0 * (N + 1) + i0]
	return s == 0


func cell_of_tile(tx: int, ty: int) -> int:
	return clampi(int(ty / cell), 0, N - 1) * N + clampi(int(tx / cell), 0, N - 1)


func biome_of_cell(k: int) -> int:
	return classify(elev[k], temp[k], moist[k])


func _overlaps_site(x: int, y: int, w: int, h: int, pad: int) -> bool:
	var r := Rect2i(x - pad, y - pad, w + pad * 2, h + pad * 2)
	for s in sites:
		if r.intersects(Rect2i(s["x"], s["y"], s["w"], s["h"])):
			return true
	return false


func _add_site(type: String, id: String, x: int, y: int) -> Dictionary:
	var sz := StructureTemplates.size_of(type)
	var s := {"id": id, "type": type, "x": x, "y": y, "w": sz.x, "h": sz.y, "seed": MP.h2(seed + 41, x, y)}
	var ck := cell_of_tile(x + sz.x / 2, y + sz.y / 2)
	var b := biome_of_cell(ck)
	s["biome"] = b
	s["layout"] = StructureTemplates.build(type, s["seed"], _content)
	var a: Vector2i = s["layout"]["anchors"].get("center", Vector2i(sz.x / 2, sz.y / 2))
	s["ax"] = x + a.x
	s["ay"] = y + a.y
	sites.append(s)
	site_by_id[id] = s
	return s


func _place_spawn() -> void:
	var c := N / 2
	var sz := StructureTemplates.size_of("spawn")
	for pass_i in 2:
		for r in range(0, N / 2 - 8):
			for j in range(c - r, c + r + 1):
				var edge_row := (j == c - r or j == c + r)
				var i := c - r
				while i <= c + r:
					var k := j * N + i
					var b := biome_of_cell(k)
					var good := (b == B_GRASS or b == B_FOREST) if pass_i == 0 else (b != B_OCEAN and b != B_MOUNTAIN)
					if good:
						var tx := int((i + 0.5) * cell) - sz.x / 2
						var ty := int((j + 0.5) * cell) - sz.y / 2
						if rect_clear(tx, ty, sz.x, sz.y, 6):
							var s := _add_site("spawn", "spawn", tx, ty)
							spawn_tile = Vector2i(s["ax"], s["ay"])
							return
					i += 1 if edge_row else maxi(1, 2 * r)
	valid = false
	errors.append("no valid spawn location")


func _flood_component() -> void:
	_comp.resize(N * N)
	_comp.fill(0)
	var start := cell_of_tile(spawn_tile.x, spawn_tile.y)
	var stack := PackedInt32Array([start])
	_comp[start] = 1
	while stack.size() > 0:
		var k := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var i := k % N
		var j := k / N
		if i > 0 and _comp[k - 1] == 0 and elev[k - 1] >= SEA:
			_comp[k - 1] = 1; stack.append(k - 1)
		if i < N - 1 and _comp[k + 1] == 0 and elev[k + 1] >= SEA:
			_comp[k + 1] = 1; stack.append(k + 1)
		if j > 0 and _comp[k - N] == 0 and elev[k - N] >= SEA:
			_comp[k - N] = 1; stack.append(k - N)
		if j < N - 1 and _comp[k + N] == 0 and elev[k + N] >= SEA:
			_comp[k + N] = 1; stack.append(k + N)


## Deterministic search for a footprint around `center` within [rmin, rmax] tiles.
func _find_site(type: String, center: Vector2i, rmin: float, rmax: float, salt: int, avoid: Array) -> Vector2i:
	var sz := StructureTemplates.size_of(type)
	# progressively relaxed: strict footprint -> wider ring -> rivers/mountains
	# allowed under the footprint (the template flattens them) -> anywhere
	for attempt in 5:
		var lo: float = rmin * [1.0, 0.7, 1.0, 0.6, 0.35][attempt]
		var hi: float = rmax * [1.0, 1.5, 1.2, 2.0, 6.0][attempt]
		var strict := attempt < 2
		var relax_avoid := 1.0 if attempt < 3 else (0.6 if attempt == 3 else 0.3)
		for k in 500:
			var ang := MP.h01(seed + salt, k, attempt) * TAU
			var rad := lerpf(lo, hi, sqrt(MP.h01(seed + salt + 1, k, attempt)))
			var px := center.x + int(cos(ang) * rad)
			var py := center.y + int(sin(ang) * rad)
			var tx := px - sz.x / 2
			var ty := py - sz.y / 2
			if not rect_clear(tx, ty, sz.x, sz.y, 4, strict):
				continue
			if _comp[cell_of_tile(px, py)] == 0:
				continue
			if _overlaps_site(tx, ty, sz.x, sz.y, 12):
				continue
			var far := true
			for a in avoid:
				if Vector2(px - a[0].x, py - a[0].y).length() < a[1] * relax_avoid:
					far = false
					break
			if far:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _place_sites() -> void:
	var p := _find_site("village", spawn_tile, 70.0, 125.0, 51, [])
	if p.x < 0:
		valid = false
		errors.append("no village site")
		return
	var village := _add_site("village", "village", p.x, p.y)
	var vpos := Vector2i(village["ax"], village["ay"])
	p = _find_site("dungeon", vpos, 100.0, 180.0, 53, [[spawn_tile, 110.0]])
	if p.x < 0:
		valid = false
		errors.append("no dungeon site")
		return
	_add_site("dungeon", "dungeon", p.x, p.y)
	p = _find_site("camp", vpos, 55.0, 100.0, 55, [[spawn_tile, 55.0]])
	if p.x < 0:
		valid = false
		errors.append("no camp site")
		return
	_add_site("camp", "camp_0", p.x, p.y)
	var scale := size / 512
	var centre := Vector2i(size / 2, size / 2)
	var n_camps := clampi(3 * scale, 3, 24)
	var n_ruins := clampi(4 * scale, 4, 32)
	for i in n_camps:
		p = _find_site("camp", centre, 40.0, size * 0.42, 60 + i * 2, [[spawn_tile, 70.0], [vpos, 60.0]])
		if p.x >= 0:
			_add_site("camp", "camp_%d" % (i + 1), p.x, p.y)
	for i in n_ruins:
		p = _find_site("ruin", centre, 30.0, size * 0.42, 160 + i * 2, [[spawn_tile, 40.0]])
		if p.x >= 0:
			_add_site("ruin", "ruin_%d" % i, p.x, p.y)


func _route(grid: AStarGrid2D, from: Vector2i, to: Vector2i) -> bool:
	var a := Vector2i(clampi(int(from.x / cell), 0, N - 1), clampi(int(from.y / cell), 0, N - 1))
	var b := Vector2i(clampi(int(to.x / cell), 0, N - 1), clampi(int(to.y / cell), 0, N - 1))
	grid.set_point_solid(a, false)
	grid.set_point_solid(b, false)
	var path := grid.get_id_path(a, b)
	if path.size() == 0:
		return false
	var pts := PackedVector2Array()
	pts.append(Vector2(from.x + 0.5, from.y + 0.5))
	for i in range(1, path.size() - 1):
		pts.append(cell_center(path[i].x, path[i].y, 71))
	pts.append(Vector2(to.x + 0.5, to.y + 0.5))
	roads.append(pts)
	for i in pts.size() - 1:
		var k := cell_of_tile(int(pts[i].x), int(pts[i].y))
		flags[k] |= 2
		_add_seg(road_cells, k, pts[i], pts[i + 1], 1.0)
	return true


func _build_roads() -> void:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, N, N)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for j in N:
		for i in N:
			var k := j * N + i
			var e := elev[k]
			if e < SEA:
				grid.set_point_solid(Vector2i(i, j), true)
			elif flags[k] & 1:
				grid.set_point_weight_scale(Vector2i(i, j), 5.0)
			elif e > MOUNTAIN - 0.02:
				grid.set_point_weight_scale(Vector2i(i, j), 7.0)
			elif e < SEA + 0.012:
				grid.set_point_weight_scale(Vector2i(i, j), 2.0)
	var dungeon: Dictionary = site_by_id["dungeon"]
	var i0 := int(dungeon["x"] / cell)
	var j0 := int(dungeon["y"] / cell)
	var i1 := int((dungeon["x"] + dungeon["w"] - 1) / cell)
	var j1 := int((dungeon["y"] + dungeon["h"] - 1) / cell)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			grid.set_point_solid(Vector2i(i, j), true)
	var v: Dictionary = site_by_id["village"]
	var links := [[spawn_tile, Vector2i(v["ax"], v["ay"]), "spawn->village"],
		[Vector2i(v["ax"], v["ay"]), Vector2i(dungeon["ax"], dungeon["ay"]), "village->dungeon"],
		[Vector2i(v["ax"], v["ay"]), Vector2i(site_by_id["camp_0"]["ax"], site_by_id["camp_0"]["ay"]), "village->camp"]]
	for l in links:
		if not _route(grid, l[0], l[1]):
			valid = false
			errors.append("no route " + str(l[2]))


func _index_sites() -> void:
	for idx in sites.size():
		var s: Dictionary = sites[idx]
		for cy in range(s["y"] / MP.CHUNK, (s["y"] + s["h"] - 1) / MP.CHUNK + 1):
			for cx in range(s["x"] / MP.CHUNK, (s["x"] + s["w"] - 1) / MP.CHUNK + 1):
				var k := MP.chunk_key(cx, cy)
				if not site_chunks.has(k):
					site_chunks[k] = []
				site_chunks[k].append(idx)


func site_at_tile(tx: int, ty: int):
	var k := MP.chunk_key(tx / MP.CHUNK, ty / MP.CHUNK)
	for idx in site_chunks.get(k, []):
		var s: Dictionary = sites[idx]
		if tx >= s["x"] and ty >= s["y"] and tx < s["x"] + s["w"] and ty < s["y"] + s["h"]:
			return s
	return null


func site_anchor(site_id: String, anchor: String) -> Vector2i:
	var s = site_by_id.get(site_id)
	if s == null:
		return Vector2i(-1, -1)
	var a: Vector2i = s["layout"]["anchors"].get(anchor, Vector2i(s["w"] / 2, s["h"] / 2))
	return Vector2i(s["x"] + a.x, s["y"] + a.y)


## Share of land cells per biome family; used by tests and the world creator preview.
func biome_stats() -> Dictionary:
	var out := {"temperate": 0, "snow": 0, "desert": 0, "wetland": 0, "land": 0}
	for k in N * N:
		var b := biome_of_cell(k)
		if b == B_OCEAN:
			continue
		out["land"] += 1
		match b:
			B_GRASS, B_FOREST: out["temperate"] += 1
			B_SNOW, B_TAIGA: out["snow"] += 1
			B_DESERT, B_CANYON: out["desert"] += 1
			B_WETLAND: out["wetland"] += 1
	return out
