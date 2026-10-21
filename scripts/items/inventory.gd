class_name Inventory
extends Node
## The player's bag: `capacity` cells, each empty or holding one
## GearDefinition (gear doesn't stack; gold lives in the PlayerProfile).
## Cells keep their place (the inventory screen shows them as a grid).
##
## It also moves items between the bag and `equipment`: equip_from()
## (the item it replaces takes its cell), unequip_to() (into a cell, or the
## first free one), and drop() / drop_equipped() put an item on the floor
## at the owner's feet as a Pickup.
##
## With `persistent`, the cells are saved to the PlayerProfile (resource
## paths, "" for empty) on every change and loaded on ready, like
## Equipment.

signal changed

@export var capacity: int = 24
@export var equipment: Equipment
## Where dropped items land (its feet). Defaults to the parent.
@export var owner_body: Node3D
@export var persistent: bool = true

## One entry per cell: a GearDefinition or null.
var _cells: Array = []


func _ready() -> void:
	if owner_body == null:
		owner_body = get_parent() as Node3D
	_cells.resize(capacity)
	_load_saved()


func item_at(index: int) -> GearDefinition:
	return _cells[index] if index >= 0 and index < _cells.size() else null


## The items (one per cell, null for empty; a copy).
func get_cells() -> Array:
	return _cells.duplicate()


func count() -> int:
	return _cells.size() - _cells.count(null)


func is_full() -> bool:
	return first_free() < 0


## The first empty cell, or -1.
func first_free() -> int:
	return _cells.find(null)


## Puts `item` in the first empty cell; false (and nothing changes) when
## the bag is full.
func add(item: GearDefinition) -> bool:
	var index := first_free()
	if item == null or index < 0:
		return false
	_put(index, item)
	return true


## Empties a cell and returns what was in it.
func remove_at(index: int) -> GearDefinition:
	var item := item_at(index)
	if item:
		_put(index, null)
	return item


## Swaps two cells (moving into an empty one is a swap with nothing).
func move(from: int, to: int) -> void:
	if from == to or item_at(from) == null or to < 0 or to >= _cells.size():
		return
	var moved: GearDefinition = _cells[from]
	_cells[from] = _cells[to]
	_cells[to] = moved
	_changed()


## Equips the item in cell `index` (in `slot`, default: where it goes); the
## item it replaces takes the cell. False when there is nothing to equip
## or it doesn't fit `slot`.
func equip_from(index: int, slot: StringName = &"") -> bool:
	var item := item_at(index)
	if item == null or equipment == null:
		return false
	if slot == &"":
		slot = equipment.slot_for(item)
	if not slot in Equipment.slots_for(item):
		return false
	_cells[index] = null  # Out of the bag first: equip() may hand back the same kind.
	var previous := equipment.equip(item, slot)
	_cells[index] = previous
	_changed()
	return true


## Takes the item off `slot` into cell `index` (default: the first empty
## one). A taken cell is swapped when its item fits the slot. False when
## nothing moved (empty slot, full bag, an item that doesn't fit).
func unequip_to(slot: StringName, index: int = -1) -> bool:
	if equipment == null or equipment.get_item(slot) == null:
		return false
	if index < 0:
		index = first_free()
		if index < 0:
			return false
	var there := item_at(index)
	if there and not slot in Equipment.slots_for(there):
		return false
	_cells[index] = null
	var taken := equipment.unequip(slot)
	if there:
		equipment.equip(there, slot)
	_cells[index] = taken
	_changed()
	return true


## Drops the item in cell `index` at the owner's feet. Returns the pickup.
func drop(index: int) -> Pickup:
	var item := remove_at(index)
	return _spawn(item) if item else null


## Drops what is equipped in `slot` at the owner's feet.
func drop_equipped(slot: StringName) -> Pickup:
	if equipment == null:
		return null
	var item := equipment.unequip(slot)
	return _spawn(item) if item else null


func _spawn(item: GearDefinition) -> Pickup:
	if owner_body == null or not owner_body.is_inside_tree():
		return null
	var container: Node = get_tree().get_first_node_in_group(DropComponent.CONTAINER_GROUP)
	if container == null:
		container = owner_body.get_parent()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var feet := owner_body.global_position
	var pickups := LootSpawner.spawn([[item, 1]], feet + Vector3.UP * 0.8, feet.y, container, rng)
	return pickups[0] if not pickups.is_empty() else null


func _put(index: int, item: GearDefinition) -> void:
	_cells[index] = item
	_changed()


func _changed() -> void:
	_save()
	changed.emit()


func _save() -> void:
	var profile := PlayerProfile.current()
	if not persistent or profile == null or not profile.persists():
		return
	var saved: Array = []
	for item: GearDefinition in _cells:
		saved.append(item.resource_path if item else "")
	profile.set_inventory(saved)


func _load_saved() -> void:
	var profile := PlayerProfile.current()
	if not persistent or profile == null or not profile.persists():
		return
	for i in mini(profile.inventory.size(), _cells.size()):
		var path := String(profile.inventory[i])
		if path != "" and ResourceLoader.exists(path):
			_cells[i] = load(path) as GearDefinition
