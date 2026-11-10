class_name ChunkService
extends RefCounted
## ChunkService: chunk generation, cache and eviction.
##
## Threading contract: every public method is main-thread only, except that
## `generate_detached()` may be called from worker threads (it touches only the
## immutable plan/content). Results of async generation are handed back through
## `adopt()` on the main thread.
##
## Error handling: a chunk outside the world returns null. A corrupt chunk file
## is reported through `load_errors`, quarantined by SaveService and replaced by
## freshly generated terrain (never silently deleted).

var config: WorldConfig
var content: ContentRegistry
var plan: WorldPlan
var generator: ChunkGenerator
var save: SaveService = null
var bus: EventBus = null
var cache: Dictionary = {}          # key -> ChunkData
var max_cached := 400
var load_errors: Array = []
var pinned: Dictionary = {}         # key -> true : never evicted (active area)
var _clock := 0
var gen_count := 0


func setup(p_config: WorldConfig, p_content: ContentRegistry, p_plan: WorldPlan) -> void:
	config = p_config
	content = p_content
	plan = p_plan
	generator = ChunkGenerator.new(plan, content)


func in_world(cx: int, cy: int) -> bool:
	var n := config.chunks_per_side()
	return cx >= 0 and cy >= 0 and cx < n and cy < n


func has(cx: int, cy: int) -> bool:
	return cache.has(MP.chunk_key(cx, cy))


func peek(cx: int, cy: int) -> ChunkData:
	return cache.get(MP.chunk_key(cx, cy))


## Synchronous get-or-load. Saved chunk wins over generation.
func get_chunk(cx: int, cy: int) -> ChunkData:
	if not in_world(cx, cy):
		return null
	var k := MP.chunk_key(cx, cy)
	var c: ChunkData = cache.get(k)
	if c == null:
		c = _load_saved(cx, cy)
		if c == null:
			c = generator.generate(cx, cy)
			gen_count += 1
		cache[k] = c
	_clock += 1
	c.last_used = _clock
	return c


func _load_saved(cx: int, cy: int) -> ChunkData:
	if save == null or not save.has_chunk(cx, cy):
		return null
	var c := save.load_chunk(cx, cy)
	if c == null:
		load_errors.append("chunk %d,%d was corrupt and has been regenerated" % [cx, cy])
	return c


## Thread-safe: generate without touching the cache.
func generate_detached(cx: int, cy: int) -> ChunkData:
	return generator.generate(cx, cy)


func needs_generation(cx: int, cy: int) -> bool:
	return in_world(cx, cy) and not has(cx, cy) and (save == null or not save.has_chunk(cx, cy))


## Main thread: accept an asynchronously generated chunk (ignored if a chunk
## for this position arrived in the meantime).
func adopt(c: ChunkData) -> ChunkData:
	var k := c.key()
	if cache.has(k):
		return cache[k]
	cache[k] = c
	gen_count += 1
	_clock += 1
	c.last_used = _clock
	return c


func mark_modified(cx: int, cy: int) -> void:
	var c := peek(cx, cy)
	if c != null:
		c.touch()
		if bus != null:
			bus.chunk_changed.emit(cx, cy)


func dirty_chunks() -> Array:
	var out: Array = []
	for k in cache:
		if cache[k].dirty:
			out.append(cache[k])
	return out


## Evict least recently used clean chunks beyond the budget. Dirty chunks are
## written first (through SaveService) so eviction can never lose changes.
func evict(budget: int = -1) -> int:
	var limit := max_cached if budget < 0 else budget
	if cache.size() <= limit:
		return 0
	var list: Array = []
	for k in cache:
		if not pinned.has(k):
			list.append(cache[k])
	list.sort_custom(func(a, b): return a.last_used < b.last_used)
	var removed := 0
	for c in list:
		if cache.size() <= limit:
			break
		if c.dirty:
			if save == null or not save.save_chunk(c):
				continue
		cache.erase(c.key())
		removed += 1
	return removed
