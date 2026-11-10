class_name TestCase
extends RefCounted
## Minimal dependency-free test base. Methods named test_* are run by
## tests/run_tests.gd. Mark slow suites by overriding is_slow().

var fails: Array = []
var checks := 0
var current := ""
var tmp_root := "user://test_tmp"


func is_slow() -> bool:
	return false


func ok(cond: bool, msg: String = "") -> bool:
	checks += 1
	if not cond:
		fails.append("%s: %s" % [current, msg if msg != "" else "expected true"])
	return cond


func eq(a, b, msg: String = "") -> bool:
	checks += 1
	if a != b:
		fails.append("%s: %s (got %s, expected %s)" % [current, msg, str(a), str(b)])
		return false
	return true


func near(a: float, b: float, eps: float, msg: String = "") -> bool:
	checks += 1
	if absf(a - b) > eps:
		fails.append("%s: %s (got %f, expected %f +- %f)" % [current, msg, a, b, eps])
		return false
	return true


func fresh_root(name: String) -> String:
	var p := tmp_root.path_join(name)
	wipe(p)
	DirAccess.make_dir_recursive_absolute(p)
	return p


static func wipe(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		wipe(path.path_join(sub))
		d.remove(sub)
