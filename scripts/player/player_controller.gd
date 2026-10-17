class_name PlayerController
extends CharacterBody3D
## Player movement and input: WASD locomotion, mouse aiming, melee attacks.
##
## WASD is always screen-relative (W = up the screen).
## - Not aiming: the character turns to face its movement direction.
## - Holding "aim" (right mouse): the character keeps facing the mouse cursor
##   while moving, so it can walk backwards or strafe.
## - "lock_on" (middle mouse) locks onto the nearest enemy (`lock_on`), and
##   "cycle_target" (Tab) steps to the next one. While locked the character
##   always faces the target, like holding "aim"; the lock wins over "aim".
## - "attack" (left mouse) steps through `light_combo`; "heavy_attack" (E)
##   swings `heavy_attack`. Presses are buffered for `input_buffer_time`, and a
##   buffered press chains out of the current attack's recovery once its
##   AttackProfile.chain_delay has passed. Holding "attack" repeats the first
##   combo step after each full recovery.
## - Attack direction: locked on -> the target; holding "aim" -> the cursor;
##   otherwise the way the model already faces (the cursor is ignored).
## - Attacking stops the character dead. During the wind-up it turns quickly
##   toward the attack direction (target or cursor), then facing locks; the
##   only movement is the attack's lunge. Late in recovery
##   (AttackProfile.move_cancel) movement input ends the attack.
## - "dodge" (Left Shift) rolls (`dodge`) toward the WASD direction, or toward
##   the cursor with no direction held. It can cut into an attack's recovery
##   but not its wind-up or strike; presses are buffered like attacks. During
##   the roll the character is committed (facing locked, other input
##   buffered); movement or a buffered attack cuts the get-up recovery short.
## - "sprint" (hold Left Alt) raises the top speed to `sprint_speed`. Sprinting
##   faces the movement direction even while aiming or locked on. A light /
##   heavy attack started at sprint speed is the `dash_attack` /
##   `dash_heavy_attack`.
## - The attacks come from the equipped weapon (`weapon`, WeaponComponent),
##   which can be swapped at runtime (debug menu); the exported attack fields
##   are only used without one.
## - "walk_toggle" (Left Ctrl) caps the speed at `walk_speed` (`is_walking`).
## - "jump" (Space) jumps `jump_height` from the floor when free to act. In
##   the air steering is weaker (`air_control`); attacks and dodges wait for
##   the landing (their presses stay buffered for `input_buffer_time`).
## - A staggering hit (`reaction`) interrupts everything for its hitstun; a
##   knockdown also turns the character to face the attacker so it falls
##   away from the blow.

signal aim_started
signal aim_stopped

enum AttackInput { NONE, LIGHT, HEAVY }

@export var move_speed: float = 6.0
## Top speed while "sprint" is held.
@export var sprint_speed: float = 8.0
## Top speed while the walk toggle is on.
@export var walk_speed: float = 1.6
@export_group("Movement Feel")
## Speed gained per second toward the input direction (m/s²).
## move_speed / acceleration = seconds to reach full speed from standstill.
@export var acceleration: float = 15.0
## Extra multiplier on acceleration at low speed, fading out toward full speed,
## so the first step has a little push before the stride settles in. 1 = off.
@export var start_boost: float = 1.3
## Speed lost per second when there is no input (m/s²).
@export var deceleration: float = 30.0
## Speed lost per second on the part of the velocity that does not point the
## way the player wants to go (turning, reversing). Higher = tighter turns.
@export var turn_braking: float = 28.0
## How quickly the character turns toward its facing direction.
@export var turn_speed: float = 11.0
## Speed multipliers while strafing (aiming or locked on), by direction
## relative to the facing: forward diagonal (45°), straight sideways and
## straight backwards, blended in between; straight ahead is full speed. They
## keep the body at a pace the directional cycles can match without skating.
## 1 = off.
@export var diagonal_speed_multiplier: float = 0.65
@export var strafe_speed_multiplier: float = 0.6
@export var backpedal_speed_multiplier: float = 0.55
@export_group("Jump")
## Apex height (m) of a jump.
@export var jump_height: float = 1.0
## Gravity multiplier while airborne (snappier arc than real gravity).
@export var air_gravity_multiplier: float = 1.6
## Fraction of the ground acceleration / braking available in the air.
@export_range(0.0, 1.0) var air_control: float = 0.35
@export_group("Combat")
## Light attack chain; each light press continues it, a full recovery resets it.
@export var light_combo: Array[AttackProfile] = []
@export var heavy_attack: AttackProfile
## Light attack started while sprinting at speed. Continues the combo like
## the heavy attack (`light_after_heavy`).
@export var dash_attack: AttackProfile
## Heavy attack started while sprinting at speed (null = `heavy_attack`).
@export var dash_heavy_attack: AttackProfile
## Combo step a light attack continues with after the heavy attack.
@export var light_after_heavy: int = 1
## Seconds an attack press stays queued while it cannot start yet.
@export var input_buffer_time: float = 0.3
## Turn rate toward the cursor during an attack's wind-up (fast, not instant).
@export var attack_turn_speed: float = 22.0
@export var reaction: HitReactionComponent
@export var lock_on: LockOnComponent
@export var dodge: DodgeComponent
## Supplies the attacks above (see _on_weapon_equipped()).
@export var weapon: WeaponComponent
@export_group("")
## When this reaches zero, player input is disabled.
@export var health: HealthComponent
@export var melee: MeleeAttackComponent

