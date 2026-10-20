extends SceneTree
## Headless checks of hand-made maps in the level pool (step 5 of procedural
## levels): room detection on dungeon_01, props and enemies by the same rules
## as generated levels, a real build with the exit gate, the pool's choice,
## and Main playing a map.
##   godot --headless --path . -s res://tests/map_pool_test.gd
## Exit code 0 = every check passed.

const MAP := "res://assets/maps/dungeon_01.ds"
const MAIN := preload("res://scenes/main/main.tscn")
const ROSTER := preload("res://resources/encounters/knights.tres")
## Footprint radius (cells) of each prop kind around its position.
const RADIUS := {"pillar": 0.28, "crate": 0.28, "barrel": 0.19, "table": 0.52, "chest": 0.3,
	"rubble": 0.4, "statue": 0.36, "brazier": 0.25, "campfire": 0.32, "bedroll": 0.48}
## Partition walls are 0.6 m thick on the cell edge: 0.15 cells into the cell.
const PARTITION_HALF := 0.15

var failures: int = 0


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	test_rooms()
	test_population()
	await test_real_build()
	test_pool()
	await test_main_plays_map()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_rooms() -> void:
	print("1. dungeon_01's rooms are found")
	var layout := DungeonLayout.from_dungeon_scrawl(MAP)
	check(RoomAnalysis.new().analyze(layout), "analyzed")
	check(layout.rooms.size() == 8, "8 rooms (north, west hall, start, central hall, east, south hall, south-east, boss): %d" % layout.rooms.size())
	check(layout.blocked_edges.size() == 6, "6 partition edges block walking")
	var owners := {}
	var shared := 0
	for i in layout.rooms.size():
		for c: Vector2i in layout.rooms[i]["cells"]:
			if owners.has(c):
				shared += 1
			owners[c] = i
	check(shared == 0, "no cell in two rooms")
	var roles := layout.rooms.map(func(r: Dictionary) -> String: return r["role"])
	check(roles.count("start") == 1 and roles.count("exit") == 1, "one start room, one exit room")
	var start_room := roles.find("start")
	var exit_room := roles.find("exit")
	var boss_point: Vector2 = layout.labels.filter(func(l: Array) -> bool: return l[0] == "boss room")[0][1]
	check((layout.rooms[exit_room]["rect"] as Rect2i).has_point(Vector2i(boss_point)),
		"the exit is the boss room (furthest from the start)")
	var exit_label: Array = layout.labels.filter(func(l: Array) -> bool: return l[0] == "Exit")
	check(exit_label.size() == 1 and owners.get(Vector2i(exit_label[0][1]), -1) == exit_room, "an Exit label was added in it")
	check(layout.rooms.all(func(r: Dictionary) -> bool: return r["depth"] > 0 or r["role"] == "start"),
		"every room is linked to the start (depths %s)" % [layout.rooms.map(func(r: Dictionary) -> int: return r["depth"])])
	check(layout.rooms[start_room]["depth"] == 0, "start depth 0")


func test_population() -> void:
	print("2. Props and enemies on dungeon_01 follow the rules (60 seeds)")
	var bad := {}
	var props := 0
	var enemies := 0
	var first := LevelPool.map_layout(MAP, 5, 3)
	var again := LevelPool.map_layout(MAP, 5, 3)
	check(var_to_str(first.props) == var_to_str(again.props) and first.spawns.size() == again.spawns.size(),
		"same seed, same props and enemies")
	for s in range(1, 61):
		var layout := LevelPool.map_layout(MAP, s, 1 + s % 6)
		props += layout.props.size()
		enemies += layout.spawns.size()
		var problem := _check(layout)
		if problem != "":
			bad[s] = problem
	check(bad.is_empty(), "all valid (%d bad: %s)" % [bad.size(), str(bad).left(300)])
	print("     %.1f props, %.1f enemies per level" % [props / 60.0, enemies / 60.0])
	check(props > 60 * 10 and enemies > 60 * 3, "the map gets furnished and populated")


func test_real_build() -> void:
	print("3. A real build of dungeon_01 as a level: gate, paths, spawns")
	var layout := LevelPool.map_layout(MAP, 777, 4)
	var level := DungeonLevel.new()
	root.add_child(level)
	level.build(layout, "Map")
	await level.navigation_ready
	var gate := level.level.get_node_or_null("NavigationRegion3D/ExitGate")
	check(gate != null, "the exit gate is built")
	var map := level.get_world_3d().navigation_map
	var start := level.get_marker("Start").global_position + Vector3.UP * 0.5
	var exit := level.get_marker("Exit").global_position + Vector3.UP * 0.5
	var path := NavigationServer3D.map_get_path(map, start, exit, true)
	check(path.size() > 2 and path[-1].distance_to(exit) < 1.5, "a path leads from Start to the gate")
	var off := 0
	for spawn in layout.spawns:
		var at := layout.to_world(spawn["cell"], DungeonBuilder.CELL) + Vector3.UP * 0.5
		var p := NavigationServer3D.map_get_path(map, start, at, true)
		if p.is_empty() or p[-1].distance_to(at) > 0.6:
			off += 1
	check(off == 0, "all %d enemies reachable" % layout.spawns.size())
	level.queue_free()
	await process_frame
	# Curvature bends every seed differently: the map's narrow doorways (in
	# its interior walls) must stay open for all of them.
	var cut_off := []
	for s in [7919, 31676, 39595, 55433, 79190, 87109, 118789, 158380]:
		var bent := LevelPool.map_layout(MAP, s, 1 + s % 6)
		var holder := DungeonLevel.new()
		root.add_child(holder)
		holder.build(bent, "Map")
		await holder.navigation_ready
		var nav_map := holder.get_world_3d().navigation_map
		var from := holder.get_marker("Start").global_position + Vector3.UP * 0.5
		for spawn in bent.spawns:
			var at := bent.to_world(spawn["cell"], DungeonBuilder.CELL) + Vector3.UP * 0.5
			var route := NavigationServer3D.map_get_path(nav_map, from, at, true)
			if route.is_empty() or route[-1].distance_to(at) > 0.6:
				cut_off.append(s)
		holder.queue_free()
		await process_frame
	check(cut_off.is_empty(), "8 more seeds: every enemy reachable (cut off in seeds %s)" % [cut_off])


