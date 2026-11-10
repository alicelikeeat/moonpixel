class_name Society
extends RefCounted
## Autonomous NPC society. Every villager decides for itself from its needs
## (hunger, rest, company), its job and what its settlement lacks. Together
## they gather, farm, build houses tile by tile, befriend each other, form
## couples, have children, grow old and die, and found new settlements when a
## village gets crowded -- which is also what makes the map keep expanding.
##
## Entirely local and deterministic (seeded RNG, utility rules); no network or
## cloud model is involved. Runs headless; rendering only reads agent state.

signal event(key: String, text: String, pos: Vector2)
signal agent_born(agent)
signal agent_died(agent)

const YEAR := OpenWorld.YEAR
const HOUR := MP.DAY_SECONDS / 24.0
const SPEED := 46.0
const HOUSE_CAP := 4
const NAMES_EN := ["Aren", "Bela", "Cato", "Dara", "Elin", "Faro", "Gwen", "Hale", "Iris", "Joss", "Kira", "Lorn", "Mira", "Nico", "Orla", "Penn", "Quin", "Rhea", "Sol", "Tess", "Ulan", "Vera", "Wyn", "Yara", "Zed", "Ash", "Bryn", "Cole", "Dawn", "Eben", "Fern", "Gale"]
const NAMES_ZH := ["岚", "禾", "青", "石", "月", "川", "竹", "溪", "松", "雨", "晴", "木", "星", "云", "叶", "砚", "舟", "霜", "朔", "棠", "原", "薇", "风", "遥", "泽", "灰", "岭", "炭", "晓", "岩", "蕨", "澜"]
const CLANS_EN := ["Oakhand", "Riverun", "Stonefield", "Moonvale", "Ashgrove", "Brightwater", "Hollowell", "Thornwick", "Greyfen", "Summerlea", "Windmere", "Deepwood"]
const CLANS_ZH := ["橡", "江", "石田", "月谷", "梣", "明川", "空井", "荆", "灰泽", "夏原", "风湖", "深林"]
const TOWN_EN := ["Moonfall", "Reedmere", "Oakrest", "Stonebrook", "Ashford", "Brightmoor", "Fernhollow", "Willowend", "Frostgate", "Dunehaven", "Mistvale", "Larkfield", "Emberly", "Pinewatch", "Saltmarsh", "Goldlea"]
const TOWN_ZH := ["月落", "苇湖", "橡息", "石溪", "梣渡", "明泽", "蕨谷", "柳尾", "霜门", "沙港", "雾谷", "雀田", "余烬", "松望", "盐沼", "金原"]
const SKINS := ["#f0c8a8", "#e8b890", "#d8a878", "#c89060", "#a87048", "#8a5a3a"]
const HAIRS := ["#2a2a2a", "#5a3a22", "#8a5a30", "#c8a060", "#b84a2a", "#d8d8e0"]
const SHIRTS := ["#3a6ac8", "#c84a4a", "#3a8a5a", "#b8983a", "#8a4ab0", "#4a9ab0", "#c87a3a", "#6a6e86"]

const TXT := {
	"born": {"en": "%s was born in %s", "zh": "%s 在%s出生了"},
	"died_old": {"en": "%s died of old age (%d)", "zh": "%s 寿终正寝（%d 岁）"},
	"died_hunger": {"en": "%s starved to death (%d)", "zh": "%s 饿死了（%d 岁）"},
	"died_ill": {"en": "%s died of illness (%d)", "zh": "%s 因病去世（%d 岁）"},
	"paired": {"en": "%s and %s became a couple", "zh": "%s 和 %s 结为伴侣"},
	"built": {"en": "%s finished a %s", "zh": "%s 建成了一座%s"},
	"founded": {"en": "%d settlers from %s founded %s", "zh": "%d 位来自%s的开拓者建立了%s"},
	"arrived": {"en": "%d wanderers joined %s", "zh": "%d 位流浪者加入了%s"},
	"abandoned": {"en": "%s has been abandoned", "zh": "%s 已被废弃"},
	"house": {"en": "house", "zh": "房屋"}, "farm": {"en": "farm", "zh": "农田"}, "well": {"en": "well", "zh": "水井"},
	"lights": {"en": "lantern square", "zh": "灯火广场"},
	"job_": {"en": "resting", "zh": "休息"}, "job_child": {"en": "child", "zh": "孩子"}, "job_elder": {"en": "elder", "zh": "长者"},
	"job_forager": {"en": "forager", "zh": "采集者"}, "job_woodcutter": {"en": "woodcutter", "zh": "伐木工"},
	"job_miner": {"en": "stonecutter", "zh": "采石工"}, "job_farmer": {"en": "farmer", "zh": "农夫"}, "job_builder": {"en": "builder", "zh": "建筑工"},
	"t_hungry": {"en": "I'm so hungry... the stores are empty.", "zh": "好饿……仓库已经空了。"},
	"t_ate": {"en": "A good meal.", "zh": "吃了顿饱饭。"},
	"t_chat": {"en": "Had a nice talk with %s.", "zh": "和%s聊得很开心。"},
	"t_quarrel": {"en": "Argued with %s.", "zh": "和%s吵了一架。"},
	"t_love": {"en": "%s and I are together now.", "zh": "我和%s在一起了。"},
	"t_child": {"en": "Our child %s was born!", "zh": "我们的孩子%s出生了！"},
	"t_grief": {"en": "I miss %s.", "zh": "我很想念%s。"},
	"t_built": {"en": "We finished building a %s.", "zh": "我们把%s盖好了。"},
	"t_home": {"en": "I have a home now.", "zh": "我终于有家了。"},
	"t_new_land": {"en": "We set out to found %s.", "zh": "我们出发去建立%s。"},
	"t_gift": {"en": "A traveler gave me food. Kind soul.", "zh": "一位旅人送了我食物，真是好人。"},
	"t_work_forager": {"en": "Picking berries for the stores.", "zh": "在给仓库采浆果。"},
	"t_work_woodcutter": {"en": "Felling trees. We need timber.", "zh": "在伐木，我们需要木材。"},
	"t_work_miner": {"en": "Breaking stone.", "zh": "在采石。"},
	"t_work_farmer": {"en": "Tending the wheat.", "zh": "在照料麦田。"},
	"t_work_builder": {"en": "Raising walls.", "zh": "在砌墙盖房。"},
	"s_hello": {"en": "Hello, traveler.", "zh": "你好，旅行者。"},
	"s_friend": {"en": "Good to see you again, friend!", "zh": "又见面了，朋友！"},
	"s_hungry": {"en": "Do you have anything to eat? We are short of food.", "zh": "你有吃的吗？我们的粮食不够了。"},
	"s_tired": {"en": "I can barely keep my eyes open.", "zh": "我困得睁不开眼了。"},
	"s_grief": {"en": "I lost someone dear. Forgive my mood.", "zh": "我失去了亲人，请原谅我的情绪。"},
	"s_preg": {"en": "We are expecting a child!", "zh": "我们要有孩子了！"},
	"s_nohome": {"en": "I sleep by the fire for now. We are building more houses.", "zh": "我暂时睡在篝火旁，大家正在盖更多的房子。"},
	"s_child": {"en": "Wanna play? I'm %d!", "zh": "要一起玩吗？我 %d 岁啦！"},
	"s_elder": {"en": "I have seen %d winters. This village grew from a single campfire.", "zh": "我已经度过了 %d 个冬天。这个村子是从一堆篝火发展起来的。"},
	"s_town": {"en": "%s has %d people and %d houses now.", "zh": "%s现在有 %d 人、%d 座房屋。"},
}

