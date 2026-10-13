class_name CharacterAnimator
extends Node
## Drives a character's AnimationPlayer from its body's movement and health.
## Shared by the player and enemies. Gameplay code only calls `play_action()`
## for one-shot animations (attacks); locomotion and death are automatic.

@export var body: CharacterBody3D
@export var health: HealthComponent
@export var animation_player: AnimationPlayer

@export_group("Animations")
@export var idle_animation: StringName = &"HumanArmature|Idle_swordRight"
@export var run_animation: StringName = &"HumanArmature|Run_swordRight"
@export var death_animation: StringName = &"HumanArmature|Death"

@export_group("Tuning")
@export var blend_time: float = 0.15
## Below this horizontal speed (m/s) the character is considered idle.
@export var move_threshold: float = 0.3
## Movement speed (m/s) at which the run cycle plays at normal rate.
@export var run_reference_speed: float = 6.0
## Moving against the facing direction more than this (dot product) plays
## the run cycle in reverse (walking backwards).
@export var backwards_threshold: float = -0.3

var _dead: bool = false
var _action: StringName = &""


func _ready() -> void:
	# Imported FBX animations are not flagged as looping.
	for anim_name in [idle_animation, run_animation]:
		if animation_player.has_animation(anim_name):
			animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		else:
			push_warning("CharacterAnimator: missing animation '%s'" % anim_name)
	if health:
		health.died.connect(_on_died)
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play(idle_animation)


func _process(_delta: float) -> void:
	if _dead or _action != &"":
		return
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := horizontal.length()
	if speed < move_threshold:
		_play(idle_animation, 1.0)
		return
	var forward := -body.global_basis.z
	var rate := speed / run_reference_speed
	if horizontal.normalized().dot(forward) < backwards_threshold:
		rate = -rate
	_play(run_animation, rate)


## Plays a one-shot animation; locomotion resumes when it finishes.
func play_action(anim_name: StringName, speed: float = 1.0) -> void:
	if _dead:
		return
	_action = anim_name
	animation_player.play(anim_name, blend_time)
	animation_player.speed_scale = speed


func is_playing_action() -> bool:
	return _action != &""


func _play(anim_name: StringName, speed: float) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, blend_time)
	animation_player.speed_scale = speed


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == _action:
		_action = &""


func _on_died() -> void:
	_dead = true
	_action = &""
	animation_player.speed_scale = 1.0
	animation_player.play(death_animation, blend_time)