func test_pool() -> void:
	print("4. The pool mixes maps into the run")
	var pool := LevelPool.new()
	check(pool.maps.has(MAP), "dungeon_01.ds is in the pool (%s)" % [pool.maps])
	pool.maps = PackedStringArray([MAP])
	var from_map := 0
	for s in range(1, 201):
		if pool.layout_for(s, 2).source == MAP:
			from_map += 1
	check(from_map > 40 and from_map < 80, "%d of 200 levels from the map (chance %.0f%%)" % [from_map, pool.scrawl_chance * 100])
	check(pool.layout_for(123, 2).source == pool.layout_for(123, 2).source, "the same seed picks the same source")
	pool.scrawl_chance = 0.0
	check(pool.layout_for(9, 1).source == "", "chance 0: always generated")
	pool.scrawl_chance = 1.0
	pool.maps = PackedStringArray(["res://assets/maps/missing.ds"])
	var fallback := pool.layout_for(9, 1)
	check(fallback != null and fallback.source == "", "an unusable map falls back to a generated level")


func test_main_plays_map() -> void:
	print("5. Main plays a map")
	GameRun.current().start_new_run(31)
	var main = MAIN.instantiate()
	main.start_run_on_ready = false
	root.add_child(main)
	await process_frame
	var layout: DungeonLayout = await main.play_map(MAP, 4242, 2)
	check(layout != null and main.layout == layout and layout.source == MAP, "the map is the level")
	check(main.gate != null, "its gate is connected")
	var alive := (main.get_node("Enemies") as Node).get_children().filter(func(e: Node) -> bool:
		return not e.is_queued_for_deletion())
	check(alive.size() == layout.spawns.size() and alive.size() > 0, "%d enemies spawned" % alive.size())
	main.queue_free()
	await process_frame


## "" when the layout's props and spawns follow the rules, else what's wrong.
func _check(layout: DungeonLayout) -> String:
	var owner := {}
	for i in layout.rooms.size():
		for c: Vector2i in layout.rooms[i]["cells"]:
			owner[c] = i
	for p: Array in layout.props:
		var pos := Vector2(p[1], p[2])
		var cell := Vector2i(floori(pos.x), floori(pos.y))
		if not owner.has(cell):
			return "%s outside the rooms at %s" % [p[0], pos]
		if layout.reserved_cells.has(cell):
			return "%s on a route %s" % [p[0], cell]
		var radius: float = RADIUS[p[0]]
		var local := pos - Vector2(cell)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			var limit := -1.0
			if not layout.floor_cells.has(n):
				limit = 0.0  # Outer walls stand outside the floor.
			elif layout.blocked_edges.has(DungeonLayout.edge_key(cell, n)):
				limit = PARTITION_HALF
			if limit < 0.0:
				continue
			var gap: float = (local.x if d.x < 0 else 1.0 - local.x) if d.x != 0 else (local.y if d.y < 0 else 1.0 - local.y)
			if gap - radius < limit - 0.02:
				return "%s pokes into a wall at %s" % [p[0], pos]
	for i in layout.rooms.size():
		var free := {}
		for c: Vector2i in layout.rooms[i]["cells"]:
			if not layout.blocked_cells.has(c):
				free[c] = true
		var seen := {}
		var queue: Array[Vector2i] = []
		for e in layout.room_entries(i):
			for c: Vector2i in e["cells"]:
				if free.has(c) and not seen.has(c):
					seen[c] = true
					queue.append(c)
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if free.has(n) and not seen.has(n) and layout.can_step(c, n):
					seen[n] = true
					queue.append(n)
		if seen.size() != free.size():
			return "room %d: %d cells cut off" % [i, free.size() - seen.size()]
	var start: Vector2 = layout.labels.filter(func(l: Array) -> bool: return (l[0] as String).to_lower() == "start")[0][1]
	var cells := {}
	for spawn in layout.spawns:
		var p: Vector2 = spawn["cell"]
		var cell := Vector2i(floori(p.x), floori(p.y))
		if owner.get(cell, -1) != spawn["room"]:
			return "enemy outside its room"
		if layout.rooms[spawn["room"]]["role"] == "start":
			return "enemy in the start room"
		if cells.has(cell) or layout.blocked_cells.has(cell):
			return "enemy on a taken cell %s" % cell
		cells[cell] = true
		if p.distance_to(start) < ROSTER.start_clearance - 0.75:
			return "enemy near the start"
	return ""
