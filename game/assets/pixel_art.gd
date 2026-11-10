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


## 16x20 villager sprite. frame 0 = stand, 1/2 = walk; child = smaller body.
static func person(skin: String, hair: String, shirt: String, child: bool, frame: int, female: bool) -> ImageTexture:
	var key := "%s%s%s%d%d%d" % [skin, hair, shirt, int(child), frame, int(female)]
	if _people.has(key):
		return _people[key]
	var img := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	var sk := Color(skin)
	var hr := Color(hair)
	var sh := Color(shirt)
	var top := 6 if child else 1
	_rect(img, 5, top, 6, 6, sk)                       # head
	_rect(img, 5, top, 6, 2, hr)
	_rect(img, 4, top + 1, 1, 4 if female else 2, hr)
	_rect(img, 11, top + 1, 1, 4 if female else 2, hr)
	_px(img, 6, top + 3, Color("#2a2a2a")); _px(img, 9, top + 3, Color("#2a2a2a"))
	var body_h := 5 if child else 7
	_rect(img, 4, top + 6, 8, body_h, sh)              # torso
	_rect(img, 3, top + 6, 1, body_h - 2, sh.darkened(0.15))
	_rect(img, 12, top + 6, 1, body_h - 2, sh.darkened(0.15))
	var ly := top + 6 + body_h
	var legs := Color("#4a4a5a")
	var l1 := 0
	var l2 := 0
	if frame == 1: l1 = -1
	if frame == 2: l2 = -1
	_rect(img, 5, ly, 2, 20 - ly + l1, legs)
	_rect(img, 9, ly, 2, 20 - ly + l2, legs)
	var tex := ImageTexture.create_from_image(img)
	_people[key] = tex
	return tex
