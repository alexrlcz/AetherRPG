class_name MeleeAttackComponent
extends Node
## Runs one melee attack: wind-up -> strike (hitbox live) -> recovery.
## Used by both the player and enemies; the owner decides when to call start()
## and handles facing/movement while is_busy().

signal started
## The hitbox became live.
signal struck
## Recovery ended; a new attack can start.
signal finished

enum Phase { READY, WINDUP, STRIKE, RECOVERY }

@export var hitbox: HitboxComponent
@export var animator: CharacterAnimator
## Optional ground marker shown during wind-up; its Z scale grows from 0 to 1.
@export var telegraph: Node3D

@export_group("Timing")
@export var damage: int = 10
@export var windup: float = 0.3
@export var strike_duration: float = 0.12
@export var recovery: float = 0.3

@export_group("Animation")
@export var animation: StringName = &""
## Seconds into `animation` where the blow visually lands; playback speed is
## set so that moment coincides with the end of the wind-up.
@export var animation_strike_time: float = 0.3

var phase: Phase = Phase.READY
var phase_time: float = 0.0


func _ready() -> void:
	hitbox.active = false
	if telegraph:
		telegraph.hide()


func is_busy() -> bool:
	return phase != Phase.READY


## Starts an attack. Returns false if one is already in progress.
func start() -> bool:
	if is_busy():
		return false
	hitbox.damage = damage
	_enter(Phase.WINDUP)
	if telegraph:
		telegraph.scale = Vector3(1.0, 1.0, 0.01)
		telegraph.show()
	if animator and animation != &"":
		var speed := animation_strike_time / windup if windup > 0.0 else 1.0
		animator.play_action(animation, speed)
	started.emit()
	return true


## Aborts the attack immediately (e.g. on death). Does not emit `finished`.
func cancel() -> void:
	hitbox.active = false
	if telegraph:
		telegraph.hide()
	_enter(Phase.READY)


func _physics_process(delta: float) -> void:
	if phase == Phase.READY:
		return
	phase_time += delta
	match phase:
		Phase.WINDUP:
			if telegraph:
				var progress := clampf(phase_time / maxf(windup, 0.001), 0.01, 1.0)
				telegraph.scale = Vector3(1.0, 1.0, progress)
			if phase_time >= windup:
				_enter(Phase.STRIKE)
				if telegraph:
					telegraph.hide()
				hitbox.active = true
				struck.emit()
		Phase.STRIKE:
			if phase_time >= strike_duration:
				_enter(Phase.RECOVERY)
				hitbox.active = false
		Phase.RECOVERY:
			if phase_time >= recovery:
				_enter(Phase.READY)
				finished.emit()


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	phase_time = 0.0
