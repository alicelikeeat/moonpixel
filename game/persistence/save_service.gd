class_name SaveService
extends RefCounted
## SaveService: world index (world.json) + one file per modified chunk.
##
## Durability model
##  * every file is written as <name>.tmp, read back and verified, the previous
##    version is kept as <name>.bak, then the tmp file is renamed into place;
##  * a world save is a transaction: all tmp files are written first, then a
##    journal (the commit point) is written, then files are promoted and the
##    journal removed;
##  * on open, a present journal is rolled forward; without a journal all
##    stray tmp files are discarded -> the world is always at the most recent
##    completed save point after a forced quit;
##  * corrupt files fall back to .bak; corrupt chunks without backup are
##    quarantined as .corrupt (never deleted) and regenerated from the seed.
##
## Main-thread only.

const INDEX := "world.json"
const JOURNAL := "journal.json"

var root := "user://worlds"
var world_id := ""
var dir := ""
var saved_chunks: Dictionary = {}       # chunk key -> true
var last_error := ""
var notes: Array = []                   # human readable recovery notes
## Test hook: abort a transaction at a given stage to simulate a crash.
## "" | "before_journal" | "after_journal" | "mid_promote"
var crash_at := ""


func open(p_world_id: String) -> void:
	world_id = p_world_id
	dir = root.path_join(world_id)
	DirAccess.make_dir_recursive_absolute(dir.path_join("chunks"))
	_recover()
	_scan_chunks()


