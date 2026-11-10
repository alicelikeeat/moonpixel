extends SceneTree
## Dev tool: render a whole world (1 px per tile) to a PNG for visual review.
##   godot --headless --path . -s tools/render_map.gd -- --seed=7919 --size=512 --out=/tmp/map.png

func _initialize() -> void:
	var seed := 7919
	var size := 512
	var out := "user://map.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed = int(a.substr(7))
		if a.begins_with("--size="): size = int(a.substr(7))
		if a.begins_with("--out="): out = a.substr(6)
	var c := ContentRegistry.shared()
	var p := WorldPlan.new().build(seed, size, c)
	var g := ChunkGenerator.new(p, c)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cols: Array = []
	for t in c.tiles:
		cols.append(Color.BLACK if t == null else Color(str(t["art"][1])))
	var n := size / MP.CHUNK
	for cy in n:
		for cx in n:
			var ch := g.generate(cx, cy)
			for i in MP.CHUNK_AREA:
				var col: Color = cols[ch.layers[0][i]]
				if ch.layers[1][i] != 0:
					col = cols[ch.layers[1][i]]
				if ch.layers[2][i] != 0:
					col = cols[ch.layers[2][i]].darkened(0.15)
				img.set_pixel(cx * MP.CHUNK + i % MP.CHUNK, cy * MP.CHUNK + i / MP.CHUNK, col)
	for s in p.sites:
		for x in range(s["x"], s["x"] + s["w"]):
			img.set_pixel(x, s["y"], Color.MAGENTA)
			img.set_pixel(x, s["y"] + s["h"] - 1, Color.MAGENTA)
	img.save_png(out)
	print("saved ", out, " valid=", p.valid, " spawn=", p.spawn_tile)
	quit()
