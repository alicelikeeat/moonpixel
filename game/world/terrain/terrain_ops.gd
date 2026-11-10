class_name TerrainOps
extends RefCounted
## Gameplay operations on terrain: tool hits, harvesting, tilling, planting,
## drops, and resource regrowth scheduling.

const TILLABLE := ["grass", "dirt", "forest_floor", "dry_grass", "marsh_grass", "tundra"]
const PROTECTED_SITES := ["village", "dungeon"]

var content: ContentRegistry
var world: WorldService
var entities: EntityService
var inv: InventoryService
var bus: EventBus
var rng := RandomNumberGenerator.new()


func setup(p_content: ContentRegistry, p_world: WorldService, p_entities: EntityService, p_inv: InventoryService, p_bus: EventBus) -> void:
	content = p_content
	world = p_world
	entities = p_entities
	inv = p_inv
	bus = p_bus


func is_protected(wx: int, wy: int) -> bool:
	if bool(world.rule("god_build")):
		return false
	var s = world.plan.site_at_tile(wx, wy)
	return s != null and PROTECTED_SITES.has(s["type"])


func roll_drops(list: Array) -> Array:
	var mult := float(world.rule("resources"))
	var out: Array = []
	for d in list:
		var n := rng.randi_range(int(d[1]), int(d[2]))
		var f := n * mult
		n = int(f)
		if rng.randf() < f - n:
			n += 1
		if n > 0:
			out.append([d[0], n])
	return out


## Which layer a tool swing would affect at this tile (-1 = nothing).
func hittable_layer(wx: int, wy: int) -> int:
	if world.tile(MP.L_OBJECT, wx, wy) != 0:
		return MP.L_OBJECT
	var s := world.tile(MP.L_STRUCT, wx, wy)
	if s != 0 and content.t_solid[s] != 0:
		return MP.L_STRUCT
	return -1


## Returns {"hit": bool, "broke": bool, "error": String}.
func hit_tile(wx: int, wy: int, tier: int, power: float) -> Dictionary:
	var layer := hittable_layer(wx, wy)
	if layer < 0:
		return {"hit": false, "broke": false, "error": ""}
	var id := world.tile(layer, wx, wy)
	var t: Dictionary = content.tiles[id]
	var god := bool(world.rule("god_build"))
	if not god:
		if int(t.get("hard", 1)) >= 99:
			return {"hit": false, "broke": false, "error": "err_protected"}
		if t.get("natural", 0) == 0 and is_protected(wx, wy):
			return {"hit": false, "broke": false, "error": "err_protected"}
		if layer == MP.L_STRUCT and not bool(world.rule("terrain_edit")):
			return {"hit": false, "broke": false, "error": "err_rule"}
		if int(t.get("tier", 0)) > tier:
			return {"hit": false, "broke": false, "error": "err_tool"}
	var key := Vector3i(wx, wy, layer)
	var dmg := float(world.tile_damage.get(key, 0.0)) + power * (1.0 + tier * 0.5)
	bus.fx.emit("chip", Vector2(wx * MP.TILE + 8, wy * MP.TILE + 8), {"tile": id})
	bus.sfx.emit("chop", Vector2(wx * MP.TILE + 8, wy * MP.TILE + 8))
	if not god and dmg < float(t.get("hard", 1)):
		world.tile_damage[key] = dmg
		return {"hit": true, "broke": false, "error": ""}
	break_tile(wx, wy, layer, true)
	return {"hit": true, "broke": true, "error": ""}


## Remove a tile, spawning its drops (or refunding its build cost).
func break_tile(wx: int, wy: int, layer: int, by_player: bool) -> void:
	var id := world.tile(layer, wx, wy)
	if id == 0:
		return
	var t: Dictionary = content.tiles[id]
	var center := Vector2(wx * MP.TILE + 8, wy * MP.TILE + 8)
	var drops: Array = []
	if t.has("drops"):
		drops = roll_drops(t["drops"])
	elif content.buildable_by_tile.has(t["key"]) and bool(world.rule("build_cost")):
		var cost: Dictionary = content.buildable_by_tile[t["key"]]["cost"]
		for k in cost:
			drops.append([k, int(cost[k])])
	if t.has("container"):
		for s in world.container_at(wx, wy):
			if s != null:
				drops.append([s[0], int(s[1])])
	var after := content.tid(str(t.get("after", "")))
	world.set_tile(layer, wx, wy, after, by_player)
	if t.has("respawn") and t.get("natural", 0) == 1:
		world.schedule(wx, wy, layer, id, float(t["respawn"]) / maxf(0.25, float(world.rule("resources"))), after)
	for d in drops:
		entities.spawn_drop(d[0], d[1], center)
	bus.fx.emit("break", center, {"tile": id})
	bus.sfx.emit("break", center)


## Interact-harvest (berries, ripe crops, fallen stars). Items go straight to
## the inventory; anything that does not fit is dropped on the ground.
func harvest(wx: int, wy: int, into: Inventory) -> bool:
	var id := world.tile(MP.L_OBJECT, wx, wy)
	if id == 0 or not content.tiles[id].has("harvest"):
		return false
	var t: Dictionary = content.tiles[id]
	var drops := roll_drops(t["harvest"]["drops"])
	world.set_tile(MP.L_OBJECT, wx, wy, content.tid(str(t["harvest"]["to"])), true)
	var center := Vector2(wx * MP.TILE + 8, wy * MP.TILE + 8)
	for d in drops:
		var left := inv.give_partial(into, d[0], d[1], "harvest")
		if left > 0:
			entities.spawn_drop(d[0], left, center)
	bus.tile_harvested.emit(wx, wy, str(t["key"]), drops)
	bus.sfx.emit("pickup", center)
	return true


func can_till(wx: int, wy: int) -> bool:
	if not world.in_bounds(wx, wy) or is_protected(wx, wy):
		return false
	if world.tile(MP.L_OBJECT, wx, wy) != 0 or world.tile(MP.L_STRUCT, wx, wy) != 0:
		return false
	return TILLABLE.has(content.tile_key(world.tile(MP.L_GROUND, wx, wy)))


func till(wx: int, wy: int) -> bool:
	if not can_till(wx, wy):
		return false
	world.set_tile(MP.L_DECOR, wx, wy, 0, true)
	world.set_tile(MP.L_GROUND, wx, wy, content.tid("farmland"), true)
	bus.sfx.emit("dig", Vector2(wx * MP.TILE + 8, wy * MP.TILE + 8))
	return true


## Plant a seed item from an inventory. Transactional: the seed is only
## consumed if the crop tile was placed.
func plant(item: String, wx: int, wy: int, from: Inventory) -> bool:
	if not content.items.has(item) or not content.items[item].has("use"):
		return false
	var use: Dictionary = content.items[item]["use"]
	if not use.has("plant") or not world.in_bounds(wx, wy):
		return false
	if world.tile(MP.L_OBJECT, wx, wy) != 0:
		return false
	if content.tile_key(world.tile(MP.L_GROUND, wx, wy)) != str(use.get("on", "farmland")):
		return false
	if not inv.take(from, item, 1):
		return false
	world.set_tile(MP.L_OBJECT, wx, wy, content.tid(use["plant"]), true)
	bus.sfx.emit("dig", Vector2(wx * MP.TILE + 8, wy * MP.TILE + 8))
	return true
