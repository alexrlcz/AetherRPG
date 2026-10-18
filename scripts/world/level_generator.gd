class_name LevelGenerator
extends RefCounted
## Seeded level layouts made in code (step 2 of procedural levels): a main
## path of rectangular rooms from the start to the exit, side branches and an
## occasional loop, joined by straight corridors. The same seed always gives
## the same layout.
##
##   var layout := LevelGenerator.new().generate(seed)
##   dungeon_level.build(layout)          # DungeonLevel, see DungeonBuilder
##
## The result carries `rooms` / `corridors` (roles, depth), "Start" / "Exit"
## labels (Marker3Ds once built), props (PropScatter) and the enemies to
## spawn (`spawns`, EncounterPlanner with `roster`, scaled by the level).
## All sizes are in cells (DungeonBuilder.CELL = 2 m).

const DEFAULT_ROSTER := "res://resources/encounters/knights.tres"

## Room sides, in cells (inclusive).
var min_room_size: int = 6
var max_room_size: int = 11
## Rooms on the main path, start and exit included.
var main_rooms: int = 6
## Side branches (1 or 2 rooms each) hung off main-path rooms.
var branches: int = 2
## Chance of one extra corridor between two rooms that line up (a loop).
var loop_chance: float = 0.5
## Corridor length and width, in cells.
var min_corridor: int = 3
var max_corridor: int = 7
var corridor_width: int = 2
## Empty cells kept between unconnected rooms and corridors (walls never merge).
var gap: int = 2
## Tries per room before giving up on it, and layouts before giving up.
var place_attempts: int = 40
var layout_attempts: int = 20
## Enemies to choose from (null = DEFAULT_ROSTER). Set `populate` false for a
## bare layout (no props, no enemies).
var roster: EnemyRoster
var populate: bool = true
## Role and side (cells; 0 = random like the others) of the last room on the
## main path. generate_boss() makes it a square "boss" arena.
var exit_role: String = "exit"
var exit_room_size: int = 0

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]

var _rng := RandomNumberGenerator.new()
var _rooms: Array[Dictionary] = []
var _corridors: Array[Dictionary] = []


## A layout for `level_seed`, populated for `level` (enemy budget). If a
## layout can't be completed (no room for the main path), the next derived
## seed is tried; `layout.seed` is `level_seed` either way, so it is
## reproducible. Returns null only after `layout_attempts` failures.
func generate(level_seed: int, level: int = 1) -> DungeonLayout:
	for attempt in layout_attempts:
		_rng.seed = hash([level_seed, attempt])
		if _try_layout():
			var layout := _to_layout(level_seed)
			layout.level = level
			if populate:
				PropScatter.new().populate(layout)
				EncounterPlanner.new().populate(layout, roster if roster else load(DEFAULT_ROSTER))
			return layout
	push_error("LevelGenerator: no layout for seed %d after %d attempts" % [level_seed, layout_attempts])
	return null


## A boss floor (step 6): a short approach of 1-2 rooms (no branches, no
## loop), then a square arena of `encounter.arena_size` holding the boss and
## its escorts, with the exit gate against the arena's far wall.
func generate_boss(level_seed: int, level: int, encounter: BossEncounter) -> DungeonLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([level_seed, "boss floor"])
	main_rooms = 2 + rng.randi_range(1, 2)
	branches = 0
	loop_chance = 0.0
	exit_role = "boss"
	exit_room_size = encounter.arena_size
	var layout := generate(level_seed, level)
	if layout and populate:
		EncounterPlanner.new().place_boss(layout, encounter, roster if roster else load(DEFAULT_ROSTER))
	return layout


