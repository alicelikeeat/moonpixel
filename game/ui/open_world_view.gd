class_name OpenWorldView
extends Node2D
## Playable view of the living world: you walk around as a traveller, watch
## the villagers run their own lives, talk to them, feed them, and see the
## map grow on its own. All game state lives in OpenWorld / Society; this node
## only renders and forwards input.

const SAVE_DIR := "user://open_world"
const SPEEDS := [0.0, 1.0, 4.0, 16.0, 64.0]

var budget: MemoryBudget
var world: OpenWorld
var society: Society
var content: ContentRegistry
var player_pos := Vector2.ZERO
var speed_i := 1
var selected := 0
var follow := false
var show_map := false
var chunk_nodes: Dictionary = {}       # chunk key -> Sprite2D
var dirty_chunks: Dictionary = {}
var cam: Camera2D
var chunk_root: Node2D
var agents_layer: Node2D
var tint: CanvasModulate
var hud: CanvasLayer
var lbl_stats: Label
var lbl_mem: Label
var lbl_log: Label
var panel: PanelContainer
var lbl_agent: Label
var map_rect: Control
var font: Font
var _autosave := 0.0
var _walk_t := 0.0
var _player_tex: Array = []
var _maint := 0.0


func start(seed: int, override_mb: int, load_existing: bool) -> void:
	content = ContentRegistry.shared()
	budget = MemoryBudget.new().configure(override_mb)
	var data = null
	if load_existing and FileAccess.file_exists(SAVE_DIR.path_join("index.json")):
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR.path_join("index.json")))
	if data is Dictionary and data.has("world"):
		seed = int(data["world"].get("seed", seed))
	else:
		data = null
		TestCaseless.wipe(SAVE_DIR)
	world = OpenWorld.new(seed, content, budget)
	world.open_dir(SAVE_DIR)
	society = Society.new(world, budget, seed)
	if data != null:
		world.from_dict(data["world"])
		society.from_dict(data["society"])
		player_pos = Vector2(float(data.get("px", 0)), float(data.get("py", 0)))
	else:
		society.bootstrap(Vector2i.ZERO, 4, 30)
		if not society.settlements.is_empty():
			player_pos = MP.tile_center(society.settlements[1].center + Vector2i(0, 4))
	world.chunk_changed.connect(func(cx, cy): dirty_chunks[MP.chunk_key(cx, cy)] = true)
	_build_nodes()


func _build_nodes() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chunk_root = Node2D.new()
	chunk_root.y_sort_enabled = true
	add_child(chunk_root)
	agents_layer = Node2D.new()
	agents_layer.draw.connect(_draw_agents)
	add_child(agents_layer)
	tint = CanvasModulate.new()
	add_child(tint)
	cam = Camera2D.new()
	cam.zoom = Vector2(3, 3)
	add_child(cam)
	cam.make_current()
	for f in 3:
		_player_tex.append(PixelArt.person("#e8b890", "#f0e8d0", "#f4f0e0", false, f, false))
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "WenQuanYi Micro Hei", "sans-serif"])
	hud = CanvasLayer.new()
	add_child(hud)
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	var top := _panel(Vector2(10, 10), theme)
	var vb := VBoxContainer.new()
	top.add_child(vb)
	lbl_stats = Label.new()
	vb.add_child(lbl_stats)
	lbl_mem = Label.new()
	lbl_mem.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	vb.add_child(lbl_mem)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	for i in SPEEDS.size():
		var b := Button.new()
		b.text = "❚❚" if i == 0 else "%d×" % int(SPEEDS[i])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): speed_i = i)
		hb.add_child(b)
	for def in [["map", _toggle_map], ["village", _next_village], ["save", save_game]]:
		var b := Button.new()
		b.text = {"map": "地图 Map (M)", "village": "下一村 Next (N)", "save": "保存 Save (F5)"}[def[0]]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(def[1])
		hb.add_child(b)
	var help := Label.new()
	help.text = "WASD 移动 Move · Shift 快跑 Run · 点击村民 Click a villager · 滚轮 Zoom"
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vb.add_child(help)
	var logp := _panel(Vector2(10, 0), theme)
	logp.anchor_top = 1.0; logp.anchor_bottom = 1.0
	logp.offset_top = -170; logp.offset_bottom = -10
	logp.custom_minimum_size = Vector2(430, 150)
	lbl_log = Label.new()
	lbl_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logp.add_child(lbl_log)
	panel = _panel(Vector2(0, 10), theme)
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.offset_left = -340; panel.offset_right = -10
	panel.custom_minimum_size = Vector2(330, 0)
	var pv := VBoxContainer.new()
	panel.add_child(pv)
	lbl_agent = Label.new()
	lbl_agent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_agent.custom_minimum_size = Vector2(310, 0)
	pv.add_child(lbl_agent)
	var ph := HBoxContainer.new()
	pv.add_child(ph)
	for def in [["交谈 Talk", func(): _talk()], ["送食物 Give food", func(): society.gift_food(selected); _talk()], ["跟随 Follow", func(): follow = not follow], ["✕", func(): selected = 0; follow = false]]:
		var b := Button.new()
		b.text = def[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(def[1])
		ph.add_child(b)
	panel.visible = false
	map_rect = Control.new()
	map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_rect.draw.connect(_draw_map)
	map_rect.visible = false
	hud.add_child(map_rect)


func _panel(pos: Vector2, theme: Theme) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme
	p.position = pos
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.72)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	hud.add_child(p)
	return p


