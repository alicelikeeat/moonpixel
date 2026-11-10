extends TestCase


func test_content_loads_without_errors() -> void:
	var c := ContentRegistry.new()
	c.load_all()
	eq(c.errors, [], "content validation errors")


func test_minimum_content_scale() -> void:
	var c := ContentRegistry.shared()
	var usable := 0
	for id in c.items:
		var it: Dictionary = c.items[id]
		if it.has("use") or it.has("weapon") or it.has("armor") or it.has("trinket"):
			usable += 1
	var craftable := {}
	for id in c.recipes:
		craftable[c.recipes[id]["out"][0]] = true
	ok(usable + craftable.size() >= 30, "30+ usable or craftable items")
	ok(c.buildables.size() + c.props.size() >= 20, "20+ build pieces")
	ok(c.quests.size() >= 10, "10+ quests")
	var classes := {}
	for id in c.items:
		if c.items[id].has("weapon"):
			classes[c.items[id]["weapon"]["class"]] = true
	for k in ["sword", "bow", "staff", "tool"]:
		ok(classes.has(k), "weapon class " + k)
	var behaviors := {}
	for id in c.actors:
		behaviors[c.actors[id]["behavior"]] = true
	for k in ["melee", "ranged", "patrol", "elite", "boss"]:
		ok(behaviors.has(k), "behavior " + k)
	var roles := {}
	for id in c.npcs:
		roles[c.npcs[id]["role"]] = true
	eq(roles.size(), 3, "three npc roles")
	var groups := {}
	for b in c.biomes:
		groups[b["group"]] = true
	for k in ["temperate", "snow", "desert", "wetland"]:
		ok(groups.has(k), "biome group " + k)


func test_tile_ids_are_stable_contract() -> void:
	var c := ContentRegistry.shared()
	# spot checks: these ids are persisted in chunk files
	eq(c.tid("grass"), 5)
	eq(c.tid("water"), 2)
	eq(c.tid("tree_oak"), 40)
	eq(c.tid("chest"), 69)
	eq(c.tid("wall_wood"), 60)


func test_every_quest_is_bound_to_world() -> void:
	var c := ContentRegistry.shared()
	var cats := {}
	for id in c.quests:
		var q: Dictionary = c.quests[id]
		ok(q.has("site") and str(q["site"]) != "", id + " has a world site")
		ok(q.get("effects", []).size() > 0, id + " has world feedback")
		cats[q["category"]] = true
	for k in ["guide", "explore", "gather", "build", "combat", "event"]:
		ok(cats.has(k), "quest category " + k)
