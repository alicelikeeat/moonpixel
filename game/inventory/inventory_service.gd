class_name InventoryService
extends RefCounted
## InventoryService: every item movement, consumption and crafting step is a
## transaction: it is validated against copies of the affected inventories and
## only then swapped in. A failed transaction changes nothing, which rules out
## duplication and loss bugs by construction.

var content: ContentRegistry
var bus: EventBus


class Txn:
	var ops: Array = []      # [inventory, item, delta]

	func add(inv: Inventory, item: String, n: int) -> Txn:
		if n > 0:
			ops.append([inv, item, n])
		return self

	func remove(inv: Inventory, item: String, n: int) -> Txn:
		if n > 0:
			ops.append([inv, item, -n])
		return self


func _init(p_content: ContentRegistry, p_bus: EventBus) -> void:
	content = p_content
	bus = p_bus


func begin() -> Txn:
	return Txn.new()


## Atomic commit: all removals, then all additions, on shadow copies.
func commit(txn: Txn) -> bool:
	var shadow := {}
	for op in txn.ops:
		var inv: Inventory = op[0]
		if not shadow.has(inv):
			shadow[inv] = inv.slots.duplicate(true)
	for op in txn.ops:
		if op[2] < 0:
			if not content.items.has(op[1]):
				return false
			if op[0]._remove_from(shadow[op[0]], op[1], -op[2]) != 0:
				return false
	for op in txn.ops:
		if op[2] > 0:
			if not content.items.has(op[1]):
				return false
			if op[0]._add_into(shadow[op[0]], op[1], op[2]) != 0:
				return false
	for inv in shadow:
		var src: Array = shadow[inv]
		for i in inv.slots.size():
			inv.slots[i] = src[i]
	return true


func give(inv: Inventory, item: String, n: int, source: String = "") -> bool:
	if not commit(begin().add(inv, item, n)):
		return false
	if bus != null:
		bus.item_gained.emit(item, n, source)
	return true


## Adds as much as fits, returns the leftover count (used for pickups).
func give_partial(inv: Inventory, item: String, n: int, source: String = "") -> int:
	if not content.items.has(item):
		return n
	var shadow := inv.slots.duplicate(true)
	var left := inv._add_into(shadow, item, n)
	for i in inv.slots.size():
		inv.slots[i] = shadow[i]
	if n - left > 0 and bus != null:
		bus.item_gained.emit(item, n - left, source)
	return left


func take(inv: Inventory, item: String, n: int) -> bool:
	return commit(begin().remove(inv, item, n))


func has_all(inv: Inventory, cost: Dictionary, mult: int = 1) -> bool:
	for k in cost:
		if inv.count(k) < int(cost[k]) * mult:
			return false
	return true


## Move/merge/swap between two slots (possibly of two inventories). Atomic.
func move_slot(a: Inventory, ia: int, b: Inventory, ib: int, amount: int = -1) -> bool:
	if ia < 0 or ib < 0 or ia >= a.slots.size() or ib >= b.slots.size():
		return false
	if a == b and ia == ib:
		return false
	var sa = a.slots[ia]
	var sb = b.slots[ib]
	if sa == null:
		return false
	if not b.slot_accepts(ib, sa[0]):
		return false
	var n := int(sa[1]) if amount < 0 else mini(amount, int(sa[1]))
	if n <= 0:
		return false
	if sb == null:
		b.slots[ib] = [sa[0], n]
		a.slots[ia] = null if n == int(sa[1]) else [sa[0], int(sa[1]) - n]
		return true
	if sb[0] == sa[0]:
		var cap := content.max_stack(sa[0])
		var put := mini(n, cap - int(sb[1]))
		if put <= 0:
			return false
		b.slots[ib] = [sb[0], int(sb[1]) + put]
		a.slots[ia] = null if put == int(sa[1]) else [sa[0], int(sa[1]) - put]
		return true
	# swap (only whole stacks, and only if both slots accept)
	if n != int(sa[1]) or not a.slot_accepts(ia, sb[0]):
		return false
	a.slots[ia] = sb
	b.slots[ib] = sa
	return true


## Move a whole slot into any free space of another inventory (shift-click).
func quick_move(a: Inventory, ia: int, b: Inventory) -> bool:
	var sa = a.slots[ia]
	if sa == null:
		return false
	var shadow := b.slots.duplicate(true)
	var left := b._add_into(shadow, sa[0], int(sa[1]))
	if left == int(sa[1]):
		return false
	for i in b.slots.size():
		b.slots[i] = shadow[i]
	a.slots[ia] = null if left == 0 else [sa[0], left]
	return true
