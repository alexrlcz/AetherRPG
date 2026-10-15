class_name CharacterAnimator
extends Node
## Drives a character's AnimationPlayer from its body's movement and health.
## Shared by the player and enemies. Gameplay code only calls `play_action()`
## for one-shot animations (attacks); locomotion and death are automatic.

@export var body: CharacterBody3D
@export var health: HealthComponent
@export var animation_player: AnimationPlayer

@export_group("Animations")
@export var idle_animation: StringName = &"Sword_Idle"
@export var walk_animation: StringName = &"Walk"
@export var run_animation: StringName = &"Jog_Fwd"
@export var death_animation: StringName = &"Death01"

@export_group("Tuning")
## Crossfade time into and out of one-shot actions (attacks).
@export var blend_time: float = 0.15
## Crossfade time between idle, walk and run. Longer reads as heavier.
@export var locomotion_blend_time: float = 0.25
## Below this horizontal speed (m/s) the character is considered idle.
@export var move_threshold: float = 0.3
## Speed (m/s) above which the walk cycle switches to the run cycle. Leave
## `walk_animation` empty to skip walking entirely.
@export var walk_to_run_speed: float = 2.6
## Dead zone around `walk_to_run_speed` so the cycles don't flicker.
@export var walk_run_hysteresis: float = 0.3
## Movement speed (m/s) at which the walk cycle plays at normal rate.
@export var walk_reference_speed: float = 1.6
## Movement speed (m/s) at which the run cycle plays at normal rate
## (Jog_Fwd covers 5 m in 0.93 s).
@export var run_reference_speed: float = 5.36
## Playback rate limits for the locomotion cycles, so a cycle never crawls in
## slow motion while the character is speeding up or slowing down.
@export var min_cycle_rate: float = 0.6
@export var max_cycle_rate: float = 1.6
## Moving against the facing direction more than this (dot product) plays
## the cycle in reverse (walking backwards). Only while the body reports
## `is_aiming`, so momentum during a quick turn doesn't moonwalk.
@export var backwards_threshold: float = -0.3

var _dead: bool = false
var _action: StringName = &""


func _ready() -> void:
	# Not every locomotion animation is flagged as looping on import.
	for anim_name in [idle_animation, walk_animation, run_animation]:
		if anim_name == &"":
			continue
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
	var anim := run_animation
	var reference := run_reference_speed
	if _uses_walk(speed):
		anim = walk_animation
		reference = walk_reference_speed
	var rate := clampf(speed / reference, min_cycle_rate, max_cycle_rate)
	var forward := -body.global_basis.z
	if body.get(&"is_aiming") == true 			and horizontal.normalized().dot(forward) < backwards_threshold:
		rate = -rate
	_play(anim, rate)


func _uses_walk(speed: float) -> bool:
	if walk_animation == &"":
		return false
	if animation_player.current_animation == walk_animation:
		return speed < walk_to_run_speed + walk_run_hysteresis
	return speed < walk_to_run_speed - walk_run_hysteresis


## Plays a one-shot animation; locomotion resumes when it finishes.
func play_action(anim_name: StringName, speed: float = 1.0) -> void:
	if _dead:
		return
	_action = anim_name
	if animation_player.current_animation == anim_name:
		# play() would just continue it (back-to-back attacks); restart.
		animation_player.seek(0.0, true)
	else:
		animation_player.play(anim_name, blend_time)
	animation_player.speed_scale = speed


func is_playing_action() -> bool:
	return _action != &""


## Ends the current one-shot early (e.g. the attack's follow-through once the
## character can move again); locomotion blends back in.
func stop_action() -> void:
	_action = &""


func _play(anim_name: StringName, speed: float) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, locomotion_blend_time)
	animation_player.speed_scale = speed


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == _action:
		_action = &""


func _on_died() -> void:
	_dead = true
	_action = &""
	# Leave `death_animation` empty when a RagdollComponent handles death.
	if death_animation != &"":
		animation_player.speed_scale = 1.0
		animation_player.play(death_animation, blend_time)
