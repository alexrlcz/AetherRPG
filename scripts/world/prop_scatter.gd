class_name PropScatter
extends RefCounted
## Fills a generated layout's rooms with props (step 3 of procedural levels),
## keeping the walking routes between doorways clear. Writes
## `layout.props`, `layout.reserved_cells` and `layout.blocked_cells`.
##
## Routes: from every doorway a band 1 cell wider than the corridor runs
## straight into the room to the centre line, then along it to a 3x3 block
## around the centre, so every pair of doors stays connected. Props never go
## on those cells, at most one prop group takes a cell, and a prop that would
## cut any free cell of its room off from the doorways is not placed.
## Rules per room: pillars (rooms >= 9 cells a side, half the time), crate and
## barrel clusters against the walls (more in bigger rooms), rubble in a
## corner, the odd table or statue, a campfire and bedroll in the start room,
## braziers in the exit room's corners, a chest in dead-end side rooms.
## Corridors stay empty.

var _rng := RandomNumberGenerator.new()
var _layout: DungeonLayout
var _taken := {}  # Cells holding any prop (also decor).
var _room: Rect2i  # The room being furnished, and its doorway cells.
var _doors: Array[Vector2i] = []


func populate(layout: DungeonLayout) -> void:
	_layout = layout
	_rng.seed = hash([layout.seed, "props"])
	_taken.clear()
	layout.props.clear()
	layout.reserved_cells.clear()
	layout.blocked_cells.clear()
	for i in layout.rooms.size():
		_reserve_routes(i)
	for i in layout.rooms.size():
		_room = layout.rooms[i]["rect"]
		_doors.clear()
		for entry in layout.room_entries(i):
			_doors.append_array(entry["cells"])
		_furnish(i)


func _reserve_routes(index: int) -> void:
	var r: Rect2i = _layout.rooms[index]["rect"]
	var centre := r.position + r.size / 2
	_reserve(Rect2i(centre - Vector2i.ONE, Vector2i(3, 3)), r)
	for entry in _layout.room_entries(index):
		var cells: Array[Vector2i] = entry["cells"]
		var inward: Vector2i = entry["inward"]
		var first := cells[0]
		var last := cells[-1]
		if inward.x != 0:
			# Along x into the room at the doorway's rows, then along y.
			var x0 := mini(first.x, centre.x)
			var x1 := maxi(first.x, centre.x)
			_reserve(Rect2i(x0, first.y - 1, x1 - x0 + 1, last.y - first.y + 3), r)
			var y0 := mini(first.y, centre.y)
			var y1 := maxi(last.y, centre.y)
			_reserve(Rect2i(centre.x - 1, y0, 3, y1 - y0 + 1), r)
		else:
			var y0 := mini(first.y, centre.y)
			var y1 := maxi(first.y, centre.y)
			_reserve(Rect2i(first.x - 1, y0, last.x - first.x + 3, y1 - y0 + 1), r)
			var x0 := mini(first.x, centre.x)
			var x1 := maxi(last.x, centre.x)
			_reserve(Rect2i(x0, centre.y - 1, x1 - x0 + 1, 3), r)


func _reserve(rect: Rect2i, room: Rect2i) -> void:
	var clipped := rect.intersection(room)
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			_layout.reserved_cells[Vector2i(x, y)] = true


func _furnish(index: int) -> void:
	var room: Dictionary = _layout.rooms[index]
	var r: Rect2i = room["rect"]
	var role: String = room["role"]
	var short_side := mini(r.size.x, r.size.y)
	if short_side >= 9 and _rng.randf() < 0.5:
		for c in [Vector2i(r.position.x + 2, r.position.y + 2), Vector2i(r.end.x - 3, r.position.y + 2),
				Vector2i(r.position.x + 2, r.end.y - 3), Vector2i(r.end.x - 3, r.end.y - 3)]:
			_place(c, "pillar", Vector2(0.5, 0.5), 0.0)
	match role:
		"start":
			var spot: Variant = _free_cell(_interior(r))
			if spot != null:
				_place(spot, "campfire", Vector2(0.5, 0.5), 0.0)
				var bed: Variant = _free_cell(_neighbours(spot, r))
				if bed != null:
					_place(bed, "bedroll", Vector2(0.5, 0.5), _rng.randf_range(0, 180), false)
		"exit":
			for c in [Vector2i(r.position.x + 1, r.position.y + 1), Vector2i(r.end.x - 2, r.position.y + 1)]:
				_place(c, "brazier", Vector2(0.5, 0.5), 0.0)
		"side":
			if _is_dead_end(index) and _rng.randf() < 0.6:
				var spot: Variant = _far_wall_cell(index)
				if spot != null:
					var to_centre := Vector2(r.get_center()) - Vector2(spot)
					_place(spot, "chest", Vector2(0.5, 0.5) + _wall_normal(spot, r) * 0.2,
						rad_to_deg(atan2(to_centre.x, to_centre.y)))
	# Crate and barrel clusters against the walls.
	var clusters := _rng.randi_range(1, maxi(1, r.get_area() / 20))
	var walls := _wall_cells(r)
	for k in clusters:
		var spot: Variant = _free_cell(walls)
		if spot == null:
			break
		_wall_cluster(spot, r)
	if _rng.randf() < 0.3:
		var corners: Array[Vector2i] = [r.position, Vector2i(r.end.x - 1, r.position.y),
			Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]
		var spot: Variant = _free_cell(corners)
		if spot != null:
			_place(spot, "rubble", Vector2(0.5, 0.5), _rng.randf_range(0, 360))
	if short_side >= 8 and _rng.randf() < 0.25:
		var spot: Variant = _free_cell(_interior(r))
		if spot != null:
			_place(spot, "table", Vector2(0.5, 0.5), 90.0 * _rng.randi_range(0, 1))
	if role == "path" and _rng.randf() < 0.15:
		var spot: Variant = _free_cell(_interior(r))
		if spot != null:
			_place(spot, "statue", Vector2(0.5, 0.5), _rng.randf_range(0, 360))