var world: OpenWorld
var content: ContentRegistry
var budget: MemoryBudget
var rng := RandomNumberGenerator.new()
var agents: Dictionary = {}          # id -> Agent
var settlements: Dictionary = {}     # id -> Settlement
var next_id := 1
var next_sid := 1
var next_bid := 1
var min_population := 100
var stats := {"births": 0, "deaths": 0, "old": 0, "hunger": 0, "ill": 0, "pairs": 0, "buildings": 0, "founded": 0, "immigrants": 0, "tiles_placed": 0}
var log: Array = []                  # recent event texts
var _hour_acc := 0.0
var _migr_acc := 0.0
var T: Dictionary = {}


func _init(p_world: OpenWorld, p_budget: MemoryBudget, p_seed: int) -> void:
	world = p_world
	content = p_world.content
	budget = p_budget
	rng.seed = p_seed
	for k in ["tree_oak", "rock", "berry_bush", "berry_bush_empty", "wheat_0", "wheat_2", "farmland", "campfire", "chest", "crate", "barrel",
			"cobble_road", "path", "wall_wood", "wall_stone", "door_wood", "wood_floor", "bed", "table", "torch", "well", "lantern_post", "grave", "sapling"]:
		T[k] = content.tid(k)
	world.tile_changed.connect(_on_tile_changed)


static func tx(key: String) -> String:
	return MP.loc(TXT[key])


func _emit(key: String, args: Array, pos: Vector2) -> void:
	var text := tx(key) % args
	log.append({"t": world.time, "text": text})
	if log.size() > 60:
		log.pop_front()
	event.emit(key, text, pos)


# ====================================================================== setup
func _new_agent(s: Settlement, age_years: float, female: bool) -> Agent:
	var a := Agent.new()
	a.id = next_id
	next_id += 1
	var ni := rng.randi() % NAMES_EN.size()
	var ci := rng.randi() % CLANS_EN.size()
	a.name = {"en": NAMES_EN[ni], "zh": NAMES_ZH[ni]}
	a.clan = {"en": CLANS_EN[ci], "zh": CLANS_ZH[ci]}
	a.female = female
	a.birth = world.time - age_years * YEAR
	a.sid = s.id
	a.traits = {"dil": rng.randf_range(0.2, 1.0), "soc": rng.randf_range(0.2, 1.0), "bold": rng.randf()}
	a.look = {"skin": SKINS[rng.randi() % SKINS.size()], "hair": HAIRS[rng.randi() % HAIRS.size()], "shirt": SHIRTS[rng.randi() % SHIRTS.size()]}
	a.hunger = rng.randf_range(0.0, 0.4)
	a.energy = rng.randf_range(0.6, 1.0)
	a.social = rng.randf_range(0.0, 0.6)
	a.think_t = rng.randf() * 1.5
	var t := world.find_free_near(s.center + Vector2i(rng.randi_range(-5, 5), rng.randi_range(2, 6)), 6)
	a.pos = MP.tile_center(t)
	a.prev_pos = a.pos
	agents[a.id] = a
	s.members.append(a.id)
	return a


func found_settlement(center: Vector2i) -> Settlement:
	var s := Settlement.new()
	s.id = next_sid
	next_sid += 1
	var ni := (s.id - 1) % TOWN_EN.size()
	var suffix := "" if s.id <= TOWN_EN.size() else " %d" % (1 + (s.id - 1) / TOWN_EN.size())
	s.name = {"en": TOWN_EN[ni] + suffix, "zh": TOWN_ZH[ni] + suffix}
	s.center = center
	s.founded = world.time
	s.last_found = world.time
	settlements[s.id] = s
	_attach(s)
	# the founding camp: fire, a chest and trodden ground
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := center.x + dx
			var y := center.y + dy
			world.set_tile(MP.L_OBJECT, x, y, 0)
			world.set_tile(MP.L_DECOR, x, y, 0)
			if world.is_land(x, y) and dx * dx + dy * dy <= 5:
				world.set_tile(MP.L_STRUCT, x, y, T["cobble_road"])
	world.set_tile(MP.L_OBJECT, center.x, center.y, T["campfire"])
	world.set_tile(MP.L_OBJECT, center.x - 2, center.y - 2, T["chest"])
	world.set_tile(MP.L_OBJECT, center.x + 2, center.y - 2, T["crate"])
	return s


## Pins the settlement's chunks and builds its navigation grid.
func _attach(s: Settlement) -> void:
	var cc := Vector2i(s.center.x >> 5, s.center.y >> 5)
	s.origin = Vector2i((cc.x - 1) * MP.CHUNK, (cc.y - 1) * MP.CHUNK)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			world.pin(cc.x + dx, cc.y + dy)
	s.nav = AStarGrid2D.new()
	s.nav.region = Rect2i(0, 0, Settlement.SPAN, Settlement.SPAN)
	s.nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	s.nav.update()
	for y in Settlement.SPAN:
		for x in Settlement.SPAN:
			if world.blocked(s.origin.x + x, s.origin.y + y):
				s.nav.set_point_solid(Vector2i(x, y), true)
	s.res_t = 0.0


func _detach(s: Settlement) -> void:
	var cc := Vector2i(s.center.x >> 5, s.center.y >> 5)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			world.unpin(cc.x + dx, cc.y + dy)
	s.nav = null


func _on_tile_changed(x: int, y: int, _layer: int, _old: int, _new: int) -> void:
	var t := Vector2i(x, y)
	for sid in settlements:
		var s: Settlement = settlements[sid]
		if s.nav != null and s.in_area(t):
			s.nav.set_point_solid(t - s.origin, world.blocked(x, y))


## Initial population: `count` settlements with `per` villagers of mixed ages.
func bootstrap(origin: Vector2i, count: int = 4, per: int = 30) -> void:
	var centers: Array = []
	for i in count:
		var from: Vector2i = origin if centers.is_empty() else centers[rng.randi() % centers.size()]
		var p := world.find_site(from, 0 if centers.is_empty() else 70, 40 if centers.is_empty() else 140, 900 + i * 7, centers, 64.0)
		if p.x == 0x7fffffff:
			p = world.find_site(origin, 0, 600, 990 + i, centers, 64.0)
		if p.x == 0x7fffffff:
			continue
		centers.append(p)
		var s := found_settlement(p)
		s.stock["food"] = per * 8.0
		s.stock["wood"] = 30.0
		s.stock["stone"] = 6.0
		var singles: Array = []
		for n in per:
			var r := rng.randf()
			var age := rng.randf_range(0.0, 13.0) if r < 0.22 else (rng.randf_range(16.0, 45.0) if r < 0.82 else rng.randf_range(45.0, 72.0))
			var a := _new_agent(s, age, n % 2 == 0)
			if age >= 20.0 and age < 50.0:
				singles.append(a)
		# some founding couples so that family life starts right away
		var men: Array = singles.filter(func(a): return not a.female)
		var women: Array = singles.filter(func(a): return a.female)
		for i2 in mini(men.size(), women.size()) / 2:
			_pair(men[i2], women[i2], false)


