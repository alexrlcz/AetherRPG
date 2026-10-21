class_name AppearanceComponent
extends Node
## Builds a humanoid rig's look from a CharacterAppearance: body meshes, skin
## texture/tint, hairstyle, beard, eyebrows and the gear drawn on it. All
## parts share the Universal skeleton's bone names, so their skinned meshes
## are moved onto this rig's Skeleton3D. Call apply() again at any time to
## change the look.
##
## Gear (`appearance.gear`, filled by the player's Equipment):
## - OutfitPieceDefinition: meshes from the Modular Character Outfits -
##   Fantasy models (assets/characters/outfits), per body. Pieces mix
##   freely (a Ranger hood over a Peasant tunic). Their skin surfaces
##   (hands; MI_Regular_* materials) take the body's skin texture and tint
##   (same UV layout), so they match the face; `cloth_variant` swaps the
##   cloth texture.
## - Other worn gear (helmet, shield) is built onto the skeleton by
##   GearBuilder. A worn cloak turns its spring-bone simulation on.
## Under the gear the body is cut away where every item's
## `hides_body_bones` say (a mesh cut by bone weights, cached per body and
## bone set), so skin never pokes through; `hides_hair` items (helmets,
## hoods) hide the hairstyle and `hides_parts` leave outfit meshes off.
##
## Creatures (Bestiary - Dungeon Monsters Kit, assets/characters/monsters):
## rigged to the same Universal skeleton (55 of its bones), so a creature's
## meshes go on the rig and its bone rests become the rig's proportions just
## like a body's, and the Universal animations drive it. Its weapon (mace,
## stick) is part of its mesh, skinned to the hand. Colour variants swap the
## base colour texture.
##
## Switching body also copies that body's bone rests (proportions) onto the
## skeleton. The animations keep position tracks only on root and pelvis (see
## tools/import/ual_post_import.gd), so every body keeps its own proportions.

## Emitted after every apply(); mesh/material listeners (silhouette) refresh.
signal applied

const BODIES_DIR := "res://assets/characters/universal/bodies/"
const HAIR_DIR := "res://assets/characters/universal/hair/"
const OUTFITS_DIR := "res://assets/characters/outfits/"
const CREATURES_DIR := "res://assets/characters/monsters/"
## Base colour textures per creature, in CharacterAppearance.CREATURES order
## (the first is the one embedded in the model).
const CREATURE_TEXTURES := {
	"Imp": ["Imp_T_Imp_BaseColor_1.png", "T_Imp_BaseColor_2.png", "T_Imp_BaseColor_3.png"],
	"Puglin": ["Puglin_T_Puglin_BaseColor_1.png", "T_Puglin_BaseColor_2.png", "T_Puglin_BaseColor_3.png"],
}
## Cloth textures per outfit (OutfitPieceDefinition.cloth_variant; the
## first is the one the model has).
const OUTFIT_TEXTURES := {
	"Peasant": ["T_Peasant_BaseColor.png", "T_Peasant_2_BaseColor.png"],
	"Ranger": ["T_Ranger_BaseColor.png", "T_Ranger_3_BaseColor.png"],
}
const BODIES := {
	CharacterAppearance.Body.MALE: {
		"scene": BODIES_DIR + "Superhero_Male_FullBody.gltf",
		"meshes": ["SuperHero_Male", "Eyes"],
		"skin_mesh": "SuperHero_Male",
		"light": BODIES_DIR + "T_Superhero_Male_Light.png",
		"dark": BODIES_DIR + "T_Superhero_Male_Dark.png",
	},
	CharacterAppearance.Body.FEMALE: {
		"scene": BODIES_DIR + "Superhero_Female_FullBody.gltf",
		"meshes": ["Superhero_Female", "Eyes"],
		"skin_mesh": "Superhero_Female",
		"light": BODIES_DIR + "T_Superhero_Female_Light_BaseColor.png",
		"dark": BODIES_DIR + "T_Superhero_Female_Dark_BaseColor.png",
	},
}
## Pelvis rest position (root bone space) of the skeleton the animations were
## authored on. The pelvis position track is absolute, so the skeleton is
## shifted by (body pelvis rest - this) to keep the feet on the ground.
const ANIMATION_PELVIS_REST := Vector3(0.0, 0.0501, 0.9167)

@export var appearance: CharacterAppearance
@export var skeleton: Skeleton3D

var _parts: Array[MeshInstance3D] = []
var _skeleton_origin: Vector3
## This character's colour when its appearance asks for a random one.
var _creature_variant: int = -1

## Meshes cut from each body (key -> ArrayMesh): the body without the torso
## under a tunic, without the feet in boots...
static var _cut_meshes: Dictionary = {}


func _ready() -> void:
	_skeleton_origin = skeleton.position
	# The rig's built-in meshes are only an editor preview.
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			_discard(child)
	if appearance:
		apply(appearance)


