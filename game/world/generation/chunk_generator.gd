class_name ChunkGenerator
extends RefCounted
## Deterministic per-chunk generation ("区域细化" / "生态配置" / "美学修正").
## Pure function of (WorldPlan, cx, cy): no shared mutable state, so it may run
## on WorkerThreadPool threads and in any order.

var plan: WorldPlan
var content: ContentRegistry
var seed: int

var _b_ground := PackedByteArray()
var _b_alt := PackedByteArray()
var _b_alt_ch := PackedFloat32Array()
var _b_density := PackedFloat32Array()
var _b_trees: Array = []      # per biome: [[id, cumulative_weight], ...]
var _b_objects: Array = []    # per biome: [[id, cumulative_chance], ...]
var _b_decor: Array = []
var _b_spawns: Array = []     # per biome: [[def, cumulative_weight], ...]
var T_DEEP: int; var T_WATER: int; var T_SHALLOW: int; var T_ICE: int; var T_SAND: int
var T_MUD: int; var T_STONE: int; var T_SNOW: int; var T_CLIFF: int; var T_PATH: int
var T_BRIDGE: int; var T_REEDS: int; var T_LILY: int; var T_CANYON: int


func _init(p_plan: WorldPlan, p_content: ContentRegistry) -> void:
	plan = p_plan
	content = p_content
	seed = plan.seed
	T_DEEP = content.tid("deep_water"); T_WATER = content.tid("water"); T_SHALLOW = content.tid("shallow_water")
	T_ICE = content.tid("ice"); T_SAND = content.tid("sand"); T_MUD = content.tid("mud"); T_STONE = content.tid("stone")
	T_SNOW = content.tid("snow"); T_CLIFF = content.tid("cliff"); T_PATH = content.tid("path")
	T_BRIDGE = content.tid("bridge_wood"); T_REEDS = content.tid("reeds"); T_LILY = content.tid("lily_pad")
	T_CANYON = content.tid("canyon_rock")
	for b in content.biomes:
		_b_ground.append(content.tid(b["ground"]))
		var alt = b.get("alt", ["", 0.0])
		_b_alt.append(content.tid(alt[0]))
		_b_alt_ch.append(float(alt[1]))
		_b_density.append(float(b.get("tree_density", 0.0)))
		_b_trees.append(_cumulative(b.get("trees", []), true))
		_b_objects.append(_cumulative(b.get("objects", []), true))
		_b_decor.append(_cumulative(b.get("decor", []), true))
		_b_spawns.append(_cumulative(b.get("spawns", []), false))


func _cumulative(list: Array, as_tiles: bool) -> Array:
	var out: Array = []
	var acc := 0.0
	for e in list:
		acc += float(e[1])
		out.append([content.tid(e[0]) if as_tiles else e[0], acc])
	return out


func _pick(table: Array, r: float):
	for e in table:
		if r < e[1]:
			return e[0]
	return table[table.size() - 1][0] if table.size() > 0 else 0


func _gather(store: Dictionary, x0: int, y0: int, x1: int, y1: int) -> Array:
	if store.is_empty():
		return []
	var N := WorldPlan.N
	var cell := plan.cell
	var i0 := clampi(int(floor(x0 / cell)) - 1, 0, N - 1)
	var j0 := clampi(int(floor(y0 / cell)) - 1, 0, N - 1)
	var i1 := clampi(int(floor(x1 / cell)) + 1, 0, N - 1)
	var j1 := clampi(int(floor(y1 / cell)) + 1, 0, N - 1)
	var out: Array = []
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var segs = store.get(j * N + i)
			if segs != null:
				out.append_array(segs)
	return out


## Squared distance from (px,py) to the nearest segment minus nothing; returns
## [dist, width] of the closest segment.
static func _seg_dist(segs: Array, px: float, py: float) -> Vector2:
	var best := 1e9
	var bw := 0.0
	for s in segs:
		var ax: float = s[0]
		var ay: float = s[1]
		var dx: float = s[2] - ax
		var dy: float = s[3] - ay
		var l2 := dx * dx + dy * dy
		var t := 0.0
		if l2 > 0.0001:
			t = clampf(((px - ax) * dx + (py - ay) * dy) / l2, 0.0, 1.0)
		var qx := ax + dx * t - px
		var qy := ay + dy * t - py
		var d := qx * qx + qy * qy
		if d < best:
			best = d
			bw = s[4]
	return Vector2(sqrt(best), bw)