# ====================================================================== main tick
func tick(dt: float) -> void:
	world.advance(dt)
	for sid in settlements:
		var s: Settlement = settlements[sid]
		if s.abandoned:
			continue
		s.plan_t -= dt
		if s.plan_t <= 0.0:
			s.plan_t = 6.0
			_plan(s)
		if world.time >= s.res_t:
			s.res_t = world.time + 25.0
			_scan(s)
	for id in agents.keys():
		var a: Agent = agents[id]
		if a.alive:
			_update(a, dt)
	_hour_acc += dt
	while _hour_acc >= HOUR:
		_hour_acc -= HOUR
		_hourly()
	_migr_acc += dt
	if _migr_acc >= YEAR * 0.1:
		_migr_acc = 0.0
		_immigration()
		for sid in settlements:
			var s: Settlement = settlements[sid]
			# the known map keeps growing outwards from every living settlement
			if not s.abandoned:
				world.survey(Vector2i(s.center.x >> 5, s.center.y >> 5), 24)
		world.maintain()


func alive_count() -> int:
	return agents.size()


# ====================================================================== settlement brain
func _scan(s: Settlement) -> void:
	var trees: Array = []
	var rocks: Array = []
	var berries: Array = []
	var inner := 6
	for y in range(inner, Settlement.SPAN - inner):
		var wy := s.origin.y + y
		var c0 := world.get_chunk(s.origin.x >> 5, wy >> 5)
		for x in range(inner, Settlement.SPAN - inner):
			var wx := s.origin.x + x
			if (wx & 31) == 0:
				c0 = world.get_chunk(wx >> 5, wy >> 5)
			var o: int = c0.layers[2][(wy & 31) * MP.CHUNK + (wx & 31)]
			if o == 0:
				continue
			var t: Dictionary = content.tiles[o]
			if o == T["berry_bush"]:
				berries.append(Vector2i(wx, wy))
			elif t.get("natural", 0) == 1 and t.get("big", 0) == 1:
				trees.append(Vector2i(wx, wy))
			elif o == T["rock"]:
				rocks.append(Vector2i(wx, wy))
	s.res = {"tree": trees, "rock": rocks, "berry": berries}
	for k in s.claims.keys():
		if not agents.has(s.claims[k]):
			s.claims.erase(k)


func _footprint_ok(s: Settlement, x: int, y: int, w: int, h: int) -> bool:
	if not s.in_area(Vector2i(x - 2, y - 2)) or not s.in_area(Vector2i(x + w + 2, y + h + 2)):
		return false
	for b in s.buildings:
		if Rect2i(x - 1, y - 1, w + 2, h + 2).intersects(Rect2i(b["x"], b["y"], b["w"], b["h"])):
			return false
	for yy in range(y - 1, y + h + 1):
		for xx in range(x - 1, x + w + 1):
			if not world.is_land(xx, yy):
				return false
			var g := world.tile(MP.L_GROUND, xx, yy)
			if content.tiles[g].get("built", 0) == 1 or g == T["farmland"]:
				return false
			var o := world.tile(MP.L_OBJECT, xx, yy)
			if o != 0 and content.tiles[o].get("natural", 0) == 0:
				return false
	return true


func _free_slot(s: Settlement, w: int, h: int) -> Vector2i:
	var cands: Array = []
	for gy in range(-4, 5):
		for gx in range(-4, 5):
			if absi(gx) + absi(gy) == 0:
				continue
			cands.append(Vector2i(gx, gy))
	cands.sort_custom(func(a, b): return a.length_squared() < b.length_squared() or (a.length_squared() == b.length_squared() and (a.y * 16 + a.x) < (b.y * 16 + b.x)))
	for g in cands:
		var key := "%d,%d" % [g.x, g.y]
		if s.used_slots.has(key):
			continue
		var x: int = s.center.x + g.x * 9 - w / 2
		var y: int = s.center.y + g.y * 8 - h / 2
		if _footprint_ok(s, x, y, w, h):
			s.used_slots[key] = true
			return Vector2i(x, y)
		s.used_slots[key] = true     # unusable ground: never retry
	return Vector2i(0x7fffffff, 0)


func _add_clear_cells(cells: Array, x: int, y: int, w: int, h: int) -> void:
	for dy in h:
		for dx in w:
			if world.tile(MP.L_OBJECT, x + dx, y + dy) != 0:
				cells.append([dx, dy, MP.L_OBJECT, "", 0, 0])
			if world.tile(MP.L_DECOR, x + dx, y + dy) != 0:
				cells.append([dx, dy, MP.L_DECOR, "", 0, 0])


func _queue(s: Settlement, type: String) -> bool:
	var w := 6
	var h := 5
	if type == "farm":
		h = 4
	var cells: Array = []
	var pos := Vector2i.ZERO
	var door := Vector2i.ZERO
	var cap := 0
	if type == "well":
		pos = s.center + Vector2i(3, 3)
		w = 1; h = 1
		cells.append([0, 0, MP.L_OBJECT, "", 0, 0])
		cells.append([0, 0, MP.L_OBJECT, "well", 0, 8])
	elif type == "lights":
		pos = s.center + Vector2i(-4, -4)
		w = 9; h = 9
		for c in [[0, 0], [8, 0], [0, 8], [8, 8]]:
			cells.append([c[0], c[1], MP.L_OBJECT, "", 0, 0])
			cells.append([c[0], c[1], MP.L_OBJECT, "lantern_post", 2, 1])
	else:
		pos = _free_slot(s, w, h)
		if pos.x == 0x7fffffff:
			return false
		_add_clear_cells(cells, pos.x, pos.y, w, h)
	if type == "farm":
		for dy in h:
			for dx in w:
				cells.append([dx, dy, MP.L_GROUND, "farmland", 0, 0])
		for dy in h:
			for dx in w:
				cells.append([dx, dy, MP.L_OBJECT, "wheat_0", 0, 0])
		door = pos + Vector2i(w / 2, h)
	elif type == "house":
		cap = HOUSE_CAP
		var stone: bool = s.count_type("house") >= 6 and s.stock["stone"] > 20.0
		var wall := "wall_stone" if stone else "wall_wood"
		# door faces the village centre
		var cx := pos.x + w / 2
		var cy := pos.y + h / 2
		var dd := Vector2i(2, h - 1)
		var out := Vector2i(0, 1)
		if absi(s.center.y - cy) >= absi(s.center.x - cx):
			if s.center.y < cy:
				dd = Vector2i(2, 0); out = Vector2i(0, -1)
		else:
			dd = Vector2i(0, 2) if s.center.x < cx else Vector2i(w - 1, 2)
			out = Vector2i(-1, 0) if s.center.x < cx else Vector2i(1, 0)
		for dy in range(1, h - 1):
			for dx in range(1, w - 1):
				cells.append([dx, dy, MP.L_GROUND, "wood_floor", 0, 0])
		for dy in h:
			for dx in w:
				if dx == 0 or dy == 0 or dx == w - 1 or dy == h - 1:
					if Vector2i(dx, dy) == dd:
						cells.append([dx, dy, MP.L_OBJECT, "door_wood", 1, 0])
					else:
						cells.append([dx, dy, MP.L_OBJECT, wall, 0 if stone else 1, 1 if stone else 0])
		# furniture on the side away from the door
		var far_y := 1 if dd.y != 0 else (1 if dd.y == 0 and dd.x != 0 else h - 2)
		if dd.y == 0 and dd.x == 2:
			far_y = h - 2
		var far_x := w - 2 if dd.x == 0 and dd.y == 2 else 1
		cells.append([far_x, far_y, MP.L_OBJECT, "bed", 2, 0])
		cells.append([w - 1 - far_x, far_y, MP.L_OBJECT, "bed", 2, 0])
		door = pos + dd + out
	s.buildings.append({"id": next_bid, "type": type, "x": pos.x, "y": pos.y, "w": w, "h": h, "cells": cells, "next": 0, "placed": 0,
		"retry": [], "done": false, "residents": [], "cap": cap, "door": door})
	next_bid += 1
	return true


