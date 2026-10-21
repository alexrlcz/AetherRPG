class_name Equipment
extends Node
## What a character wears and wields: one GearDefinition per slot (SLOTS:
## head, neck, shoulders, chest, cloak, wrists, gloves, legs, boots, two
## rings, trinket, main hand, off hand). It is the one source of truth for
## gear; every change is passed on:
## - `appearance`: the worn items with a visual (outfit pieces, helmet,
##   shield) become its appearance's `gear`, and it is re-applied;
## - `stats`: every item's modifiers are the &"gear" modifiers;
## - `weapon`: the main-hand WeaponDefinition (or `default_weapon` while the
##   main hand is empty) is equipped.
## With `persistent`, the slots are saved to the PlayerProfile (resource
## paths) on every change and loaded on ready, so gear is kept across runs
## and sessions; a fresh profile starts with `starting_items`. Under test
## suites and tools the profile doesn't persist (PlayerProfile.persists()),
## so every new player starts fresh.
##
## Keep this node after the appearance, stats and weapon nodes: it applies
## in its _ready(), once they are ready.

signal changed(slot: StringName, item: GearDefinition, previous: GearDefinition)

const SLOTS: Array[StringName] = [&"head", &"neck", &"shoulders", &"chest", &"back", &"wrists",
	&"hands", &"legs", &"feet", &"ring_1", &"ring_2", &"trinket", &"main_hand", &"off_hand"]
## The equipment slots each item slot fits.
const SLOTS_OF := {
	GearDefinition.Slot.HEAD: [&"head"], GearDefinition.Slot.NECK: [&"neck"],
	GearDefinition.Slot.SHOULDERS: [&"shoulders"], GearDefinition.Slot.CHEST: [&"chest"],
	GearDefinition.Slot.BACK: [&"back"], GearDefinition.Slot.WRISTS: [&"wrists"],
	GearDefinition.Slot.HANDS: [&"hands"], GearDefinition.Slot.LEGS: [&"legs"],
	GearDefinition.Slot.FEET: [&"feet"], GearDefinition.Slot.RING: [&"ring_1", &"ring_2"],
	GearDefinition.Slot.TRINKET: [&"trinket"], GearDefinition.Slot.MAIN_HAND: [&"main_hand"],
	GearDefinition.Slot.OFF_HAND: [&"off_hand"],
}
## Slot names for menus.
const SLOT_NAMES := {
	&"head": "Head", &"neck": "Neck", &"shoulders": "Shoulders", &"chest": "Chest", &"back": "Cloak",
	&"wrists": "Wrists", &"hands": "Gloves", &"legs": "Legs", &"feet": "Boots", &"ring_1": "Ring 1",
	&"ring_2": "Ring 2", &"trinket": "Trinket", &"main_hand": "Main hand", &"off_hand": "Off hand",
}
## CharacterStats source of the items' modifiers.
const STATS_SOURCE := &"gear"

@export var appearance: AppearanceComponent
@export var stats: CharacterStats
@export var weapon: WeaponComponent
## Wielded while the main hand is empty.
@export var default_weapon: WeaponDefinition
## Worn when nothing was saved yet (a fresh profile, tests).
@export var starting_items: Array[GearDefinition] = []
## Saves to and loads from the PlayerProfile.
@export var persistent: bool = true

## Slot -> item (empty slots are absent).
var _items: Dictionary = {}


func _ready() -> void:
	if appearance and appearance.appearance:
		# Its own copy: the .tres on disk (shared with other scenes) stays as is.
		appearance.appearance = appearance.appearance.duplicate()
	if not _load_saved():
		for item in starting_items:
			if item:
				_items[slot_for(item)] = item
	_apply()


## The item in `slot`, or null.
func get_item(slot: StringName) -> GearDefinition:
	return _items.get(slot)


## Every equipped item by slot (a copy).
func get_items() -> Dictionary:
	return _items.duplicate()


## The equipment slots `item` can go in.
static func slots_for(item: GearDefinition) -> Array:
	return SLOTS_OF.get(item.slot, []) if item else []


## Where equip(item) puts it: its slot, or for rings the first free one
## (the first when both are taken).
func slot_for(item: GearDefinition) -> StringName:
	var slots := slots_for(item)
	for slot: StringName in slots:
		if not _items.has(slot):
			return slot
	return slots[0] if not slots.is_empty() else &""


## Puts `item` in `slot` (default: slot_for(item)) and returns what was
## there (null if it was empty). An item that doesn't fit the slot is not
## equipped (returns null).
func equip(item: GearDefinition, slot: StringName = &"") -> GearDefinition:
	if item == null:
		return null
	if slot == &"":
		slot = slot_for(item)
	if not slot in slots_for(item):
		push_warning("Equipment: %s doesn't go in %s" % [item.display_name, slot])
		return null
	var previous: GearDefinition = _items.get(slot)
	if previous == item:
		return null
	_items[slot] = item
	_apply()
	changed.emit(slot, item, previous)
	return previous


## Empties `slot` and returns what was in it.
func unequip(slot: StringName) -> GearDefinition:
	var previous: GearDefinition = _items.get(slot)
	if previous == null:
		return null
	_items.erase(slot)
	_apply()
	changed.emit(slot, null, previous)
	return previous


## Passes the slots on to the appearance, stats and weapon, and saves.
func _apply() -> void:
	var modifiers: Array = []
	var worn: Array[GearDefinition] = []
	for slot in SLOTS:
		var item: GearDefinition = _items.get(slot)
		if item == null:
			continue
		modifiers.append_array(item.modifiers)
		if item.is_worn_visual():
			worn.append(item)
	if appearance and appearance.appearance:
		appearance.appearance.gear = worn
		appearance.apply(appearance.appearance)
	if stats:
		stats.set_modifiers(STATS_SOURCE, modifiers)
	if weapon:
		var wielded := _items.get(&"main_hand") as WeaponDefinition
		if wielded == null:
			wielded = default_weapon
		if wielded and weapon.current != wielded:
			weapon.equip(wielded)
	_save()


func _save() -> void:
	var profile := PlayerProfile.current()
	if not persistent or profile == null or not profile.persists():
		return
	var saved := {}
	for slot: StringName in _items:
		var item: GearDefinition = _items[slot]
		if item.resource_path != "":
			saved[String(slot)] = item.resource_path
	profile.set_equipment(saved)


## Equips what the profile saved; false when there is nothing to load.
func _load_saved() -> bool:
	var profile := PlayerProfile.current()
	if not persistent or profile == null or not profile.persists() or profile.equipment.is_empty():
		return false
	for key in profile.equipment:
		var slot := StringName(key)
		var path := String(profile.equipment[key])
		var item := load(path) as GearDefinition if ResourceLoader.exists(path) else null
		if item == null or not slot in slots_for(item):
			push_warning("Equipment: can't restore %s in %s" % [path, slot])
			continue
		_items[slot] = item
	return true
