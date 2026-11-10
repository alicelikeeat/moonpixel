class_name StructureTemplates
extends RefCounted
## Deterministic, parameterised structure layouts ("人工环境生成").
## A layout is a plain Dictionary:
##   w,h           footprint in tiles
##   g,s,o,d       PackedByteArray per layer; 0 = keep natural, 255 = force clear
##   containers    [{x,y,items:[[id,count],..]}]
##   spawns        [{def,x,y}]  (tile coords local to the footprint)
##   anchors       {name: Vector2i}  (local tile coords, may lie outside)
## The same layouts are used by the world generator, the World Artisan and
## blueprints, so everything placed in the world goes through one format.

const CLEAR := 255

const LOOT := {
	"house": [["bread", 0.6, 1, 2], ["coin", 0.8, 3, 9], ["rope", 0.4, 1, 2], ["berry", 0.5, 2, 5], ["wheat_seeds", 0.5, 2, 4]],
	"camp": [["coin", 1.0, 12, 25], ["arrow", 0.9, 8, 16], ["bread", 0.7, 1, 3], ["copper_ingot", 0.6, 1, 3], ["health_potion", 0.5, 1, 1]],
	"ruin_small": [["coin", 0.9, 5, 15], ["bone", 0.6, 1, 3], ["copper_ore", 0.5, 2, 4], ["health_potion", 0.35, 1, 1], ["moonstone", 0.15, 1, 1]],
	"ruin": [["coin", 1.0, 15, 35], ["moonstone", 0.6, 1, 2], ["iron_ingot", 0.6, 1, 3], ["health_potion", 0.7, 1, 2], ["mana_potion", 0.5, 1, 2], ["arrow", 0.6, 6, 14]],
}