func _plan(s: Settlement) -> void:
	# drop the dead, count the living
	var living: Array = []
	for id in s.members:
		if agents.has(id):
			living.append(agents[id])
	s.members = living.map(func(a): return a.id)
	if living.is_empty():
		s.abandoned = true
		_detach(s)
		_emit("abandoned", [MP.loc(s.name)], MP.tile_center(s.center))
		return
	var pop := living.size()
	# storage is finite: surplus food spoils
	s.stock["food"] = minf(s.stock["food"], 40.0 + pop * 14.0)
	var workers: Array = living.filter(func(a): return a.stage(world.time) == "adult" and not a.travelling)
	# --- projects
	var open_projects := 0
	var house_cap := 0
	for b in s.buildings:
		if not b["done"]:
			open_projects += 1
		if b["type"] == "house":
			house_cap += int(b["cap"])
	if open_projects < 2:
		var homeless := living.filter(func(a): return a.home < 0).size()
		if s.count_type("farm") < int(ceil(pop / 9.0)) and s.count_type("farm") * 2 <= s.count_type("house"):
			_queue(s, "farm")
		elif house_cap < pop + 1 or homeless > 0 and house_cap < pop + 4:
			_queue(s, "house")
		elif pop >= 14 and s.count_type("well") == 0:
			_queue(s, "well")
		elif pop >= 22 and s.count_type("lights") == 0:
			_queue(s, "lights")
	# --- housing assignment (families stay together)
	for a in living:
		if a.home >= 0 and s.building(a.home) == null:
			a.home = -1
		if a.home >= 0:
			continue
		var want := -1
		for rel_id in [a.partner, a.mother, a.father]:
			if rel_id != 0 and agents.has(rel_id) and agents[rel_id].sid == s.id and agents[rel_id].home >= 0:
				var hb = s.building(agents[rel_id].home)
				if hb != null and hb["residents"].size() < int(hb["cap"]) + 1:
					want = hb["id"]
					break
		if want < 0 and a.stage(world.time) != "child":
			for b in s.buildings:
				if b["type"] == "house" and b["done"] and b["residents"].size() < int(b["cap"]) - 1:
					want = b["id"]
					break
		if want >= 0:
			a.home = want
			s.building(want)["residents"].append(a.id)
			a.think(world.time, "t_home")
	# --- jobs
	var n := workers.size()
	var project = s.active_project()
	var need_wood := 10.0
	var need_stone := 4.0
	if project != null:
		for i in range(int(project["next"]), project["cells"].size()):
			need_wood += float(project["cells"][i][4])
			need_stone += float(project["cells"][i][5])
	var quota := {"builder": 0, "woodcutter": 0, "miner": 0, "farmer": 0, "forager": 0}
	if project != null:
		quota["builder"] = clampi(1 + n / 7, 1, 5)
	quota["woodcutter"] = clampi(int(n * (0.3 if s.stock["wood"] < need_wood else 0.1)), 1, n)
	quota["miner"] = clampi(int(n * (0.18 if s.stock["stone"] < need_stone else 0.04)), 0, n)
	quota["farmer"] = mini(s.count_type("farm", true) * 2, int(n * 0.4))
	var hungry: bool = s.stock["food"] < pop * 4.0
	if hungry:
		quota["woodcutter"] = mini(quota["woodcutter"], 1 + n / 10)
		quota["builder"] = mini(quota["builder"], 2)
	workers.sort_custom(func(a, b): return a.id < b.id)
	var pending: Array = []
	for a in workers:
		if quota.has(a.job) and quota[a.job] > 0:
			quota[a.job] -= 1
		else:
			pending.append(a)
	for a in pending:
		a.job = "forager" if s.stock["food"] < pop * 8.0 else ("woodcutter" if s.stock["wood"] < 80.0 else ("builder" if project != null else "forager"))
		for j in ["builder", "farmer", "woodcutter", "miner"]:
			if quota[j] > 0:
				quota[j] -= 1
				a.job = j
				break
	for a in living:
		if a.stage(world.time) != "adult":
			a.job = ""
	# --- expansion: a crowded village sends settlers out into unknown land
	if pop >= 34 and world.time - s.last_found > 1.5 * YEAR and _living_settlements() < budget.max_settlements and agents.size() < budget.max_agents:
		_expedition(s, living)


func _living_settlements() -> int:
	var n := 0
	for sid in settlements:
		if not settlements[sid].abandoned:
			n += 1
	return n


func _expedition(s: Settlement, living: Array) -> void:
	s.last_found = world.time
	var centers: Array = []
	for sid in settlements:
		centers.append(settlements[sid].center)
	var site := world.find_site(s.center, 80, 170, 2000 + next_sid * 13, centers, 70.0)
	if site.x == 0x7fffffff:
		return
	var group: Array = []
	for a in living:
		if group.size() >= 9:
			break
		var age: float = a.age(world.time)
		if age < 17.0 or age > 42.0 or group.has(a) or a.travelling:
			continue
		group.append(a)
		if a.partner != 0 and agents.has(a.partner) and not group.has(agents[a.partner]):
			group.append(agents[a.partner])
		for cid in a.children:
			if agents.has(cid) and agents[cid].age(world.time) < 14.0 and not group.has(agents[cid]):
				group.append(agents[cid])
	if group.size() < 5:
		return
	var ns := found_settlement(site)
	var food := minf(s.stock["food"] * 0.3, group.size() * 8.0)
	var wood := minf(s.stock["wood"] * 0.3, 30.0)
	s.stock["food"] -= food
	s.stock["wood"] -= wood
	ns.stock["food"] = food + group.size() * 3.0
	ns.stock["wood"] = wood + 10.0
	for a in group:
		_leave_home(a, s)
		s.members.erase(a.id)
		ns.members.append(a.id)
		a.sid = ns.id
		a.task = {}
		a.path = []
		a.travelling = true
		a.travel_to = MP.tile_center(world.find_free_near(site + Vector2i(rng.randi_range(-4, 4), rng.randi_range(2, 5)), 6))
		a.think(world.time, "t_new_land", [MP.loc(ns.name)])
	stats["founded"] += 1
	_emit("founded", [group.size(), MP.loc(s.name), MP.loc(ns.name)], MP.tile_center(site))


