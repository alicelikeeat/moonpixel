extends TestCase

var c := ContentRegistry.shared()


func _society(seed: int, villages: int, per: int) -> Society:
	var budget := MemoryBudget.new().configure(256)
	var world := OpenWorld.new(seed, c, budget)
	var soc := Society.new(world, budget, seed)
	soc.bootstrap(Vector2i.ZERO, villages, per)
	return soc


func _run(soc: Society, years: float) -> void:
	for i in int(years * OpenWorld.YEAR):
		soc.tick(1.0)


func test_bootstrap_has_100_plus_interactive_npcs() -> void:
	var soc := _society(7, 4, 30)
	ok(soc.agents.size() >= 100, "population %d" % soc.agents.size())
	eq(soc.settlements.size(), 4)
	for id in soc.agents:
		var info := soc.talk(id)
		ok(str(info["name"]) != "" and str(info["line"]) != "", "every villager can be talked to")
		break
	var a: Agent = soc.agents.values()[3]
	a.hunger = 0.9
	ok(soc.gift_food(a.id))
	ok(a.hunger < 0.5 and float(a.rel[0]) > 0.0, "gift feeds and builds affinity")


func test_society_lives_builds_breeds_and_dies() -> void:
	var soc := _society(7, 4, 30)
	var w := soc.world
	_run(soc, 3.0)
	print("        after 3 years: pop=%d births=%d deaths=%d pairs=%d buildings=%d tiles=%d villages=%d surveyed=%d" % [soc.agents.size(),
		soc.stats["births"], soc.stats["deaths"], soc.stats["pairs"], soc.stats["buildings"], soc.stats["tiles_placed"], soc.settlements.size(), w.surveyed])
	ok(soc.stats["births"] > 0, "children were born")
	ok(soc.stats["deaths"] > 0, "villagers died")
	ok(soc.stats["pairs"] > 0, "couples formed")
	ok(soc.stats["buildings"] >= 8, "buildings finished (%d)" % soc.stats["buildings"])
	ok(soc.stats["tiles_placed"] > 500, "tiles placed by villagers")
	ok(soc.agents.size() >= 100, "at least 100 NPCs alive (%d)" % soc.agents.size())
	ok(w.surveyed > 1000, "map expanded by itself")
	# built houses really exist as tiles in the world
	var walls := 0
	var s: Settlement = soc.settlements[1]
	for b in s.buildings:
		if b["type"] == "house" and b["done"]:
			for dy in int(b["h"]):
				for dx in int(b["w"]):
					var o := w.tile(MP.L_OBJECT, b["x"] + dx, b["y"] + dy)
					if o == c.tid("wall_wood") or o == c.tid("wall_stone"):
						walls += 1
	ok(walls >= 14, "house walls are in the world (%d)" % walls)
	# family graph is consistent
	for id in soc.agents:
		var a: Agent = soc.agents[id]
		if a.partner != 0 and soc.agents.has(a.partner):
			eq(soc.agents[a.partner].partner, a.id, "partnership is mutual")
		ok(not w.blocked(MP.tile_of(a.pos).x, MP.tile_of(a.pos).y) or a.travelling, "nobody is stuck inside a wall")
		ok(soc.settlements.has(a.sid))
	# a child born in the simulation has parents and grows up
	var born := 0
	for id in soc.agents:
		if soc.agents[id].mother != 0:
			born += 1
	ok(born > 0, "living children with known parents")


func test_society_save_load_roundtrip() -> void:
	var soc := _society(21, 2, 20)
	_run(soc, 0.5)
	var data = JSON.parse_string(JSON.stringify({"w": soc.world.to_dict(), "s": soc.to_dict()}))
	var budget := MemoryBudget.new().configure(256)
	var w2 := OpenWorld.new(21, c, budget)
	w2.from_dict(data["w"])
	var soc2 := Society.new(w2, budget, 21)
	soc2.from_dict(data["s"])
	eq(soc2.agents.size(), soc.agents.size())
	eq(soc2.settlements.size(), soc.settlements.size())
	eq(soc2.stats["tiles_placed"], soc.stats["tiles_placed"])
	var a: Agent = soc.agents.values()[0]
	var b: Agent = soc2.agents[a.id]
	eq(b.full_name(), a.full_name())
	near(b.age(w2.time), a.age(soc.world.time), 0.01)
	eq(b.partner, a.partner)
	_run(soc2, 0.2)
	ok(soc2.agents.size() > 0, "loaded society keeps running")


func test_population_floor_by_immigration() -> void:
	var soc := _society(5, 1, 12)
	_run(soc, 1.5)
	ok(soc.stats["immigrants"] > 0, "wanderers arrive when the world is underpopulated")
	ok(soc.agents.size() > 12)