var is_aiming: bool = false
## Facing is decoupled from movement (aiming or locked on, not sprinting); the
## animator plays directional locomotion while this is true.
var is_strafing: bool:
	get:
		return (is_aiming or is_locked_on()) and not is_sprinting
## "sprint" held while moving and free to move.
var is_sprinting: bool = false
## Walk toggle on: top speed `walk_speed`; the animator plays the formal walk.
var is_walking: bool = false
var is_dead: bool = false
## When not ZERO, used instead of the mouse cursor position while aiming
## (scripted sequences, tests, a future gamepad stick).
var aim_override: Vector3 = Vector3.ZERO
## Set from input events (not polled) so clicks consumed by UI don't attack.
var _attack_held: bool = false
var _buffered: AttackInput = AttackInput.NONE
var _buffer_left: float = 0.0
var _dodge_buffer_left: float = 0.0
var _jump_buffer_left: float = 0.0
## Index in `light_combo` of the next light attack.
var _combo_step: int = 0
## Horizontal unit vector the character is turning toward.
var facing_direction: Vector3 = Vector3.FORWARD

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	if health:
		health.died.connect(_on_died)
	if reaction:
		reaction.staggered.connect(_on_staggered)
	if melee:
		melee.finished.connect(_on_attack_finished)
	if weapon:
		weapon.equipped.connect(_on_weapon_equipped)
		if weapon.current:
			_on_weapon_equipped(weapon.current)


