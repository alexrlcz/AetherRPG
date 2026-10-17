class_name EnemyController
extends CharacterBody3D
## Melee enemy AI: idle (return home) -> chase -> attack -> dead, plus
## stagger: a staggering hit cancels whatever the enemy was doing and the
## knockback/hitstun from `reaction` has priority until it recovers.
##
## Attacks come from the equipped weapon (`weapon`, WeaponComponent): the
## basic swing within `attack_range`, and the optional dash attack, a gap
## closer from mid range on `stats.dash_cooldown`.
##
## Targets the first node in the "player" group. Movement uses a
## NavigationAgent3D on the baked navigation mesh. Numbers come from `stats`.

signal state_changed(new_state: State)

enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD }

@export var stats: EnemyStats
@export var health: HealthComponent
@export var nav_agent: NavigationAgent3D
@export var hurtbox: HurtboxComponent
## Runs the attacks.
@export var melee: MeleeAttackComponent
## Supplies the attacks (see _on_weapon_equipped()).
@export var weapon: WeaponComponent
## Optional: hit reactions (hitstun, knockback, poise).
@export var reaction: HitReactionComponent

@export_group("Navigation")
## How often the chase path is recomputed.
@export var repath_interval: float = 0.2
## Distance from home that counts as "home".
@export var home_tolerance: float = 0.5

@export_group("Sight")
## Height of the eyes above the origin (feet) for line-of-sight rays.
@export var eye_height: float = 1.6
## Height on the target the line-of-sight ray aims at.
@export var target_aim_height: float = 1.0
## Physics layers that block sight (world).
@export_flags_3d_physics var sight_mask: int = 1

var state: State = State.IDLE
var target: Node3D
var facing_direction: Vector3 = Vector3.FORWARD

var _repath_timer: float = 0.0
var _last_seen_position: Vector3
var _unseen_time: float = 0.0
var _home: Vector3
var _dash_cooldown_left: float = 0.0

## From the equipped weapon.
var attack_profile: AttackProfile
var attack_range: float = 1.7
var dash_attack: AttackProfile
var dash_min_range: float = 3.0
var dash_max_range: float = 5.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	health.max_health = stats.max_health
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	if weapon:
		weapon.equipped.connect(_on_weapon_equipped)
		if weapon.current:
			_on_weapon_equipped(weapon.current)
	if reaction:
		reaction.poise = stats.poise
		reaction.knockback_scale = stats.knockback_scale
		reaction.staggered.connect(_on_staggered)
	_home = global_position
	facing_direction = -global_basis.z


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D

	_dash_cooldown_left -= delta
	var move_dir := Vector3.ZERO
	match state:
		State.IDLE:
			move_dir = _process_idle()
		State.CHASE:
			move_dir = _process_chase(delta)
		State.ATTACK:
			_process_attack()
		State.STAGGER:
			_process_stagger()
	if reaction:
		# Hyper armour while winding up and swinging; recovery is punishable.
		reaction.armored = state == State.ATTACK 			and melee.phase != MeleeAttackComponent.Phase.RECOVERY

	_apply_movement(move_dir, delta)
	if state == State.ATTACK:
		# The attack's own forward step (the dash attack's lunge).
		var forward := -global_basis.z
		var lunge := melee.lunge_speed()
		velocity.x += forward.x * lunge
		velocity.z += forward.z * lunge
	_apply_rotation(delta)
	move_and_slide()


func _process_idle() -> Vector3:
	if _target_alive() and _distance_to_target() <= stats.detection_radius and can_see_target():
		_start_chase()
		return Vector3.ZERO
	if _flat(global_position - _home).length() > home_tolerance:
		return _navigate_to(_home)
	return Vector3.ZERO


