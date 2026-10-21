class_name IsoCameraRig
extends Node3D
## Follow camera that blends from an isometric overview into a close
## third-person view as it zooms in, and orbits around the target.
##
## The rig sits on the target's position (plus a look height) and is rotated
## (yaw, then pitch); the child Camera3D is pushed back along the rig's local
## +Z axis. The camera is always perspective:
## - zoom 0 .. `overview_zoom_end`: the overview. A narrow field of view from
##   far away looks close to the old orthographic isometric view; zooming in
##   shrinks the visible height at the target from `max_view_height` to
##   `min_view_height`, at the isometric pitch.
## - `overview_zoom_end` .. 1: the close-up. The camera moves in to
##   `close_distance`, the field of view widens, the pitch flattens to
##   `close_pitch_degrees` and the look point rises to the character's chest,
##   so at full zoom it is a third-person camera behind the character.
## The mouse wheel steps the zoom (smoothed) at any time.
##
## Free look, only while the target stands still (horizontal speed under
## `free_look_max_speed`): dragging with "camera_rotate" (middle mouse) held
## orbits (sideways) and tilts (up / down). As soon as the target moves, the
## view eases back (ease in, ease out over `return_time`) to the default:
## `yaw_degrees` (isometric) and the zoom's own pitch. Only the zoom stays
## as it was.
##
## Every frame the rig also sets the global shader parameters `cutout_camera`,
## `cutout_target`, `cutout_radius`, `cutout_front_width` and
## `cutout_stub_height` (project.godot [shader_globals]); the wall shader
## (shaders/wall_cutout.gdshader) cuts walls on the camera's side of the
## target down to low stubs, and a see-through hole wherever a wall stands
## between the camera and the target.

@export var target_path: NodePath
@export var yaw_degrees: float = 45.0
## Higher values follow more tightly. 0 disables smoothing.
@export var follow_smoothing: float = 10.0

@export_group("Free Look")
## Yaw degrees per pixel of mouse movement while "camera_rotate" is held.
@export var rotate_sensitivity: float = 0.3
## Pitch degrees per pixel of vertical mouse movement (dragging down tilts
## toward top-down).
@export var tilt_sensitivity: float = 0.2
## Tilt range (degrees) around the zoom's own pitch, and the final pitch's
## limits.
@export var min_tilt: float = -25.0
@export var max_tilt: float = 35.0
@export var pitch_limits: Vector2 = Vector2(5.0, 85.0)
## Free look only works below this target speed (m/s); above it the view
## returns to the default.
@export var free_look_max_speed: float = 0.25
## Seconds to ease back to the default view once the target moves.
@export var return_time: float = 0.7

@export_group("Zoom")
## 0 = furthest overview, 1 = closest third-person view.
@export_range(0.0, 1.0) var zoom: float = 0.3
@export var zoom_step: float = 0.08
## Higher values reach a new zoom faster. 0 disables smoothing.
@export var zoom_smoothing: float = 12.0
## Zoom at which the overview ends and the close-up blend begins.
@export_range(0.05, 0.95) var overview_zoom_end: float = 0.5

@export_group("Overview")
## Downward tilt. 35.264 is true isometric.
@export_range(1.0, 89.0) var overview_pitch_degrees: float = 35.264
## Narrow field of view, so the overview has little perspective distortion.
@export_range(1.0, 90.0) var overview_fov: float = 25.0
## Visible height (m) at the target at zoom 0 and at `overview_zoom_end`.
@export var max_view_height: float = 20.0
@export var min_view_height: float = 10.0

@export_group("Close-up")
@export_range(-30.0, 89.0) var close_pitch_degrees: float = 12.0
@export_range(1.0, 120.0) var close_fov: float = 55.0
## Camera distance (m) from the look point at zoom 1.
@export var close_distance: float = 3.5
## Look point height (m) above the target's origin at zoom 1 (0 in the overview).
@export var close_look_height: float = 1.4

