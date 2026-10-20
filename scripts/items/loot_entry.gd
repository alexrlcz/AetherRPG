class_name LootEntry
extends Resource
## One line of a LootTable: an item, how many, and how likely.

@export var item: ItemDefinition
## Amount rolled from x to y (inclusive).
@export var amount: Vector2i = Vector2i(1, 1)
## Extra amount per level above the first, as a fraction of the roll (0.15 =
## +15% per level): deeper floors give more gold.
@export var per_level: float = 0.0
## Share of a weighted roll (LootTable.weighted).
@export var weight: float = 1.0
## Chance to drop at all (LootTable.guaranteed entries).
@export_range(0.0, 1.0) var chance: float = 1.0


## The amount for one drop on `level`.
func roll_amount(rng: RandomNumberGenerator, level: int) -> int:
	var base := rng.randi_range(mini(amount.x, amount.y), maxi(amount.x, amount.y))
	return roundi(base * (1.0 + per_level * maxi(level - 1, 0)))
