extends SceneTree
## Headless fog of war checks on a generated level in the real Main scene:
## the inverse warp, the lit circle around the player (not whole rooms) and
## what stays explored after moving, the mask the shader reads (floor and
## wall texels), line of sight blocked by walls in rooms and corridors, the
## soft falloff, enemies hidden outside sight, the debug toggle, and a new
## level starting unexplored.
##   godot --headless --path . -s res://tests/fog_test.gd
## Exit code 0 = every check passed.

var failures: int = 0


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_inverse_warp()
	var main: Node3D = load("res://scenes/main/main.tscn").instantiate()
	main.start_run_on_ready = false
	root.add_child(main)
	await process_frame
	var layout: DungeonLayout = await main.generate_level(12345, 2)
	await ticks(5)
	var fog := main.get_node("FogOfWar") as FogOfWar
	test_start(main, fog, layout)
	await test_moving(main, fog, layout)
	await test_sight_blocked_by_walls(main, fog, layout)
	test_soft_edges(fog)
	test_enemies(main, fog)
	await test_toggle(main, fog)
	await test_new_level(main, fog)
	main.queue_free()
	await ticks(2)
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_inverse_warp() -> void:
	print("1. to_cell() inverts to_world() on a curved level")
	var layout := LevelGenerator.new().generate(777, 3)
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		var cell := Vector2(rng.randf_range(-20, 40), rng.randf_range(-20, 40))
		var back := layout.to_cell(layout.to_world(cell, DungeonBuilder.CELL, 1.5), DungeonBuilder.CELL)
		worst = maxf(worst, back.distance_to(cell))
	check(layout.curvature > 0.0 and worst < 0.001, "round trip error %.6f cells" % worst)


func test_start(main: Node3D, fog: FogOfWar, layout: DungeonLayout) -> void:
	print("2. At the start: a circle around the player is lit, not the whole room")
	var here := fog.cell_at(main.player.global_position)
	check(fog.visible_cells.has(here) and fog.explored.has(here) and _mask_at(fog, here) == Vector2(1, 1),
		"the player's cell is lit and explored")
	var viewer: Vector2 = fog.get("_viewer")
	var beyond := fog.visible_cells.keys().filter(func(c: Vector2i) -> bool:
		return (Vector2(c) + Vector2(0.5, 0.5)).distance_to(viewer) > fog.sight_fade + 0.75)
	check(beyond.is_empty(), "nothing lit beyond %.0f m (%d cells)" % [fog.sight_fade * DungeonBuilder.CELL, beyond.size()])
	var start := _start_room(layout)
	var cells: Array = layout.rooms[start]["cells"]
	var dark_in_room := cells.filter(func(c: Vector2i) -> bool:
		return fog.light_at(Vector2(c) + Vector2(0.5, 0.5)) < 0.05)
	check(not dark_in_room.is_empty(), "the start room is not lit as a whole (%d of %d cells dark)"
		% [dark_in_room.size(), cells.size()])
	var far := _farthest_room(layout, start)
	check(not fog.explored.has(layout.room_centre(far)), "room %d (farthest) unexplored" % far)
	check(_mask_at(fog, layout.room_centre(far)) == Vector2(0, 0), "mask: far room black")
	var quad := fog.get("_quad") as MeshInstance3D
	check(quad.is_inside_tree() and quad.visible and quad.get_parent() is Camera3D, "the fog quad is on the camera")
	var lit_wall := false
	for cell: Vector2i in fog.visible_cells:
		for texel: int in fog.get("_outer_texels").get(cell, PackedInt32Array()):
			var w := fog.mask.get_width()
			lit_wall = lit_wall or fog.mask.get_pixel(texel % w, texel / w).g > 0.5
	check(lit_wall, "the walls next to lit floor are lit too")


func test_moving(main: Node3D, fog: FogOfWar, layout: DungeonLayout) -> void:
	print("3. Moving: the new place lights up, where the player was dims")
	var was := fog.cell_at(main.player.global_position)
	var start := _start_room(layout)
	var next := _farthest_room(layout, start)
	var centre := layout.room_centre(next)
	main.player.global_position = layout.to_world(Vector2(centre) + Vector2(0.5, 0.5), DungeonBuilder.CELL, 0.1)
	await ticks(3)
	for i in 3:
		await process_frame  # The fog follows the player in _process().
	check(fog.visible_cells.has(centre) and _mask_at(fog, centre) == Vector2(1, 1), "room %d's centre lit" % next)
	check(fog.explored.has(was) and not fog.visible_cells.has(was) and _mask_at(fog, was) == Vector2(1, 0),
		"where the player started: explored, not lit (dim)")


