class_name Inventory
extends RefCounted
## Slot container. A slot is null or [item_id: String, count: int].
## Direct mutation is only done by InventoryService (transactions).

var slots: Array = []
var content: ContentRegistry
var accept: Array = []     # optional per-slot item type restriction ("" = any)


func _init(size: int, p_content: ContentRegistry) -> void:
	content = p_content
	slots.resize(size)
	accept.resize(size)
	accept.fill("")


static func wrap(p_slots: Array, p_content: ContentRegistry) -> Inventory:
	## View over an existing slot array (chest contents live in ChunkData).
	var inv := Inventory.new(0, p_content)
	inv.slots = p_slots
	inv.accept.resize(p_slots.size())
	inv.accept.fill("")
	return inv


func count(item: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s[0] == item:
			n += int(s[1])
	return n


func totals() -> Dictionary:
	var out := {}
	for s in slots:
		if s != null:
			out[s[0]] = int(out.get(s[0], 0)) + int(s[1])
	return out


func slot_accepts(i: int, item: String) -> bool:
	if accept[i] == "":
		return true
	return content.items.has(item) and content.items[item]["type"] == accept[i]


## Adds into the given slot array; returns leftover that did not fit.
func _add_into(arr: Array, item: String, n: int) -> int:
	var cap := content.max_stack(item)
	if cap <= 0:
		return n
	for i in arr.size():
		if n <= 0:
			break
		var s = arr[i]
		if s != null and s[0] == item and int(s[1]) < cap:
			var put := mini(n, cap - int(s[1]))
			arr[i] = [item, int(s[1]) + put]
			n -= put
	for i in arr.size():
		if n <= 0:
			break
		if arr[i] == null and slot_accepts(i, item):
			var put := mini(n, cap)
			arr[i] = [item, put]
			n -= put
	return n


func _remove_from(arr: Array, item: String, n: int) -> int:
	for i in range(arr.size() - 1, -1, -1):
		if n <= 0:
			break
		var s = arr[i]
		if s != null and s[0] == item:
			var take := mini(n, int(s[1]))
			n -= take
			arr[i] = null if int(s[1]) - take <= 0 else [item, int(s[1]) - take]
	return n


func can_add(item: String, n: int) -> bool:
	return _add_into(slots.duplicate(true), item, n) == 0


func to_array() -> Array:
	return slots.duplicate(true)


func from_array(a: Array) -> void:
	for i in slots.size():
		var s = a[i] if i < a.size() else null
		if s is Array and s.size() == 2 and content.items.has(str(s[0])) and int(s[1]) > 0:
			slots[i] = [str(s[0]), mini(int(s[1]), content.max_stack(str(s[0])))]
		else:
			slots[i] = null
