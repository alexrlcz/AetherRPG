class_name EncounterPlanner
extends RefCounted
## Decides which enemies a level gets and where (steps 3 and 5 of procedural
## levels). Works on each room's `cells`, so generated levels and hand-made
## maps follow the same rules. Writes `layout.spawns`; Main spawns them once
## the navmesh is ready. Run after PropScatter (enemies avoid its props).
##
## Each room's budget comes from the roster (EnemyRoster.room_budget(): grows
## with the level, scaled by room role, none in the start room) ± variance.
## It is spent on random affordable entries for the level until nothing more
## fits or the room holds one enemy per `cells_per_enemy` cells. Each enemy
## stands on its own cell, never on a prop, at least `door_clearance` cells
## from every doorway (so nobody waits right at a door), `start_clearance`
## cells from the start and `exit_clearance` cells from the exit gate, facing
## the room's centre.

var _rng := RandomNumberGenerator.new()


func populate(layout: DungeonLayout, roster: EnemyRoster) -> void:
	_rng.seed = hash([layout.seed, "enemies"])
	layout.spawns.clear()
	if roster == null:
		return
	var options := roster.available(layout.level)
	if options.is_empty():
		return
	var cheapest := INF
	for e in options:
		cheapest = minf(cheapest, e.cost)
	for i in layout.rooms.size():
		var room: Dictionary = layout.rooms[i]
		var budget := roster.room_budget(room["role"], layout.level)
		if budget <= 0.0:
			continue
		budget *= 1.0 + _rng.randf_range(-roster.budget_variance, roster.budget_variance)
		var room_cells: Array = room["cells"]
		var centroid := Vector2.ZERO
		for c: Vector2i in room_cells:
			centroid += Vector2(c) + Vector2(0.5, 0.5)
		centroid /= room_cells.size()
		var cells := _spawn_cells(layout, i, roster)
		var cap := maxi(1, room_cells.size() / roster.cells_per_enemy)
		var placed := 0
		while budget >= cheapest and placed < cap and not cells.is_empty():
			var affordable := options.filter(func(e: EnemyEntry) -> bool: return e.cost <= budget)
			var entry: EnemyEntry = affordable[_rng.randi_range(0, affordable.size() - 1)]
			var cell: Vector2i = cells.pop_at(_rng.randi_range(0, cells.size() - 1))
			var spot := Vector2(cell) + Vector2(_rng.randf_range(0.35, 0.65), _rng.randf_range(0.35, 0.65))
			var to_centre := centroid - spot
			# rotation.y = yaw makes local -Z (the model's front) face along
			# (-sin, -cos): the room's centre.
			layout.spawns.append({"cell": spot, "room": i, "entry": entry,
				"yaw": rad_to_deg(atan2(-to_centre.x, -to_centre.y))})
			budget -= entry.cost
			placed += 1


## Puts `encounter` in the layout's boss arena (the room with role "boss"):
## the boss on the arena's centre facing the way in, its escorts on free
## cells (the roster's clearances apply) at least `boss_clearance` cells
## from it. Sets `layout.boss`. Run after populate().
func place_boss(layout: DungeonLayout, encounter: BossEncounter, roster: EnemyRoster,
		boss_clearance: int = 2) -> void:
	layout.boss = encounter
	var index := -1
	for i in layout.rooms.size():
		if layout.rooms[i]["role"] == "boss":
			index = i
	if index < 0 or encounter.boss == null:
		push_warning("EncounterPlanner: no boss arena in the layout")
		return
	_rng.seed = hash([layout.seed, "boss"])
	var centre := layout.room_centre(index)
	var spot := Vector2(centre) + Vector2(0.5, 0.5)
	var way_in := spot
	var entries := layout.room_entries(index)
	if not entries.is_empty():
		var door := Vector2.ZERO
		for c: Vector2i in entries[0]["cells"]:
			door += Vector2(c) + Vector2(0.5, 0.5)
		way_in = door / entries[0]["cells"].size()
	var to_door := way_in - spot
	layout.spawns.append({"cell": spot, "room": index, "entry": encounter.boss, "boss": true,
		"yaw": rad_to_deg(atan2(-to_door.x, -to_door.y))})
	if encounter.escorts.is_empty():
		return
	var cells := _spawn_cells(layout, index, roster).filter(func(c: Vector2i) -> bool:
		return absi(c.x - centre.x) > boss_clearance or absi(c.y - centre.y) > boss_clearance)
	for k in mini(encounter.escort_count, cells.size()):
		var cell: Vector2i = cells.pop_at(_rng.randi_range(0, cells.size() - 1))
		var entry: EnemyEntry = encounter.escorts[_rng.randi_range(0, encounter.escorts.size() - 1)]
		var at := Vector2(cell) + Vector2(0.5, 0.5)
		var to_way_in := way_in - at
		layout.spawns.append({"cell": at, "room": index, "entry": entry,
			"yaw": rad_to_deg(atan2(-to_way_in.x, -to_way_in.y))})


## The room's cells an enemy may stand on, in order.
func _spawn_cells(layout: DungeonLayout, index: int, roster: EnemyRoster) -> Array[Vector2i]:
	var start := Vector2.INF
	var exit := Vector2.INF
	for label in layout.labels:
		match (label[0] as String).strip_edges().to_lower():
			"start":
				start = label[1]
			"exit":
				exit = label[1]
	var doors: Array[Vector2i] = []
	for entry in layout.room_entries(index):
		doors.append_array(entry["cells"])
	var cells: Array[Vector2i] = []
	for c: Vector2i in layout.rooms[index]["cells"]:
		if layout.blocked_cells.has(c):
			continue
		var centre := Vector2(c) + Vector2(0.5, 0.5)
		if start != Vector2.INF and centre.distance_to(start) < roster.start_clearance:
			continue
		if exit != Vector2.INF and absf(centre.x - exit.x) <= roster.exit_clearance + 0.5 \
				and absf(centre.y - exit.y) <= roster.exit_clearance + 0.5:
			continue
		var near_door := false
		for d in doors:
			if absi(c.x - d.x) <= roster.door_clearance and absi(c.y - d.y) <= roster.door_clearance:
				near_door = true
				break
		if not near_door:
			cells.append(c)
	return cells