func _try_layout() -> bool:
	_rooms.clear()
	_corridors.clear()
	_rooms.append({"rect": Rect2i(0, 0, _size(), _size()), "role": "start", "depth": 0, "parent": -1})
	for i in range(1, main_rooms):
		var role := exit_role if i == main_rooms - 1 else "path"
		if _attach(i - 1, role, i, true) < 0:
			return false
	# Side branches off the rooms between start and exit.
	if main_rooms > 2:
		for b in branches:
			var parent := _rng.randi_range(1, main_rooms - 2)
			var side := _attach(parent, "side", _rooms[parent]["depth"] + 1)
			if side >= 0 and _rng.randf() < 0.5:
				_attach(side, "side", _rooms[side]["depth"] + 1)
	if _rng.randf() < loop_chance:
		_add_loop()
	return true


## Adds a room joined to room `parent` by a straight corridor. Returns its
## index, or -1 when no placement fits. With `outward`, the first half of the
## tries only accept rooms further from the start than `parent` (so the main
## path heads somewhere instead of curling back on itself).
func _attach(parent: int, role: String, depth: int, outward: bool = false) -> int:
	var p: Rect2i = _rooms[parent]["rect"]
	var w := corridor_width
	var origin := _centre(_rooms[0]["rect"])
	var parent_reach := _centre(p).distance_to(origin)
	for attempt in place_attempts:
		var dir: Vector2i = DIRECTIONS[_rng.randi_range(0, 3)]
		var size := Vector2i(_size(), _size())
		if role == exit_role and exit_room_size > 0:
			size = Vector2i(exit_room_size, exit_room_size)
		var length := _rng.randi_range(min_corridor, max_corridor)
		var corridor: Rect2i
		var room: Rect2i
		if dir.x != 0:
			if p.size.y < w + 2:
				continue
			# Keep a cell of wall between the corridor and the rooms' corners.
			var y := _rng.randi_range(p.position.y + 1, p.end.y - 1 - w)
			var x := p.end.x if dir.x > 0 else p.position.x - length
			corridor = Rect2i(x, y, length, w)
			var ry := _rng.randi_range(y + w + 1 - size.y, y - 1)
			var rx := corridor.end.x if dir.x > 0 else corridor.position.x - size.x
			room = Rect2i(rx, ry, size.x, size.y)
		else:
			if p.size.x < w + 2:
				continue
			var x := _rng.randi_range(p.position.x + 1, p.end.x - 1 - w)
			var y := p.end.y if dir.y > 0 else p.position.y - length
			corridor = Rect2i(x, y, w, length)
			var rx := _rng.randi_range(x + w + 1 - size.x, x - 1)
			var ry := corridor.end.y if dir.y > 0 else corridor.position.y - size.y
			room = Rect2i(rx, ry, size.x, size.y)
		if outward and attempt < place_attempts / 2 				and _centre(room).distance_to(origin) <= parent_reach:
			continue
		if not _is_free(room, []) or not _is_free(corridor, [parent]):
			continue
		_rooms.append({"rect": room, "role": role, "depth": depth, "parent": parent})
		var index := _rooms.size() - 1
		_corridors.append({"rect": corridor, "from": parent, "to": index, "horizontal": dir.x != 0})
		return index
	return -1


## One extra straight corridor between two rooms that face each other across
## a short gap, if any pair does.
func _add_loop() -> void:
	var w := corridor_width
	var pairs := []
	for i in _rooms.size():
		for j in range(i + 1, _rooms.size()):
			if _connected(i, j):
				continue
			pairs.append([i, j])
	pairs = _shuffled(pairs)  # Never the global RNG: the seed must decide.
	for pair: Array in pairs:
		var a: Rect2i = _rooms[pair[0]]["rect"]
		var b: Rect2i = _rooms[pair[1]]["rect"]
		for horizontal in [true, false]:
			var corridor := _bridge(a, b, horizontal, w)
			if corridor.size == Vector2i.ZERO or not _is_free(corridor, [pair[0], pair[1]]):
				continue
			_corridors.append({"rect": corridor, "from": pair[0], "to": pair[1], "horizontal": horizontal})
			return


