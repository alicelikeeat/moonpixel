class_name MP
extends RefCounted
## Shared constants and deterministic helpers. No state.

const TILE := 16                 # logical pixels per tile
const CHUNK := 32                # tiles per chunk side
const CHUNK_AREA := CHUNK * CHUNK
const CHUNK_PX := CHUNK * TILE
const SIM_DT := 1.0 / 30.0       # main logic tick
const DAY_SECONDS := 1200.0      # one in-game day at time_scale 1

const L_GROUND := 0
const L_STRUCT := 1
const L_OBJECT := 2
const L_DECOR := 3
const LAYERS := 4

const SAVE_FORMAT := 2
const GENERATOR_VERSION := 1


## Deterministic 32-bit hash of (seed, x, y). Stable across platforms: only
## uses integer ops that stay inside 63 bits.
static func h2(s: int, x: int, y: int) -> int:
	var h: int = (s & 0xffffffff) ^ ((x * 0x27d4eb2d) & 0xffffffff)
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0xffffffff
	h = h ^ ((y * 0x165667b1) & 0xffffffff)
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0xffffffff
	h = h ^ (h >> 15)
	return h


static func h01(s: int, x: int, y: int) -> float:
	return float(h2(s, x, y) & 0xffffff) / 16777216.0


static func hash_str(s: String) -> int:
	var h: int = 2166136261
	for b in s.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xffffffff
	return h


## Chunk coordinates may be negative (infinite worlds): 32 bits per axis.
static func chunk_key(cx: int, cy: int) -> int:
	return ((cy + 0x40000000) << 32) | (cx + 0x40000000)


static func key_cx(k: int) -> int:
	return (k & 0xffffffff) - 0x40000000


static func key_cy(k: int) -> int:
	return (k >> 32) - 0x40000000


static func tile_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


static func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE + TILE * 0.5, t.y * TILE + TILE * 0.5)


static func loc(d, lang: String = "") -> String:
	## Resolve a {"en":..,"zh":..} dictionary (or plain string) to text.
	if d is String:
		return d
	if d is Dictionary:
		var l := lang if lang != "" else Loc.lang
		if d.has(l):
			return str(d[l])
		if d.has("en"):
			return str(d["en"])
	return ""