func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_movement(Vector3.ZERO, delta)
		move_and_slide()
		return

	_update_aim_state()
	# A press made during recovery waits for the chain point however long the
	# attack's chain_delay is; earlier presses expire.
	var awaiting_chain := melee != null \
		and melee.phase == MeleeAttackComponent.Phase.RECOVERY and not melee.can_chain()
	# An attack pressed mid-roll waits for the roll to end.
	var rolling := dodge != null and dodge.is_rolling()
	if not awaiting_chain and not rolling:
		_buffer_left -= delta
	if _buffer_left <= 0.0:
		_buffered = AttackInput.NONE
	_dodge_buffer_left -= delta
	_jump_buffer_left -= delta

	if reaction and melee:
		# Hyper armour while winding up and swinging; recovery is punishable.
		reaction.armored = melee.is_busy() and melee.phase != MeleeAttackComponent.Phase.RECOVERY
	var reacting := reaction != null and reaction.is_reacting()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := _camera_relative_direction(input)
	var grounded := is_on_floor()
	var sprint_held := Input.is_action_pressed("sprint") and move_dir != Vector3.ZERO
	if dodge and not reacting and grounded:
		_update_dodge(move_dir)
	var dodging := dodge != null and dodge.is_dodging()
	if melee and not reacting and not dodging and grounded:
		if move_dir != Vector3.ZERO and _buffered == AttackInput.NONE and melee.can_move_cancel():
			melee.end_recovery()
		var at_sprint_speed := Vector2(velocity.x, velocity.z).length() > move_speed + 0.5
		_update_attacks(sprint_held and at_sprint_speed)
	var attacking := melee != null and melee.is_busy()
	var winding_up := attacking and melee.phase == MeleeAttackComponent.Phase.WINDUP
	is_sprinting = sprint_held and not attacking and not reacting and not dodging

	if attacking or reacting or dodging:
		move_dir = Vector3.ZERO  # Committed: only lunge / knockback / roll move the body.
	if winding_up:
		var aim_dir := _attack_aim()
		if aim_dir != Vector3.ZERO:
			facing_direction = aim_dir
	elif attacking or reacting or dodging:
		pass  # Facing stays locked through the strike, recovery, hitstun and roll.
	elif is_strafing and is_locked_on():
		var target_dir := lock_on.direction_from(global_position)
		if target_dir != Vector3.ZERO:
			facing_direction = target_dir
	elif is_strafing:
		var aim_dir := _cursor_aim()
		if aim_dir != Vector3.ZERO:
			facing_direction = aim_dir
	elif move_dir != Vector3.ZERO:
		facing_direction = move_dir.normalized()

	if is_strafing and move_dir != Vector3.ZERO:
		move_dir *= _strafe_speed_factor(move_dir)
	_apply_movement(move_dir, delta)
	if dodging:
		var roll := dodge.current_velocity()
		velocity.x = roll.x
		velocity.z = roll.z
	elif attacking:
		var forward := -global_basis.z
		var lunge := melee.lunge_speed()
		velocity.x = forward.x * lunge
		velocity.z = forward.z * lunge
	elif reacting:
		velocity.x = reaction.knockback_velocity.x
		velocity.z = reaction.knockback_velocity.z
	if winding_up:
		_apply_rotation(delta, attack_turn_speed)
	elif not attacking and not reacting and not dodging:
		_apply_rotation(delta, turn_speed)
	if _jump_buffer_left > 0.0 and grounded and not attacking and not reacting and not dodging:
		_jump_buffer_left = 0.0
		velocity.y = sqrt(2.0 * _gravity * air_gravity_multiplier * jump_height)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	# Presses only arrive here if no UI control consumed them.
	if event.is_action_pressed("attack"):
		_attack_held = true
		request_attack(false)
	elif event.is_action_pressed("heavy_attack"):
		request_attack(true)
	elif event.is_action_pressed("dodge"):
		request_dodge()
	elif event.is_action_pressed("jump"):
		request_jump()
	elif event.is_action_pressed("walk_toggle"):
		is_walking = not is_walking
	elif event.is_action_pressed("lock_on"):
		if lock_on and not is_dead:
			lock_on.toggle()
	elif event.is_action_pressed("cycle_target"):
		if lock_on and not is_dead:
			lock_on.cycle()
			get_viewport().set_input_as_handled()  # Keep Tab from moving UI focus.


func _input(event: InputEvent) -> void:
	# Releases are always seen, even over UI, so the attack never sticks.
	if event.is_action_released("attack"):
		_attack_held = false


## Queues an attack press; it starts as soon as the current state allows.
func request_attack(heavy: bool) -> void:
	if is_dead:
		return
	_buffered = AttackInput.HEAVY if heavy else AttackInput.LIGHT
	_buffer_left = input_buffer_time


## Queues a dodge press; it starts as soon as the current state allows.
func request_dodge() -> void:
	if is_dead:
		return
	_dodge_buffer_left = input_buffer_time


## Queues a jump press; it happens as soon as the character is free on the
## floor.
func request_jump() -> void:
	if is_dead:
		return
	_jump_buffer_left = input_buffer_time