func apply(new_appearance: CharacterAppearance) -> void:
	appearance = new_appearance
	for part in _parts:
		_discard(part)
	_parts.clear()
	if appearance.creature != "":
		_apply_creature()
		GearBuilder.set_cloak_active(skeleton, null)
		applied.emit()
		return

	var body: Dictionary = BODIES[appearance.body]
	var hidden := PackedStringArray()
	var hidden_bones := {}
	var gear_hides_hair := false
	for item in appearance.gear:
		if item and item.is_worn_visual():
			hidden.append_array(item.hides_parts)
			for bone in item.hides_body_bones:
				hidden_bones[bone] = true
			gear_hides_hair = gear_hides_hair or item.hides_hair
	var source := (load(body["scene"]) as PackedScene).instantiate()
	_copy_proportions(source.find_children("*", "Skeleton3D", true, false)[0])
	var skin_texture: Texture2D = load(body["light" if appearance.skin_texture == CharacterAppearance.SkinTexture.LIGHT else "dark"])
	for mesh_name in body["meshes"]:
		var mesh := _take_mesh(source, mesh_name)
		if mesh_name == body["skin_mesh"]:
			if not hidden_bones.is_empty():
				var bones := PackedStringArray(hidden_bones.keys())
				bones.sort()  # One cached cut per set of bones, whatever the order.
				mesh.mesh = _cut_body(body["scene"], mesh, bones, false)
			var skin := _tinted(mesh, appearance.skin_tint)
			skin.albedo_texture = skin_texture
	source.free()

	for item in appearance.gear:
		var piece := item as OutfitPieceDefinition
		if piece:
			_add_piece(piece, skin_texture, hidden)

	if appearance.hair_style != "None" and not gear_hides_hair:
		_add_hair_part("Hair_" + appearance.hair_style)
	if appearance.beard:
		_add_hair_part("Hair_Beard")
	if appearance.eyebrows != "None":
		_add_hair_part("Eyebrows_" + appearance.eyebrows)
	var cloak: GearDefinition = null
	for item in appearance.gear:
		if item == null or item is OutfitPieceDefinition or not item.is_worn_visual():
			continue
		for mesh in GearBuilder.build(item, skeleton):
			skeleton.add_child(mesh)
			mesh.skeleton = mesh.get_path_to(skeleton)
			_parts.append(mesh)
		if item.rig == GearDefinition.Rig.CLOAK:
			cloak = item
	GearBuilder.set_cloak_active(skeleton, cloak)
	applied.emit()


## Wears the appearance's creature model instead of a human body.
func _apply_creature() -> void:
	var path := CREATURES_DIR + appearance.creature + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("AppearanceComponent: no creature '%s'" % path)
		return
	var textures: Array = CREATURE_TEXTURES.get(appearance.creature, [])
	var variant := appearance.creature_variant
	if variant < 0 and not textures.is_empty():
		# Random per character, kept for later applies. Not written back:
		# enemies of a type share one appearance resource.
		if _creature_variant < 0:
			_creature_variant = randi() % textures.size()
		variant = _creature_variant
	variant = clampi(variant, 0, maxi(textures.size() - 1, 0))
	var colour: Texture2D = load(CREATURES_DIR + textures[variant]) if variant > 0 else null
	var source := (load(path) as PackedScene).instantiate()
	_copy_proportions(source.find_children("*", "Skeleton3D", true, false)[0], true)
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		_attach(mesh)
		if colour:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				if material:
					material = material.duplicate()
					material.albedo_texture = colour
					mesh.set_surface_override_material(surface, material)
	source.free()


## Attaches an outfit piece's meshes for the appearance's body (leaving off
## any whose names contain one of `hidden`).
func _add_piece(piece: OutfitPieceDefinition, skin_texture: Texture2D, hidden: PackedStringArray) -> void:
	var female := appearance.body == CharacterAppearance.Body.FEMALE
	var path := OUTFITS_DIR + ("Female_" if female else "Male_") + piece.outfit + ".gltf"
	if not ResourceLoader.exists(path):
		push_warning("AppearanceComponent: no outfit '%s'" % path)
		return
	var source := (load(path) as PackedScene).instantiate()
	var textures: Array = OUTFIT_TEXTURES.get(piece.outfit, [])
	var variant := clampi(piece.cloth_variant, 0, maxi(textures.size() - 1, 0))
	var cloth: Texture2D = load(OUTFITS_DIR + textures[variant]) if variant > 0 else null
	for mesh_name in piece.meshes_for(female):
		var mesh := source.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh == null:
			push_warning("AppearanceComponent: %s has no mesh '%s'" % [path.get_file(), mesh_name])
			continue
		if Array(hidden).any(func(part: String) -> bool: return part in mesh.name):
			continue
		_attach(mesh)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			if material.resource_name.begins_with("MI_Regular"):
				# Exposed skin: the body's texture and tint, like the face.
				material = material.duplicate()
				material.albedo_texture = skin_texture
				material.albedo_color = appearance.skin_tint
				mesh.set_surface_override_material(surface, material)
			elif cloth:
				material = material.duplicate()
				material.albedo_texture = cloth
				mesh.set_surface_override_material(surface, material)
	source.free()


