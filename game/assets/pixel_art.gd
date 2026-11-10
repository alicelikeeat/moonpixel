class_name PixelArt
extends RefCounted
## Procedural pixel art: every tile and character sprite is drawn by code from
## the colour descriptors in the content files. No binary art assets, so the
## whole project stays MIT-licensable and tiny.

const CELL := 32      # atlas cell; ground tiles use the top-left 16x16

static var _atlas: Image = null
static var _people: Dictionary = {}


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


static func _disc(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for yy in range(int(cy - r), int(cy + r) + 1):
		for xx in range(int(cx - r), int(cx + r) + 1):
			if (xx + 0.5 - cx) * (xx + 0.5 - cx) + (yy + 0.5 - cy) * (yy + 0.5 - cy) <= r * r:
				_px(img, xx, yy, c)


static func _speck(img: Image, ox: int, oy: int, w: int, h: int, c: Color, salt: int, density: float) -> void:
	for y in h:
		for x in w:
			if MP.h01(salt, x, y) < density:
				_px(img, ox + x, oy + y, c)


static func atlas(content: ContentRegistry) -> Image:
	if _atlas != null:
		return _atlas
	var img := Image.create(16 * CELL, 16 * CELL, false, Image.FORMAT_RGBA8)
	for t in content.tiles:
		if t != null:
			_draw_tile(img, (int(t["id"]) % 16) * CELL, (int(t["id"]) / 16) * CELL, t)
	_atlas = img
	return img


static func cell_rect(id: int) -> Rect2i:
	return Rect2i((id % 16) * CELL, (id / 16) * CELL, CELL, CELL)


static func _draw_tile(img: Image, ox: int, oy: int, t: Dictionary) -> void:
	var art: Array = t["art"]
	var kind := str(art[0])
	var c1 := Color(str(art[1]))
	var c2 := Color(str(art[2])) if art.size() > 2 and art[2] is String and str(art[2]).begins_with("#") else c1.darkened(0.2)
	var c3 := Color(str(art[3])) if art.size() > 3 and art[3] is String and str(art[3]).begins_with("#") else c1.lightened(0.2)
	var salt := int(t["id"]) * 31
	var layer := int(t["layer"])
	if layer == MP.L_GROUND or (layer == MP.L_STRUCT and kind != "cliff"):
		_rect(img, ox, oy, 16, 16, c1)
		match kind:
			"grass":
				_speck(img, ox, oy, 16, 16, c2, salt, 0.14)
				_speck(img, ox, oy, 16, 16, c3, salt + 1, 0.07)
			"water":
				for y in [3, 9, 13]:
					_rect(img, ox + (y * 5) % 9, oy + y, 5, 1, c2)
			"planks":
				for y in [0, 4, 8, 12]:
					_rect(img, ox, oy + y, 16, 1, c2)
				for y in 4:
					_px(img, ox + (y * 7 + 3) % 16, oy + y * 4 + 2, c2)
			"bricks", "cobble":
				for y in [0, 5, 10, 15]:
					_rect(img, ox, oy + y, 16, 1, c2)
				for r in 3:
					for x in [2 + r * 4, 10 + r * 3]:
						_rect(img, ox + x % 16, oy + r * 5 + 1, 1, 4, c2)
			"rows":
				for y in [2, 6, 10, 14]:
					_rect(img, ox, oy + y, 16, 2, c2)
			"bridge":
				for x in [0, 5, 10, 15]:
					_rect(img, ox + x, oy, 1, 16, c2)
				_rect(img, ox, oy, 16, 1, c2.darkened(0.2))
				_rect(img, ox, oy + 15, 16, 1, c2.darkened(0.2))
			"ice":
				_speck(img, ox, oy, 16, 16, c2, salt, 0.08)
				_rect(img, ox + 3, oy + 5, 6, 1, Color.WHITE)
			_:
				_speck(img, ox, oy, 16, 16, c2, salt, 0.16)
		return
	# objects are anchored bottom-centre in a 32x32 cell: tile occupies x 8..23, y 16..31
	var bx := ox + 8
	var by := oy + 16
	match kind:
		"cliff":
			_rect(img, bx, by - 8, 16, 24, c2)
			_rect(img, bx, by - 8, 16, 10, c1)
			_speck(img, bx, by - 8, 16, 10, c3, salt, 0.12)
			_speck(img, bx, by + 2, 16, 14, c2.darkened(0.2), salt + 2, 0.2)
		"tree":
			_rect(img, bx + 6, by + 6, 4, 9, c3)
			_disc(img, bx + 8, by - 2, 10.0, c2)
			_disc(img, bx + 7, by - 4, 8.0, c1)
			_disc(img, bx + 4, by - 6, 3.0, c1.lightened(0.18))
		"pine":
			_rect(img, bx + 7, by + 9, 3, 6, c3)
			for i in 3:
				var w := 6 + i * 4
				for r in 7:
					var ww := int(w * (r + 1) / 7.0)
					_rect(img, bx + 8 - ww / 2, by - 12 + i * 7 + r, ww, 1, c1 if r < 5 else c2)
			_rect(img, bx + 7, by - 13, 2, 2, c2 if c2.get_luminance() > 0.7 else c1.lightened(0.2))
		"deadtree":
			_rect(img, bx + 7, by - 2, 3, 17, c1)
			_rect(img, bx + 3, by + 2, 5, 2, c2)
			_rect(img, bx + 9, by - 1, 5, 2, c2)
		"cactus":
			_rect(img, bx + 6, by + 1, 4, 14, c1)
			_rect(img, bx + 2, by + 5, 3, 5, c2); _rect(img, bx + 2, by + 9, 5, 2, c2)
			_rect(img, bx + 11, by + 3, 3, 5, c2); _rect(img, bx + 9, by + 7, 5, 2, c2)
		"bush", "berrybush":
			_disc(img, bx + 8, by + 10, 6.0, c2)
			_disc(img, bx + 7, by + 9, 5.0, c1)
			if kind == "berrybush":
				for p in [[5, 8], [9, 7], [8, 11], [11, 10]]:
					_rect(img, bx + p[0], by + p[1], 2, 2, c3)
		"rock", "ore":
			_disc(img, bx + 8, by + 10, 6.0, c2)
			_disc(img, bx + 7, by + 9, 5.0, c1)
			_rect(img, bx + 4, by + 6, 3, 1, c1.lightened(0.25))
			if kind == "ore":
				for p in [[5, 9], [9, 7], [8, 11]]:
					_rect(img, bx + p[0], by + p[1], 2, 2, c3)
		"wall":
			_rect(img, bx, by - 6, 16, 22, c2)
			_rect(img, bx, by - 6, 16, 8, c1.lightened(0.12))
			for y in [4, 9, 14]:
				_rect(img, bx, by + y, 16, 1, c2.darkened(0.25))
			_rect(img, bx, by + 15, 16, 1, c2.darkened(0.4))
		"door":
			_rect(img, bx + 2, by - 4, 12, 20, c2)
			_rect(img, bx + 3, by - 3, 10, 19, c1)
			_rect(img, bx + 11, by + 6, 2, 2, Color("#e8c84a"))
		"fence", "gate":
			_rect(img, bx, by + 6, 16, 2, c1); _rect(img, bx, by + 11, 16, 2, c1)
			for x in [1, 7, 13]:
				_rect(img, bx + x, by + 3, 2, 12, c2)
		"crop":
			var st := int(art[3])
			for x in [2, 7, 12]:
				_rect(img, bx + x, by + 13 - st * 4, 2, 3 + st * 4, c1)
				if st == 2:
					_rect(img, bx + x - 1, by + 4, 4, 3, c1.lightened(0.15))
		"sapling":
			_rect(img, bx + 7, by + 9, 2, 6, c2)
			_disc(img, bx + 8, by + 7, 3.5, c1)
		"flower":
			_rect(img, bx + 7, by + 9, 1, 5, c2)
			_rect(img, bx + 6, by + 6, 3, 3, c1); _px(img, bx + 7, by + 7, Color("#fff7cf"))
		"tuft", "leaves":
			for p in [[3, 10], [6, 8], [9, 11], [12, 9], [7, 12]]:
				_rect(img, bx + p[0], by + p[1], 1, 4, c1 if p[0] % 2 == 0 else c2)
		"mushroom":
			_rect(img, bx + 7, by + 10, 2, 4, c2); _rect(img, bx + 5, by + 8, 6, 3, c1)
		"pebbles", "shell", "bones":
			for p in [[4, 11], [9, 9], [11, 13]]:
				_rect(img, bx + p[0], by + p[1], 3, 2, c1 if p[0] != 9 else c2)
		"lily":
			_disc(img, bx + 8, by + 9, 4.0, c1); _rect(img, bx + 8, by + 8, 2, 2, c2)
		"campfire", "campfire_out":
			_rect(img, bx + 3, by + 11, 10, 3, c1)
			_rect(img, bx + 2, by + 13, 12, 2, Color("#6e7079"))
			if kind == "campfire":
				_disc(img, bx + 8, by + 8, 4.0, c2); _disc(img, bx + 8, by + 9, 2.2, c3)
		"bed":
			_rect(img, bx + 1, by + 2, 14, 13, c3); _rect(img, bx + 2, by + 6, 12, 8, c1); _rect(img, bx + 3, by + 3, 10, 3, c2)
		"chest":
			_rect(img, bx + 2, by + 5, 12, 10, c2); _rect(img, bx + 2, by + 5, 12, 4, c1); _rect(img, bx + 7, by + 8, 2, 3, c3)
		"well", "well_broken":
			_disc(img, bx + 8, by + 9, 7.0, c2); _disc(img, bx + 8, by + 9, 5.0, c1)
			_disc(img, bx + 8, by + 9, 3.0, c3 if kind == "well" else Color("#2a2a2a"))
		"lantern", "moonlantern", "torch":
			_rect(img, bx + 7, by - 2, 2, 17, c1); _rect(img, bx + 5, by - 6, 6, 5, c2)
		"grave":
			_rect(img, bx + 4, by + 4, 8, 11, c1); _rect(img, bx + 5, by + 2, 6, 2, c1)
			_rect(img, bx + 7, by + 6, 2, 5, c2); _rect(img, bx + 6, by + 7, 4, 1, c2)
		"star":
			_disc(img, bx + 8, by + 9, 4.0, c1); _disc(img, bx + 8, by + 9, 2.0, c2)
		_:
			# generic furniture box
			_rect(img, bx + 2, by + 3, 12, 12, c2)
			_rect(img, bx + 2, by + 3, 12, 5, c1)
			_rect(img, bx + 4, by + 10, 8, 1, c3)


## Bakes one chunk into an image: ground, structures, decor, then objects row
## by row (tall sprites overlap upwards). 24 px headroom at the top.
static func bake_chunk(c: ChunkData, content: ContentRegistry) -> Image:
	var at := atlas(content)
	var px := MP.CHUNK_PX
	var img := Image.create(px + 16, px + 24, false, Image.FORMAT_RGBA8)
	var g: PackedByteArray = c.layers[0]
	var st: PackedByteArray = c.layers[1]
	var ob: PackedByteArray = c.layers[2]
	var de: PackedByteArray = c.layers[3]
	var cliff := content.tid("cliff")
	for i in MP.CHUNK_AREA:
		var x := (i % MP.CHUNK) * 16 + 8
		var y := (i / MP.CHUNK) * 16 + 24
		img.blit_rect(at, Rect2i((g[i] % 16) * CELL, (g[i] / 16) * CELL, 16, 16), Vector2i(x, y))
		if st[i] != 0 and st[i] != cliff:
			img.blit_rect(at, Rect2i((st[i] % 16) * CELL, (st[i] / 16) * CELL, 16, 16), Vector2i(x, y))
	for i in MP.CHUNK_AREA:
		var x := (i % MP.CHUNK) * 16
		var y := (i / MP.CHUNK) * 16 + 8
		if de[i] != 0:
			img.blend_rect(at, cell_rect(de[i]), Vector2i(x, y))
		if st[i] == cliff:
			img.blend_rect(at, cell_rect(cliff), Vector2i(x, y))
		if ob[i] != 0:
			img.blend_rect(at, cell_rect(ob[i]), Vector2i(x, y))
	return img


# ---------------------------------------------------------------- characters
## Characters are drawn on a 32x40 canvas (feet at y 38, centred on x 16) so
## that every part reads clearly at game zoom: head with hair and eyes, two
## arms ending in skin-coloured hands, torso, legs, shoes, and whatever is
## held (weapon, tool, magic staff). A dark outline separates them from terrain.
const CHAR_W := 32
const CHAR_H := 40
const CHAR_ANCHOR := Vector2(16, 38)
const OUTLINE := Color("#1a1a26")
const HELD := ["", "sword", "bow", "staff", "axe", "pick", "hoe", "hammer", "basket", "cane"]

static var _chars: Dictionary = {}
static var _faces: Dictionary = {}     # face id -> Image (10x8), from imported photos


static func register_face(id: String, img: Image) -> void:
	_faces[id] = img
	for k in _chars.keys():
		if str(k).contains(id):
			_chars.erase(k)


static func _held(img: Image, kind: String, hx: int, hy: int) -> void:
	var wood := Color("#8a5a30")
	var steel := Color("#d0d4e0")
	var dark := Color("#8f93a6")
	match kind:
		"sword":
			for i in 13:
				_rect(img, hx + i / 4, hy - 3 - i, 2, 1, steel)
				_px(img, hx + i / 4, hy - 3 - i, Color.WHITE)
			_rect(img, hx - 2, hy - 2, 6, 1, Color("#e8c84a"))
			_rect(img, hx, hy - 1, 2, 3, wood)
		"axe", "hammer", "pick", "hoe":
			_rect(img, hx, hy - 12, 2, 15, wood)
			if kind == "axe":
				_rect(img, hx + 2, hy - 13, 4, 6, steel); _rect(img, hx + 5, hy - 12, 1, 4, Color.WHITE)
			elif kind == "hammer":
				_rect(img, hx - 2, hy - 15, 6, 4, dark); _rect(img, hx - 2, hy - 15, 6, 1, steel)
			elif kind == "pick":
				_rect(img, hx - 4, hy - 13, 10, 2, steel); _px(img, hx - 5, hy - 12, steel); _px(img, hx + 6, hy - 12, steel)
			else:
				_rect(img, hx + 2, hy - 13, 4, 2, steel); _rect(img, hx + 5, hy - 12, 1, 3, steel)
		"bow":
			for i in 15:
				var bend := int(round(4.0 * sin(PI * i / 14.0)))
				_rect(img, hx + bend, hy - 9 + i, 2, 1, wood)
				_px(img, hx - 1, hy - 9 + i, Color("#f0ece0"))
		"staff":
			_rect(img, hx, hy - 20, 2, 26, wood)
			_rect(img, hx - 1, hy - 25, 4, 5, Color("#59d8ff"))
			_rect(img, hx, hy - 24, 2, 3, Color.WHITE)
			for p in [[-3, -27], [4, -26], [-3, -21], [5, -22]]:
				_px(img, hx + p[0], hy + p[1], Color("#bff2ff"))
		"cane":
			_rect(img, hx, hy - 2, 1, 12, wood); _rect(img, hx, hy - 3, 3, 1, wood)
		"basket":
			_rect(img, hx - 2, hy + 2, 7, 5, Color("#b08050")); _rect(img, hx - 2, hy + 2, 7, 1, Color("#80582f"))
			_rect(img, hx - 1, hy + 1, 2, 1, Color("#c8324a")); _rect(img, hx + 2, hy + 1, 2, 1, Color("#c8324a"))


static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var marks: Array = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			if (x > 0 and img.get_pixel(x - 1, y).a > 0.0) or (x < w - 1 and img.get_pixel(x + 1, y).a > 0.0) \
					or (y > 0 and img.get_pixel(x, y - 1).a > 0.0) or (y < h - 1 and img.get_pixel(x, y + 1).a > 0.0):
				marks.append(Vector2i(x, y))
	for m in marks:
		img.set_pixel(m.x, m.y, OUTLINE)


## look: {skin, hair, shirt, pants?, shoes?, face?}; dir: "down" | "up" | "side";
## frame: 0 stand, 1/2 walk, 3 = acting (arm and tool raised); held: see HELD.
static func character_image(look: Dictionary, dir: String, frame: int, held: String, child: bool, female: bool) -> Image:
	var img := Image.create(CHAR_W, CHAR_H, false, Image.FORMAT_RGBA8)
	var sk := Color(str(look.get("skin", "#e8b890")))
	var hr := Color(str(look.get("hair", "#5a3a22")))
	var sh := Color(str(look.get("shirt", "#3a6ac8")))
	var pa := Color(str(look.get("pants", "#4a4a5a")))
	var so := Color(str(look.get("shoes", "#3a2a20")))
	var eye := Color("#20202a")
	var l_up := 2 if frame == 1 else 0       # left leg lifted
	var r_up := 2 if frame == 2 else 0
	var act := frame == 3
	if dir == "side":
		# legs + shoes (stride)
		var spread := 2 if frame == 1 else (-2 if frame == 2 else 0)
		_rect(img, 12 - spread, 29, 4, 7, pa.darkened(0.15)); _rect(img, 12 - spread, 36, 5, 3, so)
		_rect(img, 16 + spread, 29, 4, 7, pa); _rect(img, 16 + spread, 36, 5, 3, so)
		# torso
		_rect(img, 12, 19, 8, 10, sh); _rect(img, 12, 19, 2, 10, sh.darkened(0.18)); _rect(img, 12, 28, 8, 1, sh.darkened(0.3))
		# head
		_rect(img, 11, 8, 10, 11, sk)
		_rect(img, 11, 8, 10, 3, hr); _rect(img, 11, 11, 4, 5 if not female else 9, hr)
		_rect(img, 18, 13, 1, 2, eye); _px(img, 21, 15, sk); _px(img, 19, 17, sk.darkened(0.25))
		# front arm + hand
		if act:
			_rect(img, 16, 16, 6, 3, sh.lightened(0.08)); _rect(img, 22, 15, 3, 3, sk)
			_held(img, held, 23, 15)
		else:
			var sw := 1 if frame == 1 else (-1 if frame == 2 else 0)
			_rect(img, 15 + sw, 19, 3, 7, sh.lightened(0.08)); _rect(img, 15 + sw, 26, 3, 3, sk)
			_held(img, held, 17 + sw, 26)
	else:
		var back := dir == "up"
		# legs + shoes
		_rect(img, 11, 29, 5, 7 - l_up, pa); _rect(img, 10, 36 - l_up, 6, 3, so)
		_rect(img, 16, 29, 5, 7 - r_up, pa.darkened(0.12)); _rect(img, 16, 36 - r_up, 6, 3, so)
		# torso
		_rect(img, 11, 19, 10, 10, sh); _rect(img, 19, 19, 2, 10, sh.darkened(0.18)); _rect(img, 11, 28, 10, 1, sh.darkened(0.3))
		if not back:
			_rect(img, 15, 19, 2, 2, sk)
		# head
		_rect(img, 10, 9, 12, 10, sk); _rect(img, 11, 8, 10, 1, sk)
		if back:
			_rect(img, 10, 8, 12, 9 if not female else 13, hr)
		else:
			_rect(img, 10, 8, 12, 3, hr); _rect(img, 11, 7, 10, 1, hr)
			_rect(img, 10, 11, 1, 3 if not female else 9, hr); _rect(img, 21, 11, 1, 3 if not female else 9, hr)
			var fid := str(look.get("face", ""))
			if fid != "" and _faces.has(fid):
				img.blit_rect(_faces[fid], Rect2i(0, 0, 10, 8), Vector2i(11, 11))
			else:
				_rect(img, 13, 13, 1, 2, eye); _rect(img, 18, 13, 1, 2, eye)
				_rect(img, 15, 17, 2, 1, sk.darkened(0.3))
		# arms + hands (left arm always down, right arm holds)
		var a1 := 1 if frame == 2 else 0
		_rect(img, 8, 19, 3, 7 - a1, sh.darkened(0.1)); _rect(img, 8, 26 - a1, 3, 3, sk)
		if act:
			_rect(img, 21, 17, 3, 5, sh.darkened(0.1)); _rect(img, 21, 14, 3, 3, sk)
			_held(img, held, 22, 14)
		else:
			var a2 := 1 if frame == 1 else 0
			_rect(img, 21, 19, 3, 7 - a2, sh.darkened(0.1)); _rect(img, 21, 26 - a2, 3, 3, sk)
			_held(img, held, 22, 26 - a2)
	if child:
		var small := img.duplicate()
		small.resize(24, 30, Image.INTERPOLATE_NEAREST)
		img.fill(Color(0, 0, 0, 0))
		img.blit_rect(small, Rect2i(0, 0, 24, 30), Vector2i(4, 10))
	_outline(img)
	return img


static func character(look: Dictionary, dir: String, frame: int, held: String, child: bool, female: bool) -> ImageTexture:
	var key := "%s|%s|%s|%s|%s|%s|%s|%d|%s|%d|%d" % [look.get("skin", ""), look.get("hair", ""), look.get("shirt", ""), look.get("pants", ""),
		look.get("shoes", ""), look.get("face", ""), dir, frame, held, int(child), int(female)]
	var tex = _chars.get(key)
	if tex == null:
		tex = ImageTexture.create_from_image(character_image(look, dir, frame, held, child, female))
		_chars[key] = tex
	return tex


static func facing_dir(f: Vector2) -> String:
	if absf(f.x) > absf(f.y):
		return "side"
	return "up" if f.y < 0.0 else "down"
