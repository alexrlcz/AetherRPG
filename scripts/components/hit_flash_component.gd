class_name HitFlashComponent
extends Node
## Briefly tints a mesh when `health` takes damage, using an overlay material
## so the mesh's own materials (and recolour overrides) are untouched.

@export var health: HealthComponent
@export var meshes: Array[GeometryInstance3D] = []
## Alternative to `meshes`: flash every MeshInstance3D under this node, found
## at flash time (for characters whose parts change at runtime).
@export var root: Node3D
@export var color: Color = Color(1, 1, 1, 0.7)
@export var duration: float = 0.15

var _material: StandardMaterial3D
var _tween: Tween
var _targets: Array[GeometryInstance3D] = []


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(color, 0.0)
	health.damaged.connect(_on_damaged)


func _exit_tree() -> void:
	# Freed mid-flash (scene restart): detach the overlay before its material
	# goes away, or the meshes are left pointing at a freed material.
	_clear()


func _on_damaged(_amount: int, _source: Node) -> void:
	flash()


func flash() -> void:
	_clear()
	_targets = _collect()
	for mesh in _targets:
		mesh.material_overlay = _material
	_material.albedo_color = color
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_material, "albedo_color:a", 0.0, duration)
	_tween.tween_callback(_clear)


## True while the overlay is visible (used by tests).
func is_flashing() -> bool:
	return _material.albedo_color.a > 0.0 and _targets.size() > 0 and _targets[0].material_overlay == _material


func _collect() -> Array[GeometryInstance3D]:
	if root == null:
		return meshes
	var result: Array[GeometryInstance3D] = []
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_in_group(&"vfx"):  # weapon trails and other effects
			result.append(mesh)
	return result


func _clear() -> void:
	for mesh in _targets:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	_targets.clear()
