class_name CharacterStats
extends Node
## A character's core stats: base values (`base`, a StatBlock) changed by
## modifiers grouped by source (&"gear", &"elite", later buffs), giving the
## final values. Those are pushed into the components that use them; the
## controllers read MOVE_SPEED themselves. Knows nothing about who owns it.
##
##   MAX_HEALTH    -> health.max_health (rounded)
##   MAX_STAMINA   -> stamina.max_stamina
##   STAMINA_REGEN -> stamina.regen_rate
##   DAMAGE        -> melee.damage_scale (multiplier, base 1)
##   ARMOR         -> hurtbox.damage_reduction = armor / (armor + 100)
##   MOVE_SPEED    -> multiplier (base 1) on the controller's speeds
##
## Until equipment slots exist, the gear worn by `appearance` supplies the
## &"gear" modifiers (GearDefinition.modifiers), refreshed on every apply.

signal stats_changed

enum Stat { MAX_HEALTH, MAX_STAMINA, STAMINA_REGEN, DAMAGE, ARMOR, MOVE_SPEED }

const GEAR_SOURCE := &"gear"

## Base values. The enemy controller sets its EnemyStats here; null = the
## StatBlock defaults.
@export var base: StatBlock
@export var health: HealthComponent
@export var stamina: StaminaComponent
@export var melee: MeleeAttackComponent
@export var hurtbox: HurtboxComponent
## Optional: its worn gear's modifiers apply (see above).
@export var appearance: AppearanceComponent

## Source -> Array[StatModifier].
var _modifiers: Dictionary = {}
## Stat -> final value.
var _values: Dictionary = {}


func _ready() -> void:
	if base == null:
		base = StatBlock.new()
	if appearance:
		appearance.applied.connect(_refresh_gear)
		_refresh_gear()
	recalculate()


## Final value of `stat`.
func get_value(stat: Stat) -> float:
	if _values.is_empty():
		recalculate()
	return _values[stat]


## Value of `stat` before modifiers.
func get_base_value(stat: Stat) -> float:
	var block := base if base else StatBlock.new()
	match stat:
		Stat.MAX_HEALTH:
			return block.max_health
		Stat.MAX_STAMINA:
			return block.max_stamina
		Stat.STAMINA_REGEN:
			return block.stamina_regen
		Stat.ARMOR:
			return block.armor
	return 1.0  # DAMAGE and MOVE_SPEED are multipliers.


func set_base(new_base: StatBlock) -> void:
	base = new_base
	recalculate()


## Replaces every modifier from `source` with `modifiers`.
func set_modifiers(source: StringName, modifiers: Array) -> void:
	if modifiers.is_empty():
		_modifiers.erase(source)
	else:
		_modifiers[source] = modifiers.duplicate()
	recalculate()


func remove_modifiers(source: StringName) -> void:
	set_modifiers(source, [])


func get_modifiers(source: StringName) -> Array:
	return _modifiers.get(source, [])


## Fraction of incoming damage armor removes (0 with no armor).
static func armor_reduction(armor: float) -> float:
	return armor / (armor + 100.0) if armor > 0.0 else 0.0


## Recomputes every final value and pushes them into the components.
func recalculate() -> void:
	for stat: Stat in Stat.values():
		var flat := 0.0
		var percent := 0.0
		var factor := 1.0
		for modifiers: Array in _modifiers.values():
			for modifier: StatModifier in modifiers:
				if modifier.stat != stat:
					continue
				match modifier.kind:
					StatModifier.Kind.FLAT:
						flat += modifier.value
					StatModifier.Kind.PERCENT:
						percent += modifier.value
					StatModifier.Kind.MULTIPLY:
						factor *= modifier.value
		_values[stat] = maxf((get_base_value(stat) + flat) * (1.0 + percent) * factor, 0.0)
	_push()
	stats_changed.emit()


func _push() -> void:
	if health:
		health.max_health = maxi(roundi(_values[Stat.MAX_HEALTH]), 1)
	if stamina:
		stamina.max_stamina = _values[Stat.MAX_STAMINA]
		stamina.regen_rate = _values[Stat.STAMINA_REGEN]
	if melee:
		melee.damage_scale = _values[Stat.DAMAGE]
	if hurtbox:
		hurtbox.damage_reduction = armor_reduction(_values[Stat.ARMOR])


func _refresh_gear() -> void:
	var modifiers: Array = []
	if appearance.appearance:
		for item in appearance.appearance.gear:
			if item:
				modifiers.append_array(item.modifiers)
	set_modifiers(GEAR_SOURCE, modifiers)
