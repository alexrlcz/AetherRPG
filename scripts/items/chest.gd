class_name Chest
extends StaticBody3D
## A treasure chest prop that can be opened once with the interact key
## (Interactor): the lid swings back and `loot` (rolled for `level`) is
## thrown out of the front (LootSpawner). DungeonBuilder builds its meshes
## (the lid under `lid_pivot`, hinged at the back) and sets `level` and
## `rng_seed` from the layout, so a level's chests always hold the same.
##
## Interactable: in group Interactor.GROUP, with can_interact(),
## interact_prompt(), interact_animation() and interact(by).

signal opened(by: Node3D)

@export var loot: LootTable = preload("res://resources/loot/chest.tres")
## Run level the loot is rolled for.
@export var level: int = 1
## The lid's hinge (rotated about its local X to open).
@export var lid_pivot: Node3D
## Seconds after interact() before the lid starts to swing / the loot flies
## (timed to the opener's animation: hands reach the lid, then lift).
@export var lid_delay: float = 0.3
@export var loot_delay: float = 0.7
@export var open_angle_degrees: float = 105.0

var rng_seed: int = 0
var is_open: bool = false


func _ready() -> void:
	add_to_group(Interactor.GROUP)


func can_interact() -> bool:
	return not is_open


func interact_prompt() -> String:
	return "Open chest"


## The opener plays this (Interactor).
func interact_animation() -> StringName:
	return &"UAL2/Chest_Open"


## Opens the chest (once): lid, then loot.
func interact(by: Node3D) -> void:
	if is_open:
		return
	is_open = true
	remove_from_group(Interactor.GROUP)
	opened.emit(by)
	var tween := create_tween()
	if lid_pivot:
		tween.tween_interval(lid_delay)
		tween.tween_property(lid_pivot, "rotation:x", -deg_to_rad(open_angle_degrees), 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(loot_delay - lid_delay - 0.35, 0.0))
	tween.tween_callback(spill_loot)


## Throws the loot out of the front now. Returns the pickups.
func spill_loot() -> Array[Pickup]:
	if loot == null or not is_inside_tree():
		return []
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	var front := global_basis.z  # The lock side (local +Z).
	front.y = 0.0
	front = front.normalized()
	var container := get_tree().get_first_node_in_group(DropComponent.CONTAINER_GROUP)
	if container == null:
		container = get_parent()
	return LootSpawner.spawn(loot.roll(rng, level), global_position + Vector3.UP * 0.7 + front * 0.35,
		global_position.y, container, rng, front, deg_to_rad(55.0))