func _leave_home(a: Agent, s: Settlement) -> void:
	if a.home >= 0:
		var b = s.building(a.home)
		if b != null:
			b["residents"].erase(a.id)
	a.home = -1


func _immigration() -> void:
	if agents.size() >= min_population or _living_settlements() == 0:
		return
	var best: Settlement = null
	for sid in settlements:
		var s: Settlement = settlements[sid]
		if not s.abandoned and (best == null or s.members.size() < best.members.size()):
			best = s
	var n := rng.randi_range(3, 6)
	for i in n:
		_new_agent(best, rng.randf_range(17.0, 34.0), i % 2 == 0)
	best.stock["food"] += n * 6.0
	stats["immigrants"] += n
	_emit("arrived", [n, MP.loc(best.name)], MP.tile_center(best.center))


# ====================================================================== agent brain
func _update(a: Agent, dt: float) -> void:
	a.prev_pos = a.pos
	a.moving = false
	var s: Settlement = settlements[a.sid]
	a.hunger = minf(1.0, a.hunger + dt / (0.45 * MP.DAY_SECONDS))
	a.social = minf(1.0, a.social + dt / (0.6 * MP.DAY_SECONDS))
	a.grief = maxf(0.0, a.grief - dt / (1.5 * YEAR))
	if a.sleeping:
		a.energy = minf(1.0, a.energy + dt / (0.3 * MP.DAY_SECONDS))
	else:
		a.energy = maxf(0.0, a.energy - dt / (0.75 * MP.DAY_SECONDS))
	if a.hunger >= 1.0:
		a.health -= dt / (0.6 * MP.DAY_SECONDS)
		if a.health <= 0.0:
			_die(a, "hunger")
			return
	else:
		a.health = minf(1.0, a.health + dt / MP.DAY_SECONDS)
	if a.travelling:
		var to := a.travel_to - a.pos
		var step := SPEED * 1.2 * dt
		a.moving = true
		a.facing = to.normalized()
		if to.length() <= step:
			a.pos = a.travel_to
			a.travelling = false
		else:
			a.pos += a.facing * step
		return
	if s.nav == null:
		return
	if a.task.is_empty():
		a.think_t -= dt
		if a.think_t > 0.0:
			return
		a.think_t = 0.6 + rng.randf() * 0.8
		_decide(a, s)
		if a.task.is_empty():
			return
	_run(a, s, dt)


func _stand_tile(s: Settlement, a: Agent, target: Vector2i, beside: bool = false) -> Vector2i:
	## Nearest walkable tile next to (or on) a target tile.
	if not beside and not world.blocked(target.x, target.y):
		return target
	var best := Vector2i(0x7fffffff, 0)
	var best_d := 1e12
	var me := MP.tile_of(a.pos)
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var t: Vector2i = target + d
		if s.in_area(t) and not world.blocked(t.x, t.y):
			var dd := float((t - me).length_squared())
			if dd < best_d:
				best_d = dd
				best = t
	return best


func _go(a: Agent, s: Settlement, target: Vector2i, act: String, dur: float, data: Dictionary = {}, beside: bool = false) -> bool:
	var stand := _stand_tile(s, a, target, beside)
	if stand.x == 0x7fffffff or not s.in_area(stand):
		return false
	var from := MP.tile_of(a.pos)
	if not s.in_area(from) or world.blocked(from.x, from.y):
		# outside the village or stuck inside something: step back to the square
		from = world.find_free_near(s.center + Vector2i(0, 3), 8)
		a.pos = MP.tile_center(from)
	var ids := s.nav.get_id_path(from - s.origin, stand - s.origin)
	if ids.is_empty():
		return false
	a.path = []
	for p in ids:
		a.path.append(MP.tile_center(p + s.origin))
	a.path_i = 1
	a.task = {"act": act, "target": target, "dur": dur, "t": 0.0, "stage": 0}
	a.task.merge(data)
	return true


func _decide(a: Agent, s: Settlement) -> void:
	var now := world.time
	var st := a.stage(now)
	a.sleeping = false
	if a.carry_n > 0.0:
		if _go(a, s, s.center, "deliver", 0.4):
			return
	if a.hunger > 0.55:
		if s.stock["food"] >= 1.0:
			if _go(a, s, s.center, "eat", 1.5):
				return
			if a.hunger > 0.85:
				# cannot reach the stores: someone brings a ration
				s.stock["food"] -= 1.0
				a.hunger -= 0.6
				return
		elif st != "child" and _work(a, s, "forager"):
			a.think(now, "t_hungry")
			return
	var night := world.is_night()
	if (night and a.energy < 0.85) or a.energy < 0.15:
		var hb = s.building(a.home) if a.home >= 0 else null
		var spot: Vector2i = (Vector2i(hb["x"] + 2 + a.id % 2, hb["y"] + 2) if hb != null and hb["done"] else s.center + Vector2i(a.id % 5 - 2, 3 + a.id % 2))
		if _go(a, s, spot, "sleep", 9999.0):
			return
	var h := world.hour()
	if st == "child":
		_wander(a, s, 7, "play")
		return
	if a.social > 0.7 or (h > 17.0 and a.social > 0.35) or (st == "elder" and rng.randf() < 0.5):
		if _go(a, s, s.center + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4)), "social", 3.0):
			return
	if st == "adult" and a.job != "" and _work(a, s, a.job):
		return
	if st == "elder" and rng.randf() < 0.4 and _work(a, s, "forager"):
		return
	_wander(a, s, 6, "idle")


func _wander(a: Agent, s: Settlement, radius: int, act: String) -> void:
	var base: Vector2i = s.center
	if a.home >= 0 and s.building(a.home) != null:
		base = s.building(a.home)["door"]
	for i in 4:
		var t := base + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if s.in_area(t) and not world.blocked(t.x, t.y) and _go(a, s, t, act, rng.randf_range(1.0, 3.0)):
			return


func _nearest(a: Agent, s: Settlement, list: Array, valid: Callable) -> Vector2i:
	var best := Vector2i(0x7fffffff, 0)
	var best_d := 1e12
	var me := MP.tile_of(a.pos)
	var n := list.size()
	if n == 0:
		return best
	var start := rng.randi() % n
	for k in mini(n, 40):
		var t: Vector2i = list[(start + k * 7) % n]
		if s.claims.has(t) or not valid.call(t):
			continue
		var d := float((t - me).length_squared())
		if d < best_d:
			best_d = d
			best = t
	return best


func _is_tree(p: Vector2i) -> bool:
	var o := world.tile(MP.L_OBJECT, p.x, p.y)
	return o != 0 and content.tiles[o].get("big", 0) == 1


func _is_rock(p: Vector2i) -> bool:
	return world.tile(MP.L_OBJECT, p.x, p.y) == T["rock"]


func _is_berry(p: Vector2i) -> bool:
	return world.tile(MP.L_OBJECT, p.x, p.y) == T["berry_bush"]


