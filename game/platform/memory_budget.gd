class_name MemoryBudget
extends RefCounted
## Asks the device how much memory it has and derives the limits the open
## world runs with (cached chunks, map survey size, population ceiling).
## The budget can also be set explicitly by the player (override_mb).

const CHUNK_BYTES := 12 * 1024          # layers + bookkeeping, measured upper bound
const MIN_MB := 96
const MAX_AUTO_MB := 2048

var physical_mb := 0
var available_mb := 0
var detected := false
var budget_mb := 256
var max_chunks := 1024
var max_agents := 300
var max_settlements := 12
var override_mb := 0


static func query_device() -> Dictionary:
	var info := OS.get_memory_info()
	var phys := int(info.get("physical", -1))
	var avail := int(info.get("available", -1))
	if avail <= 0:
		avail = int(info.get("free", -1))
	return {"physical_mb": maxi(0, phys / 1048576), "available_mb": maxi(0, avail / 1048576), "ok": phys > 0}


func configure(p_override_mb: int = 0) -> MemoryBudget:
	override_mb = p_override_mb
	var q := query_device()
	physical_mb = q["physical_mb"]
	available_mb = q["available_mb"]
	detected = q["ok"]
	if override_mb > 0:
		budget_mb = maxi(MIN_MB, override_mb)
	elif detected:
		# use at most a quarter of what is free and never more than 1/6 of the device
		var by_avail := available_mb / 4 if available_mb > 0 else physical_mb / 8
		budget_mb = clampi(mini(by_avail, physical_mb / 6), MIN_MB, MAX_AUTO_MB)
	else:
		budget_mb = 256      # unknown device: conservative default
	# 40% of the budget for chunk data, the rest for textures, agents, engine
	max_chunks = clampi(int(budget_mb * 1048576.0 * 0.4 / CHUNK_BYTES), 256, 60000)
	max_agents = clampi(budget_mb, 150, 1200)
	max_settlements = clampi(max_chunks / 24, 6, 200)
	return self


func used_mb() -> int:
	return int(OS.get_static_memory_usage() / 1048576)


## > 1.0 means the process is above its budget and caches must shrink.
func pressure() -> float:
	return float(used_mb()) / float(maxi(1, budget_mb))


func describe() -> String:
	return "device %d MB (free %d MB) · budget %d MB%s · chunk cache %d · NPC cap %d" % [physical_mb, available_mb, budget_mb,
		" (manual)" if override_mb > 0 else "", max_chunks, max_agents]
