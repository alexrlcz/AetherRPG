class_name HitboxComponent
extends Area3D
## Area that deals damage to overlapping HurtboxComponents while active.
##
## Each hurtbox is hit once per activation, unless `rehit_interval` > 0,
## in which case it is hit again every `rehit_interval` seconds while it
## stays inside (useful for hazards and damage-over-time zones).
## Set the collision mask to the hurtbox layer(s) this hitbox should hurt.
##
## With `sweep` on, every physics tick also tests the space its shapes moved
## through since the previous tick (interpolated samples, so rotating arcs are
## followed too). A fast weapon then cannot skip a target between ticks, at
## any frame rate. Every hit is described by a HitEvent.

## A hit was confirmed (the victim actually took damage).
signal hit_landed(event: HitEvent)

@export var damage: int = 10
@export var active: bool = false:
	set = set_active
## Seconds before the same hurtbox can be hit again. 0 = once per activation.
@export var rehit_interval: float = 0.0
## Reported as the damage source. Defaults to this scene's owner.
@export var source: Node
## Attack data put on each HitEvent (MeleeAttackComponent sets it per attack).
## Null = plain damage: victims only flinch.
@export var profile: AttackProfile

@export_group("Sweep")
@export var sweep: bool = false
## Maximum distance (m) any corner of a shape moves between two samples.
@export var sweep_spacing: float = 0.12
@export var max_sweep_samples: int = 16

var _time: float = 0.0
var _last_hit_time: Dictionary = {}  # hurtbox instance id -> _time of last hit
var _shapes: Array[CollisionShape3D] = []
## Global transform of each shape at the end of the previous tick.
var _previous: Array[Transform3D] = []
## Per shape: a copy scaled to the shape's global scale (queries need an
## orthonormal transform), or the shape itself when unscaled.
var _query_shapes: Array[Shape3D] = []
var _last_processed_frame: int = -1
## Remaining _physics_process passes before close_after_current_pose() closes.
var _closes_in: int = 0


func _ready() -> void:
	monitoring = true
	monitorable = false
	if source == null:
		source = owner
	for child in get_children():
		if child is CollisionShape3D:
			_shapes.append(child)
	_snapshot()


## Re-reads the CollisionShape3D children after their shapes or transforms
## changed (a different weapon was equipped).
func refresh_shapes() -> void:
	_shapes.clear()
	_query_shapes.clear()
	for child in get_children():
		if child is CollisionShape3D:
			_shapes.append(child)
	_snapshot()


func set_active(value: bool) -> void:
	active = value
	_closes_in = 0
	_last_hit_time.clear()
	# Sweeps start from where the shapes are now, never from an old pose.
	if is_inside_tree():
		_snapshot()


## Closes the hitbox once the pose of the current tick has been tested.
## Bone poses are applied at the end of each physics tick, so the hitbox always
## sees the previous tick's pose; closing straight away would skip the last
## tick of the swing (a large part of it at low tick rates).
func close_after_current_pose() -> void:
	if not active:
		return
	var processed := _last_processed_frame == Engine.get_physics_frames()
	_closes_in = 1 if processed else 2


func _physics_process(delta: float) -> void:
	_time += delta
	_last_processed_frame = Engine.get_physics_frames()
	if not active:
		return
	if sweep:
		# The sweep's last sample is the current pose: overlaps are covered.
		_sweep()
	elif not _shapes.is_empty():
		for area in get_overlapping_areas():
			var hurtbox := area as HurtboxComponent
			if hurtbox:
				var xf := _shapes[0].global_transform
				_try_hit(hurtbox, 0, xf, _previous[0], xf)
	_snapshot()
	if _closes_in > 0:
		_closes_in -= 1
		if _closes_in == 0:
			active = false


func _sweep() -> void:
	var space := get_world_3d().direct_space_state
	for i in _shapes.size():
		var cs := _shapes[i]
		if cs.disabled or cs.shape == null:
			continue
		var from := _previous[i]
		var to := cs.global_transform
		var travel := _max_corner_travel(cs.shape, from, to)
		var steps := clampi(ceili(travel / maxf(sweep_spacing, 0.01)), 1, max_sweep_samples)
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = _query_shape(i)
		params.collision_mask = collision_mask
		params.collide_with_areas = true
		params.collide_with_bodies = false
		for s in steps + 1:
			var xf := from.interpolate_with(to, float(s) / steps)
			params.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
			for result in space.intersect_shape(params, 16):
				var hurtbox := result.collider as HurtboxComponent
				if hurtbox:
					_try_hit(hurtbox, i, xf, from, to)


