class_name BuildService
extends RefCounted
## BuildService: validation and atomic application of build operations,
## undo/redo, region copy and blueprint paste, free-positioned props.
##
## Flow for every tool (continuous draw, rectangle, erase, paste, artisan):
##   preview (BuildOp) -> validate() -> user confirms -> commit()
## commit() re-validates, performs the inventory transaction first, and only
## then writes tiles; a failure at any point leaves world and inventory
## untouched. Edits spanning several chunks are one operation.

const UNDO_LIMIT := 64

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var inv: InventoryService
var terrain: TerrainOps
var bus: EventBus
var undo_stack: Array = []
var redo_stack: Array = []
var custom_props: Dictionary = {}     # imported assets: key -> {cost:{}, ...}


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_inv: InventoryService,
		p_terrain: TerrainOps, p_bus: EventBus) -> void:
	content = p_content; world = p_world; entities = p_entities; inv = p_inv; terrain = p_terrain; bus = p_bus


func layer_of(tile_key: String) -> int:
	return int(content.t_layer[content.tid(tile_key)])


func _costs_on() -> bool:
	return bool(world.rule("build_cost")) and not bool(world.rule("god_build"))


func _cost_of(id: int) -> Dictionary:
	if id == 0 or not _costs_on():
		return {}
	var b = content.buildable_by_tile.get(content.tile_key(id))
	return {} if b == null else b["cost"]


func _actor_on_tile(x: int, y: int) -> bool:
	var r := Rect2(x * MP.TILE, y * MP.TILE, MP.TILE, MP.TILE)
	for a in entities.actors:
		if a.alive and r.grow(a.radius - 0.5).has_point(a.pos):
			return true
	return false


## "" = ok, "noop" = nothing to do, otherwise a Loc error key.
func check_cell(c: Dictionary) -> String:
	var x: int = c["x"]
	var y: int = c["y"]
	var layer: int = c["l"]
	var id: int = c["id"]
	if not world.in_bounds(x, y):
		return "err_bounds"
	var cur := world.tile(layer, x, y)
	if cur == id:
		return "noop"
	var god := bool(world.rule("god_build"))
	if terrain.is_protected(x, y):
		return "err_protected"
	var replace: bool = c.get("r", false)
	if cur != 0 and (id == 0 or replace or layer == MP.L_GROUND):
		# removing/replacing what is there
		var ct: Dictionary = content.tiles[cur]
		if not god:
			if int(ct.get("hard", 1)) >= 99:
				return "err_protected"
			if layer != MP.L_GROUND and ct.get("natural", 0) == 1 and not bool(world.rule("terrain_edit")):
				return "err_rule"
	if id == 0:
		if layer == MP.L_GROUND:
			return "noop"
		return ""
	var t: Dictionary = content.tiles[id]
	if int(t["layer"]) != layer:
		return "err_blocked"
	var ground := world.tile(MP.L_GROUND, x, y)
	var st := world.tile(MP.L_STRUCT, x, y)
	var ob := world.tile(MP.L_OBJECT, x, y)
	match layer:
		MP.L_GROUND:
			var natural_change: bool = t.get("built", 0) == 0 or content.t_water[ground] != 0
			if natural_change and not god and not bool(world.rule("terrain_edit")):
				return "err_rule"
			if content.t_solid[id] != 0 and (ob != 0 or _actor_on_tile(x, y)):
				return "err_blocked"
		MP.L_STRUCT:
			if cur != 0 and content.t_solid[cur] != 0 and not replace:
				return "err_blocked"
		MP.L_OBJECT:
			if cur != 0 and not replace:
				return "err_blocked"
			if st != 0 and content.t_solid[st] != 0:
				return "err_blocked"
			if content.t_solid[ground] != 0 and not (st != 0 and content.t_bridge[st] != 0):
				return "err_blocked"
			if t.get("crop", 0) == 1 and content.tile_key(ground) != "farmland":
				return "err_blocked"
			if content.t_solid[id] != 0 and _actor_on_tile(x, y):
				return "err_blocked"
		MP.L_DECOR:
			if ob != 0 or content.t_solid[ground] != 0:
				return "err_blocked"
	return ""


