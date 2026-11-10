extends SceneTree
## Headless test runner.
##   godot --headless --path . -s tests/run_tests.gd -- [--filter=name] [--slow] [--seeds=N]
## Exit code 0 = all passed.

func _initialize() -> void:
	var filter := ""
	var slow := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
		elif a == "--slow":
			slow = true
	var files: Array = []
	var d := DirAccess.open("res://tests")
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var checks := 0
	var t_all := Time.get_ticks_msec()
	for f in files:
		if filter != "" and not f.contains(filter):
			continue
		var script = load("res://tests/" + f)
		if script == null:
			print("FAIL  %s (script failed to load)" % f)
			failed += 1
			continue
		var inst = script.new()
		if inst.is_slow() and not slow:
			print("SKIP  %s (slow; run with -- --slow)" % f)
			continue
		var methods: Array = []
		for m in inst.get_method_list():
			if str(m["name"]).begins_with("test_"):
				methods.append(str(m["name"]))
		methods.sort()
		for m in methods:
			inst.current = m
			var before: int = inst.fails.size()
			var t0 := Time.get_ticks_msec()
			inst.call(m)
			total += 1
			var dt := Time.get_ticks_msec() - t0
			if inst.fails.size() > before:
				failed += 1
				print("FAIL  %s::%s (%d ms)" % [f, m, dt])
				for i in range(before, inst.fails.size()):
					print("        " + str(inst.fails[i]))
			else:
				print("ok    %s::%s (%d ms)" % [f, m, dt])
		checks += inst.checks
	TestCase.wipe("user://test_tmp")
	print("\n%d tests, %d checks, %d failed, %.1f s" % [total, checks, failed, (Time.get_ticks_msec() - t_all) / 1000.0])
	quit(1 if failed > 0 else 0)
