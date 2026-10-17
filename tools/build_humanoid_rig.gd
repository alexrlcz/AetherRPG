extends SceneTree
## Generates res://scenes/characters/humanoid_rig.tscn: an instance of the male
## base character (skeleton + default meshes) plus a ragdoll
## (PhysicalBoneSimulator3D + PhysicalBone3Ds), the right-hand weapon
## attachment and an AnimationPlayer using the Universal Animation Library:
## UAL1 as the default library ("Idle", "Sword_Attack"...) and UAL2 as the
## "UAL2" library ("UAL2/Sword_Regular_A"...). Both share the same skeleton.
## Retargeted Mixamo locomotion (tools/build_mixamo_library.gd) is the "MX"
## library ("MX/Strafe_L"...), the retargeted Mixamo greatsword set the "GS"
## library ("GS/Slash"...).
## The look (body, skin, hair...) is applied at runtime by AppearanceComponent.
##
## Run:  godot --headless --path . -s res://tools/build_humanoid_rig.gd
## Re-run after changing the table below or the model. Hand edits to the
## generated scene are overwritten.

const MODEL := "res://assets/characters/universal/bodies/Superhero_Male_FullBody.gltf"
const ANIMATIONS := "res://assets/characters/universal/animations/UAL1_Standard.glb"
const ANIMATIONS_2 := "res://assets/characters/universal/animations/UAL2_Standard.glb"
const ANIMATIONS_MX := "res://assets/characters/mixamo/mixamo_locomotion.res"
const ANIMATIONS_GS := "res://assets/characters/mixamo/mixamo_greatsword.res"
const OUTPUT := "res://scenes/characters/humanoid_rig.tscn"
const SKELETON := "Armature/Skeleton3D"
const SIM := SKELETON + "/PhysicalBoneSimulator3D"
const RAGDOLL_LAYER := 1 << 6  # layer 7 "ragdoll"
const WORLD_MASK := 1           # layer 1 "world"

enum { NONE, CONE }

## bone, end (bone name, or a Vector3 offset from the bone in model space for
## leaf bones), radius, mass, joint, swing, twist.
## Bones without an entry (spine_01, neck, clavicles, hands, feet) follow
## their nearest simulated parent.
const BONES := [
	["pelvis", "spine_02", 0.15, 12.0, NONE, 0, 0],
	["spine_02", "neck_01", 0.16, 14.0, CONE, 20, 15],
	["Head", Vector3(0, 0.24, 0.02), 0.11, 4.0, CONE, 35, 30],
	["upperarm_l", "lowerarm_l", 0.065, 2.5, CONE, 70, 30],
	["lowerarm_l", "hand_l", 0.05, 1.5, CONE, 60, 10],
	["upperarm_r", "lowerarm_r", 0.065, 2.5, CONE, 70, 30],
	["lowerarm_r", "hand_r", 0.05, 1.5, CONE, 60, 10],
	["thigh_l", "calf_l", 0.085, 6.0, CONE, 45, 15],
	["calf_l", "foot_l", 0.07, 4.0, CONE, 50, 10],
	["thigh_r", "calf_r", 0.085, 6.0, CONE, 45, 15],
	["calf_r", "foot_r", 0.07, 4.0, CONE, 50, 10],
]


func _initialize() -> void:
	var model := (load(MODEL) as PackedScene).instantiate()
	var skeleton := model.get_node(SKELETON) as Skeleton3D

	var subs := PackedStringArray()
	var nodes := PackedStringArray()
	nodes.append('[node name="HumanoidRig" instance=ExtResource("1_model")]\n')
	nodes.append('[node name="PhysicalBoneSimulator3D" type="PhysicalBoneSimulator3D" parent="%s"]\n' % SKELETON)

	for spec in BONES:
		_emit_bone(skeleton, spec, subs, nodes)

	nodes.append('[node name="RightHand" type="BoneAttachment3D" parent="%s"]\nbone_name = "hand_r"\n' % SKELETON)
	nodes.append('[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\nlibraries = {\n&"": ExtResource("2_anims"),\n&"UAL2": ExtResource("3_anims"),\n&"MX": ExtResource("4_anims"),\n&"GS": ExtResource("5_anims")\n}\n')

	var text := "[gd_scene format=3]\n\n"
	text += '[ext_resource type="PackedScene" path="%s" id="1_model"]\n' % MODEL
	text += '[ext_resource type="AnimationLibrary" path="%s" id="2_anims"]\n' % ANIMATIONS
	text += '[ext_resource type="AnimationLibrary" path="%s" id="3_anims"]\n' % ANIMATIONS_2
	text += '[ext_resource type="AnimationLibrary" path="%s" id="4_anims"]\n' % ANIMATIONS_MX
	text += '[ext_resource type="AnimationLibrary" path="%s" id="5_anims"]\n\n' % ANIMATIONS_GS
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
	assert(bone >= 0, "missing bone %s" % bone_name)
	var bone_global := skeleton.get_bone_global_rest(bone)
	var end_global: Vector3
	if spec[1] is Vector3:
		end_global = bone_global.origin + spec[1]
	else:
		var end := skeleton.find_bone(spec[1])
		assert(end >= 0, "missing bone %s" % spec[1])
		end_global = skeleton.get_bone_global_rest(end).origin
	var radius: float = spec[2]

	# Same construction as the editor's "Create Physical Skeleton", but with a
	# chosen end point: the body is centred on the segment, -Z along it.
	var end_local := bone_global.affine_inverse() * end_global
	var half := end_local.length() * 0.5
	var up := Vector3.UP if not Vector3.UP.cross(end_local).is_zero_approx() else Vector3.BACK
	var body_offset := Transform3D(Basis.looking_at(end_local, up), Vector3.ZERO)
	body_offset.origin = body_offset.basis * Vector3(0, 0, -half)
	var joint_offset := Transform3D(Basis.IDENTITY, Vector3(0, 0, half))
	var height := maxf(half * 2.0, radius * 2.0 + 0.01)

	subs.append('[sub_resource type="CapsuleShape3D" id="Capsule_%s"]\nradius = %s\nheight = %s\n' % [bone_name, _f(radius), _f(height)])

	var n := '[node name="Physical Bone %s" type="PhysicalBone3D" parent="%s"]\n' % [bone_name, SIM]
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

	var shape := '[node name="CollisionShape3D" type="CollisionShape3D" parent="%s/Physical Bone %s"]\n' % [SIM, bone_name]
	shape += "transform = %s\n" % var_to_str(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO))
	shape += 'shape = SubResource("Capsule_%s")\n' % bone_name
	nodes.append(shape)


static func _f(v: float) -> String:
	return var_to_str(float(v))