func _prop_def(key: String):
	if content.props.has(key):
		return content.props[key]
	return custom_props.get(key)


func check_prop(p: Dictionary) -> String:
	if _prop_def(str(p["key"])) == null:
		return "err_blocked"
	var t := MP.tile_of(Vector2(p["x"], p["y"]))
	if not world.in_bounds(t.x, t.y):
		return "err_bounds"
	if terrain.is_protected(t.x, t.y):
		return "err_protected"
	return ""


static func _acc(into: Dictionary, add: Dictionary) -> void:
	for k in add:
		into[k] = int(into.get(k, 0)) + int(add[k])


## Returns {"ok", "error", "cell_errors": {Vector3i: code}, "valid": Array,
##          "cost": Dictionary, "refund": Dictionary, "props_ok": Array}
func validate(op: BuildOp, bag: Inventory, skip_invalid: bool = true) -> Dictionary:
	var res := {"ok": true, "error": "", "cell_errors": {}, "valid": [], "cost": {}, "refund": {}, "props_ok": []}
	for c in op.cells:
		var err := check_cell(c)
		if err == "noop":
			continue
		if err != "":
			res["cell_errors"][Vector3i(c["x"], c["y"], c["l"])] = err
			if not skip_invalid:
				res["ok"] = false
				res["error"] = err
			continue
		res["valid"].append(c)
		_acc(res["cost"], _cost_of(c["id"]))
		var cur := world.tile(c["l"], c["x"], c["y"])
		if cur != 0 and content.tiles[cur].get("natural", 0) == 0:
			_acc(res["refund"], _cost_of(cur))
	for p in op.prop_adds:
		var err := check_prop(p)
		if err != "":
			res["cell_errors"][Vector3i(int(p["x"]) / MP.TILE, int(p["y"]) / MP.TILE, 9)] = err
			if not skip_invalid:
				res["ok"] = false
				res["error"] = err
			continue
		res["props_ok"].append(p)
		if _costs_on() and not p.has("id"):
			_acc(res["cost"], _prop_def(str(p["key"]))["cost"])
	if res["ok"] and res["valid"].is_empty() and res["props_ok"].is_empty() and op.prop_removes.is_empty():
		res["ok"] = false
		res["error"] = "err_blocked" if not res["cell_errors"].is_empty() else "noop"
		if res["error"] == "err_blocked":
			res["error"] = str(res["cell_errors"].values()[0])
	if res["ok"] and bag != null and not inv.has_all(bag, res["cost"]):
		res["ok"] = false
		res["error"] = "err_cost"
	return res


