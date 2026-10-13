extends SceneTree
## Generates res://scenes/characters/knight_rig.tscn: an instance of the knight
## FBX plus a ragdoll (PhysicalBoneSimulator3D + PhysicalBone3Ds), the
## foot-follow modifier and the right-hand weapon attachment.
##
## Run:  godot --headless --path . -s res://tools/build_knight_rig.gd
## Re-run after changing the table below or the model. Hand edits to the
## generated scene are overwritten.

const MODEL := "res://assets/characters/knight/KnightCharacter.fbx"
const OUTPUT := "res://scenes/characters/knight_rig.tscn"
const FOLLOW_SCRIPT := "res://scripts/characters/ragdoll_limb_follow.gd"
const SKELETON := "HumanArmature/Skeleton3D"
const SIM := SKELETON + "/PhysicalBoneSimulator3D"
const RAGDOLL_LAYER := 1 << 6  # layer 7 "ragdoll"
const WORLD_MASK := 1           # layer 1 "world"

enum { NONE, CONE }

## bone, end bone (sets length/direction), radius, mass, joint, swing, twist
const BONES := [
	["Body", "Abdomen", 0.17, 12.0, NONE, 0, 0],
	["Abdomen", "Torso", 0.15, 8.0, CONE, 20, 15],
	["Torso", "Neck", 0.17, 12.0, CONE, 20, 15],
	["Head", "Head_end", 0.19, 4.0, CONE, 35, 30],
	["UpperArm.L", "LowerArm.L", 0.07, 2.5, CONE, 70, 30],
	["LowerArm.L", "Palm.L", 0.06, 1.5, CONE, 60, 10],
	["UpperArm.R", "LowerArm.R", 0.07, 2.5, CONE, 70, 30],
	["LowerArm.R", "Palm.R", 0.06, 1.5, CONE, 60, 10],
	["UpperLeg.L", "LowerLeg.L", 0.09, 6.0, CONE, 45, 15],
	["LowerLeg.L", "LowerLeg.L_end", 0.08, 4.0, CONE, 50, 10],
	["UpperLeg.R", "LowerLeg.R", 0.09, 6.0, CONE, 45, 15],
	["LowerLeg.R", "LowerLeg.R_end", 0.08, 4.0, CONE, 50, 10],
]


func _initialize() -> void:
	var model := (load(MODEL) as PackedScene).instantiate()
	var skeleton := model.get_node(SKELETON) as Skeleton3D

	var subs := PackedStringArray()
	var nodes := PackedStringArray()
	nodes.append('[node name="KnightRig" instance=ExtResource("1_model")]\n')
	nodes.append('[node name="PhysicalBoneSimulator3D" type="PhysicalBoneSimulator3D" parent="%s"]\n' % SKELETON)

	for spec in BONES:
		_emit_bone(skeleton, spec, subs, nodes)

	nodes.append('[node name="RagdollLimbFollow" type="SkeletonModifier3D" parent="%s"]\nscript = ExtResource("2_follow")\nbones = PackedStringArray("Foot.L", "Foot.R")\ntargets = PackedStringArray("LowerLeg.L_end", "LowerLeg.R_end")\n' % SKELETON)
	nodes.append('[node name="RightHand" type="BoneAttachment3D" parent="%s"]\nbone_name = "Palm.R"\n' % SKELETON)

	var text := "[gd_scene format=3]\n\n"
	text += '[ext_resource type="PackedScene" path="%s" id="1_model"]\n' % MODEL
	text += '[ext_resource type="Script" path="%s" id="2_follow"]\n\n' % FOLLOW_SCRIPT
	text += "\n".join(subs) + "\n" + "\n".join(nodes)

	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("wrote %s (%d physical bones)" % [OUTPUT, BONES.size()])
	model.free()
	quit()


func _emit_bone(skeleton: Skeleton3D, spec: Array, subs: PackedStringArray, nodes: PackedStringArray) -> void:
	var bone_name: String = spec[0]
	var bone := skeleton.find_bone(bone_name)
	var end := skeleton.find_bone(spec[1])
	assert(bone >= 0 and end >= 0, "missing bone %s/%s" % [spec[0], spec[1]])
	var radius: float = spec[2]
	var safe := bone_name.replace(".", "_")

	# Same construction as the editor's "Create Physical Skeleton", but with a
	# chosen end bone: the body is centred on the segment, -Z along it.
	var bone_global := skeleton.get_bone_global_rest(bone)
	var end_local := bone_global.affine_inverse() * skeleton.get_bone_global_rest(end).origin
	var half := end_local.length() * 0.5
	var up := Vector3.UP if not Vector3.UP.cross(end_local).is_zero_approx() else Vector3.BACK
	var body_offset := Transform3D(Basis.looking_at(end_local, up), Vector3.ZERO)
	body_offset.origin = body_offset.basis * Vector3(0, 0, -half)
	var joint_offset := Transform3D(Basis.IDENTITY, Vector3(0, 0, half))
	var height := maxf(half * 2.0, radius * 2.0 + 0.01)

	subs.append('[sub_resource type="CapsuleShape3D" id="Capsule_%s"]\nradius = %s\nheight = %s\n' % [safe, _f(radius), _f(height)])

	var n := '[node name="Physical Bone %s" type="PhysicalBone3D" parent="%s"]\n' % [safe, SIM]
	n += "transform = %s\n" % var_to_str(bone_global * body_offset)
	n += "collision_layer = %d\ncollision_mask = %d\n" % [RAGDOLL_LAYER, WORLD_MASK]
	n += "joint_type = %d\n" % (PhysicalBone3D.JOINT_TYPE_CONE if spec[4] == CONE else PhysicalBone3D.JOINT_TYPE_NONE)
	n += "joint_offset = %s\n" % var_to_str(joint_offset)
	n += "body_offset = %s\n" % var_to_str(body_offset)
	n += 'bone_name = "%s"\n' % bone_name
	if spec[4] == CONE:
		n += "joint_constraints/swing_span = %s\njoint_constraints/twist_span = %s\n" % [_f(spec[5]), _f(spec[6])]
	n += "mass = %s\nfriction = 0.9\nlinear_damp = 0.2\nangular_damp = 2.0\n" % _f(spec[3])
	nodes.append(n)

	var shape := '[node name="CollisionShape3D" type="CollisionShape3D" parent="%s/Physical Bone %s"]\n' % [SIM, safe]
	shape += "transform = %s\n" % var_to_str(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO))
	shape += 'shape = SubResource("Capsule_%s")\n' % safe
	nodes.append(shape)


static func _f(v: float) -> String:
	return var_to_str(float(v))
