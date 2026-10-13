class_name PlayerController
extends CharacterBody3D
## Player movement: WASD locomotion with optional mouse aiming.
##
## WASD is always screen-relative (W = up the screen).
## - Not aiming: the character turns to face its movement direction.
## - Holding "aim" (right mouse): the character keeps facing the mouse cursor
##   while moving, so it can walk backwards or strafe.

signal aim_started
signal aim_stopped

@export var move_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
## How quickly the character turns toward its facing direction.
@export var turn_speed: float = 14.0
## When this reaches zero, player input is disabled.
@export var health: HealthComponent

var is_aiming: bool = false
var is_dead: bool = false
## Horizontal unit vector the character is turning toward.
var facing_direction: Vector3 = Vector3.FORWARD

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	if health:
		health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_movement(Vector3.ZERO, delta)
		move_and_slide()
		return

	_update_aim_state()

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := _camera_relative_direction(input)

	if is_aiming:
		var aim_dir := get_aim_direction_at(get_viewport().get_mouse_position())
		if aim_dir != Vector3.ZERO:
			facing_direction = aim_dir
	elif move_dir != Vector3.ZERO:
		facing_direction = move_dir.normalized()

	_apply_movement(move_dir, delta)
	_apply_rotation(delta)
	move_and_slide()


func _on_died() -> void:
	is_dead = true
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


func _apply_movement(move_dir: Vector3, delta: float) -> void:
	var target := move_dir * move_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if move_dir != Vector3.ZERO else deceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


func _apply_rotation(delta: float) -> void:
	var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
