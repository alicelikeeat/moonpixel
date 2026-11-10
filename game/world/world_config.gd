class_name WorldConfig
extends RefCounted
## Immutable creation parameters of a world + mutable rules.

const SIZES := {"small": 512, "medium": 2048, "large": 4096}

const RULE_DEFAULTS := {
	"time_scale": 1.0,            # 0 = frozen time
	"weather_frequency": 1.0,     # 0 = always clear
	"monsters": true,
	"difficulty": 1.0,            # incoming damage multiplier
	"resources": 1.0,             # drop quantity multiplier
	"build_cost": true,
	"terrain_edit": true,         # allow destroying natural terrain
	"combat": true,               # false = nobody can be damaged
	"god_build": false,           # creative: instant break, free placement
}

const PRESETS := {
	"adventure": {},
	"survival": {"difficulty": 1.5, "resources": 0.75},
	"peaceful": {"monsters": false},
	"creative": {"monsters": false, "combat": false, "build_cost": false, "god_build": true, "resources": 2.0},
}

var id: String = ""
var name: String = "World"
var seed: int = 0
var size: int = 512
var preset: String = "adventure"
var rules: Dictionary = RULE_DEFAULTS.duplicate()
var generator_version: int = MP.GENERATOR_VERSION
var appearance: Dictionary = {"skin": "#e8b890", "hair": "#5a3a22", "shirt": "#3a6ac8", "pants": "#4a4a5a"}


static func make(p_name: String, p_seed: int, size_key: String, p_preset: String) -> WorldConfig:
	var c := WorldConfig.new()
	c.name = p_name
	c.seed = p_seed
	c.size = int(SIZES.get(size_key, 512))
	c.apply_preset(p_preset)
	c.id = "w_%s_%d" % [str(abs(p_seed) % 100000), Time.get_ticks_usec() % 1000000]
	return c


func apply_preset(p: String) -> void:
	preset = p if PRESETS.has(p) else "adventure"
	rules = RULE_DEFAULTS.duplicate()
	for k in PRESETS[preset]:
		rules[k] = PRESETS[preset][k]


func rule(k: String):
	return rules.get(k, RULE_DEFAULTS.get(k))


func chunks_per_side() -> int:
	return size / MP.CHUNK


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "seed": seed, "size": size, "preset": preset, "rules": rules.duplicate(),
		"generator_version": generator_version, "appearance": appearance.duplicate()}


static func from_dict(d: Dictionary) -> WorldConfig:
	var c := WorldConfig.new()
	c.id = str(d.get("id", ""))
	c.name = str(d.get("name", "World"))
	c.seed = int(d.get("seed", 0))
	c.size = int(d.get("size", 512))
	c.preset = str(d.get("preset", "adventure"))
	c.rules = RULE_DEFAULTS.duplicate()
	var r = d.get("rules", {})
	if r is Dictionary:
		for k in r:
			if RULE_DEFAULTS.has(k):
				c.rules[k] = r[k]
	c.generator_version = int(d.get("generator_version", 1))
	var a = d.get("appearance", {})
	if a is Dictionary:
		for k in a:
			c.appearance[k] = str(a[k])
	return c


## Shareable text form: seed + generation parameters + rules (no world data).
func export_string() -> String:
	return "MPW1:" + Marshalls.utf8_to_base64(JSON.stringify({"name": name, "seed": seed, "size": size, "preset": preset, "rules": rules, "appearance": appearance}))


static func import_string(s: String) -> WorldConfig:
	s = s.strip_edges()
	if not s.begins_with("MPW1:"):
		return null
	var parsed = JSON.parse_string(Marshalls.base64_to_utf8(s.substr(5)))
	if not (parsed is Dictionary) or not parsed.has("seed"):
		return null
	var size := int(parsed.get("size", 512))
	if not SIZES.values().has(size):
		return null
	var c := from_dict(parsed)
	c.id = "w_%s_%d" % [str(abs(c.seed) % 100000), Time.get_ticks_usec() % 1000000]
	c.generator_version = MP.GENERATOR_VERSION
	return c
