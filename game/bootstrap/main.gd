extends Node
## Entry scene: asks the device for its memory, lets the player confirm or
## override the budget, then starts (or continues) the living world.

const BUDGETS := [0, 128, 256, 512, 1024, 2048, 4096]

var menu: Control
var seed_edit: LineEdit
var budget_opt: OptionButton


func _ready() -> void:
	Loc.detect()
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
	for a in args:
		if a.begins_with("--autostart"):
			var view := _start(int(a.get_slice("=", 1)) if a.contains("=") else 7, 0, false)
			view.speed_i = speed
			if shot != "":
				view.capture_after(after, shot, with_map, not with_map)
			return
	_build_menu()


func _build_menu() -> void:
	var q := MemoryBudget.query_device()
	var auto := MemoryBudget.new().configure()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans SC", "PingFang SC", "Microsoft YaHei", "WenQuanYi Micro Hei", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	var layer := CanvasLayer.new()
	add_child(layer)
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
		cont.pressed.connect(func(): _start(0, BUDGETS[budget_opt.selected], true))
		vb.add_child(cont)
	var go := Button.new()
	go.text = "新世界 New world" + ("（覆盖存档 overwrites save）" if has_save else "")
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
