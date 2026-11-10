class_name InfiniteGenerator
extends RefCounted
## Unbounded deterministic terrain: every tile is a pure function of
## (seed, x, y), so any chunk at any coordinate (negative included) can be
## generated at any time, in any order, on any thread.

const SEA := 0.34
const MOUNTAIN := 0.80

var seed: int
var content: ContentRegistry
var n_elev := FastNoiseLite.new()
var n_temp := FastNoiseLite.new()
var n_moist := FastNoiseLite.new()
var n_river := FastNoiseLite.new()
var n_forest := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var _ground := PackedByteArray()
var _alt := PackedByteArray()
var _alt_ch := PackedFloat32Array()
var _density := PackedFloat32Array()
var _trees: Array = []
var _objects: Array = []
var _decor: Array = []
var T: Dictionary = {}


func _mk(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = s & 0x7fffffff
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if oct > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = oct
	return n


func _init(p_seed: int, p_content: ContentRegistry) -> void:
	seed = p_seed
	content = p_content
	n_elev = _mk(seed + 1, 0.0035, 4)
	n_temp = _mk(seed + 2, 0.0012, 2)
	n_moist = _mk(seed + 3, 0.004, 3)
	n_river = _mk(seed + 4, 0.005, 2)
	n_forest = _mk(seed + 5, 0.035, 2)
	n_detail = _mk(seed + 6, 0.09, 1)
	for k in ["deep_water", "water", "shallow_water", "ice", "sand", "mud", "snow", "cliff", "reeds", "lily_pad"]:
		T[k] = content.tid(k)
	for b in content.biomes:
		_ground.append(content.tid(b["ground"]))
		var alt = b.get("alt", ["", 0.0])
		_alt.append(content.tid(alt[0]))
		_alt_ch.append(float(alt[1]))
		_density.append(float(b.get("tree_density", 0.0)))
		_trees.append(_cum(b.get("trees", [])))
		_objects.append(_cum(b.get("objects", [])))
		_decor.append(_cum(b.get("decor", [])))


func _cum(list: Array) -> Array:
	var out: Array = []
	var acc := 0.0
	for e in list:
		acc += float(e[1])
		out.append([content.tid(e[0]), acc])
	return out


## Climate sample: Vector3(elevation, temperature, moisture).
func climate(wx: int, wy: int) -> Vector3:
	return Vector3(0.5 + 0.55 * n_elev.get_noise_2d(wx, wy), clampf(0.5 + 0.9 * n_temp.get_noise_2d(wx, wy), 0.0, 1.0),
		clampf(0.5 + 0.75 * n_moist.get_noise_2d(wx, wy), 0.0, 1.0))


func biome_at(wx: int, wy: int) -> int:
	var c := climate(wx, wy)
	return WorldPlan.classify(c.x, c.y, c.z)


func is_river(wx: int, wy: int, e: float) -> bool:
	return e >= SEA and e < MOUNTAIN and absf(n_river.get_noise_2d(wx, wy)) < 0.012


func generate(cx: int, cy: int) -> ChunkData:
	var c := ChunkData.new(cx, cy)
	var C := MP.CHUNK
	var g := PackedByteArray(); g.resize(MP.CHUNK_AREA)
	var st := PackedByteArray(); st.resize(MP.CHUNK_AREA)
	var ob := PackedByteArray(); ob.resize(MP.CHUNK_AREA)
	var de := PackedByteArray(); de.resize(MP.CHUNK_AREA)
	var bx := cx * C
	var by := cy * C
	for ty in C:
		var wy := by + ty
		for tx in C:
			var wx := bx + tx
			var dn := n_detail.get_noise_2d(wx, wy)
			var e := 0.5 + 0.55 * n_elev.get_noise_2d(wx, wy) + dn * 0.006
			var t := clampf(0.5 + 0.9 * n_temp.get_noise_2d(wx, wy) + dn * 0.012, 0.0, 1.0)
			var m := clampf(0.5 + 0.75 * n_moist.get_noise_2d(wx, wy) + dn * 0.012, 0.0, 1.0)
			var fo := n_forest.get_noise_2d(wx, wy)
			var b := WorldPlan.classify(e, t, m)
			var h := MP.h2(seed, wx, wy)
			var r1 := float(h & 0xffff) / 65536.0
			var r2 := float((h >> 16) & 0xffff) / 65536.0
			var idx := ty * C + tx
			var ground := 0
			var natural := true
			var cliff := false
			if b == WorldPlan.B_OCEAN:
				natural = false
				if t < 0.27 and e > SEA - 0.035:
					ground = T["ice"]
				elif e < SEA - 0.05:
					ground = T["deep_water"]
				elif e < SEA - 0.012:
					ground = T["water"]
				else:
					ground = T["shallow_water"]
			else:
				ground = _ground[b]
				if r2 < _alt_ch[b]:
					ground = _alt[b]
				if b == WorldPlan.B_MOUNTAIN:
					if t < 0.36:
						ground = T["snow"]
					cliff = e > MOUNTAIN + 0.012 and absf(fo) > 0.10
				elif b == WorldPlan.B_CANYON:
					cliff = fo > 0.26
				elif b == WorldPlan.B_WETLAND and fo < -0.22:
					ground = T["shallow_water"]
					natural = false
					if r2 < 0.12:
						de[idx] = T["lily_pad"]
				var rv := absf(n_river.get_noise_2d(wx, wy))
				if e < MOUNTAIN and rv < 0.022:
					cliff = false
					natural = false
					if rv < 0.012:
						ground = T["ice"] if t < 0.27 else (T["shallow_water"] if rv > 0.008 else T["water"])
						de[idx] = 0
					elif t >= 0.30:
						ground = T["mud"] if b == WorldPlan.B_WETLAND else T["sand"]
						if t < 0.7 and r2 < 0.2:
							de[idx] = T["reeds"]
			g[idx] = ground
			if cliff:
				st[idx] = T["cliff"]
			elif natural:
				var dens := minf(0.30, _density[b] * clampf(1.0 + fo * 2.2, 0.15, 2.4))
				if r1 < dens:
					var tr: Array = _trees[b]
					var pick := float((h >> 8) & 0xff) / 256.0 * float(tr[tr.size() - 1][1])
					for e2 in tr:
						if pick < e2[1]:
							ob[idx] = e2[0]
							break
				else:
					var rr := r1 - dens
					var placed := false
					for oe in _objects[b]:
						if rr < oe[1]:
							ob[idx] = oe[0]
							placed = true
							break
					if not placed:
						for d2 in _decor[b]:
							if r2 < d2[1]:
								de[idx] = d2[0]
								break
	c.layers = [g, st, ob, de]
	return c
