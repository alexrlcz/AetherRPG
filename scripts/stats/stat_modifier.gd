class_name StatModifier
extends Resource
## One change to one core stat (gear bonuses, elite scaling, later buffs).
## CharacterStats combines a stat's modifiers as
##   (base + every FLAT) * (1 + every PERCENT) * every MULTIPLY
## so PERCENT bonuses add up with each other (+10% and +10% = +20%) and
## MULTIPLY ones compound (elite x2).

enum Kind { FLAT, PERCENT, MULTIPLY }

@export var stat: CharacterStats.Stat = CharacterStats.Stat.ARMOR
@export var kind: Kind = Kind.FLAT
## FLAT: added (10 = +10 armor). PERCENT: a fraction (0.1 = +10%).
## MULTIPLY: a factor (2 = double).
@export var value: float = 0.0


static func make(stat_id: CharacterStats.Stat, modifier_kind: Kind, amount: float) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat_id
	modifier.kind = modifier_kind
	modifier.value = amount
	return modifier
