class_name OutfitPieceDefinition
extends GearDefinition
## Wearable gear cut from a Modular Character Outfits model
## (assets/characters/outfits/<Male|Female>_<outfit>.gltf): the meshes named
## in `male_meshes` / `female_meshes` (already skinned to the Universal
## skeleton) go on the character, matching its body. Skin surfaces of the
## piece (hands; MI_Regular_* materials) take the body's skin texture and
## tint; `cloth_variant` > 0 swaps the cloth texture
## (AppearanceComponent.OUTFIT_TEXTURES). `hides_body_bones` cuts the body
## away under it, `hides_hair` hides the hair (hoods).

## "Peasant" or "Ranger".
@export var outfit: String = "Peasant"
## Mesh node names in the male / female outfit model.
@export var male_meshes: PackedStringArray = []
@export var female_meshes: PackedStringArray = []
## Index into AppearanceComponent.OUTFIT_TEXTURES[outfit] (0 = the model's).
@export var cloth_variant: int = 0


func is_worn_visual() -> bool:
	return true


func meshes_for(female: bool) -> PackedStringArray:
	return female_meshes if female else male_meshes
