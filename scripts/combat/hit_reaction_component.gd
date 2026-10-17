class_name HitReactionComponent
extends Node
## Makes a character visibly react to hits from its HurtboxComponent.
##
## - Stagger: hitstun (the owner must stop acting while `is_reacting()`),
##   knockback velocity that decays smoothly (the owner applies it through
##   move_and_slide, so walls stop it), a hit animation and a procedural lean.
## - Poise: while `armored` (e.g. during the owner's own attack), hits only
##   flinch (lean + a little knockback) until their AttackProfile.stagger adds
##   up past `poise`; then the hit staggers and `staggered` asks the owner to
##   cancel its action. Unarmoured, every attack staggers.
## - Knockdown: a staggering hit whose AttackProfile has `knockdown` throws
##   the character down (`knockdown_animation`, which ends lying on its back),
##   then it gets up (`get_up_animation`). The whole sequence is the hitstun.
##   Hits while down still deal damage but don't restart it; with
##   `knockdown_invulnerable` the hurtbox ignores them until it is up.
## - Hits without an AttackProfile (hazards) and lethal hits never stagger;
##   the ragdoll takes over on death.

## The owner should cancel what it is doing (attack, navigation).
signal staggered(event: HitEvent)
signal flinched(event: HitEvent)
## Hitstun is over; normal behaviour may resume.
signal recovered

@export var hurtbox: HurtboxComponent
@export var health: HealthComponent
## Leaned procedurally on impact (the character's visual root, pivot at feet).
@export var visual: Node3D
@export var animator: CharacterAnimator

@export_group("Stagger")
## Played when a light / heavy attack staggers. Empty = no animation.
@export var light_animation: StringName = &"Hit_Chest"
@export var heavy_animation: StringName = &"Hit_Head"
@export var hitstun_scale: float = 1.0
## Multiplier on incoming knockback speed (heavier characters < 1).
@export var knockback_scale: float = 1.0
## Knockback deceleration (m/s²).
@export var knockback_friction: float = 18.0

@export_group("Knockdown")
@export var knockdown_animation: StringName = &"UAL2/Hit_Knockback"
## Starts from the lying pose `knockdown_animation` ends in.
@export var get_up_animation: StringName = &"UAL2/LayToIdle"
@export var knockdown_speed: float = 1.0
@export var get_up_speed: float = 1.3
## Ignore hits while knocked down (sets HurtboxComponent.invulnerable).
@export var knockdown_invulnerable: bool = false

@export_group("Poise")
## Set by the owner while it should resist interruption.
@export var armored: bool = false
@export var poise: float = 30.0
## Poise damage resets after this long without being hit.
@export var poise_reset_time: float = 2.0
## Knockback fraction kept when a hit does not stagger.
@export_range(0.0, 1.0) var flinch_knockback: float = 0.2

@export_group("Lean")
## Lean (degrees) for a staggering light / heavy hit; flinches lean half.
@export var light_lean_degrees: float = 7.0
@export var heavy_lean_degrees: float = 13.0
## Spring stiffness and damping of the lean (higher = snappier).
@export var lean_stiffness: float = 260.0
@export var lean_damping: float = 22.0

var knockback_velocity: Vector3 = Vector3.ZERO
var poise_damage: float = 0.0

var _stun_left: float = 0.0
var _knocked_down: bool = false
var _since_hit: float = 0.0
var _lean_axis: Vector3 = Vector3.RIGHT
var _lean: float = 0.0
var _lean_speed: float = 0.0
var _visual_rest: Basis
var _dead: bool = false


func _ready() -> void:
	hurtbox.hit_received.connect(_on_hit_received)
	if health:
		health.died.connect(_on_died)
	if visual:
		_visual_rest = visual.basis


func is_reacting() -> bool:
	return _stun_left > 0.0


## True from a knockdown hit until the character is back on its feet.
func is_knocked_down() -> bool:
	return _knocked_down


## Seconds a knockdown lasts (fall + get-up), or 0 if its clips are missing.
func knockdown_duration() -> float:
	if not _has_knockdown_clips():
		return 0.0
	var anims := animator.animation_player
	return anims.get_animation(knockdown_animation).length / maxf(knockdown_speed, 0.01) \
		+ anims.get_animation(get_up_animation).length / maxf(get_up_speed, 0.01)