## One or two crates / barrels in `cell`, pushed against its wall.
func _wall_cluster(cell: Vector2i, r: Rect2i) -> void:
	if not _keeps_room_open(cell):
		return
	var n := _wall_normal(cell, r)
	var t := Vector2(-n.y, n.x)
	var kind := "crate" if _rng.randf() < 0.5 else "barrel"
	# A turned crate's corner reaches further: keep it clear of the wall.
	var base := Vector2(0.5, 0.5) + n * (0.2 if kind == "crate" else 0.25)
	var count := _rng.randi_range(1, 2)
	var corner := (cell.x == r.position.x or cell.x == r.end.x - 1) \
		and (cell.y == r.position.y or cell.y == r.end.y - 1)
	if corner and kind == "crate":
		count = 1  # A second crate would reach into the other wall.
	var spacing := 0.24 if kind == "crate" else 0.21
	for k in count:
		var along := 0.0 if count == 1 else (spacing if k == 0 else -spacing)
		_add(cell, kind, base + t * along, _rng.randf_range(-15, 15))
	_taken[cell] = true
	_layout.blocked_cells[cell] = true


## Places a prop at `offset` (cell fractions) in `cell` if the cell is free.
func _place(cell: Vector2i, kind: String, offset: Vector2, yaw: float, blocks: bool = true) -> void:
	if not _can_use(cell) or (blocks and not _keeps_room_open(cell)):
		return
	_add(cell, kind, offset, yaw)
	_taken[cell] = true
	if blocks:
		_layout.blocked_cells[cell] = true


func _add(cell: Vector2i, kind: String, offset: Vector2, yaw: float) -> void:
	var p := Vector2(cell) + offset
	_layout.props.append([kind, p.x, p.y, yaw])


## True when blocking `cell` still leaves every free cell of the room
## reachable from its doorways.
func _keeps_room_open(cell: Vector2i) -> bool:
	var free := 0
	for y in range(_room.position.y, _room.end.y):
		for x in range(_room.position.x, _room.end.x):
			var c := Vector2i(x, y)
			if c != cell and not _layout.blocked_cells.has(c):
				free += 1
	var seen := {}
	var queue: Array[Vector2i] = []
	for d in _doors:
		if d != cell and not _layout.blocked_cells.has(d) and not seen.has(d):
			seen[d] = true
			queue.append(d)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + step
			if _room.has_point(n) and n != cell and not _layout.blocked_cells.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == free


func _can_use(cell: Vector2i) -> bool:
	return not _taken.has(cell) and not _layout.reserved_cells.has(cell)


## A random usable cell from `cells`, or null.
func _free_cell(cells: Array) -> Variant:
	var options := cells.filter(_can_use)
	if options.is_empty():
		return null
	return options[_rng.randi_range(0, options.size() - 1)]


func _interior(r: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			cells.append(Vector2i(x, y))
	return cells


func _wall_cells(r: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1:
				cells.append(Vector2i(x, y))
	return cells


func _neighbours(cell: Vector2i, r: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if r.has_point(cell + d):
			cells.append(cell + d)
	return cells


## Unit vector (cells) from `cell` toward its nearest room wall.
func _wall_normal(cell: Vector2i, r: Rect2i) -> Vector2:
	var options := [[cell.x - r.position.x, Vector2.LEFT], [r.end.x - 1 - cell.x, Vector2.RIGHT],
		[cell.y - r.position.y, Vector2.UP], [r.end.y - 1 - cell.y, Vector2.DOWN]]
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return options[0][1]


func _is_dead_end(index: int) -> bool:
	return _layout.room_entries(index).size() == 1


## The usable wall cell furthest from the room's doorways.
func _far_wall_cell(index: int) -> Variant:
	var r: Rect2i = _layout.rooms[index]["rect"]
	var doors: Array[Vector2i] = []
	for entry in _layout.room_entries(index):
		doors.append_array(entry["cells"])
	var best: Variant = null
	var best_distance := -1.0
	for c in _wall_cells(r):
		if not _can_use(c):
			continue
		var nearest := INF
		for d in doors:
			nearest = minf(nearest, Vector2(c).distance_to(Vector2(d)))
		if nearest > best_distance:
			best_distance = nearest
			best = c
	return best
