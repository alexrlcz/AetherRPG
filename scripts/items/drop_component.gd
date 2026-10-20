class_name DropComponent
extends Node
## Drops loot where its owner dies: rolls `loot` for `level` and throws it
## out in a ring (LootSpawner). Rolls use `rng_seed` (Main seeds it from the
## level so a level always drops the same; 0 = random).
##
## Pickups go into the first node of group CONTAINER_GROUP (the current
## level, freed with it), else next to the owner.

const CONTAINER_GROUP := &"drop_container"

@export var health: HealthComponent
@export var loot: LootTable
## Run level the drop is rolled for (amounts can grow per level).
@export var level: int = 1
## Height (m) above the owner's origin the loot pops out from.
@export var drop_height: float = 1.0
## Physics layers that stop a throw (world).
@export_flags_3d_physics var wall_mask: int = 1

var rng_seed: int = 0


func _ready() -> void:
	if health:
		health.died.connect(drop)


## Drops the loot now (normally on death). Returns the pickups.
func drop() -> Array[Pickup]:
	var body := get_parent() as Node3D
	if loot == null or body == null or not body.is_inside_tree():
		return []
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	var container := get_tree().get_first_node_in_group(CONTAINER_GROUP)
	if container == null:
		container = body.get_parent()
	return LootSpawner.spawn(loot.roll(rng, level), body.global_position + Vector3.UP * drop_height,
		body.global_position.y, container, rng, Vector3.ZERO, PI, wall_mask)
