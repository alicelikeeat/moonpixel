extends TestCase

var c := ContentRegistry.shared()


func _world(seed: int, mb: int = 96) -> OpenWorld:
	return OpenWorld.new(seed, c, MemoryBudget.new().configure(mb))


func test_memory_budget_is_queried_and_overridable() -> void:
	var auto := MemoryBudget.new().configure()
	ok(auto.budget_mb >= MemoryBudget.MIN_MB, "auto budget has a floor")
	ok(auto.max_chunks >= 256)
	if auto.detected:
		ok(auto.physical_mb > 0, "device memory reported")
		ok(auto.budget_mb <= auto.physical_mb, "budget never exceeds the device")
	var small := MemoryBudget.new().configure(96)
	var big := MemoryBudget.new().configure(2048)
	eq(small.budget_mb, 96)
	ok(big.max_chunks > small.max_chunks, "more memory -> larger chunk cache")
	ok(big.max_agents > small.max_agents, "more memory -> higher NPC ceiling")


func test_infinite_generation_any_coordinate_any_order() -> void:
	var a := _world(42)
	var b := _world(42)
	var coords := [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(-500, 320), Vector2i(100000, -100000), Vector2i(7, -3)]
	var first := {}
	for v in coords:
		first[v] = a.get_chunk(v.x, v.y)
	var rev := coords.duplicate()
	rev.reverse()
	for v in rev:
		var cb := b.get_chunk(v.x, v.y)
		for l in MP.LAYERS:
			ok(first[v].layers[l] == cb.layers[l], "chunk %s layer %d deterministic" % [str(v), l])
	ok(_world(43).get_chunk(0, 0).layers[0] != first[Vector2i(0, 0)].layers[0] or _world(43).get_chunk(5, 5).layers[0] != a.get_chunk(5, 5).layers[0], "seeds differ")
	eq(MP.key_cx(MP.chunk_key(-500, 320)), -500)
	eq(MP.key_cy(MP.chunk_key(-500, 320)), 320)


func test_tile_access_across_negative_chunks() -> void:
	var w := _world(5)
	var grass := c.tid("grass")
	w.set_tile(MP.L_GROUND, -1, -1, grass)
	w.set_tile(MP.L_GROUND, -33, 40, grass)
	eq(w.tile(MP.L_GROUND, -1, -1), grass)
	eq(w.get_chunk(-1, -1).get_t(MP.L_GROUND, 31, 31), grass)
	eq(w.get_chunk(-2, 1).get_t(MP.L_GROUND, 31, 8), grass)


func test_cache_stays_inside_budget_and_keeps_pins() -> void:
	var w := _world(9)
	w.budget.max_chunks = 300
	w.pin(0, 0)
	for i in 900:
		w.get_chunk(i % 60, i / 60)
		if i % 50 == 0:
			w.maintain()
	w.maintain()
	ok(w.cache.size() <= 300, "cache bounded (%d)" % w.cache.size())
	ok(w.loaded(0, 0), "pinned chunk survives eviction")
	ok(w.evicted > 0)
	ok(w.generated >= 900)


func test_modified_chunks_survive_eviction() -> void:
	var root := fresh_root("ow")
	var w := _world(11)
	w.open_dir(root)
	w.budget.max_chunks = 256
	var wall := c.tid("wall_wood")
	w.set_tile(MP.L_OBJECT, 5, 5, wall)
	for i in 600:
		w.get_chunk(100 + i % 30, 100 + i / 30)
	w.maintain()
	ok(not w.loaded(0, 0), "edited chunk was evicted")
	eq(w.tile(MP.L_OBJECT, 5, 5), wall, "edit restored from disk")
	# a brand new world object over the same directory sees it too
	var w2 := _world(11)
	w2.open_dir(root)
	eq(w2.tile(MP.L_OBJECT, 5, 5), wall)


func test_memory_only_world_never_drops_edits() -> void:
	var w := _world(12)
	w.budget.max_chunks = 256
	w.set_tile(MP.L_OBJECT, 5, 5, c.tid("wall_wood"))
	for i in 600:
		w.get_chunk(100 + i % 30, 100 + i / 30)
	w.maintain()
	ok(w.loaded(0, 0), "unsaved edits are kept in memory")


func test_map_survey_expands_without_keeping_chunks() -> void:
	var w := _world(13)
	var before := w.cache.size()
	var total := 0
	for i in 20:
		total += w.survey(Vector2i(0, 0), 50)
	eq(total, 1000)
	eq(w.surveyed, 1000)
	eq(w.cache.size(), before, "survey generates no terrain")
	ok(w.known(0, 0) != 0 and w.known(-10, 10) != 0)
	eq(w.known(5000, 5000), 0)
	var d := w.to_dict()
	var w2 := _world(13)
	w2.from_dict(JSON.parse_string(JSON.stringify(d)))
	eq(w2.surveyed, 1000, "survey map persists")
	eq(w2.known(-10, 10), w.known(-10, 10))


func test_growth_catches_up_after_eviction() -> void:
	var root := fresh_root("ow2")
	var w := _world(14)
	w.open_dir(root)
	w.budget.max_chunks = 256
	w.set_tile(MP.L_GROUND, 3, 3, c.tid("farmland"))
	w.set_tile(MP.L_OBJECT, 3, 3, c.tid("wheat_0"))
	for i in 600:
		w.get_chunk(100 + i % 30, 100 + i / 30)
	w.maintain()
	w.time += 1000.0
	eq(w.tile(MP.L_OBJECT, 3, 3), c.tid("wheat_2"), "crop ripened while unloaded")
