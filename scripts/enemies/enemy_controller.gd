class_name EnemyController
extends CharacterBody3D
## Melee enemy AI: idle (return home) -> chase -> telegraphed attack -> dead.
##
## Targets the first node in the "player" group. Movement uses a
## NavigationAgent3D on the baked navigation mesh. Numbers come from `stats`.

signal state_changed(new_state: State)
## Emitted when the wind-up (telegraph) begins.
signal attack_started
## Emitted when the hitbox becomes live.
signal attack_struck

enum State { IDLE, CHASE, ATTACK, DEAD }
enum AttackPhase { WINDUP, STRIKE, RECOVERY }

@export var stats: EnemyStats
@export var health: HealthComponent
@export var nav_agent: NavigationAgent3D
@export var attack_hitbox: HitboxComponent
@export var hurtbox: HurtboxComponent
## Ground marker shown during wind-up; scaled along Z from 0 to 1.
@export var telegraph: Node3D
@export var animator: CharacterAnimator

@export_group("Attack animation")
@export var attack_animation: StringName = &"HumanArmature|swordAttackJump"
## Seconds into `attack_animation` where the blow visually lands.
@export var attack_animation_strike_time: float = 0.5

@export_group("Navigation")
## How often the chase path is recomputed.
@export var repath_interval: float = 0.2
## Distance from home that counts as "home".
@export var home_tolerance: float = 0.5

var state: State = State.IDLE
var target: Node3D
var facing_direction: Vector3 = Vector3.FORWARD

var _attack_phase: AttackPhase = AttackPhase.WINDUP
var _phase_time: float = 0.0
var _repath_timer: float = 0.0
var _home: Vector3
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	health.max_health = stats.max_health
	health.died.connect(_on_died)
	attack_hitbox.damage = stats.attack_damage
	attack_hitbox.active = false
	telegraph.hide()
	_home = global_position
	facing_direction = -global_basis.z


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D

	var move_dir := Vector3.ZERO
	match state:
		State.IDLE:
			move_dir = _process_idle()
		State.CHASE:
			move_dir = _process_chase(delta)
		State.ATTACK:
			_process_attack(delta)

	_apply_movement(move_dir, delta)
	_apply_rotation(delta)
	move_and_slide()


func _process_idle() -> Vector3:
	if _target_alive() and _distance_to_target() <= stats.detection_radius:
		_set_state(State.CHASE)
		return Vector3.ZERO
	if _flat(global_position - _home).length() > home_tolerance:
		return _navigate_to(_home)
	return Vector3.ZERO


func _process_chase(delta: float) -> Vector3:
	if not _target_alive() or _distance_to_target() > stats.lose_interest_radius:
		_set_state(State.IDLE)
		return Vector3.ZERO
	if _distance_to_target() <= stats.attack_range:
		_start_attack()
		return Vector3.ZERO
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		nav_agent.target_position = target.global_position
	return _next_path_direction()


func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_phase = AttackPhase.WINDUP
	_phase_time = 0.0
	# Lock facing at the start so the player can sidestep the blow.
	var to_target := _flat(target.global_position - global_position)
	if to_target.length_squared() > 0.0001:
		facing_direction = to_target.normalized()
		rotation.y = _yaw_for(facing_direction)
	telegraph.scale = Vector3(1.0, 1.0, 0.01)
	telegraph.show()
	animator.play_action(attack_animation, attack_animation_strike_time / stats.attack_windup)
	attack_started.emit()


func _process_attack(delta: float) -> void:
	_phase_time += delta
	match _attack_phase:
		AttackPhase.WINDUP:
			var progress := clampf(_phase_time / stats.attack_windup, 0.01, 1.0)
			telegraph.scale = Vector3(1.0, 1.0, progress)
			if _phase_time >= stats.attack_windup:
				_attack_phase = AttackPhase.STRIKE
				_phase_time = 0.0
				telegraph.hide()
				attack_hitbox.active = true
				attack_struck.emit()
		AttackPhase.STRIKE:
			if _phase_time >= stats.attack_strike_duration:
				_attack_phase = AttackPhase.RECOVERY
				_phase_time = 0.0
				attack_hitbox.active = false
		AttackPhase.RECOVERY:
			if _phase_time >= stats.attack_recovery:
				_set_state(State.CHASE if _target_alive() else State.IDLE)


func _navigate_to(point: Vector3) -> Vector3:
	if nav_agent.target_position.distance_to(point) > 0.1:
		nav_agent.target_position = point
	return _next_path_direction()


func _next_path_direction() -> Vector3:
	if nav_agent.is_navigation_finished():
		return Vector3.ZERO
	var dir := _flat(nav_agent.get_next_path_position() - global_position)
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


func _apply_movement(move_dir: Vector3, delta: float) -> void:
	velocity.x = move_dir.x * stats.move_speed
	velocity.z = move_dir.z * stats.move_speed
	if move_dir != Vector3.ZERO:
		facing_direction = move_dir
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


func _apply_rotation(delta: float) -> void:
	if state == State.ATTACK or state == State.DEAD:
		return
	if state == State.CHASE and _target_alive() and _distance_to_target() <= stats.attack_range * 1.5:
		facing_direction = _flat(target.global_position - global_position).normalized()
	rotation.y = lerp_angle(rotation.y, _yaw_for(facing_direction), 1.0 - exp(-stats.turn_speed * delta))


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_repath_timer = 0.0
	state_changed.emit(new_state)


func _on_died() -> void:
	_set_state(State.DEAD)
	attack_hitbox.active = false
	telegraph.hide()
	velocity = Vector3.ZERO
	# Corpse: no longer blocks movement or receives hits.
	collision_layer = 0
	hurtbox.set_deferred("monitorable", false)


func _target_alive() -> bool:
	# Targets expose `is_dead` (PlayerController does).
	return target != null and not ("is_dead" in target and target.is_dead)


func _distance_to_target() -> float:
	return _flat(target.global_position - global_position).length()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _yaw_for(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