func _update_dodge(move_dir: Vector3) -> void:
	if dodge.is_recovering() and (move_dir != Vector3.ZERO or _buffered != AttackInput.NONE
			or _attack_held):
		dodge.end_recovery()
	if _dodge_buffer_left <= 0.0 or not dodge.is_ready():
		return
	if melee and melee.is_busy():
		if melee.phase != MeleeAttackComponent.Phase.RECOVERY:
			return  # Wind-up and strike are committed; the press stays buffered.
		melee.end_recovery()
	var dir := move_dir.normalized() if move_dir != Vector3.ZERO else _cursor_aim()
	if dir == Vector3.ZERO:
		dir = -global_basis.z
	if not dodge.start(dir):
		return
	_dodge_buffer_left = 0.0
	facing_direction = dodge.direction
	rotation.y = atan2(-facing_direction.x, -facing_direction.z)  # Roll the way it goes.


## `sprinting`: a light attack starting now is the dash attack.
func _update_attacks(sprinting: bool = false) -> void:
	if melee.is_busy():
		if _buffered != AttackInput.NONE and melee.can_chain():
			var next := _next_profile(_buffered)
			if next:
				_buffered = AttackInput.NONE
				_begin_attack(next, true)
		return
	var wanted := _buffered
	if wanted == AttackInput.NONE and _attack_held:
		wanted = AttackInput.LIGHT
		_combo_step = 0
	if wanted == AttackInput.NONE:
		return
	_buffered = AttackInput.NONE
	var profile := _next_profile(wanted)
	if sprinting:
		if wanted == AttackInput.LIGHT and dash_attack:
			profile = dash_attack
		elif wanted == AttackInput.HEAVY and dash_heavy_attack:
			profile = dash_heavy_attack
	if profile:
		_begin_attack(profile, false)
	elif melee.start():
		_stop_dead()  # No profiles assigned: the component's own fields.


func _next_profile(kind: AttackInput) -> AttackProfile:
	if kind == AttackInput.HEAVY:
		return heavy_attack
	if light_combo.is_empty():
		return null
	return light_combo[_combo_step % light_combo.size()]


func _begin_attack(profile: AttackProfile, chained: bool) -> void:
	var started := melee.chain(profile) if chained else melee.start(profile)
	if not started:
		return
	if profile in [heavy_attack, dash_attack, dash_heavy_attack]:
		_combo_step = light_after_heavy
	else:
		_combo_step = (light_combo.find(profile) + 1) % maxi(light_combo.size(), 1)
	var aim_dir := _attack_aim()
	if aim_dir != Vector3.ZERO:
		facing_direction = aim_dir
	else:
		# Attack exactly where the model points, even mid-turn.
		var forward := -global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			facing_direction = forward.normalized()
	_stop_dead()


## Hard stop: no slide into the swing.
func _stop_dead() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## Takes the weapon's attacks. An attack in progress is cancelled.
func _on_weapon_equipped(new_weapon: WeaponDefinition) -> void:
	if melee:
		melee.cancel()
		if melee.animator and melee.animator.is_playing_action():
			melee.animator.stop_action()
	light_combo = new_weapon.light_combo
	heavy_attack = new_weapon.heavy_attack
	dash_attack = new_weapon.dash_attack
	dash_heavy_attack = new_weapon.dash_heavy_attack
	light_after_heavy = new_weapon.light_after_heavy
	_buffered = AttackInput.NONE
	_combo_step = 0


func _on_attack_finished() -> void:
	# A full recovery without a follow-up ends the combo.
	_combo_step = 0


func _on_staggered(event: HitEvent) -> void:
	if melee:
		melee.cancel()
	if dodge:
		dodge.cancel()
	_buffered = AttackInput.NONE
	_dodge_buffer_left = 0.0
	_jump_buffer_left = 0.0
	_combo_step = 0
	if reaction.is_knocked_down() and event.direction != Vector3.ZERO:
		# Face the attacker: the knockdown clip falls backwards.
		facing_direction = -event.direction
		rotation.y = atan2(-facing_direction.x, -facing_direction.z)


func _on_died() -> void:
	is_dead = true
	_attack_held = false
	_buffered = AttackInput.NONE
	_dodge_buffer_left = 0.0
	_jump_buffer_left = 0.0
	is_sprinting = false
	if dodge:
		dodge.cancel()
	# The body stays as an anchor but no longer blocks enemies.
	collision_layer = 0
	if melee:
		melee.cancel()
	if lock_on:
		lock_on.release()
	if is_aiming:
		is_aiming = false
		aim_stopped.emit()


