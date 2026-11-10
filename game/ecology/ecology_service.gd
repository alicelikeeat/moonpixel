class_name EcologyService
extends RefCounted
## Ecology rules: which species may appear where and when (time of day,
## weather, world rules, cleared sites), plus the "falling star" region event.
## Plant growth and resource regrowth are event driven through chunk timers
## (see WorldService.process_timers), not simulated per frame.

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var bus: EventBus
var rng := RandomNumberGenerator.new()
var _event_acc := 0.0


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_bus: EventBus) -> void:
	content = p_content; world = p_world; entities = p_entities; bus = p_bus
	entities.spawn_filter = allow_spawn


## Spawn gate used by EntityService when a chunk's population is rolled.
func allow_spawn(def: Dictionary, sp: Dictionary) -> bool:
	var site := str(sp.get("site", ""))
	if def["kind"] == "enemy":
		if not bool(world.rule("monsters")):
			return false
		if site != "" and world.flag("cleared_" + site):
			return false
		if site == "dungeon" and world.flag("boss_defeated"):
			return false
		return true
	# wildlife: activity window and weather
	var active := str(def.get("active", "any"))
	var night := world.is_night()
	var tx := int(float(sp["x"]) / MP.TILE)
	var ty := int(float(sp["y"]) / MP.TILE)
	var weather := world.weather_at(world.biome_group_at(tx, ty))
	if def["id"] == "frog" and weather == "rain":
		return true
	if weather == "storm" or weather == "snow":
		# most animals shelter in bad weather
		return MP.h01(world.day(), tx, ty) < 0.4
	if active == "day" and night:
		return false
	if active == "night" and not night:
		return false
	return true


## Region event: at night a star may fall near the player. It becomes a real
## world object the player has to reach before dawn.
func tick(dt: float, player_pos: Vector2, enabled: bool) -> void:
	_event_acc += dt
	if _event_acc < 2.0:
		return
	_event_acc = 0.0
	var ev: Dictionary = world.event_state
	if ev.has("star"):
		var s: Dictionary = ev["star"]
		var x := int(s["x"])
		var y := int(s["y"])
		if world.tile(MP.L_OBJECT, x, y) != content.tid("star_fragment"):
			ev.erase("star")      # collected (quest service reacts to the harvest event)
		elif not world.is_night() and world.day() > int(s["day"]):
			world.set_tile(MP.L_OBJECT, x, y, 0)
			ev.erase("star")
			bus.toast.emit(Loc.t("star_gone"))
			bus.flag_changed.emit("star_event", false)
		return
	if not enabled or not world.is_night() or int(ev.get("star_day", -1)) == world.day():
		return
	ev["star_day"] = world.day()
	if rng.randf() > 0.7:
		return
	var pt := MP.tile_of(player_pos)
	for attempt in 12:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(18.0, 34.0)
		var t := Vector2i(pt.x + int(cos(ang) * dist), pt.y + int(sin(ang) * dist))
		if not world.in_bounds(t.x, t.y) or world.blocked(t.x, t.y):
			continue
		if world.tile(MP.L_OBJECT, t.x, t.y) != 0 or world.plan.site_at_tile(t.x, t.y) != null:
			continue
		world.set_tile(MP.L_OBJECT, t.x, t.y, content.tid("star_fragment"))
		ev["star"] = {"x": t.x, "y": t.y, "day": world.day()}
		bus.toast.emit(Loc.t("star_fell"))
		bus.fx.emit("starfall", MP.tile_center(t), {})
		bus.sfx.emit("magic", MP.tile_center(t))
		bus.flag_changed.emit("star_event", true)
		return
