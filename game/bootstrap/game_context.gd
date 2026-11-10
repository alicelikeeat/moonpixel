class_name GameContext
extends RefCounted
## Composition root for one loaded world. Owns every service and wires their
## dependencies explicitly; modules talk through these service interfaces and
## the EventBus, never by reaching into each other's internal state.
## See docs/architecture/overview.md for the dependency graph.

var bus: EventBus
var content: ContentRegistry
var config: WorldConfig
var plan: WorldPlan
var world: WorldService
var chunks: ChunkService
var entities: EntityService
var combat: CombatService
var ai: ActorAI
var inventory: InventoryService
var terrain: TerrainOps
var crafting: CraftingService
var build: BuildService
var npcs: NpcService
var ecology: EcologyService
var quests: QuestService
var save: SaveService
var player: PlayerController
var sim: Simulation
var artisan: WorldArtisan
var rng := RandomNumberGenerator.new()
var load_notes: Array = []
var play_seconds := 0.0


static func _wire(cfg: WorldConfig, save_root: String) -> GameContext:
	var c := GameContext.new()
	c.config = cfg
	c.content = ContentRegistry.shared()
	c.bus = EventBus.new()
	c.rng.seed = cfg.seed ^ 0x5bd1e995
	c.plan = WorldPlan.new().build(cfg.seed, cfg.size, c.content)
	c.chunks = ChunkService.new()
	c.chunks.setup(cfg, c.content, c.plan)
	c.chunks.bus = c.bus
	c.world = WorldService.new()
	c.world.setup(cfg, c.content, c.plan, c.chunks, c.bus)
	c.save = SaveService.new()
	c.save.root = save_root
	c.entities = EntityService.new()
	c.entities.setup(c.content, c.world, c.chunks, c.bus)
	c.entities.rng.seed = c.rng.randi()
	c.inventory = InventoryService.new(c.content, c.bus)
	c.combat = CombatService.new()
	c.combat.setup(c.content, c.world, c.entities, c.bus)
	c.combat.rng.seed = c.rng.randi()
	c.ai = ActorAI.new()
	c.ai.setup(c.content, c.world, c.entities, c.combat, c.bus)
	c.ai.rng.seed = c.rng.randi()
	c.terrain = TerrainOps.new()
	c.terrain.setup(c.content, c.world, c.entities, c.inventory, c.bus)
	c.terrain.rng.seed = c.rng.randi()
	c.crafting = CraftingService.new()
	c.crafting.setup(c.content, c.world, c.inventory, c.bus)
	c.build = BuildService.new()
	c.build.setup(c.content, c.world, c.entities, c.inventory, c.terrain, c.bus)
	c.player = PlayerController.new()
	c.player.setup(c.content, c.world, c.entities, c.combat, c.inventory, c.terrain, c.bus)
	c.npcs = NpcService.new()
	c.npcs.setup(c.content, c.world, c.entities, c.inventory, c.bus)
	c.ecology = EcologyService.new()
	c.ecology.setup(c.content, c.world, c.entities, c.bus)
	c.ecology.rng.seed = c.rng.randi()
	c.quests = QuestService.new()
	c.quests.setup(c.content, c.world, c.entities, c.inventory, c.bus, c.npcs, c.player)
	c.npcs.quests = c.quests
	c.artisan = WorldArtisan.new()
	c.artisan.setup(c.content, c.world, c.build, c.terrain)
	c.sim = Simulation.new(c)
	return c


## Create a brand new world. Returns null if the seed cannot produce a valid
## world (plan.errors explains why).
static func create_world(cfg: WorldConfig, save_root: String = "user://worlds") -> GameContext:
	var c := _wire(cfg, save_root)
	if not c.plan.valid:
		return null
	c.save.open(cfg.id)
	c.chunks.save = c.save
	c.npcs.init_new_world()
	var spawn := MP.tile_center(c.world.find_free_near(c.plan.spawn_tile, 6))
	c.player.spawn_at(spawn)
	c.player.give_starting_kit()
	c.player.noclip = false
	c.world.discover("spawn")
	c.quests.refresh()
	c.sim.tick(0.0)
	return c


## Returns {"ok", "ctx", "error", "backup_available", "notes"}.
static func load_world(world_id: String, save_root: String = "user://worlds") -> Dictionary:
	var probe := SaveService.new()
	probe.root = save_root
	probe.open(world_id)
	var res := probe.load_index()
	if not res["ok"]:
		return {"ok": false, "ctx": null, "error": res["error"], "backup_available": res["backup_available"], "notes": probe.notes}
	var d: Dictionary = res["data"]
	var cfg := WorldConfig.from_dict(d["config"])
	if cfg.generator_version > MP.GENERATOR_VERSION:
		return {"ok": false, "ctx": null, "error": "err_newer", "backup_available": false, "notes": probe.notes}
	cfg.id = world_id
	var c := _wire(cfg, save_root)
	c.save = probe
	c.chunks.save = probe
	c.load_notes = probe.notes.duplicate()
	if int(res["migrated_from"]) > 0:
		c.load_notes.append("save migrated from format %d" % int(res["migrated_from"]))
	c.world.from_dict(d.get("world", {}))
	c.npcs.from_dict(d.get("npcs", {}))
	c.entities.next_id = maxi(1, int(d.get("next_entity_id", 1)))
	c.player.entity.id = 0
	c.player.spawn_at(Vector2.ZERO)
	c.player.from_dict(d.get("player", {}))
	c.quests.from_dict(d.get("quests", {}))
	c.play_seconds = float(d.get("play_seconds", 0.0))
	c.build.custom_props = d.get("custom_props", {})
	if not c.plan.valid:
		# a pinned world must stay loadable even if today's generator would reject the seed
		c.load_notes.append("world plan reported: " + str(c.plan.errors))
	var t := MP.tile_of(c.player.entity.pos)
	if c.world.blocked(t.x, t.y):
		c.player.entity.pos = MP.tile_center(c.world.find_free_near(t, 10))
		c.player.entity.prev_pos = c.player.entity.pos
	c.quests.refresh()
	c.sim.tick(0.0)
	return {"ok": true, "ctx": c, "error": "", "backup_available": res["backup_available"], "notes": c.load_notes}


func index_snapshot() -> Dictionary:
	return {
		"format": MP.SAVE_FORMAT,
		"generator_version": config.generator_version,
		"config": config.to_dict(),
		"world": world.to_dict(),
		"player": player.to_dict(),
		"quests": quests.to_dict(),
		"npcs": npcs.to_dict(),
		"next_entity_id": entities.next_id,
		"play_seconds": play_seconds,
		"custom_props": build.custom_props.duplicate(true),
	}


## Transactional save of everything (safe to call while playing).
func save_game() -> bool:
	entities.begin_save()
	var ok := save.save_world(index_snapshot(), chunks.dirty_chunks())
	entities.end_save()
	chunks.evict()
	return ok


func close() -> void:
	entities.store_all()