## Atomic commit. Returns {"ok", "error", "placed"}.
func commit(op: BuildOp, bag: Inventory, skip_invalid: bool = true, _from_redo: bool = false) -> Dictionary:
	var v := validate(op, bag, skip_invalid)
	if not v["ok"]:
		return {"ok": false, "error": v["error"], "placed": 0}
	# 1) inventory transaction (may fail -> nothing changed)
	var leftovers: Array = []
	if bag != null and _costs_on():
		var txn := inv.begin()
		for k in v["cost"]:
			txn.remove(bag, k, int(v["cost"][k]))
		if not inv.commit(txn):
			return {"ok": false, "error": "err_cost", "placed": 0}
		for k in v["refund"]:
			var left := inv.give_partial(bag, k, int(v["refund"][k]), "refund")
			if left > 0:
				leftovers.append([k, left])
	# 2) world writes (validated; cannot fail)
	var rec := {"cells": [], "props_added": [], "props_removed": [], "op": op}
	for c in v["valid"]:
		var x: int = c["x"]
		var y: int = c["y"]
		var layer: int = c["l"]
		var old := world.tile(layer, x, y)
		var entry := {"x": x, "y": y, "l": layer, "old": old, "new": c["id"], "cost": _cost_of(c["id"]).duplicate(),
			"refund": (_cost_of(old).duplicate() if old != 0 and content.tiles[old].get("natural", 0) == 0 else {})}
		if layer == MP.L_OBJECT and old != 0:
			var ot: Dictionary = content.tiles[old]
			if ot.has("container"):
				entry["container"] = world.container_at(x, y).duplicate(true)
				# contents of a removed chest spill out, they are never destroyed
				for s in entry["container"]:
					if s != null:
						entities.spawn_drop(s[0], int(s[1]), Vector2(x * MP.TILE + 8, y * MP.TILE + 8))
			elif ot.get("natural", 0) == 1 and ot.has("drops") and not bool(world.rule("god_build")):
				for d in terrain.roll_drops(ot["drops"]):
					leftovers.append(d)
		world.set_tile(layer, x, y, c["id"], true)
		rec["cells"].append(entry)
	for pr in op.prop_removes:
		var removed = _remove_prop(int(pr["id"]), float(pr["x"]), float(pr["y"]))
		if removed != null:
			rec["props_removed"].append(removed)
			if _costs_on() and not pr.get("moving", false):
				var def = _prop_def(str(removed["key"]))
				if def != null:
					for k in def["cost"]:
						leftovers.append([k, int(def["cost"][k])])
	for p in v["props_ok"]:
		rec["props_added"].append(_add_prop(p))
	if bag != null:
		for l in leftovers:
			var left := inv.give_partial(bag, l[0], int(l[1]), "refund")
			if left > 0:
				entities.spawn_drop(l[0], left, entities.actors[0].pos if entities.actors.size() > 0 else Vector2.ZERO)
	undo_stack.append(rec)
	if undo_stack.size() > UNDO_LIMIT:
		undo_stack.pop_front()
	if not _from_redo:
		redo_stack.clear()
	bus.sfx.emit("place", Vector2.ZERO)
	return {"ok": true, "error": "", "placed": rec["cells"].size() + rec["props_added"].size() + rec["props_removed"].size()}


func can_undo() -> bool:
	return not undo_stack.is_empty()


func can_redo() -> bool:
	return not redo_stack.is_empty()


## Reverts the last committed operation. Cells that changed since (crop grew,
## something else was built there) are left alone rather than clobbered.
func undo(bag: Inventory) -> bool:
	if undo_stack.is_empty():
		return false
	var rec: Dictionary = undo_stack.pop_back()
	var cells: Array = rec["cells"]
	for i in range(cells.size() - 1, -1, -1):
		var e: Dictionary = cells[i]
		if world.tile(e["l"], e["x"], e["y"]) != int(e["new"]):
			continue
		if bag != null and _costs_on():
			# take back the refund, return the cost; skip the cell if impossible
			var txn := inv.begin()
			for k in e["refund"]:
				txn.remove(bag, k, int(e["refund"][k]))
			if not inv.commit(txn):
				continue
			for k in e["cost"]:
				var left := inv.give_partial(bag, k, int(e["cost"][k]), "refund")
				if left > 0:
					entities.spawn_drop(k, left, Vector2(e["x"] * MP.TILE + 8, e["y"] * MP.TILE + 8))
		world.set_tile(e["l"], e["x"], e["y"], int(e["old"]), true)
		if e.has("container"):
			var slots := world.container_at(e["x"], e["y"])
			# contents were spilled as drops on removal; restore the empty chest only
			for s in slots.size():
				slots[s] = null
	for id_added in rec["props_added"]:
		_remove_prop(int(id_added["id"]), float(id_added["x"]), float(id_added["y"]))
	for p in rec["props_removed"]:
		_add_prop(p)
	redo_stack.append(rec["op"])
	return true