@export_group("Wall Cutout")
## Radius (m) of the see-through hole around the camera-to-target line, in
## the overview and in the close-up.
@export var overview_cutout_radius: float = 2.2
@export var close_cutout_radius: float = 1.0
## Height (m) above the target's origin that the hole is aimed at.
@export var cutout_target_height: float = 1.0
## Half-width (m) of the front cutaway: walls on the camera's side of the
## target and within this distance of the view line are cut down to
## `cutout_stub_height`. Wide in the overview (the whole screen), narrow in
## the close-up (just what stands between the camera and the character).
@export var overview_front_width: float = 40.0
@export var close_front_width: float = 1.6
@export var cutout_stub_height: float = 0.5

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
## The wall cutout values last sent to the shader globals (debugging, tests).
var cutout_camera: Vector3
var cutout_target: Vector3
var cutout_radius: float = 0.0
var cutout_front_width: float = 0.0

var _target: Node3D
## Rig position without the look height (follows the target smoothly).
var _follow_position: Vector3
var _zoom_goal: float
var _rotating: bool = false
## Free look on top of the default view.
var _yaw_offset: float = 0.0
var _tilt: float = 0.0
## Easing back: progress 0..1 (< 0 = not returning) and where it started.
var _return_progress: float = -1.0
var _return_from: Array = [0.0, 0.0]
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


func _ready() -> void:
	add_to_group(GROUP)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_zoom_goal = zoom
	_follow_position = global_position
	if not target_path.is_empty():
		set_target(get_node(target_path) as Node3D)
	_apply_view()


func set_target(new_target: Node3D) -> void:
	_target = new_target
	if _target:
		_follow_position = _target.global_position
		_apply_view()


## Sets the zoom goal (0 = overview, 1 = third-person); `instant` skips the glide.
func set_zoom(value: float, instant: bool = false) -> void:
	_zoom_goal = clampf(value, 0.0, 1.0)
	if instant:
		zoom = _zoom_goal
		_apply_view()


func get_zoom_goal() -> float:
	return _zoom_goal


## Sets the default yaw (`degrees` around the target) and drops any free
## look.
func set_yaw(degrees: float) -> void:
	yaw_degrees = wrapf(degrees, -180.0, 180.0)
	reset_free_look()


## The yaw the camera has now: the default plus any free look.
func get_yaw() -> float:
	return wrapf(yaw_degrees + _yaw_offset, -180.0, 180.0)


## Horizontal axes WASD moves along: the view's yaw now (free look
## included), so W is always up the screen; while the view eases back to the
## default the walking direction turns with it. x = screen right, -z =
## screen up.
func get_movement_basis() -> Basis:
	return Basis.from_euler(Vector3(0.0, deg_to_rad(get_yaw()), 0.0))


## Free-look tilt (degrees) on top of the zoom's pitch.
func get_tilt() -> float:
	return _tilt


## True while the view differs from the default (or is easing back to it).
func is_free_looking() -> bool:
	return _yaw_offset != 0.0 or _tilt != 0.0


func is_returning() -> bool:
	return _return_progress >= 0.0


## Free look is allowed now: the target stands still.
func can_free_look() -> bool:
	return _target_speed() < free_look_max_speed


## Back to the default view at once.
func reset_free_look() -> void:
	_yaw_offset = 0.0
	_tilt = 0.0
	_return_progress = -1.0
	_apply_view()


## 0 in the overview, rising to 1 at the closest third-person view.
func get_close_blend() -> float:
	if zoom <= overview_zoom_end:
		return 0.0
	return smoothstep(0.0, 1.0, (zoom - overview_zoom_end) / (1.0 - overview_zoom_end))


func get_pitch_degrees() -> float:
	var pitch := lerpf(overview_pitch_degrees, close_pitch_degrees, get_close_blend()) + _tilt
	return clampf(pitch, pitch_limits.x, pitch_limits.y) if _tilt != 0.0 else pitch


func get_fov() -> float:
	return lerpf(overview_fov, close_fov, get_close_blend())


## Camera distance from the look point for the current zoom.
func get_distance() -> float:
	var overview_end_distance := _distance_for_height(min_view_height, overview_fov)
	if zoom <= overview_zoom_end:
		var t := zoom / overview_zoom_end
		return _distance_for_height(lerpf(max_view_height, min_view_height, t), overview_fov)
	# Exponential blend: equal wheel steps feel like equal zoom steps.
	return overview_end_distance * pow(close_distance / overview_end_distance, get_close_blend())


