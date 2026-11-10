extends TestCase

var c := ContentRegistry.shared()


func _plan(seed: int, size: int = 512) -> WorldPlan:
	return WorldPlan.new().build(seed, size, c)


func test_plan_is_deterministic() -> void:
	var a := _plan(1234)
	var b := _plan(1234)
	eq(a.spawn_tile, b.spawn_tile)
	eq(a.sites.size(), b.sites.size())
	ok(a.elev == b.elev, "elevation identical")
	for i in a.sites.size():
		eq(a.sites[i]["x"], b.sites[i]["x"])
		eq(a.sites[i]["y"], b.sites[i]["y"])


func test_chunks_identical_regardless_of_order() -> void:
	var p1 := _plan(777)
	var p2 := _plan(777)
	var g1 := ChunkGenerator.new(p1, c)
	var g2 := ChunkGenerator.new(p2, c)
	var coords: Array = []
	var sc := p1.spawn_tile / MP.CHUNK
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			coords.append(Vector2i(sc.x + dx, sc.y + dy))
	var first := {}
	for v in coords:
		first[v] = g1.generate(v.x, v.y)
	var rev := coords.duplicate()
	rev.reverse()
	for v in rev:
		var b := g2.generate(v.x, v.y)
		var a: ChunkData = first[v]
		for l in MP.LAYERS:
			ok(a.layers[l] == b.layers[l], "layer %d of chunk %s" % [l, str(v)])
		eq(a.spawn_points.size(), b.spawn_points.size())
		eq(a.containers.size(), b.containers.size())


func test_different_seeds_differ() -> void:
	ok(_plan(1).elev != _plan(2).elev)


func test_all_three_world_sizes() -> void:
	for size in [512, 2048, 4096]:
		var p := _plan(4242, size)
		ok(p.valid, "size %d valid: %s" % [size, str(p.errors)])
		ok(p.build_ms < 5000, "plan under 5s (%d ms)" % p.build_ms)
		var g := ChunkGenerator.new(p, c)
		var ch := g.generate(p.spawn_tile.x / MP.CHUNK, p.spawn_tile.y / MP.CHUNK)
		eq(ch.layers[0].size(), MP.CHUNK_AREA)


func test_four_biome_families_present() -> void:
	for seed in [11, 22, 33, 44, 55]:
		var s := _plan(seed).biome_stats()
		for k in ["temperate", "snow", "desert", "wetland"]:
			ok(float(s[k]) / float(s["land"]) > 0.02, "seed %d biome %s share %.3f" % [seed, k, float(s[k]) / float(s["land"])])


func test_chunk_generation_speed() -> void:
	var p := _plan(99)
	var g := ChunkGenerator.new(p, c)
	var sc := p.spawn_tile / MP.CHUNK
	var t0 := Time.get_ticks_usec()
	var n := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			g.generate(sc.x + dx, sc.y + dy)
			n += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("        chunk generation: %.2f ms/chunk" % ms)
	ok(ms < 40.0, "chunk generation under 40ms (%.2f)" % ms)
