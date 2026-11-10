extends TestCase

const Maker := preload("res://tools/make_test_images.gd")


func _close(a: Color, b: Color, eps: float = 0.12) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < eps


func test_character_sprite_shows_every_body_part() -> void:
	var look := {"skin": "#e8b890", "hair": "#5a3a22", "shirt": "#3a6ac8", "pants": "#4a4a5a", "shoes": "#3a2a20"}
	var img := PixelArt.character_image(look, "down", 0, "", false, false)
	eq(img.get_size(), Vector2i(32, 40))
	ok(_close(img.get_pixel(15, 9), Color("#5a3a22")), "hair on top of the head")
	ok(_close(img.get_pixel(16, 15), Color("#e8b890")), "face skin")
	ok(_close(img.get_pixel(13, 13), Color("#20202a")), "eyes")
	ok(_close(img.get_pixel(14, 23), Color("#3a6ac8")), "torso")
	ok(_close(img.get_pixel(9, 27), Color("#e8b890")) and _close(img.get_pixel(22, 27), Color("#e8b890")), "two skin-coloured hands")
	ok(_close(img.get_pixel(13, 32), Color("#4a4a5a")), "legs")
	ok(_close(img.get_pixel(12, 37), Color("#3a2a20")) and _close(img.get_pixel(19, 37), Color("#3a2a20")), "two feet")
	ok(_close(img.get_pixel(9, 20), PixelArt.OUTLINE) or _close(img.get_pixel(7, 22), PixelArt.OUTLINE), "dark outline")


func test_held_weapons_and_magic_are_visible() -> void:
	var look := {"skin": "#e8b890", "hair": "#5a3a22", "shirt": "#3a6ac8"}
	var bare := PixelArt.character_image(look, "down", 0, "", false, false)
	for held in ["sword", "bow", "staff", "axe", "pick", "hoe", "hammer", "basket", "cane"]:
		var img := PixelArt.character_image(look, "down", 0, held, false, false)
		var extra := 0
		for y in 40:
			for x in 32:
				if img.get_pixel(x, y).a > 0.0 and bare.get_pixel(x, y).a == 0.0:
					extra += 1
		ok(extra >= 12, "%s adds visible pixels (%d)" % [held, extra])
	var staff := PixelArt.character_image(look, "down", 0, "staff", false, false)
	var glow := 0
	for y in 12:
		for x in 32:
			if _close(staff.get_pixel(x, y), Color("#59d8ff"), 0.2):
				glow += 1
	ok(glow >= 6, "staff carries a glowing orb")
	# every direction and frame renders
	for dir in ["down", "up", "side"]:
		for frame in 4:
			ok(not PixelArt.character_image(look, dir, frame, "sword", false, true).is_invisible())
	ok(not PixelArt.character_image(look, "down", 1, "", true, false).is_invisible(), "child sprite")


func test_photo_becomes_character_look() -> void:
	var skin := Color("#c98a62")
	var hair := Color("#2b1d16")
	var shirt := Color("#2f9e6a")
	var photo: Image = Maker.portrait(skin, hair, shirt, Color("#8fb4d8"))
	var out := AssetImporter.photo_to_look(photo)
	var look: Dictionary = out["look"]
	ok(_close(Color(str(look["skin"])), skin, 0.15), "skin colour from photo: " + str(look["skin"]))
	ok(_close(Color(str(look["hair"])), hair, 0.2), "hair colour from photo: " + str(look["hair"]))
	ok(_close(Color(str(look["shirt"])), shirt, 0.2), "shirt colour from photo: " + str(look["shirt"]))
	eq(out["face"].get_size(), Vector2i(10, 8))
	var fr: Rect2i = out["face_rect"]
	ok(fr.has_point(Vector2i(32, 26)), "face found around the real face: " + str(fr))
	# the pixel face is painted on the sprite head
	PixelArt.register_face("face_test", out["face"])
	look["face"] = "face_test"
	var img := PixelArt.character_image(look, "down", 0, "", false, false)
	ok(_close(img.get_pixel(15, 14), out["face"].get_pixel(4, 3), 0.02), "face pixels on the head")


func test_picture_becomes_pixel_asset() -> void:
	var pic: Image = Maker.teapot()
	var img := AssetImporter.pixelize(pic, 32, 8, true)
	ok(img.get_width() <= 32 and img.get_height() <= 32, "fits the size limit")
	eq(img.get_pixel(0, 0).a, 0.0, "background removed")
	ok(img.get_pixel(img.get_width() / 2, int(img.get_height() * 0.6)).a > 0.5, "subject kept")
	var cols := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				cols[c.to_html(false)] = true
	ok(cols.size() <= 8 and cols.size() >= 2, "palette reduced to %d colours" % cols.size())
	ok(AssetImporter.pixelize(pic, 500, 16, false).get_width() <= AssetImporter.MAX_SPRITE, "hard size cap")


func test_import_rejects_bad_files() -> void:
	ok(not AssetImporter.load_image_file("user://nope.png")["ok"])
	ok(not AssetImporter.load_image_file("user://clip.gif")["ok"], "gif is not supported yet")
	var root := fresh_root("imp")
	var f := FileAccess.open(root.path_join("broken.png"), FileAccess.WRITE)
	f.store_string("not an image")
	f.close()
	ok(not AssetImporter.load_image_file(root.path_join("broken.png"))["ok"], "corrupt file rejected")
	Maker.teapot().save_png(root.path_join("ok.png"))
	ok(AssetImporter.load_image_file(root.path_join("ok.png"))["ok"])


func test_props_persist_in_world() -> void:
	var root := fresh_root("props")
	var c := ContentRegistry.shared()
	var w := OpenWorld.new(3, c, MemoryBudget.new().configure(96))
	w.open_dir(root)
	var id := w.add_prop("asset:teapot", Vector2(-40.0, 25.0))
	w.save_all()
	var w2 := OpenWorld.new(3, c, MemoryBudget.new().configure(96))
	w2.open_dir(root)
	eq(w2.get_chunk(-1, 0).props.size(), 1)
	eq(int(w2.get_chunk(-1, 0).props[0]["id"]), id)
	ok(w2.remove_prop_near(Vector2(-38.0, 26.0)))
	eq(w2.get_chunk(-1, 0).props.size(), 0)
