@tool
extends EditorScenePostImport
## Post-import script for the Universal Animation Library (UAL1_Standard.glb,
## UAL2_Standard.glb), imported as AnimationLibraries.
##
## The library's tracks move every bone to the reference mannequin's
## proportions. Our bodies (male / female base characters) share its bone
## names but not its bone lengths, so only rotations are kept for most bones:
## position tracks survive on `root` and `pelvis` only (body movement / bob),
## and scale tracks are dropped (always 1). Each body then keeps its own
## proportions. See HumanoidAppearance for the pelvis height correction.

const KEEP_POSITION_BONES := ["root", "pelvis"]


func _post_import(scene: Node) -> Object:
	var removed := 0
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for lib_name in player.get_animation_library_list():
			var lib := player.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				removed += _strip(lib.get_animation(anim_name))
	print("ual_post_import: removed %d position/scale tracks" % removed)
	return scene


func _strip(anim: Animation) -> int:
	var removed := 0
	for t in range(anim.get_track_count() - 1, -1, -1):
		var type := anim.track_get_type(t)
		if type == Animation.TYPE_SCALE_3D:
			anim.remove_track(t)
			removed += 1
		elif type == Animation.TYPE_POSITION_3D:
			var bone := str(anim.track_get_path(t).get_concatenated_subnames())
			if bone not in KEEP_POSITION_BONES:
				anim.remove_track(t)
				removed += 1
	return removed
