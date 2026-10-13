@tool
extends EditorScenePostImport
## Post-import script for KnightCharacter.fbx.
##
## The FBX stores the skeleton in centimetres under an armature node scaled
## x100, and the model is ~5.6 m tall. Physics bodies (ragdoll bones) behave
## badly under scaled parents, so this bakes the armature scale and the final
## character scale into the skeleton, skinned meshes and animation position
## keys, leaving every node at scale 1 and the character ~1.8 m tall.

## Final world scale of the character relative to the FBX's metre units.
const CHARACTER_SCALE := 0.32
const ARMATURE_NODE := "HumanArmature"


func _post_import(scene: Node) -> Object:
	var armature := scene.get_node_or_null(ARMATURE_NODE) as Node3D
	if armature == null:
		push_error("knight_post_import: '%s' not found" % ARMATURE_NODE)
		return scene
	var s := armature.scale.x * CHARACTER_SCALE
	armature.scale = Vector3.ONE

	for skeleton: Skeleton3D in armature.find_children("*", "Skeleton3D", true, false):
		_scale_skeleton(skeleton, s)
		for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
			mi.mesh = _scale_mesh(mi.mesh, s)
			if mi.skin:
				mi.skin = _scale_skin(mi.skin, s)

	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for lib_name in player.get_animation_library_list():
			var lib := player.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				_scale_position_tracks(lib.get_animation(anim_name), s)
	return scene


func _scale_skeleton(skeleton: Skeleton3D, s: float) -> void:
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		rest.origin *= s
		skeleton.set_bone_rest(i, rest)
		skeleton.set_bone_pose_position(i, skeleton.get_bone_pose_position(i) * s)


func _scale_mesh(mesh: Mesh, s: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = mesh.resource_name
	var keep_flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts.size():
			verts[v] *= s
		arrays[Mesh.ARRAY_VERTEX] = verts
		var flags: int = mesh.surface_get_format(i) & keep_flags
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays, [], {}, flags)
		out.surface_set_material(i, mesh.surface_get_material(i))
		if mesh is ArrayMesh:
			out.surface_set_name(i, (mesh as ArrayMesh).surface_get_name(i))
	return out


func _scale_skin(skin: Skin, s: float) -> Skin:
	var out := skin.duplicate() as Skin
	for i in out.get_bind_count():
		var bind := out.get_bind_pose(i)
		bind.origin *= s
		out.set_bind_pose(i, bind)
	return out


func _scale_position_tracks(anim: Animation, s: float) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if anim.track_is_compressed(t):
			push_warning("knight_post_import: compressed track %d in '%s' not scaled" % [t, anim.resource_name])
			continue
		for k in anim.track_get_key_count(t):
			anim.track_set_key_value(t, k, (anim.track_get_key_value(t, k) as Vector3) * s)
