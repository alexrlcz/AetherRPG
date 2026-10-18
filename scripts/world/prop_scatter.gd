class_name PropScatter
extends RefCounted
## Fills a layout's rooms with props (steps 3 and 5 of procedural levels),
## keeping the walking routes between doorways clear. Works on any room shape
## (each room's `cells`), so generated levels and hand-made maps get the same
## rules. Writes `layout.props`, `layout.reserved_cells` and
## `layout.blocked_cells`.
##
## Routes: a 3x3 block around the room's centre cell, plus the shortest walk
## from every doorway to it, widened by one cell. Props never go on those
## cells, at most one prop group takes a cell, and a prop that would cut any
## free cell of its room off from the doorways is not placed.
## Rules per room: pillars (rooms whose bounding box is >= 9 cells a side,
## half the time), crate and barrel clusters against the walls (more in
## bigger rooms), rubble in a corner, the odd table or statue, a campfire and
## bedroll in the start room, braziers in the exit room's corners, a chest in
## dead-end side rooms. Corridors stay empty.

const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _rng := RandomNumberGenerator.new()
var _layout: DungeonLayout
var _taken := {}  # Cells holding any prop (also decor).
# The room being furnished: its cells, bounding box and doorway cells.
var _cells := {}
var _rect: Rect2i
var _doors: Array[Vector2i] = []


func populate(layout: DungeonLayout) -> void:
	_layout = layout
	_rng.seed = hash([layout.seed, "props"])
	_taken.clear()
	layout.props.clear()
	layout.reserved_cells.clear()
	layout.blocked_cells.clear()
	for i in layout.rooms.size():
		_enter_room(i)
		_reserve_routes(i)
	_reserve_exit()
	for i in layout.rooms.size():
		_enter_room(i)
		_furnish(i)


func _enter_room(index: int) -> void:
	_cells.clear()
	for c: Vector2i in _layout.rooms[index]["cells"]:
		_cells[c] = true
	_rect = _layout.rooms[index]["rect"]
	_doors.clear()
	for entry in _layout.room_entries(index):
		_doors.append_array(entry["cells"])


func _reserve_routes(index: int) -> void:
	var centre := _layout.room_centre(index)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_reserve_cell(centre + Vector2i(dx, dy))
	# Shortest walks from the centre to every cell of the room.
	var parent := {centre: centre}
	var queue: Array[Vector2i] = [centre]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in STEPS:
			var n: Vector2i = c + d
			if _cells.has(n) and not parent.has(n) and _layout.can_step(c, n):
				parent[n] = c
				queue.append(n)
	for door in _doors:
		var at := door
		while parent.has(at):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					_reserve_cell(at + Vector2i(dx, dy))
			if at == centre:
				break
			at = parent[at]


## The cells under and around the exit gate (it may stand off the routes, as
## in a boss arena).
func _reserve_exit() -> void:
	for label: Array in _layout.labels:
		if (label[0] as String).strip_edges().to_lower() != "exit":
			continue
		var at := Vector2i(floori(label[1].x), floori(label[1].y))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if _layout.floor_cells.has(at + Vector2i(dx, dy)):
					_layout.reserved_cells[at + Vector2i(dx, dy)] = true


func _reserve_cell(c: Vector2i) -> void:
	if _cells.has(c):
		_layout.reserved_cells[c] = true


func _furnish(index: int) -> void:
	var room: Dictionary = _layout.rooms[index]
	var role: String = room["role"]
	var short_side := mini(_rect.size.x, _rect.size.y)
	if short_side >= 9 and (role == "boss" or _rng.randf() < 0.5):
		for c in [Vector2i(_rect.position.x + 2, _rect.position.y + 2), Vector2i(_rect.end.x - 3, _rect.position.y + 2),
				Vector2i(_rect.position.x + 2, _rect.end.y - 3), Vector2i(_rect.end.x - 3, _rect.end.y - 3)]:
			if _is_interior(c):
				_place(c, "pillar", Vector2(0.5, 0.5), 0.0)
	match role:
		"start":
			var spot: Variant = _free_cell(_interior())
			if spot != null:
				_place(spot, "campfire", Vector2(0.5, 0.5), 0.0)
				var bed: Variant = _free_cell(_neighbours(spot))
				if bed != null:
					_place(bed, "bedroll", Vector2(0.5, 0.5), _rng.randf_range(0, 180), false)
		"exit":
			for c in [Vector2i(_rect.position.x + 1, _rect.position.y + 1), Vector2i(_rect.end.x - 2, _rect.position.y + 1)]:
				if _is_interior(c):
					_place(c, "brazier", Vector2(0.5, 0.5), 0.0)
		"boss":
			for c in [Vector2i(_rect.position.x + 1, _rect.position.y + 1), Vector2i(_rect.end.x - 2, _rect.position.y + 1),
					Vector2i(_rect.position.x + 1, _rect.end.y - 2), Vector2i(_rect.end.x - 2, _rect.end.y - 2)]:
				if _is_interior(c):
					_place(c, "brazier", Vector2(0.5, 0.5), 0.0)
		"side":
			if _layout.room_entries(index).size() == 1 and _rng.randf() < 0.6:
				var spot: Variant = _far_wall_cell()
				if spot != null:
					var side: Array = _wall_sides(spot)[0]
					var to_centre := Vector2(_layout.room_centre(index)) - Vector2(spot)
					_place(spot, "chest", Vector2(0.5, 0.5) + Vector2(side[0]) * _wall_push(side, 0.2, 0.0),
						rad_to_deg(atan2(to_centre.x, to_centre.y)))
	# Crate and barrel clusters against the walls.
	var clusters := _rng.randi_range(1, maxi(1, _cells.size() / 20))
	var walls := _wall_cells()
	for k in clusters:
		var spot: Variant = _free_cell(walls)
		if spot == null:
			break
		_wall_cluster(spot)
	if _rng.randf() < 0.3:
		var spot: Variant = _free_cell(_corner_cells())
		if spot != null:
			_place(spot, "rubble", Vector2(0.5, 0.5), _rng.randf_range(0, 360))
	if role == "boss":
		return  # The arena stays open for the fight.
	if short_side >= 8 and _rng.randf() < 0.25:
		var spot: Variant = _free_cell(_interior())
		if spot != null:
			_place(spot, "table", Vector2(0.5, 0.5), 90.0 * _rng.randi_range(0, 1))
	if role == "path" and _rng.randf() < 0.15:
		var spot: Variant = _free_cell(_interior())
		if spot != null:
			_place(spot, "statue", Vector2(0.5, 0.5), _rng.randf_range(0, 360))