func _try_hit(hurtbox: HurtboxComponent, shape_index: int, xf: Transform3D,
		from: Transform3D, to: Transform3D) -> void:
	var id := hurtbox.get_instance_id()
	if _last_hit_time.has(id):
		if rehit_interval <= 0.0 or _time - _last_hit_time[id] < rehit_interval:
			return
	_last_hit_time[id] = _time
	var event := HitEvent.new()
	event.source = source
	event.hitbox = self
	event.profile = profile
	event.amount = damage
	event.point = _contact_point(_shapes[shape_index], xf, hurtbox)
	var local := xf.affine_inverse() * event.point
	var motion := to * local - from * local
	event.swing_direction = motion.normalized() if motion.length() > 0.001 else Vector3.ZERO
	event.direction = _knockback_direction(hurtbox, event.swing_direction)
	hurtbox.receive_event(event)
	if event.applied > 0:
		hit_landed.emit(event)


## Point on the weapon closest to the victim's body axis, pulled in to the
## body's surface.
func _contact_point(cs: CollisionShape3D, xf: Transform3D, hurtbox: HurtboxComponent) -> Vector3:
	var blade := _segment(cs.shape, xf)
	var body := hurtbox.get_body_segment()
	var closest := Geometry3D.get_closest_points_between_segments(blade[0], blade[1], body[0], body[1])
	var on_body: Vector3 = closest[1]
	return on_body + (closest[0] - on_body).limit_length(hurtbox.get_body_radius())


func _knockback_direction(hurtbox: HurtboxComponent, swing: Vector3) -> Vector3:
	var away := Vector3.ZERO
	var attacker := source as Node3D
	if attacker:
		away = hurtbox.global_position - attacker.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(swing.x, 0.0, swing.z)
	return away.normalized() if away.length_squared() > 0.0001 else Vector3.ZERO


func _snapshot() -> void:
	_previous.resize(_shapes.size())
	for i in _shapes.size():
		_previous[i] = _shapes[i].global_transform


func _query_shape(i: int) -> Shape3D:
	_query_shapes.resize(_shapes.size())
	var shape := _shapes[i].shape
	var scale := _shapes[i].global_basis.get_scale()
	if scale.is_equal_approx(Vector3.ONE):
		return shape
	if _query_shapes[i] == null:
		_query_shapes[i] = _scaled_copy(shape, scale)
	return _query_shapes[i]


static func _scaled_copy(shape: Shape3D, scale: Vector3) -> Shape3D:
	if shape is BoxShape3D:
		var box := BoxShape3D.new()
		box.size = (shape as BoxShape3D).size * scale
		return box
	if shape is CapsuleShape3D:
		var capsule := CapsuleShape3D.new()
		capsule.radius = (shape as CapsuleShape3D).radius * maxf(scale.x, scale.z)
		capsule.height = (shape as CapsuleShape3D).height * scale.y
		return capsule
	if shape is SphereShape3D:
		var sphere := SphereShape3D.new()
		sphere.radius = (shape as SphereShape3D).radius * maxf(scale.x, maxf(scale.y, scale.z))
		return sphere
	return shape


static func _half_extents(shape: Shape3D) -> Vector3:
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size * 0.5
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return Vector3(c.radius, c.height * 0.5, c.radius)
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return Vector3(r, r, r)
	if shape is CylinderShape3D:
		var cy := shape as CylinderShape3D
		return Vector3(cy.radius, cy.height * 0.5, cy.radius)
	return Vector3(0.5, 0.5, 0.5)


static func _max_corner_travel(shape: Shape3D, from: Transform3D, to: Transform3D) -> float:
	var h := _half_extents(shape)
	var travel := 0.0
	for i in 8:
		var corner := Vector3(
			h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		travel = maxf(travel, (to * corner).distance_to(from * corner))
	return travel


## The shape's long axis as a world-space segment (blade edge, capsule spine).
static func _segment(shape: Shape3D, xf: Transform3D) -> Array[Vector3]:
	var h := _half_extents(shape)
	var axis := Vector3.ZERO
	axis[h.max_axis_index()] = h[h.max_axis_index()]
	return [xf * -axis, xf * axis]
