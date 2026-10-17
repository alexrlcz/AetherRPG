extends SceneTree
## Headless checks of the seeded level generator (step 2 of procedural
## levels): determinism, a sweep of seeds for valid layouts, real builds with
## navmesh paths to every room, and the debug "generate level" path in Main.
##   godot --headless --path . -s res://tests/level_generator_test.gd
## Exit code 0 = every check passed.

const MAIN := preload("res://scenes/main/main.tscn")
const SWEEP := 300
const PARITY_SEEDS := 60
const BUILD_SEEDS := 15

var failures: int = 0


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	test_determinism()
	test_sweep()
	test_outline_matches_cells()
	await test_builds_and_paths()
	await test_main_generate()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_determinism() -> void:
	print("1. The same seed gives the same level; different seeds differ")
	var a := LevelGenerator.new().generate(1234)
	var b := LevelGenerator.new().generate(1234)
	var c := LevelGenerator.new().generate(1235)
	check(_signature(a) == _signature(b), "seed 1234 twice: identical layouts")
	check(_signature(a) != _signature(c), "seeds 1234 and 1235 differ")
	check(a.seed == 1234, "layout records its seed")


func test_sweep() -> void:
	print("2. %d seeds: every layout is complete, connected and non-overlapping" % SWEEP)
	var generator := LevelGenerator.new()
	var bad := {}
	var room_counts := []
	var loops := 0
	var t0 := Time.get_ticks_usec()
	for s in range(1, SWEEP + 1):
		var layout := generator.generate(s)
		if layout == null:
			bad[s] = "no layout"
			continue
		var problem := _validate(layout, generator)
		if problem != "":
			bad[s] = problem
		room_counts.append(layout.rooms.size())
		if layout.corridors.size() >= layout.rooms.size():
			loops += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / SWEEP
	check(bad.is_empty(), "all valid (%d bad: %s)" % [bad.size(), str(bad).left(300)])
	room_counts.sort()
	print("     rooms per level %d..%d, levels with a loop %d / %d, %.2f ms per layout" % [
		room_counts[0], room_counts[-1], loops, SWEEP, ms])
	check(loops > 0, "some levels have a loop")
	check(room_counts[-1] > room_counts[0], "room counts vary with branches")


func test_outline_matches_cells() -> void:
	print("3. The traced outline is exactly the generated floor (%d seeds)" % PARITY_SEEDS)
	var mismatches := 0
	var checked := 0
	for s in range(1, PARITY_SEEDS + 1):
		var layout := LevelGenerator.new().generate(s)
		var cells := _cells(layout)
		var bounds := layout.bounds().grow(1)
		for y in range(int(bounds.position.y), int(bounds.end.y)):
			for x in range(int(bounds.position.x), int(bounds.end.x)):
				checked += 1
				if layout.is_floor(Vector2(x + 0.5, y + 0.5)) != cells.has(Vector2i(x, y)):
					mismatches += 1
	check(mismatches == 0, "%d cells checked, %d mismatches" % [checked, mismatches])


func test_builds_and_paths() -> void:
	print("4. %d seeds built and baked: Start reaches Exit and every room" % BUILD_SEEDS)
	var worst := 0.0
	var unreachable := []
	for s in range(1, BUILD_SEEDS + 1):
		var layout := LevelGenerator.new().generate(s * 7919)
		var level := DungeonLevel.new()
		root.add_child(level)
		level.build(layout, "Level")
		await level.navigation_ready
		worst = maxf(worst, level.total_seconds)
		var map := level.get_world_3d().navigation_map
		var from := level.get_marker("Start").global_position + Vector3.UP * 0.5
		var targets: Array[Vector3] = [level.get_marker("Exit").global_position]
		for room in layout.rooms:
			var r: Rect2i = room["rect"]
			targets.append(layout.to_world(Vector2(r.position) + Vector2(r.size) * 0.5, DungeonBuilder.CELL))
		for to in targets:
			var goal := to + Vector3.UP * 0.5
			var path := NavigationServer3D.map_get_path(map, from, goal, true)
			if path.is_empty() or path[-1].distance_to(goal) > 0.6:
				unreachable.append([s * 7919, to])
		level.queue_free()
		await process_frame
	check(unreachable.is_empty(), "every room reachable (%d unreachable: %s)" % [unreachable.size(), str(unreachable).left(200)])
	check(worst < 2.0, "slowest build + bake %.3f s (target < 2 s)" % worst)


