extends SceneTree
## Headless checks of level population (step 3 of procedural levels): props
## keep the routes clear and stay inside their rooms, enemies follow the
## budget and placement rules, and in real builds every enemy stands on the
## navmesh and stays put.
##   godot --headless --path . -s res://tests/population_test.gd
## Exit code 0 = every check passed.

const MAIN := preload("res://scenes/main/main.tscn")
const ROSTER := preload("res://resources/encounters/knights.tres")
const GREATSWORD_KNIGHT := preload("res://resources/encounters/greatsword_knight.tres")
const SWEEP := 200
## Footprint radius (cells) of each prop kind around its position.
const RADIUS := {"pillar": 0.28, "crate": 0.28, "barrel": 0.19, "table": 0.52, "chest": 0.3,
	"rubble": 0.4, "statue": 0.36, "brazier": 0.25, "campfire": 0.32, "bedroll": 0.48}

var failures: int = 0


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	test_props()
	test_enemies()
	await test_real_builds()
	await test_main_spawns()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_props() -> void:
	print("1. %d seeds: props stay in their rooms, off the routes, doors stay connected" % SWEEP)
	var bad := {}
	var total := 0
	var kinds := {}
	for s in range(1, SWEEP + 1):
		var layout := LevelGenerator.new().generate(s)
		total += layout.props.size()
		for p: Array in layout.props:
			kinds[p[0]] = kinds.get(p[0], 0) + 1
		for p: Array in layout.props:
			var pos := Vector2(p[1], p[2])
			var cell := Vector2i(floori(pos.x), floori(pos.y))
			var room := _room_at(layout, cell)
			if room < 0:
				bad[s] = "%s outside the rooms at %s" % [p[0], pos]
				break
			if layout.reserved_cells.has(cell):
				bad[s] = "%s on a route cell %s" % [p[0], cell]
				break
			var r: Rect2i = layout.rooms[room]["rect"]
			var radius: float = RADIUS[p[0]]
			if pos.x - radius < r.position.x - 0.02 or pos.x + radius > r.end.x + 0.02 \
					or pos.y - radius < r.position.y - 0.02 or pos.y + radius > r.end.y + 0.02:
				bad[s] = "%s pokes into a wall at %s" % [p[0], pos]
				break
		for i in layout.rooms.size():
			var sealed := _sealed_cells(layout, i)
			if sealed > 0:
				bad[s] = "room %d: %d free cells cut off from the doors" % [i, sealed]
				break
	check(bad.is_empty(), "all valid (%d bad: %s)" % [bad.size(), str(bad).left(300)])
	print("     %.1f props per level: %s" % [float(total) / SWEEP, kinds])
	check(kinds.size() >= 9, "%d prop kinds used" % kinds.size())


func test_enemies() -> void:
	print("2. Enemies follow the budget and the placement rules (levels 1, 3, 6)")
	var averages := {}
	for level in [1, 3, 6]:
		var bad := {}
		var count := 0
		var greatswords := 0
		for s in range(1, SWEEP + 1):
			var layout := LevelGenerator.new().generate(s, level)
			count += layout.spawns.size()
			var problem := _check_spawns(layout, level)
			if problem != "":
				bad[s] = problem
			for spawn in layout.spawns:
				if spawn["entry"] == GREATSWORD_KNIGHT:
					greatswords += 1
		averages[level] = float(count) / SWEEP
		check(bad.is_empty(), "level %d: all valid (%d bad: %s)" % [level, bad.size(), str(bad).left(240)])
		print("     level %d: %.1f enemies per level, %d greatsword knights in %d levels" % [
			level, averages[level], greatswords, SWEEP])
		if level < GREATSWORD_KNIGHT.min_level:
			check(greatswords == 0, "no greatsword knights before level %d" % GREATSWORD_KNIGHT.min_level)
		else:
			check(greatswords > 0, "greatsword knights from level %d" % GREATSWORD_KNIGHT.min_level)
	check(averages[1] < averages[3] and averages[3] < averages[6], "more enemies deeper (%s)" % averages)


func test_real_builds() -> void:
	print("3. Real builds: every enemy spawn is on the navmesh and reachable from Start")
	var off := []
	var spawns := 0
	for s in range(1, 9):
		var layout := LevelGenerator.new().generate(s * 104729, 4)
		var level := DungeonLevel.new()
		root.add_child(level)
		level.build(layout, "Level")
		await level.navigation_ready
		var map := level.get_world_3d().navigation_map
		var start := level.get_marker("Start").global_position + Vector3.UP * 0.5
		for spawn in layout.spawns:
			spawns += 1
			var at := layout.to_world(spawn["cell"], DungeonBuilder.CELL) + Vector3.UP * 0.5
			var near := NavigationServer3D.map_get_closest_point(map, at)
			var path := NavigationServer3D.map_get_path(map, start, at, true)
			var flat_gap := Vector2(near.x - at.x, near.z - at.z).length()
			if flat_gap > 0.3 or path.is_empty() or path[-1].distance_to(at) > 0.6:
				off.append([s * 104729, spawn["cell"], snappedf(flat_gap, 0.01)])
		level.queue_free()
		await process_frame
	check(off.is_empty(), "%d spawns checked, %d off the navmesh or unreachable %s" % [spawns, off.size(), str(off).left(200)])


