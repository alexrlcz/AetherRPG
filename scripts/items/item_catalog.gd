class_name ItemCatalog
extends Resource
## A list of equippable items: what the debug Equipment panel offers and
## what LootTable gear drops pick from (resources/items/catalog.tres).

@export var items: Array[GearDefinition] = []


## The items for an item slot, in catalog order.
func for_slot(slot: GearDefinition.Slot) -> Array[GearDefinition]:
	var result: Array[GearDefinition] = []
	for item in items:
		if item and item.slot == slot:
			result.append(item)
	return result


## One item at random (null when empty).
func pick(rng: RandomNumberGenerator) -> GearDefinition:
	if items.is_empty():
		return null
	return items[rng.randi_range(0, items.size() - 1)]
