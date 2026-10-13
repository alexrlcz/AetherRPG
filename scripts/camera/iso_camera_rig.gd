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

@onready var camera: Camera3D = $Camera3D

var _target: Node3D


func _ready() -> void:
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
