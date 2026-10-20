class_name GearDefinition
extends ItemDefinition
## A piece of wearable gear (helmet, cloak, boots): one .tres per item in
## resources/items/gear/. AppearanceComponent puts it on a character through
## GearBuilder: the model's meshes are placed by `fit` relative to
## `anchor_bone` and skinned to the skeleton according to `rig`.
## (Stats come with the character stats step.)

enum Slot { HEAD, BACK, FEET }
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
@export var rig: Rig = Rig.RIGID
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
