class_name MeleeAttackComponent
extends Node
## Runs one melee attack at a time: wind-up -> strike (hitbox live) -> recovery.
## Used by both the player and enemies; the owner decides when to call start()
## and handles facing/movement while is_busy().
##
## An attack is an AttackProfile. Without one, the exported fields below
## describe it (the enemy sets them from its EnemyStats). Each phase plays its
## own segment of the animation (see AttackProfile), so the visible swing and
## the hit window stay in sync whatever the timings are.

signal started(profile: AttackProfile)
## The hitbox became live.
signal struck(profile: AttackProfile)
## The hitbox closed; recovery began.
signal strike_ended(profile: AttackProfile)
## Recovery ended; a new attack can start.
signal finished
## The current attack damaged something.
signal hit_confirmed(event: HitEvent)

enum Phase { READY, WINDUP, STRIKE, RECOVERY }

## Animation time (s) played during `AttackProfile.windup_hold`, so the held
## pose still breathes instead of freezing.
const HOLD_CREEP := 0.03

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
## Seconds into `animation` where the blade's sweep ends. When set (greater
## than `animation_strike_time`), each phase plays its own segment.
## 0 = one speed for the whole attack.
@export var animation_strike_end: float = 0.0
## Seconds into `animation` reached when recovery ends. 0 = full length.
@export var animation_recovery_end: float = 0.0

var phase: Phase = Phase.READY
var phase_time: float = 0.0
## The attack in progress (or the last one).
var current: AttackProfile
## True once the current attack has damaged something.
var has_hit: bool = false

var _exports_profile: AttackProfile
var _anim_from: float = 0.0
var _holding: bool = false


func _ready() -> void:
	hitbox.active = false
	hitbox.hit_landed.connect(_on_hit_landed)
	if telegraph:
		telegraph.hide()


func is_busy() -> bool:
	return phase != Phase.READY


## Starts an attack (`profile`, or the exported fields). Returns false if one
## is already in progress.
func start(profile: AttackProfile = null) -> bool:
	if is_busy():
		return false
	_begin(profile if profile else _profile_from_exports(), false)
	return true


## True when the current attack's recovery may be cut into a follow-up.
func can_chain() -> bool:
	return phase == Phase.RECOVERY and current != null \
		and phase_time >= current.chain_delay


## Starts `profile` out of the current recovery (combo). The animation carries
## on from its current pose when both attacks use the same clip.
func chain(profile: AttackProfile) -> bool:
	if profile == null or not can_chain():
		return false
	_begin(profile, true)
	return true


## True when movement input may end the current recovery early.
func can_move_cancel() -> bool:
	return phase == Phase.RECOVERY and current != null 		and current.move_cancel >= 0.0 and phase_time >= current.move_cancel


## Ends the current recovery now (movement cancel); locomotion blends in.
func end_recovery() -> void:
	if phase != Phase.RECOVERY:
		return
	_finish()


## Aborts the attack immediately (stagger, death). Does not emit `finished`.
func cancel() -> void:
	hitbox.active = false
	if telegraph:
		telegraph.hide()
	_enter(Phase.READY)


## Forward speed (m/s) the owner should move at right now: the clip's root
## motion for `root_motion` attacks, else the lunge (0 outside it or once the
## attack has connected).
func lunge_speed() -> float:
	if current != null and current.root_motion:
		return _root_motion_speed()
	if current == null or current.lunge_distance <= 0.0 or has_hit:
		return 0.0
	var lead := minf(current.lunge_lead, current.windup)
	var in_lunge := phase == Phase.STRIKE \
		or (phase == Phase.WINDUP and phase_time >= current.windup - lead)
	if not in_lunge:
		return 0.0
	return current.lunge_distance / maxf(lead + current.strike_duration, 0.01)


## The clip's forward travel rate at the current animation position, times
## the playback speed. 0 when the clip has no root motion or isn't playing
## (e.g. its follow-through was cut).
func _root_motion_speed() -> float:
	if animator == null or phase == Phase.READY or animator.current_action() != current.animation:
		return 0.0
	var anim := animator.animation_player.get_animation(current.animation)
	var curve: PackedFloat32Array = anim.get_meta(&"root_motion", PackedFloat32Array())
	if curve.size() < 2:
		return 0.0
	var fps: float = anim.get_meta(&"root_motion_fps", 30.0)
	var frame := clampf(animator.get_action_position() * fps, 0.0, curve.size() - 1.001)
	var i := int(frame)
	return (curve[i + 1] - curve[i]) * fps * animator.animation_player.speed_scale \
		* current.root_motion_scale


