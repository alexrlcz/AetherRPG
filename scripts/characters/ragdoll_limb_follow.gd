class_name RagdollLimbFollow
extends SkeletonModifier3D
## Keeps bones that are not children of their limb (e.g. IK-driven feet that
## are parented to the root bone) attached to that limb while ragdolling.
## Place it after the PhysicalBoneSimulator3D; it starts inactive and the
## RagdollComponent activates it.

## Bones to move, e.g. ["Foot.L", "Foot.R"].
@export var bones: PackedStringArray
## Bone each entry in `bones` should stick to, e.g. ["LowerLeg.L_end", ...].
@export var targets: PackedStringArray

var _pairs: Array = []  # [bone_idx, target_idx, offset: Transform3D]


func _ready() -> void:
	active = false
	var skeleton := get_skeleton()
	if skeleton == null or bones.size() != targets.size():
		push_warning("RagdollLimbFollow: needs a Skeleton3D parent and matching bones/targets")
		return
	for i in bones.size():
		var b := skeleton.find_bone(bones[i])
		var t := skeleton.find_bone(targets[i])
		if b < 0 or t < 0:
			push_warning("RagdollLimbFollow: unknown bone '%s' or '%s'" % [bones[i], targets[i]])
			continue
		var offset := skeleton.get_bone_global_rest(t).affine_inverse() * skeleton.get_bone_global_rest(b)
		_pairs.append([b, t, offset])


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	for pair in _pairs:
		skeleton.set_bone_global_pose(pair[0], skeleton.get_bone_global_pose(pair[1]) * pair[2])
