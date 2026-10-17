class_name CharacterAnimator
extends Node
## Drives a character's AnimationPlayer from its body's movement and health.
## Shared by the player and enemies. Gameplay code only calls `play_action()`
## for one-shot animations (attacks); locomotion, jumps / falls, landings,
## idle variants and death are automatic.
##
## Optional body properties it reads (via get(), so any body works):
## `is_strafing` (directional cycles), `is_walking` (formal walk cycle).

@export var body: CharacterBody3D
@export var health: HealthComponent
@export var animation_player: AnimationPlayer

@export_group("Animations")
@export var idle_animation: StringName = &"Sword_Idle"
@export var walk_animation: StringName = &"Walk"
@export var run_animation: StringName = &"Jog_Fwd"
## Played above `run_to_sprint_speed`. Empty = never sprint.
@export var sprint_animation: StringName = &"Sprint"
## Walk cycle used instead of `walk_animation` while the body's `is_walking`
## is true (walk toggle). Empty = always `walk_animation`.
@export var formal_walk_animation: StringName = &"Walk_Formal"
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
## Speed (m/s) above which the run cycle switches to the sprint cycle
## (same hysteresis as walk/run).
@export var run_to_sprint_speed: float = 7.0
## Movement speed (m/s) at which the sprint cycle plays at normal rate
## (measured from its stride against Jog_Fwd's: ~7.06 m/s).
@export var sprint_reference_speed: float = 7.06
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

@export_group("Jump")
## One-shot played when the body leaves the floor moving up (a jump).
@export var jump_animation: StringName = &"Jump_Start"
## Seconds into `jump_animation` to start from (skips the crouch, so the
## take-off shows on the same tick the body leaves the ground).
@export var jump_animation_start: float = 0.1
@export var jump_animation_speed: float = 1.5
## Used instead of `jump_animation` when taking off at run speed (above
## `walk_to_run_speed`), from `run_jump_animation_start`, at the same speed.
## Empty = always `jump_animation`.
@export var run_jump_animation: StringName = &""
@export var run_jump_animation_start: float = 0.0
## Loop played while airborne once the jump clip ends (or when falling).
@export var air_animation: StringName = &"Jump"
## One-shot played on touching down after at least `min_air_time` airborne.
@export var land_animation: StringName = &"Jump_Land"
## Seconds into `land_animation` to start from (the moment of contact).
@export var land_animation_start: float = 0.05
@export var land_animation_speed: float = 1.4
## Seconds after touching down before moving cuts the landing short.
@export var land_cancel_time: float = 0.15
## Shorter airborne spells (steps, bumps) don't change the animation.
@export var min_air_time: float = 0.12
## Vertical speed (m/s) leaving the floor that counts as a jump, not a fall.
@export var jump_detect_speed: float = 1.0

@export_group("Idle Variants")
## Played now and then while standing still (not strafing). Empty = none.
@export var idle_variants: Array[StringName] = []
## Seconds of standing still before a variant plays (and between variants).
@export var idle_variant_delay: float = 8.0
## A variant loops for at least this long (whole loops), then the base idle
## returns.
@export var idle_variant_min_duration: float = 4.0

var _dead: bool = false
var _action: StringName = &""
var _queued: StringName = &""
var _queued_speed: float = -1.0
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _land_time: float = -1.0
var _idle_time: float = 0.0
var _variant: StringName = &""
var _variant_left: float = 0.0
var _last_variant: StringName = &""
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
	var loops: Array[StringName] = [idle_animation, walk_animation, run_animation,
		sprint_animation, formal_walk_animation, air_animation]
	loops.append_array(idle_variants)
	for anim_name in loops:
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


func _process(delta: float) -> void:
	if _dead:
		return
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := horizontal.length()
	_update_air(delta, speed)
	if _action != &"":
		_idle_time = 0.0
		return
	if _air_time >= min_air_time:
		_idle_time = 0.0
		_play(air_animation, 1.0)
		return
	if speed < move_threshold:
		_play_idle(delta)
		return
	_idle_time = 0.0
	_variant = &""
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
		anim = _walk_cycle()
		reference = walk_reference_speed
	elif _uses_sprint(speed):
		anim = sprint_animation
		reference = sprint_reference_speed
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
	var current := StringName(animation_player.current_animation)
	if current == walk_animation or (current == formal_walk_animation and current != &""):
		return speed < walk_to_run_speed + walk_run_hysteresis
	return speed < walk_to_run_speed - walk_run_hysteresis


