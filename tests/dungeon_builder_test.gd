extends SceneTree
## Headless checks of the runtime dungeon builder (step 1 of level generation):
## the runtime build of dungeon_01 matches the saved scene, the navmesh bakes
## on a thread and connects the level, and a layout made in code builds.
##   godot --headless --path . -s res://tests/dungeon_builder_test.gd
## Exit code 0 = every check passed.

const SAVED := preload("res://scenes/world/dungeon_01.tscn")
const SAVED_NAVMESH := preload("res://resources/navigation/dungeon_01_navmesh.tres")

var failures: int = 0


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	await test_matches_saved_scene()
	await test_runtime_bake()
	await test_layout_with_hole()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_matches_saved_scene() -> void:
	print("1. The runtime build of dungeon_01 matches the saved scene")
	var saved: Node3D = SAVED.instantiate()
	root.add_child(saved)
	var built := DungeonBuilder.new().build(Dungeon01Layout.create(), "Dungeon01")
	root.add_child(built)
	await process_frame
	var a := _shapes(saved)
	var b := _shapes(built)
	check(a.size() == b.size() and a.size() > 100, "%d collision shapes each (saved %d)" % [b.size(), a.size()])
	var mismatched := 0
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			mismatched += 1
	check(mismatched == 0, "every shape has the same size and place (%d differ)" % mismatched)
	for group in ["Torches", "Doors/", "NavigationRegion3D/Props", "Decor", "Hazards"]:
		var path: String = group.trim_suffix("/")
		check(saved.get_node(path).get_child_count() == built.get_node(path).get_child_count(),
			"%s: %d" % [path, built.get_node(path).get_child_count()])
	for marker in ["Start", "BossRoom"]:
		var p1: Vector3 = saved.get_node("Markers/" + marker).position
		var p2: Vector3 = built.get_node("Markers/" + marker).position
		check(p1.is_equal_approx(p2), "marker %s at %s" % [marker, p2])
	saved.queue_free()
	built.queue_free()
	await process_frame


func test_runtime_bake() -> void:
	print("2. The navmesh bakes at runtime on a thread and connects the level")
	var holder := DungeonLevel.new()
	root.add_child(holder)
	var signalled := [false]
	holder.navigation_ready.connect(func() -> void: signalled[0] = true)
	holder.build(Dungeon01Layout.create(), "Dungeon01")
	check(not holder.is_navigation_ready(), "build() returns before the bake finishes")
	var frames := 0
	while not signalled[0] and frames < 600:
		await process_frame
		frames += 1
	check(signalled[0] and holder.is_navigation_ready(), "navigation_ready emitted")
	print("     geometry %.3f s, geometry + navmesh %.3f s" % [holder.build_seconds, holder.total_seconds])
	check(holder.total_seconds < 2.0, "built and baked in %.2f s (target < 2 s)" % holder.total_seconds)
	var navmesh := (holder.level.get_node("NavigationRegion3D") as NavigationRegion3D).navigation_mesh
	check(navmesh.get_polygon_count() == SAVED_NAVMESH.get_polygon_count(),
		"%d polygons, same as the saved navmesh" % navmesh.get_polygon_count())
	# No extra wait: navigation_ready promises the map is already synced.
	var map := holder.get_world_3d().navigation_map
	var from := holder.get_marker("Start").global_position + Vector3.UP * 0.5
	var to := holder.get_marker("BossRoom").global_position + Vector3.UP * 0.5
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var end_gap := path[-1].distance_to(to) if path.size() > 0 else INF
	check(path.size() > 2 and end_gap < 0.5, "a path leads from Start to BossRoom (%d points, ends %.2f m away)" % [path.size(), end_gap])
	holder.queue_free()
	await process_frame


func test_layout_with_hole() -> void:
	print("3. A layout made in code (a ring of floor around a hole) builds and bakes")
	var layout := DungeonLayout.new()
	layout.floor_rings.append(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]))
	layout.floor_rings.append(PackedVector2Array([Vector2(4, 4), Vector2(6, 4), Vector2(6, 6), Vector2(4, 6)]))
	layout.labels = [["West", Vector2(1, 5)], ["East", Vector2(9, 5)]]
	layout.props = [["crate", 2.0, 2.0, 0]]
	layout.centre_origin()
	check(layout.is_floor(Vector2(1, 1)) and not layout.is_floor(Vector2(5, 5)) and not layout.is_floor(Vector2(11, 5)),
		"floor around the hole, none inside or outside")
	var holder := DungeonLevel.new()
	root.add_child(holder)
	holder.build(layout, "Ring")
	var frames := 0
	while not holder.is_navigation_ready() and frames < 600:
		await process_frame
		frames += 1
	check(holder.is_navigation_ready(), "baked")
	var area := 0.0
	for shape in _shapes(holder.level.get_node("NavigationRegion3D/Floor")):
		area += shape[1].x * shape[1].z
	check(is_equal_approx(area, 96.0 * 4.0), "floor covers 96 cells (%.0f m²)" % area)
	# No extra wait: navigation_ready promises the map is already synced.
	var map := holder.get_world_3d().navigation_map
	var from := holder.get_marker("West").global_position + Vector3.UP * 0.5
	var to := holder.get_marker("East").global_position + Vector3.UP * 0.5
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	check(path.size() > 2 and length > from.distance_to(to) + 0.5,
		"the path goes around the hole (%.1f m vs %.1f m straight)" % [length, from.distance_to(to)])
	holder.queue_free()
	await process_frame


## [global origin, size] of every box / cylinder collision shape under `node`,
## rounded and sorted, so two builds compare independent of node order.
func _shapes(node: Node) -> Array:
	var result := []
	for cs: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
		var size := Vector3.ZERO
		if cs.shape is BoxShape3D:
			size = (cs.shape as BoxShape3D).size
		elif cs.shape is CylinderShape3D:
			var c := cs.shape as CylinderShape3D
			size = Vector3(c.radius, c.height, c.radius)
		var xf := cs.global_transform
		result.append([xf.origin.snapped(Vector3.ONE * 0.001), size.snapped(Vector3.ONE * 0.001),
			xf.basis.get_euler().snapped(Vector3.ONE * 0.001)])
	result.sort_custom(func(p, q) -> bool: return str(p) < str(q))
	return result
