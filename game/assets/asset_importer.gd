class_name AssetImporter
extends RefCounted
## Turns photos and pictures into game assets, entirely on the device.
##
##  * photo_to_look(): analyses a portrait (skin-tone detection in YCbCr,
##    region statistics) and produces a character look: skin, hair and clothes
##    colours plus a 10x8 pixel face that is painted onto the sprite's head.
##  * pixelize(): converts any picture into a small palette-reduced sprite with
##    optional background removal, usable as a placeable world object.
##
## This is deterministic image analysis, not a neural network: nothing is
## uploaded anywhere and no model download is needed. GIF and video are not
## supported yet (Godot has no built-in decoder for them).

const MAX_FILE_BYTES := 20 * 1024 * 1024
const MAX_SIDE := 8192
const MAX_SPRITE := 64
const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp"]


## Returns {"ok": bool, "image": Image, "error": String}
static func load_image_file(path: String) -> Dictionary:
	if not EXTENSIONS.has(path.get_extension().to_lower()):
		return {"ok": false, "image": null, "error": "unsupported file type (png, jpg, webp, bmp)"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "image": null, "error": "file not found"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_FILE_BYTES:
		return {"ok": false, "image": null, "error": "file too large (max 20 MB)"}
	var img := Image.new()
	if img.load(path) != OK or img.is_empty():
		return {"ok": false, "image": null, "error": "could not decode image"}
	if img.get_width() > MAX_SIDE or img.get_height() > MAX_SIDE:
		return {"ok": false, "image": null, "error": "image too large (max 8192 px)"}
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return {"ok": true, "image": img, "error": ""}


static func _is_skin(c: Color) -> bool:
	var r := c.r * 255.0
	var g := c.g * 255.0
	var b := c.b * 255.0
	var cb := 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b
	var cr := 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b
	return cb >= 77.0 and cb <= 127.0 and cr >= 133.0 and cr <= 173.0 and r > 60.0


static func _mean(img: Image, rect: Rect2i, want_skin: int) -> Array:
	## want_skin: 1 only skin, 0 only non-skin, -1 everything. Returns [Color, count].
	var r := rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var acc := Vector3.ZERO
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or (want_skin >= 0 and int(_is_skin(c)) != want_skin):
				continue
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return [Color.BLACK, 0]
	return [Color(acc.x / n, acc.y / n, acc.z / n), n]


## Face bounding box in a 64x64 working image, found from skin-tone density.
static func find_face(small: Image) -> Rect2i:
	var w := small.get_width()
	var h := small.get_height()
	var cols := PackedInt32Array(); cols.resize(w)
	var rows := PackedInt32Array(); rows.resize(h)
	var total := 0
	for y in int(h * 0.8):
		for x in w:
			if _is_skin(small.get_pixel(x, y)):
				cols[x] += 1
				rows[y] += 1
				total += 1
	if total < w * h * 0.03:
		return Rect2i(int(w * 0.3), int(h * 0.15), int(w * 0.4), int(h * 0.4))
	var cmax := 0
	var rmax := 0
	for v in cols: cmax = maxi(cmax, v)
	for v in rows: rmax = maxi(rmax, v)
	var x0 := 0
	var x1 := w - 1
	var y0 := 0
	var y1 := h - 1
	while x0 < w - 1 and cols[x0] < cmax * 0.35: x0 += 1
	while x1 > x0 and cols[x1] < cmax * 0.35: x1 -= 1
	while y0 < h - 1 and rows[y0] < rmax * 0.35: y0 += 1
	while y1 > y0 and rows[y1] < rmax * 0.35: y1 -= 1
	return Rect2i(x0, y0, maxi(4, x1 - x0 + 1), maxi(4, y1 - y0 + 1))


## Portrait photo -> {"look": {skin, hair, shirt, pants}, "face": Image(10x8), "face_rect": Rect2i}
static func photo_to_look(photo: Image) -> Dictionary:
	var small: Image = photo.duplicate()
	small.convert(Image.FORMAT_RGBA8)
	small.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var face := find_face(small)
	var fh := face.size.y
	var skin: Array = _mean(small, face, 1)
	if skin[1] == 0:
		skin = _mean(small, face, -1)
	# hair: the narrow band right above the forehead (avoids background at the sides)
	var hair: Array = _mean(small, Rect2i(face.position.x + face.size.x / 4, face.position.y - maxi(2, int(fh * 0.28)), maxi(2, face.size.x / 2), maxi(2, int(fh * 0.28))), 0)
	if hair[1] < 6:
		hair = _mean(small, Rect2i(face.position.x - 4, face.position.y - 2, 4, fh / 2), 0)
	var shirt_rect := Rect2i(face.position.x - face.size.x / 2, face.end.y + int(fh * 0.3), face.size.x * 2, int(fh * 0.8))
	var shirt: Array = _mean(small, shirt_rect, 0)
	if shirt[1] < 6:
		shirt = _mean(small, Rect2i(0, 52, 64, 12), -1)
	var pants: Array = _mean(small, Rect2i(8, 58, 48, 6), 0)
	var shirt_c: Color = shirt[0] if shirt[1] > 0 else Color("#3a6ac8")
	var pants_c: Color = pants[0] if pants[1] > 20 and Vector3(pants[0].r - shirt_c.r, pants[0].g - shirt_c.g, pants[0].b - shirt_c.b).length() > 0.18 else shirt_c.darkened(0.45)
	var hair_c: Color = hair[0] if hair[1] > 0 else Color("#3a2a22")
	# pixel face: inner part of the face box, 10x8, slightly posterised
	var inner := Rect2i(face.position.x + face.size.x / 8, face.position.y + fh / 5, maxi(4, face.size.x * 3 / 4), maxi(4, int(fh * 0.7)))
	inner = inner.intersection(Rect2i(0, 0, 64, 64))
	var scale := Vector2(photo.get_width() / 64.0, photo.get_height() / 64.0)
	var src: Image = photo.get_region(Rect2i(int(inner.position.x * scale.x), int(inner.position.y * scale.y), maxi(1, int(inner.size.x * scale.x)), maxi(1, int(inner.size.y * scale.y))))
	src.convert(Image.FORMAT_RGBA8)
	src.resize(10, 8, Image.INTERPOLATE_LANCZOS)
	for y in 8:
		for x in 10:
			var c := src.get_pixel(x, y)
			src.set_pixel(x, y, Color(snappedf(c.r, 1.0 / 12.0), snappedf(c.g, 1.0 / 12.0), snappedf(c.b, 1.0 / 12.0), 1.0))
	return {"look": {"skin": "#" + skin[0].to_html(false), "hair": "#" + hair_c.to_html(false), "shirt": "#" + shirt_c.to_html(false),
		"pants": "#" + pants_c.to_html(false)}, "face": src, "face_rect": face}


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Median-cut palette of at most `n` colours from the opaque pixels.
static func palette(img: Image, n: int) -> Array:
	var px: Array = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a >= 0.5:
				px.append(Vector3(c.r, c.g, c.b))
	if px.is_empty():
		return []
	var boxes: Array = [px]
	while boxes.size() < n:
		var bi := -1
		var best := 0.0
		var axis := 0
		for i in boxes.size():
			var b: Array = boxes[i]
			if b.size() < 2:
				continue
			var lo: Vector3 = b[0]
			var hi: Vector3 = b[0]
			for v in b:
				lo = lo.min(v)
				hi = hi.max(v)
			var ext := hi - lo
			var m := maxf(ext.x, maxf(ext.y, ext.z))
			if m * sqrt(b.size()) > best:
				best = m * sqrt(b.size())
				bi = i
				axis = 0 if m == ext.x else (1 if m == ext.y else 2)
		if bi < 0 or best < 0.001:
			break
		var box: Array = boxes[bi]
		box.sort_custom(func(a, b2): return a[axis] < b2[axis])
		boxes[bi] = box.slice(0, box.size() / 2)
		boxes.append(box.slice(box.size() / 2))
	var out: Array = []
	for b in boxes:
		var acc := Vector3.ZERO
		for v in b:
			acc += v
		acc /= b.size()
		out.append(Color(acc.x, acc.y, acc.z))
	return out


## Any picture -> small pixel sprite (<= max_side px, <= colors colours).
static func pixelize(src: Image, max_side: int = 32, colors: int = 16, remove_bg: bool = true) -> Image:
	max_side = clampi(max_side, 8, MAX_SPRITE)
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var k := float(max_side) / float(maxi(img.get_width(), img.get_height()))
	var w := maxi(1, int(round(img.get_width() * k)))
	var h := maxi(1, int(round(img.get_height() * k)))
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	if remove_bg:
		# flood from the border through pixels close to the corner colour
		var bg := img.get_pixel(0, 0).lerp(img.get_pixel(w - 1, 0), 0.5).lerp(img.get_pixel(0, h - 1).lerp(img.get_pixel(w - 1, h - 1), 0.5), 0.5)
		var stack: Array = []
		for x in w:
			stack.append(Vector2i(x, 0)); stack.append(Vector2i(x, h - 1))
		for y in h:
			stack.append(Vector2i(0, y)); stack.append(Vector2i(w - 1, y))
		var seen := {}
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or seen.has(p):
				continue
			seen[p] = true
			var c := img.get_pixel(p.x, p.y)
			if c.a >= 0.5 and _dist(c, bg) > 0.16:
				continue
			img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
			stack.append(p + Vector2i(1, 0)); stack.append(p + Vector2i(-1, 0))
			stack.append(p + Vector2i(0, 1)); stack.append(p + Vector2i(0, -1))
	var pal := palette(img, clampi(colors, 2, 64))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or pal.is_empty():
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var best: Color = pal[0]
			var bd := 9.0
			for pc in pal:
				var d := _dist(c, pc)
				if d < bd:
					bd = d
					best = pc
			img.set_pixel(x, y, best)
	return img
