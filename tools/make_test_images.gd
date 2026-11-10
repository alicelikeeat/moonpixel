extends SceneTree
## Dev tool: writes synthetic test pictures (no real photos are stored in the repo).
##   godot --headless --path . -s tools/make_test_images.gd -- --out=/tmp

static func portrait(skin: Color, hair: Color, shirt: Color, bg: Color) -> Image:
	var img := Image.create(240, 320, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	for y in 320:
		for x in 240:
			var dx := (x - 120) / 62.0
			var dy := (y - 120) / 78.0
			if y > 215 and absf(x - 120) < 60 + (y - 215) * 0.9:
				img.set_pixel(x, y, shirt)
			if absf(x - 120) < 22 and y > 180 and y < 222:
				img.set_pixel(x, y, skin.darkened(0.08))
			var hx := (x - 120) / 72.0
			var hy := (y - 100) / 84.0
			if hx * hx + hy * hy < 1.0 and y < 150:
				img.set_pixel(x, y, hair)
			if dx * dx + dy * dy < 1.0 and y > 70:
				img.set_pixel(x, y, skin)
	for p in [[96, 112], [144, 112]]:
		for y in range(-6, 7):
			for x in range(-9, 10):
				if x * x / 81.0 + y * y / 36.0 < 1.0:
					img.set_pixel(p[0] + x, p[1] + y, Color(0.08, 0.08, 0.1))
	for x in range(100, 141):
		for y in range(158, 164):
			img.set_pixel(x, y, Color(0.6, 0.2, 0.2))
	return img


static func teapot() -> Image:
	var img := Image.create(200, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.93, 0.93, 0.9))
	for y in 160:
		for x in 200:
			var dx := (x - 100) / 55.0
			var dy := (y - 95) / 42.0
			if dx * dx + dy * dy < 1.0:
				img.set_pixel(x, y, Color(0.75, 0.25, 0.2) if dy > -0.2 else Color(0.85, 0.35, 0.28))
			if absf(x - 100) < 14 and y > 40 and y < 56:
				img.set_pixel(x, y, Color(0.95, 0.8, 0.3))
			if x > 150 and x < 185 and absf(y - 80 - (x - 150) * -0.6) < 7:
				img.set_pixel(x, y, Color(0.7, 0.22, 0.18))
	return img


func _initialize() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	portrait(Color("#c98a62"), Color("#2b1d16"), Color("#2f9e6a"), Color("#8fb4d8")).save_png(out.path_join("portrait.png"))
	teapot().save_png(out.path_join("teapot.png"))
	print("written to ", out)
	quit()
