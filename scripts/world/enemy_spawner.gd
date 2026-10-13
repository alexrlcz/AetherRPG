class_name EnemySpawner
extends Node
## Spawns enemy scenes at random walkable points on the navigation map.
## Used by the debug menu now; intended for real spawn logic later.

signal enemy_spawned(enemy: Node3D)

@export var enemy_scene: PackedScene
## Spawned enemies are added here.
@export var container: Node3D
## Keep spawns at least `min_distance` away from this node (usually the player).
@export var avoid: Node3D
@export var min_distance: float = 6.0
## Navmesh points higher than this are rejected (tops of rocks/pillars).
@export var max_spawn_height: float = 0.75
@export var max_attempts: int = 30


## Spawns one enemy; returns it, or null if no valid point was found.
func spawn_random() -> Node3D:
	var point: Variant = find_spawn_point()
	if point == null:
		push_warning("EnemySpawner: no valid spawn point found")
		return null
	var enemy := enemy_scene.instantiate() as Node3D
	# Set the transform before add_child: enemies record their home (spawn
	# point) and facing in _ready(). Face a random direction.
	enemy.position = container.to_local(point)
	enemy.rotation.y = randf() * TAU
	container.add_child(enemy)
	enemy_spawned.emit(enemy)
	return enemy


## Returns a random ground-level navmesh point (Vector3) or null.
func find_spawn_point() -> Variant:
	var map := container.get_world_3d().navigation_map
	for i in max_attempts:
		var p := NavigationServer3D.map_get_random_point(map, 1, true)
		if p.y > max_spawn_height:
			continue
		if avoid and Vector2(p.x - avoid.global_position.x, p.z - avoid.global_position.z).length() < min_distance:
			continue
		# The navmesh floats ~0.5 m above the floor; spawn on the floor.
		return Vector3(p.x, 0.0, p.z)
	return null
