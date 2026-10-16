extends SceneTree
## Generates res://assets/characters/mixamo/mixamo_locomotion.res: an
## AnimationLibrary of Mixamo locomotion clips retargeted onto the Universal
## (UE-mannequin-style) skeleton, used by the rig as the "MX" library.
##
## Run:  godot --headless --path . -s res://tools/build_mixamo_library.gd [-- <source dir>]
## The source FBX files (Mixamo, "Without Skin", Y Bot skeleton) are read from
## SOURCE_DIR at build time and are not part of the project.
##
## Retargeting: both skeletons rest in a T-pose, Y up, facing +Z, in metres,
## so each mapped bone gets the source bone's world-space rotation away from
## its rest applied on top of the target's rest:
##     target_global = source_global * source_rest_global^-1 * target_rest_global
## then converted back to local rotations. Unmapped target bones (root, leaf
## bones) keep their rest. Only the pelvis keeps a position track: the hips'
## offset from rest, scaled by the hip-height ratio, with the clip's travel
## removed (in place) so code-driven movement owns the root. The removed
## travel speed is stored as metadata "reference_speed" (m/s, at our scale) so
## CharacterAnimator can match the cycle rate to the body's speed.

const SOURCE_DIR := "D:/AetherRPG/MIXAMO Animations"
const OUTPUT := "res://assets/characters/mixamo/mixamo_locomotion.res"
const TARGET_BODY := "res://assets/characters/universal/bodies/Superhero_Male_FullBody.gltf"
const TRACK_PREFIX := "Armature/Skeleton3D:"
const FPS := 30.0
const SOURCE_PREFIX := "mixamorig_"

## Output clip name -> source file. The character faces +Z, so its left is +X.
const CLIPS := {
	"Jog_Bwd": "Jog Backward.fbx",
	"Jog_Bwd_L": "Jog Backward Diagonal.fbx",       # travels back and to the left
	"Jog_Bwd_R": "Jog Backward Diagonal (1).fbx",   # travels back and to the right
	"Strafe_L": "Jog Strafe Left.fbx",
	"Strafe_R": "Jog Strafe Right.fbx",
}


func _initialize() -> void:
	var source_dir := SOURCE_DIR
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		source_dir = args[0]

	var target: Node3D = (load(TARGET_BODY) as PackedScene).instantiate()
	root.add_child(target)
	var tgt_skel: Skeleton3D = target.find_children("*", "Skeleton3D", true, false)[0]

	var library := AnimationLibrary.new()
	for clip_name: String in CLIPS:
		var path := source_dir.path_join(CLIPS[clip_name])
		var doc := FBXDocument.new()
		var state := FBXState.new()
		var err := doc.append_from_file(path, state)
		if err != OK:
			push_error("cannot read %s (%s)" % [path, error_string(err)])
			quit(1)
			return
		var source := doc.generate_scene(state)
		root.add_child(source)
		await process_frame  # The AnimationPlayer only applies poses once it has processed.
		var src_skel: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
		var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
		var anim := _retarget(src_skel, player, player.get_animation_list()[0], tgt_skel)
		library.add_animation(clip_name, anim)
		print("%s <- %s: %.2f s, reference speed %.2f m/s" % [
			clip_name, CLIPS[clip_name], anim.length, anim.get_meta("reference_speed")])
		source.free()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var save_err := ResourceSaver.save(library, OUTPUT)
	print("wrote %s (%s)" % [OUTPUT, error_string(save_err)])
	target.free()
	quit(0 if save_err == OK else 1)


