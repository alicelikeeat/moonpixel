extends Node
## Entry scene: asks the device for its memory, lets the player confirm or
## override the budget, then starts (or continues) the living world.

const BUDGETS := [0, 128, 256, 512, 1024, 2048, 4096]

var menu: Control
var seed_edit: LineEdit
var budget_opt: OptionButton


var boot_info := ""


## Startup diagnostics: printed (goes to user://logs/godot.log) and written to
## user://boot.log, which is reachable through the Files app on iOS.
func _boot_log() -> void:
	var c := ContentRegistry.shared()
	var vs := get_viewport().get_visible_rect().size
	boot_info = "MoonPixel %s · Godot %s · %s %s · %s · renderer %s / %s · screen %dx%d · tiles %d · content errors %d" % [
		ProjectSettings.get_setting("application/config/version", "?"), Engine.get_version_info()["string"], OS.get_name(), OS.get_version(),
		OS.get_model_name(), str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")),
		RenderingServer.get_video_adapter_name(), int(vs.x), int(vs.y), c.tile_ids.size(), c.errors.size()]
	print(boot_info)
	for e in c.errors:
		print("content error: ", e)
	var f := FileAccess.open("user://boot.log", FileAccess.WRITE)
	if f != null:
		f.store_line(Time.get_datetime_string_from_system())
		f.store_line(boot_info)
		for e in c.errors:
			f.store_line("content error: " + str(e))
		f.close()


func _ready() -> void:
	Loc.detect()
	_boot_log()
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var after := 6.0
	var speed := 1
	var with_map := false
	for a in args:
		if a.begins_with("--shot="): shot = a.substr(7)
		if a.begins_with("--after="): after = float(a.substr(8))
		if a.begins_with("--speed="): speed = int(a.substr(8))
		if a == "--map": with_map = true
	var photo := ""
	var asset := ""
	var zoom := 3
	var demo := false
	for a in args:
		if a.begins_with("--photo="): photo = a.substr(8)
		if a.begins_with("--asset="): asset = a.substr(8)
		if a.begins_with("--zoom="): zoom = int(a.substr(7))
		if a == "--demo-attack": demo = true
	for a in args:
		if a.begins_with("--autostart"):
			var view := _start(int(a.get_slice("=", 1)) if a.contains("=") else 7, 0, false)
			view.speed_i = speed
			view.cam.zoom = Vector2(zoom, zoom)
			view.demo_attack = demo
			if photo != "":
				print("photo: ", view.apply_photo(photo, 0))
			if asset != "":
				var id := view.import_asset(asset, 40)
				if id != "":
					view.world.add_prop("asset:" + id, view.player_pos + Vector2(-40, 30))
			if shot != "":
				view.capture_after(after, shot, with_map, not with_map)
			return
	_build_menu()
	for a in args:
		if a.begins_with("--menu-shot="):
			await get_tree().create_timer(1.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(12))
			get_tree().quit()


func _build_menu() -> void:
	var q := MemoryBudget.query_device()
	var auto := MemoryBudget.new().configure()
	var font := Loc.ui_font()
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	var layer := CanvasLayer.new()
	add_child(layer)
	# a coloured backdrop that does not depend on fonts: if you can see it, rendering works
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.16, 0.30)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var moon := ColorRect.new()
	moon.color = Color(0.96, 0.92, 0.70)
	moon.position = Vector2(60, 50)
	moon.size = Vector2(72, 72)
	layer.add_child(moon)
	var diag := Label.new()
	diag.text = boot_info
	diag.add_theme_font_size_override("font_size", 11)
	diag.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	diag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diag.anchor_top = 1.0; diag.anchor_bottom = 1.0; diag.anchor_right = 1.0
	diag.offset_top = -44; diag.offset_left = 12; diag.offset_right = -12
	layer.add_child(diag)
	menu = CenterContainer.new()
	menu.theme = theme
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	menu.add_child(vb)
	var title := Label.new()
	title.text = "MoonPixel"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "世界由游戏生成，但世界的未来由居民和你决定。\nA self-growing world of autonomous villagers."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var mem := Label.new()
	mem.text = ("检测到设备内存 Device memory: %d MB（可用 free %d MB）\n自动预算 Auto budget: %d MB → 区块缓存 chunk cache %d · NPC 上限 cap %d" % [
		q["physical_mb"], q["available_mb"], auto.budget_mb, auto.max_chunks, auto.max_agents]) if q["ok"] else "无法检测设备内存，请手动选择 · Could not detect device memory, please choose"
	mem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mem.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	vb.add_child(mem)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var l1 := Label.new()
	l1.text = "内存预算 Memory budget"
	row.add_child(l1)
	budget_opt = OptionButton.new()
	for b in BUDGETS:
		budget_opt.add_item("自动 Auto" if b == 0 else "%d MB" % b)
	row.add_child(budget_opt)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row2)
	var l2 := Label.new()
	l2.text = "种子 Seed"
	row2.add_child(l2)
	seed_edit = LineEdit.new()
	seed_edit.text = str(randi() % 100000)
	seed_edit.custom_minimum_size = Vector2(160, 0)
	row2.add_child(seed_edit)
	var has_save := FileAccess.file_exists(OpenWorldView.SAVE_DIR.path_join("index.json"))
	if has_save:
		var cont := Button.new()
		cont.text = "继续 Continue"
		cont.custom_minimum_size = Vector2(0, 60)
		cont.pressed.connect(func(): _start(0, BUDGETS[budget_opt.selected], true))
		vb.add_child(cont)
	var go := Button.new()
	go.text = "新世界 New world" + ("（覆盖存档 overwrites save）" if has_save else "")
	go.custom_minimum_size = Vector2(0, 60)
	go.pressed.connect(func(): _start(int(seed_edit.text) if seed_edit.text.is_valid_int() else MP.hash_str(seed_edit.text), BUDGETS[budget_opt.selected], false))
	vb.add_child(go)


func _start(seed: int, budget_mb: int, load_existing: bool) -> OpenWorldView:
	if menu != null:
		menu.get_parent().queue_free()
		menu = null
	var view := OpenWorldView.new()
	add_child(view)
	view.start(seed, budget_mb, load_existing)
	return view
