class_name EntityService
extends RefCounted
## EntityService: entity lifecycle, chunk bound activation / dormancy and
## distance graded update tiers.
##
## Invariant (tested): an entity is either active (in `entities`) or stored in
## exactly one chunk's dormant list, never both -> sleeping and waking can not
## duplicate monsters.

const ACTIVE_RADIUS := 2          # chunks around the player that simulate
const NEAR_PX := 22 * 16.0
const MID_PX := 44 * 16.0
const DROP_LIFETIME := 300.0

var content: ContentRegistry
var world: WorldService
var chunks: ChunkService
var bus: EventBus
var entities: Dictionary = {}     # id -> Entity
var actors: Array = []            # player, enemies, animals, npcs
var projectiles: Array = []
var drops: Array = []
var next_id := 1
var active_chunks: Dictionary = {}   # key -> true
var spawn_filter: Callable = Callable()   # (def: Dictionary, spawn_point: Dictionary) -> bool
var rng := RandomNumberGenerator.new()


func setup(p_content: ContentRegistry, p_world: WorldService, p_chunks: ChunkService, p_bus: EventBus) -> void:
	content = p_content
	world = p_world
	chunks = p_chunks
	bus = p_bus


func add(e: Entity) -> Entity:
	if e.id == 0:
		e.id = next_id
		next_id += 1
	else:
		next_id = maxi(next_id, e.id + 1)
	e.prev_pos = e.pos
	entities[e.id] = e
	if e.is_actor():
		actors.append(e)
	elif e.kind == "projectile":
		projectiles.append(e)
	elif e.kind == "drop":
		drops.append(e)
	bus.entity_added.emit(e)
	return e


func get_entity(id: int) -> Entity:
	return entities.get(id)


func _detach(e: Entity) -> void:
	entities.erase(e.id)
	if e.is_actor():
		actors.erase(e)
	elif e.kind == "projectile":
		projectiles.erase(e)
	elif e.kind == "drop":
		drops.erase(e)
	bus.entity_removed.emit(e)


func sweep() -> void:
	for id in entities.keys():
		var e: Entity = entities[id]
		if e.remove:
			_detach(e)


func make_actor(def_id: String, pos: Vector2) -> Entity:
	var d: Dictionary = content.actors[def_id]
	var e := Entity.new()
	e.kind = d["kind"]
	e.def_id = def_id
	e.def = d
	e.pos = pos
	e.home = pos
	e.radius = float(d.get("radius", 6))
	e.max_hp = float(d["hp"])
	e.hp = e.max_hp
	e.max_poise = float(d.get("poise", 0))
	e.poise = e.max_poise
	e.team = Entity.TEAM_HOSTILE if e.kind == "enemy" else Entity.TEAM_WILD
	return e


func spawn_actor(def_id: String, pos: Vector2, site: String = "") -> Entity:
	var e := make_actor(def_id, pos)
	e.site = site
	e.home_chunk = MP.chunk_key(floori(pos.x / MP.CHUNK_PX), floori(pos.y / MP.CHUNK_PX))
	return add(e)


func spawn_drop(item: String, count: int, pos: Vector2, scatter: float = 6.0) -> Entity:
	var e := Entity.new()
	e.kind = "drop"
	e.def_id = item
	e.pos = pos + Vector2(rng.randf_range(-scatter, scatter), rng.randf_range(-scatter, scatter))
	e.radius = 4.0
	e.data = {"item": item, "count": count, "age": 0.0}
	return add(e)


func restore(d: Dictionary) -> Entity:
	var kind := str(d.get("kind", ""))
	var e: Entity
	if kind == "drop":
		e = Entity.new()
		e.kind = "drop"
		e.def_id = str(d.get("def", ""))
		e.radius = 4.0
		if not content.items.has(e.def_id):
			return null
	else:
		if not content.actors.has(str(d.get("def", ""))):
			return null
		e = make_actor(str(d["def"]), Vector2.ZERO)
		e.hp = minf(float(d.get("hp", e.max_hp)), e.max_hp)
		e.phase = int(d.get("phase", 0))
		if bool(d.get("angry", false)):
			e.ai["angry"] = true
	e.id = int(d.get("id", 0))
	if entities.has(e.id):
		return null     # already active: never duplicate
	e.pos = Vector2(float(d.get("x", 0)), float(d.get("y", 0)))
	e.home = Vector2(float(d.get("hx", e.pos.x)), float(d.get("hy", e.pos.y)))
	e.home_chunk = int(d.get("hc", -1))
	e.site = str(d.get("site", ""))
	e.data = d.get("data", {})
	return add(e)