func get_look_height() -> float:
	return close_look_height * get_close_blend()


func _distance_for_height(view_height: float, fov_degrees: float) -> float:
	return view_height * 0.5 / tan(deg_to_rad(fov_degrees) * 0.5)


func _process(delta: float) -> void:
	_update_shake(delta)
	_update_cutout()


func _physics_process(delta: float) -> void:
	if _target:
		var goal := _target.global_position
		if follow_smoothing <= 0.0:
			_follow_position = goal
		else:
			_follow_position = _follow_position.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
	_update_return(delta)
	if zoom_smoothing <= 0.0:
		zoom = _zoom_goal
	else:
		zoom = lerpf(zoom, _zoom_goal, 1.0 - exp(-zoom_smoothing * delta))
		if absf(zoom - _zoom_goal) < 0.0005:
			zoom = _zoom_goal
	_apply_view()


func _apply_view() -> void:
	if not is_node_ready():
		return
	global_position = _follow_position + Vector3.UP * get_look_height()
	rotation = Vector3(deg_to_rad(-get_pitch_degrees()), deg_to_rad(get_yaw()), 0.0)
	var distance := get_distance()
	camera.position = Vector3(0.0, 0.0, distance)
	camera.fov = get_fov()
	camera.near = 0.05
	camera.far = distance + 120.0


func _update_shake(delta: float) -> void:
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


func _update_cutout() -> void:
	cutout_radius = 0.0
	cutout_front_width = 0.0
	cutout_target = Vector3.ZERO
	cutout_camera = camera.global_position
	if _target and camera.is_current():
		var blend := get_close_blend()
		cutout_radius = lerpf(overview_cutout_radius, close_cutout_radius, blend)
		cutout_front_width = lerpf(overview_front_width, close_front_width, blend)
		cutout_target = _target.global_position + Vector3.UP * cutout_target_height
	RenderingServer.global_shader_parameter_set(&"cutout_camera", cutout_camera)
	RenderingServer.global_shader_parameter_set(&"cutout_target", cutout_target)
	RenderingServer.global_shader_parameter_set(&"cutout_radius", cutout_radius)
	RenderingServer.global_shader_parameter_set(&"cutout_front_width", cutout_front_width)
	RenderingServer.global_shader_parameter_set(&"cutout_stub_height", cutout_stub_height)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		set_zoom(_zoom_goal + zoom_step)
	elif event.is_action_pressed("zoom_out"):
		set_zoom(_zoom_goal - zoom_step)
	elif event.is_action_pressed("camera_rotate"):
		_rotating = true
	elif event is InputEventMouseMotion and _rotating and can_free_look():
		# screen_relative: physical pixels, so the rates ignore window stretch.
		var moved := (event as InputEventMouseMotion).screen_relative
		_return_progress = -1.0  # Standing still and dragging: stop easing back.
		_yaw_offset -= moved.x * rotate_sensitivity
		_tilt = clampf(_tilt + moved.y * tilt_sensitivity, min_tilt, max_tilt)
		_apply_view()


## Starts easing back to the default view when the target moves, and runs
## the ease (in and out).
func _update_return(delta: float) -> void:
	if not is_returning():
		if is_free_looking() and not can_free_look():
			_return_progress = 0.0
			_return_from = [_yaw_offset, _tilt]
		else:
			return
	_return_progress = minf(_return_progress + delta / maxf(return_time, 0.001), 1.0)
	var t := _return_progress
	var eased := 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
	var keep := 1.0 - eased
	# Turn back the short way round.
	_yaw_offset = wrapf(_return_from[0], -180.0, 180.0) * keep
	_tilt = _return_from[1] * keep
	if _return_progress >= 1.0:
		_yaw_offset = 0.0
		_tilt = 0.0
		_return_progress = -1.0


func _target_speed() -> float:
	if _target == null:
		return 0.0
	var velocity: Variant = _target.get(&"velocity")
	if velocity is Vector3:
		return Vector2(velocity.x, velocity.z).length()
	return 0.0


func _input(event: InputEvent) -> void:
	# Releases are always seen, even over UI, so the drag never sticks.
	if event.is_action_released("camera_rotate"):
		_rotating = false