func test_main_spawns() -> void:
	print("4. Main.generate_level() spawns the planned enemies, and they stay put")
	var main: Node3D = MAIN.instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	var layout: DungeonLayout = await main.generate_level(31337, 4)
	var enemies: Array = main.get_node("Enemies").get_children().filter(func(e: Node) -> bool:
		return not e.is_queued_for_deletion())
	check(enemies.size() == layout.spawns.size(), "%d spawned of %d planned" % [enemies.size(), layout.spawns.size()])
	var right_weapon := 0
	for i in mini(enemies.size(), layout.spawns.size()):
		var weapon := (enemies[i] as Node).get_node("Weapon") as WeaponComponent
		if weapon.current == (layout.spawns[i]["entry"] as EnemyEntry).weapon:
			right_weapon += 1
	check(right_weapon == layout.spawns.size(), "each wields its planned weapon (%d/%d)" % [right_weapon, layout.spawns.size()])
	var homes := enemies.map(func(e: Node3D) -> Vector3: return e.global_position)
	for i in 90:
		await physics_frame
	var moved := 0
	var airborne := 0
	var player := main.get_node("Player") as Node3D
	var nearest := INF
	for i in enemies.size():
		var e := enemies[i] as EnemyController
		if EnemyController._flat(e.global_position - homes[i]).length() > 0.3:
			moved += 1
		if not e.is_on_floor():
			airborne += 1
		nearest = minf(nearest, EnemyController._flat(e.global_position - player.global_position).length())
	check(moved == 0 and airborne == 0, "after 1.5 s none moved or fell (%d moved, %d airborne)" % [moved, airborne])
	check(nearest >= 11.9, "nearest enemy %.1f m from the player's start (>= 12 m)" % nearest)
	main.queue_free()
	await process_frame


## "" when the level's spawns follow the rules, else what is wrong.
func _check_spawns(layout: DungeonLayout, level: int) -> String:
	var seen := {}
	var per_room := {}
	var start := Vector2.INF
	for label in layout.labels:
		if label[0] == "Start":
			start = label[1]
	for spawn in layout.spawns:
		var p: Vector2 = spawn["cell"]
		var cell := Vector2i(floori(p.x), floori(p.y))
		var room: int = spawn["room"]
		var entry: EnemyEntry = spawn["entry"]
		if layout.rooms[room]["role"] == "start":
			return "enemy in the start room"
		if not (layout.rooms[room]["rect"] as Rect2i).has_point(cell):
			return "enemy outside its room"
		if seen.has(cell):
			return "two enemies on cell %s" % cell
		seen[cell] = true
		if layout.blocked_cells.has(cell):
			return "enemy on a prop at %s" % cell
		if entry.min_level > level:
			return "%s before its level" % entry.display_name
		if p.distance_to(start) < ROSTER.start_clearance - 0.75:
			return "enemy %.1f cells from the start" % p.distance_to(start)
		for e in layout.room_entries(room):
			for d: Vector2i in e["cells"]:
				if absi(cell.x - d.x) <= ROSTER.door_clearance and absi(cell.y - d.y) <= ROSTER.door_clearance:
					return "enemy at a doorway %s" % cell
		per_room[room] = per_room.get(room, 0) + entry.cost
	for room: int in per_room:
		var most := ROSTER.room_budget(layout.rooms[room]["role"], level) * (1.0 + ROSTER.budget_variance)
		if per_room[room] > most + 0.001:
			return "room %d spent %d of at most %.1f" % [room, per_room[room], most]
	return ""


func _room_at(layout: DungeonLayout, cell: Vector2i) -> int:
	for i in layout.rooms.size():
		if (layout.rooms[i]["rect"] as Rect2i).has_point(cell):
			return i
	return -1


## Free (prop-less) cells of room `index` that no doorway can reach.
func _sealed_cells(layout: DungeonLayout, index: int) -> int:
	var r: Rect2i = layout.rooms[index]["rect"]
	var free := {}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not layout.blocked_cells.has(Vector2i(x, y)):
				free[Vector2i(x, y)] = true
	var queue: Array[Vector2i] = []
	var seen := {}
	for e in layout.room_entries(index):
		for c: Vector2i in e["cells"]:
			if free.has(c) and not seen.has(c):
				seen[c] = true
				queue.append(c)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if free.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return free.size() - seen.size()
