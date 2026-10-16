class_name IsoCameraRig
extends Node3D
## Fixed-angle orthographic isometric camera that smoothly follows a target.
##
## The rig sits on the target's position and is rotated (yaw, then pitch);
## the child Camera3D is pushed back along the rig's local +Z axis.
## The angle is fixed by design: the player cannot rotate the camera.

@export var target_path: NodePath
## Downward tilt. 35.264 is true isometric; 30.0 gives the classic 2:1 look.
@export_range(1.0, 89.0) var pitch_degrees: float = 35.264
@export var yaw_degrees: float = 45.0
## Distance from the target. Only affects clipping, not apparent size (orthographic).
@export var distance: float = 50.0
## Higher values follow more tightly. 0 disables smoothing.
@export var follow_smoothing: float = 10.0

@export_group("Zoom")
## Orthographic size: the visible height of the view in world units.
@export var zoom_size: float = 18.0
@export var min_zoom_size: float = 8.0
@export var max_zoom_size: float = 30.0
@export var zoom_step: float = 2.0

@export_group("Impact Shake")
## Largest camera offset (world units) at full strength.
@export var shake_max_offset: float = 0.3
## Strength lost per real second (hitstop does not slow it).
@export var shake_decay: float = 4.0
@export var shake_frequency: float = 32.0
## Share of the offset that is a directional punch along the hit, rather
## than random shake.
@export_range(0.0, 1.0) var shake_punch: float = 0.6

const GROUP := &"camera_rig"

@onready var camera: Camera3D = $Camera3D

## Strength of the most recent add_impulse() (debugging, tests).
var last_impulse_strength: float = 0.0

var _target: Node3D
var _trauma: float = 0.0
var _punch_dir: Vector2 = Vector2.ZERO
var _shake_time: float = 0.0


## Kicks the view along `world_direction` with `strength` 0..1. The strongest
## recent impulse wins; impulses never stack past full strength.
func add_impulse(world_direction: Vector3, strength: float) -> void:
	if strength <= 0.0:
		return
	last_impulse_strength = strength
	_trauma = clampf(maxf(_trauma, strength), 0.0, 1.0)
	var screen := Vector2(world_direction.dot(camera.global_basis.x),
		world_direction.dot(camera.global_basis.y))
	_punch_dir = screen.normalized() if screen.length() > 0.001 else Vector2.ZERO


func get_shake_strength() -> float:
	return _trauma


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	var real_delta := minf(delta / maxf(Engine.time_scale, 0.0001), 0.1)
	_shake_time += real_delta
	_trauma = maxf(_trauma - shake_decay * real_delta, 0.0)
	var amount := _trauma * _trauma
	var noise := Vector2(sin(_shake_time * shake_frequency),
		sin(_shake_time * shake_frequency * 1.31 + 1.7))
	var offset := (_punch_dir * shake_punch + noise * (1.0 - shake_punch)) * amount * shake_max_offset
	camera.h_offset = offset.x
	camera.v_offset = offset.y


func _ready() -> void:
	add_to_group(GROUP)
	rotation = Vector3(deg_to_rad(-pitch_degrees), deg_to_rad(yaw_degrees), 0.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 0.0, distance)
	camera.size = zoom_size
	camera.far = distance * 3.0
	if not target_path.is_empty():
		set_target(get_node(target_path) as Node3D)


func set_target(new_target: Node3D) -> void:
	_target = new_target
	if _target:
		global_position = _target.global_position


func _physics_process(delta: float) -> void:
	if not _target:
		return
	var goal := _target.global_position
	if follow_smoothing <= 0.0:
		global_position = goal
	else:
		global_position = global_position.lerp(goal, 1.0 - exp(-follow_smoothing * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_set_zoom(zoom_size - zoom_step)
	elif event.is_action_pressed("zoom_out"):
		_set_zoom(zoom_size + zoom_step)


func _set_zoom(value: float) -> void:
	zoom_size = clampf(value, min_zoom_size, max_zoom_size)
	camera.size = zoom_size
