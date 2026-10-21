@tool
class_name CharacterAppearance
extends Resource
## The look of a humanoid character (body, skin, hair) and the gear drawn on
## it. Applied to a humanoid rig by AppearanceComponent. One .tres per
## character / enemy type; a future character creator can produce these
## too. The player's `gear` is filled by its Equipment.

enum Body { MALE, FEMALE }
enum SkinTexture { LIGHT, DARK }

## Hairstyle ids; "None" = bald. AppearanceComponent loads Hair_<id>.gltf.
const HAIR_STYLES: PackedStringArray = ["None", "Buns", "Buzzed", "BuzzedFemale", "Long", "SimpleParted"]
## Eyebrow ids; "None" = no eyebrows. Loads Eyebrows_<id>.gltf.
const EYEBROW_STYLES: PackedStringArray = ["None", "Regular", "Female"]
## Creatures (Bestiary - Dungeon Monsters Kit) that replace the human body:
## their colour variant names, in `creature_variant` order.
const CREATURES := {
	"Imp": ["Crimson", "Bile", "Frost"],
	"Puglin": ["Moss", "Blood", "Deep"],
}

@export var body: Body = Body.MALE

@export_group("Skin")
@export var skin_texture: SkinTexture = SkinTexture.LIGHT
## Multiplied with the skin texture (white = unchanged).
@export var skin_tint: Color = Color.WHITE

@export_group("Hair")
@export var hair_style: String = "SimpleParted"
## Hair, beard and eyebrow colour (the hair textures are greyscale).
@export var hair_color: Color = Color(0.32, 0.2, 0.12)
@export var beard: bool = false
@export var eyebrows: String = "Regular"

@export_group("Creature")
## A monster model instead of the human body ("" = human). When set, body,
## skin, hair and gear are ignored.
@export var creature: String = ""
## Index into CREATURES[creature] (colour); -1 = a random one on apply.
@export var creature_variant: int = 0

@export_group("Gear")
## Gear drawn on the body (helmets, outfit pieces, the shield), at most one
## per GearDefinition.Slot (two rings never show).
@export var gear: Array[GearDefinition] = []


func _validate_property(property: Dictionary) -> void:
	# Dropdowns in the inspector, driven by the id lists above.
	if property.name == "hair_style":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(HAIR_STYLES)
	elif property.name == "eyebrows":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(EYEBROW_STYLES)


## The gear worn in `slot`, or null.
func gear_in(slot: GearDefinition.Slot) -> GearDefinition:
	for item in gear:
		if item and item.slot == slot:
			return item
	return null


## Wears `item` in its slot (replacing what was there); null clears `slot`.
func set_gear(slot: GearDefinition.Slot, item: GearDefinition) -> void:
	var kept: Array[GearDefinition] = []
	for worn in gear:
		if worn and worn.slot != slot:
			kept.append(worn)
	if item:
		kept.append(item)
	gear = kept