var _last_line := ""


func _talk() -> void:
	var info := society.talk(selected)
	if not info.is_empty():
		_last_line = str(info["line"])


func _toggle_map() -> void:
	show_map = not show_map
	map_rect.visible = show_map


## Dev/CI helper: run for a while, save a screenshot, quit.
func capture_after(seconds: float, path: String, with_map: bool, select_someone: bool) -> void:
	await get_tree().create_timer(seconds).timeout
	if select_someone:
		var a := society.agent_near(player_pos, 400.0)
		if a != null:
			selected = a.id
			_talk()
	if with_map:
		_toggle_map()
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _next_village() -> void:
	var ids: Array = []
	for sid in society.settlements:
		if not society.settlements[sid].abandoned:
			ids.append(sid)
	if ids.is_empty():
		return
	var cur := MP.tile_of(player_pos)
	var best := 0
	var best_d := 1e18
	for i in ids.size():
		var d := float((society.settlements[ids[i]].center - cur).length_squared())
		if d < best_d:
			best_d = d
			best = i
	var s: Settlement = society.settlements[ids[(best + 1) % ids.size()]]
	player_pos = MP.tile_center(world.find_free_near(s.center + Vector2i(0, 4), 8))
	follow = false


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_M:
				show_map = not show_map
				map_rect.visible = show_map
			KEY_N: _next_village()
			KEY_F5: save_game()
			KEY_SPACE: speed_i = 0 if speed_i != 0 else 1
			KEY_1, KEY_2, KEY_3, KEY_4: speed_i = ev.keycode - KEY_1 + 1
			KEY_ESCAPE:
				selected = 0
				follow = false
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = Vector2.ONE * minf(6.0, cam.zoom.x + 1.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = Vector2.ONE * maxf(1.0, cam.zoom.x - 1.0)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			var a := society.agent_near(get_global_mouse_position() + Vector2(0, 6), 14.0)
			selected = a.id if a != null else 0
			follow = false
			_last_line = ""
			if a != null:
				_talk()


func _process(delta: float) -> void:
	if world == null:
		return
	# simulation (bounded work per frame; dt grows with the chosen speed)
	var sim := delta * float(SPEEDS[speed_i])
	while sim > 0.0:
		var step := minf(sim, 1.0)
		society.tick(step)
		sim -= step
	# traveller
	var mv := Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_up", &"ui_down"))
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): mv.y += 1.0
	if mv != Vector2.ZERO:
		follow = false
		var sp := 90.0 * (2.4 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var d := mv.normalized() * sp * delta
		for axis in [Vector2(d.x, 0), Vector2(0, d.y)]:
			var np: Vector2 = player_pos + axis
			var t := MP.tile_of(np)
			if not world.blocked(t.x, t.y):
				player_pos = np
		_walk_t += delta * 8.0
	if follow and society.agents.has(selected):
		player_pos = society.agents[selected].pos
	cam.position = player_pos.round()
	var dl := world.daylight()
	tint.color = Color(0.36, 0.42, 0.68).lerp(Color.WHITE, dl)
	_update_chunks()
	agents_layer.queue_redraw()
	_update_hud()
	if show_map:
		map_rect.queue_redraw()
	_maint += delta
	if _maint > 2.0:
		_maint = 0.0
		world.survey(Vector2i(floori(player_pos.x / MP.CHUNK_PX), floori(player_pos.y / MP.CHUNK_PX)), 16)
		world.maintain()
	_autosave += delta
	if _autosave > 120.0:
		save_game()


func _update_chunks() -> void:
	var half := get_viewport_rect().size / cam.zoom.x * 0.5
	var c0 := Vector2i(floori((player_pos.x - half.x) / MP.CHUNK_PX) - 1, floori((player_pos.y - half.y) / MP.CHUNK_PX) - 1)
	var c1 := Vector2i(floori((player_pos.x + half.x) / MP.CHUNK_PX) + 1, floori((player_pos.y + half.y) / MP.CHUNK_PX) + 1)
	var made := 0
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var k := MP.chunk_key(cx, cy)
			var need := not chunk_nodes.has(k) or dirty_chunks.has(k)
			if not need or made >= 2:
				continue
			made += 1
			dirty_chunks.erase(k)
			var tex := ImageTexture.create_from_image(PixelArt.bake_chunk(world.get_chunk(cx, cy), content))
			var sp: Sprite2D = chunk_nodes.get(k)
			if sp == null:
				sp = Sprite2D.new()
				sp.centered = false
				sp.position = Vector2(cx * MP.CHUNK_PX, cy * MP.CHUNK_PX + MP.CHUNK_PX)
				sp.offset = Vector2(-8, -24 - MP.CHUNK_PX)
				chunk_root.add_child(sp)
				chunk_nodes[k] = sp
			sp.texture = tex
	for k in chunk_nodes.keys():
		var cx := MP.key_cx(k)
		var cy := MP.key_cy(k)
		if cx < c0.x - 1 or cy < c0.y - 1 or cx > c1.x + 1 or cy > c1.y + 1:
			chunk_nodes[k].queue_free()
			chunk_nodes.erase(k)
	for k in dirty_chunks.keys():
		if not chunk_nodes.has(k):
			dirty_chunks.erase(k)


func _draw_agents() -> void:
	var half := get_viewport_rect().size / cam.zoom.x * 0.5 + Vector2(24, 32)
	var view := Rect2(player_pos - half, half * 2.0)
	var list: Array = []
	for id in society.agents:
		var a: Agent = society.agents[id]
		if view.has_point(a.pos):
			list.append(a)
	list.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	var now := world.time
	var t := Time.get_ticks_msec() / 130
	var drew_player := false
	for a: Agent in list:
		if not drew_player and a.pos.y > player_pos.y:
			_draw_player()
			drew_player = true
		var child: bool = a.stage(now) == "child"
		var frame := (1 + (t + a.id) % 2) if a.moving else 0
		var tex := PixelArt.person(a.look["skin"], a.look["hair"] if a.age(now) < 58.0 else "#d8d8e0", a.look["shirt"], child, frame, a.female)
		var p := (a.pos - Vector2(8, 18)).round()
		if a.id == selected:
			agents_layer.draw_arc(a.pos + Vector2(0, 1), 8.0, 0.0, TAU, 20, Color(1, 0.95, 0.4), 1.0)
		if a.sleeping:
			agents_layer.draw_set_transform(a.pos + Vector2(8, 0), PI / 2.0)
			agents_layer.draw_texture(tex, Vector2(-8, -8))
			agents_layer.draw_set_transform(Vector2.ZERO, 0.0)
			agents_layer.draw_string(font, a.pos + Vector2(4, -8), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.8, 0.9, 1.0))
			continue
		agents_layer.draw_texture_rect(tex, Rect2(p, Vector2(16, 20)), false, Color.WHITE)
		if a.facing.x < -0.3:
			pass
		if a.carry_n > 0.0:
			var cc := {"wood": Color("#a8703a"), "stone": Color("#8a8c96"), "food": Color("#c8324a")}
			agents_layer.draw_rect(Rect2(p + Vector2(11, 8), Vector2(5, 5)), cc.get(a.carry_kind, Color.WHITE))
		if a.pregnant_due > 0.0:
			agents_layer.draw_rect(Rect2(p + Vector2(6, 11), Vector2(4, 3)), Color(1, 0.7, 0.8))
		if not a.task.is_empty() and int(a.task["stage"]) == 1 and ["chop", "mine", "build", "forage", "reap", "sow"].has(a.task["act"]):
			var k := float(a.task["t"]) / float(a.task["dur"])
			agents_layer.draw_rect(Rect2(p + Vector2(2, -3), Vector2(12, 2)), Color(0, 0, 0, 0.6))
			agents_layer.draw_rect(Rect2(p + Vector2(2, -3), Vector2(12 * k, 2)), Color(0.5, 1.0, 0.5))
	if not drew_player:
		_draw_player()


