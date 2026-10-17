class_name DungeonLevel
extends Node3D
## A level built at runtime: build(layout) makes the geometry with
## DungeonBuilder, bakes the navmesh on a background thread, then emits
## `navigation_ready`. Until then agents have no navmesh: spawn enemies and
## start the level only after the signal (a loading screen covers the wait).

## The navmesh is baked and the navigation map uses it; the level is playable.
signal navigation_ready

## Physics frames to wait for the navigation map to take in a new navmesh
## before giving up waiting (it takes a few).
const MAP_SYNC_MAX_FRAMES := 120

## The built level (child of this node), or null before build().
var level: Node3D
## Seconds the last build took: geometry, and geometry + navmesh bake.
var build_seconds: float = 0.0
var total_seconds: float = 0.0

var _nav_ready: bool = false
var _started_usec: int = 0


## Replaces any previous level with `layout` and starts baking its navmesh.
## Must be in the scene tree.
func build(layout: DungeonLayout, level_name: String = "Dungeon") -> void:
	if level:
		remove_child(level)
		level.queue_free()
	_nav_ready = false
	_started_usec = Time.get_ticks_usec()
	level = DungeonBuilder.new().build(layout, level_name)
	add_child(level)
	build_seconds = (Time.get_ticks_usec() - _started_usec) / 1e6
	var nav := level.get_node("NavigationRegion3D") as NavigationRegion3D
	nav.bake_finished.connect(_on_bake_finished, CONNECT_ONE_SHOT)
	DungeonBuilder.bake_navigation(level, true)


func is_navigation_ready() -> bool:
	return _nav_ready


## The level's Marker3D called `marker_name` (e.g. "Start"), or null.
func get_marker(marker_name: String) -> Marker3D:
	if level == null:
		return null
	return level.get_node_or_null("Markers/" + marker_name) as Marker3D


func _on_bake_finished() -> void:
	# The region has its navmesh, but the navigation map takes it in on a
	# later (background) sync, a few physics frames on: until then path
	# queries return nothing, or still see a level this one replaced. Wait
	# until the map's closest point to the new navmesh belongs to this
	# level's region before calling the level playable.
	var nav := level.get_node("NavigationRegion3D") as NavigationRegion3D
	var vertices := nav.navigation_mesh.get_vertices()
	if not vertices.is_empty():
		var probe := nav.global_transform * vertices[0]
		var map := get_world_3d().navigation_map
		for i in MAP_SYNC_MAX_FRAMES:
			# Queries before the map's first sync are errors, not answers.
			if NavigationServer3D.map_get_iteration_id(map) > 0 \
					and NavigationServer3D.map_get_closest_point_owner(map, probe) == nav.get_rid():
				break
			await get_tree().physics_frame
			if not is_inside_tree():
				return
	total_seconds = (Time.get_ticks_usec() - _started_usec) / 1e6
	_nav_ready = true
	navigation_ready.emit()
