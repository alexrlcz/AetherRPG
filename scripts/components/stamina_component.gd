class_name StaminaComponent
extends Node
## Stamina pool for any character: actions (attacks, dodges) pay a cost up
## front, sprinting drains it per second, and it regenerates after
## `regen_delay` seconds without spending. Knows nothing about who owns it;
## the components that start actions ask can_act() / spend(), and UI listens
## to the signals.
##
## Running dry (reaching 0) leaves the owner `is_exhausted`: no stamina
## actions until it has regenerated back to `recover_threshold` of the
## maximum. An action is allowed whenever stamina is above zero and the owner
## is not exhausted, even if its cost is larger; the pool then bottoms out at
## 0, which exhausts it (the last swing always comes out, but it costs a
## breather).

signal stamina_changed(current: float, maximum: float)
## Stamina hit 0: actions are locked until it recovers.
signal exhausted
## Regenerated back to `recover_threshold` after being exhausted.
signal recovered

@export var max_stamina: float = 100.0:
	set(value):
		var was_full := current_stamina >= max_stamina
		max_stamina = maxf(value, 1.0)
		if was_full or current_stamina > max_stamina:
			current_stamina = max_stamina
		stamina_changed.emit(current_stamina, max_stamina)
## Stamina regained per second once regeneration has started.
@export var regen_rate: float = 30.0
## Seconds after the last spend before regeneration starts.
@export var regen_delay: float = 0.6
## Fraction of `max_stamina` to regain before an exhausted owner may act again.
@export_range(0.0, 1.0) var recover_threshold: float = 0.25
## Debug: nothing costs stamina.
@export var infinite: bool = false

## Valid from construction (not only after _ready), like HealthComponent.
var current_stamina: float = max_stamina
var is_exhausted: bool = false

var _regen_wait: float = 0.0


## True when a stamina action may start now.
func can_act() -> bool:
	return infinite or (current_stamina > 0.0 and not is_exhausted)


## Pays `amount` for an action. Returns false (and spends nothing) when
## can_act() is false.
func spend(amount: float) -> bool:
	if not can_act():
		return false
	_consume(amount)
	return true


## Continuous cost (sprinting): removes `amount` even when it can't be paid
## in full. Call every tick with rate * delta.
func drain(amount: float) -> void:
	_consume(amount)


## Back to full and not exhausted (respawn, new level).
func reset() -> void:
	current_stamina = max_stamina
	_regen_wait = 0.0
	var was_exhausted := is_exhausted
	is_exhausted = false
	stamina_changed.emit(current_stamina, max_stamina)
	if was_exhausted:
		recovered.emit()


## Fill fraction 0..1 (UI).
func ratio() -> float:
	return current_stamina / max_stamina


func _physics_process(delta: float) -> void:
	if _regen_wait > 0.0:
		_regen_wait -= delta
		return
	if current_stamina >= max_stamina:
		return
	current_stamina = minf(current_stamina + regen_rate * delta, max_stamina)
	stamina_changed.emit(current_stamina, max_stamina)
	if is_exhausted and current_stamina >= max_stamina * recover_threshold:
		is_exhausted = false
		recovered.emit()


func _consume(amount: float) -> void:
	if infinite or amount <= 0.0:
		return
	current_stamina = maxf(current_stamina - amount, 0.0)
	_regen_wait = regen_delay
	stamina_changed.emit(current_stamina, max_stamina)
	if current_stamina <= 0.0 and not is_exhausted:
		is_exhausted = true
		exhausted.emit()