func _on_hit_received(event: HitEvent) -> void:
	if _dead or event.lethal:
		return
	_since_hit = 0.0
	if _knocked_down:
		return  # Already down: the damage lands, the reaction doesn't restart.
	var profile := event.profile
	if profile == null:
		_kick_lean(event.direction, light_lean_degrees * 0.5)
		flinched.emit(event)
		return
	var breaks := not armored
	if armored:
		poise_damage += profile.stagger
		breaks = poise_damage >= poise
	var lean := heavy_lean_degrees if profile.is_heavy() else light_lean_degrees
	if not breaks:
		knockback_velocity = event.direction * profile.knockback * knockback_scale * flinch_knockback
		_kick_lean(event.direction, lean * 0.5)
		flinched.emit(event)
		return
	poise_damage = 0.0
	knockback_velocity = event.direction * profile.knockback * knockback_scale
	if profile.knockdown and _has_knockdown_clips():
		_knock_down(event)
		return
	_stun_left = maxf(_stun_left, profile.hitstun * hitstun_scale)
	_kick_lean(event.direction, lean)
	var anim := heavy_animation if profile.is_heavy() else light_animation
	if animator and anim != &"" and animator.animation_player.has_animation(anim):
		var length := animator.animation_player.get_animation(anim).length
		animator.play_action(anim, clampf(length / maxf(_stun_left, 0.05), 0.75, 2.0))
	staggered.emit(event)


func _knock_down(event: HitEvent) -> void:
	_knocked_down = true
	_stun_left = knockdown_duration()
	animator.play_action(knockdown_animation, knockdown_speed)
	animator.queue_action(get_up_animation, get_up_speed)
	staggered.emit(event)
	# After the signal: owners cancel their dodge there, which clears i-frames.
	if knockdown_invulnerable and hurtbox:
		hurtbox.invulnerable = true


func _has_knockdown_clips() -> bool:
	if animator == null or knockdown_animation == &"" or get_up_animation == &"":
		return false
	var anims := animator.animation_player
	return anims.has_animation(knockdown_animation) and anims.has_animation(get_up_animation)


func _physics_process(delta: float) -> void:
	_since_hit += delta
	if _since_hit >= poise_reset_time:
		poise_damage = 0.0
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_friction * delta)
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			_stun_left = 0.0
			if animator and animator.current_action() in [light_animation, heavy_animation,
					knockdown_animation, get_up_animation]:
				animator.stop_action()
			if _knocked_down:
				_knocked_down = false
				if knockdown_invulnerable and hurtbox:
					hurtbox.invulnerable = false
			recovered.emit()


func _process(delta: float) -> void:
	if visual == null or _dead:
		return
	if is_zero_approx(_lean) and is_zero_approx(_lean_speed):
		return
	# Damped spring back to upright.
	_lean_speed += (-lean_stiffness * _lean - lean_damping * _lean_speed) * delta
	_lean += _lean_speed * delta
	if absf(_lean) < 0.0005 and absf(_lean_speed) < 0.01:
		_lean = 0.0
		_lean_speed = 0.0
	visual.basis = Basis(_lean_axis, _lean) * _visual_rest


## Throws the upper body along `direction` (world, horizontal).
func _kick_lean(direction: Vector3, degrees: float) -> void:
	if visual == null or direction == Vector3.ZERO or degrees <= 0.0:
		return
	var parent := visual.get_parent() as Node3D
	var local := direction
	if parent:
		local = parent.global_basis.inverse() * direction
	local.y = 0.0
	if local.length_squared() < 0.0001:
		return
	# Rotating about UP × dir moves the top of the body along dir.
	_lean_axis = Vector3.UP.cross(local.normalized()).normalized()
	_lean_speed += deg_to_rad(degrees) * sqrt(lean_stiffness) * 1.6


func _on_died() -> void:
	# The ragdoll owns the body now; leave the visual where it is.
	_dead = true
	_stun_left = 0.0
	_knocked_down = false
	knockback_velocity = Vector3.ZERO
