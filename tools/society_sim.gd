extends SceneTree
## Dev tool: fast-forward the autonomous society headless and print a yearly census.
##   godot --headless --path . -s tools/society_sim.gd -- --years=20 --seed=7 --pop=120

func _initialize() -> void:
	var years := 20
	var seed := 7
	var pop := 120
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--years="): years = int(a.substr(8))
		if a.begins_with("--seed="): seed = int(a.substr(7))
		if a.begins_with("--pop="): pop = int(a.substr(6))
	var budget := MemoryBudget.new().configure()
	print(budget.describe())
	var world := OpenWorld.new(seed, ContentRegistry.shared(), budget)
	var soc := Society.new(world, budget, seed)
	soc.bootstrap(Vector2i.ZERO, 4, pop / 4)
	var t0 := Time.get_ticks_msec()
	for y in years:
		var steps := int(OpenWorld.YEAR / 1.0)
		for i in steps:
			soc.tick(1.0)
		var houses := 0
		var farms := 0
		var food := 0.0
		var living := 0
		for sid in soc.settlements:
			var s: Settlement = soc.settlements[sid]
			if s.abandoned:
				continue
			living += 1
			houses += s.count_type("house", true)
			farms += s.count_type("farm", true)
			food += s.stock["food"]
		var homeless := 0
		for id in soc.agents:
			if soc.agents[id].home < 0:
				homeless += 1
		print("year %2d pop=%3d births=%3d deaths=%3d (old %d hunger %d ill %d) pairs=%d villages=%d houses=%d farms=%d food=%d homeless=%d tiles=%d chunks=%d surveyed=%d mem=%dMB" % [
			y + 1, soc.agents.size(), soc.stats["births"], soc.stats["deaths"], soc.stats["old"], soc.stats["hunger"], soc.stats["ill"],
			soc.stats["pairs"], living, houses, farms, int(food), homeless, soc.stats["tiles_placed"], world.cache.size(), world.surveyed, budget.used_mb()])
	print("%.1f s wall for %d years" % [(Time.get_ticks_msec() - t0) / 1000.0, years])
	for e in soc.log.slice(-8):
		print("  ", e["text"])
	quit()
