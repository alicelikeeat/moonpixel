class_name ContentRegistry
extends RefCounted
## ContentRegistry: read-only game data definitions loaded from res://content.
## Everything is referenced by stable ids (string keys, plus numeric tile ids
## that are part of the save format). Immutable after load; safe to read from
## worker threads.

const CONTENT_VERSION := 1

var tiles: Array = []                     # 256 entries: Dictionary or null
var tile_ids: Dictionary = {}             # key -> numeric id
var t_solid := PackedByteArray()
var t_water := PackedByteArray()
var t_layer := PackedByteArray()
var t_bridge := PackedByteArray()
var t_walk := PackedFloat32Array()
var t_light := PackedByteArray()
var biomes: Array = []                    # by index
var items: Dictionary = {}
var item_order: Array = []
var recipes: Dictionary = {}
var recipe_order: Array = []
var buildables: Array = []
var buildable_by_tile: Dictionary = {}
var props: Dictionary = {}
var prop_order: Array = []
var skills: Dictionary = {}
var actors: Dictionary = {}               # enemies + animals by id
var npcs: Dictionary = {}
var npc_order: Array = []
var quests: Dictionary = {}
var quest_order: Array = []
var errors: Array = []

static var _shared: ContentRegistry = null


static func shared() -> ContentRegistry:
	if _shared == null:
		_shared = ContentRegistry.new()
		_shared.load_all()
	return _shared