## The body mesh cut down to the triangles whose corners are mostly weighted
## to `bone_names` (`keep`), or to the others (not `keep`: no torso under a
## tunic, no feet in boots). Made once per body and cut, then shared.
static func _cut_body(body_key: String, body: MeshInstance3D, bone_names: PackedStringArray,
		keep: bool) -> ArrayMesh:
	var key := "%s|%s|%s" % [body_key, ",".join(bone_names), keep]
	if _cut_meshes.has(key):
		return _cut_meshes[key]
	var full := body.mesh as ArrayMesh
	var arrays := full.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per_vertex := bones.size() / count
	var head_binds := {}
	for i in body.skin.get_bind_count():
		if String(body.skin.get_bind_name(i)) in bone_names:
			head_binds[i] = true
	var kept := PackedByteArray()
	kept.resize(count)
	for v in count:
		var weight := 0.0
		for k in per_vertex:
			if head_binds.has(bones[v * per_vertex + k]):
				weight += weights[v * per_vertex + k]
		kept[v] = 1 if (weight >= 0.5) == keep else 0
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var head_index := PackedInt32Array()
	for t in range(0, index.size(), 3):
		if kept[index[t]] and kept[index[t + 1]] and kept[index[t + 2]]:
			head_index.append_array([index[t], index[t + 1], index[t + 2]])
	arrays[Mesh.ARRAY_INDEX] = head_index
	# Custom vertex channels (the female body has some) would need their
	# format flags; the head's material doesn't read them.
	for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[channel] = null
	var head := ArrayMesh.new()
	head.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		full.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	head.surface_set_material(0, full.surface_get_material(0))
	_cut_meshes[key] = head
	return head


## Currently attached part meshes (body, eyes, hair...).
func get_parts() -> Array[MeshInstance3D]:
	return _parts


## Detaches right away (frees its name for the replacement part), frees later.
func _discard(mesh: MeshInstance3D) -> void:
	mesh.get_parent().remove_child(mesh)
	mesh.queue_free()


func _add_hair_part(part_name: String) -> void:
	var path := HAIR_DIR + part_name + ".gltf"
	if not ResourceLoader.exists(path):
		push_warning("AppearanceComponent: missing part '%s'" % path)
		return
	var source := (load(path) as PackedScene).instantiate()
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		_attach(mesh)
		_tinted(mesh, appearance.hair_color)
	source.free()


func _take_mesh(source: Node, mesh_name: String) -> MeshInstance3D:
	var mesh := source.find_child(mesh_name, true, false) as MeshInstance3D
	_attach(mesh)
	return mesh


## Moves a skinned mesh from a part scene onto this rig's skeleton. Skins are
## imported with bone names, so binds resolve against any Universal skeleton.
func _attach(mesh: MeshInstance3D) -> void:
	mesh.get_parent().remove_child(mesh)
	mesh.owner = null
	skeleton.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	_parts.append(mesh)


## Gives the mesh its own copy of its material, tinted, and returns it.
func _tinted(mesh: MeshInstance3D, tint: Color) -> StandardMaterial3D:
	var material := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = tint
	mesh.set_surface_override_material(0, material)
	return material


## Copies `source`'s bone rests (proportions). With `scale_motion` (creatures
## of another size), animated positions (the pelvis bob and crouch, authored
## in metres for a human) are scaled by the pelvis height ratio
## (Skeleton3D.motion_scale), so a small creature crouches as deep as its own
## legs allow instead of a human's metre-for-metre.
func _copy_proportions(source: Skeleton3D, scale_motion: bool = false) -> void:
	for i in skeleton.get_bone_count():
		var j := source.find_bone(skeleton.get_bone_name(i))
		if j >= 0:
			skeleton.set_bone_rest(i, source.get_bone_rest(j))
	# Bones without position tracks keep their pose position, so reset it.
	skeleton.reset_bone_poses()
	var root_rest := skeleton.get_bone_rest(0)
	var pelvis_rest := skeleton.get_bone_rest(skeleton.find_bone("pelvis"))
	var motion := pelvis_rest.origin.z / ANIMATION_PELVIS_REST.z if scale_motion else 1.0
	skeleton.motion_scale = motion
	skeleton.position = _skeleton_origin + root_rest.basis * (pelvis_rest.origin - ANIMATION_PELVIS_REST * motion)
