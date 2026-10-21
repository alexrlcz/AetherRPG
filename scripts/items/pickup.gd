class_name Pickup
extends Area3D
## An item lying in the world (LootSpawner makes them from a loot roll).
## launch() pops it out in a small arc onto the
## floor (no physics body: it flies a fixed arc down to the height it was
## launched from); then it spins and bobs. An `auto_collect` item (gold)
## flies to the player once they are within `magnet_radius` and is collected
## on contact. Gear (GearDefinition) waits for the interact key: it is an
## interactable (Interactor.GROUP) once it has landed. Taking it equips it
## when a slot it fits is empty (the collector's `equipment`), else puts it
## in the collector's `inventory`; with the bag full it stays on the floor
## and the HUD says so.
##
## On the "interactable" physics layer; it doesn't monitor anything itself.
## In group GROUP.

signal collected(pickup: Pickup, collector: Node3D)

const GROUP := &"pickups"
const INTERACTABLE_LAYER := 1 << 5

@export var item: ItemDefinition
@export var amount: int = 1
## Seconds after spawning before it can be collected (let the pop be seen).
@export var collect_delay: float = 0.45
## Distance (m, horizontal) at which an auto-collect item starts flying to
## the player, and its flight speed range (m/s, accelerating).
@export var magnet_radius: float = 3.5
@export var magnet_speed: Vector2 = Vector2(4.0, 16.0)
## Collected within this distance (m) of the player's chest.
@export var collect_radius: float = 0.5

var velocity: Vector3 = Vector3.ZERO
var _floor_y: float = 0.0
var _airborne: bool = false
var _age: float = 0.0
var _magnet_time: float = 0.0
var _visual: Node3D
var _collected: bool = false

const _GRAVITY := 16.0
const _COIN_COLOR := Color(1.0, 0.78, 0.25)


func _ready() -> void:
	add_to_group(GROUP)
	if item is GearDefinition:
		add_to_group(Interactor.GROUP)
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	add_child(shape)
	_visual = _build_visual()
	add_child(_visual)


## Starts the pop: from `from` (world) with `launch_velocity`, landing at
## height `floor_y`. Call after it is in the tree.
func launch(from: Vector3, launch_velocity: Vector3, floor_y: float) -> void:
	global_position = from
	_floor_y = floor_y
	velocity = launch_velocity
	_airborne = true


## Seconds a pop launched at `vertical_speed` from `height` above the floor
## stays in the air (before its bounce).
static func flight_time(vertical_speed: float, height: float) -> float:
	return (vertical_speed + sqrt(vertical_speed * vertical_speed + 2.0 * _GRAVITY * height)) / _GRAVITY


func _physics_process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	_visual.rotation.y += delta * 4.0
	if _airborne:
		velocity.y -= _GRAVITY * delta
		global_position += velocity * delta
		if global_position.y <= _floor_y and velocity.y < 0.0:
			global_position.y = _floor_y
			if velocity.y < -2.0:
				velocity = Vector3(velocity.x * 0.4, -velocity.y * 0.3, velocity.z * 0.4)  # One small bounce.
			else:
				_airborne = false
				velocity = Vector3.ZERO
	else:
		_visual.position.y = 0.25 + sin(_age * 3.0) * 0.05
	if item and item.auto_collect and _age >= collect_delay:
		_update_magnet(delta)


func _update_magnet(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or ("is_dead" in player and player.is_dead):
		_magnet_time = 0.0
		return
	var target := player.global_position + Vector3.UP * 0.9
	var offset := target - global_position
	var flat := Vector2(offset.x, offset.z).length()
	if _magnet_time == 0.0 and flat > magnet_radius:
		return
	_magnet_time += delta
	_airborne = false
	var speed := lerpf(magnet_speed.x, magnet_speed.y, clampf(_magnet_time / 0.6, 0.0, 1.0))
	var step := minf(speed * delta, offset.length())
	global_position += offset.normalized() * step
	if (target - global_position).length() <= collect_radius:
		collect(player)


## Interactable (gear): can be picked up once it has landed.
func can_interact() -> bool:
	return item is GearDefinition and not _collected and not _airborne and _age >= collect_delay


func interact_prompt() -> String:
	var gear := item as GearDefinition
	var stats := gear.describe_modifiers() if gear else ""
	return "Take %s%s" % [item.display_name, " (%s)" % stats if stats != "" else ""]


func interact_animation() -> StringName:
	return &"PickUp_Table"


func interact(by: Node3D) -> void:
	collect(by)


## Hands the item to `collector` and removes it: gold goes to the profile,
## gear into an empty slot of the collector's `equipment`, else into its
## `inventory`. Returns false (and the item stays) when gear has nowhere to
## go: the HUD shows "Bag full".
func collect(collector: Node3D) -> bool:
	if _collected:
		return false
	if item is GearDefinition and not _take_gear(collector):
		get_tree().call_group(HUD.GROUP, &"notify", "Bag full")
		return false
	_collected = true
	if item and item.kind == ItemDefinition.Kind.CURRENCY:
		var profile := PlayerProfile.current()
		if profile:
			profile.add_gold(amount)
	_play_sound()
	collected.emit(self, collector)
	queue_free()
	return true


## Equips the gear into an empty slot it fits, else bags it.
func _take_gear(collector: Node3D) -> bool:
	if collector == null:
		return false
	var gear := item as GearDefinition
	var equipment := collector.get(&"equipment") as Equipment
	if equipment:
		for slot: StringName in Equipment.slots_for(gear):
			if equipment.get_item(slot) == null:
				equipment.equip(gear, slot)
				return true
	var inventory := collector.get(&"inventory") as Inventory
	return inventory != null and inventory.add(gear)


func _play_sound() -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = PlaceholderSfx.coin()
	sound.volume_db = -6.0
	get_parent().add_child(sound)
	sound.global_position = global_position
	sound.finished.connect(sound.queue_free)
	sound.play()


## A gold coin for currency; a placeholder glowing sack for anything else
## (gear gets its own models with the equipment step).
func _build_visual() -> Node3D:
	var holder := Node3D.new()
	holder.position.y = 0.25
	if item == null or item.kind != ItemDefinition.Kind.CURRENCY:
		var sack := SphereMesh.new()
		sack.radius = 0.2
		sack.height = 0.34
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color(0.55, 0.42, 0.28)
		cloth.emission_enabled = true
		cloth.emission = Color(0.6, 0.5, 1.0)
		cloth.emission_energy_multiplier = 0.4
		sack.material = cloth
		var bag := MeshInstance3D.new()
		bag.mesh = sack
		holder.add_child(bag)
		return holder
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.15
	mesh.height = 0.04
	mesh.radial_segments = 16
	var material := StandardMaterial3D.new()
	material.albedo_color = _COIN_COLOR
	material.metallic = 0.85
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = _COIN_COLOR
	material.emission_energy_multiplier = 0.6
	mesh.material = material
	var coin := MeshInstance3D.new()
	coin.mesh = mesh
	coin.rotation.x = PI * 0.5  # Stand it on its edge so the spin shows its face.
	coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(coin)
	return holder
