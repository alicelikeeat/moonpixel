class_name SaveMigrations
extends RefCounted
## World index migrations. Each step upgrades format N -> N+1 in memory; the
## original file is preserved as world.json.v<N>.bak before the upgraded index
## is written. Saves are never deleted to resolve incompatibilities.

## Returns {"ok": bool, "data": Dictionary, "from": int, "error": String}
static func migrate(d: Dictionary) -> Dictionary:
	var fmt := int(d.get("format", 0))
	var from := fmt
	if fmt <= 0:
		return {"ok": false, "data": d, "from": from, "error": "err_corrupt"}
	if fmt > MP.SAVE_FORMAT:
		return {"ok": false, "data": d, "from": from, "error": "err_newer"}
	while fmt < MP.SAVE_FORMAT:
		match fmt:
			1: d = _v1_to_v2(d)
			_: return {"ok": false, "data": d, "from": from, "error": "err_corrupt"}
		fmt += 1
		d["format"] = fmt
	return {"ok": true, "data": d, "from": from, "error": ""}


## v1 (pre-release): player.items was a flat [[id,count],..] list without slot
## positions, explored chunks were a list of [cx,cy] pairs, and the rule set
## had no "combat"/"god_build" keys.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	var p: Dictionary = d.get("player", {})
	if p.has("items") and not p.has("inventory"):
		var inv: Array = []
		for e in p["items"]:
			inv.append(e)
		p["inventory"] = inv
		p.erase("items")
	d["player"] = p
	var w: Dictionary = d.get("world", {})
	if w.get("explored") is Array:
		var size := int(d.get("config", {}).get("size", 512))
		var n := size / MP.CHUNK
		var bits := PackedByteArray()
		bits.resize((n * n + 7) / 8)
		for e in w["explored"]:
			var b := int(e[1]) * n + int(e[0])
			if b >= 0 and b < n * n:
				bits[b >> 3] = bits[b >> 3] | (1 << (b & 7))
		w["explored"] = Marshalls.raw_to_base64(bits)
	d["world"] = w
	var cfg: Dictionary = d.get("config", {})
	var rules: Dictionary = cfg.get("rules", {})
	if not rules.has("combat"):
		rules["combat"] = cfg.get("preset", "adventure") != "creative"
	if not rules.has("god_build"):
		rules["god_build"] = cfg.get("preset", "adventure") == "creative"
	cfg["rules"] = rules
	d["config"] = cfg
	if not d.has("generator_version"):
		d["generator_version"] = 1
	if not d.has("content_version"):
		d["content_version"] = 1
	return d
