class_name Entity
extends RefCounted
## Logical entity state. Rendering nodes (EntityView) only read from this;
## logic never depends on scene nodes, so the simulation runs headless.

const TEAM_PLAYER := 0
const TEAM_HOSTILE := 1
const TEAM_WILD := 2

const PH_NONE := 0
const PH_WINDUP := 1
const PH_ACTIVE := 2
const PH_RECOVERY := 3

var id := 0
var kind := ""                 # player | enemy | animal | npc | drop | projectile
var def_id := ""
var def: Dictionary = {}
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO        # external impulse (knockback)
var facing := Vector2.DOWN
var move_dir := Vector2.ZERO   # last intentional movement (animation)
var radius := 6.0
var hp := 1.0
var max_hp := 1.0
var team := TEAM_HOSTILE
var alive := true
var remove := false
var state := "idle"
var state_t := 0.0
# skill runner
var skill: Dictionary = {}
var skill_phase := PH_NONE
var skill_t := 0.0
var skill_dir := Vector2.DOWN
var skill_power := 1.0         # attacker base damage captured at cast time
var cooldowns: Dictionary = {}
var statuses: Array = []       # [{type,time,power,acc}]
var iframes := 0.0
var stun := 0.0
var stagger := 0.0
var poise := 0.0
var max_poise := 0.0
var phase := 0
var home := Vector2.ZERO
var home_chunk := -1
var site := ""
var ai: Dictionary = {}
var data: Dictionary = {}
var acc_dt := 0.0              # accumulated dt for distance graded updates
var hit_flash := 0.0


func is_actor() -> bool:
	return kind == "player" or kind == "enemy" or kind == "animal" or kind == "npc"


func speed_mult() -> float:
	var m := 1.0
	for s in statuses:
		match s["type"]:
			"slow": m *= float(s["power"])
			"freeze": m = 0.0
			"haste": m *= 1.0 + float(s["power"])
	return m


func has_status(t: String) -> bool:
	for s in statuses:
		if s["type"] == t:
			return true
	return false


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "def": def_id, "x": pos.x, "y": pos.y, "hp": hp, "phase": phase,
		"hx": home.x, "hy": home.y, "hc": home_chunk, "site": site, "data": data.duplicate(true),
		"angry": bool(ai.get("angry", false))}