func _draw_player() -> void:
	var frame := 1 + int(_walk_t) % 2 if Input.is_anything_pressed() else 0
	agents_layer.draw_texture(_player_tex[frame], (player_pos - Vector2(8, 18)).round())
	agents_layer.draw_arc(player_pos + Vector2(0, 1), 7.0, 0.0, TAU, 16, Color(0.5, 0.9, 1.0, 0.8), 1.0)


func _update_hud() -> void:
	var st := society.stats
	var villages := 0
	var houses := 0
	for sid in society.settlements:
		var s: Settlement = society.settlements[sid]
		if not s.abandoned:
			villages += 1
			houses += s.count_type("house", true)
	var h := world.hour()
	lbl_stats.text = "第 %d 年 Year %d · %02d:%02d\n人口 Pop %d · 出生 Births %d · 死亡 Deaths %d · 伴侣 Couples %d\n村落 Villages %d · 房屋 Houses %d · 建筑 Built %d" % [
		world.year() + 1, world.year() + 1, int(h), int(fmod(h, 1.0) * 60.0), society.agents.size(), st["births"], st["deaths"], st["pairs"], villages, houses, st["buildings"]]
	lbl_mem.text = "内存 Memory: 设备 device %d MB · 预算 budget %d MB%s · 已用 used %d MB\n区块 Chunks: 缓存 cached %d/%d · 生成 generated %d · 回收 evicted %d · 地图 mapped %d" % [
		budget.physical_mb, budget.budget_mb, " (手动 manual)" if budget.override_mb > 0 else " (自动 auto)", budget.used_mb(),
		world.cache.size(), budget.max_chunks, world.generated, world.evicted, world.surveyed]
	var lines: Array = []
	for e in society.log.slice(-6):
		lines.append("· " + str(e["text"]))
	lbl_log.text = "\n".join(lines)
	var a: Agent = society.agents.get(selected)
	panel.visible = a != null
	if a == null:
		if selected != 0:
			selected = 0
		return
	var s: Settlement = society.settlements[a.sid]
	var now := world.time
	var txt := "%s  %s %d\n%s · %s\n" % [a.full_name(), "♀" if a.female else "♂", int(a.age(now)), MP.loc(s.name), society.job_label(a)]
	txt += "心情 Mood %d%% · 饥饿 Hunger %d%% · 精力 Energy %d%%\n" % [int(a.mood() * 100), int(a.hunger * 100), int(a.energy * 100)]
	if a.partner != 0 and society.agents.has(a.partner):
		txt += "♥ %s\n" % society.agents[a.partner].full_name()
	if a.pregnant_due > 0.0:
		txt += "怀孕中 Expecting\n"
	var kids := 0
	for cid in a.children:
		if society.agents.has(cid):
			kids += 1
	if kids > 0:
		txt += "子女 Children: %d\n" % kids
	if _last_line != "":
		txt += "\n「%s」\n" % _last_line
	for th in a.thoughts.slice(-3):
		txt += "\n· " + (Society.tx(str(th["k"])) % th["a"] if th["a"].size() > 0 else Society.tx(str(th["k"])))
	txt += "\n\n%s: 粮 food %d · 木 wood %d · 石 stone %d" % [MP.loc(s.name), int(s.stock["food"]), int(s.stock["wood"]), int(s.stock["stone"])]
	lbl_agent.text = txt


