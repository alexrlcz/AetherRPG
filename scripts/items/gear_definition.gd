class_name GearDefinition
extends ItemDefinition
## An equippable item: one .tres per item (resources/items/gear/, weapons in
## resources/weapons/). Equipment puts it in a slot; what it looks like
## depends on the kind:
## - a model (helmet, shield): AppearanceComponent builds it onto the
##   skeleton through GearBuilder: the meshes are placed by `fit` relative
##   to `anchor_bone` and skinned according to `rig`;
## - OutfitPieceDefinition: meshes taken from an outfit model;
## - WeaponDefinition (main hand): WeaponComponent puts it in the hand;
## - no model (neck, rings, trinket): stats only.
## Every kind gives its `modifiers` (CharacterStats) while equipped.

## Item slots. RING items go in either ring slot (Equipment). New values
## are appended so saved .tres slot numbers stay valid.
enum Slot { HEAD, BACK, FEET, OFF_HAND, NECK, SHOULDERS, CHEST, WRISTS, HANDS, LEGS, RING, TRINKET, MAIN_HAND }
## How the meshes follow the skeleton:
## RIGID: entirely `anchor_bone` (a helmet on the head).
## BOOTS: calf above the ankle, foot, toes past the ball; worn on both feet
##   (the model is the right boot; a mirrored copy goes on the left).
## CLOAK: a grid of spring bones hung from `anchor_bone` along the cloth,
##   simulated (gravity, inertia, leg and torso colliders).
enum Rig { RIGID, BOOTS, CLOAK }

## Slot names for menus and prompts.
const SLOT_NAMES := {
	Slot.HEAD: "Head", Slot.BACK: "Cloak", Slot.FEET: "Boots", Slot.OFF_HAND: "Off hand",
	Slot.NECK: "Neck", Slot.SHOULDERS: "Shoulders", Slot.CHEST: "Chest", Slot.WRISTS: "Wrists",
	Slot.HANDS: "Gloves", Slot.LEGS: "Legs", Slot.RING: "Ring", Slot.TRINKET: "Trinket",
	Slot.MAIN_HAND: "Main hand",
}

@export var slot: Slot = Slot.HEAD
@export var model: PackedScene
## Skeleton bone the fit is relative to (the right foot for boots).
@export var anchor_bone: StringName = &"Head"
## Model space -> offset from the anchor bone's rest origin, in skeleton
## space (Y up, the character faces +Z). Fitted to the male base body;
## other bodies move with their anchor bone.
@export var fit: Transform3D = Transform3D.IDENTITY
## `fit` is in the anchor bone's own space (its rest rotation included),
## like a weapon in the hand: for things held rather than worn (a shield).
@export var fit_in_bone_space: bool = false
@export var rig: Rig = Rig.RIGID
## Core stat changes while worn (CharacterStats).
@export var modifiers: Array[StatModifier] = []
## Hides the hairstyle while worn (helmets, hoods).
@export var hides_hair: bool = false
## Outfit meshes whose names contain any of these are left off while worn
## (e.g. "_Head_Hood" under a helmet).
@export var hides_parts: PackedStringArray = []
## Body triangles mostly weighted to these bones are cut away while worn, so
## the skin can't poke through (the torso under a tunic, feet in boots).
@export var hides_body_bones: PackedStringArray = []


func _init() -> void:
	kind = ItemDefinition.Kind.GEAR
	auto_collect = false


## True when AppearanceComponent should draw it on the body (a model or
## outfit meshes; not weapons, which go in the hand, nor stat-only items).
func is_worn_visual() -> bool:
	return model != null


## One line per stat it gives, for prompts and menus ("+10 Armor").
func describe_modifiers() -> String:
	var lines := PackedStringArray()
	for modifier in modifiers:
		lines.append(modifier.describe())
	return ", ".join(lines)
