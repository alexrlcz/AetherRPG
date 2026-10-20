class_name HealthComponent
extends Node
## Tracks hit points for any entity. Knows nothing about who owns it;
## other systems react through its signals.

signal health_changed(current: int, maximum: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int)
signal died

@export var max_health: int = 100:
	set(value):
		var was_full := current_health == max_health
		max_health = maxi(value, 1)
		if was_full or current_health > max_health:
			current_health = max_health
		health_changed.emit(current_health, max_health)

## Debug god mode: take_damage() removes nothing (so hits don't stagger
## either: hurtboxes only react to damage actually taken).
@export var god_mode: bool = false

## Valid from construction (not only after _ready), so other nodes can read
## it regardless of scene-tree ready order.
var current_health: int = max_health
var is_dead: bool:
	get:
		return current_health <= 0


## Applies damage and returns the amount actually removed.
func take_damage(amount: int, source: Node = null) -> int:
	if is_dead or amount <= 0 or god_mode:
		return 0
	var applied := mini(amount, current_health)
	current_health -= applied
	damaged.emit(applied, source)
	health_changed.emit(current_health, max_health)
	if is_dead:
		died.emit()
	return applied


## Restores health (not above max) and returns the amount actually restored.
func heal(amount: int) -> int:
	if is_dead or amount <= 0:
		return 0
	var applied := mini(amount, max_health - current_health)
	if applied == 0:
		return 0
	current_health += applied
	healed.emit(applied)
	health_changed.emit(current_health, max_health)
	return applied


## Restores full health, including from death.
func reset() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
