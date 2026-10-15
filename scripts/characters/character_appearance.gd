@tool
class_name CharacterAppearance
extends Resource
## The look of a humanoid character (body, skin, hair). Applied to a
## humanoid rig by AppearanceComponent. One .tres per character / enemy type;
## a future character creator can produce these too.

enum Body { MALE, FEMALE }
enum SkinTexture { LIGHT, DARK }

## Hairstyle ids; "None" = bald. AppearanceComponent loads Hair_<id>.gltf.
const HAIR_STYLES: PackedStringArray = ["None", "Buns", "Buzzed", "BuzzedFemale", "Long", "SimpleParted"]
## Eyebrow ids; "None" = no eyebrows. Loads Eyebrows_<id>.gltf.
const EYEBROW_STYLES: PackedStringArray = ["None", "Regular", "Female"]

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


func _validate_property(property: Dictionary) -> void:
	# Dropdowns in the inspector, driven by the id lists above.
	if property.name == "hair_style":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(HAIR_STYLES)
	elif property.name == "eyebrows":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(EYEBROW_STYLES)
