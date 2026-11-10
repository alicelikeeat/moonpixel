class_name CraftingService
extends RefCounted
## Recipes, stations and upgrades. Crafting is a single inventory transaction.

var content: ContentRegistry
var world: WorldService
var inv: InventoryService
var bus: EventBus


func setup(p_content: ContentRegistry, p_world: WorldService, p_inv: InventoryService, p_bus: EventBus) -> void:
	content = p_content
	world = p_world
	inv = p_inv
	bus = p_bus


## Crafting stations within reach of a world position.
func stations_near(pos: Vector2, reach_tiles: int = 3) -> Dictionary:
	var out := {"": true}
	var t := MP.tile_of(pos)
	for dy in range(-reach_tiles, reach_tiles + 1):
		for dx in range(-reach_tiles, reach_tiles + 1):
			var o := world.tile(MP.L_OBJECT, t.x + dx, t.y + dy)
			if o != 0 and content.tiles[o].has("station"):
				out[str(content.tiles[o]["station"])] = true
	return out


func can_craft(recipe_id: String, bag: Inventory, stations: Dictionary) -> bool:
	if not content.recipes.has(recipe_id):
		return false
	var r: Dictionary = content.recipes[recipe_id]
	if not stations.has(str(r.get("station", ""))):
		return false
	return inv.has_all(bag, r["in"])


func craft(recipe_id: String, bag: Inventory, stations: Dictionary) -> bool:
	if not can_craft(recipe_id, bag, stations):
		return false
	var r: Dictionary = content.recipes[recipe_id]
	var txn := inv.begin()
	for k in r["in"]:
		txn.remove(bag, k, int(r["in"][k]))
	txn.add(bag, r["out"][0], int(r["out"][1]))
	if not inv.commit(txn):
		bus.toast.emit(Loc.t("err_full"))
		return false
	bus.item_crafted.emit(recipe_id, r["out"][0], int(r["out"][1]))
	bus.item_gained.emit(r["out"][0], int(r["out"][1]), "craft")
	bus.sfx.emit("craft", Vector2.ZERO)
	return true
