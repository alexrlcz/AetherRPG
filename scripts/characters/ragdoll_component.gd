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

@export_group("Knockback")
## Horizontal speed (m/s) away from the attacker on the killing blow.
@export var knockback_speed: float = 3.0
## Upward speed (m/s) added on the killing blow.
@export var knockback_lift: float = 1.5

var is_ragdoll: bool = false
var _last_source: Node3D


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(start_ragdoll)


func start_ragdoll() -> void:
	if is_ragdoll:
		return
	is_ragdoll = true
	var velocity := _inherited_velocity() + _knockback()
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
	for bone in get_physical_bones():
		bone.linear_velocity = velocity
		bone.angular_velocity = Vector3.ZERO


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


func _knockback() -> Vector3:
	var push := Vector3.UP * knockback_lift
	if is_instance_valid(_last_source) and body:
		var away := body.global_position - _last_source.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			push += away.normalized() * knockback_speed
	return push
