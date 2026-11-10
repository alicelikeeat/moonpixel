class_name BuildOp
extends RefCounted
## A previewable, validatable batch of world edits. Nothing touches the world
## until BuildService.commit() applies the whole batch atomically.

var cells: Array = []          # [{x,y,l,id,r}]  id 0 = erase, r = replace existing
var prop_adds: Array = []      # [{key,x,y,rot,z}] (+id when re-adding)
var prop_removes: Array = []   # [{id,x,y}]
var label := ""
var _index: Dictionary = {}


func set_cell(x: int, y: int, layer: int, id: int, replace: bool = false) -> void:
	var k := Vector3i(x, y, layer)
	var c := {"x": x, "y": y, "l": layer, "id": id, "r": replace}
	if _index.has(k):
		cells[_index[k]] = c
	else:
		_index[k] = cells.size()
		cells.append(c)


func has_cell(x: int, y: int, layer: int) -> bool:
	return _index.has(Vector3i(x, y, layer))


func is_empty() -> bool:
	return cells.is_empty() and prop_adds.is_empty() and prop_removes.is_empty()


func bounds() -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var r := Rect2i(cells[0]["x"], cells[0]["y"], 1, 1)
	for c in cells:
		r = r.expand(Vector2i(c["x"], c["y"])).expand(Vector2i(c["x"] + 1, c["y"] + 1))
	return r
