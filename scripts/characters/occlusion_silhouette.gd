class_name OcclusionSilhouette
extends Node
## Shows a flat-colour silhouette of a character wherever obstacles hide it.
##
## Uses BaseMaterial3D's X-Ray stencil mode: the character's own pass writes
## stencil 1 where it is visible, and an extra no-depth-test pass draws
## `color` only where the stencil is not 1. So the silhouette never covers the
## character's own visible pixels (no self x-ray) or other characters.
## Each surface gets its own material copy, so recolour overrides are kept.
## Call refresh() after the character's meshes or materials change
## (AppearanceComponent.applied is connected to it).

@export var root: Node3D
## Silhouette colour; alpha controls how strongly it shows through obstacles.
@export var color: Color = Color(0.35, 0.65, 1.0, 0.55)
## Optional: the silhouette is turned off when this dies (corpses don't x-ray).
@export var health: HealthComponent

var enabled: bool = true
var _materials: Array[BaseMaterial3D] = []


func _ready() -> void:
	refresh()
	if health:
		health.died.connect(set_enabled.bind(false))


## Re-applies the silhouette to every mesh currently under `root`.
func refresh() -> void:
	_materials.clear()
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_queued_for_deletion():
			_apply(mesh)
	set_enabled(enabled)


func set_enabled(value: bool) -> void:
	enabled = value
	for mat in _materials:
		mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY if value else BaseMaterial3D.STENCIL_MODE_DISABLED
		if value:
			mat.stencil_color = color


func get_materials() -> Array[BaseMaterial3D]:
	return _materials


func _apply(mesh: MeshInstance3D) -> void:
	for i in mesh.get_surface_override_material_count():
		var source := mesh.get_active_material(i) as BaseMaterial3D
		if source == null:
			continue
		var mat := source.duplicate() as BaseMaterial3D
		mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
		mat.stencil_color = color
		mesh.set_surface_override_material(i, mat)
		_materials.append(mat)
