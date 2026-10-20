class_name FlaskComponent
extends Node
## Healing flasks: `max_charges` drinks that each restore `heal_fraction` of
## the owner's maximum health. Drinking is a committed action of `duration`
## seconds (the owner stands still and does nothing else); the health comes
## back `heal_time` seconds in, and only then is the charge spent. cancel()
## before that (a staggering hit, death) wastes the time but not the charge.
## Charges refill at the start of every run level (`refill_on_new_level`).
##
## The owner decides when to call start() (can_drink() first) and reads
## is_drinking() to stay committed; UI listens to the signals.

signal charges_changed(current: int, maximum: int)
## A drink began.
signal started
## The drink landed: `amount` health restored, one charge spent.
signal drank(amount: int)
## A drink was cut short before it healed.
signal interrupted

@export var health: HealthComponent
@export var animator: CharacterAnimator
## Optional flask model (in the hand), shown only while drinking.
@export var prop: Node3D
@export var max_charges: int = 3:
	set(value):
		max_charges = maxi(value, 0)
		charges = mini(charges, max_charges)
		charges_changed.emit(charges, max_charges)
## Fraction of max health one drink restores.
@export_range(0.0, 1.0) var heal_fraction: float = 0.35
@export var animation: StringName = &"UAL2/Consume"
## Seconds the drink takes (the animation is fitted to it).
@export var duration: float = 1.1
## Seconds into the drink when the health comes back.
@export var heal_time: float = 0.6
## Refill when the run moves to a new level (GameRun.level_changed).
@export var refill_on_new_level: bool = true

var charges: int = max_charges

## Seconds into the current drink; < 0 when not drinking.
var _time: float = -1.0
var _healed: bool = false


func _ready() -> void:
	if prop:
		prop.hide()
	if refill_on_new_level:
		GameRun.current().level_changed.connect(func(_level: int) -> void: refill())


func is_drinking() -> bool:
	return _time >= 0.0


## True when a drink may start now: a charge left, not already drinking,
## alive and not at full health (a drink is never wasted).
func can_drink() -> bool:
	return charges > 0 and not is_drinking() and health != null \
		and not health.is_dead and health.current_health < health.max_health


## Starts a drink. Returns false if can_drink() is false.
func start() -> bool:
	if not can_drink():
		return false
	_time = 0.0
	_healed = false
	if animator and animation != &"" and animator.animation_player.has_animation(animation):
		var length := animator.animation_player.get_animation(animation).length
		animator.play_action(animation, length / maxf(duration, 0.01))
	if prop:
		prop.show()
	started.emit()
	return true


## Aborts the drink (stagger, death). Before it healed, the charge is kept.
func cancel() -> void:
	if not is_drinking():
		return
	var healed := _healed
	_finish()
	if not healed:
		interrupted.emit()


## All charges back.
func refill() -> void:
	charges = max_charges
	charges_changed.emit(charges, max_charges)


## Health one drink restores.
func heal_amount() -> int:
	return roundi(health.max_health * heal_fraction) if health else 0


func _physics_process(delta: float) -> void:
	if not is_drinking():
		return
	_time += delta
	if not _healed and _time >= heal_time:
		_healed = true
		charges -= 1
		charges_changed.emit(charges, max_charges)
		drank.emit(health.heal(heal_amount()))
	if _time >= duration:
		_finish()


func _finish() -> void:
	_time = -1.0
	if prop:
		prop.hide()
	if animator and animator.current_action() == animation:
		animator.stop_action()