func _begin(profile: AttackProfile, chained: bool) -> void:
	current = profile
	has_hit = false
	hitbox.active = false
	hitbox.damage = profile.damage
	hitbox.profile = profile
	_holding = false
	_enter(Phase.WINDUP)
	if telegraph:
		telegraph.scale = Vector3(1.0, 1.0, 0.01)
		telegraph.show()
	if animator and profile.animation != &"":
		_anim_from = profile.anim_start
		var continuing := chained and animator.current_action() == profile.animation
		if continuing:
			var position := animator.get_action_position()
			if position < profile.anim_strike_start - HOLD_CREEP:
				_anim_from = position
			else:
				continuing = false
		var speed := _windup_speed()
		if continuing:
			animator.set_action_speed(speed)
		else:
			animator.play_action(profile.animation, speed, _anim_from)
	started.emit(profile)


func _physics_process(delta: float) -> void:
	if phase == Phase.READY:
		return
	phase_time += delta
	match phase:
		Phase.WINDUP:
			if telegraph:
				var progress := clampf(phase_time / maxf(current.windup, 0.001), 0.01, 1.0)
				telegraph.scale = Vector3(1.0, 1.0, progress)
			if not _holding and current.windup_hold > 0.0 \
					and phase_time >= current.windup - current.windup_hold:
				_holding = true
				_set_speed(HOLD_CREEP / current.windup_hold)
			if phase_time >= current.windup:
				_enter(Phase.STRIKE)
				if telegraph:
					telegraph.hide()
				hitbox.active = true
				if current.uses_segments():
					_set_speed(_segment_speed(current.anim_strike_start,
						current.anim_strike_end, current.strike_duration))
				struck.emit(current)
		Phase.STRIKE:
			if phase_time >= current.strike_duration:
				_enter(Phase.RECOVERY)
				hitbox.close_after_current_pose()
				if current.uses_segments():
					_set_speed(_segment_speed(0.0, _recovery_span(), current.recovery))
					if animator and current.recovery_animation != &"":
						animator.queue_action(current.recovery_animation)
				strike_ended.emit(current)
		Phase.RECOVERY:
			if phase_time >= current.recovery:
				_finish()


func _finish() -> void:
	_enter(Phase.READY)
	# Cut the animation's follow-through so locomotion resumes.
	if animator and animator.is_playing_action():
		animator.stop_action()
	finished.emit()


func _enter(new_phase: Phase) -> void:
	phase = new_phase
	phase_time = 0.0


func _on_hit_landed(event: HitEvent) -> void:
	has_hit = true
	hit_confirmed.emit(event)


func _windup_speed() -> float:
	if not current.uses_segments():
		# Legacy: one speed so the impact frame lands at the end of the wind-up.
		return _segment_speed(_anim_from, current.anim_strike_start, current.windup)
	var hold := minf(current.windup_hold, current.windup)
	var raise_end := current.anim_strike_start - (HOLD_CREEP if hold > 0.0 else 0.0)
	return _segment_speed(_anim_from, raise_end, current.windup - hold)


## Playback speed that covers animation time `from` -> `to` in `duration` s.
static func _segment_speed(from: float, to: float, duration: float) -> float:
	if duration <= 0.0 or to <= from:
		return 1.0
	return (to - from) / duration


## Animation seconds played during recovery: the rest of the swing (up to
## anim_recovery_end), or the rest of the swing clip plus the recovery clip.
func _recovery_span() -> float:
	var swing_end := _clip_length(current.animation)
	if current.recovery_animation == &"":
		if current.anim_recovery_end > current.anim_strike_end:
			swing_end = current.anim_recovery_end
		return maxf(swing_end - current.anim_strike_end, 0.0)
	var rec_end := current.anim_recovery_end
	if rec_end <= 0.0:
		rec_end = _clip_length(current.recovery_animation)
	return maxf(swing_end - current.anim_strike_end, 0.0) + rec_end


func _clip_length(anim_name: StringName) -> float:
	var anim_player := animator.animation_player if animator else null
	if anim_player and anim_player.has_animation(anim_name):
		return anim_player.get_animation(anim_name).length
	return current.anim_strike_end


func _set_speed(speed: float) -> void:
	if animator and animator.is_playing_action():
		animator.set_action_speed(speed)


## The exported fields as a profile (rebuilt per attack: owners such as
## EnemyController set them after this node is ready).
func _profile_from_exports() -> AttackProfile:
	if _exports_profile == null:
		_exports_profile = AttackProfile.new()
	var p := _exports_profile
	p.damage = damage
	p.windup = windup
	p.strike_duration = strike_duration
	p.recovery = recovery
	p.animation = animation
	p.anim_strike_start = animation_strike_time
	p.anim_strike_end = animation_strike_end
	p.anim_recovery_end = animation_recovery_end
	p.stagger = damage
	return p