class Layout:
	var w: int
	var h: int
	var g := PackedByteArray()
	var s := PackedByteArray()
	var o := PackedByteArray()
	var d := PackedByteArray()
	var containers: Array = []
	var spawns: Array = []
	var anchors: Dictionary = {}
	var c: ContentRegistry
	var seed: int
	var _n := 0

	func _init(p_w: int, p_h: int, p_c: ContentRegistry, p_seed: int) -> void:
		w = p_w; h = p_h; c = p_c; seed = p_seed
		for a in [g, s, o, d]:
			a.resize(w * h)
		# PackedByteArray members are value-shared; resize through members directly
		g.resize(w * h); s.resize(w * h); o.resize(w * h); d.resize(w * h)

	func rnd() -> float:
		_n += 1
		return MP.h01(seed, _n, 7919)

	func rndi(n: int) -> int:
		return int(rnd() * n) % max(n, 1)

	func inside(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h

	func put(layer: int, x: int, y: int, key) -> void:
		if not inside(x, y):
			return
		var v: int = key if key is int else c.tid(key)
		match layer:
			0: g[y * w + x] = v
			1: s[y * w + x] = v
			2: o[y * w + x] = v
			3: d[y * w + x] = v

	func at(layer: int, x: int, y: int) -> int:
		if not inside(x, y):
			return 0
		match layer:
			0: return g[y * w + x]
			1: return s[y * w + x]
			2: return o[y * w + x]
		return d[y * w + x]

	func fill(layer: int, x: int, y: int, fw: int, fh: int, key) -> void:
		for yy in range(y, y + fh):
			for xx in range(x, x + fw):
				put(layer, xx, yy, key)

	func outline(layer: int, x: int, y: int, fw: int, fh: int, key) -> void:
		for xx in range(x, x + fw):
			put(layer, xx, y, key)
			put(layer, xx, y + fh - 1, key)
		for yy in range(y, y + fh):
			put(layer, x, yy, key)
			put(layer, x + fw - 1, yy, key)

	func clear_all() -> void:
		o.fill(CLEAR)
		d.fill(CLEAR)

	func chest(x: int, y: int, table: String) -> void:
		put(2, x, y, "chest")
		var items: Array = []
		for e in StructureTemplates.LOOT[table]:
			if rnd() < e[1]:
				items.append([e[0], int(e[2]) + rndi(int(e[3]) - int(e[2]) + 1)])
		containers.append({"x": x, "y": y, "items": items})

	func spawn(def: String, x: int, y: int) -> void:
		spawns.append({"def": def, "x": x, "y": y})

	## Walled room with a floor and a door gap. door_side: 0 N, 1 E, 2 S, 3 W.
	func room(x: int, y: int, rw: int, rh: int, wall: String, floor_key: String, door_side: int, door_key: String = "door_wood") -> Vector2i:
		fill(0, x, y, rw, rh, floor_key)
		fill(2, x, y, rw, rh, CLEAR)
		fill(3, x, y, rw, rh, CLEAR)
		outline(2, x, y, rw, rh, wall)
		var dp := Vector2i(x + rw / 2, y)
		match door_side:
			1: dp = Vector2i(x + rw - 1, y + rh / 2)
			2: dp = Vector2i(x + rw / 2, y + rh - 1)
			3: dp = Vector2i(x, y + rh / 2)
		put(2, dp.x, dp.y, door_key if door_key != "" else CLEAR)
		return dp

	func to_dict() -> Dictionary:
		return {"w": w, "h": h, "g": g, "s": s, "o": o, "d": d, "containers": containers, "spawns": spawns, "anchors": anchors}


static func size_of(type: String) -> Vector2i:
	match type:
		"spawn": return Vector2i(14, 14)
		"village": return Vector2i(48, 48)
		"dungeon": return Vector2i(53, 53)
		"camp": return Vector2i(16, 16)
		"ruin": return Vector2i(12, 12)
	return Vector2i(8, 8)


static func build(type: String, seed: int, c: ContentRegistry) -> Dictionary:
	match type:
		"spawn": return _spawn(seed, c)
		"village": return _village(seed, c)
		"dungeon": return _dungeon(seed, c)
		"camp": return _camp(seed, c)
		"ruin": return _ruin(seed, c)
	return Layout.new(1, 1, c, seed).to_dict()


static func _spawn(seed: int, c: ContentRegistry) -> Dictionary:
	var L := Layout.new(14, 14, c, seed)
	for y in 14:
		for x in 14:
			var dx := x - 6.5
			var dy := y - 6.5
			if dx * dx + dy * dy < 30.0:
				L.put(2, x, y, CLEAR)
	L.put(2, 7, 6, "campfire_out")
	L.put(2, 9, 5, "sign")
	L.put(2, 4, 5, "tent")
	# guaranteed starter resources ("必需的初始资源必须可到达")
	for p in [[1, 1], [12, 2], [2, 11], [11, 12], [0, 6], [13, 8]]:
		L.put(2, p[0], p[1], "tree_oak")
	for p in [[3, 1], [12, 5], [1, 9], [10, 12]]:
		L.put(2, p[0], p[1], "rock")
	L.put(2, 5, 12, "berry_bush")
	L.put(2, 8, 1, "bush")
	L.put(2, 12, 10, "bush")
	L.put(3, 6, 9, "flower_yellow")
	L.put(3, 9, 8, "flower_red")
	L.anchors["center"] = Vector2i(7, 8)
	return L.to_dict()


static func house(L: Layout, x: int, y: int, hw: int, hh: int, wall: String, door_side: int, loot: bool) -> Vector2i:
	var dp := L.room(x, y, hw, hh, wall, "wood_floor", door_side)
	var ix := x + 1
	var iy := y + 1
	var bottom_door := door_side == 2
	var fy := iy if bottom_door else y + hh - 2     # furniture row far from the door
	L.put(2, ix, fy, "bed")
	L.put(2, x + hw - 2, fy, "bookshelf" if L.rnd() < 0.5 else "barrel")
	L.put(2, x + hw / 2, fy + (1 if bottom_door else -1), "table")
	L.put(2, x + hw / 2 + 1, fy + (1 if bottom_door else -1), "chair")
	if loot:
		L.chest(x + hw - 2, y + hh - 2 if bottom_door else iy, "house")
	L.put(2, ix, y + hh - 2 if bottom_door else iy, "torch")
	return dp


static func _path_to(L: Layout, from: Vector2i, to_y: int, key: String) -> void:
	var step := 1 if to_y > from.y else -1
	var y := from.y + step
	while y != to_y + step:
		if L.at(2, from.x, y) == 0 or L.at(2, from.x, y) == CLEAR:
			if L.at(1, from.x, y) == 0:
				L.put(1, from.x, y, key)
		y += step


static func _village(seed: int, c: ContentRegistry) -> Dictionary:
	var L := Layout.new(48, 48, c, seed)
	L.clear_all()
	# main cross roads + plaza
	L.fill(1, 23, 0, 2, 48, "cobble_road")
	L.fill(1, 0, 23, 48, 2, "cobble_road")
	for y in range(17, 31):
		for x in range(17, 31):
			var dx := x - 23.5
			var dy := y - 23.5
			if dx * dx + dy * dy < 36.0:
				L.put(1, x, y, "cobble_road")
	L.put(2, 23, 21, "well_broken")
	for p in [[19, 19], [28, 19], [19, 28], [28, 28]]:
		L.put(2, p[0], p[1], "moon_lantern")
	# houses: top row doors face south, bottom row doors face north
	var slots := [[3, 7, 2], [13, 7, 2], [27, 7, 2], [3, 34, 0], [13, 34, 0], [27, 34, 0]]
	var hi := 0
	for sl in slots:
		var hw := 8 + L.rndi(2)
		var hh := 6 + L.rndi(2)
		var wall := "wall_stone" if hi == 2 else ("wall_brick" if L.rnd() < 0.3 else "wall_wood")
		var dp := house(L, sl[0], sl[1], hw, hh, wall, sl[2], true)
		_path_to(L, dp, 22 if sl[2] == 2 else 25, "path")
		L.anchors["house_%d" % hi] = Vector2i(sl[0] + hw / 2, sl[1] + hh / 2 + (1 if sl[2] == 2 else -1))
		hi += 1
	# smith yard next to house_2
	L.put(2, 36, 15, "anvil")
	L.put(2, 37, 15, "furnace")
	L.put(2, 38, 16, "barrel")
	# market
	L.put(2, 39, 9, "market_stall")
	L.put(2, 41, 9, "crate")
	L.put(2, 38, 9, "barrel")
	L.fill(1, 37, 10, 6, 2, "cobble_road")
	_path_to(L, Vector2i(40, 11), 22, "path")
	L.anchors["stall"] = Vector2i(39, 10)
	# farm
	L.outline(2, 36, 33, 10, 9, "fence")
	L.put(2, 40, 33, "fence_gate")
	L.fill(0, 37, 34, 8, 7, "farmland")
	for y in range(34, 41):
		for x in range(37, 45):
			var r := L.rnd()
			L.put(2, x, y, "wheat_2" if r < 0.45 else ("wheat_1" if r < 0.75 else ("carrot_1" if r < 0.9 else CLEAR)))
	L.put(2, 41, 37, "scarecrow")
	_path_to(L, Vector2i(40, 32), 25, "path")
	L.anchors["farm"] = Vector2i(40, 31)
	# dressing
	for p in [[21, 26], [26, 26], [21, 20], [26, 20]]:
		L.put(2, p[0], p[1], "flower_pot")
	L.put(2, 25, 4, "lantern_post")
	L.put(2, 22, 43, "lantern_post")
	L.put(2, 4, 22, "lantern_post")
	L.put(2, 43, 25, "lantern_post")
	L.put(2, 26, 27, "sign")
	for i in 26:
		var x := L.rndi(48)
		var y := L.rndi(48)
		if L.at(2, x, y) == CLEAR and L.at(1, x, y) == 0 and L.at(0, x, y) == 0:
			L.put(3, x, y, ["flower_red", "flower_yellow", "flower_blue", "tall_grass"][L.rndi(4)])
	for p in [[1, 1], [46, 2], [2, 45], [45, 46], [17, 2], [31, 45], [1, 30], [46, 18]]:
		L.put(2, p[0], p[1], "tree_oak")
	L.anchors["center"] = Vector2i(24, 25)
	L.anchors["plaza"] = Vector2i(25, 22)
	L.anchors["gate"] = Vector2i(24, 44)
	return L.to_dict()


static func _dungeon(seed: int, c: ContentRegistry) -> Dictionary:
	var L := Layout.new(53, 53, c, seed)
	L.clear_all()
	L.fill(0, 0, 0, 53, 53, "ruin_floor")
	L.outline(2, 0, 0, 53, 53, "ruin_wall")
	# 4x4 cells of 12 with 1-tile walls; centre 2x2 merged into the boss arena
	for i in range(1, 4):
		L.fill(2, 13 * i, 1, 1, 51, "ruin_wall")
		L.fill(2, 1, 13 * i, 51, 1, "ruin_wall")
	L.fill(2, 14, 14, 25, 25, CLEAR)
	# maze: nodes 0..15 for cells, the four centre cells collapse into node 5
	var node := func(ix: int, iy: int) -> int:
		if ix >= 1 and ix <= 2 and iy >= 1 and iy <= 2:
			return 5
		return iy * 4 + ix
	var edges: Array = []   # [node_a, node_b, ax, ay, horizontal]
	for iy in 4:
		for ix in 4:
			if ix < 3 and node.call(ix, iy) != node.call(ix + 1, iy):
				edges.append([node.call(ix, iy), node.call(ix + 1, iy), 13 * (ix + 1), 1 + 13 * iy + 5, true])
			if iy < 3 and node.call(ix, iy) != node.call(ix, iy + 1):
				edges.append([node.call(ix, iy), node.call(ix, iy + 1), 1 + 13 * ix + 5, 13 * (iy + 1), false])
	# randomised Kruskal -> spanning tree, plus two extra loops
	for i in range(edges.size() - 1, 0, -1):
		var j := L.rndi(i + 1)
		var tmp = edges[i]; edges[i] = edges[j]; edges[j] = tmp
	var parent := {}
	var find := func(a: int) -> int:
		while parent.get(a, a) != a:
			a = parent[a]
		return a
	var extra := 2
	var arena_doors := 0
	for e in edges:
		var ra: int = find.call(e[0])
		var rb: int = find.call(e[1])
		var open := false
		if ra != rb:
			parent[ra] = rb
			open = true
		elif extra > 0 and e[0] != 5 and e[1] != 5:
			extra -= 1
			open = true
		if open:
			if e[0] == 5 or e[1] == 5:
				arena_doors += 1
			if e[4]:
				L.fill(2, e[2], e[3], 1, 2, CLEAR)
			else:
				L.fill(2, e[2], e[3], 2, 1, CLEAR)
	# gate (south side, cell (1,3))
	L.fill(2, 19, 52, 2, 1, CLEAR)
	L.anchors["gate"] = Vector2i(19, 54)
	L.anchors["center"] = Vector2i(19, 54)
	# arena dressing
	L.put(2, 26, 26, "altar")
	for p in [[18, 18], [34, 18], [18, 34], [34, 34]]:
		L.put(2, p[0], p[1], "ruin_pillar")
	for p in [[15, 15], [37, 15], [15, 37], [37, 37]]:
		L.put(2, p[0], p[1], "moon_lantern")
	L.anchors["altar"] = Vector2i(26, 26)
	L.anchors["boss"] = Vector2i(26, 21)
	L.anchors["arena_min"] = Vector2i(14, 14)
	L.anchors["arena_max"] = Vector2i(38, 38)
	# outer cells
	var chests := 0
	for iy in 4:
		for ix in 4:
			if node.call(ix, iy) == 5:
				continue
			var ox := 1 + 13 * ix
			var oy := 1 + 13 * iy
			var entry := ix == 1 and iy == 3
			for k in 5:
				var px := ox + 1 + L.rndi(10)
				var py := oy + 1 + L.rndi(10)
				if L.at(2, px, py) == CLEAR:
					L.put(3, px, py, "rubble" if L.rnd() < 0.7 else "bones")
			if entry:
				L.put(2, ox + 2, oy + 9, "statue")
				L.put(2, ox + 9, oy + 9, "statue")
				continue
			for p in [[2, 2], [9, 2], [2, 9], [9, 9]]:
				if L.rnd() < 0.45:
					L.put(2, ox + p[0], oy + p[1], "ruin_pillar")
			if L.rnd() < 0.35:
				L.put(2, ox + 3 + L.rndi(6), oy + 3, "ore_moon")
			if L.rnd() < 0.5 or chests < 3 and (iy * 4 + ix) % 3 == 0:
				L.chest(ox + 5 + L.rndi(2), oy + 5, "ruin")
				chests += 1
			var n := 1 + L.rndi(2)
			for k in n:
				var r := L.rnd()
				var def := "ruin_sentinel" if r < 0.45 else ("skeleton_archer" if r < 0.8 else "slime")
				L.spawn(def, ox + 3 + L.rndi(6), oy + 6 + L.rndi(4))
	if chests == 0:
		L.chest(6, 6, "ruin")
	# elite guarding one corner
	L.spawn("stone_golem", 46, 6)
	return L.to_dict()


static func _camp(seed: int, c: ContentRegistry) -> Dictionary:
	var L := Layout.new(16, 16, c, seed)
	for y in 16:
		for x in 16:
			var dx := x - 7.5
			var dy := y - 7.5
			var d := dx * dx + dy * dy
			if d < 52.0:
				L.put(2, x, y, CLEAR)
				L.put(3, x, y, CLEAR)
			if d >= 40.0 and d < 52.0 and L.rnd() < 0.6 and absf(dx) > 1.5:
				L.put(2, x, y, "fence")
	L.put(2, 8, 8, "campfire_out")
	L.put(2, 4, 5, "tent")
	L.put(2, 11, 5, "tent")
	L.put(2, 5, 10, "crate")
	L.put(2, 6, 10, "barrel")
	L.chest(10, 10, "camp")
	L.put(0, 7, 9, "dirt")
	L.put(0, 8, 9, "dirt")
	L.put(0, 9, 8, "dirt")
	L.spawn("bandit", 6, 7)
	L.spawn("bandit", 10, 7)
	L.spawn("bandit", 8, 11)
	L.spawn("skeleton_archer", 8, 5)
	L.anchors["center"] = Vector2i(8, 9)
	return L.to_dict()


static func _ruin(seed: int, c: ContentRegistry) -> Dictionary:
	var L := Layout.new(12, 12, c, seed)
	for y in range(2, 10):
		for x in range(2, 10):
			L.put(2, x, y, CLEAR)
			if L.rnd() < 0.7:
				L.put(0, x, y, "ruin_floor")
			if L.rnd() < 0.12:
				L.put(3, x, y, "rubble")
	for x in range(2, 10):
		if L.rnd() < 0.6 and x != 5 and x != 6:
			L.put(2, x, 2, "ruin_wall")
		if L.rnd() < 0.6 and x != 5 and x != 6:
			L.put(2, x, 9, "ruin_wall")
	for y in range(3, 9):
		if L.rnd() < 0.6 and y != 5 and y != 6:
			L.put(2, 2, y, "ruin_wall")
		if L.rnd() < 0.6 and y != 5 and y != 6:
			L.put(2, 9, y, "ruin_wall")
	L.put(2, 4, 4, "ruin_pillar")
	L.put(2, 7, 4, "statue" if L.rnd() < 0.5 else "ruin_pillar")
	L.chest(6, 6, "ruin_small")
	L.spawn("skeleton_archer" if L.rnd() < 0.5 else "slime", 5, 7)
	L.anchors["center"] = Vector2i(5, 5)
	return L.to_dict()
