class_name RagdollComponent
extends Node
## Turns a character into a ragdoll the moment its HealthComponent dies.
##
## The rig's PhysicalBone3Ds follow the animation while alive. On death the
## animation is frozen, physics takes over, and every bone is given the
## character's current velocity plus a knockback away from the last attacker.

signal ragdoll_started

@export var health: HealthComponent
@export var simulator: PhysicalBoneSimulator3D
@export var animation_player: AnimationPlayer
## Its velocity is carried into the ragdoll.
@export var body: CharacterBody3D
## Optional modifier that keeps IK-parented bones (feet) attached.
@export var limb_follow: SkeletonModifier3D
## Optional: the killing HitEvent sets the fling direction and strength
## (AttackProfile.ragdoll_force), so heavy finishers throw harder.
@export var hurtbox: HurtboxComponent

@export_group("Knockback")
## Horizontal speed (m/s) away from the attacker on the killing blow.
@export var knockback_speed: float = 3.0
## Upward speed (m/s) added on the killing blow.
@export var knockback_lift: float = 1.5
## Tumble on the killing blow (rad/s): a backwards flip away from the attacker
## (random axis if there is no attacker). 0 disables it; 2π = one turn/second.
@export var knockback_spin: float = 5.0
## 0..1 random variation of the spin axis and speed, so deaths differ.
@export_range(0.0, 1.0) var spin_randomness: float = 0.35

var is_ragdoll: bool = false
## Angular velocity given to the whole body on the last ragdoll start.
var start_spin: Vector3 = Vector3.ZERO
var _last_source: Node3D


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(start_ragdoll)


func start_ragdoll() -> void:
	if is_ragdoll:
		return
	is_ragdoll = true
	var away := _away_from_attacker()
	var force := 1.0
	var killing_hit: HitEvent = hurtbox.last_hit if hurtbox else null
	if killing_hit:
		if killing_hit.direction != Vector3.ZERO:
			away = killing_hit.direction
		if killing_hit.profile:
			force = killing_hit.profile.ragdoll_force
	var velocity := _inherited_velocity() + (away * knockback_speed + Vector3.UP * knockback_lift) * force
	start_spin = _spin(away)
	animation_player.pause()
	if limb_follow:
		limb_follow.active = true
	simulator.physical_bones_start_simulation()
	ragdoll_started.emit()
	# Bodies switch to rigid simulation during the next physics step.
	await get_tree().physics_frame
	# Overwrite both velocities: kinematic bones can carry NaN/inf velocities
	# after zero-length physics steps (Engine.time_scale = 0), which would
	# explode the ragdoll. Pause the game with SceneTree.paused instead.
	# Every bone moves as part of one rigid body spinning about the centre:
	# v = v_centre + ω × r. That keeps the joints together during the tumble.
	var bones := get_physical_bones()
	var centre := Vector3.ZERO
	for bone in bones:
		centre += bone.global_position
	centre /= maxf(bones.size(), 1)
	for bone in bones:
		bone.linear_velocity = velocity + start_spin.cross(bone.global_position - centre)
		bone.angular_velocity = start_spin


func get_physical_bones() -> Array[PhysicalBone3D]:
	var result: Array[PhysicalBone3D] = []
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			result.append(child)
	return result


func _on_damaged(_amount: int, source: Node) -> void:
	_last_source = source as Node3D


func _inherited_velocity() -> Vector3:
	return body.velocity if body else Vector3.ZERO


## Horizontal unit vector from the last attacker to this body, or ZERO.
func _away_from_attacker() -> Vector3:
	if not is_instance_valid(_last_source) or body == null:
		return Vector3.ZERO
	var away := body.global_position - _last_source.global_position
	away.y = 0.0
	return away.normalized() if away.length_squared() > 0.0001 else Vector3.ZERO


func _spin(away: Vector3) -> Vector3:
	if knockback_spin <= 0.0:
		return Vector3.ZERO
	# UP × away: rotation that moves the top of the body along `away`
	# (head thrown back, feet swept forward).
	var axis := Vector3.UP.cross(away)
	if axis.length_squared() < 0.0001:
		var angle := randf() * TAU
		axis = Vector3(cos(angle), 0.0, sin(angle))
	var j := spin_randomness
	axis = (axis.normalized() + Vector3(randf_range(-j, j), randf_range(-j, j), randf_range(-j, j))).normalized()
	return axis * knockback_spin * randf_range(1.0 - j * 0.5, 1.0 + j * 0.5)
