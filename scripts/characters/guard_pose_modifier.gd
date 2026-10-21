class_name GuardPoseModifier
extends SkeletonModifier3D
## Holds one limb in a fixed pose on top of whatever the AnimationPlayer
## plays, so a character can run with its shield raised: the legs and torso
## keep the locomotion cycle, the arm takes the guard. The pose is sampled
## once from `animation` at `pose_time` for `chain_root` and every bone
## below it. `raised` blends it in and out through the modifier's
## `influence` at `blend_speed` per second.
##
## Must come before other modifiers under the Skeleton3D (the ragdoll's
## PhysicalBoneSimulator3D, the cloak spring); BlockComponent creates it
## as the skeleton's first child.

@export var animation_player: AnimationPlayer
@export var animation: StringName = &"UAL2/Idle_Shield"
## Seconds into `animation` the pose is taken from.
@export var pose_time: float = 0.6
## Top of the limb taken from the pose (the clavicle: the whole arm, hand
## and fingers).
@export var chain_root: StringName = &"clavicle_l"
@export var blend_speed: float = 10.0

var raised: bool = false

## Bone index -> local pose rotation in the guard.
var _rotations: Dictionary = {}


func _ready() -> void:
	influence = 0.0
	_sample()


func _sample() -> void:
	_rotations.clear()
	var skeleton := get_skeleton()
	if skeleton == null or animation_player == null or not animation_player.has_animation(animation):
		push_warning("GuardPoseModifier: no skeleton or animation '%s'" % animation)
		return
	var root := skeleton.find_bone(chain_root)
	if root < 0:
		return
	var chain := {}
	var stack: Array[int] = [root]
	while not stack.is_empty():
		var bone: int = stack.pop_back()
		chain[skeleton.get_bone_name(bone)] = bone
		stack.append_array(skeleton.get_bone_children(bone))
	var clip := animation_player.get_animation(animation)
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := String(clip.track_get_path(track).get_concatenated_subnames())
		if chain.has(bone_name):
			_rotations[chain[bone_name]] = clip.rotation_track_interpolate(track, pose_time)


## Seconds to fully raise or lower the limb.
func blend_duration() -> float:
	return 1.0 / maxf(blend_speed, 0.001)


func _process_modification_with_delta(delta: float) -> void:
	influence = move_toward(influence, 1.0 if raised else 0.0, blend_speed * delta)
	if influence <= 0.0:
		return
	var skeleton := get_skeleton()
	for bone: int in _rotations:
		skeleton.set_bone_pose_rotation(bone, _rotations[bone])
