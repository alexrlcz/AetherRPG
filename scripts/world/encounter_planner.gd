class_name EncounterPlanner
extends RefCounted
## Decides which enemies a generated level gets and where (step 3 of
## procedural levels). Writes `layout.spawns`; Main spawns them once the
## navmesh is ready. Run after PropScatter (enemies avoid its props).
##
## Each room's budget comes from the roster (EnemyRoster.room_budget(): grows
## with the level, scaled by room role, none in the start room) ± variance.
## It is spent on random affordable entries for the level until nothing more
## fits or the room holds one enemy per `cells_per_enemy` cells. Each enemy
## stands on its own cell, never on a prop, at least `door_clearance` cells
## from every doorway (so nobody waits right at a door), `start_clearance`
## cells from the start and `exit_clearance` cells from the exit gate, facing
## the room.

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
		var r: Rect2i = room["rect"]
		var cells := _spawn_cells(layout, i, roster)
		var cap := maxi(1, r.get_area() / roster.cells_per_enemy)
		var placed := 0
		while budget >= cheapest and placed < cap and not cells.is_empty():
			var affordable := options.filter(func(e: EnemyEntry) -> bool: return e.cost <= budget)
			var entry: EnemyEntry = affordable[_rng.randi_range(0, affordable.size() - 1)]
			var cell: Vector2i = cells.pop_at(_rng.randi_range(0, cells.size() - 1))
			var spot := Vector2(cell) + Vector2(_rng.randf_range(0.35, 0.65), _rng.randf_range(0.35, 0.65))
			var to_centre := Vector2(r.position) + Vector2(r.size) * 0.5 - spot
			# rotation.y = yaw makes local -Z (the model's front) face along
			# (-sin, -cos): the room's centre.
			layout.spawns.append({"cell": spot, "room": i, "entry": entry,
				"yaw": rad_to_deg(atan2(-to_centre.x, -to_centre.y))})
			budget -= entry.cost
			placed += 1


## The room's cells an enemy may stand on, in order.
func _spawn_cells(layout: DungeonLayout, index: int, roster: EnemyRoster) -> Array[Vector2i]:
	var r: Rect2i = layout.rooms[index]["rect"]
	var clearance := roster.door_clearance
	var start := Vector2.INF
	var exit := Vector2.INF
	for label in layout.labels:
		if label[0] == "Start":
			start = label[1]
		elif label[0] == "Exit":
			exit = label[1]
	var doors: Array[Vector2i] = []
	for entry in layout.room_entries(index):
		doors.append_array(entry["cells"])
	var cells: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
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
				if absi(c.x - d.x) <= clearance and absi(c.y - d.y) <= clearance:
					near_door = true
					break
			if not near_door:
				cells.append(c)
	return cells