func _work(a: Agent, s: Settlement, job: String) -> bool:
	match job:
		"builder":
			var b = s.active_project()
			if b == null:
				return _work(a, s, "woodcutter")
			var idx := -1
			if not b["retry"].is_empty():
				idx = b["retry"].pop_back()
			elif int(b["next"]) < b["cells"].size():
				idx = int(b["next"])
			if idx < 0:
				return false       # every cell is in someone's hands
			var cell: Array = b["cells"][idx]
			if s.stock["wood"] < float(cell[4]) or s.stock["stone"] < float(cell[5]):
				if idx != int(b["next"]):
					b["retry"].append(idx)
				return _work(a, s, "woodcutter" if s.stock["wood"] < float(cell[4]) else "miner")
			var target := Vector2i(b["x"] + int(cell[0]), b["y"] + int(cell[1]))
			var solid: bool = str(cell[3]) != "" and content.t_solid[content.tid(str(cell[3]))] != 0
			if not _go(a, s, target, "build", 1.2, {"bid": b["id"], "cell": idx}, solid):
				if idx != int(b["next"]):
					b["retry"].append(idx)
				else:
					# unreachable right now: skip it and come back later
					b["next"] = idx + 1
					b["retry"].push_front(idx)
				return false
			if idx == int(b["next"]):
				b["next"] = idx + 1
			s.stock["wood"] -= float(cell[4])
			s.stock["stone"] -= float(cell[5])
			return true
		"woodcutter":
			var t := _nearest(a, s, s.res["tree"], _is_tree)
			if t.x != 0x7fffffff and _go(a, s, t, "chop", 5.0):
				s.claims[t] = a.id
				return true
		"miner":
			var t := _nearest(a, s, s.res["rock"], _is_rock)
			if t.x != 0x7fffffff and _go(a, s, t, "mine", 6.0):
				s.claims[t] = a.id
				return true
		"farmer":
			for b in s.buildings:
				if b["type"] != "farm" or not b["done"]:
					continue
				for dy in int(b["h"]):
					for dx in int(b["w"]):
						var t := Vector2i(b["x"] + dx, b["y"] + dy)
						if s.claims.has(t):
							continue
						var o := world.tile(MP.L_OBJECT, t.x, t.y)
						if (o == T["wheat_2"] or o == 0) and _go(a, s, t, "reap" if o != 0 else "sow", 2.0):
							s.claims[t] = a.id
							return true
			return _work(a, s, "forager")
		"forager":
			var t := _nearest(a, s, s.res["berry"], _is_berry)
			if t.x != 0x7fffffff and _go(a, s, t, "forage", 3.0):
				s.claims[t] = a.id
				return true
			# nothing to pick: help where the village is short
			if s.stock["wood"] < 60.0:
				return _work(a, s, "woodcutter")
			if s.stock["stone"] < 30.0:
				return _work(a, s, "miner")
	return false


func _abort(a: Agent, s: Settlement) -> void:
	if a.task.has("target"):
		s.claims.erase(a.task["target"])
	if a.task.get("act", "") == "build":
		var b = s.building(int(a.task["bid"]))
		if b != null:
			b["retry"].append(int(a.task["cell"]))
			var cell: Array = b["cells"][int(a.task["cell"])]
			s.stock["wood"] += float(cell[4])
			s.stock["stone"] += float(cell[5])
	a.task = {}
	a.path = []
	a.sleeping = false


func _run(a: Agent, s: Settlement, dt: float) -> void:
	var task := a.task
	if int(task["stage"]) == 0:
		var budget_px := SPEED * dt * (0.75 if a.stage(world.time) != "adult" else 1.0) * (0.6 + 0.4 * a.health)
		while budget_px > 0.0 and a.path_i < a.path.size():
			var wp: Vector2 = a.path[a.path_i]
			var to := wp - a.pos
			var d := to.length()
			if d <= budget_px:
				a.pos = wp
				budget_px -= d
				a.path_i += 1
			else:
				a.facing = to / d
				a.pos += a.facing * budget_px
				budget_px = 0.0
			a.moving = true
		if a.path_i < a.path.size():
			return
		task["stage"] = 1
		var tgt: Vector2i = task["target"]
		var look := MP.tile_center(tgt) - a.pos
		if look.length_squared() > 1.0:
			a.facing = look.normalized()
		if task["act"] == "sleep":
			a.sleeping = true
	task["t"] = float(task["t"]) + dt * (0.7 + 0.6 * float(a.traits["dil"]))
	if task["act"] == "sleep":
		if (a.energy >= 0.98 and not world.is_night()) or a.hunger > 0.9:
			a.sleeping = false
			a.task = {}
		return
	if float(task["t"]) < float(task["dur"]):
		return
	_finish(a, s)


func _finish(a: Agent, s: Settlement) -> void:
	var task := a.task
	var t: Vector2i = task["target"]
	var now := world.time
	s.claims.erase(t)
	a.task = {}
	match str(task["act"]):
		"eat":
			if s.stock["food"] >= 1.0:
				s.stock["food"] -= 1.0
				a.hunger = maxf(0.0, a.hunger - 0.6)
				if rng.randf() < 0.2:
					a.think(now, "t_ate")
		"deliver":
			if a.carry_kind != "":
				s.stock[a.carry_kind] += a.carry_n
			a.carry_kind = ""
			a.carry_n = 0.0
		"chop":
			var o := world.tile(MP.L_OBJECT, t.x, t.y)
			if o != 0 and content.tiles[o].get("big", 0) == 1:
				world.set_tile(MP.L_OBJECT, t.x, t.y, content.tid(str(content.tiles[o].get("after", ""))))
				a.carry_kind = "wood"; a.carry_n = 3.0
				s.res["tree"].erase(t)
				if rng.randf() < 0.15:
					a.think(now, "t_work_woodcutter")
		"mine":
			if world.tile(MP.L_OBJECT, t.x, t.y) == T["rock"]:
				world.set_tile(MP.L_OBJECT, t.x, t.y, 0)
				world.schedule(t.x, t.y, MP.L_OBJECT, T["rock"], 700.0, 0)
				a.carry_kind = "stone"; a.carry_n = 3.0
				if rng.randf() < 0.15:
					a.think(now, "t_work_miner")
		"forage":
			if world.tile(MP.L_OBJECT, t.x, t.y) == T["berry_bush"]:
				world.set_tile(MP.L_OBJECT, t.x, t.y, T["berry_bush_empty"])
				a.carry_kind = "food"; a.carry_n = 3.0
				if rng.randf() < 0.15:
					a.think(now, "t_work_forager")
		"reap":
			if world.tile(MP.L_OBJECT, t.x, t.y) == T["wheat_2"]:
				world.set_tile(MP.L_OBJECT, t.x, t.y, T["wheat_0"])
				a.carry_kind = "food"; a.carry_n = 4.0
				if rng.randf() < 0.15:
					a.think(now, "t_work_farmer")
		"sow":
			if world.tile(MP.L_OBJECT, t.x, t.y) == 0 and world.tile(MP.L_GROUND, t.x, t.y) == T["farmland"]:
				world.set_tile(MP.L_OBJECT, t.x, t.y, T["wheat_0"])
		"build":
			_build_cell(a, s, task)
		"social", "play", "idle":
			_socialize(a, s)


