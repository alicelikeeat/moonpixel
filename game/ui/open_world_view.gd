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
var panel: Glass
var lbl_agent: Label
var map_rect: Control
var font: Font
var _autosave := 0.0
var _walk_t := 0.0
var _maint := 0.0
var player_look := {"skin": "#e8b890", "hair": "#f0e8d0", "shirt": "#f4f0e0", "pants": "#5a5a78", "shoes": "#3a2a20"}
var player_facing := Vector2.DOWN
var player_moving := false
var held_i := 1                         # index into PLAYER_HELD
var attack_t := 0.0
var fx: Array = []                      # visual effects: slashes, arrows, magic
var assets: Dictionary = {}             # asset id -> ImageTexture
var placing := ""                       # asset id being placed with the mouse
var file_dialog: FileDialog
var _dialog_mode := ""
var demo_attack := false
var joy_id := -1                        # touch index driving the virtual stick
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var joy_ctl: Control
var safe: Control
var status_btn: Button
var details: Glass
var speed_glass: Glass
var speed_btns: Array = []
var tab_glass: Glass
var toast_glass: Glass
var toast_lbl: Label
var toast_t := 0.0
var auto_btn: Button
var auto_clean := true
var _clean_cd := 0.0
var _log_seen := 0
var pinch: Dictionary = {}              # touch index -> position
var pinch_d0 := 0.0
var pinch_z0 := 3.0

const PLAYER_HELD := ["", "sword", "bow", "staff"]
const JOB_TOOL := {"woodcutter": "axe", "miner": "pick", "farmer": "hoe", "builder": "hammer", "forager": "basket"}


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
		var pl = data.get("player_look")
		if pl is Dictionary:
			player_look = pl
	else:
		society.bootstrap(Vector2i.ZERO, 4, 30)
		if not society.settlements.is_empty():
			player_pos = MP.tile_center(society.settlements[1].center + Vector2i(0, 4))
	world.chunk_changed.connect(func(cx, cy): dirty_chunks[MP.chunk_key(cx, cy)] = true)
	_load_assets()
	_build_nodes()


# --- imported assets -------------------------------------------------------------
func _assets_dir() -> String:
	return SAVE_DIR.path_join("assets")


func _load_assets() -> void:
	var d := DirAccess.open(_assets_dir())
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".png"):
			continue
		var img := Image.load_from_file(_assets_dir().path_join(f))
		if img == null:
			continue
		var id := f.get_basename()
		if id.begins_with("face_"):
			PixelArt.register_face(id, img)
		else:
			assets[id] = ImageTexture.create_from_image(img)


func _new_asset_id(prefix: String) -> String:
	return "%s%d_%d" % [prefix, int(Time.get_unix_time_from_system()), randi() % 100000]


## Photo -> character. target 0 = the player, otherwise a villager id.
func apply_photo(path: String, target: int = 0) -> String:
	var res := AssetImporter.load_image_file(path)
	if not res["ok"]:
		return str(res["error"])
	var out := AssetImporter.photo_to_look(res["image"])
	var id := _new_asset_id("face_")
	DirAccess.make_dir_recursive_absolute(_assets_dir())
	out["face"].save_png(_assets_dir().path_join(id + ".png"))
	PixelArt.register_face(id, out["face"])
	var look: Dictionary = out["look"]
	look["face"] = id
	if target != 0 and society.agents.has(target):
		society.agents[target].look.merge(look, true)
	else:
		player_look.merge(look, true)
	return ""


## Any picture -> placeable pixel object. Returns the asset id ("" on failure).
func import_asset(path: String, max_side: int = 32) -> String:
	var res := AssetImporter.load_image_file(path)
	if not res["ok"]:
		society.log.append({"t": world.time, "text": "导入失败 Import failed: " + str(res["error"])})
		return ""
	var img := AssetImporter.pixelize(res["image"], max_side, 16, true)
	var id := _new_asset_id("a")
	DirAccess.make_dir_recursive_absolute(_assets_dir())
	img.save_png(_assets_dir().path_join(id + ".png"))
	assets[id] = ImageTexture.create_from_image(img)
	return id


