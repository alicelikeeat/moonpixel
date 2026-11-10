class_name Settlement
extends RefCounted
## A village founded and built by agents: stockpile, building projects,
## navigation grid and the resource index of its surroundings.

const SPAN := 96                 # tiles (3x3 chunks) managed around the centre

var id := 0
var name := {"en": "", "zh": ""}
var center := Vector2i.ZERO
var founded := 0.0
var stock := {"food": 0.0, "wood": 0.0, "stone": 0.0}
var buildings: Array = []        # [{id,type,x,y,w,h,cells,next,placed,retry,done,residents,cap,door}]
var members: Array = []          # agent ids
var nav: AStarGrid2D = null
var origin := Vector2i.ZERO      # top-left tile of the managed area
var res := {"tree": [], "rock": [], "berry": []}
var claims: Dictionary = {}
var res_t := 0.0
var plan_t := 0.0
var last_found := 0.0
var used_slots: Dictionary = {}
var graves := 0
var abandoned := false


func in_area(t: Vector2i) -> bool:
	return t.x >= origin.x and t.y >= origin.y and t.x < origin.x + SPAN and t.y < origin.y + SPAN


func building(bid: int):
	for b in buildings:
		if b["id"] == bid:
			return b
	return null


func count_type(type: String, only_done: bool = false) -> int:
	var n := 0
	for b in buildings:
		if b["type"] == type and (b["done"] or not only_done):
			n += 1
	return n


func active_project():
	for b in buildings:
		if not b["done"]:
			return b
	return null


func to_dict() -> Dictionary:
	var bl: Array = []
	for b in buildings:
		var c: Dictionary = b.duplicate(true)
		c["door"] = [b["door"].x, b["door"].y]
		bl.append(c)
	return {"id": id, "name": name, "cx": center.x, "cy": center.y, "founded": founded, "stock": stock, "buildings": bl,
		"members": members, "last_found": last_found, "slots": used_slots.keys(), "graves": graves, "abandoned": abandoned}


static func from_dict(d: Dictionary) -> Settlement:
	var s := Settlement.new()
	s.id = int(d["id"])
	s.name = d.get("name", s.name)
	s.center = Vector2i(int(d["cx"]), int(d["cy"]))
	s.founded = float(d.get("founded", 0.0))
	var st = d.get("stock", {})
	for k in s.stock:
		s.stock[k] = float(st.get(k, 0.0))
	for b in d.get("buildings", []):
		var c: Dictionary = b
		for k in ["id", "x", "y", "w", "h", "next", "placed", "cap"]:
			c[k] = int(c.get(k, 0))
		c["door"] = Vector2i(int(c["door"][0]), int(c["door"][1]))
		var res_ids: Array = []
		for r in c.get("residents", []):
			res_ids.append(int(r))
		c["residents"] = res_ids
		var retry: Array = []
		for r in c.get("retry", []):
			retry.append(int(r))
		c["retry"] = retry
		for cell in c["cells"]:
			cell[0] = int(cell[0]); cell[1] = int(cell[1]); cell[2] = int(cell[2])
		s.buildings.append(c)
	for m in d.get("members", []):
		s.members.append(int(m))
	s.last_found = float(d.get("last_found", 0.0))
	for k in d.get("slots", []):
		s.used_slots[str(k)] = true
	s.graves = int(d.get("graves", 0))
	s.abandoned = bool(d.get("abandoned", false))
	return s