## The straight corridor between rooms a and b along x (horizontal) or y, or
## an empty rect when they don't face each other closely enough.
func _bridge(a: Rect2i, b: Rect2i, horizontal: bool, w: int) -> Rect2i:
	var axis := 0 if horizontal else 1
	var across := 1 - axis
	var left := a if a.position[axis] < b.position[axis] else b
	var right := b if left == a else a
	var span := right.position[axis] - left.end[axis]
	if span < min_corridor or span > max_corridor + 3:
		return Rect2i()
	var lo := maxi(left.position[across], right.position[across]) + 1
	var hi := mini(left.end[across], right.end[across]) - 1 - w
	if hi < lo:
		return Rect2i()
	var at := _rng.randi_range(lo, hi)
	if horizontal:
		return Rect2i(left.end.x, at, span, w)
	return Rect2i(at, left.end.y, w, span)


func _connected(i: int, j: int) -> bool:
	for c in _corridors:
		if (c["from"] == i and c["to"] == j) or (c["from"] == j and c["to"] == i):
			return true
	return false


## True when `rect`, grown by `gap`, overlaps no room or corridor except the
## rooms listed in `allowed` (the ones it connects to).
func _is_free(rect: Rect2i, allowed: Array) -> bool:
	var grown := rect.grow(gap)
	for i in _rooms.size():
		if i in allowed:
			continue
		if grown.intersects(_rooms[i]["rect"]):
			return false
	for c in _corridors:
		if grown.intersects(c["rect"]):
			return false
	return true


func _size() -> int:
	return _rng.randi_range(min_room_size, max_room_size)


func _shuffled(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


func _to_layout(level_seed: int) -> DungeonLayout:
	var layout := DungeonLayout.new()
	layout.seed = level_seed
	var cells := {}
	for room in _rooms:
		_fill(cells, room["rect"])
	for c in _corridors:
		_fill(cells, c["rect"])
	layout.set_floor_cells(cells)
	# Door frames where each corridor meets a room.
	for c in _corridors:
		var r: Rect2i = c["rect"]
		if c["horizontal"]:
			for x in [r.position.x, r.end.x]:
				layout.doors.append(_door(Vector2(x - 0.1, r.position.y), Vector2(x + 0.1, r.end.y)))
		else:
			for y in [r.position.y, r.end.y]:
				layout.doors.append(_door(Vector2(r.position.x, y - 0.1), Vector2(r.end.x, y + 0.1)))
	layout.rooms.assign(_rooms.duplicate(true))
	for room in layout.rooms:
		var r: Rect2i = room["rect"]
		var room_cells: Array[Vector2i] = []
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				room_cells.append(Vector2i(x, y))
		room["cells"] = room_cells
	layout.corridors.assign(_corridors.duplicate(true))
	layout.labels.append(["Start", _centre(_rooms[0]["rect"])])
	layout.labels.append(["Exit", _exit_point()])
	layout.centre_origin()
	return layout


## The gate's spot: the exit room's centre, or in a boss arena 2.5 cells
## from the wall opposite the way in (the fight happens in front of it).
func _exit_point() -> Vector2:
	var index := main_rooms - 1
	var rect: Rect2i = _rooms[index]["rect"]
	var centre := _centre(rect)
	if exit_role != "boss":
		return centre
	for c in _corridors:
		if c["to"] == index:
			var way_in := centre - _centre(c["rect"])
			var axis := Vector2(signf(way_in.x), 0) if c["horizontal"] else Vector2(0, signf(way_in.y))
			var half := (rect.size.x if c["horizontal"] else rect.size.y) * 0.5
			return centre + axis * (half - 2.5)
	return centre


static func _centre(rect: Rect2i) -> Vector2:
	return Vector2(rect.position) + Vector2(rect.size) * 0.5


static func _fill(cells: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells[Vector2i(x, y)] = true


static func _door(lo: Vector2, hi: Vector2) -> PackedVector2Array:
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