func _update_aim_state() -> void:
	var aiming_now := Input.is_action_pressed("aim")
	if aiming_now != is_aiming:
		is_aiming = aiming_now
		if is_aiming:
			aim_started.emit()
		else:
			aim_stopped.emit()


func is_locked_on() -> bool:
	return lock_on != null and lock_on.is_locked()


## Direction an attack goes: the locked target, else the cursor while aiming,
## else ZERO (keep the model's current facing).
func _attack_aim() -> Vector3:
	if is_locked_on():
		return lock_on.direction_from(global_position)
	if is_aiming:
		return _cursor_aim()
	return Vector3.ZERO


func _cursor_aim() -> Vector3:
	if aim_override != Vector3.ZERO:
		return Vector3(aim_override.x, 0.0, aim_override.z).normalized()
	return get_aim_direction_at(get_viewport().get_mouse_position())


## Returns the horizontal unit direction from the player toward the point
## under `screen_pos`, or Vector3.ZERO if it cannot be determined.
func get_aim_direction_at(screen_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_pos)
	var normal := camera.project_ray_normal(screen_pos)
	var ground := Plane(Vector3.UP, global_position.y)
	var hit: Variant = ground.intersects_ray(origin, normal)
	if hit == null:
		return Vector3.ZERO
	var offset: Vector3 = hit - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		return Vector3.ZERO
	return offset.normalized()


func _camera_relative_direction(input: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if not camera or input == Vector2.ZERO:
		return Vector3.ZERO
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	return right * input.x + forward * -input.y


## Momentum-based horizontal movement. Velocity is split into the part along
## the wanted direction (accelerates toward the target speed) and the part
## across or against it (brakes away), so starts ramp up, stops slide out and
## direction changes carve a short arc instead of snapping.
func _apply_movement(move_dir: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var on_floor := is_on_floor()
	# Weaker steering in the air; with no input a jump keeps its momentum.
	var control := 1.0 if on_floor else air_control
	if move_dir == Vector3.ZERO:
		if on_floor:
			horizontal = horizontal.move_toward(Vector3.ZERO, deceleration * delta)
	else:
		var wish_dir := move_dir.normalized()
		var top_speed := _top_speed()
		var target_speed := move_dir.length() * top_speed
		var along := horizontal.dot(wish_dir)
		var across := horizontal - wish_dir * along
		across = across.move_toward(Vector3.ZERO, turn_braking * control * delta)
		if along < 0.0:
			# Moving away from the wanted direction: brake hard first.
			along = move_toward(along, 0.0, turn_braking * control * delta)
		elif along > target_speed:
			# Slowed (e.g. attacking, sprint released) or gently released the stick.
			along = move_toward(along, target_speed, deceleration * control * delta)
		else:
			var t := clampf(along / top_speed, 0.0, 1.0)
			var accel := acceleration * lerpf(start_boost, 1.0, t)
			along = move_toward(along, target_speed, accel * control * delta)
		horizontal = wish_dir * along + across
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if on_floor:
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * air_gravity_multiplier * delta


func _top_speed() -> float:
	if is_sprinting:
		return sprint_speed
	if is_walking:
		return walk_speed
	return move_speed


## Speed multiplier for moving along `move_dir` while facing `facing_direction`.
func _strafe_speed_factor(move_dir: Vector3) -> float:
	var angle := rad_to_deg(facing_direction.angle_to(move_dir.normalized()))
	if angle <= 45.0:
		return lerpf(1.0, diagonal_speed_multiplier, angle / 45.0)
	if angle <= 90.0:
		return lerpf(diagonal_speed_multiplier, strafe_speed_multiplier, (angle - 45.0) / 45.0)
	return lerpf(strafe_speed_multiplier, backpedal_speed_multiplier, (angle - 90.0) / 90.0)


func _apply_rotation(delta: float, rate: float) -> void:
	var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rate * delta))