func redo(bag: Inventory) -> bool:
	if redo_stack.is_empty():
		return false
	var op: BuildOp = redo_stack.pop_back()
	# re-adding props must not reuse stale ids
	for p in op.prop_adds:
		p.erase("id")
	var res := commit(op, bag, true, true)
	return res["ok"]


# --- props (free positioning) --------------------------------------------------
func _prop_chunk(x: float, y: float) -> ChunkData:
	return world.chunks.get_chunk(floori(x / MP.CHUNK_PX), floori(y / MP.CHUNK_PX))


func _add_prop(p: Dictionary) -> Dictionary:
	var c := _prop_chunk(p["x"], p["y"])
	var q := {"id": int(p.get("id", 0)), "key": str(p["key"]), "x": float(p["x"]), "y": float(p["y"]),
		"rot": int(p.get("rot", 0)), "z": int(p.get("z", 0))}
	if q["id"] == 0:
		q["id"] = world.next_prop_id
		world.next_prop_id += 1
	c.props.append(q)
	c.touch()
	bus.props_changed.emit(c.cx, c.cy)
	return q


func _remove_prop(id: int, x: float, y: float):
	var c := _prop_chunk(x, y)
	if c == null:
		return null
	for i in c.props.size():
		if int(c.props[i]["id"]) == id:
			var p: Dictionary = c.props[i]
			c.props.remove_at(i)
			c.touch()
			bus.props_changed.emit(c.cx, c.cy)
			return p
	return null


## Nearest prop within `radius` px of a world position (searches 3x3 chunks).
func prop_at(pos: Vector2, radius: float = 10.0):
	var best = null
	var best_d := radius * radius
	var cc := Vector2i(floori(pos.x / MP.CHUNK_PX), floori(pos.y / MP.CHUNK_PX))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := world.chunks.peek(cc.x + dx, cc.y + dy)
			if c == null:
				continue
			for p in c.props:
				var d := Vector2(p["x"], p["y"]).distance_squared_to(pos)
				if d < best_d:
					best_d = d
					best = p
	return best


func op_place_prop(key: String, pos: Vector2, rot: int = 0, z: int = 0) -> BuildOp:
	var op := BuildOp.new()
	op.prop_adds.append({"key": key, "x": pos.x, "y": pos.y, "rot": rot, "z": z})
	return op


func op_remove_prop(p: Dictionary) -> BuildOp:
	var op := BuildOp.new()
	op.prop_removes.append({"id": p["id"], "x": p["x"], "y": p["y"]})
	return op


## Move / rotate / re-layer an existing prop (keeps its id, costs nothing).
func op_modify_prop(p: Dictionary, new_pos: Vector2, rot: int, z: int) -> BuildOp:
	var op := BuildOp.new()
	op.prop_removes.append({"id": p["id"], "x": p["x"], "y": p["y"], "moving": true})
	op.prop_adds.append({"id": p["id"], "key": p["key"], "x": new_pos.x, "y": new_pos.y, "rot": rot, "z": z})
	return op


# --- tool helpers -----------------------------------------------------------------
static func line_points(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var x := a.x
	var y := a.y
	while true:
		out.append(Vector2i(x, y))
		if x == b.x and y == b.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return out


func add_tile(op: BuildOp, tile_key: String, t: Vector2i) -> void:
	var id := content.tid(tile_key)
	op.set_cell(t.x, t.y, int(content.t_layer[id]), id)


func op_line(tile_key: String, a: Vector2i, b: Vector2i, into: BuildOp = null) -> BuildOp:
	var op := into if into != null else BuildOp.new()
	for p in line_points(a, b):
		add_tile(op, tile_key, p)
	return op


func op_rect(tile_key: String, a: Vector2i, b: Vector2i, filled: bool = true) -> BuildOp:
	var op := BuildOp.new()
	var x0 := mini(a.x, b.x); var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y); var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if filled or x == x0 or x == x1 or y == y0 or y == y1:
				add_tile(op, tile_key, Vector2i(x, y))
	return op