func _process_chase(delta: float) -> Vector3:
	if not _target_alive() or _distance_to_target() > stats.lose_interest_radius:
		_set_state(State.IDLE)
		return Vector3.ZERO
	if can_see_target():
		_last_seen_position = target.global_position
		_unseen_time = 0.0
	else:
		# Out of sight: search the last seen spot, then give up.
		_unseen_time += delta
		if _unseen_time >= stats.lose_sight_time:
			_set_state(State.IDLE)
			return Vector3.ZERO
		return _navigate_to(_last_seen_position)
	if _distance_to_target() <= attack_range:
		_start_attack()
		return Vector3.ZERO
	if _can_dash():
		_start_attack(dash_attack)
		_dash_cooldown_left = stats.dash_cooldown
		return Vector3.ZERO
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		nav_agent.target_position = target.global_position
	return _next_path_direction()


func _start_chase() -> void:
	_last_seen_position = target.global_position
	_unseen_time = 0.0
	_set_state(State.CHASE)


## True when nothing on `sight_mask` blocks the ray from the eyes to the target.
func can_see_target() -> bool:
	if not stats.requires_line_of_sight:
		return true
	if target == null:
		return false
	var from := global_position + Vector3.UP * eye_height
	var to := target.global_position + Vector3.UP * target_aim_height
	var query := PhysicsRayQueryParameters3D.create(from, to, sight_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Starts `profile`, or the weapon's basic swing when null.
func _start_attack(profile: AttackProfile = null) -> void:
	if profile == null:
		profile = attack_profile
	# Lock facing at the start so the player can sidestep the blow.
	var to_target := _flat(target.global_position - global_position)
	if to_target.length_squared() > 0.0001:
		facing_direction = to_target.normalized()
		rotation.y = _yaw_for(facing_direction)
	if melee.start(profile):
		_set_state(State.ATTACK)


func _can_dash() -> bool:
	if dash_attack == null or _dash_cooldown_left > 0.0:
		return false
	var distance := _distance_to_target()
	return distance >= dash_min_range and distance <= dash_max_range


func _on_weapon_equipped(new_weapon: WeaponDefinition) -> void:
	melee.cancel()
	attack_profile = new_weapon.enemy_attack
	attack_range = new_weapon.enemy_attack_range
	dash_attack = new_weapon.enemy_dash_attack
	dash_min_range = new_weapon.enemy_dash_min_range
	dash_max_range = new_weapon.enemy_dash_max_range


func _process_attack() -> void:
	if not melee.is_busy():
		_set_state(State.CHASE if _target_alive() else State.IDLE)


func _process_stagger() -> void:
	if not reaction.is_reacting():
		if _target_alive():
			_start_chase()
		else:
			_set_state(State.IDLE)


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
	if reaction and state != State.DEAD:
		# Knockback (also the small push of a flinch) rides on top.
		velocity.x += reaction.knockback_velocity.x
		velocity.z += reaction.knockback_velocity.z
	if move_dir != Vector3.ZERO:
		facing_direction = move_dir
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


func _apply_rotation(delta: float) -> void:
	if state == State.ATTACK or state == State.STAGGER or state == State.DEAD:
		return
	if state == State.CHASE and _target_alive() and _distance_to_target() <= attack_range * 1.5:
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
	melee.cancel()
	velocity = Vector3.ZERO
	# Corpse: no longer blocks movement or receives hits.
	collision_layer = 0
	hurtbox.set_deferred("monitorable", false)


func _on_staggered(event: HitEvent) -> void:
	if state == State.DEAD:
		return
	melee.cancel()
	if reaction.is_knocked_down() and event.direction != Vector3.ZERO:
		# Face the attacker: the knockdown clip falls backwards.
		facing_direction = -event.direction
		rotation.y = _yaw_for(facing_direction)
	_set_state(State.STAGGER)


func _on_damaged(_amount: int, _source: Node) -> void:
	# Getting hit reveals the attacker, even outside detection range or sight.
	if state == State.IDLE and _target_alive():
		_start_chase()


func _target_alive() -> bool:
	# Targets expose `is_dead` (PlayerController does).
	return target != null and not ("is_dead" in target and target.is_dead)


func _distance_to_target() -> float:
	return _flat(target.global_position - global_position).length()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _yaw_for(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
