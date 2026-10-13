class_name HitFlashComponent
extends Node
## Briefly tints a mesh when `health` takes damage, using an overlay material
## so the mesh's own materials (and recolour overrides) are untouched.

@export var health: HealthComponent
@export var meshes: Array[GeometryInstance3D] = []
@export var color: Color = Color(1, 1, 1, 0.7)
@export var duration: float = 0.15

var _material: StandardMaterial3D
var _tween: Tween


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(color, 0.0)
	health.damaged.connect(_on_damaged)


func _on_damaged(_amount: int, _source: Node) -> void:
	flash()


func flash() -> void:
	for mesh in meshes:
		mesh.material_overlay = _material
	_material.albedo_color = color
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_material, "albedo_color:a", 0.0, duration)
	_tween.tween_callback(_clear)


## True while the overlay is visible (used by tests).
func is_flashing() -> bool:
	return _material.albedo_color.a > 0.0 and meshes.size() > 0 and meshes[0].material_overlay == _material


func _clear() -> void:
	for mesh in meshes:
		mesh.material_overlay = null