func _open_dialog(mode: String) -> void:
	_dialog_mode = mode
	file_dialog.popup_centered_ratio(0.7)


func _on_file(path: String) -> void:
	match _dialog_mode:
		"photo_me":
			var err := apply_photo(path, 0)
			society.log.append({"t": world.time, "text": ("照片已生成角色 Character created from photo" if err == "" else "失败 Failed: " + err)})
		"photo_npc":
			var err := apply_photo(path, selected)
			society.log.append({"t": world.time, "text": ("村民外观已更新 Villager updated from photo" if err == "" else "失败 Failed: " + err)})
		"asset":
			placing = import_asset(path)
			if placing != "":
				society.log.append({"t": world.time, "text": "点击地面放置，右键取消 · Click to place, right-click to cancel"})


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
	# with the phone UI scale one unit is larger, so use a wider default view
	cam.zoom = Vector2(2, 2) if get_window().content_scale_factor > 1.2 else Vector2(3, 3)
	add_child(cam)
	cam.make_current()
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Images"])
	file_dialog.file_selected.connect(_on_file)
	font = Loc.ui_font()
	hud = CanvasLayer.new()
	add_child(hud)
	file_dialog.use_native_dialog = true
	hud.add_child(file_dialog)
	safe = Control.new()
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.theme = Glass.ui_theme()
	hud.add_child(safe)
	joy_ctl = Control.new()
	joy_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	joy_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_ctl.draw.connect(_draw_joystick)
	safe.add_child(joy_ctl)
	# --- status capsule (tap for details)
	status_btn = Glass.button("", func(): details.visible = not details.visible, 150)
	var status_glass := Glass.make(20, 4)
	status_glass.position = Vector2(0, 0)
	status_glass.add_child(status_btn)
	safe.add_child(status_glass)
	# --- details sheet
	details = Glass.make(22, 12)
	details.position = Vector2(0, 52)
	details.custom_minimum_size = Vector2(360, 0)
	var dv := VBoxContainer.new()
	details.add_child(dv)
	lbl_stats = Label.new()
	dv.add_child(lbl_stats)
	lbl_mem = Label.new()
	lbl_mem.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	lbl_mem.add_theme_font_size_override("font_size", 11)
	dv.add_child(lbl_mem)
	var auto_row := HBoxContainer.new()
	dv.add_child(auto_row)
	auto_row.add_child(Glass.button(_L("立即清理内存", "Free memory now"), func(): clean_memory(true)))
	auto_btn = Glass.button("", func(): auto_clean = not auto_clean)
	auto_row.add_child(auto_btn)
	lbl_log = Label.new()
	lbl_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_log.custom_minimum_size = Vector2(340, 0)
	lbl_log.add_theme_font_size_override("font_size", 11)
	lbl_log.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	dv.add_child(lbl_log)
	var note := Label.new()
	note.text = _L("导入图片请确保你有权使用；素材只保存在本机。", "Only import pictures you may use; they stay on this device.")
	note.add_theme_font_size_override("font_size", 9)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	dv.add_child(note)
	details.visible = false
	safe.add_child(details)
	# --- speed capsule
	speed_glass = Glass.make(20, 4)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 2)
	speed_glass.add_child(sh)
	for i in SPEEDS.size():
		var b := Glass.button("❚❚" if i == 0 else "%d×" % int(SPEEDS[i]), func(): speed_i = i, 40)
		sh.add_child(b)
		speed_btns.append(b)
	safe.add_child(speed_glass)
	# --- toast (latest life event)
	toast_glass = Glass.make(16, 8)
	toast_lbl = Label.new()
	toast_lbl.add_theme_font_size_override("font_size", 12)
	toast_glass.add_child(toast_lbl)
	toast_glass.visible = false
	toast_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(toast_glass)
	# --- floating tab bar
	tab_glass = Glass.make(26, 6)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 4)
	tab_glass.add_child(th)
	for def in [[_L("地图", "Map"), _toggle_map], [_L("村落", "Village"), _next_village], [_L("武器", "Weapon"), _cycle_held],
			[_L("照片", "Photo"), func(): _open_dialog("photo_me")], [_L("素材", "Import"), func(): _open_dialog("asset")],
			[_L("清理", "Clean"), func(): clean_memory(true)], [_L("保存", "Save"), save_game],
			["＋", func(): cam.zoom = Vector2.ONE * clampf(cam.zoom.x + 1.0, 1.0, 6.0)], ["－", func(): cam.zoom = Vector2.ONE * clampf(cam.zoom.x - 1.0, 1.0, 6.0)]]:
		th.add_child(Glass.button(def[0], def[1], 44 if def[0].length() <= 1 else 54))
	safe.add_child(tab_glass)
	# --- villager sheet
	panel = Glass.make(24, 12)
	panel.custom_minimum_size = Vector2(280, 0)
	var pv := VBoxContainer.new()
	panel.add_child(pv)
	lbl_agent = Label.new()
	lbl_agent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_agent.custom_minimum_size = Vector2(256, 0)
	lbl_agent.add_theme_font_size_override("font_size", 12)
	pv.add_child(lbl_agent)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 4)
	pv.add_child(ph)
	for def in [[_L("交谈", "Talk"), func(): _talk()], [_L("送食物", "Feed"), func(): society.gift_food(selected); _talk()],
			[_L("跟随", "Follow"), func(): follow = not follow], [_L("照片", "Photo"), func(): _open_dialog("photo_npc")],
			["✕", func(): selected = 0; follow = false]]:
		ph.add_child(Glass.button(def[0], def[1], 40))
	panel.visible = false
	safe.add_child(panel)
	map_rect = Control.new()
	map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_rect.draw.connect(_draw_map)
	map_rect.visible = false
	hud.add_child(map_rect)
	hud.move_child(map_rect, 1)
	get_viewport().size_changed.connect(_layout)
	_layout()


