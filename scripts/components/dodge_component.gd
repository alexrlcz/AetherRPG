class_name DodgeComponent
extends Node
## A committed dodge roll: a burst of movement along a direction with
## invulnerability frames, then a short recovery while the character gets back
## up. The owner picks the direction and calls start(); while is_dodging() it
## applies current_velocity() to its body instead of its own movement (like a
## melee lunge) and ignores other actions.
##
## The distance covered is exact at any tick rate: each tick's velocity is the
## change of an analytic position curve over that tick.

signal started(direction: Vector3)
## Recovery ended (or was cut short with end_recovery()).
signal finished

enum Phase { READY, ROLL, RECOVERY }

@export var animator: CharacterAnimator
## Made invulnerable during the i-frame window.
@export var hurtbox: HurtboxComponent
## Optional: each roll pays `stamina_cost` here; none starts while it can't
## act (exhausted).
@export var stamina: StaminaComponent
@export var stamina_cost: float = 18.0
@export var animation: StringName = &"Roll"
## Seconds into `animation` reached when recovery ends. 0 = full length.
@export var animation_end: float = 0.0

@export_group("Movement")
@export var distance: float = 4.0
## Seconds of movement.
@export var duration: float = 0.6
## Shape of the speed curve: 0 = constant speed; higher = a faster burst at the
## start and a longer slow-down at the end.
@export var falloff: float = 0.75
## Seconds rooted after the movement while the animation gets up. Movement or
## attack input may cut it short (see end_recovery()).
@export var recovery: float = 0.15

@export_group("Timing")
## Window (seconds from the start) in which hits are ignored.
@export var invulnerable_start: float = 0.03
@export var invulnerable_end: float = 0.4
## Minimum seconds between the starts of two dodges.
@export var cooldown: float = 0.9

var phase: Phase = Phase.READY
var phase_time: float = 0.0
## Horizontal unit vector of the current (or last) dodge.
var direction: Vector3 = Vector3.FORWARD

var _since_start: float = INF


func is_dodging() -> bool:
	return phase != Phase.READY


func is_rolling() -> bool:
	return phase == Phase.ROLL


func is_recovering() -> bool:
	return phase == Phase.RECOVERY


## True when a new dodge may start now (not dodging, cooldown over, stamina
## to act).
func is_ready() -> bool:
	return phase == Phase.READY and _since_start >= cooldown 		and (stamina == null or stamina.can_act())


## Starts a dodge along `dir` (horizontal). Returns false if not ready.
func start(dir: Vector3) -> bool:
	dir.y = 0.0
	if not is_ready() or dir.length_squared() < 0.0001:
		return false
	direction = dir.normalized()
	if stamina:
		stamina.spend(stamina_cost)
	_since_start = 0.0
	_enter(Phase.ROLL)
	_update_invulnerability()
	if animator and animation != &"" and animator.animation_player.has_animation(animation):
		var end := animation_end
		if end <= 0.0:
			end = animator.animation_player.get_animation(animation).length
		animator.play_action(animation, end / maxf(duration + recovery, 0.01))
	started.emit(direction)
	return true


## Velocity (m/s, horizontal) the owner should move at this tick.
func current_velocity() -> Vector3:
	if phase != Phase.ROLL:
		return Vector3.ZERO
	var dt := get_physics_process_delta_time()
	var covered := _position_at(phase_time + dt) - _position_at(phase_time)
	return direction * (covered / dt)


## Ends the recovery now (the owner wants to move or attack).
func end_recovery() -> void:
	if phase == Phase.RECOVERY:
		_finish()


## Aborts the dodge immediately (stagger, death). Does not emit `finished`.
func cancel() -> void:
	_enter(Phase.READY)
	_update_invulnerability()


func _physics_process(delta: float) -> void:
	_since_start += delta
	if phase == Phase.READY:
		return
	phase_time += delta
	match phase:
		Phase.ROLL:
			if phase_time >= duration:
				_enter(Phase.RECOVERY)
		Phase.RECOVERY:
			if phase_time >= recovery:
				_finish()
	_update_invulnerability()


func _finish() -> void:
	_enter(Phase.READY)
	_update_invulnerability()
	if animator and animator.current_action() == animation:
		animator.stop_action()
	finished.emit()


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	phase_time = 0.0


## Distance covered `t` seconds into the movement: ease-out from a burst.
func _position_at(t: float) -> float:
	var u := clampf(t / maxf(duration, 0.001), 0.0, 1.0)
	return distance * (1.0 - pow(1.0 - u, falloff + 1.0))


func _update_invulnerability() -> void:
	if hurtbox == null:
		return
	# _since_start counts from the start through both phases.
	hurtbox.invulnerable = phase != Phase.READY \
		and _since_start >= invulnerable_start and _since_start < invulnerable_end
