class_name ExitGate
extends Area3D
## The way to the next level: a stone arch with a glowing portal. Emits
## `player_entered` once when the player's body steps into it (enemies and
## other bodies are ignored). Visuals are built in code, like the dungeon's;
## the pillars are solid (a StaticBody3D on the world layer), so placed under
## a NavigationRegion3D they bake into the navmesh like any prop.
## DungeonBuilder puts one on every "Exit" label.

signal player_entered

## Seconds after entering the tree before the gate reacts (no instant
## trigger while a level is being set up).
@export var arm_delay: float = 0.5
@export var portal_color: Color = Color(0.45, 0.75, 1.0)

var _armed_at: float = INF
var _used: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Player body.
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 1.2)
	shape.shape = box
	shape.position = Vector3(0, 1.2, 0)
	add_child(shape)
	_build_visuals()
	_armed_at = Time.get_ticks_msec() / 1000.0 + arm_delay
	body_entered.connect(_on_body_entered)


## True once it has sent the player on (it fires once).
func is_used() -> bool:
	return _used


func _on_body_entered(body: Node3D) -> void:
	if _used or not body.is_in_group(&"player") or Time.get_ticks_msec() / 1000.0 < _armed_at:
		return
	_used = true
	player_entered.emit()


func _physics_process(_delta: float) -> void:
	# A player already standing in the gate when it arms still counts.
	if _used or Time.get_ticks_msec() / 1000.0 < _armed_at:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group(&"player"):
			_on_body_entered(body)
			return


func _build_visuals() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.35, 0.34, 0.38)
	stone.roughness = 0.9
	var pillars := StaticBody3D.new()
	pillars.name = "Pillars"
	pillars.collision_layer = 1  # World.
	pillars.collision_mask = 0
	add_child(pillars)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.5, 3.0, 0.7), Vector3(side * 1.45, 1.5, 0), stone)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.5, 3.0, 0.7)
		shape.shape = box
		shape.position = Vector3(side * 1.45, 1.5, 0)
		pillars.add_child(shape)
	_box(Vector3(3.6, 0.5, 0.8), Vector3(0, 3.2, 0), stone)
	_box(Vector3(3.8, 0.06, 1.4), Vector3(0, 0.03, 0), stone)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(portal_color, 0.55)
	glow.emission_enabled = true
	glow.emission = portal_color
	glow.emission_energy_multiplier = 2.0
	var portal := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.9)
	quad.material = glow
	portal.mesh = quad
	portal.position = Vector3(0, 1.55, 0)
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(portal)
	var light := OmniLight3D.new()
	light.light_color = portal_color
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.position = Vector3(0, 1.6, 0.8)
	add_child(light)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)
