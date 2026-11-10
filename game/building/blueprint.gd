class_name Blueprint
extends RefCounted
## Portable building description. Uses tile *keys* (not numeric ids) so it
## survives content updates and can be shared between worlds and players.

const FORMAT := 1
const PREFIX := "MPB1:"
const DIR := "user://blueprints"

var name := "blueprint"
var w := 0
var h := 0
var cells: Array = []     # [[dx, dy, layer, key]]
var props: Array = []     # [[key, x, y, rot, z]]  x/y in px relative to origin


func rotated() -> Blueprint:
	## 90 degrees clockwise.
	var b := Blueprint.new()
	b.name = name
	b.w = h
	b.h = w
	for c in cells:
		b.cells.append([h - 1 - int(c[1]), int(c[0]), c[2], c[3]])
	for p in props:
		b.props.append([p[0], h * MP.TILE - float(p[2]), float(p[1]), (int(p[3]) + 1) % 4, p[4]])
	return b


func to_dict() -> Dictionary:
	return {"format": FORMAT, "name": name, "w": w, "h": h, "cells": cells, "props": props}


static func from_dict(d) -> Blueprint:
	if not (d is Dictionary) or int(d.get("format", 0)) != FORMAT:
		return null
	var b := Blueprint.new()
	b.name = str(d.get("name", "blueprint")).validate_filename()
	b.w = int(d.get("w", 0))
	b.h = int(d.get("h", 0))
	if b.w <= 0 or b.h <= 0 or b.w > 256 or b.h > 256:
		return null
	for c in d.get("cells", []):
		if c is Array and c.size() == 4:
			var x := int(c[0])
			var y := int(c[1])
			var l := int(c[2])
			if x >= 0 and y >= 0 and x < b.w and y < b.h and l >= 0 and l < MP.LAYERS:
				b.cells.append([x, y, l, str(c[3])])
	for p in d.get("props", []):
		if p is Array and p.size() == 5:
			b.props.append([str(p[0]), float(p[1]), float(p[2]), int(p[3]), int(p[4])])
	return b


func export_string() -> String:
	return PREFIX + Marshalls.raw_to_base64(JSON.stringify(to_dict()).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)) \
		+ ":" + str(JSON.stringify(to_dict()).to_utf8_buffer().size())


static func import_string(s: String) -> Blueprint:
	s = s.strip_edges()
	if not s.begins_with(PREFIX):
		return null
	var parts := s.substr(PREFIX.length()).split(":")
	if parts.size() != 2:
		return null
	var size := int(parts[1])
	if size <= 0 or size > 4 * 1024 * 1024:
		return null
	var raw := Marshalls.base64_to_raw(parts[0])
	if raw.is_empty():
		return null
	var data := raw.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != size:
		return null
	return from_dict(JSON.parse_string(data.get_string_from_utf8()))


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	return SaveService.atomic_write(DIR.path_join(name.validate_filename() + ".json"), JSON.stringify(to_dict()).to_utf8_buffer())


static func list_saved() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	out.sort()
	return out


static func load_saved(p_name: String) -> Blueprint:
	var path := DIR.path_join(p_name.validate_filename() + ".json")
	if not FileAccess.file_exists(path):
		return null
	return from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
