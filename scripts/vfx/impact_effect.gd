class_name ImpactEffect
extends Node3D
## Placeholder sword-hit effect, built from primitives: directional sparks,
## a short flash and a slash streak along the swing. ImpactFeedbackComponent
## spawns one per confirmed hit and calls setup(); it frees itself.
## Replace with authored VFX by giving ImpactFeedbackComponent another scene
## whose root has the same setup(event, strength) method.

@export var lifetime: float = 0.4
@export var spark_count: int = 10
@export var spark_speed: float = 6.0
@export var flash_size: float = 0.55
@export var streak_length: float = 1.1


func setup(event: HitEvent, strength: float) -> void:
	var color := event.profile.impact_color if event.profile else Color(1.0, 0.85, 0.55)
	var away := event.swing_direction if event.swing_direction != Vector3.ZERO else event.direction
	_add_sparks(away, color, strength)
	_add_flash(color, strength)
	if event.swing_direction != Vector3.ZERO:
		_add_streak(event.swing_direction, color, strength)
	var tween := create_tween()
	tween.tween_interval(lifetime)
	tween.tween_callback(queue_free)


func _add_sparks(direction: Vector3, color: Color, strength: float) -> void:
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = maxi(int(spark_count * strength), 3)
	sparks.lifetime = 0.25
	sparks.local_coords = false
	# Sparks fly on along the blade's path, with a little lift.
	sparks.direction = (direction.normalized() + Vector3.UP * 0.35).normalized()
	sparks.spread = 38.0
	sparks.initial_velocity_min = spark_speed * 0.5 * strength
	sparks.initial_velocity_max = spark_speed * strength
	sparks.gravity = Vector3(0, -12, 0)
	sparks.damping_min = 4.0
	sparks.damping_max = 8.0
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.16, 0.025)
	mesh.material = _material(color.lightened(0.3), true)
	sparks.mesh = mesh
	add_child(sparks)
	sparks.emitting = true


func _add_flash(color: Color, strength: float) -> void:
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * flash_size * strength
	var material := _material(Color(color.lightened(0.5), 0.9), true)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	var tween := flash.create_tween().set_parallel()
	tween.tween_property(flash, "scale", Vector3.ONE * 1.6, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.1)


## Thin quad laid along the swing, turned to face the camera.
func _add_streak(swing: Vector3, color: Color, strength: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var to_camera := camera.global_basis.z if camera else Vector3.UP
	var x := swing.normalized()
	var y := to_camera.cross(x)
	if y.length_squared() < 0.0001:
		return
	y = y.normalized()
	var z := x.cross(y).normalized()
	var streak := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(streak_length * strength, 0.07 * strength)
	var material := _material(Color(color.lightened(0.6), 0.85), true)
	quad.material = material
	streak.mesh = quad
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(streak)
	streak.global_basis = Basis(x, y, z)
	var tween := streak.create_tween().set_parallel()
	tween.tween_property(streak, "scale", Vector3(1.4, 0.2, 1.0), 0.13)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.13)


static func _material(color: Color, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Drawn over the body it hits, which half-hides the contact point.
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material
