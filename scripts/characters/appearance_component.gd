class_name AppearanceComponent
extends Node
## Builds a humanoid rig's look from a CharacterAppearance: body meshes, skin
## texture/tint, hairstyle, beard and eyebrows. All parts share the Universal
## skeleton's bone names, so their skinned meshes are moved onto this rig's
## Skeleton3D. Call apply() again at any time to change the look.
##
## Switching body also copies that body's bone rests (proportions) onto the
## skeleton. The animations keep position tracks only on root and pelvis (see
## tools/import/ual_post_import.gd), so every body keeps its own proportions.

## Emitted after every apply(); mesh/material listeners (silhouette) refresh.
signal applied

const BODIES_DIR := "res://assets/characters/universal/bodies/"
const HAIR_DIR := "res://assets/characters/universal/hair/"
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

	var body: Dictionary = BODIES[appearance.body]
	var source := (load(body["scene"]) as PackedScene).instantiate()
	_copy_proportions(source.find_children("*", "Skeleton3D", true, false)[0])
	for mesh_name in body["meshes"]:
		var mesh := _take_mesh(source, mesh_name)
		if mesh_name == body["skin_mesh"]:
			var skin := _tinted(mesh, appearance.skin_tint)
			var texture_key := "light" if appearance.skin_texture == CharacterAppearance.SkinTexture.LIGHT else "dark"
			skin.albedo_texture = load(body[texture_key])
	source.free()

	if appearance.hair_style != "None":
		_add_hair_part("Hair_" + appearance.hair_style)
	if appearance.beard:
		_add_hair_part("Hair_Beard")
	if appearance.eyebrows != "None":
		_add_hair_part("Eyebrows_" + appearance.eyebrows)
	applied.emit()


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


func _copy_proportions(source: Skeleton3D) -> void:
	for i in skeleton.get_bone_count():
		var j := source.find_bone(skeleton.get_bone_name(i))
		if j >= 0:
			skeleton.set_bone_rest(i, source.get_bone_rest(j))
	# Bones without position tracks keep their pose position, so reset it.
	skeleton.reset_bone_poses()
	var root_rest := skeleton.get_bone_rest(0)
	var pelvis_rest := skeleton.get_bone_rest(skeleton.find_bone("pelvis"))
	skeleton.position = _skeleton_origin + root_rest.basis * (pelvis_rest.origin - ANIMATION_PELVIS_REST)