static func _L(zh: String, en: String) -> String:
	return zh if Loc.lang == "zh" else en


## Keeps the HUD inside the device safe area (notch, Dynamic Island, home bar).
func _layout() -> void:
	var vs := get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var sa := DisplayServer.get_display_safe_area()
	var m := Vector4(10, 8, 10, 8)        # left, top, right, bottom in UI units
	if OS.has_feature("mobile") and win.x > 0.0 and sa.size.x > 0:
		var k := vs.x / win.x
		m.x = maxf(m.x, sa.position.x * k + 6.0)
		m.y = maxf(m.y, sa.position.y * k + 4.0)
		m.z = maxf(m.z, (win.x - sa.end.x) * k + 6.0)
		m.w = maxf(m.w, (win.y - sa.end.y) * k + 4.0)
	safe.position = Vector2(m.x, m.y)
	safe.size = Vector2(vs.x - m.x - m.z, vs.y - m.y - m.w)
	_place.call_deferred()


func _place() -> void:
	var s := safe.size
	speed_glass.position = Vector2(s.x - speed_glass.size.x, 0)
	tab_glass.position = Vector2((s.x - tab_glass.size.x) * 0.5, s.y - tab_glass.size.y)
	panel.position = Vector2(s.x - panel.size.x, 52)
	toast_glass.position = Vector2((s.x - toast_glass.size.x) * 0.5, 0)


func toast(text: String) -> void:
	toast_lbl.text = text
	toast_glass.visible = true
	toast_glass.modulate.a = 1.0
	toast_t = 4.0
	toast_glass.reset_size()
	_place.call_deferred()