func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("missing content file: " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		errors.append("invalid json: " + path)
		return {}
	return parsed


func load_all() -> void:
	errors.clear()
	tiles.resize(256)
	tiles.fill(null)
	t_solid.resize(256); t_water.resize(256); t_layer.resize(256); t_bridge.resize(256); t_walk.resize(256); t_light.resize(256)
	t_walk.fill(1.0)
	for t in _read("res://content/tiles/tiles.json").get("tiles", []):
		var id := int(t["id"])
		if id <= 0 or id > 255 or tiles[id] != null:
			errors.append("bad or duplicate tile id %d" % id)
			continue
		t["id"] = id
		t["layer"] = int(t["layer"])
		tiles[id] = t
		tile_ids[t["key"]] = id
		t_solid[id] = int(t.get("solid", 0))
		t_water[id] = int(t.get("water", 0))
		t_layer[id] = t["layer"]
		t_bridge[id] = int(t.get("bridge", 0))
		t_walk[id] = float(t.get("walk", 1.0))
		t_light[id] = int(t.get("light", 0))
	for b in _read("res://content/biomes/biomes.json").get("biomes", []):
		var idx := int(b["index"])
		while biomes.size() <= idx:
			biomes.append(null)
		biomes[idx] = b
	for it in _read("res://content/items/items.json").get("items", []):
		items[it["id"]] = it
		item_order.append(it["id"])
	for r in _read("res://content/recipes/recipes.json").get("recipes", []):
		recipes[r["id"]] = r
		recipe_order.append(r["id"])
	var bd := _read("res://content/structures/buildables.json")
	for b in bd.get("buildables", []):
		buildables.append(b)
		buildable_by_tile[b["tile"]] = b
	for p in bd.get("props", []):
		props[p["key"]] = p
		prop_order.append(p["key"])
	for s in _read("res://content/skills/skills.json").get("skills", []):
		skills[s["id"]] = s
	var en := _read("res://content/enemies/enemies.json")
	for e in en.get("enemies", []):
		e["kind"] = "enemy"
		actors[e["id"]] = e
	for a in en.get("animals", []):
		a["kind"] = "animal"
		actors[a["id"]] = a
	for n in _read("res://content/npcs/npcs.json").get("npcs", []):
		npcs[n["id"]] = n
		npc_order.append(n["id"])
	for q in _read("res://content/quests/quests.json").get("quests", []):
		quests[q["id"]] = q
		quest_order.append(q["id"])
	_validate()


func _need_item(id, where: String) -> void:
	if not items.has(id):
		errors.append("%s references unknown item '%s'" % [where, str(id)])


func _need_tile(key, where: String) -> void:
	if key != "" and not tile_ids.has(key):
		errors.append("%s references unknown tile '%s'" % [where, str(key)])


func _validate() -> void:
	for t in tiles:
		if t == null:
			continue
		var w := "tile " + str(t["key"])
		for d in t.get("drops", []):
			_need_item(d[0], w)
		if t.has("grow"):
			_need_tile(t["grow"]["to"], w)
		if t.has("after"):
			_need_tile(t["after"], w)
		if t.has("harvest"):
			_need_tile(t["harvest"]["to"], w)
			for d in t["harvest"]["drops"]:
				_need_item(d[0], w)
	for b in biomes:
		if b == null:
			errors.append("biome index gap")
			continue
		var w := "biome " + str(b["key"])
		_need_tile(b["ground"], w)
		for e in b.get("trees", []) + b.get("objects", []) + b.get("decor", []):
			_need_tile(e[0], w)
		if b.has("alt"):
			_need_tile(b["alt"][0], w)
		for s in b.get("spawns", []):
			if not actors.has(s[0]):
				errors.append(w + " unknown spawn " + str(s[0]))
	for id in items:
		var it: Dictionary = items[id]
		if it.has("weapon"):
			var wp: Dictionary = it["weapon"]
			for k in ["skill", "charge"]:
				if wp.has(k) and not skills.has(wp[k]):
					errors.append("item %s unknown skill %s" % [id, wp[k]])
			if wp.has("ammo"):
				_need_item(wp["ammo"], "item " + id)
		if it.has("use") and it["use"].has("plant"):
			_need_tile(it["use"]["plant"], "item " + id)
	for id in recipes:
		var r: Dictionary = recipes[id]
		_need_item(r["out"][0], "recipe " + id)
		for k in r["in"]:
			_need_item(k, "recipe " + id)
	for b in buildables:
		_need_tile(b["tile"], "buildable")
		for k in b["cost"]:
			_need_item(k, "buildable " + str(b["tile"]))
	for k in props:
		for c in props[k]["cost"]:
			_need_item(c, "prop " + k)
	for id in skills:
		var s: Dictionary = skills[id]
		if s.has("combo_next") and not skills.has(s["combo_next"]):
			errors.append("skill %s unknown combo %s" % [id, s["combo_next"]])
		if s.has("ammo"):
			_need_item(s["ammo"], "skill " + id)
	for id in actors:
		var a: Dictionary = actors[id]
		var sk: Array = a.get("skills", []).duplicate()
		for ph in a.get("phases", []):
			sk.append_array(ph.get("skills", []))
		for s in sk:
			if not skills.has(s):
				errors.append("actor %s unknown skill %s" % [id, s])
		for d in a.get("drops", []):
			_need_item(d[0], "actor " + id)
	for id in npcs:
		var n: Dictionary = npcs[id]
		if n.has("trade"):
			for s in n["trade"]["sells"]:
				_need_item(s[0], "npc " + id)
	for id in quests:
		var q: Dictionary = quests[id]
		for p in q["prereq"]:
			if not quests.has(p):
				errors.append("quest %s unknown prereq %s" % [id, p])
		if q["giver"] != "auto" and q["giver"] != "event" and not npcs.has(q["giver"]):
			errors.append("quest %s unknown giver" % id)
		for o in q["objectives"]:
			if o.has("item"):
				_need_item(o["item"], "quest " + id)
			if o.has("def") and o["def"] != "*" and not actors.has(o["def"]):
				errors.append("quest %s unknown actor" % id)
		for r in q["rewards"].get("items", []):
			_need_item(r[0], "quest " + id)
		for e in q.get("effects", []):
			if e["type"] == "set_tiles":
				_need_tile(e["from"], "quest " + id)
				_need_tile(e["to"], "quest " + id)
			if e["type"] == "stock":
				_need_item(e["item"], "quest " + id)


func tid(key: String) -> int:
	return int(tile_ids.get(key, 0))


func tile(id: int):
	return tiles[id]


func tile_key(id: int) -> String:
	var t = tiles[id]
	return "" if t == null else str(t["key"])


func item_name(id: String) -> String:
	return MP.loc(items[id]["name"]) if items.has(id) else id


func max_stack(id: String) -> int:
	return int(items[id].get("stack", 99)) if items.has(id) else 0