## One or two crates / barrels in `cell`, pushed against one of its walls.
func _wall_cluster(cell: Vector2i) -> void:
	if not _keeps_room_open(cell):
		return
	var sides := _wall_sides(cell)
	var side: Array = sides[_rng.randi_range(0, sides.size() - 1)]
	var n := Vector2(side[0])
	var t := Vector2(-n.y, n.x)
	var kind := "crate" if _rng.randf() < 0.5 else "barrel"
	# A turned crate's corner reaches further; partition walls stand on the
	# cell edge itself (outer walls are outside the floor).
	var base := Vector2(0.5, 0.5) + n * _wall_push(side, 0.2 if kind == "crate" else 0.25,
		0.05 if kind == "crate" else 0.1)
	var count := _rng.randi_range(1, 2)
	if sides.size() > 1 and kind == "crate":
		count = 1  # In a corner a second crate would reach into the other wall.
	var spacing := 0.24 if kind == "crate" else 0.21
	for k in count:
		var along := 0.0 if count == 1 else (spacing if k == 0 else -spacing)
		_add(cell, kind, base + t * along, _rng.randf_range(-15, 15))
	_taken[cell] = true
	_layout.blocked_cells[cell] = true


## How far (cells) to push a prop from the cell centre toward wall `side`.
static func _wall_push(side: Array, outer: float, partition: float) -> float:
	return partition if side[1] else outer


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
	for c: Vector2i in _cells:
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
		for step in STEPS:
			var n: Vector2i = c + step
			if _cells.has(n) and n != cell and not _layout.blocked_cells.has(n) and not seen.has(n) \
					and _layout.can_step(c, n):
				seen[n] = true
				queue.append(n)
	return seen.size() == free


func _can_use(cell: Vector2i) -> bool:
	return _cells.has(cell) and not _taken.has(cell) and not _layout.reserved_cells.has(cell)


## A random usable cell from `cells`, or null.
func _free_cell(cells: Array) -> Variant:
	var options := cells.filter(_can_use)
	if options.is_empty():
		return null
	return options[_rng.randi_range(0, options.size() - 1)]


## [direction (Vector2i, toward the wall), is_partition (bool)] for every
## side of `cell` that is a wall: the floor's edge or an interior wall.
func _wall_sides(cell: Vector2i) -> Array:
	var sides := []
	for d in STEPS:
		var n: Vector2i = cell + d
		if not _layout.floor_cells.has(n):
			sides.append([d, false])
		elif _layout.blocked_edges.has(DungeonLayout.edge_key(cell, n)):
			sides.append([d, true])
	return sides


func _wall_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c: Vector2i in _sorted_cells():
		if not _wall_sides(c).is_empty():
			result.append(c)
	return result


## Wall cells with walls on two perpendicular sides.
func _corner_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in _wall_cells():
		var sides := _wall_sides(c)
		for i in sides.size():
			for j in range(i + 1, sides.size()):
				var a: Vector2i = sides[i][0]
				var b: Vector2i = sides[j][0]
				if a.x * b.x + a.y * b.y == 0 and not result.has(c):
					result.append(c)
	return result


## Room cells with room on all four sides and no wall at all.
func _interior() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c: Vector2i in _sorted_cells():
		if _is_interior(c):
			result.append(c)
	return result


func _is_interior(c: Vector2i) -> bool:
	if not _cells.has(c) or not _wall_sides(c).is_empty():
		return false
	for d in STEPS:
		if not _cells.has(c + d):
			return false
	return true


func _neighbours(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in STEPS:
		if _cells.has(cell + d) and _layout.can_step(cell, cell + d):
			result.append(cell + d)
	return result


## The usable wall cell furthest from the room's doorways.
func _far_wall_cell() -> Variant:
	var best: Variant = null
	var best_distance := -1.0
	for c in _wall_cells():
		if not _can_use(c):
			continue
		var nearest := INF
		for d in _doors:
			nearest = minf(nearest, Vector2(c).distance_to(Vector2(d)))
		if nearest > best_distance:
			best_distance = nearest
			best = c
	return best


func _sorted_cells() -> Array:
	var keys := _cells.keys()
	keys.sort()  # Deterministic order for the RNG.
	return keys