func generate(cx: int, cy: int) -> ChunkData:
	var c := ChunkData.new(cx, cy)
	var C := MP.CHUNK
	var N := WorldPlan.N
	var bx := cx * C
	var by := cy * C
	var g := PackedByteArray(); g.resize(MP.CHUNK_AREA)
	var st := PackedByteArray(); st.resize(MP.CHUNK_AREA)
	var ob := PackedByteArray(); ob.resize(MP.CHUNK_AREA)
	var de := PackedByteArray(); de.resize(MP.CHUNK_AREA)
	var biome_map := PackedByteArray(); biome_map.resize(MP.CHUNK_AREA)
	var E := plan.elev
	var TT := plan.temp
	var MM := plan.moist
	var cell := plan.cell
	var inv_cell := 1.0 / cell
	var nd := plan.noise_detail
	var nm := plan.noise_mid
	var nf := plan.noise_forest
	var SEA := WorldPlan.SEA
	var MOUNTAIN := WorldPlan.MOUNTAIN
	var rivers := _gather(plan.river_cells, bx - 8, by - 8, bx + C + 8, by + C + 8)
	var road_segs := _gather(plan.road_cells, bx - 4, by - 4, bx + C + 4, by + C + 4)
	var has_rivers := rivers.size() > 0
	var has_roads := road_segs.size() > 0
	var site_idx: Array = plan.site_chunks.get(MP.chunk_key(cx, cy), [])
	var fmax := float(N) - 1.001

	for ty in C:
		var wy := by + ty
		var fy := clampf((wy + 0.5) * inv_cell - 0.5, 0.0, fmax)
		var j0 := int(fy)
		var wyf := fy - j0
		for tx in C:
			var wx := bx + tx
			var fx := clampf((wx + 0.5) * inv_cell - 0.5, 0.0, fmax)
			var i0 := int(fx)
			var wxf := fx - i0
			var k := j0 * N + i0
			var dn := nd.get_noise_2d(wx, wy)
			var mn := nm.get_noise_2d(wx, wy)
			var e := lerpf(lerpf(E[k], E[k + 1], wxf), lerpf(E[k + N], E[k + N + 1], wxf), wyf) + dn * 0.006 + mn * 0.02
			var t := lerpf(lerpf(TT[k], TT[k + 1], wxf), lerpf(TT[k + N], TT[k + N + 1], wxf), wyf) + mn * 0.035 + dn * 0.012
			var m := lerpf(lerpf(MM[k], MM[k + 1], wxf), lerpf(MM[k + N], MM[k + N + 1], wxf), wyf) - mn * 0.04 + dn * 0.012
			var fo := nf.get_noise_2d(wx, wy)
			var b := WorldPlan.classify(e, t, m)
			var h := MP.h2(seed, wx, wy)
			var r1 := float(h & 0xffff) / 65536.0
			var r2 := float((h >> 16) & 0xffff) / 65536.0
			var idx := ty * C + tx
			var ground := 0
			var natural_ok := true     # may receive trees/objects
			var cliff := false
			if b == WorldPlan.B_OCEAN:
				natural_ok = false
				if t < 0.27 and e > SEA - 0.035:
					ground = T_ICE
				elif e < SEA - 0.05:
					ground = T_DEEP
				elif e < SEA - 0.012:
					ground = T_WATER
				else:
					ground = T_SHALLOW
					if t > 0.3 and t < 0.7 and r2 < 0.05:
						de[idx] = T_LILY
			else:
				ground = _b_ground[b]
				if r2 < _b_alt_ch[b]:
					ground = _b_alt[b]
				if b == WorldPlan.B_MOUNTAIN:
					if t < 0.36:
						ground = T_SNOW
					if e > MOUNTAIN + 0.012 and absf(fo) > 0.10:
						cliff = true
				elif b == WorldPlan.B_CANYON:
					if fo > 0.26:
						cliff = true
				elif b == WorldPlan.B_WETLAND:
					if fo < -0.22:
						ground = T_SHALLOW
						natural_ok = false
						if r2 < 0.12:
							de[idx] = T_LILY
			# rivers
			if has_rivers and b != WorldPlan.B_OCEAN:
				var rd := _seg_dist(rivers, wx + 0.5 + dn * 2.2, wy + 0.5 + mn * 6.0)
				if rd.x < rd.y:
					ground = T_ICE if t < 0.27 else (T_SHALLOW if rd.x > rd.y - 0.55 else T_WATER)
					natural_ok = false
					cliff = false
					de[idx] = 0
				elif rd.x < rd.y + 1.3:
					cliff = false
					natural_ok = false
					if t >= 0.30:
						ground = T_MUD if b == WorldPlan.B_WETLAND else T_SAND
						if t < 0.7 and r2 < 0.22:
							de[idx] = T_REEDS
			biome_map[idx] = b
			g[idx] = ground
			if cliff:
				st[idx] = T_CLIFF
			elif natural_ok:
				var dens := _b_density[b] * clampf(1.0 + fo * 2.2, 0.15, 2.4)
				if dens > 0.30:
					dens = 0.30
				if r1 < dens:
					ob[idx] = _pick(_b_trees[b], float((h >> 8) & 0xff) / 256.0 * _b_trees[b][_b_trees[b].size() - 1][1])
				else:
					var objs: Array = _b_objects[b]
					var rr := r1 - dens
					var placed := false
					for oe in objs:
						if rr < oe[1]:
							ob[idx] = oe[0]
							placed = true
							break
					if not placed:
						for d2 in _b_decor[b]:
							if r2 < d2[1]:
								de[idx] = d2[0]
								break

	# structures
	for si in site_idx:
		var s: Dictionary = plan.sites[si]
		var L: Dictionary = s["layout"]
		var sw: int = s["w"]
		var lg: PackedByteArray = L["g"]
		var ls: PackedByteArray = L["s"]
		var lo: PackedByteArray = L["o"]
		var ld: PackedByteArray = L["d"]
		var base_ground: int = _b_ground[s["biome"]]
		var sx: int = s["x"]
		var sy: int = s["y"]
		var sh: int = s["h"]
		var x0 := maxi(sx, bx)
		var y0 := maxi(sy, by)
		var x1 := mini(sx + sw, bx + C)
		var y1 := mini(sy + sh, by + C)
		for wy in range(y0, y1):
			for wx in range(x0, x1):
				var li := (wy - sy) * sw + (wx - sx)
				var idx := (wy - by) * C + (wx - bx)
				if lg[li] != 0:
					g[idx] = lg[li]
				elif content.t_solid[g[idx]] != 0 or content.t_water[g[idx]] != 0 or g[idx] == T_ICE:
					g[idx] = base_ground
				st[idx] = ls[li]
				if lo[li] == 255:
					ob[idx] = 0
				elif lo[li] != 0:
					ob[idx] = lo[li]
				if ld[li] == 255:
					de[idx] = 0
				elif ld[li] != 0:
					de[idx] = ld[li]
				if ob[idx] != 0 and (ld[li] == 0):
					de[idx] = 0
		for cont in L["containers"]:
			var wx: int = s["x"] + cont["x"]
			var wy: int = s["y"] + cont["y"]
			if wx >= bx and wy >= by and wx < bx + C and wy < by + C:
				c.containers[(wy - by) * C + (wx - bx)] = cont["items"].duplicate(true)
		for sp in L["spawns"]:
			var wx: int = s["x"] + sp["x"]
			var wy: int = s["y"] + sp["y"]
			if wx >= bx and wy >= by and wx < bx + C and wy < by + C:
				c.spawn_points.append({"def": sp["def"], "x": wx * MP.TILE + 8.0, "y": wy * MP.TILE + 8.0, "site": s["id"]})

	# roads: carve after structures so key routes can never be sealed by nature
	if has_roads:
		for ty in C:
			for tx in C:
				var wx := bx + tx
				var wy := by + ty
				var rd := _seg_dist(road_segs, wx + 0.5, wy + 0.5)
				if rd.x >= 2.1:
					continue
				var idx := ty * C + tx
				var site = plan.site_at_tile(wx, wy)
				if site != null:
					# inside a footprint the template wins; only fill unclaimed walkable gaps
					if rd.x < 1.0 and ob[idx] == 0 and st[idx] == 0 and content.tiles[g[idx]].get("built", 0) == 0:
						st[idx] = T_PATH
					continue
				if rd.x < 1.0:
					ob[idx] = 0
					de[idx] = 0
					var gid := g[idx]
					if content.t_water[gid] != 0:
						st[idx] = T_BRIDGE
					else:
						st[idx] = T_PATH
				else:
					# verge: keep the road readable, remove blocking nature
					if st[idx] == T_CLIFF:
						st[idx] = 0
					var o := ob[idx]
					if o != 0 and content.tiles[o].get("natural", 0) == 1 and content.tiles[o].get("big", 0) == 1:
						ob[idx] = 0

	# aesthetic pass: no decor under objects/cliffs or on water (except lilies)
	for idx in MP.CHUNK_AREA:
		if de[idx] != 0:
			if ob[idx] != 0 or st[idx] == T_CLIFF:
				de[idx] = 0
			elif content.t_solid[g[idx]] != 0:
				de[idx] = 0
		if ob[idx] != 0 and st[idx] == T_CLIFF:
			ob[idx] = 0

	# ecology / enemy spawn points
	var sp_seed := seed + 97
	for n in 4:
		var hh := MP.h2(sp_seed, cx * 8 + n, cy)
		if (hh & 0xff) > 140:
			continue
		var lx := (hh >> 8) & 31
		var ly := (hh >> 13) & 31
		var idx := ly * C + lx
		if ob[idx] != 0 or st[idx] == T_CLIFF or content.t_solid[g[idx]] != 0 or content.t_water[g[idx]] != 0:
			continue
		var wx := bx + lx
		var wy := by + ly
		if plan.site_at_tile(wx, wy) != null:
			continue
		var table: Array = _b_spawns[biome_map[idx]]
		if table.is_empty():
			continue
		var def: String = _pick(table, float((hh >> 18) & 0x3ff) / 1024.0 * table[table.size() - 1][1])
		if content.actors[def]["kind"] == "enemy":
			var dx := wx - plan.spawn_tile.x
			var dy := wy - plan.spawn_tile.y
			if dx * dx + dy * dy < 30 * 30:
				continue
		c.spawn_points.append({"def": def, "x": wx * MP.TILE + 8.0, "y": wy * MP.TILE + 8.0})

	c.layers = [g, st, ob, de]
	return c


## Biome index at a tile without generating the chunk (map, ecology, weather).
func biome_at(wx: int, wy: int) -> int:
	var N := WorldPlan.N
	var fmax := float(N) - 1.001
	var fx := clampf((wx + 0.5) / plan.cell - 0.5, 0.0, fmax)
	var fy := clampf((wy + 0.5) / plan.cell - 0.5, 0.0, fmax)
	var i0 := int(fx)
	var j0 := int(fy)
	var wxf := fx - i0
	var wyf := fy - j0
	var k := j0 * N + i0
	var mn := plan.noise_mid.get_noise_2d(wx, wy)
	var e := lerpf(lerpf(plan.elev[k], plan.elev[k + 1], wxf), lerpf(plan.elev[k + N], plan.elev[k + N + 1], wxf), wyf) + mn * 0.02
	var t := lerpf(lerpf(plan.temp[k], plan.temp[k + 1], wxf), lerpf(plan.temp[k + N], plan.temp[k + N + 1], wxf), wyf) + mn * 0.035
	var m := lerpf(lerpf(plan.moist[k], plan.moist[k + 1], wxf), lerpf(plan.moist[k + N], plan.moist[k + N + 1], wxf), wyf) - mn * 0.04
	return WorldPlan.classify(e, t, m)