## One-tap memory cleanup: saves, then drops every chunk and cached texture
## that is not needed for what is on screen. Also runs automatically on an iOS
## memory warning or when the budget is nearly used up.
func clean_memory(announce: bool = false) -> Dictionary:
	var before := budget.used_mb()
	var keep := {}
	for k in chunk_nodes:
		keep[k] = true
	var dropped := world.purge(keep)
	var tex := PixelArt.clear_caches()
	fx.clear()
	if society.log.size() > 12:
		society.log = society.log.slice(-12)
	_clean_cd = 30.0
	var res := {"chunks": dropped, "textures": tex, "freed_mb": maxi(0, before - budget.used_mb()), "used_mb": budget.used_mb()}
	if announce:
		toast(_L("已清理：%d 个区块、%d 张贴图，释放约 %d MB（当前 %d MB）", "Cleaned %d chunks, %d textures, freed ~%d MB (now %d MB)") % [dropped, tex, res["freed_mb"], res["used_mb"]])
	return res


var _last_line := ""


func _talk() -> void:
	var info := society.talk(selected)
	if not info.is_empty():
		_last_line = str(info["line"])


# --- touch: virtual stick in the lower-left part of the screen ----------------------
func _in_joy_zone(p: Vector2) -> bool:
	var vs := get_viewport_rect().size
	return p.x < vs.x * 0.36 and p.y > vs.y * 0.34 and p.y < vs.y - 64.0


func _draw_joystick() -> void:
	if joy_id < 0 and not DisplayServer.is_touchscreen_available():
		return
	var vs := get_viewport_rect().size
	var base := (joy_origin if joy_id >= 0 else Vector2(safe.position.x + 70, vs.y - 130)) - safe.position
	joy_ctl.draw_circle(base, 46.0, Color(1, 1, 1, 0.10))
	joy_ctl.draw_arc(base, 46.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 1.5)
	joy_ctl.draw_circle(base + joy_vec * 32.0, 20.0, Color(1, 1, 1, 0.35))


func _cycle_held() -> void:
	held_i = (held_i + 1) % PLAYER_HELD.size()


## Player attack: visible weapon swing, arrow or magic bolt towards a point.
func attack(target: Vector2) -> void:
	if attack_t > 0.0:
		return
	var dir := (target - player_pos).normalized()
	if dir == Vector2.ZERO:
		dir = player_facing
	player_facing = dir
	attack_t = 0.3
	var origin := player_pos + Vector2(0, -14)
	match PLAYER_HELD[held_i]:
		"sword": fx.append({"k": "slash", "pos": origin, "dir": dir, "t": 0.0, "dur": 0.22})
		"bow": fx.append({"k": "arrow", "pos": origin, "dir": dir, "t": 0.0, "dur": 0.9, "speed": 300.0})
		"staff": fx.append({"k": "bolt", "pos": origin + Vector2(8, -18), "dir": (target - (origin + Vector2(8, -18))).normalized(), "t": 0.0, "dur": 1.1, "speed": 190.0, "to": target})
		_: fx.append({"k": "slash", "pos": origin, "dir": dir, "t": 0.0, "dur": 0.15})


