extends SceneTree
## Dev tool: render a sheet of characters (styles, directions, tools) to a PNG.
##   godot --headless --path . -s tools/char_sheet.gd -- --out=/tmp/chars.png

func _initialize() -> void:
	var out := "user://chars.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var skins: Array = Society.SKINS
	var hairs: Array = Society.HAIRS
	var shirts: Array = Society.SHIRTS
	var sheet := Image.create(34 * 10, 42 * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#5fa84a"))
	var helds := ["", "axe", "pick", "hoe", "hammer", "basket", "sword", "bow", "staff", "cane"]
	for i in 10:
		var look := {"skin": skins[i % skins.size()], "hair": hairs[i % hairs.size()], "shirt": shirts[i % shirts.size()], "style": i % 4}
		var female := i % 2 == 0
		sheet.blend_rect(PixelArt.character_image(look, "down", 0, helds[i], false, female), Rect2i(0, 0, 32, 40), Vector2i(i * 34 + 1, 1))
		sheet.blend_rect(PixelArt.character_image(look, "side", 1, helds[i], false, female), Rect2i(0, 0, 32, 40), Vector2i(i * 34 + 1, 43))
		sheet.blend_rect(PixelArt.character_image(look, "up", 2, "", false, female), Rect2i(0, 0, 32, 40), Vector2i(i * 34 + 1, 85))
		sheet.blend_rect(PixelArt.character_image(look, "down", 3 if i % 2 == 0 else 1, helds[i], i >= 6, female), Rect2i(0, 0, 32, 40), Vector2i(i * 34 + 1, 127))
	sheet.resize(sheet.get_width() * 4, sheet.get_height() * 4, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("saved ", out)
	quit()