## Erase everything removable (objects, structures, decor) in a rectangle.
func op_erase(a: Vector2i, b: Vector2i, into: BuildOp = null) -> BuildOp:
	var op := into if into != null else BuildOp.new()
	var x0 := mini(a.x, b.x); var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y); var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			# top-most layer first: one erase pass removes one thing per tile
			if world.tile(MP.L_OBJECT, x, y) != 0:
				op.set_cell(x, y, MP.L_OBJECT, 0)
			elif world.tile(MP.L_DECOR, x, y) != 0:
				op.set_cell(x, y, MP.L_DECOR, 0)
			elif world.tile(MP.L_STRUCT, x, y) != 0:
				op.set_cell(x, y, MP.L_STRUCT, 0)
			else:
				var g := world.tile(MP.L_GROUND, x, y)
				if g != 0 and content.tiles[g].get("built", 0) == 1:
					# removing a floor reveals plain dirt
					op.set_cell(x, y, MP.L_GROUND, content.tid("dirt"))
	var r := Rect2(x0 * MP.TILE, y0 * MP.TILE, (x1 - x0 + 1) * MP.TILE, (y1 - y0 + 1) * MP.TILE)
	for cy in range(floori(r.position.y / MP.CHUNK_PX), floori(r.end.y / MP.CHUNK_PX) + 1):
		for cx in range(floori(r.position.x / MP.CHUNK_PX), floori(r.end.x / MP.CHUNK_PX) + 1):
			var c := world.chunks.peek(cx, cy)
			if c != null:
				for p in c.props:
					if r.has_point(Vector2(p["x"], p["y"])):
						op.prop_removes.append({"id": p["id"], "x": p["x"], "y": p["y"]})
	return op


func copy_region(a: Vector2i, b: Vector2i, include_ground: bool = false) -> Blueprint:
	var bp := Blueprint.new()
	var x0 := mini(a.x, b.x); var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y); var y1 := maxi(a.y, b.y)
	bp.w = x1 - x0 + 1
	bp.h = y1 - y0 + 1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			for layer in MP.LAYERS:
				var id := world.tile(layer, x, y)
				if id == 0:
					continue
				var t: Dictionary = content.tiles[id]
				if int(t.get("hard", 1)) >= 99:
					continue
				if layer == MP.L_GROUND and not include_ground and t.get("built", 0) == 0:
					continue
				bp.cells.append([x - x0, y - y0, layer, t["key"]])
	var r := Rect2(x0 * MP.TILE, y0 * MP.TILE, bp.w * MP.TILE, bp.h * MP.TILE)
	for cy in range(floori(r.position.y / MP.CHUNK_PX), floori(r.end.y / MP.CHUNK_PX) + 1):
		for cx in range(floori(r.position.x / MP.CHUNK_PX), floori(r.end.x / MP.CHUNK_PX) + 1):
			var c := world.chunks.peek(cx, cy)
			if c != null:
				for p in c.props:
					if r.has_point(Vector2(p["x"], p["y"])):
						bp.props.append([p["key"], float(p["x"]) - r.position.x, float(p["y"]) - r.position.y, p["rot"], p["z"]])
	return bp


func op_paste(bp: Blueprint, origin: Vector2i, rotation: int = 0, replace: bool = false) -> BuildOp:
	var b := bp
	for i in posmod(rotation, 4):
		b = b.rotated()
	var op := BuildOp.new()
	op.label = bp.name
	for c in b.cells:
		var id := content.tid(str(c[3]))
		if id != 0 and int(content.t_layer[id]) == int(c[2]):
			op.set_cell(origin.x + int(c[0]), origin.y + int(c[1]), int(c[2]), id, replace)
	for p in b.props:
		op.prop_adds.append({"key": p[0], "x": origin.x * MP.TILE + float(p[1]), "y": origin.y * MP.TILE + float(p[2]), "rot": p[3], "z": p[4]})
	return op