func test_sight_blocked_by_walls(main: Node3D, fog: FogOfWar, layout: DungeonLayout) -> void:
	print("4. Line of sight: walls block it, in rooms and corridors alike")
	var walls := 0
	for a: Vector2i in layout.floor_cells:
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var b := a + step
			if not layout.floor_cells.has(b) or layout.can_step(a, b):
				continue
			if fog.call("_line_of_sight", Vector2(a) + Vector2(0.5, 0.5), Vector2(b) + Vector2(0.5, 0.5)):
				walls += 1
	check(walls == 0, "no line of sight crosses an interior wall (%d)" % walls)
	# In a corridor: two cells out of the start room's first doorway.
	var start := _start_room(layout)
	var door: Dictionary = layout.room_entries(start)[0]
	var outside: Vector2i = (door["cells"][0] as Vector2i) - (door["inward"] as Vector2i) * 2
	main.player.global_position = layout.to_world(Vector2(outside) + Vector2(0.5, 0.5), DungeonBuilder.CELL, 0.1)
	await ticks(3)
	for i in 3:
		await process_frame
	var viewer: Vector2 = fog.get("_viewer")
	check(fog.visible_cells.has(outside), "the corridor cell the player stands on is lit")
	var hidden_near := 0
	for cell: Vector2i in layout.floor_cells:
		var centre := Vector2(cell) + Vector2(0.5, 0.5)
		if centre.distance_to(viewer) < fog.sight_fade and not fog.visible_cells.has(cell):
			hidden_near += 1
	check(hidden_near > 0, "%d floor cells within %.0f m are hidden behind walls"
		% [hidden_near, fog.sight_fade * DungeonBuilder.CELL])


func test_soft_edges(fog: FogOfWar) -> void:
	print("5. The light fades smoothly with distance; explored edges are soft")
	var falloff: Array[float] = []
	for d in [1.0, fog.sight_radius, (fog.sight_radius + fog.sight_fade) * 0.5, fog.sight_fade, fog.sight_fade + 1.0]:
		falloff.append(fog.call("_falloff", d))
	check(falloff[0] == 1.0 and falloff[1] == 1.0 and falloff[2] > 0.2 and falloff[2] < 0.8
		and falloff[3] == 0.0 and falloff[4] == 0.0, "full to %.0f cells, fading, gone at %.0f (%s)"
		% [fog.sight_radius, fog.sight_fade, falloff])
	var partial := 0
	var data: PackedByteArray = fog.mask.get_data()
	for i in range(0, data.size(), 4):
		if data[i] > 20 and data[i] < 235:
			partial += 1
	check(partial > 50, "%d mask texels are partly explored (soft edges, not cell blocks)" % partial)


func test_enemies(main: Node3D, fog: FogOfWar) -> void:
	print("6. Enemies show only in sight")
	fog.refresh()
	var shown := 0
	var hidden := 0
	var wrong := 0
	for enemy: Node3D in main.enemies.get_children():
		var seen := fog.is_enemy_visible_at(enemy.global_position)
		if enemy.visible != seen:
			wrong += 1
		if enemy.visible:
			shown += 1
		else:
			hidden += 1
	check(wrong == 0 and hidden > 0, "%d shown, %d hidden, %d wrong" % [shown, hidden, wrong])


func test_toggle(main: Node3D, fog: FogOfWar) -> void:
	print("7. The debug menu's Fog of war checkbox")
	var menu := main.get_node("DebugMenu") as DebugMenu
	var check_box := menu.get_node("%FogCheck") as CheckBox
	check(check_box.button_pressed, "the checkbox starts on")
	check_box.toggled.emit(false)
	await ticks(2)
	var quad := fog.get("_quad") as MeshInstance3D
	check(not fog.enabled and not quad.visible, "off: no darkening")
	check(main.enemies.get_children().all(func(e: Node3D) -> bool: return e.visible), "off: every enemy shown")
	check_box.toggled.emit(true)
	await ticks(2)
	check(fog.enabled and quad.visible and main.enemies.get_children().any(func(e: Node3D) -> bool: return not e.visible),
		"back on: dark again, far enemies hidden")


func test_new_level(main: Node3D, fog: FogOfWar) -> void:
	print("8. A new level starts unexplored")
	var before := fog.explored.size()
	var layout: DungeonLayout = await main.generate_level(999, 1)
	await ticks(3)
	check(fog.layout == layout and fog.explored.size() < before + 1
		and fog.explored.size() <= fog.visible_cells.size(), "only what is visible now is explored (%d)" % fog.explored.size())
	check(fog.visible_cells.has(fog.cell_at(main.player.global_position)), "the player's new spot is lit")


func _start_room(layout: DungeonLayout) -> int:
	for i in layout.rooms.size():
		if layout.rooms[i]["role"] == "start":
			return i
	return 0


func _farthest_room(layout: DungeonLayout, from: int) -> int:
	var steps := layout.walk_distances(layout.room_centre(from))
	var best := from
	for i in layout.rooms.size():
		if steps.get(layout.room_centre(i), -1) > steps.get(layout.room_centre(best), -1):
			best = i
	return best


## Mask state (explored, visible) at the middle of a cell.
func _mask_at(fog: FogOfWar, cell: Vector2i) -> Vector2:
	var origin: Vector2i = fog.get("_mask_cell_origin")
	var texel := (cell - origin) * FogOfWar.TEXELS_PER_CELL + Vector2i.ONE * (FogOfWar.TEXELS_PER_CELL / 2)
	var colour := fog.mask.get_pixelv(texel)
	return Vector2(roundf(colour.r), roundf(colour.g))


func ticks(n: int) -> void:
	for i in n:
		await physics_frame
