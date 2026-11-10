class_name ChunkData
extends RefCounted
## One 32x32 chunk: tile layers, free-positioned props, containers, growth
## timers and dormant entities. Pure data; owned by ChunkService.

const MAGIC := 0x4b43504d  # "MPCK"
const FORMAT := 1

var cx: int
var cy: int
var layers: Array = []            # 4 x PackedByteArray(1024)
var props: Array = []             # [{id,key,x,y,rot,z}] world px coordinates
var containers: Dictionary = {}   # tile index -> Array of [item_id, count] / null slots
var timers: Array = []            # [{i,l,to,due,expect}]
var entities: Array = []          # dormant entity dictionaries
var spawn_points: Array = []      # generator output, never saved
var spawned_day: int = -1
var modified := false             # differs from generator output -> must be persisted
var dirty := false                # unsaved changes
var revision := 0
var from_save := false
var last_used := 0


func _init(p_cx: int = 0, p_cy: int = 0) -> void:
	cx = p_cx
	cy = p_cy
	for i in MP.LAYERS:
		var a := PackedByteArray()
		a.resize(MP.CHUNK_AREA)
		layers.append(a)


func key() -> int:
	return MP.chunk_key(cx, cy)


func get_t(layer: int, lx: int, ly: int) -> int:
	return layers[layer][ly * MP.CHUNK + lx]


func set_t(layer: int, lx: int, ly: int, id: int) -> void:
	layers[layer][ly * MP.CHUNK + lx] = id


func touch() -> void:
	modified = true
	dirty = true
	revision += 1


func to_bytes() -> PackedByteArray:
	var payload := var_to_bytes({
		"cx": cx, "cy": cy, "l0": layers[0], "l1": layers[1], "l2": layers[2], "l3": layers[3],
		"props": props, "containers": containers, "timers": timers, "entities": entities,
		"spawned_day": spawned_day, "revision": revision,
	})
	var comp := payload.compress(FileAccess.COMPRESSION_ZSTD)
	var out := StreamPeerBuffer.new()
	out.put_u32(MAGIC)
	out.put_u16(FORMAT)
	out.put_u32(payload.size())
	out.put_u32(comp.size())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(comp)
	out.put_data(ctx.finish())
	out.put_data(comp)
	return out.data_array


## Returns null when the buffer is truncated, corrupt or of an unknown format.
static func from_bytes(buf: PackedByteArray) -> ChunkData:
	if buf.size() < 30:
		return null
	var sp := StreamPeerBuffer.new()
	sp.data_array = buf
	if sp.get_u32() != MAGIC:
		return null
	var fmt := sp.get_u16()
	if fmt != FORMAT:
		return null
	var raw_size := sp.get_u32()
	var comp_size := sp.get_u32()
	if comp_size != buf.size() - 30 or raw_size > 16 * 1024 * 1024:
		return null
	var md5: PackedByteArray = sp.get_data(16)[1]
	var comp: PackedByteArray = sp.get_data(comp_size)[1]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(comp)
	if ctx.finish() != md5:
		return null
	var payload := comp.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if payload.size() != raw_size:
		return null
	var d = bytes_to_var(payload)
	if not (d is Dictionary):
		return null
	var c := ChunkData.new(int(d["cx"]), int(d["cy"]))
	for i in MP.LAYERS:
		var a = d.get("l%d" % i)
		if not (a is PackedByteArray) or a.size() != MP.CHUNK_AREA:
			return null
		c.layers[i] = a
	c.props = d.get("props", [])
	c.containers = d.get("containers", {})
	c.timers = d.get("timers", [])
	c.entities = d.get("entities", [])
	c.spawned_day = int(d.get("spawned_day", -1))
	c.revision = int(d.get("revision", 0))
	c.modified = true
	c.from_save = true
	return c
