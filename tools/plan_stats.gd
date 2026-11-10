extends SceneTree
## Dev tool: print macro plan statistics for a range of seeds.
##   godot --headless --path . -s tools/plan_stats.gd -- --seeds=20 --size=512

func _initialize() -> void:
	var n := 20
	var size := 512
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			n = int(a.substr(8))
		if a.begins_with("--size="):
			size = int(a.substr(7))
	var c := ContentRegistry.shared()
	var bad := 0
	for seed in range(1, n + 1):
		var p := WorldPlan.new().build(seed * 7919, size, c)
		var s := p.biome_stats()
		var land := float(s["land"])
		print("seed %6d valid=%s land=%.2f T=%.2f S=%.2f D=%.2f W=%.2f rivers=%d sites=%d roads=%d ms=%d %s" % [seed * 7919, str(p.valid), land / 65536.0,
			s["temperate"] / land, s["snow"] / land, s["desert"] / land, s["wetland"] / land, p.river_cells.size(), p.sites.size(), p.roads.size(), p.build_ms, str(p.errors)])
		if not p.valid:
			bad += 1
	print("invalid: %d / %d" % [bad, n])
	quit()