func _update_fx(delta: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f["t"] = float(f["t"]) + delta
		if f["k"] == "arrow" or f["k"] == "bolt":
			f["pos"] = f["pos"] + f["dir"] * float(f["speed"]) * delta
			var t := MP.tile_of(f["pos"] + Vector2(0, 14))
			var hit: bool = world.blocked(t.x, t.y) and world.tile(MP.L_OBJECT, t.x, t.y) != 0
			if f["k"] == "bolt" and (hit or f["pos"].distance_to(f["to"]) < 6.0):
				fx.append({"k": "burst", "pos": f["pos"], "t": 0.0, "dur": 0.5})
				fx.remove_at(i)
				continue
			if hit:
				fx.remove_at(i)
				continue
		if float(f["t"]) >= float(f["dur"]):
			if f["k"] == "bolt":
				fx.append({"k": "burst", "pos": f["pos"], "t": 0.0, "dur": 0.5})
			fx.remove_at(i)


func _draw_fx() -> void:
	var L := agents_layer
	for f in fx:
		var k := float(f["t"]) / float(f["dur"])
		var p: Vector2 = f["pos"]
		match str(f["k"]):
			"slash":
				var a0: float = f["dir"].angle() - 1.1 + k * 0.6
				L.draw_arc(p, 20.0, a0, a0 + 1.6, 12, Color(1, 1, 1, 1.0 - k), 3.0)
				L.draw_arc(p, 16.0, a0 + 0.2, a0 + 1.4, 10, Color(0.8, 0.9, 1.0, 0.7 * (1.0 - k)), 2.0)
			"arrow":
				var d: Vector2 = f["dir"]
				L.draw_line(p - d * 9.0, p, Color("#a8703a"), 1.5)
				L.draw_line(p, p + d * 3.0, Color("#e8e8f0"), 2.0)
				L.draw_line(p - d * 9.0, p - d * 12.0, Color("#f0ece0"), 2.0)
			"bolt":
				for n in 5:
					L.draw_circle(p - f["dir"] * (n * 5.0), 4.0 - n * 0.6, Color(0.35, 0.85, 1.0, 0.8 - n * 0.15))
				L.draw_circle(p, 2.5, Color.WHITE)
			"burst":
				L.draw_arc(p, 4.0 + 22.0 * k, 0.0, TAU, 24, Color(0.45, 0.9, 1.0, 1.0 - k), 2.5)
				for n in 8:
					var ang := n * TAU / 8.0 + k * 2.0
					L.draw_rect(Rect2(p + Vector2.from_angle(ang) * (6.0 + 26.0 * k) - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 1.0 - k))


func _toggle_map() -> void:
	show_map = not show_map
	map_rect.visible = show_map


## Dev/CI helper: run for a while, save a screenshot, quit.
func capture_after(seconds: float, path: String, with_map: bool, select_someone: bool) -> void:
	await get_tree().create_timer(seconds).timeout
	if demo_attack:
		held_i = 3
		attack(player_pos + Vector2(70, -10))
		fx.append({"k": "slash", "pos": player_pos + Vector2(-30, 10), "dir": Vector2.LEFT, "t": 0.0, "dur": 5.0})
		fx.append({"k": "burst", "pos": player_pos + Vector2(60, 30), "t": 0.0, "dur": 1.6})
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
	if ev is InputEventScreenTouch:
		if ev.pressed:
			pinch[ev.index] = ev.position
		else:
			pinch.erase(ev.index)
		if pinch.size() == 2:
			var pts: Array = pinch.values()
			pinch_d0 = maxf(1.0, pts[0].distance_to(pts[1]))
			pinch_z0 = cam.zoom.x
			joy_id = -1
			joy_vec = Vector2.ZERO
		if ev.pressed and joy_id < 0 and pinch.size() == 1 and _in_joy_zone(ev.position):
			joy_id = ev.index
			joy_origin = ev.position
			joy_vec = Vector2.ZERO
		elif not ev.pressed and ev.index == joy_id:
			joy_id = -1
			joy_vec = Vector2.ZERO
		joy_ctl.queue_redraw()
		return
	if ev is InputEventScreenDrag:
		if pinch.has(ev.index):
			pinch[ev.index] = ev.position
		if pinch.size() == 2:
			var pts: Array = pinch.values()
			cam.zoom = Vector2.ONE * clampf(snappedf(pinch_z0 * pts[0].distance_to(pts[1]) / pinch_d0, 0.5), 1.0, 6.0)
			return
		if ev.index == joy_id:
			joy_vec = ((ev.position - joy_origin) / 40.0).limit_length(1.0)
			joy_ctl.queue_redraw()
		return
	if ev is InputEventMouseButton and ev.device == InputEvent.DEVICE_ID_EMULATION and (joy_id >= 0 or _in_joy_zone(ev.position)):
		return      # the emulated click of a stick touch must not attack or select
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_M:
				show_map = not show_map
				map_rect.visible = show_map
			KEY_N: _next_village()
			KEY_Q: _cycle_held()
			KEY_F5: save_game()
			KEY_SPACE: speed_i = 0 if speed_i != 0 else 1
			KEY_1, KEY_2, KEY_3, KEY_4: speed_i = ev.keycode - KEY_1 + 1
			KEY_ESCAPE:
				selected = 0
				follow = false
				placing = ""
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = Vector2.ONE * minf(6.0, cam.zoom.x + 1.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = Vector2.ONE * maxf(1.0, cam.zoom.x - 1.0)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if placing != "":
				placing = ""
			else:
				world.remove_prop_near(get_global_mouse_position())
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if placing != "":
				world.add_prop("asset:" + placing, get_global_mouse_position().round())
				return
			var a := society.agent_near(get_global_mouse_position() + Vector2(0, 14), 16.0)
			if a == null:
				if selected == 0:
					attack(get_global_mouse_position())
				selected = 0
				follow = false
				return
			selected = a.id
			follow = false
			_last_line = ""
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
	if joy_vec.length() > 0.15:
		mv += joy_vec
	player_moving = mv != Vector2.ZERO
	attack_t = maxf(0.0, attack_t - delta)
	_update_fx(delta)
	if mv != Vector2.ZERO:
		follow = false
		if attack_t <= 0.0:
			player_facing = mv.normalized()
		var sp := 90.0 * (2.4 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		var d := mv.limit_length(1.0) * sp * (1.8 if joy_vec.length() > 0.92 else 1.0) * delta
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
	if toast_t > 0.0:
		toast_t -= delta
		toast_glass.modulate.a = clampf(toast_t, 0.0, 1.0)
		if toast_t <= 0.0:
			toast_glass.visible = false
	_clean_cd = maxf(0.0, _clean_cd - delta)
	_maint += delta
	if _maint > 2.0:
		_maint = 0.0
		if auto_clean and _clean_cd <= 0.0 and budget.pressure() > 0.9:
			clean_memory(true)
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


func _char_tex(look: Dictionary, facing: Vector2, moving: bool, acting: bool, held: String, child: bool, female: bool, phase: int) -> ImageTexture:
	var frame := 0
	if acting:
		frame = 3 if phase % 2 == 0 else 0
	elif moving:
		frame = 1 + phase % 2
	return PixelArt.character(look, PixelArt.facing_dir(facing), frame, held, child, female)


func _draw_char(tex: ImageTexture, pos: Vector2, facing: Vector2) -> void:
	var p := (pos - PixelArt.CHAR_ANCHOR + Vector2(0, 4)).round()
	var flip := PixelArt.facing_dir(facing) == "side" and facing.x < 0.0
	agents_layer.draw_texture_rect(tex, Rect2(p + (Vector2(PixelArt.CHAR_W, 0) if flip else Vector2.ZERO), Vector2(-PixelArt.CHAR_W if flip else PixelArt.CHAR_W, PixelArt.CHAR_H)), false)


func _draw_agents() -> void:
	var L := agents_layer
	var half := get_viewport_rect().size / cam.zoom.x * 0.5 + Vector2(40, 56)
	var view := Rect2(player_pos - half, half * 2.0)
	var list: Array = [[player_pos.y, 0, null]]
	for id in society.agents:
		var a: Agent = society.agents[id]
		if view.has_point(a.pos):
			list.append([a.pos.y, 1, a])
	var c0 := Vector2i(floori(view.position.x / MP.CHUNK_PX), floori(view.position.y / MP.CHUNK_PX))
	var c1 := Vector2i(floori(view.end.x / MP.CHUNK_PX), floori(view.end.y / MP.CHUNK_PX))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if world.loaded(cx, cy):
				for pr in world.get_chunk(cx, cy).props:
					list.append([float(pr["y"]), 2, pr])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var now := world.time
	var phase := Time.get_ticks_msec() / 150
	for item in list:
		if item[1] == 2:
			var pr: Dictionary = item[2]
			var tex = assets.get(str(pr["key"]).trim_prefix("asset:"))
			if tex != null:
				L.draw_texture(tex, (Vector2(pr["x"], pr["y"]) - Vector2(tex.get_width() * 0.5, tex.get_height())).round())
			continue
		if item[1] == 0:
			var held: String = PLAYER_HELD[held_i]
			L.draw_arc(player_pos + Vector2(0, 2), 9.0, 0.0, TAU, 18, Color(0.5, 0.9, 1.0, 0.8), 1.0)
			_draw_char(_char_tex(player_look, player_facing, player_moving, attack_t > 0.12, held, false, false, phase), player_pos, player_facing)
			if held == "staff":
				# living magic: pulsing glow and orbiting sparks around the orb
				var side := PixelArt.facing_dir(player_facing) == "side"
				var orb := player_pos + Vector2(7.0 if not side else (2.0 if player_facing.x >= 0.0 else -2.0), -31.0)
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
				L.draw_circle(orb, 5.0 + pulse * 2.0, Color(0.35, 0.85, 1.0, 0.25))
				for n in 3:
					var ang := Time.get_ticks_msec() / 300.0 + n * TAU / 3.0
					L.draw_rect(Rect2(orb + Vector2(cos(ang) * 7.0, sin(ang) * 4.0) - Vector2(0.5, 0.5), Vector2(1, 1)), Color(0.9, 1.0, 1.0))
			continue
		var a: Agent = item[2]
		var st := a.stage(now)
		var look: Dictionary = a.look
		if a.age(now) >= 58.0 and not look.has("face"):
			look = look.duplicate()
			look["hair"] = "#d8d8e0"
		var working: bool = not a.task.is_empty() and int(a.task["stage"]) == 1 and ["chop", "mine", "build", "forage", "reap", "sow"].has(a.task["act"])
		var held: String = "cane" if st == "elder" else str(JOB_TOOL.get(a.job, ""))
		if working and a.task["act"] == "build":
			held = "hammer"
		var tex := _char_tex(look, a.facing, a.moving, working, held, st == "child", a.female, phase + a.id)
		var p := a.pos + Vector2(0, 0)
		if a.id == selected:
			L.draw_arc(a.pos + Vector2(0, 2), 9.0, 0.0, TAU, 20, Color(1, 0.95, 0.4), 1.5)
		if a.sleeping:
			L.draw_set_transform(a.pos + Vector2(14, 12), PI / 2.0)
			L.draw_texture(tex, Vector2(-16, -20))
			L.draw_set_transform(Vector2.ZERO, 0.0)
			L.draw_string(font, a.pos + Vector2(6, -4), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.9, 1.0))
			continue
		_draw_char(tex, a.pos, a.facing)
		var top := a.pos + Vector2(-8, -22 if st != "child" else -12)
		if a.carry_n > 0.0:
			var cc := {"wood": Color("#a8703a"), "stone": Color("#8a8c96"), "food": Color("#c8324a")}
			L.draw_rect(Rect2(a.pos + Vector2(-13, 6), Vector2(6, 6)), PixelArt.OUTLINE)
			L.draw_rect(Rect2(a.pos + Vector2(-12, 7), Vector2(4, 4)), cc.get(a.carry_kind, Color.WHITE))
		if a.pregnant_due > 0.0:
			L.draw_string(font, top + Vector2(12, 0), "♥", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 0.6, 0.75))
		if working:
			var k := clampf(float(a.task["t"]) / float(a.task["dur"]), 0.0, 1.0)
			L.draw_rect(Rect2(top + Vector2(0, -2), Vector2(16, 3)), Color(0, 0, 0, 0.7))
			L.draw_rect(Rect2(top + Vector2(1, -1), Vector2(14 * k, 1)), Color(0.5, 1.0, 0.5))
	_draw_fx()
	if placing != "" and assets.has(placing):
		var tex: ImageTexture = assets[placing]
		L.draw_texture(tex, (get_global_mouse_position() - Vector2(tex.get_width() * 0.5, tex.get_height())).round(), Color(1, 1, 1, 0.6))


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
	status_btn.text = _L("第 %d 年 %02d:%02d · %d 人", "Year %d %02d:%02d · %d people") % [world.year() + 1, int(h), int(fmod(h, 1.0) * 60.0), society.agents.size()]
	for i in speed_btns.size():
		speed_btns[i].modulate = Color(1, 1, 1, 1.0) if i == speed_i else Color(1, 1, 1, 0.55)
	if society.log.size() > 0 and society.log[-1]["t"] != _log_seen:
		_log_seen = society.log[-1]["t"]
		toast(str(society.log[-1]["text"]))
	if details.visible:
		lbl_stats.text = _L("出生 %d · 死亡 %d · 伴侣 %d\n村落 %d · 房屋 %d · 建筑 %d", "Births %d · Deaths %d · Couples %d\nVillages %d · Houses %d · Built %d") % [
			st["births"], st["deaths"], st["pairs"], villages, houses, st["buildings"]]
		lbl_mem.text = _L("内存：设备 %d MB · 预算 %d MB%s · 已用 %d MB\n区块：缓存 %d/%d · 生成 %d · 回收 %d · 地图 %d",
			"Memory: device %d MB · budget %d MB%s · used %d MB\nChunks: cached %d/%d · generated %d · evicted %d · mapped %d") % [
			budget.physical_mb, budget.budget_mb, _L("（手动）", " (manual)") if budget.override_mb > 0 else _L("（自动）", " (auto)"), budget.used_mb(),
			world.cache.size(), budget.max_chunks, world.generated, world.evicted, world.surveyed]
		auto_btn.text = _L("自动清理：开", "Auto clean: on") if auto_clean else _L("自动清理：关", "Auto clean: off")
		var lines: Array = []
		for e in society.log.slice(-5):
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
	txt += _L("心情 %d%% · 饥饿 %d%% · 精力 %d%%\n", "Mood %d%% · Hunger %d%% · Energy %d%%\n") % [int(a.mood() * 100), int(a.hunger * 100), int(a.energy * 100)]
	if a.partner != 0 and society.agents.has(a.partner):
		txt += "♥ %s\n" % society.agents[a.partner].full_name()
	if a.pregnant_due > 0.0:
		txt += _L("怀孕中\n", "Expecting\n")
	var kids := 0
	for cid in a.children:
		if society.agents.has(cid):
			kids += 1
	if kids > 0:
		txt += _L("子女 %d 人\n", "Children: %d\n") % kids
	if _last_line != "":
		txt += "\n「%s」\n" % _last_line
	for th in a.thoughts.slice(-3):
		txt += "\n· " + (Society.tx(str(th["k"])) % th["a"] if th["a"].size() > 0 else Society.tx(str(th["k"])))
	txt += _L("\n\n%s：粮 %d · 木 %d · 石 %d", "\n\n%s: food %d · wood %d · stone %d") % [MP.loc(s.name), int(s.stock["food"]), int(s.stock["wood"]), int(s.stock["stone"])]
	if lbl_agent.text != txt:
		lbl_agent.text = txt
		panel.reset_size()
		_place.call_deferred()


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
	var data := {"world": world.to_dict(), "society": society.to_dict(), "px": player_pos.x, "py": player_pos.y, "player_look": player_look}
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	SaveService.atomic_write(SAVE_DIR.path_join("index.json"), JSON.stringify(data).to_utf8_buffer())
	toast(_L("已保存", "Saved"))


func _notification(what: int) -> void:
	if world == null:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_game()          # iOS may kill a backgrounded app at any time
		NOTIFICATION_OS_MEMORY_WARNING:
			clean_memory(true)   # the system asked for memory back


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
