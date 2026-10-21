class_name BlockComponent
extends Node
## Blocking with a shield. The owner sets `raised` while the block input is
## held and the character is free to guard; the guard is up (is_guarding())
## while a ShieldDefinition is worn in the OFF_HAND slot of `appearance`
## and `stamina` is not exhausted. A GuardPoseModifier (created under
## `skeleton`) raises the shield arm meanwhile, over whatever the legs play.
##
## The hurtbox asks try_block() before applying a hit: a hit from within the
## shield's `block_angle` in front of `body` does no damage and costs
## `stamina_per_damage` stamina per point instead. A hit that costs more
## than the stamina left breaks the guard (stamina to 0, exhausted, so the
## shield drops until it recovers) and lands in full.

signal blocked(event: HitEvent)
signal guard_broken(event: HitEvent)

## Its facing (-Z) decides which hits are in front.
@export var body: Node3D
## The shield is whatever ShieldDefinition its appearance wears.
@export var appearance: AppearanceComponent
@export var stamina: StaminaComponent
## The guard pose (`guard_animation`) is sampled from this player's clips.
@export var animation_player: AnimationPlayer
@export var skeleton: Skeleton3D
## Optional: pops "Block" on a blocked hit.
@export var numbers: DamageNumbers
@export var guard_animation: StringName = &"UAL2/Idle_Shield"
## Seconds into `guard_animation` the arm pose is taken from.
@export var guard_pose_time: float = 0.6

@export_group("Feedback")
## Spawned at the contact point of a blocked hit; its root needs
## setup(event, strength) like ImpactEffect. Null = ImpactEffect.
@export var effect_scene: PackedScene
## Null = a placeholder clang.
@export var block_sound: AudioStream
@export var volume_db: float = -4.0
@export var hitstop: float = 0.05
@export var camera_shake: float = 0.12

## Block input held and free to guard (the owner sets it every tick).
var raised: bool = false
## The worn shield, or null.
var shield: ShieldDefinition
## Blocked hits so far (tests and debugging).
var hits_blocked: int = 0

var _pose: GuardPoseModifier


func _ready() -> void:
	if skeleton:
		_pose = GuardPoseModifier.new()
		_pose.name = "GuardPose"
		_pose.animation_player = animation_player
		_pose.animation = guard_animation
		_pose.pose_time = guard_pose_time
		skeleton.add_child(_pose)
		skeleton.move_child(_pose, 0)  # Before the ragdoll and cloak modifiers.
	if appearance:
		appearance.applied.connect(_refresh_shield)
		_refresh_shield()


func _physics_process(_delta: float) -> void:
	if _pose:
		_pose.raised = is_guarding()


## The shield is up: hits in front are blocked.
func is_guarding() -> bool:
	return raised and shield != null and (stamina == null or stamina.can_act())


## A shield is worn (whether or not it is raised).
func has_shield() -> bool:
	return shield != null


## The arm pose (null without a skeleton).
func get_pose() -> GuardPoseModifier:
	return _pose


## Called by the hurtbox before a hit is applied. True = blocked: the hit
## does nothing more.
func try_block(event: HitEvent) -> bool:
	if not is_guarding() or body == null:
		return false
	var to_attacker := Vector3.ZERO
	var attacker := event.source as Node3D
	if attacker:
		to_attacker = attacker.global_position - body.global_position
	else:
		to_attacker = -event.direction
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return false
	var forward := -body.global_basis.z
	forward.y = 0.0
	if rad_to_deg(forward.angle_to(to_attacker)) > shield.block_angle * 0.5:
		return false
	var cost := event.amount * shield.stamina_per_damage
	if stamina and not stamina.infinite and stamina.current_stamina < cost:
		stamina.drain(stamina.current_stamina)
		guard_broken.emit(event)
		return false
	if stamina:
		stamina.drain(cost)
	hits_blocked += 1
	_feedback(event)
	blocked.emit(event)
	return true


func _refresh_shield() -> void:
	var worn := appearance.appearance.gear_in(GearDefinition.Slot.OFF_HAND) if appearance.appearance else null
	shield = worn as ShieldDefinition


func _feedback(event: HitEvent) -> void:
	var effect: Node3D = effect_scene.instantiate() if effect_scene else ImpactEffect.new()
	_world_root().add_child(effect)
	effect.global_position = event.point
	effect.setup(event, 0.6)
	Hitstop.request_for(self, hitstop)
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	if rig:
		rig.add_impulse(event.direction, camera_shake)
	var player := AudioStreamPlayer3D.new()
	player.stream = block_sound if block_sound else PlaceholderSfx.hit(false)
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.5, 1.7)  # Higher than a flesh hit: a clang.
	player.unit_size = 20.0
	_world_root().add_child(player)
	player.global_position = event.point
	player.finished.connect(player.queue_free)
	player.play()
	if numbers:
		numbers.spawn("Block").modulate = Color(0.7, 0.85, 1.0)


func _world_root() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root