static func _md5(b: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(b)
	return ctx.finish()


static func _write_tmp(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.flush()
	f.close()
	var back := FileAccess.get_file_as_bytes(path + ".tmp")
	return back.size() == bytes.size() and _md5(back) == _md5(bytes)


static func _promote(path: String) -> bool:
	if not FileAccess.file_exists(path + ".tmp"):
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


static func atomic_write(path: String, bytes: PackedByteArray) -> bool:
	return _write_tmp(path, bytes) and _promote(path)


func _chunk_path(cx: int, cy: int) -> String:
	return dir.path_join("chunks").path_join("c_%d_%d.bin" % [cx, cy])


func _scan_chunks() -> void:
	saved_chunks.clear()
	var d := DirAccess.open(dir.path_join("chunks"))
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("c_") and (f.ends_with(".bin") or f.ends_with(".bin.bak")):
			var parts := f.split(".")[0].split("_")
			if parts.size() == 3:
				saved_chunks[MP.chunk_key(int(parts[1]), int(parts[2]))] = true


func _all_files(sub: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir.path_join(sub))
	if d != null:
		for f in d.get_files():
			out.append(dir.path_join(sub).path_join(f))
	return out


## Crash recovery, see class comment.
func _recover() -> void:
	var jpath := dir.path_join(JOURNAL)
	if FileAccess.file_exists(jpath):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(jpath))
		if parsed is Dictionary and parsed.get("files") is Array:
			var n := 0
			for rel in parsed["files"]:
				var p := dir.path_join(str(rel))
				if FileAccess.file_exists(p + ".tmp"):
					if _promote(p):
						n += 1
			notes.append("recovered interrupted save (%d files rolled forward)" % n)
		DirAccess.remove_absolute(jpath)
	for p in _all_files("") + _all_files("chunks"):
		if p.ends_with(".tmp"):
			DirAccess.remove_absolute(p)


func has_chunk(cx: int, cy: int) -> bool:
	return saved_chunks.has(MP.chunk_key(cx, cy))


func load_chunk(cx: int, cy: int) -> ChunkData:
	var p := _chunk_path(cx, cy)
	if FileAccess.file_exists(p):
		var c := ChunkData.from_bytes(FileAccess.get_file_as_bytes(p))
		if c != null and c.cx == cx and c.cy == cy:
			return c
		# quarantine, never delete
		DirAccess.rename_absolute(p, p + ".corrupt")
		notes.append("chunk %d,%d corrupt -> quarantined" % [cx, cy])
	if FileAccess.file_exists(p + ".bak"):
		var c := ChunkData.from_bytes(FileAccess.get_file_as_bytes(p + ".bak"))
		if c != null and c.cx == cx and c.cy == cy:
			notes.append("chunk %d,%d restored from backup" % [cx, cy])
			c.dirty = true
			return c
	saved_chunks.erase(MP.chunk_key(cx, cy))
	return null


func save_chunk(c: ChunkData) -> bool:
	if dir == "":
		return false
	if not atomic_write(_chunk_path(c.cx, c.cy), c.to_bytes()):
		last_error = "chunk write failed"
		return false
	c.dirty = false
	saved_chunks[c.key()] = true
	return true


## Transactional world save: index + every dirty chunk.
func save_world(index: Dictionary, dirty: Array) -> bool:
	if dir == "":
		return false
	index["format"] = MP.SAVE_FORMAT
	index["content_version"] = ContentRegistry.CONTENT_VERSION
	index["app_version"] = "1.0.0"
	index["saved_at"] = Time.get_datetime_string_from_system(true)
	var files: Array = []
	for c in dirty:
		var p := _chunk_path(c.cx, c.cy)
		if not _write_tmp(p, c.to_bytes()):
			last_error = "chunk write failed"
			_discard_tmp(files)
			return false
		files.append("chunks/c_%d_%d.bin" % [c.cx, c.cy])
	var ipath := dir.path_join(INDEX)
	if not _write_tmp(ipath, JSON.stringify(index, "\t").to_utf8_buffer()):
		last_error = "index write failed"
		_discard_tmp(files)
		return false
	files.append(INDEX)
	if crash_at == "before_journal":
		return false
	# commit point
	if not atomic_write(dir.path_join(JOURNAL), JSON.stringify({"files": files}).to_utf8_buffer()):
		last_error = "journal write failed"
		_discard_tmp(files)
		return false
	if crash_at == "after_journal":
		return false
	var n := 0
	for rel in files:
		_promote(dir.path_join(str(rel)))
		n += 1
		if crash_at == "mid_promote" and n == 1:
			return false
	DirAccess.remove_absolute(dir.path_join(JOURNAL))
	if FileAccess.file_exists(dir.path_join(JOURNAL) + ".bak"):
		DirAccess.remove_absolute(dir.path_join(JOURNAL) + ".bak")
	for c in dirty:
		c.dirty = false
		saved_chunks[c.key()] = true
	return true


func _discard_tmp(files: Array) -> void:
	for rel in files:
		DirAccess.remove_absolute(dir.path_join(str(rel)) + ".tmp")
	DirAccess.remove_absolute(dir.path_join(INDEX) + ".tmp")


static func _parse_index(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and parsed.has("format") and parsed.get("config") is Dictionary and parsed.get("player") is Dictionary:
		return parsed
	return null


## Returns {"ok", "data", "error", "backup_available", "migrated_from"}.
## Never modifies or deletes a damaged index; restore_backup() is explicit.
func load_index() -> Dictionary:
	var ipath := dir.path_join(INDEX)
	var d = _parse_index(ipath)
	var bak_ok := _parse_index(ipath + ".bak") != null
	if d == null:
		last_error = "err_corrupt"
		return {"ok": false, "data": {}, "error": "err_corrupt", "backup_available": bak_ok, "migrated_from": 0}
	var from := int(d.get("format", 0))
	if from < MP.SAVE_FORMAT and from > 0:
		# keep the pre-migration file forever
		var keep := ipath + ".v%d.bak" % from
		if not FileAccess.file_exists(keep):
			DirAccess.copy_absolute(ipath, keep)
	var res := SaveMigrations.migrate(d)
	if not res["ok"]:
		last_error = res["error"]
		return {"ok": false, "data": {}, "error": res["error"], "backup_available": bak_ok, "migrated_from": from}
	return {"ok": true, "data": res["data"], "error": "", "backup_available": bak_ok, "migrated_from": from if from < MP.SAVE_FORMAT else 0}


## Replace a damaged index with the previous completed save. The damaged file
## is kept as world.json.corrupt.
func restore_backup() -> bool:
	var ipath := dir.path_join(INDEX)
	if _parse_index(ipath + ".bak") == null:
		return false
	if FileAccess.file_exists(ipath):
		if FileAccess.file_exists(ipath + ".corrupt"):
			DirAccess.remove_absolute(ipath + ".corrupt")
		DirAccess.rename_absolute(ipath, ipath + ".corrupt")
	return DirAccess.copy_absolute(ipath + ".bak", ipath) == OK


## Lightweight listing for the world menu.
static func list_worlds(p_root: String = "user://worlds") -> Array:
	var out: Array = []
	var d := DirAccess.open(p_root)
	if d == null:
		return out
	for id in d.get_directories():
		var ipath := p_root.path_join(id).path_join(INDEX)
		var parsed = _parse_index(ipath)
		var entry := {"id": id, "ok": parsed != null, "name": id, "saved_at": "", "preset": "", "size": 0, "seed": 0,
			"backup": _parse_index(ipath + ".bak") != null}
		if parsed != null:
			var cfg: Dictionary = parsed["config"]
			entry["name"] = str(cfg.get("name", id))
			entry["saved_at"] = str(parsed.get("saved_at", ""))
			entry["preset"] = str(cfg.get("preset", ""))
			entry["size"] = int(cfg.get("size", 0))
			entry["seed"] = int(cfg.get("seed", 0))
		elif not FileAccess.file_exists(ipath) and not entry["backup"]:
			continue
		out.append(entry)
	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return out


## Explicit user action only (menu "Delete"). Removes one world directory.
static func delete_world(p_root: String, id: String) -> void:
	var base := p_root.path_join(id)
	for sub in ["chunks", "assets", ""]:
		var d := DirAccess.open(base.path_join(sub))
		if d != null:
			for f in d.get_files():
				d.remove(f)
	DirAccess.remove_absolute(base.path_join("chunks"))
	DirAccess.remove_absolute(base.path_join("assets"))
	DirAccess.remove_absolute(base)