func _retarget(src_skel: Skeleton3D, player: AnimationPlayer, anim_name: StringName,
		tgt_skel: Skeleton3D) -> Animation:
	var source_anim := player.get_animation(anim_name)
	var length := source_anim.length
	var bone_map := _bone_map()

	# Target bone -> source bone index, and the rest rotations both sides.
	var source_of := {}
	for b in tgt_skel.get_bone_count():
		var src_name: String = bone_map.get(tgt_skel.get_bone_name(b), "")
		var s := src_skel.find_bone(SOURCE_PREFIX + src_name) if src_name != "" else -1
		if s >= 0:
			source_of[b] = s
	var src_rest := {}
	for s: int in source_of.values():
		src_rest[s] = src_skel.get_bone_global_rest(s).basis.get_rotation_quaternion()
	var tgt_rest := {}
	for b in tgt_skel.get_bone_count():
		tgt_rest[b] = tgt_skel.get_bone_global_rest(b).basis.get_rotation_quaternion()

	var hips := src_skel.find_bone(SOURCE_PREFIX + "Hips")
	var hips_rest := src_skel.get_bone_global_rest(hips).origin
	var pelvis := tgt_skel.find_bone("pelvis")
	var root_bone := tgt_skel.find_bone("root")
	var root_basis_inv := tgt_skel.get_bone_rest(root_bone).basis.inverse()
	# Hip height of the mannequin the animations are authored for (root space,
	# Z up) over the Mixamo hip height.
	var pelvis_rest := AppearanceComponent.ANIMATION_PELVIS_REST
	var ratio := pelvis_rest.z / hips_rest.y

	player.play(anim_name)
	var start := _sample_hips(player, src_skel, hips, 0.0)
	var travel := _sample_hips(player, src_skel, hips, length) - start
	travel.y = 0.0

	var out := Animation.new()
	out.length = length
	out.loop_mode = Animation.LOOP_LINEAR
	out.set_meta("reference_speed", travel.length() / length * ratio)
	var rot_track := {}
	for b in tgt_skel.get_bone_count():
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, TRACK_PREFIX + tgt_skel.get_bone_name(b))
		rot_track[b] = t
	var pelvis_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pelvis_track, TRACK_PREFIX + "pelvis")
	var root_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(root_track, TRACK_PREFIX + "root")
	out.position_track_insert_key(root_track, 0.0, tgt_skel.get_bone_rest(root_bone).origin)

	var frames := int(round(length * FPS))
	for f in frames + 1:
		var time := minf(f / FPS, length)
		var hips_pos := _sample_hips(player, src_skel, hips, time)
		var global := {}
		for b in tgt_skel.get_bone_count():
			var parent := tgt_skel.get_bone_parent(b)
			var parent_q: Quaternion = global[parent] if parent >= 0 else Quaternion.IDENTITY
			var q: Quaternion
			if source_of.has(b):
				var s: int = source_of[b]
				var src_q := src_skel.get_bone_global_pose(s).basis.get_rotation_quaternion()
				q = src_q * src_rest[s].inverse() * tgt_rest[b]
			else:
				q = parent_q * tgt_skel.get_bone_rest(b).basis.get_rotation_quaternion()
			global[b] = q
			out.rotation_track_insert_key(rot_track[b], time, (parent_q.inverse() * q).normalized())
		# In place: remove the straight-line travel, keep sway and bob.
		var offset := hips_pos - hips_rest - travel * (time / length)
		out.position_track_insert_key(pelvis_track, time, pelvis_rest + root_basis_inv * (offset * ratio))
	return out


func _sample_hips(player: AnimationPlayer, skel: Skeleton3D, hips: int, time: float) -> Vector3:
	player.seek(time, true)
	skel.force_update_all_bone_transforms()
	return skel.get_bone_global_pose(hips).origin


## Universal bone name -> Mixamo bone name (without the "mixamorig_" prefix).
static func _bone_map() -> Dictionary:
	var map := {
		"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2",
		"neck_01": "Neck", "Head": "Head",
	}
	for side in [["Left", "l"], ["Right", "r"]]:
		var s: String = side[0]
		var x: String = side[1]
		map["clavicle_" + x] = s + "Shoulder"
		map["upperarm_" + x] = s + "Arm"
		map["lowerarm_" + x] = s + "ForeArm"
		map["hand_" + x] = s + "Hand"
		map["thigh_" + x] = s + "UpLeg"
		map["calf_" + x] = s + "Leg"
		map["foot_" + x] = s + "Foot"
		map["ball_" + x] = s + "ToeBase"
		for finger in [["thumb", "Thumb"], ["index", "Index"], ["middle", "Middle"],
				["ring", "Ring"], ["pinky", "Pinky"]]:
			for i in 3:
				map["%s_%02d_%s" % [finger[0], i + 1, x]] = "%sHand%s%d" % [s, finger[1], i + 1]
	return map
