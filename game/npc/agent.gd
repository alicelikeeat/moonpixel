class_name Agent
extends RefCounted
## One autonomous villager. Pure data + small helpers; all behaviour lives in
## Society so the whole population can be simulated headless.

var id := 0
var name := {"en": "", "zh": ""}
var clan := {"en": "", "zh": ""}
var female := false
var birth := 0.0                  # world time of birth
var sid := 0                      # settlement id
var home := -1                    # building id
var partner := 0
var mother := 0
var father := 0
var children: Array = []
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var facing := Vector2.DOWN
var moving := false
var hunger := 0.2                 # 0 fed .. 1 starving
var energy := 0.9                 # 1 rested .. 0 exhausted
var social := 0.3                 # 0 content .. 1 lonely
var health := 1.0
var grief := 0.0
var traits := {"dil": 0.5, "soc": 0.5, "bold": 0.5}
var look := {"skin": "#e8b890", "hair": "#5a3a22", "shirt": "#3a6ac8"}
var job := ""
var task: Dictionary = {}
var path: Array = []
var path_i := 0
var carry_kind := ""
var carry_n := 0.0
var rel: Dictionary = {}          # other agent id (0 = player) -> affinity -1..1
var thoughts: Array = []          # [{t, k, a}]
var pregnant_due := -1.0
var birth_father := 0
var last_birth := -1e9
var alive := true
var think_t := 0.0
var travelling := false
var travel_to := Vector2.ZERO
var sleeping := false


func age(now: float) -> float:
	return (now - birth) / OpenWorld.YEAR


func stage(now: float) -> String:
	var a := age(now)
	if a < 14.0:
		return "child"
	if a < 62.0:
		return "adult"
	return "elder"


func think(now: float, key: String, args: Array = []) -> void:
	thoughts.append({"t": now, "k": key, "a": args})
	if thoughts.size() > 6:
		thoughts.pop_front()


func mood() -> float:
	## 0 miserable .. 1 happy
	var m := 1.0 - hunger * 0.45 - (1.0 - energy) * 0.15 - social * 0.15 - grief * 0.3
	if home < 0:
		m -= 0.12
	return clampf(m * health, 0.0, 1.0)


func full_name() -> String:
	if Loc.lang == "zh":
		return MP.loc(clan) + MP.loc(name)
	return MP.loc(name) + " " + MP.loc(clan)


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "clan": clan, "f": female, "birth": birth, "sid": sid, "home": home, "partner": partner,
		"mother": mother, "father": father, "children": children, "x": pos.x, "y": pos.y, "hunger": hunger, "energy": energy,
		"social": social, "health": health, "grief": grief, "traits": traits, "look": look, "job": job, "rel": rel,
		"thoughts": thoughts, "due": pregnant_due, "bf": birth_father, "lb": last_birth, "trav": travelling,
		"tx": travel_to.x, "ty": travel_to.y}


static func from_dict(d: Dictionary) -> Agent:
	var a := Agent.new()
	a.id = int(d["id"])
	a.name = d.get("name", a.name)
	a.clan = d.get("clan", a.clan)
	a.female = bool(d.get("f", false))
	a.birth = float(d.get("birth", 0.0))
	a.sid = int(d.get("sid", 0))
	a.home = int(d.get("home", -1))
	a.partner = int(d.get("partner", 0))
	a.mother = int(d.get("mother", 0))
	a.father = int(d.get("father", 0))
	for c in d.get("children", []):
		a.children.append(int(c))
	a.pos = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
	a.prev_pos = a.pos
	a.hunger = float(d.get("hunger", 0.2))
	a.energy = float(d.get("energy", 0.9))
	a.social = float(d.get("social", 0.3))
	a.health = float(d.get("health", 1.0))
	a.grief = float(d.get("grief", 0.0))
	a.traits = d.get("traits", a.traits)
	a.look = d.get("look", a.look)
	a.job = str(d.get("job", ""))
	var rel = d.get("rel", {})
	for k in rel:
		a.rel[int(k)] = float(rel[k])
	a.thoughts = d.get("thoughts", [])
	a.pregnant_due = float(d.get("due", -1.0))
	a.birth_father = int(d.get("bf", 0))
	a.last_birth = float(d.get("lb", -1e9))
	a.travelling = bool(d.get("trav", false))
	a.travel_to = Vector2(float(d.get("tx", 0)), float(d.get("ty", 0)))
	return a
