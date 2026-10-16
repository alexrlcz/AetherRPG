class_name LockOnComponent
extends Node
## Target lock: picks an enemy for the player to face and attack.
##
## `toggle()` locks onto the nearest visible living enemy within `lock_range`
## (or releases the lock); `cycle()` steps to the next candidate, nearest to
## farthest, wrapping around. The lock breaks when the target is farther than
## `break_range` or out of sight for longer than `lose_sight_time`. When the
## target dies the lock jumps to the next-nearest enemy, or releases.
##
## Enemies are nodes in the "enemies" group; a node with a `health`
## HealthComponent that reports `is_dead` is not a candidate.
## A ring under the target's feet and a pointer above its head mark it.

signal target_changed(new_target: Node3D)

const ENEMY_GROUP := &"enemies"

## The locking character (distance and sight are measured from it).
@export var body: Node3D
@export var lock_range: float = 15.0
@export var break_range: float = 20.0
## Seconds the target may stay hidden behind walls before the lock breaks.
@export var lose_sight_time: float = 1.0
## Physics layers that block sight (world).
@export_flags_3d_physics var sight_mask: int = 1
@export var eye_height: float = 1.6
@export var target_aim_height: float = 1.0
@export_group("Marker")
@export var marker_color: Color = Color(1.0, 0.45, 0.15, 0.9)
@export var ring_radius: float = 0.75
## Height of the pointer above the target's origin (above the health bar).
@export var pointer_height: float = 2.6

var target: Node3D

var _unseen_time: float = 0.0
var _marker_root: Node3D
var _ring: MeshInstance3D
var _pointer: MeshInstance3D
var _marker_time: float = 0.0


func _ready() -> void:
	_build_marker()


func is_locked() -> bool:
	return target != null


## Locks onto the nearest candidate, or releases the current lock.
func toggle() -> void:
	if is_locked():
		release()
	else:
		var candidates := get_candidates()
		_set_target(candidates[0] if not candidates.is_empty() else null)


## Moves the lock to the next candidate by distance (locks the nearest when
## nothing is locked).
func cycle() -> void:
	var candidates := get_candidates()
	if candidates.is_empty():
		return
	if not is_locked():
		_set_target(candidates[0])
		return
	var index := candidates.find(target)
	# A target that left the candidate list (e.g. hidden) still cycles on.
	_set_target(candidates[(index + 1) % candidates.size()])


func release() -> void:
	_set_target(null)


## Horizontal unit direction from `from` to the target, or ZERO.
func direction_from(from: Vector3) -> Vector3:
	if not is_locked():
		return Vector3.ZERO
	var offset := target.global_position - from
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	return offset.normalized()


## Living, visible enemies within `lock_range`, nearest first.
func get_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if body == null:
		return result
	for node in body.get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Node3D
		if enemy == null or not is_alive(enemy):
			continue
		if _flat_distance(enemy) > lock_range or not can_see(enemy):
			continue
		result.append(enemy)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat_distance(a) < _flat_distance(b))
	return result


static func is_alive(enemy: Node3D) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return false
	var health: Variant = enemy.get(&"health")
	return not (health is HealthComponent and health.is_dead)


func can_see(enemy: Node3D) -> bool:
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		body.global_position + Vector3.UP * eye_height,
		enemy.global_position + Vector3.UP * target_aim_height,
		sight_mask)
	return space.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	if not is_locked():
		return
	if not is_alive(target):
		var candidates := get_candidates()
		_set_target(candidates[0] if not candidates.is_empty() else null)
		return
	if _flat_distance(target) > break_range:
		release()
		return
	if can_see(target):
		_unseen_time = 0.0
	else:
		_unseen_time += delta
		if _unseen_time > lose_sight_time:
			release()


func _process(delta: float) -> void:
	if not is_locked() or not is_instance_valid(target):
		return
	_marker_time += delta
	var at := target.global_position
	_ring.global_position = at + Vector3.UP * 0.04
	var pulse := 1.0 + 0.06 * sin(_marker_time * 6.0)
	_ring.scale = Vector3.ONE * pulse
	_pointer.global_position = at + Vector3.UP * (pointer_height + 0.06 * sin(_marker_time * 4.0))


func _set_target(new_target: Node3D) -> void:
	_unseen_time = 0.0
	if new_target == target:
		return
	target = new_target
	_marker_root.visible = target != null
	_marker_time = 0.0
	if target:
		_process(0.0)
	target_changed.emit(target)


func _flat_distance(enemy: Node3D) -> float:
	var offset := enemy.global_position - body.global_position
	offset.y = 0.0
	return offset.length()


func _build_marker() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = marker_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_marker_root = Node3D.new()
	_marker_root.name = "LockMarker"
	_marker_root.top_level = true
	_marker_root.visible = false
	add_child(_marker_root)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = ring_radius - 0.08
	ring_mesh.outer_radius = ring_radius
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 4
	ring_mesh.material = material
	_ring = _marker_mesh(ring_mesh)  # TorusMesh lies flat in XZ.

	var pointer_mesh := CylinderMesh.new()  # point-down cone
	pointer_mesh.top_radius = 0.14
	pointer_mesh.bottom_radius = 0.0
	pointer_mesh.height = 0.28
	pointer_mesh.radial_segments = 4
	pointer_mesh.rings = 1
	pointer_mesh.material = material
	_pointer = _marker_mesh(pointer_mesh)


func _marker_mesh(mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.top_level = true
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.add_to_group(&"vfx")
	_marker_root.add_child(instance)
	return instance
