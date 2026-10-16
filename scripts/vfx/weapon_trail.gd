class_name WeaponTrail
extends Node3D
## Fading ribbon behind a blade while `emitting`. Put it on the weapon's bone
## attachment; `base_offset` / `tip_offset` are the blade's ends in this node's
## space. Between frames the ribbon follows the interpolated blade transform,
## so a fast swing draws an arc rather than straight chords.
## With `melee` set, it emits during each strike in the attack's trail colour.

@export var melee: MeleeAttackComponent
@export var base_offset: Vector3 = Vector3(0, 0.085, 0.15)
@export var tip_offset: Vector3 = Vector3(0, 0.085, 0.95)
## Seconds a ribbon segment takes to fade out.
@export var lifetime: float = 0.13
@export var color: Color = Color(0.85, 0.9, 1.0, 0.55)
## Maximum distance (m) the tip moves between two ribbon samples.
@export var sample_spacing: float = 0.08
@export var emitting: bool = false:
	set(value):
		if value and not emitting:
			_last = Transform3D()
			_has_last = false
		emitting = value

var _samples: Array[Dictionary] = []  # {base, tip, age}
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _last: Transform3D
var _has_last: bool = false


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.top_level = true
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Character-wide material effects (hit flash, silhouette) skip it.
	instance.add_to_group(&"vfx")
	add_child(instance)
	instance.global_transform = Transform3D.IDENTITY
	if melee:
		melee.struck.connect(_on_struck)
		melee.strike_ended.connect(_on_strike_ended)
		melee.finished.connect(_on_strike_ended)


func sample_count() -> int:
	return _samples.size()


func _on_struck(profile: AttackProfile) -> void:
	if profile:
		color = profile.trail_color
	emitting = true


func _on_strike_ended(_profile: AttackProfile = null) -> void:
	emitting = false


func _process(delta: float) -> void:
	for sample in _samples:
		sample.age += delta
	while not _samples.is_empty() and _samples[0].age >= lifetime:
		_samples.pop_front()
	if emitting:
		_add_samples()
	_rebuild()


func _add_samples() -> void:
	var now := global_transform
	if not _has_last:
		_push(now)
	else:
		var travel := (now * tip_offset).distance_to(_last * tip_offset)
		var steps := clampi(ceili(travel / sample_spacing), 1, 24)
		for s in range(1, steps + 1):
			_push(_last.interpolate_with(now, float(s) / steps))
	_last = now
	_has_last = true


func _push(xf: Transform3D) -> void:
	_samples.append({base = xf * base_offset, tip = xf * tip_offset, age = 0.0})


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	var count := _samples.size()
	for i in count:
		var sample: Dictionary = _samples[i]
		var fade: float = 1.0 - sample.age / lifetime
		# Oldest end tapers to nothing.
		var taper := float(i + 1) / count
		var c := Color(color, color.a * fade * taper)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(sample.base)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(sample.tip)
	_mesh.surface_end()
