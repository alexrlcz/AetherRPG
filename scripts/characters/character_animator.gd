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
## `is_strafing` (aiming or locked on), so momentum during a quick turn
## doesn't moonwalk.
@export var backwards_threshold: float = -0.3

@export_group("Directional Locomotion")
## While the body reports `is_strafing` (facing decoupled from movement), the
## cycle is picked from the movement direction relative to the facing:
## forward (walk/run above), forward diagonal, strafe, backward diagonal or
## backward. Clips may carry a "reference_speed" meta (m/s, see
## tools/build_mixamo_library.gd) used instead of `run_reference_speed` for
## their playback rate. A missing clip falls back to the forward cycle (played
## in reverse when moving backwards).
@export var forward_left_animation: StringName = &"MX/Jog_Fwd_L"
@export var forward_right_animation: StringName = &"MX/Jog_Fwd_R"
@export var strafe_left_animation: StringName = &"MX/Strafe_L"
@export var strafe_right_animation: StringName = &"MX/Strafe_R"
@export var backward_left_animation: StringName = &"MX/Jog_Bwd_L"
@export var backward_right_animation: StringName = &"MX/Jog_Bwd_R"
@export var backward_animation: StringName = &"MX/Jog_Bwd"
## Degrees away from the facing where each sector starts.
@export var forward_diagonal_angle: float = 22.5
@export var strafe_angle: float = 67.5
@export var backward_diagonal_angle: float = 115.0
@export var backward_angle: float = 160.0
## Degrees a direction must pass a sector boundary before the clip changes.
@export var direction_hysteresis: float = 10.0

var _dead: bool = false
var _action: StringName = &""
var _queued: StringName = &""
## Directional sector while strafing: 0 forward, 1 forward diagonal, 2 strafe,
## 3 back diagonal, 4 back.
var _sector: int = 0


func _ready() -> void:
	# Advance animations on physics ticks, in lockstep with gameplay timers
	# (attack phases, hit windows, blade sweeps). On render frames they drift
	# apart at low frame rates and the hit window no longer matches the swing.
	# Bodies already move per tick (no physics interpolation), so nothing
	# visible is lost.
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
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
	if body.get(&"is_strafing") == true:
		var directional := _directional_animation(horizontal)
		if directional != &"":
			var reference: float = animation_player.get_animation(directional) \
				.get_meta(&"reference_speed", run_reference_speed)
			_play(directional, clampf(speed / reference, min_cycle_rate, max_cycle_rate))
			return
	else:
		_sector = 0
	var anim := run_animation
	var reference := run_reference_speed
	if _uses_walk(speed):
		anim = walk_animation
		reference = walk_reference_speed
	var rate := clampf(speed / reference, min_cycle_rate, max_cycle_rate)
	var forward := -body.global_basis.z
	if body.get(&"is_strafing") == true 			and horizontal.normalized().dot(forward) < backwards_threshold:
		rate = -rate
	_play(anim, rate)


## The strafe / backward clip for moving along `horizontal` relative to the
## body's facing, or &"" for the forward cycle (or when the clip is missing).
func _directional_animation(horizontal: Vector3) -> StringName:
	var forward := -body.global_basis.z
	var right := body.global_basis.x
	var angle := rad_to_deg(atan2(horizontal.dot(right), horizontal.dot(forward)))
	var off := absf(angle)
	var sector := _sector_for(off)
	if sector != _sector and (_sector_for(off - direction_hysteresis) == _sector
			or _sector_for(off + direction_hysteresis) == _sector):
		sector = _sector  # Near a boundary: keep the current clip.
	_sector = sector
	var to_right := angle > 0.0
	var anim: StringName = &""
	match sector:
		1:
			anim = forward_right_animation if to_right else forward_left_animation
		2:
			anim = strafe_right_animation if to_right else strafe_left_animation
		3:
			anim = backward_right_animation if to_right else backward_left_animation
		4:
			anim = backward_animation
	if anim != &"" and not animation_player.has_animation(anim):
		return &""
	return anim


func _sector_for(off: float) -> int:
	if off < forward_diagonal_angle:
		return 0
	if off < strafe_angle:
		return 1
	if off < backward_diagonal_angle:
		return 2
	if off < backward_angle:
		return 3
	return 4


func _uses_walk(speed: float) -> bool:
	if walk_animation == &"":
		return false
	if animation_player.current_animation == walk_animation:
		return speed < walk_to_run_speed + walk_run_hysteresis
	return speed < walk_to_run_speed - walk_run_hysteresis


## Plays a one-shot animation from `from_time` (s); locomotion resumes when it
## finishes.
func play_action(anim_name: StringName, speed: float = 1.0, from_time: float = 0.0) -> void:
	if _dead:
		return
	_action = anim_name
	_queued = &""
	if animation_player.current_animation == anim_name:
		# play() would just continue it (back-to-back attacks); restart.
		animation_player.seek(from_time, true)
	else:
		animation_player.play(anim_name, blend_time)
		if from_time > 0.0:
			animation_player.seek(from_time, true)
	animation_player.speed_scale = speed


## Plays `anim_name` straight after the current one-shot ends, at the same
## speed and without a crossfade (for clips that continue each other's pose,
## e.g. a swing and its return to guard). Cleared by any new action.
func queue_action(anim_name: StringName) -> void:
	if _action != &"":
		_queued = anim_name


## The one-shot playing now, or &"" during locomotion.
func current_action() -> StringName:
	return _action


## Seconds into the current animation.
func get_action_position() -> float:
	return animation_player.current_animation_position


## Changes the playback speed of the current one-shot (e.g. per attack phase).
func set_action_speed(speed: float) -> void:
	if _action != &"":
		animation_player.speed_scale = speed


func is_playing_action() -> bool:
	return _action != &""


## Ends the current one-shot early (e.g. the attack's follow-through once the
## character can move again); locomotion blends back in.
func stop_action() -> void:
	_action = &""
	_queued = &""


func _play(anim_name: StringName, speed: float) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name, locomotion_blend_time)
	animation_player.speed_scale = speed


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != _action:
		return
	if _queued != &"" and not _dead:
		_action = _queued
		_queued = &""
		animation_player.play(_action, 0.0)
		return
	_action = &""


func _on_died() -> void:
	_dead = true
	_action = &""
	_queued = &""
	# Leave `death_animation` empty when a RagdollComponent handles death.
	if death_animation != &"":
		animation_player.speed_scale = 1.0
		animation_player.play(death_animation, blend_time)
