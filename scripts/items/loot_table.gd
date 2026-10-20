class_name LootTable
extends Resource
## What something drops (an enemy, a chest): one .tres per table in
## resources/loot/. Every `guaranteed` entry is rolled on its own `chance`;
## then `rolls` picks are made from `weighted` by weight, where
## `nothing_weight` is the share of a pick that gives nothing.

@export var guaranteed: Array[LootEntry] = []
@export var weighted: Array[LootEntry] = []
@export var rolls: int = 0
@export var nothing_weight: float = 0.0


## The drop for `level`: [[item: ItemDefinition, amount: int], ...], one line
## per item (amounts of the same item added up), in table order.
func roll(rng: RandomNumberGenerator, level: int = 1) -> Array:
	var totals := {}
	var order: Array[ItemDefinition] = []
	for entry in guaranteed:
		if entry.item and rng.randf() < entry.chance:
			_add(totals, order, entry.item, entry.roll_amount(rng, level))
	var total_weight := nothing_weight
	for entry in weighted:
		total_weight += maxf(entry.weight, 0.0)
	for i in rolls:
		var pick := rng.randf() * total_weight
		for entry in weighted:
			pick -= maxf(entry.weight, 0.0)
			if pick < 0.0:
				if entry.item:
					_add(totals, order, entry.item, entry.roll_amount(rng, level))
				break
	var result := []
	for item in order:
		if totals[item] > 0:
			result.append([item, totals[item]])
	return result


## A table that always drops `low`..`high` gold (tests, quick setups).
static func gold_only(low: int, high: int) -> LootTable:
	var entry := LootEntry.new()
	entry.item = preload("res://resources/items/gold.tres")
	entry.amount = Vector2i(low, high)
	var table := LootTable.new()
	table.guaranteed = [entry]
	return table


static func _add(totals: Dictionary, order: Array[ItemDefinition], item: ItemDefinition, amount: int) -> void:
	if not totals.has(item):
		totals[item] = 0
		order.append(item)
	totals[item] += amount
