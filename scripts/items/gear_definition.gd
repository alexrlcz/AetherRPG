class_name GearDefinition
extends ItemDefinition
## A piece of wearable gear (helmet, cloak, boots, shield): one .tres per item in
## resources/items/gear/. AppearanceComponent puts it on a character through
## GearBuilder: the model's meshes are placed by `fit` relative to
## `anchor_bone` and skinned to the skeleton according to `rig`.

enum Slot { HEAD, BACK, FEET, OFF_HAND }
## How the meshes follow the skeleton:
## RIGID: entirely `anchor_bone` (a helmet on the head).
## BOOTS: calf above the ankle, foot, toes past the ball; worn on both feet
##   (the model is the right boot; a mirrored copy goes on the left).
## CLOAK: a grid of spring bones hung from `anchor_bone` along the cloth,
##   simulated (gravity, inertia, leg and torso colliders).
enum Rig { RIGID, BOOTS, CLOAK }

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
## Hides the hairstyle while worn (helmets).
@export var hides_hair: bool = false
## Outfit meshes whose names contain any of these are left off while worn
## (e.g. "_Feet" under boots, "_Head_Hood" under a helmet).
@export var hides_parts: PackedStringArray = []
## Body triangles mostly weighted to these bones are cut away while worn, so
## the skin can't poke through (feet under boots).
@export var hides_body_bones: PackedStringArray = []


func _init() -> void:
	kind = ItemDefinition.Kind.GEAR
	auto_collect = false
