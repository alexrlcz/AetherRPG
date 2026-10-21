class_name ShieldDefinition
extends GearDefinition
## A shield: gear for the OFF_HAND slot, held in the left hand (`fit` in the
## hand bone's space), plus how well it blocks. BlockComponent reads these
## while the shield is worn. One .tres per shield in resources/items/gear/.

## Width (degrees) of the arc in front of the character that blocks hits.
@export_range(0.0, 360.0) var block_angle: float = 140.0
## Stamina paid per point of damage blocked (a blocked hit does no damage).
## A hit that costs more than the stamina left breaks the guard and lands in
## full.
@export var stamina_per_damage: float = 1.5


func _init() -> void:
	super()
	slot = GearDefinition.Slot.OFF_HAND
	anchor_bone = &"hand_l"
	fit_in_bone_space = true