func _occupied(t: Vector2i, except: Agent) -> bool:
	for id in agents:
		var o: Agent = agents[id]
		if o != except and MP.tile_of(o.pos) == t:
			return true
	return false


func _build_cell(a: Agent, s: Settlement, task: Dictionary) -> void:
	var b = s.building(int(task["bid"]))
	if b == null:
		return
	var idx := int(task["cell"])
	var cell: Array = b["cells"][idx]
	var t := Vector2i(b["x"] + int(cell[0]), b["y"] + int(cell[1]))
	var layer := int(cell[2])
	var id := content.tid(str(cell[3]))
	if id != 0 and content.t_solid[id] != 0 and (_occupied(t, a) or MP.tile_of(a.pos) == t):
		# somebody is standing there: try again later, never wall anyone in
		b["retry"].push_front(idx)
		s.stock["wood"] += float(cell[4])
		s.stock["stone"] += float(cell[5])
		return
	if id == 0:
		var old := world.tile(layer, t.x, t.y)
		if old != 0 and layer == MP.L_OBJECT:
			var ot: Dictionary = content.tiles[old]
			if ot.get("big", 0) == 1:
				s.stock["wood"] += 2.0
			elif old == T["rock"]:
				s.stock["stone"] += 2.0
	world.set_tile(layer, t.x, t.y, id)
	stats["tiles_placed"] += 1
	b["placed"] = int(b["placed"]) + 1
	if rng.randf() < 0.05:
		a.think(world.time, "t_work_builder")
	if int(b["placed"]) >= b["cells"].size():
		b["done"] = true
		stats["buildings"] += 1
		if b["type"] == "house" or b["type"] == "farm":
			_lay_path(s, b["door"])
		for id2 in s.members:
			if agents.has(id2) and agents[id2].job == "builder":
				agents[id2].think(world.time, "t_built", [tx(str(b["type"]))])
		_emit("built", [MP.loc(s.name), tx(str(b["type"]))], MP.tile_center(Vector2i(b["x"], b["y"])))
		s.plan_t = 0.0


func _lay_path(s: Settlement, from: Vector2i) -> void:
	var p := from
	var guard := 0
	while p != s.center and guard < 200:
		guard += 1
		if world.is_land(p.x, p.y) and world.tile(MP.L_OBJECT, p.x, p.y) == 0 and world.tile(MP.L_STRUCT, p.x, p.y) == 0:
			var g := world.tile(MP.L_GROUND, p.x, p.y)
			if content.tiles[g].get("built", 0) == 0 and g != T["farmland"]:
				world.set_tile(MP.L_STRUCT, p.x, p.y, T["path"])
				world.set_tile(MP.L_DECOR, p.x, p.y, 0)
		if absi(s.center.x - p.x) > absi(s.center.y - p.y):
			p.x += signi(s.center.x - p.x)
		else:
			p.y += signi(s.center.y - p.y)


# ====================================================================== social life
func _affinity(a: Agent, other: int) -> float:
	return float(a.rel.get(other, 0.0))


func _related(a: Agent, b: Agent) -> bool:
	if a.mother == b.id or a.father == b.id or b.mother == a.id or b.father == a.id:
		return true
	if a.mother != 0 and a.mother == b.mother:
		return true
	return a.father != 0 and a.father == b.father


