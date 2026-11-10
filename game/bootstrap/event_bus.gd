class_name EventBus
extends RefCounted
## Bounded cross-module event channel. Only the signals declared here may be
## used for cross-module communication; payloads are plain data.
## All signals are emitted on the main (simulation) thread.

signal item_gained(item_id: String, count: int, source: String)
signal item_crafted(recipe_id: String, item_id: String, count: int)
signal tile_changed(x: int, y: int, layer: int, old_id: int, new_id: int, by_player: bool)
signal tile_harvested(x: int, y: int, tile_key: String, drops: Array)
signal chunk_changed(cx: int, cy: int)
signal props_changed(cx: int, cy: int)
signal entity_added(entity)
signal entity_removed(entity)
signal entity_died(entity, killer)
signal entity_damaged(entity, amount: float, source)
signal site_discovered(site_id: String)
signal container_opened(x: int, y: int)
signal quest_changed(quest_id: String, state: String)
signal flag_changed(key: String, value)
signal toast(text: String)
signal fx(kind: String, pos: Vector2, data: Dictionary)
signal sfx(name: String, pos: Vector2)
signal player_respawned()
signal boss_state(state: String, entity)
signal weather_changed(kind: String)
