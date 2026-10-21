extends SceneTree
## Generates res://assets/characters/mutant/mutant_animations.res: the
## mutant boss's clips, taken from Mixamo FBX downloads of the same
## character (Warrok W Kurniawan, same skeleton as Mutant.fbx), so no
## retargeting. Only the animation data is kept (the downloads carry the
## whole model each).
##
## Run:  godot --headless --path . -s res://tools/build_mutant_library.gd
## The FBX files are read from SOURCE_DIR at build time and are not part of
## the project. `in_place` clips have the hips' straight-line travel taken
## out (code moves the body); the sway stays. It also prints, per clip, the
## moment the hands move fastest (where an attack lands), for tuning the
## AttackProfiles.

const SOURCE_DIR := "D:/AetherRPG/mutant/"
const OUTPUT := "res://assets/characters/mutant/mutant_animations.res"
const MODEL := "res://assets/characters/mutant/Mutant.fbx"

## Clip name -> [source file, loop, in_place].
const CLIPS := {
	"Idle": ["Mutant Idle", true, false],
	"Walk": ["Strut Walking", true, true],
	"Punch": ["Mutant Punch", false, false],
	"Swipe": ["Mutant Swiping", false, false],
	"JumpAttack": ["Mutant Jump Attack", false, true],
	"Roar": ["Mutant Roaring", false, false],
	"Flex": ["Mutant Flexing Muscles", false, false],
	"Dance": ["Hip Hop Dancing", true, false],
	"Dying": ["Mutant Dying", false, false],
}


func _initialize() -> void:
	var library := AnimationLibrary.new()
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(model)
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	for clip_name: String in CLIPS:
		var spec: Array = CLIPS[clip_name]
		var doc := FBXDocument.new()
		var state := FBXState.new()
		if doc.append_from_file(SOURCE_DIR + spec[0] + ".fbx", state) != OK:
			push_error("cannot read %s" % spec[0])
			continue
		var scene := doc.generate_scene(state)
		var source: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		var names := source.get_animation_list()
		var anim: Animation = source.get_animation(names[names.size() - 1]).duplicate(true)
		scene.free()
		anim.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		if spec[2]:
			var speed := _remove_travel(anim)
			anim.set_meta(&"reference_speed", speed)
		library.add_animation(clip_name, anim)
		_report(clip_name, anim, player, skeleton, library)
	var err := ResourceSaver.save(library, OUTPUT)
	print("saved ", OUTPUT, " (", error_string(err), ")")
	quit()


## Takes the hips' straight start-to-end travel (x, z) out of the clip;
## returns its speed (m/s).
func _remove_travel(anim: Animation) -> float:
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_POSITION_3D \
				or not String(anim.track_get_path(track)).ends_with("mixamorig_Hips"):
			continue
		var count := anim.track_get_key_count(track)
		var first: Vector3 = anim.track_get_key_value(track, 0)
		var last: Vector3 = anim.track_get_key_value(track, count - 1)
		var travel := Vector3(last.x - first.x, 0.0, last.z - first.z)
		for k in count:
			var t := anim.track_get_key_time(track, k) / maxf(anim.length, 0.001)
			anim.track_set_key_value(track, k, (anim.track_get_key_value(track, k) as Vector3) - travel * t)
		return travel.length() / maxf(anim.length, 0.001)
	return 0.0


## Prints the length and when each hand moves fastest (positions from the
## clip's own tracks down the bone chain, over the skeleton's rests).
func _report(clip_name: String, anim: Animation, _player: AnimationPlayer, skeleton: Skeleton3D,
		_library: AnimationLibrary) -> void:
	var peaks := {}
	for hand in ["mixamorig_RightHand", "mixamorig_LeftHand"]:
		var chain: Array[int] = []
		var bone := skeleton.find_bone(hand)
		while bone >= 0:
			chain.push_front(bone)
			bone = skeleton.get_bone_parent(bone)
		var best := 0.0
		var best_time := 0.0
		var previous := Vector3.ZERO
		var steps := int(anim.length * 30.0)
		for i in steps + 1:
			var t := i / 30.0
			var at := Transform3D.IDENTITY
			for b in chain:
				var rest := skeleton.get_bone_rest(b)
				var path := NodePath("Skeleton3D:" + skeleton.get_bone_name(b))
				var rot_track := anim.find_track(path, Animation.TYPE_ROTATION_3D)
				var pos_track := anim.find_track(path, Animation.TYPE_POSITION_3D)
				var rotation := anim.rotation_track_interpolate(rot_track, t) if rot_track >= 0 else rest.basis.get_rotation_quaternion()
				var position := anim.position_track_interpolate(pos_track, t) if pos_track >= 0 else rest.origin
				at = at * Transform3D(Basis(rotation), position)
			if i > 0:
				var speed := at.origin.distance_to(previous) * 30.0
				if speed > best:
					best = speed
					best_time = t
			previous = at.origin
		peaks[hand] = "%.2fs (%.1f m/s)" % [best_time, best]
	print("%s: %.2f s, right hand fastest at %s, left at %s" % [clip_name, anim.length,
		peaks["mixamorig_RightHand"], peaks["mixamorig_LeftHand"]])