func _socialize(a: Agent, s: Settlement) -> void:
	var best: Agent = null
	var best_d := 56.0 * 56.0
	for id in s.members:
		if id == a.id or not agents.has(id):
			continue
		var o: Agent = agents[id]
		if o.travelling or o.sleeping:
			continue
		var d := o.pos.distance_squared_to(a.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return
	var now := world.time
	var chem := 0.06 + 0.1 * float(a.traits["soc"]) * float(best.traits["soc"]) + rng.randf_range(-0.05, 0.08)
	if rng.randf() < 0.07:
		chem = -0.2
		a.think(now, "t_quarrel", [MP.loc(best.name)])
	elif rng.randf() < 0.3:
		a.think(now, "t_chat", [MP.loc(best.name)])
	a.rel[best.id] = clampf(_affinity(a, best.id) + chem, -1.0, 1.0)
	best.rel[a.id] = clampf(_affinity(best, a.id) + chem, -1.0, 1.0)
	a.social = maxf(0.0, a.social - 0.5)
	best.social = maxf(0.0, best.social - 0.3)
	# courtship
	if a.partner == 0 and best.partner == 0 and a.female != best.female and not _related(a, best):
		var aa := a.age(now)
		var ab := best.age(now)
		if aa >= 18.0 and ab >= 18.0 and absf(aa - ab) < 16.0 and _affinity(a, best.id) > 0.45 and _affinity(best, a.id) > 0.45:
			_pair(a, best, true)


func _pair(a: Agent, b: Agent, announce: bool) -> void:
	a.partner = b.id
	b.partner = a.id
	a.rel[b.id] = maxf(0.8, _affinity(a, b.id))
	b.rel[a.id] = maxf(0.8, _affinity(b, a.id))
	stats["pairs"] += 1
	if announce:
		a.think(world.time, "t_love", [MP.loc(b.name)])
		b.think(world.time, "t_love", [MP.loc(a.name)])
		# move in together when one of them has a home with room
		var s: Settlement = settlements[a.sid]
		for pr in [[a, b], [b, a]]:
			var has: Agent = pr[0]
			var joins: Agent = pr[1]
			if has.home >= 0 and joins.sid == has.sid:
				var hb = s.building(has.home)
				if hb != null and hb["residents"].size() < int(hb["cap"]):
					_leave_home(joins, s)
					joins.home = has.home
					hb["residents"].append(joins.id)
					break
		_emit("paired", [a.full_name(), b.full_name()], a.pos)


## Demography, once per in-game hour.
func _hourly() -> void:
	var now := world.time
	var dty := HOUR / YEAR
	var crowd := clampf(1.0 - float(agents.size()) / float(budget.max_agents), 0.0, 1.0)
	for id in agents.keys():
		var a: Agent = agents[id]
		var age: float = a.age(now)
		# mortality: Gompertz-like old age curve plus a small illness risk
		var hazard := 0.004
		if age > 55.0:
			hazard += 0.02 * exp((age - 55.0) / 8.0)
		if age < 3.0:
			hazard += 0.01
		if rng.randf() < hazard * dty:
			_die(a, "old" if age > 55.0 else "ill")
			continue
		if not a.female:
			continue
		if a.pregnant_due > 0.0:
			if now >= a.pregnant_due:
				_birth(a)
			continue
		if a.partner == 0 or not agents.has(a.partner) or age < 18.0 or age > 43.0 or a.travelling:
			continue
		var s: Settlement = settlements[a.sid]
		var p: Agent = agents[a.partner]
		if p.sid != a.sid or now - a.last_birth < 1.2 * YEAR or a.children.size() >= 6:
			continue
		var fed: bool = s.stock["food"] >= s.members.size() * 2.5 and a.hunger < 0.7
		var boost := 2.5 if agents.size() < min_population else 1.0
		if fed and rng.randf() < 0.75 * dty * crowd * boost * (1.0 if a.home >= 0 else 0.35):
			a.pregnant_due = now + 0.7 * YEAR
			a.birth_father = p.id


func _birth(m: Agent) -> void:
	var s: Settlement = settlements[m.sid]
	m.pregnant_due = -1.0
	m.last_birth = world.time
	var c := _new_agent(s, 0.0, rng.randf() < 0.5)
	var f: Agent = agents.get(m.birth_father)
	c.mother = m.id
	c.father = m.birth_father if f != null else 0
	c.clan = (f.clan if f != null else m.clan).duplicate()
	c.pos = m.pos
	c.prev_pos = m.pos
	c.hunger = 0.1
	m.children.append(c.id)
	m.think(world.time, "t_child", [MP.loc(c.name)])
	if f != null:
		f.children.append(c.id)
		f.think(world.time, "t_child", [MP.loc(c.name)])
		# inheritance with a little mutation
		for k in c.traits:
			c.traits[k] = clampf((float(m.traits[k]) + float(f.traits[k])) * 0.5 + rng.randf_range(-0.15, 0.15), 0.05, 1.0)
		c.look["skin"] = (m if rng.randf() < 0.5 else f).look["skin"]
		c.look["hair"] = (m if rng.randf() < 0.5 else f).look["hair"]
	if m.home >= 0:
		var hb = s.building(m.home)
		if hb != null:
			c.home = m.home
			hb["residents"].append(c.id)
	stats["births"] += 1
	_emit("born", [c.full_name(), MP.loc(s.name)], c.pos)
	agent_born.emit(c)


func _die(a: Agent, cause: String) -> void:
	if not a.alive:
		return
	a.alive = false
	var s: Settlement = settlements[a.sid]
	_abort(a, s)
	_leave_home(a, s)
	s.members.erase(a.id)
	agents.erase(a.id)
	stats["deaths"] += 1
	stats[cause] += 1
	for rid in [a.partner, a.mother, a.father] + a.children:
		if rid != 0 and agents.has(rid):
			var r: Agent = agents[rid]
			r.grief = 1.0
			r.think(world.time, "t_grief", [MP.loc(a.name)])
			if r.partner == a.id:
				r.partner = 0
	# a grave in the village cemetery keeps the memory in the world itself
	if s.nav != null and s.graves < 24:
		var g := s.center + Vector2i(-8 - s.graves % 6, 6 + s.graves / 6)
		if s.in_area(g) and world.is_land(g.x, g.y) and world.tile(MP.L_OBJECT, g.x, g.y) == 0 and not _occupied(g, a):
			world.set_tile(MP.L_OBJECT, g.x, g.y, T["grave"])
		s.graves += 1
	_emit({"old": "died_old", "hunger": "died_hunger", "ill": "died_ill"}[cause], [a.full_name(), int(a.age(world.time))], a.pos)
	agent_died.emit(a)


# ====================================================================== player interaction
func agent_near(pos: Vector2, radius: float = 20.0) -> Agent:
	var best: Agent = null
	var best_d := radius * radius
	for id in agents:
		var a: Agent = agents[id]
		var d := a.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = a
	return best


func job_label(a: Agent) -> String:
	var st := a.stage(world.time)
	if st != "adult":
		return tx("job_" + st)
	return tx("job_" + a.job)


## Talk to a villager: they answer from their own current situation.
func talk(id: int) -> Dictionary:
	var a: Agent = agents.get(id)
	if a == null:
		return {}
	var s: Settlement = settlements[a.sid]
	var now := world.time
	a.rel[0] = clampf(_affinity(a, 0) + 0.05, -1.0, 1.0)
	a.social = maxf(0.0, a.social - 0.3)
	if not a.sleeping and not a.travelling:
		_abort(a, s)
		a.think_t = 3.0
	var age := int(a.age(now))
	var line := tx("s_friend") if _affinity(a, 0) > 0.4 else tx("s_hello")
	if a.stage(now) == "child":
		line = tx("s_child") % age
	elif a.hunger > 0.75:
		line = tx("s_hungry")
	elif a.grief > 0.5:
		line = tx("s_grief")
	elif a.pregnant_due > 0.0 or (a.partner != 0 and agents.has(a.partner) and agents[a.partner].pregnant_due > 0.0):
		line = tx("s_preg")
	elif a.energy < 0.2:
		line = tx("s_tired")
	elif a.home < 0:
		line = tx("s_nohome")
	elif a.stage(now) == "elder":
		line = tx("s_elder") % age
	elif rng.randf() < 0.5:
		line = tx("s_town") % [MP.loc(s.name), s.members.size(), s.count_type("house", true)]
	var thoughts: Array = []
	for th in a.thoughts:
		thoughts.append(tx(str(th["k"])) % th["a"] if th["a"].size() > 0 else tx(str(th["k"])))
	var family: Array = []
	if a.partner != 0 and agents.has(a.partner):
		family.append("♥ " + agents[a.partner].full_name())
	for cid in a.children:
		if agents.has(cid):
			family.append("· " + agents[cid].full_name() + " (%d)" % int(agents[cid].age(now)))
	return {"id": a.id, "name": a.full_name(), "age": age, "female": a.female, "job": job_label(a), "mood": a.mood(),
		"hunger": a.hunger, "energy": a.energy, "settlement": MP.loc(s.name), "line": line, "thoughts": thoughts,
		"family": family, "affinity": _affinity(a, 0), "pregnant": a.pregnant_due > 0.0}


## Give food to a villager (the player's way to help a starving village).
func gift_food(id: int, amount: float = 1.0) -> bool:
	var a: Agent = agents.get(id)
	if a == null:
		return false
	a.hunger = maxf(0.0, a.hunger - 0.6 * amount)
	a.rel[0] = clampf(_affinity(a, 0) + 0.2, -1.0, 1.0)
	a.think(world.time, "t_gift")
	return true


func donate(sid: int, kind: String, amount: float) -> void:
	if settlements.has(sid) and settlements[sid].stock.has(kind):
		settlements[sid].stock[kind] += amount


# ====================================================================== persistence
func to_dict() -> Dictionary:
	var al: Array = []
	for id in agents:
		al.append(agents[id].to_dict())
	var sl: Array = []
	for sid in settlements:
		sl.append(settlements[sid].to_dict())
	return {"agents": al, "settlements": sl, "next_id": next_id, "next_sid": next_sid, "next_bid": next_bid, "stats": stats}


func from_dict(d: Dictionary) -> void:
	agents.clear()
	settlements.clear()
	for sd in d.get("settlements", []):
		var s := Settlement.from_dict(sd)
		settlements[s.id] = s
		if not s.abandoned:
			_attach(s)
	for ad in d.get("agents", []):
		var a := Agent.from_dict(ad)
		if settlements.has(a.sid):
			agents[a.id] = a
	next_id = int(d.get("next_id", 1))
	next_sid = int(d.get("next_sid", 1))
	next_bid = int(d.get("next_bid", 1))
	var st = d.get("stats", {})
	for k in stats:
		stats[k] = int(st.get(k, 0))