func _walk_cycle() -> StringName:
	if formal_walk_animation != &"" and body.get(&"is_walking") == true \
			and animation_player.has_animation(formal_walk_animation):
		return formal_walk_animation
	return walk_animation


func _uses_sprint(speed: float) -> bool:
	if sprint_animation == &"" or not animation_player.has_animation(sprint_animation):
		return false
	if animation_player.current_animation == sprint_animation:
		return speed > run_to_sprint_speed - walk_run_hysteresis
	return speed > run_to_sprint_speed + walk_run_hysteresis


## Jump start on take-off, landing on touch-down. The air loop itself is
## picked in _process() once nothing else plays.
func _update_air(delta: float, speed: float) -> void:
	var on_floor := body.is_on_floor()
	if not on_floor:
		if _was_on_floor and body.velocity.y > jump_detect_speed:
			_air_time = min_air_time  # A jump: show it at once.
			if run_jump_animation != &"" and speed >= walk_to_run_speed \
					and animation_player.has_animation(run_jump_animation):
				_play_one_shot(run_jump_animation, jump_animation_speed, run_jump_animation_start)
			else:
				_play_one_shot(jump_animation, jump_animation_speed, jump_animation_start)
		_air_time += delta
	else:
		if _air_time >= min_air_time and _action in [&"", jump_animation, run_jump_animation]:
			_land_time = 0.0
			_play_one_shot(land_animation, land_animation_speed, land_animation_start)
		_air_time = 0.0
		if _land_time >= 0.0:
			_land_time += delta
			if _action != land_animation:
				_land_time = -1.0
			elif _land_time >= land_cancel_time and speed >= move_threshold:
				stop_action()  # Moving off: the run takes over from the squat.
				_land_time = -1.0
	_was_on_floor = on_floor


func _play_one_shot(anim_name: StringName, speed: float, from_time: float) -> void:
	if anim_name != &"" and animation_player.has_animation(anim_name):
		play_action(anim_name, speed, from_time)


## True while airborne long enough to show the jump / air animations.
func is_airborne() -> bool:
	return _air_time >= min_air_time


## Base idle, with a random variant now and then.
func _play_idle(delta: float) -> void:
	if idle_variants.is_empty() or body.get(&"is_strafing") == true:
		_idle_time = 0.0
		_variant = &""
		_play(idle_animation, 1.0)
		return
	if _variant != &"":
		_variant_left -= delta
		if _variant_left <= 0.0:
			_variant = &""
			_idle_time = 0.0
		else:
			_play(_variant, 1.0)
			return
	_idle_time += delta
	if _idle_time >= idle_variant_delay:
		_start_variant()
		if _variant != &"":
			_play(_variant, 1.0)
			return
	_play(idle_animation, 1.0)


func _start_variant() -> void:
	var choices: Array[StringName] = []
	for anim_name in idle_variants:
		if anim_name != _last_variant and animation_player.has_animation(anim_name):
			choices.append(anim_name)
	if choices.is_empty():
		_idle_time = 0.0
		return
	_variant = choices.pick_random()
	_last_variant = _variant
	var length := animation_player.get_animation(_variant).length
	_variant_left = ceilf(idle_variant_min_duration / maxf(length, 0.01)) * length


## The idle variant playing now, or &"".
func current_idle_variant() -> StringName:
	return _variant


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


## Plays `anim_name` straight after the current one-shot ends, without a
## crossfade (for clips that continue each other's pose, e.g. a swing and its
## return to guard), at `speed` (< 0 = the current speed). Cleared by any new
## action.
func queue_action(anim_name: StringName, speed: float = -1.0) -> void:
	if _action != &"":
		_queued = anim_name
		_queued_speed = speed


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
		if _queued_speed >= 0.0:
			animation_player.speed_scale = _queued_speed
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