func _draw_map() -> void:
	var size := map_rect.size
	map_rect.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.92))
	var pc := Vector2(player_pos.x / MP.CHUNK_PX, player_pos.y / MP.CHUNK_PX)
	# fit everything that has been surveyed
	var ext := 8.0
	for rk in world.regions:
		ext = maxf(ext, maxf(absf((rk.x + 0.5) * OpenWorld.REGION - pc.x), absf((rk.y + 0.5) * OpenWorld.REGION - pc.y)) + OpenWorld.REGION * 0.5)
	var scale := minf(size.x, size.y) * 0.5 / ext
	scale = clampf(scale, 0.5, 6.0)
	var mid := size * 0.5
	var cols: Array = []
	for b in content.biomes:
		cols.append(Color(str(b["color"])))
	for rk in world.regions:
		var r: PackedByteArray = world.regions[rk]
		for i in r.size():
			if r[i] == 0:
				continue
			var cx: int = rk.x * OpenWorld.REGION + i % OpenWorld.REGION
			var cy: int = rk.y * OpenWorld.REGION + i / OpenWorld.REGION
			var p := mid + (Vector2(cx, cy) - pc) * scale
			if p.x < -scale or p.y < -scale or p.x > size.x or p.y > size.y:
				continue
			map_rect.draw_rect(Rect2(p, Vector2(scale, scale) + Vector2(0.5, 0.5)), cols[r[i] - 1])
	for sid in society.settlements:
		var s: Settlement = society.settlements[sid]
		var p := mid + (Vector2(s.center) / MP.CHUNK - pc) * scale
		map_rect.draw_circle(p, 5.0, Color(0.3, 0.3, 0.3) if s.abandoned else Color(1.0, 0.85, 0.3))
		map_rect.draw_string(font, p + Vector2(8, 5), "%s (%d)" % [MP.loc(s.name), s.members.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	map_rect.draw_circle(mid, 4.0, Color(0.5, 0.9, 1.0))
	map_rect.draw_string(font, Vector2(20, size.y - 20), "已探明 %d 区块 · 地图随村民扩张自动生长  |  %d chunks mapped · the map grows as villagers spread" % [world.surveyed, world.surveyed],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.8))


func save_game() -> void:
	_autosave = 0.0
	world.save_all()
	var data := {"world": world.to_dict(), "society": society.to_dict(), "px": player_pos.x, "py": player_pos.y}
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	SaveService.atomic_write(SAVE_DIR.path_join("index.json"), JSON.stringify(data).to_utf8_buffer())
	society.log.append({"t": world.time, "text": "已保存 Saved"})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and world != null:
		save_game()


class TestCaseless:
	static func wipe(path: String) -> void:
		var d := DirAccess.open(path)
		if d == null:
			return
		for f in d.get_files():
			d.remove(f)
		for sub in d.get_directories():
			wipe(path.path_join(sub))
			d.remove(sub)