# --- chunk activation -----------------------------------------------------------
func set_active_area(center: Vector2i) -> void:
	var want := {}
	for dy in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
		for dx in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
			var cx := center.x + dx
			var cy := center.y + dy
			if chunks.in_world(cx, cy):
				want[MP.chunk_key(cx, cy)] = true
	for k in active_chunks.keys():
		if not want.has(k):
			_deactivate(k)
	for k in want:
		if not active_chunks.has(k):
			_activate(k)
	chunks.pinned = want


func _activate(k: int) -> void:
	var c := chunks.get_chunk(MP.key_cx(k), MP.key_cy(k))
	active_chunks[k] = true
	world.process_timers(c)
	world.mark_explored(c.cx, c.cy)
	var dormant: Array = c.entities
	c.entities = []
	for d in dormant:
		restore(d)
	var day := world.day()
	var need_spawn := c.spawned_day < 0
	if not need_spawn and day - c.spawned_day >= 2 and dormant.is_empty():
		need_spawn = true
		for e in actors:
			if e.home_chunk == k and e.alive:
				need_spawn = false
				break
	if need_spawn:
		c.spawned_day = day
		if c.spawn_points.is_empty() and c.from_save:
			# saved chunks do not carry generator spawn points; recompute them
			c.spawn_points = chunks.generate_detached(c.cx, c.cy).spawn_points
		for sp in c.spawn_points:
			var d: Dictionary = content.actors[sp["def"]]
			if spawn_filter.is_valid() and not spawn_filter.call(d, sp):
				continue
			var pos := Vector2(float(sp["x"]), float(sp["y"]))
			if world.blocked(floori(pos.x / MP.TILE), floori(pos.y / MP.TILE)):
				continue
			var e := spawn_actor(sp["def"], pos, str(sp.get("site", "")))
			e.home_chunk = k


func _deactivate(k: int) -> void:
	active_chunks.erase(k)
	var c := chunks.peek(MP.key_cx(k), MP.key_cy(k))
	for e in entities.values():
		if e.kind == "player" or e.kind == "npc" or e.remove:
			continue
		var ek := MP.chunk_key(floori(e.pos.x / MP.CHUNK_PX), floori(e.pos.y / MP.CHUNK_PX))
		if ek != k:
			continue
		if e.kind == "projectile" or not e.alive or bool(e.data.get("transient", false)):
			e.remove = true
			_detach(e)
			continue
		if c != null:
			c.entities.append(e.to_dict())
			if c.modified:
				c.dirty = true
		e.remove = true
		_detach(e)


## Move every non-player entity back into chunk storage (world shutdown).
func store_all() -> void:
	for k in active_chunks.keys():
		_deactivate(k)


## Saving while playing: write a snapshot of the active entities into their
## chunks without putting them to sleep. end_save() must follow, otherwise the
## snapshot would be restored as duplicates on the next activation.
func begin_save() -> void:
	for k in active_chunks:
		var c := chunks.peek(MP.key_cx(k), MP.key_cy(k))
		if c != null:
			c.entities = []
	for e in entities.values():
		if e.kind == "player" or e.kind == "npc" or e.kind == "projectile" or e.remove or not e.alive:
			continue
		if bool(e.data.get("transient", false)):
			continue
		var c := chunks.peek(floori(e.pos.x / MP.CHUNK_PX), floori(e.pos.y / MP.CHUNK_PX))
		if c != null and active_chunks.has(c.key()):
			c.entities.append(e.to_dict())
			if c.modified:
				c.dirty = true


func end_save() -> void:
	for k in active_chunks:
		var c := chunks.peek(MP.key_cx(k), MP.key_cy(k))
		if c != null:
			c.entities = []


func tier_of(e: Entity, player_pos: Vector2) -> int:
	var d := e.pos.distance_squared_to(player_pos)
	if d < NEAR_PX * NEAR_PX:
		return 0
	if d < MID_PX * MID_PX:
		return 1
	return 2


func actors_in_circle(center: Vector2, r: float) -> Array:
	var out: Array = []
	for e in actors:
		if e.alive and e.pos.distance_squared_to(center) <= (r + e.radius) * (r + e.radius):
			out.append(e)
	return out


func count_kind(kind: String) -> int:
	var n := 0
	for e in actors:
		if e.kind == kind and e.alive:
			n += 1
	return n