func test_main_generate() -> void:
	print("5. Main.generate_level() swaps in a generated level and moves the player")
	var main: Node3D = MAIN.instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	var player := main.get_node("Player") as PlayerController
	var old_dungeon: Node = main.get_node("Dungeon")
	var layout: DungeonLayout = await main.generate_level(4242)
	for i in 5:
		await physics_frame
	var level := main.get_node("Dungeon") as DungeonLevel
	check(layout != null and level != null and level != old_dungeon, "the dungeon was replaced")
	check(not is_instance_valid(old_dungeon) or old_dungeon.is_queued_for_deletion() or not old_dungeon.is_inside_tree(),
		"the old dungeon is gone")
	var alive := main.get_node("Enemies").get_children().filter(func(e: Node) -> bool:
		return not e.is_queued_for_deletion())
	check(alive.size() == layout.spawns.size() and alive.size() > 0,
		"the old knights replaced by the level's %d planned enemies (%d)" % [layout.spawns.size(), alive.size()])
	var start := level.get_marker("Start").global_position
	check(EnemyController._flat(player.global_position - start).length() < 0.5 and player.is_on_floor(),
		"player stands at Start (%.2f m off, on floor %s)" % [
			EnemyController._flat(player.global_position - start).length(), player.is_on_floor()])
	var map := level.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, player.global_position + Vector3.UP * 0.5,
		level.get_marker("Exit").global_position + Vector3.UP * 0.5, true)
	check(path.size() > 1, "the player has a path to the Exit (%d points)" % path.size())
	main.queue_free()
	await process_frame


## "" when the layout is valid, else what is wrong.
func _validate(layout: DungeonLayout, generator: LevelGenerator) -> String:
	var main_path := layout.rooms.filter(func(r: Dictionary) -> bool: return r["role"] != "side")
	if main_path.size() != generator.main_rooms:
		return "main path has %d rooms" % main_path.size()
	if layout.rooms[0]["role"] != "start" or main_path[-1]["role"] != "exit":
		return "start / exit roles"
	# Unconnected rooms and corridors keep `gap` empty cells between them.
	var rects := []
	for r in layout.rooms:
		rects.append(r["rect"])
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2i).grow(generator.gap).intersects(rects[j]):
				return "rooms %d and %d too close" % [i, j]
	# Each corridor touches exactly its two rooms.
	for c in layout.corridors:
		var cr: Rect2i = c["rect"]
		for k in [c["from"], c["to"]]:
			if not cr.grow(1).intersects(rects[k]):
				return "corridor does not reach room %d" % k
	# Every floor cell is reachable from the start room.
	var cells := _cells(layout)
	var start := Vector2i((rects[0] as Rect2i).position)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if cells.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	if seen.size() != cells.size():
		return "%d of %d cells unreachable" % [cells.size() - seen.size(), cells.size()]
	for label in layout.labels:
		if not layout.is_floor(label[1]):
			return "label %s off the floor" % label[0]
	return ""


func _cells(layout: DungeonLayout) -> Dictionary:
	var cells := {}
	for r in layout.rooms + layout.corridors:
		var rect: Rect2i = r["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells


func _signature(layout: DungeonLayout) -> String:
	var spawns := layout.spawns.map(func(s: Dictionary) -> Array:
		return [s["cell"], s["room"], s["entry"].resource_path, s["yaw"]])
	return var_to_str([layout.floor_rings, layout.rooms, layout.corridors, layout.doors, layout.labels,
		layout.props, spawns])
